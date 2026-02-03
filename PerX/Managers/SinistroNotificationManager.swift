import Foundation
import SwiftUI
import Combine
import CoreData

/// Gestisce le notifiche per sezione di ogni sinistro (diario, cartella, etc.)
/// Le notifiche vengono azzerate quando l'utente visita la sezione corrispondente.
@MainActor
final class SinistroNotificationManager: ObservableObject {
    static let shared = SinistroNotificationManager()
    
    /// Sezioni disponibili per le notifiche
    enum Section: String, CaseIterable {
        case dettagli = "Dettagli"
        case diario = "Diario"
        case fulminazione = "Fulminazione"
        case cartella = "Cartella"
        case perizia = "Perizia"
    }
    
    /// Struttura per tracciare le notifiche di un sinistro
    struct SinistroNotifications: Codable {
        var diario: Int = 0
        var cartella: Int = 0
        var dettagli: Int = 0
        var fulminazione: Int = 0
        var perizia: Int = 0
        
        var total: Int {
            diario + cartella + dettagli + fulminazione + perizia
        }
        
        mutating func increment(section: Section, by count: Int = 1) {
            switch section {
            case .dettagli: dettagli += count
            case .diario: diario += count
            case .fulminazione: fulminazione += count
            case .cartella: cartella += count
            case .perizia: perizia += count
            }
        }
        
        mutating func clear(section: Section) {
            switch section {
            case .dettagli: dettagli = 0
            case .diario: diario = 0
            case .fulminazione: fulminazione = 0
            case .cartella: cartella = 0
            case .perizia: perizia = 0
            }
        }
        
        func count(for section: Section) -> Int {
            switch section {
            case .dettagli: return dettagli
            case .diario: return diario
            case .fulminazione: return fulminazione
            case .cartella: return cartella
            case .perizia: return perizia
            }
        }
    }
    
    /// Mappa riferimento -> notifiche per sezione
    @Published private(set) var notifications: [String: SinistroNotifications] = [:]
    
    private let storageKey = "sinistroNotifications"
    
    private init() {
        loadFromStorage()
        setupObservers()
    }
    
    // MARK: - Public API
    
    /// Aggiunge una notifica per una sezione di un sinistro
    func addNotification(riferimento: String, section: Section, count: Int = 1) {
        var current = notifications[riferimento] ?? SinistroNotifications()
        current.increment(section: section, by: count)
        notifications[riferimento] = current
        saveToStorage()
        
        print("[Notifications] ➕ \(riferimento): +\(count) notifica per \(section.rawValue)")
    }
    
    /// Azzera le notifiche di una sezione quando l'utente la visita
    func clearNotifications(riferimento: String, section: Section) {
        guard var current = notifications[riferimento] else { return }
        let previousCount = current.count(for: section)
        guard previousCount > 0 else { return }
        
        current.clear(section: section)
        notifications[riferimento] = current
        saveToStorage()
        
        print("[Notifications] ✓ \(riferimento): azzerata sezione \(section.rawValue) (era \(previousCount))")
    }
    
    /// Ottiene il conteggio notifiche per una sezione
    func getCount(riferimento: String, section: Section) -> Int {
        notifications[riferimento]?.count(for: section) ?? 0
    }
    
    /// Ottiene il conteggio totale per un sinistro
    func getTotalCount(riferimento: String) -> Int {
        notifications[riferimento]?.total ?? 0
    }
    
    /// Ottiene tutti i riferimenti con almeno una notifica (per ottimizzazione iterazioni)
    func getAllRiferimentiWithNotifications() -> Set<String> {
        Set(notifications.filter { $0.value.total > 0 }.keys)
    }
    
    /// Converte il nome tab in Section
    func section(fromTabName tab: String) -> Section? {
        Section(rawValue: tab)
    }
    
