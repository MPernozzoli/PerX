import Foundation
import CoreData

/// Servizio per validare e correggere le date di assegnazione errate
/// Esegue una validazione one-shot all'avvio per correggere date impostate male dalle email
@MainActor
final class AssignmentDateValidationService {
    static let shared = AssignmentDateValidationService()
    
    private let defaults = UserDefaults.standard
    private let validationKey = "assignmentDateValidation_v1_done"
    
    private init() {}
    
    /// Esegue la validazione se non è già stata eseguita
    func runIfNeeded(context: NSManagedObjectContext) {
        guard defaults.bool(forKey: validationKey) == false else {
            print("[AssignmentDateValidation] ✅ Validazione già eseguita")
            return
        }
        
        print("[AssignmentDateValidation] 🔍 Avvio validazione date assegnazione...")
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "dataAssegnazione != nil")
        
        do {
            let results = try context.fetch(request)
            guard !results.isEmpty else {
                defaults.set(true, forKey: validationKey)
                print("[AssignmentDateValidation] ✅ Nessun sinistro con data assegnazione trovato")
                return
            }
            
            var corrected = 0
            var invalidated = 0
            
            for sinistro in results {
                guard let dataAssegnazione = sinistro.dataAssegnazione else { continue }
                
                // Verifica vincoli: data assegnazione non può essere precedente a data incarico
                if let dataIncarico = sinistro.dataIncarico {
                    let calendar = Calendar.current
                    if dataAssegnazione < dataIncarico && !calendar.isDate(dataAssegnazione, inSameDayAs: dataIncarico) {
                        print("[AssignmentDateValidation] ⚠️ Sinistro \(sinistro.riferimento ?? "unknown"): data assegnazione (\(dataAssegnazione)) precedente a data incarico (\(dataIncarico))")
                        sinistro.setDataAssegnazione(nil)
                        invalidated += 1
                        continue
                    }
                }
                
                // Verifica vincoli: data assegnazione non può essere successiva a data invio atto
                if let dataInvioAtto = sinistro.dataInvioAtto {
                    let calendar = Calendar.current
                    if dataAssegnazione > dataInvioAtto && !calendar.isDate(dataAssegnazione, inSameDayAs: dataInvioAtto) {
                        print("[AssignmentDateValidation] ⚠️ Sinistro \(sinistro.riferimento ?? "unknown"): data assegnazione (\(dataAssegnazione)) successiva a data invio atto (\(dataInvioAtto))")
                        sinistro.setDataAssegnazione(nil)
                        invalidated += 1
                        continue
                    }
                }
                
                // Verifica vincoli: data assegnazione non può essere successiva a data chiusura
                if let dataChiusura = sinistro.dataChiusura {
                    let calendar = Calendar.current
                    if dataAssegnazione > dataChiusura && !calendar.isDate(dataAssegnazione, inSameDayAs: dataChiusura) {
                        print("[AssignmentDateValidation] ⚠️ Sinistro \(sinistro.riferimento ?? "unknown"): data assegnazione (\(dataAssegnazione)) successiva a data chiusura (\(dataChiusura))")
                        sinistro.setDataAssegnazione(nil)
                        invalidated += 1
                        continue
                    }
                }
                
                // Se passa tutti i controlli, valida anche le altre date
                sinistro.validateAllDates()
                corrected += 1
            }
            
            if context.hasChanges {
                try context.save()
            }
            
            defaults.set(true, forKey: validationKey)
            print("[AssignmentDateValidation] ✅ Validazione completata: \(corrected) date valide, \(invalidated) date invalidate")
        } catch {
            print("[AssignmentDateValidation] ❌ Errore validazione: \(error)")
        }
    }
}
