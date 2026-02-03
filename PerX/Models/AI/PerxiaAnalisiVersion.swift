import Foundation
import CoreData

@objc(PerxiaAnalisiVersion)
public class PerxiaAnalisiVersion: NSManagedObject, Identifiable {}

extension PerxiaAnalisiVersion {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PerxiaAnalisiVersion> {
        NSFetchRequest<PerxiaAnalisiVersion>(entityName: "PerxiaAnalisiVersion")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var numeroVersione: Int16
    @NSManaged public var dataCreazione: Date?
    @NSManaged public var jsonDescrizioniCloud: String?
    @NSManaged public var outputPhi4: String?
    @NSManaged public var relazioneGenerata: String?
    @NSManaged public var modificheUtente: String?
    
    @NSManaged public var analisi: PerxiaAnalisi?
}