    // MARK: - Storage
    
    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: SinistroNotifications].self, from: data) else {
            return
        }
        notifications = decoded
    }
    
    private func saveToStorage() {
        guard let data = try? JSONEncoder().encode(notifications) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    // MARK: - Observers
    
    private func setupObservers() {
        // Osserva quando viene aggiunta una nota diario da altri utenti
        NotificationCenter.default.addObserver(
            forName: .diarioEntryAdded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let riferimento = notification.userInfo?["riferimento"] as? String,
                  let fromOtherUser = notification.userInfo?["fromOtherUser"] as? Bool,
                  fromOtherUser else { return }
            
            Task { @MainActor in
                // Verifica se il sinistro è assegnato all'utente corrente
                guard self.isSinistroAssignedToCurrentUser(riferimento: riferimento) else {
                    print("[Notifications] ⏭️ Sinistro \(riferimento) non assegnato all'utente, skip notifica diario")
                    return
                }
                self.addNotification(riferimento: riferimento, section: .diario)
            }
        }
        
        // Osserva quando arrivano nuovi file dalla sincronizzazione
        NotificationCenter.default.addObserver(
            forName: .newFilesDownloaded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let riferimento = notification.userInfo?["riferimento"] as? String,
                  let count = notification.userInfo?["count"] as? Int,
                  count > 0 else { return }
            
            Task { @MainActor in
                // Verifica se il sinistro è assegnato all'utente corrente
                guard self.isSinistroAssignedToCurrentUser(riferimento: riferimento) else {
                    print("[Notifications] ⏭️ Sinistro \(riferimento) non assegnato all'utente, skip notifica cartella")
                    return
                }
                
                // Filtra ulteriormente i file se presenti nella notifica (extra safety)
                var finalCount = count
                if let files = notification.userInfo?["files"] as? [String] {
                    let filtered = files.filter { !self.isNotificationExcluded(path: $0) }
                    finalCount = filtered.count
                    
                    if finalCount == 0 && count > 0 {
                        print("[Notifications] ⏭️ Tutti i \(count) file sono esclusi (generati/utente), skip badge per \(riferimento)")
                        return
                    }
                }
                
                self.addNotification(riferimento: riferimento, section: .cartella, count: finalCount)
            }
        }
    }
    
    /// Determina se un file deve essere escluso dalle notifiche (file generati o caricati dall'utente)
    private func isNotificationExcluded(path: String) -> Bool {
        let filename = (path as NSString).lastPathComponent.lowercased()
        let pathLower = path.lowercased().replacingOccurrences(of: "\\", with: "/")
        
        // 1. Cartella "Da Chiudere" (file di chiusura generati)
        if pathLower.contains("/da chiudere/") || pathLower.hasPrefix("da chiudere/") {
            return true
        }
        
        // 2. Pattern nomi file generati (Atto, Perizia, Verbale)
        let generatedPatterns = [
            "atto da firmare", "atto_da_firmare",
            "atto da inviare", "atto_da_inviare",
            "atto firmato", "atto_firmato",
            "chiusura", "perizia_", "verbale_",
            "file_unificati_", "messaggi.txt"
        ]
        
        for pattern in generatedPatterns {
            if filename.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Assignment Check
    
    /// Verifica se un sinistro è assegnato all'utente corrente
    private func isSinistroAssignedToCurrentUser(riferimento: String) -> Bool {
        guard let currentUserEmail = AppState.shared.googleAuthService.userEmail?.lowercased(),
              !currentUserEmail.isEmpty else {
            return false
        }
        
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        
        guard let sinistro = try? context.fetch(request).first else {
            return false
        }
        
        let assignedEmail = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail ?? "").lowercased()
        return assignedEmail == currentUserEmail && !assignedEmail.isEmpty
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Emessa quando viene aggiunta una nota diario
    static let diarioEntryAdded = Notification.Name("diarioEntryAdded")
    /// Emessa quando vengono scaricati nuovi file dalla sincronizzazione
    static let newFilesDownloaded = Notification.Name("newFilesDownloaded")
}
