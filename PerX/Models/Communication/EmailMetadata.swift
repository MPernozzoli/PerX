import Foundation
import CoreData

@objc(EmailMetadata)
public class EmailMetadata: NSManagedObject {
    @NSManaged public var messageId: String?
    @NSManaged public var tags: NSSet?
}

extension EmailMetadata {
    static func fetchRequest() -> NSFetchRequest<EmailMetadata> {
        return NSFetchRequest<EmailMetadata>(entityName: "EmailMetadata")
    }
    
    @objc(addTagsObject:)
    @NSManaged public func addToTags(_ value: Tag)
    
    @objc(removeTagsObject:)
    @NSManaged public func removeFromTags(_ value: Tag)
    
    @objc(addTags:)
    @NSManaged public func addToTags(_ values: NSSet)
    
    @objc(removeTags:)
    @NSManaged public func removeFromTags(_ values: NSSet)
} 