import Foundation
import CoreData

@objc(PerxiaFileAnalysis)
public class PerxiaFileAnalysis: NSManagedObject, Identifiable {}

extension PerxiaFileAnalysis {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PerxiaFileAnalysis> {
        NSFetchRequest<PerxiaFileAnalysis>(entityName: "PerxiaFileAnalysis")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var filePath: String
    @NSManaged public var jsonAnalisi: String
    @NSManaged public var tagSuggerito: String?
    @NSManaged public var daAllegare: Bool
    @NSManaged public var analisi: PerxiaAnalisi?
}

