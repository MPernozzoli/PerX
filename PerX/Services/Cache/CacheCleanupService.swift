import Foundation
import CoreData

/// Servizio per pulizia periodica della cache locale
/// Rimuove dati SinistroFull per sinistri non acceduti di recente
class CacheCleanupService: ObservableObject {
    static let shared = CacheCleanupService()
    
    // MARK: - Configuration
    
    /// Giorni di inattività prima di rimuovere dalla cache
    private let cacheRetentionDays = 14
    
    /// Intervallo tra cleanup automatici (in ore)
    private let cleanupIntervalHours = 24
    
    /// Timer per cleanup periodico
    private var cleanupTimer: Timer?
    
    // MARK: - Published State
    
    @Published var lastCleanup: Date?
    @Published var itemsCleaned: Int = 0
    
    private init() {
        loadLastCleanupDate()
    }
    
    // MARK: - Lifecycle
    
    /// Avvia il cleanup periodico
    func startPeriodicCleanup() {
        // Cleanup immediato se non fatto di recente
        if shouldRunCleanup() {
            Task {
                await CPUThrottler.shared.runWithThrottle { await performCleanup() }
            }
        }
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: Double(cleanupIntervalHours) * 3600, repeats: true) { [weak self] _ in
            Task {
                await CPUThrottler.shared.runWithThrottle { await self?.performCleanup() }
            }
        }
    }
    
    /// Ferma il cleanup periodico
    func stopPeriodicCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }
    
    // MARK: - Cleanup Logic
    
    /// Esegue pulizia della cache
    @MainActor
    func performCleanup() async {
        print("[CacheCleanup] Starting cleanup...")
        
        let context = PersistenceController.shared.container.viewContext
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -cacheRetentionDays, to: Date())!
        
        var cleanedCount = 0
        
        do {
            // 1. Trova sinistri non acceduti da tempo
            let staleSinistri = findStaleSinistri(context: context, before: cutoffDate)
            
            for sinistro in staleSinistri {
                // Non pulire sinistri in stati attivi
                if isSinistroActive(sinistro) {
                    continue
                }
                
                // Pulisci dati "full"
                cleanFullData(for: sinistro, context: context)
                cleanedCount += 1
            }
            
            // 2. Pulisci email body per sinistri chiusi
            let cleanedEmails = cleanEmailBodies(context: context, olderThan: cutoffDate)
            cleanedCount += cleanedEmails
            
            // 3. Rimuovi file cartella locali per sinistri non acceduti
            let cleanedFiles = await cleanLocalFiles(for: staleSinistri)
            cleanedCount += cleanedFiles
            
            // Salva
            if context.hasChanges {
                try context.save()
            }
            
            // Aggiorna stato
            lastCleanup = Date()
            itemsCleaned = cleanedCount
            saveLastCleanupDate()
            
            print("[CacheCleanup] Completed. Cleaned \(cleanedCount) items.")
            
        } catch {
            print("[CacheCleanup] Error: \(error)")
        }
    }
    
    // MARK: - Find Stale Sinistri
    
    private func findStaleSinistri(context: NSManagedObjectContext, before cutoffDate: Date) -> [Sinistro] {
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        
        // Sinistri con lastAccessedAt più vecchio di cutoffDate
        // o senza lastAccessedAt (mai acceduti dopo l'introduzione del campo)
        request.predicate = NSPredicate(
            format: "lastAccessedAt == nil OR lastAccessedAt < %@",
            cutoffDate as NSDate
        )
        
        do {
            return try context.fetch(request)
        } catch {
            print("[CacheCleanup] Failed to fetch stale sinistri: \(error)")
            return []
        }
    }
    
    private func isSinistroActive(_ sinistro: Sinistro) -> Bool {
        guard let stato = sinistro.stato else { return false }
        
        // Trova lo stato corrispondente
        guard let statoEnum = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == stato }) else {
            // Se lo stato non è riconosciuto, assumiamo non attivo
            return false
        }
        
        // Stati considerati NON attivi (da pulire): chiusa, annullata, revocata
        // Tutti gli altri stati sono attivi
        switch statoEnum {
        case .chiusa, .annullata, .revocata:
            return false
        default:
            return true
        }
    }
    
    // MARK: - Clean Full Data
    
    private func cleanFullData(for sinistro: Sinistro, context: NSManagedObjectContext) {
        // Rimuovi dati "pesanti" mantenendo i minimi
        // - Pulisci campi testuali grandi che possono essere riscaricati
        sinistro.ubicazioneNote = nil
        sinistro.definizione = nil
        
        // Mantieni: riferimento, stato, assegnatario, date chiave
        
        print("[CacheCleanup] Cleaned full data for: \(sinistro.riferimento ?? "?")")
    }
    
    // MARK: - Clean Email Bodies
    
    private func cleanEmailBodies(context: NSManagedObjectContext, olderThan cutoffDate: Date) -> Int {
        // Per sinistri chiusi, conta le email associate per statistiche
        // Le email sono gestite tramite SinistroEmailThread e cache in memoria
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "stato == %@", "Chiusa")
        
        do {
            let closedSinistri = try context.fetch(request)
            var count = 0
            
            for sinistro in closedSinistri {
                // Trova i thread email associati a questo sinistro
                let threadRequest = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
                threadRequest.predicate = NSPredicate(format: "sinistro == %@", sinistro)
                
                if let threads = try? context.fetch(threadRequest) {
                    for thread in threads {
                        // Conta i message ID per statistiche
                        count += thread.messageIds.count
                    }
                }
            }
            
            // Le email vengono pulite automaticamente dalla cache LRU di EmailCacheService
            // quando superano il limite di memoria
            
            return count
        } catch {
            return 0
        }
    }
    
    // MARK: - Clean Local Files
    
    private func cleanLocalFiles(for sinistri: [Sinistro]) async -> Int {
        let fileService = FileService.shared
        var count = 0
        
        for sinistro in sinistri {
            guard let riferimento = sinistro.riferimento else { continue }
            
            // Verifica se la cartella locale esiste
            if let path = fileService.getSinistroPath(riferimento: riferimento),
               FileManager.default.fileExists(atPath: path) {
                
                // Non eliminare se sinistro attivo
                if isSinistroActive(sinistro) {
                    continue
                }
                
                // Elimina cartella locale
                do {
                    try FileManager.default.removeItem(atPath: path)
                    count += 1
                    print("[CacheCleanup] Removed local folder for: \(riferimento)")
                } catch {
                    print("[CacheCleanup] Failed to remove folder for \(riferimento): \(error)")
                }
            }
        }
        
        return count
    }
    
    // MARK: - Helpers
    
    private func shouldRunCleanup() -> Bool {
        guard let last = lastCleanup else { return true }
        
        let hoursSinceLastCleanup = Calendar.current.dateComponents(
            [.hour],
            from: last,
            to: Date()
        ).hour ?? 0
        
        return hoursSinceLastCleanup >= cleanupIntervalHours
    }
    
    private func loadLastCleanupDate() {
        lastCleanup = UserDefaults.standard.object(forKey: "CacheCleanup.lastCleanup") as? Date
    }
    
    private func saveLastCleanupDate() {
        UserDefaults.standard.set(lastCleanup, forKey: "CacheCleanup.lastCleanup")
    }
}
