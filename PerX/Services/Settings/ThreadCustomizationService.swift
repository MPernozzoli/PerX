import Foundation
import CoreData

/// Servizio per gestire thread personalizzati ed esclusioni email
class ThreadCustomizationService {
    static let shared = ThreadCustomizationService()
    
    private let userDefaults = UserDefaults.standard
    private let customThreadsKey = "customThreads"
    private let excludedEmailsKey = "excludedEmails"
    
    private init() {}
    
    // MARK: - Custom Threads
    
    /// Crea o aggiorna un thread personalizzato
    func createOrUpdateCustomThread(threadId: UUID, name: String, context: NSManagedObjectContext) {
        var customThreads = getCustomThreads()
        customThreads[threadId.uuidString] = name
        userDefaults.set(customThreads, forKey: customThreadsKey)
        
        // Se il thread esiste già, aggiornalo
        let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        request.predicate = NSPredicate(format: "id == %@", threadId as CVarArg)
        
        if let thread = try? context.fetch(request).first {
            // Il thread esiste già, non serve crearlo
        } else {
            // Crea nuovo thread personalizzato
            let thread = SinistroEmailThread(context: context)
            thread.id = threadId
            thread.sinistro = nil
            thread.messageIds = []
            thread.dataCreazione = Date()
            thread.dataUltimaModifica = Date()
            
            do {
                try context.save()
            } catch {
                print("[ThreadCustomizationService] ❌ Errore creazione thread: \(error)")
            }
        }
    }
    
    /// Ottiene il nome personalizzato di un thread
    func getCustomThreadName(threadId: UUID) -> String? {
        let customThreads = getCustomThreads()
        return customThreads[threadId.uuidString]
    }
    
    /// Rimuove un thread personalizzato
    func removeCustomThread(threadId: UUID, context: NSManagedObjectContext) {
        var customThreads = getCustomThreads()
        customThreads.removeValue(forKey: threadId.uuidString)
        userDefaults.set(customThreads, forKey: customThreadsKey)
        
        // Rimuovi il thread da Core Data
        let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        request.predicate = NSPredicate(format: "id == %@", threadId as CVarArg)
        
        if let thread = try? context.fetch(request).first {
            context.delete(thread)
            try? context.save()
        }
    }
    
    /// Verifica se un thread è personalizzato
    func isCustomThread(threadId: UUID) -> Bool {
        return getCustomThreadName(threadId: threadId) != nil
    }
    
    private func getCustomThreads() -> [String: String] {
        return userDefaults.dictionary(forKey: customThreadsKey) as? [String: String] ?? [:]
    }
    
    // MARK: - Excluded Emails
    
    /// Esclude un'email da tutti i thread
    func excludeEmail(emailId: String) {
        var excluded = getExcludedEmails()
        if !excluded.contains(emailId) {
            excluded.append(emailId)
            userDefaults.set(excluded, forKey: excludedEmailsKey)
        }
    }
    
    /// Rimuove l'esclusione di un'email
    func includeEmail(emailId: String) {
        var excluded = getExcludedEmails()
        excluded.removeAll { $0 == emailId }
        userDefaults.set(excluded, forKey: excludedEmailsKey)
    }
    
    /// Verifica se un'email è esclusa
    func isEmailExcluded(emailId: String) -> Bool {
        return getExcludedEmails().contains(emailId)
    }
    
    private func getExcludedEmails() -> [String] {
        return userDefaults.stringArray(forKey: excludedEmailsKey) ?? []
    }
    
    // MARK: - Thread Management
    
    /// Aggiunge un'email a un thread personalizzato
    func addEmailToCustomThread(emailId: String, threadId: UUID, context: NSManagedObjectContext) {
        let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        request.predicate = NSPredicate(format: "id == %@", threadId as CVarArg)
        
        if let thread = try? context.fetch(request).first {
            thread.addEmailMessageId(emailId)
            thread.dataUltimaModifica = Date()
            try? context.save()
        }
    }
    
    /// Rimuove un'email da un thread personalizzato
    func removeEmailFromCustomThread(emailId: String, threadId: UUID, context: NSManagedObjectContext) {
        let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        request.predicate = NSPredicate(format: "id == %@", threadId as CVarArg)
        
        if let thread = try? context.fetch(request).first {
            thread.removeEmailMessageId(emailId)
            thread.dataUltimaModifica = Date()
            try? context.save()
        }
    }
}

