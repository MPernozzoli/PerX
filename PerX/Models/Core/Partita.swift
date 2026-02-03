import Foundation
import CoreData

@objc(Partita)
public class Partita: NSManagedObject, Identifiable {
    
}

extension Partita {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Partita> {
        return NSFetchRequest<Partita>(entityName: "Partita")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var tipoPartita: String
    @NSManaged public var nomeFornitoCompagnia: String?
    @NSManaged public var nomeEditabile: String
    @NSManaged public var tipologia: String
    @NSManaged public var valoreAssicurato: NSDecimalNumber
    @NSManaged public var percentualeDeroga: NSDecimalNumber?
    @NSManaged public var determinazioneDanno: String
    @NSManaged public var regoleSpeciali: String?
    @NSManaged public var ordine: Int16
    @NSManaged public var partitaAcquistata: Bool // true = acquistata, false = non acquistata sulla polizza
    
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

