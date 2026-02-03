import Foundation
import CoreData

@objc(SinistroEmailThread)
public class SinistroEmailThread: NSManagedObject {
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var sinistro: Sinistro?
    @NSManaged private var emailMessageIds: NSArray?
    @NSManaged public var dataCreazione: Date
    @NSManaged public var dataUltimaModifica: Date
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        dataCreazione = Date()
        dataUltimaModifica = Date()
    }
    
    // Proprietà calcolata per accedere agli emailMessageIds come array di String
    public var messageIds: [String] {
        get {
            return emailMessageIds as? [String] ?? []
        }
        set {
            emailMessageIds = newValue as NSArray
        }
    }
}

// MARK: - Helper methods per gestire le email
extension SinistroEmailThread {
    func addEmailMessageId(_ messageId: String) {
        var ids = messageIds
        if !ids.contains(messageId) {
            ids.append(messageId)
            messageIds = ids
        }
    }
    
    func removeEmailMessageId(_ messageId: String) {
        var ids = messageIds
        ids.removeAll { $0 == messageId }
        messageIds = ids
    }
}

// MARK: - Identifiable & Computed Properties
extension SinistroEmailThread: Identifiable {
    
    // NOTA: I metodi per ottenere le email sono stati spostati nel PrincipaleViewModel
    // perché richiedono accesso a mailViewModel.emailsByMailbox che è isolato dal main actor
} 
