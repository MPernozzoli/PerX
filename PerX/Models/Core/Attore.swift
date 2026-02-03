import Foundation
import CoreData

@objc(Attore)
public class Attore: NSManagedObject {
    
}

extension Attore {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Attore> {
        return NSFetchRequest<Attore>(entityName: "Attore")
    }
    
    // MARK: - Identificazione base
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var isPersonaFisica: Bool // true = persona fisica, false = azienda
    @NSManaged public var tipoAttore: String? // membro_team, liquidatore, agente, tecnico, amministratore_condominio, cat
    
    // MARK: - Dati anagrafici
    @NSManaged public var nome: String?
    @NSManaged public var cognome: String?
    @NSManaged public var ragioneSociale: String?
    @NSManaged public var codiceFiscale: String?
    @NSManaged public var partitaIva: String?
    @NSManaged public var dataNascita: Date?
    @NSManaged public var sesso: String? // M, F, Altro
    
    // MARK: - Dati bancari
    @NSManaged public var iban: String?
    
    // MARK: - Relazioni con indirizzi, telefoni, email
    @NSManaged public var indirizzi: NSSet?
    @NSManaged public var telefoni: NSSet?
    @NSManaged public var emails: NSSet?
    
    // MARK: - Relazioni con sinistri (inverse relationships)
    @NSManaged public var sinistroContraente: NSSet? // Sinistri dove questa persona è il contraente
    @NSManaged public var sinistroAssicurato: NSSet? // Sinistri dove questa persona è l'assicurato
    @NSManaged public var sinistroDanneggiato: NSSet? // Sinistri dove questa persona è il danneggiato
    @NSManaged public var sinistroAltriAttori: NSSet? // Altri ruoli nel sinistro
    
    // MARK: - Metadati
    @NSManaged public var dataCreazione: Date
    @NSManaged public var dataModifica: Date
    
    // MARK: - Computed Properties
    public var nomeCompleto: String {
        if isPersonaFisica {
            let nome = self.nome ?? ""
            let cognome = self.cognome ?? ""
            return "\(nome) \(cognome)".trimmingCharacters(in: .whitespaces)
        } else {
            return ragioneSociale ?? ""
        }
    }
    
    public var nominativo: String {
        return nomeCompleto
    }
    
    public var tipoAttoreLocalizzato: String {
        guard let tipo = tipoAttore else { return "Non specificato" }
        switch tipo {
        case "membro_team": return "Membro del Team"
        case "liquidatore": return "Liquidatore"
        case "agente": return "Agente"
        case "tecnico": return "Tecnico"
        case "amministratore_condominio": return "Amministratore di Condominio"
        case "cat": return "CAT"
        default: return tipo.capitalized
        }
    }
    
    // MARK: - Lifecycle
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        dataCreazione = Date()
        dataModifica = Date()
        isPersonaFisica = true // Default a persona fisica
    }
    
    public override func willSave() {
        super.willSave()
        dataModifica = Date()
    }
}

// MARK: - Core Data Relationships
extension Attore {
    
    @objc(addIndirizziObject:)
    @NSManaged public func addToIndirizzi(_ value: Indirizzo)
    
    @objc(removeIndirizziObject:)
    @NSManaged public func removeFromIndirizzi(_ value: Indirizzo)
    
    @objc(addIndirizzi:)
    @NSManaged public func addToIndirizzi(_ values: NSSet)
    
    @objc(removeIndirizzi:)
    @NSManaged public func removeFromIndirizzi(_ values: NSSet)
    
    @objc(addTelefoniObject:)
    @NSManaged public func addToTelefoni(_ value: Telefono)
    
    @objc(removeTelefoniObject:)
    @NSManaged public func removeFromTelefoni(_ value: Telefono)
    
    @objc(addTelefoni:)
    @NSManaged public func addToTelefoni(_ values: NSSet)
    
    @objc(removeTelefoni:)
    @NSManaged public func removeFromTelefoni(_ values: NSSet)
    
    @objc(addEmailsObject:)
    @NSManaged public func addToEmails(_ value: EmailContatto)
    
    @objc(removeEmailsObject:)
    @NSManaged public func removeFromEmails(_ value: EmailContatto)
    
    @objc(addEmails:)
    @NSManaged public func addToEmails(_ values: NSSet)
    
    @objc(removeEmails:)
    @NSManaged public func removeFromEmails(_ values: NSSet)
}

// MARK: - Enums per i selettori
extension Attore {
    
    enum TipoAttore: String, CaseIterable {
        case membroTeam = "membro_team"
        case liquidatore = "liquidatore"
        case agente = "agente"
        case tecnico = "tecnico"
        case amministratoreCondominio = "amministratore_condominio"
        case cat = "cat"
        
        var localizedName: String {
            switch self {
            case .membroTeam: return "Membro del Team"
            case .liquidatore: return "Liquidatore"
            case .agente: return "Agente"
            case .tecnico: return "Tecnico"
            case .amministratoreCondominio: return "Amministratore di Condominio"
            case .cat: return "CAT"
            }
        }
    }
    
    enum Sesso: String, CaseIterable {
        case maschio = "M"
        case femmina = "F"
        case altro = "Altro"
        
        var localizedName: String {
            switch self {
            case .maschio: return "Maschio"
            case .femmina: return "Femmina"
            case .altro: return "Altro"
            }
        }
    }
}

// MARK: - Modelli per indirizzi, telefoni, email

@objc(Indirizzo)
public class Indirizzo: NSManagedObject {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Indirizzo> {
        return NSFetchRequest<Indirizzo>(entityName: "Indirizzo")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var tipo: String? // residenza, domicilio, lavoro, altro
    @NSManaged public var via: String?
    @NSManaged public var civico: String?
    @NSManaged public var cap: String?
    @NSManaged public var citta: String?
    @NSManaged public var provincia: String?
    @NSManaged public var stato: String?
    @NSManaged public var isPrincipale: Bool
    
    @NSManaged public var attore: Attore?
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        isPrincipale = false
        stato = "Italia"
    }
    
    public var indirizzoCompleto: String {
        var componenti: [String] = []
        
        if let via = via, !via.isEmpty {
            var indirizzo = via
            if let civico = civico, !civico.isEmpty {
                indirizzo += ", \(civico)"
            }
            componenti.append(indirizzo)
        }
        
        if let cap = cap, !cap.isEmpty, let citta = citta, !citta.isEmpty {
            componenti.append("\(cap) \(citta)")
        } else if let citta = citta, !citta.isEmpty {
            componenti.append(citta)
        }
        
        if let provincia = provincia, !provincia.isEmpty {
            componenti.append("(\(provincia))")
        }
        
        return componenti.joined(separator: ", ")
    }
}

@objc(Telefono)
public class Telefono: NSManagedObject {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Telefono> {
        return NSFetchRequest<Telefono>(entityName: "Telefono")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var tipo: String? // cellulare, fisso, lavoro, fax, altro
    @NSManaged public var numero: String?
    @NSManaged public var isPrincipale: Bool
    
    @NSManaged public var attore: Attore?
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        isPrincipale = false
    }
}

@objc(EmailContatto)
public class EmailContatto: NSManagedObject {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<EmailContatto> {
        return NSFetchRequest<EmailContatto>(entityName: "EmailContatto")
    }
    
    @NSManaged public var id: UUID?
    
    public var wrappedId: UUID {
        id ?? UUID()
    }
    @NSManaged public var tipo: String? // personale, lavoro, altro
    @NSManaged public var indirizzo: String?
    @NSManaged public var isPrincipale: Bool
    
    @NSManaged public var attore: Attore?
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        isPrincipale = false
    }
} 