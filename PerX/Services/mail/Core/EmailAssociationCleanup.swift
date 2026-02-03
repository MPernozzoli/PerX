import Foundation
import CoreData

/// Servizio per cancellare tutte le associazioni email-sinistro esistenti
/// Utile per rigenerare le associazioni da zero
@MainActor
class EmailAssociationCleanup {
    static let shared = EmailAssociationCleanup()
    
    private init() {}
    
    /// Cancella tutte le associazioni email-sinistro esistenti
    /// - Parameter context: Contesto Core Data
    /// - Returns: Numero di thread cancellati
    func clearAllAssociations(context: NSManagedObjectContext) async -> Int {
        let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        
        guard let threads = try? context.fetch(request) else {
            print("[EmailAssociationCleanup] ⚠️ Errore nel fetch dei thread")
            return 0
        }
        
        let count = threads.count
        
        for thread in threads {
            context.delete(thread)
        }
        
        do {
            try context.save()
            print("[EmailAssociationCleanup] ✅ Cancellati \(count) thread email-sinistro")
            return count
        } catch {
            print("[EmailAssociationCleanup] ❌ Errore nel salvataggio: \(error)")
            return 0
        }
    }
    
    /// Cancella le associazioni per un sinistro specifico
    /// - Parameters:
    ///   - sinistro: Il sinistro per cui cancellare le associazioni
    ///   - context: Contesto Core Data
    /// - Returns: Numero di thread cancellati
    func clearAssociations(for sinistro: Sinistro, context: NSManagedObjectContext) async -> Int {
        let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        request.predicate = NSPredicate(format: "sinistro == %@", sinistro)
        
        guard let threads = try? context.fetch(request) else {
            print("[EmailAssociationCleanup] ⚠️ Errore nel fetch dei thread per sinistro")
            return 0
        }
        
        let count = threads.count
        
        for thread in threads {
            context.delete(thread)
        }
        
        do {
            try context.save()
            print("[EmailAssociationCleanup] ✅ Cancellati \(count) thread per sinistro \(sinistro.riferimento ?? "N/A")")
            return count
        } catch {
            print("[EmailAssociationCleanup] ❌ Errore nel salvataggio: \(error)")
            return 0
        }
    }
    
    /// Cancella le associazioni per un'email specifica
    /// - Parameters:
    ///   - emailId: ID dell'email
    ///   - context: Contesto Core Data
    /// - Returns: Numero di thread modificati (rimossa email dai thread)
    func clearAssociations(for emailId: String, context: NSManagedObjectContext) async -> Int {
        // Non possiamo usare CONTAINS su campi Transformable, quindi facciamo fetch e filtriamo in memoria
        let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        
        guard let allThreads = try? context.fetch(request) else {
            print("[EmailAssociationCleanup] ⚠️ Errore nel fetch dei thread per email")
            return 0
        }
        
        // Filtra in memoria usando messageIds
        let threads = allThreads.filter { $0.messageIds.contains(emailId) }
        
        var modified = 0
        
        for thread in threads {
            thread.removeEmailMessageId(emailId)
            modified += 1
            
            // Se il thread non ha più email, cancellalo
            if thread.messageIds.isEmpty {
                context.delete(thread)
            }
        }
        
        do {
            try context.save()
            print("[EmailAssociationCleanup] ✅ Rimossa email \(emailId) da \(modified) thread")
            return modified
        } catch {
            print("[EmailAssociationCleanup] ❌ Errore nel salvataggio: \(error)")
            return 0
        }
    }
    
    /// Rimuove le entry diario di tipo email per un sinistro specifico
    /// - Parameters:
    ///   - sinistro: Il sinistro per cui rimuovere le entry email
    ///   - context: Contesto Core Data
    /// - Returns: Numero di entry rimosse
    func clearEmailDiarioEntries(for sinistro: Sinistro, context: NSManagedObjectContext) async -> Int {
        let diarioArray = sinistro.diarioArray
        let emailEntries = diarioArray.filter { $0.tipo == .email }
        let count = emailEntries.count
        
        if count > 0 {
            let remainingEntries = diarioArray.filter { $0.tipo != .email }
            sinistro.diarioArray = remainingEntries
            
            do {
                try context.save()
                print("[EmailAssociationCleanup] ✅ Rimosse \(count) entry email dal diario del sinistro \(sinistro.riferimento ?? "N/A")")
                return count
            } catch {
                print("[EmailAssociationCleanup] ❌ Errore nel salvataggio: \(error)")
                return 0
            }
        }
        
        return 0
    }
    
    /// Rimuove tutte le entry diario di tipo email per tutti i sinistri
    /// - Parameter context: Contesto Core Data
    /// - Returns: Numero totale di entry rimosse
    func clearAllEmailDiarioEntries(context: NSManagedObjectContext) async -> Int {
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        
        guard let sinistri = try? context.fetch(request) else {
            print("[EmailAssociationCleanup] ⚠️ Errore nel fetch dei sinistri")
            return 0
        }
        
        var totalRemoved = 0
        
        for sinistro in sinistri {
            let removed = await clearEmailDiarioEntries(for: sinistro, context: context)
            totalRemoved += removed
        }
        
        print("[EmailAssociationCleanup] ✅ Rimosse \(totalRemoved) entry email dal diario di tutti i sinistri")
        return totalRemoved
    }
}

