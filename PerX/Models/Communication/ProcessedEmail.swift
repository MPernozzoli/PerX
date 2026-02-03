import Foundation
import CoreData

@objc(ProcessedEmail)
public class ProcessedEmail: NSManagedObject {
    @NSManaged public var messageId: String?
    @NSManaged public var processedDate: Date?
}

extension ProcessedEmail {
    static func fetchRequest() -> NSFetchRequest<ProcessedEmail> {
        return NSFetchRequest<ProcessedEmail>(entityName: "ProcessedEmail")
    }
} 