import Foundation
import CoreData

@objc(VoceCosto)
public class VoceCosto: NSManagedObject, Identifiable {
    
}

extension VoceCosto {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<VoceCosto> {
        return NSFetchRequest<VoceCosto>(entityName: "VoceCosto")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var descrizione: String
    @NSManaged public var unitaMisura: String
    @NSManaged public var quantita: NSDecimalNumber
    @NSManaged public var valoreUnitario: NSDecimalNumber
    @NSManaged public var totaleANuovo: NSDecimalNumber?
    @NSManaged public var percentualeMigliorie: NSDecimalNumber?
    @NSManaged public var nettoMigliorie: NSDecimalNumber?
    @NSManaged public var percentualeIllesi: NSDecimalNumber?
    @NSManaged public var nettoIllesi: NSDecimalNumber?
    @NSManaged public var vsu: NSDecimalNumber?
    @NSManaged public var si: NSDecimalNumber?
    @NSManaged public var indennizzabile: Bool
    @NSManaged public var formula: String?
    @NSManaged public var ordine: Int16
    @NSManaged public var campiForzati: NSSet?
    
    @NSManaged public var bene: Bene?
    
    var campiForzatiSet: Set<String> {
        get {
            return campiForzati as? Set<String> ?? []
        }
        set {
            campiForzati = NSSet(set: newValue)
        }
    }
    
    func isForzato(_ campo: String) -> Bool {
        return campiForzatiSet.contains(campo)
    }
    
    func setForzato(_ campo: String, value: Bool) {
        var set = campiForzatiSet
        if value {
            set.insert(campo)
        } else {
            set.remove(campo)
        }
        campiForzatiSet = set
    }
}

