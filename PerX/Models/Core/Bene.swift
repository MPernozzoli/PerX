import Foundation
import CoreData

@objc(Bene)
public class Bene: NSManagedObject, Identifiable {
    
}

extension Bene {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Bene> {
        return NSFetchRequest<Bene>(entityName: "Bene")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var nome: String
    @NSManaged public var marca: String?
    @NSManaged public var modello: String?
    @NSManaged public var numeroSerie: String?
    @NSManaged public var anno: Int16 // 0 se non specificato
    @NSManaged public var stimata: Bool
    @NSManaged public var relazioneTecnica: String?
    @NSManaged public var richiesta: NSDecimalNumber?
    @NSManaged public var ivaInclusa: Bool
    @NSManaged public var ripristiniUltimati: Bool
    @NSManaged public var residuiMantenuti: String? // "si", "parziali", "no"
    @NSManaged public var sostituzioneIntero: Bool
    @NSManaged public var diversiPerRiga: Bool
    @NSManaged public var riconosciIVA: Bool
    @NSManaged public var determinazioneDanno: String?
    @NSManaged public var deprezzamento: Double // default 20
    @NSManaged public var aliquotaIVA: Double // default 22
    @NSManaged public var liquidazioneForzata: NSDecimalNumber? // se forzata manualmente
    @NSManaged public var ordine: Int16
    
    @NSManaged public var partita: Partita?
    @NSManaged public var garanzia: Garanzia?
    @NSManaged public var vociCosto: NSSet?
    @NSManaged public var periziaBozza: Perizia? // Per beni in bozza senza partita
    
    var vociCostoArray: [VoceCosto] {
        let set = vociCosto as? Set<VoceCosto> ?? []
        return set.sorted { $0.ordine < $1.ordine }
    }
    
    var determinazioneDannoEffettiva: String {
        determinazioneDanno ?? partita?.determinazioneDanno ?? "Valore a nuovo"
    }
    
    func addToVociCosto(_ value: VoceCosto) {
        let items = self.mutableSetValue(forKey: "vociCosto")
        items.add(value)
    }
    
    func removeFromVociCosto(_ value: VoceCosto) {
        let items = self.mutableSetValue(forKey: "vociCosto")
        items.remove(value)
    }
}
