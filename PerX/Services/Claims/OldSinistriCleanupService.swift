import Foundation
import CoreData

/// Servizio per rimuovere sinistri vecchi (non recenti) senza data chiusura
@MainActor
final class OldSinistriCleanupService {
    static let shared = OldSinistriCleanupService()
    
    private let defaults = UserDefaults.standard
    private let cleanupKey = "oldSinistriCleanup_v1_done"
    private let lastWeeklyCleanupKey = "lastWeeklyOldSinistriCleanup"
    
    private init() {}
    
    /// Verifica se la pulizia è abilitata
    var isEnabled: Bool {
        get {
            defaults.object(forKey: "rimuoviSinistriVecchiSenzaChiusura") == nil ? true : defaults.bool(forKey: "rimuoviSinistriVecchiSenzaChiusura")
        }
        set {
            defaults.set(newValue, forKey: "rimuoviSinistriVecchiSenzaChiusura")
        }
    }
    
    /// Esegue la pulizia se necessario (all'avvio)
    func runIfNeeded(context: NSManagedObjectContext) {
        guard isEnabled else {
            print("[OldSinistriCleanup] ⏭️ Pulizia sinistri vecchi disabilitata")
            return
        }
        
        guard defaults.bool(forKey: cleanupKey) == false else {
            // Già eseguita al primo avvio, controlla se è passata una settimana
            checkWeeklyCleanup(context: context)
            return
        }
        
        print("[OldSinistriCleanup] 🔍 Avvio pulizia sinistri vecchi senza data chiusura...")
        performCleanup(context: context)
        defaults.set(true, forKey: cleanupKey)
    }
    
    /// Controlla se è necessario eseguire la pulizia settimanale
    private func checkWeeklyCleanup(context: NSManagedObjectContext) {
        guard let lastCleanupString = defaults.string(forKey: lastWeeklyCleanupKey),
              let lastCleanup = ISO8601DateFormatter().date(from: lastCleanupString) else {
            // Prima esecuzione settimanale
            performCleanup(context: context)
            return
        }
        
        let daysSinceLastCleanup = Calendar.current.dateComponents([.day], from: lastCleanup, to: Date()).day ?? 0
        
        if daysSinceLastCleanup >= 7 {
            print("[OldSinistriCleanup] 📅 Esecuzione pulizia settimanale (ultima: \(daysSinceLastCleanup) giorni fa)")
            performCleanup(context: context)
        }
    }
    
    /// Esegue manualmente la pulizia
    func runManualCleanup(context: NSManagedObjectContext) -> CleanupResult {
        guard isEnabled else {
            return CleanupResult(removed: 0, skipped: 0, errors: ["Pulizia disabilitata nelle impostazioni"])
        }
        
        return performCleanup(context: context)
    }
    
    /// Esegue la pulizia dei sinistri vecchi senza data chiusura
    @discardableResult
    private func performCleanup(context: NSManagedObjectContext) -> CleanupResult {
        guard isEnabled else {
            return CleanupResult(removed: 0, skipped: 0, errors: [])
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento != nil")
        
        do {
            let allSinistri = try context.fetch(request)
            var removed = 0
            var skipped = 0
            var errors: [String] = []
            
            let currentYear = Calendar.current.component(.year, from: Date())
            let previousYear = currentYear - 1
            
            for sinistro in allSinistri {
                guard let riferimento = sinistro.riferimento, !riferimento.isEmpty else {
                    continue
                }
                
                // Estrai anno dal riferimento
                guard let year = RiferimentoValidator.extractYear(from: riferimento) else {
                    continue
                }
                
                // Verifica se è vecchio (non recente)
                let isRecent = (year == currentYear || year == previousYear)
                
                if !isRecent {
                    // Sinistro vecchio: verifica se ha data chiusura
                    if sinistro.dataChiusura == nil {
                        // Rimuovi sinistro vecchio senza data chiusura
                        print("[OldSinistriCleanup] 🗑️ Rimozione sinistro \(riferimento) (anno \(year), senza data chiusura)")
                        context.delete(sinistro)
                        removed += 1
                    } else {
                        // Mantieni sinistro vecchio con data chiusura
                        print("[OldSinistriCleanup] ✅ Mantenuto sinistro \(riferimento) (anno \(year), con data chiusura)")
                        skipped += 1
                    }
                }
            }
            
            if context.hasChanges {
                try context.save()
            }
            
            // Aggiorna data ultima pulizia settimanale
            defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: lastWeeklyCleanupKey)
            
            let result = CleanupResult(removed: removed, skipped: skipped, errors: errors)
            print("[OldSinistriCleanup] ✅ Pulizia completata: \(removed) rimossi, \(skipped) mantenuti (con data chiusura)")
            return result
            
        } catch {
            print("[OldSinistriCleanup] ❌ Errore durante la pulizia: \(error)")
            return CleanupResult(removed: 0, skipped: 0, errors: [error.localizedDescription])
        }
    }
    
    struct CleanupResult {
        let removed: Int
        let skipped: Int
        let errors: [String]
    }
}
