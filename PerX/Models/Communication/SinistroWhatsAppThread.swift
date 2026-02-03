import Foundation
import CoreData

@objc(SinistroWhatsAppThread)
public class SinistroWhatsAppThread: NSManagedObject {
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var sinistro: Sinistro?
    @NSManaged private var whatsAppChatIds: NSArray?
    @NSManaged public var dataCreazione: Date
    @NSManaged public var dataUltimaModifica: Date
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        dataCreazione = Date()
        dataUltimaModifica = Date()
    }
    
    // Proprietà calcolata per accedere ai whatsAppChatIds come array di String
    public var chatIds: [String] {
        get {
            return whatsAppChatIds as? [String] ?? []
        }
        set {
            whatsAppChatIds = newValue as NSArray
        }
    }
}

// MARK: - Helper methods per gestire le chat
extension SinistroWhatsAppThread {
    func addWhatsAppChatId(_ chatId: String) {
        var ids = chatIds
        if !ids.contains(chatId) {
            ids.append(chatId)
            chatIds = ids
        }
    }
    
    func removeWhatsAppChatId(_ chatId: String) {
        var ids = chatIds
        ids.removeAll { $0 == chatId }
        chatIds = ids
    }
}

// MARK: - Identifiable
extension SinistroWhatsAppThread: Identifiable {
}

