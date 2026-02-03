import Foundation
import CoreData

/// Servizio per il backfill dei campi solleciti consolidati sui sinistri esistenti
/// Analizza il diario di ogni sinistro e popola:
/// - sollecitiRicevutiCount / dataUltimoSollecitoRicevuto / tipoMittenteSollecitoMax
/// - sollecitiInviatiCount / dataUltimoSollecitoInviato
@MainActor
class SollecitiBackfillService {
    static let shared = SollecitiBackfillService()
    
    // Versione incrementata per includere tipo mittente
    private let backfillCompletedKey = "SollecitiBackfillCompleted_v2"
    
    private init() {}
    
    /// Verifica se il backfill è già stato eseguito
    var isBackfillCompleted: Bool {
        return UserDefaults.standard.bool(forKey: backfillCompletedKey)
    }
    
    /// Esegue il backfill se non già completato
    func runBackfillIfNeeded() async {
        guard !isBackfillCompleted else {
            print("[SollecitiBackfill] ✅ Backfill già completato, skip")
            return
        }
        
        await runBackfill()
    }
    
    /// Forza l'esecuzione del backfill (per debug/testing)
    func forceBackfill() async {
        UserDefaults.standard.set(false, forKey: backfillCompletedKey)
        await runBackfill()
    }
    
    /// Esegue il backfill su tutti i sinistri
    private func runBackfill() async {
        print("[SollecitiBackfill] 🔄 Avvio backfill solleciti...")
        
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        
        // Processa tutti i sinistri non chiusi
        let excludedStates = [
            StatoManager.StatoSinistro.chiusa.descrizione,
            StatoManager.StatoSinistro.revocata.descrizione,
            StatoManager.StatoSinistro.annullata.descrizione
        ]
        request.predicate = NSPredicate(format: "NOT (stato IN %@)", excludedStates)
        
        do {
            let sinistri = try context.fetch(request)
            print("[SollecitiBackfill] 📊 Sinistri da processare: \(sinistri.count)")
            
            var updatedCount = 0
            
            for sinistro in sinistri {
                let (ricevuti, inviati) = extractRemindersFromDiario(sinistro: sinistro)
                
                // Aggiorna solo se ci sono solleciti o se i campi sono a 0 (per sicurezza)
                if ricevuti.count > 0 || inviati.count > 0 {
                    sinistro.sollecitiRicevutiCount = Int16(ricevuti.count)
                    sinistro.dataUltimoSollecitoRicevuto = ricevuti.first?.date
                    
                    // Trova il tipo mittente massimo tra tutti i solleciti ricevuti
                    let maxTipoMittente = ricevuti.map { $0.tipoMittente }.max(by: { $0.rawValue < $1.rawValue }) ?? .unknown
                    sinistro.tipoMittenteSollecitoMax = Int16(maxTipoMittente.rawValue)
                    
                    sinistro.sollecitiInviatiCount = Int16(inviati.count)
                    sinistro.dataUltimoSollecitoInviato = inviati.first?.date
                    
                    updatedCount += 1
                }
            }
            
            if updatedCount > 0 {
                try context.save()
                print("[SollecitiBackfill] ✅ Aggiornati \(updatedCount) sinistri con dati solleciti")
            } else {
                print("[SollecitiBackfill] ℹ️ Nessun sinistro da aggiornare")
            }
            
            // Segna backfill come completato
            UserDefaults.standard.set(true, forKey: backfillCompletedKey)
            print("[SollecitiBackfill] ✅ Backfill completato")
            
        } catch {
            print("[SollecitiBackfill] ❌ Errore: \(error.localizedDescription)")
        }
    }
    
    /// Estrae solleciti ricevuti e inviati dal diario di un sinistro
    private func extractRemindersFromDiario(sinistro: Sinistro) -> (ricevuti: [ReminderEntry], inviati: [ReminderEntry]) {
        var ricevuti: [ReminderEntry] = []
        var inviati: [ReminderEntry] = []
        
        let diarioEntries = sinistro.diarioArray
        
        for entry in diarioEntries {
            let titolo = entry.titolo?.lowercased() ?? ""
            let testo = entry.testo.lowercased()
            let combined = "\(titolo) \(testo)"
            
            let isSollecito = combined.contains("sollecit") || combined.contains("reminder")
            guard isSollecito else { continue }
            
            let isInviato = combined.contains("inviato") || combined.contains("inviata") || combined.contains("manualmente")
            let isRicevuto = combined.contains("ricevuto") || combined.contains("ricevuta") || combined.contains("da ")
            
            let date = entry.timestamp ?? Date()
            
            if isInviato {
                inviati.append(ReminderEntry(date: date, title: entry.titolo ?? "", tipoMittente: .unknown))
            } else if isRicevuto || !isInviato {
                // Determina tipo mittente dal testo
                let tipoMittente = TipoMittenteSollecito.fromText(combined)
                ricevuti.append(ReminderEntry(date: date, title: entry.titolo ?? "", tipoMittente: tipoMittente))
            }
        }
        
        // Ordina per data (più recenti prima)
        ricevuti.sort { $0.date > $1.date }
        inviati.sort { $0.date > $1.date }
        
        return (ricevuti, inviati)
    }
    
    /// Esegue backfill per un singolo sinistro (utile per update incrementali)
    func backfillSingleSinistro(_ sinistro: Sinistro) {
        let (ricevuti, inviati) = extractRemindersFromDiario(sinistro: sinistro)
        
        sinistro.sollecitiRicevutiCount = Int16(ricevuti.count)
        sinistro.dataUltimoSollecitoRicevuto = ricevuti.first?.date
        
        // Trova il tipo mittente massimo
        let maxTipoMittente = ricevuti.map { $0.tipoMittente }.max(by: { $0.rawValue < $1.rawValue }) ?? .unknown
        sinistro.tipoMittenteSollecitoMax = Int16(maxTipoMittente.rawValue)
        
        sinistro.sollecitiInviatiCount = Int16(inviati.count)
        sinistro.dataUltimoSollecitoInviato = inviati.first?.date
    }
}

// MARK: - Supporting Types

private struct ReminderEntry {
    let date: Date
    let title: String
    let tipoMittente: TipoMittenteSollecito
}
