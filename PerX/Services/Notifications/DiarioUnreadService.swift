import Foundation

/// Servizio per tracciare le entry del Diario non lette dall'owner.
/// Memorizza per ogni utente/sinistro il timestamp dell'ultima visualizzazione,
/// e calcola quante entry "esterne" (create da altri) sono successive.
@MainActor
final class DiarioUnreadService: ObservableObject {
    static let shared = DiarioUnreadService()
    
    /// Trigger per forzare aggiornamento UI quando cambiano i dati
    @Published private(set) var updateTrigger: Int = 0
    
    private let defaults = UserDefaults.standard
    private let lastSeenKeyPrefix = "diario.lastSeen"
    
    private init() {}
    
    // MARK: - Public API
    
    /// Restituisce il numero di entry non lette per un sinistro dall'utente corrente.
    /// Considera "non lette" le entry create da altri (createdByEmail != currentUserEmail)
    /// con timestamp successivo all'ultima visualizzazione.
    /// Esclude entry che hanno già generato una task (generatedTaskId != nil).
    func unreadCount(for sinistro: Sinistro, currentUserEmail: String) -> Int {
        guard let riferimento = sinistro.riferimento, !riferimento.isEmpty else { return 0 }
        
        let lastSeen = loadLastSeen(riferimento: riferimento, userEmail: currentUserEmail)
        let entries = sinistro.diarioArray
        
        // Conta entry create da altri (o senza autore per retrocompatibilita) con timestamp > lastSeen
        // Esclude entry con task già generata (l'utente le vede tramite la task)
        let unread = entries.filter { entry in
            guard entry.timestamp > lastSeen else { return false }
            guard entry.generatedTaskId == nil else { return false } // Ha già una task, skip
            guard let creator = entry.createdByEmail?.lowercased() else {
                return true // Entry legacy senza autore = tratta come "altri"
            }
            return creator != currentUserEmail.lowercased()
        }
        
        return unread.count
    }
    
    /// Segna come "viste" tutte le entry di un sinistro per l'utente corrente.
    func markSeen(sinistroRiferimento: String, currentUserEmail: String, seenAt: Date = Date()) {
        guard !sinistroRiferimento.isEmpty, !currentUserEmail.isEmpty else { return }
        saveLastSeen(riferimento: sinistroRiferimento, userEmail: currentUserEmail, date: seenAt)
        updateTrigger += 1 // Notifica SwiftUI del cambiamento
    }
    
    /// Restituisce l'ultimo timestamp di visualizzazione del Diario per un sinistro/utente.
    func lastSeenDate(riferimento: String, userEmail: String) -> Date {
        loadLastSeen(riferimento: riferimento, userEmail: userEmail)
    }
    
    /// Restituisce i riferimenti sinistri con potenziali entry non lette.
    /// Nota: questo metodo scansiona UserDefaults per chiavi salvate - potrebbe non essere completo
    /// per sinistri mai visitati ma con entry da altri.
    func getRiferimentiWithUnread(currentUserEmail: String) -> Set<String> {
        // Ritorna un set vuoto - questo metodo è usato solo come ottimizzazione.
        // Il calcolo effettivo avviene quando necessario tramite unreadCount().
        // Per una vera implementazione, si dovrebbe mantenere un indice separato.
        return []
    }
    
    // MARK: - Private Storage
    
    private func storageKey(riferimento: String, userEmail: String) -> String {
        let normalizedEmail = userEmail.lowercased().replacingOccurrences(of: "@", with: "_at_").replacingOccurrences(of: ".", with: "_")
        return "\(lastSeenKeyPrefix).\(normalizedEmail).\(riferimento)"
    }
    
    private func loadLastSeen(riferimento: String, userEmail: String) -> Date {
        let key = storageKey(riferimento: riferimento, userEmail: userEmail)
        let timestamp = defaults.double(forKey: key)
        guard timestamp > 0 else { return .distantPast }
        return Date(timeIntervalSince1970: timestamp)
    }
    
    private func saveLastSeen(riferimento: String, userEmail: String, date: Date) {
        let key = storageKey(riferimento: riferimento, userEmail: userEmail)
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }
}
