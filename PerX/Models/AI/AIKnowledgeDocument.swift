import Foundation
import CoreData

@objc(AIKnowledgeDocument)
public class AIKnowledgeDocument: NSManagedObject, Identifiable {}

extension AIKnowledgeDocument {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<AIKnowledgeDocument> {
        NSFetchRequest<AIKnowledgeDocument>(entityName: "AIKnowledgeDocument")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var titolo: String
    @NSManaged public var contenuto: String
    @NSManaged public var categoria: String
    @NSManaged public var ordine: Int16
    @NSManaged public var attivo: Bool
}

