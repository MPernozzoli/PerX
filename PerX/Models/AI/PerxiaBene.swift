import Foundation
import CoreData

@objc(PerxiaBene)
public class PerxiaBene: NSManagedObject, Identifiable {
    
}

extension PerxiaBene {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PerxiaBene> {
        return NSFetchRequest<PerxiaBene>(entityName: "PerxiaBene")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var tipologia: String
    @NSManaged public var componenti: String?
    @NSManaged public var modello: String?
    @NSManaged public var anno: String?
    @NSManaged public var osservazioniVisive: String?
    @NSManaged public var valutazioneTest: String?
    @NSManaged public var compatibilitaGaranzia: String?
    @NSManaged public var stimaEconomica: String?
    @NSManaged public var noteAggiuntive: String?
    @NSManaged public var ordine: Int16
    // Certezze e metadata
    @NSManaged public var certezzaTipologia: Double
    @NSManaged public var certezzaModello: Double
    @NSManaged public var certezzaAnno: Double
    @NSManaged public var certezzaOsservazioni: Double
    @NSManaged public var certezzaTest: Double
    @NSManaged public var certezzaCompatibilita: Double
    @NSManaged public var certezzaStima: Double
    @NSManaged public var fotoAssociate: [String]?
    @NSManaged public var compatibilitaDanno: String?
    // Bene vs componente
    @NSManaged public var tipoBene: String?
    @NSManaged public var beneParent: PerxiaBene?
    @NSManaged public var componentiDettaglio: NSSet?
    
    @NSManaged public var analisi: PerxiaAnalisi?
}

// MARK: - Generated accessors for componentiDettaglio
extension PerxiaBene {
    @objc(addComponentiDettaglioObject:)
    @NSManaged public func addToComponentiDettaglio(_ value: PerxiaBene)

    @objc(removeComponentiDettaglioObject:)
    @NSManaged public func removeFromComponentiDettaglio(_ value: PerxiaBene)

    @objc(addComponentiDettaglio:)
    @NSManaged public func addToComponentiDettaglio(_ values: NSSet)

    @objc(removeComponentiDettaglio:)
    @NSManaged public func removeFromComponentiDettaglio(_ values: NSSet)
}

