import Foundation
import CoreData

@objc(PerxiaAnalisi)
public class PerxiaAnalisi: NSManagedObject, Identifiable {
    
}

extension PerxiaAnalisi {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PerxiaAnalisi> {
        return NSFetchRequest<PerxiaAnalisi>(entityName: "PerxiaAnalisi")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var dataAnalisi: Date?
    @NSManaged public var relazioneComplessiva: String?
    @NSManaged public var systemPrompt: String?
    @NSManaged public var contextSummary: String?
    
    @NSManaged public var sinistro: Sinistro?
    @NSManaged public var beni: NSSet?
    
    var beniArray: [PerxiaBene] {
        let set = beni as? Set<PerxiaBene> ?? []
        return set.sorted { $0.ordine < $1.ordine }
    }
}

