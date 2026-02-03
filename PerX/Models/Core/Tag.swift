import Foundation
import CoreData

@objc(Tag)
public class Tag: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var type: Int16
    @NSManaged public var color: String?
    @NSManaged public var sinistro: Sinistro?
    @NSManaged public var emails: NSSet?
}

extension Tag {
    static func fetchRequest() -> NSFetchRequest<Tag> {
        return NSFetchRequest<Tag>(entityName: "Tag")
    }
    
    public var wrappedName: String {
        name ?? "Tag senza nome"
    }
    
    public var wrappedColor: String {
        color ?? "#808080" // Grigio di default
    }
} 