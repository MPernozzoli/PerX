import Foundation
import CoreData

/// Fotografia salvata della stima: input e calcolo congelati, con approvazione.
/// Solo l'ultima revisione approvata è valida; le precedenti diventano «superate».
@objc(StimaRevisione)
public class StimaRevisione: NSManagedObject, Identifiable {

}

extension StimaRevisione {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<StimaRevisione> {
        return NSFetchRequest<StimaRevisione>(entityName: "StimaRevisione")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var numero: Int32
    @NSManaged public var dataCreazione: Date?
    @NSManaged public var inputJSON: String?
    @NSManaged public var calcoloJSON: String?
    @NSManaged public var hashCalcolo: String?
    @NSManaged public var hashEconomico: String?
    @NSManaged public var liquidabile: NSDecimalNumber?
    @NSManaged public var dannoAccertato: NSDecimalNumber?
    @NSManaged public var richiesta: NSDecimalNumber?
    @NSManaged public var esito: String?
    @NSManaged public var approvata: Bool
    @NSManaged public var approvataDa: String?
    @NSManaged public var dataApprovazione: Date?
    /// Numero della revisione da cui l'approvazione è stata ereditata (0 = approvazione diretta)
    @NSManaged public var ereditataDa: Int32
    @NSManaged public var superata: Bool
    @NSManaged public var nota: String?
    @NSManaged public var perizia: Perizia?

    var calcolo: StimaCalcolo? {
        guard let data = calcoloJSON?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StimaCalcolo.self, from: data)
    }

    var input: StimaInput? {
        guard let data = inputJSON?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StimaInput.self, from: data)
    }

    var esitoValue: EsitoStima { EsitoStima(stringa: esito) }
}
