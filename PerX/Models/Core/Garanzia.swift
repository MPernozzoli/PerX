import Foundation
import CoreData

@objc(Garanzia)
public class Garanzia: NSManagedObject, Identifiable {
    
}

extension Garanzia {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Garanzia> {
        return NSFetchRequest<Garanzia>(entityName: "Garanzia")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var tipoGaranzia: String
    @NSManaged public var nomeFornitoCompagnia: String?
    @NSManaged public var nomeEditabile: String
    @NSManaged public var tipologia: String
    @NSManaged public var valorePRA: NSDecimalNumber?
    @NSManaged public var massimale: NSDecimalNumber
    @NSManaged public var massimaleUnico: Bool
    @NSManaged public var franchigiaMinimo: NSDecimalNumber?
    @NSManaged public var franchigiaMassimo: NSDecimalNumber?
    @NSManaged public var scopertoPercentuale: NSDecimalNumber?
    @NSManaged public var scopertoMinimo: NSDecimalNumber?
    @NSManaged public var scopertoMassimo: NSDecimalNumber?
    @NSManaged public var ordine: Int16
    
    @NSManaged public var perizia: Perizia?
    @NSManaged public var beni: NSSet?
    
    var beniArray: [Bene] {
        let set = beni as? Set<Bene> ?? []
        return set.sorted { $0.ordine < $1.ordine }
    }
    
    func addToBeni(_ value: Bene) {
        let items = self.mutableSetValue(forKey: "beni")
        items.add(value)
    }
    
    func removeFromBeni(_ value: Bene) {
        let items = self.mutableSetValue(forKey: "beni")
        items.remove(value)
    }
}

