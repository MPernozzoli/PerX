import Foundation
import CoreData

@objc(Coassicurazione)
public class Coassicurazione: NSManagedObject, Identifiable {
    
}

extension Coassicurazione {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Coassicurazione> {
        return NSFetchRequest<Coassicurazione>(entityName: "Coassicurazione")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var tipo: String
    @NSManaged public var compagnia: String
    @NSManaged public var polizza: String
    @NSManaged public var numeroSinistro: String
    @NSManaged public var ordine: Int16
    /// Indennizzo virtuale dell'altra polizza (riparto art. 1910 c.c., coassicurazione indiretta)
    @NSManaged public var indennizzoVirtuale: NSDecimalNumber?
    
    @NSManaged public var sinistro: Sinistro?
}

