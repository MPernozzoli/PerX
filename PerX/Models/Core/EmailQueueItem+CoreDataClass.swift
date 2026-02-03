import Foundation
import CoreData

/// Entità Core Data per gli elementi della coda email
@objc(EmailQueueItem)
public class EmailQueueItem: NSManagedObject, Identifiable {
    
    @NSManaged public var id: UUID?
    @NSManaged public var messageId: String?
    @NSManaged public var mailboxId: String?
    @NSManaged public var priority: Int16
    @NSManaged public var status: String?
    @NSManaged public var retryCount: Int16
    @NSManaged public var maxRetries: Int16
    @NSManaged public var createdAt: Date?
    @NSManaged public var scheduledAt: Date?
    @NSManaged public var startedAt: Date?
    @NSManaged public var completedAt: Date?
    @NSManaged public var lastError: String?
    @NSManaged public var emailCategory: String?
    @NSManaged public var emailSubject: String?
    @NSManaged public var emailSender: String?
    @NSManaged public var emailDate: Date?
    @NSManaged public var sinistroReference: String?
}

extension EmailQueueItem {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<EmailQueueItem> {
        return NSFetchRequest<EmailQueueItem>(entityName: "EmailQueueItem")
    }
}
