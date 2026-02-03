import Foundation
import CoreData

@objc(Perizia)
public class Perizia: NSManagedObject, Identifiable {
    
}

extension Perizia {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Perizia> {
        return NSFetchRequest<Perizia>(entityName: "Perizia")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var descrizioneRischio: String?
    @NSManaged public var strutturaPortante: String?
    @NSManaged public var tamponamenti: String?
    @NSManaged public var ordituraTetto: String?
    @NSManaged public var copertura: String?
    @NSManaged public var finiture: String?
    @NSManaged public var condizioneRischio: String?
    @NSManaged public var rischio: String?
    @NSManaged public var deprezzamentoFabbricato: NSDecimalNumber?
    @NSManaged public var numeroPiani: Int16
    @NSManaged public var annoCostruzione: Int16
    @NSManaged public var denunciaTardiva: Bool
    @NSManaged public var mantenimentoResidui: String?
    @NSManaged public var rivalsaPresente: Bool
    @NSManaged public var rivalsaNota: String?
    @NSManaged public var arrotondamentoLiquidazione: NSDecimalNumber?
    @NSManaged public var stimaDannoIndennizzabile: NSDecimalNumber?
    @NSManaged public var vociPersonalizzateJSON: String?
    
    // Campi per generazione atti
    @NSManaged public var relazionePerizia: String?
    @NSManaged public var noteConclusive: String?
    @NSManaged public var noteRiserva: String?
    @NSManaged public var noteOsservazioni: String?
    @NSManaged public var hasRiserva: Bool
    @NSManaged public var eventoCausatoDa: String?
    @NSManaged public var determinazione: String? // Determinazione specifica (concordato con bonifico, verbalmente, ecc.)
    
    @NSManaged public var sinistro: Sinistro?
    @NSManaged public var partite: NSSet?
    @NSManaged public var garanzie: NSSet?
    @NSManaged public var beniBozza: NSSet?
    @NSManaged public var versioni: NSSet?
    
    var beniBozzaArray: [Bene] {
        let set = beniBozza as? Set<Bene> ?? []
        return set.sorted { $0.ordine < $1.ordine }
    }
    
    var partiteArray: [Partita] {
        let set = partite as? Set<Partita> ?? []
        return set.sorted { $0.ordine < $1.ordine }
    }
    
    var garanzieArray: [Garanzia] {
        let set = garanzie as? Set<Garanzia> ?? []
        return set.sorted { $0.ordine < $1.ordine }
    }
    
    var versioniArray: [PeriziaVersion] {
        let set = versioni as? Set<PeriziaVersion> ?? []
        return set.sorted { $0.numeroVersione < $1.numeroVersione }
    }
    
    func versioniPerCampo(_ campo: String) -> [PeriziaVersion] {
        return versioniArray.filter { $0.campo == campo }
    }
    
    func addToPartite(_ value: Partita) {
        let items = self.mutableSetValue(forKey: "partite")
        items.add(value)
    }
    
    func removeFromPartite(_ value: Partita) {
        let items = self.mutableSetValue(forKey: "partite")
        items.remove(value)
    }
    
    func addToGaranzie(_ value: Garanzia) {
        let items = self.mutableSetValue(forKey: "garanzie")
        items.add(value)
    }
    
    func removeFromGaranzie(_ value: Garanzia) {
        let items = self.mutableSetValue(forKey: "garanzie")
        items.remove(value)
    }
}

