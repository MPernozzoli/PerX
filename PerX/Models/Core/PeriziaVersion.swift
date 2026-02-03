import Foundation
import CoreData

@objc(PeriziaVersion)
public class PeriziaVersion: NSManagedObject, Identifiable {
    
}

extension PeriziaVersion {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PeriziaVersion> {
        return NSFetchRequest<PeriziaVersion>(entityName: "PeriziaVersion")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var campo: String // "relazionePerizia", "noteConclusive", "noteRiserva", "noteOsservazioni"
    @NSManaged public var contenuto: String
    @NSManaged public var numeroVersione: Int16
    @NSManaged public var dataCreazione: Date
    @NSManaged public var perizia: Perizia?
}
