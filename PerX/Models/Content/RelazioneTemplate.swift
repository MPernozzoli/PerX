import Foundation
import CoreData

@objc(RelazioneTemplate)
public class RelazioneTemplate: NSManagedObject, Identifiable {}

extension RelazioneTemplate {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<RelazioneTemplate> {
        NSFetchRequest<RelazioneTemplate>(entityName: "RelazioneTemplate")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var nome: String
    @NSManaged public var contenuto: String
    @NSManaged public var tipoSinistro: String?
    @NSManaged public var dataCreazione: Date?
    @NSManaged public var attivo: Bool
    
    // Condizioni booleane: nil = qualsiasi, true/false = match esplicito
    @NSManaged public var condSopralluogo: NSNumber?
    @NSManaged public var condFulminazione: NSNumber?
    @NSManaged public var condLiquidiamo: NSNumber?
}

