import Foundation

struct ExcelData: Codable {
    // Importi
    let importoRichiesto: Double?
    let importoLiquidato: Double?
    let dannoAccertato: Double?
    let dannoAccertatoNetto: Double?
    let massimals: [Double]  // C34/C35/C36
    
    // Date
    let dataSinistro: Date?
    
    // Informazioni compagnia
    let compagnia: String?
    let divisione: String?
    let numeroSinistro: String?
    let codiceAgenzia: String?
    let agenzia: String?
    
    // Informazioni assicurato
    let nomeAssicurato: String?
    let indirizzoAssicurato: String?
    let telefonoAssicurato: String?
    let emailAssicurato: String?
    let iban: Bool
    
    enum CodingKeys: String, CodingKey {
        case importoRichiesto = "importo_richiesto"
        case importoLiquidato = "importo_liquidato"
        case dannoAccertato = "danno_accertato"
        case dannoAccertatoNetto = "danno_accertato_netto"
        case massimals = "massimals"
        case dataSinistro = "data_sinistro"
        case compagnia = "compagnia"
        case compagniaAlt = "compagnia_alt"
        case divisione = "divisione"
        case numeroSinistro = "numero_sinistro"
        case codiceAgenzia = "codice_agenzia"
        case agenzia = "agenzia"
        case nomeAssicurato = "nome_assicurato"
        case indirizzoAssicurato = "indirizzo_assicurato"
        case telefonoAssicurato = "telefono_assicurato"
        case emailAssicurato = "email_assicurato"
        case iban = "iban"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Gestione importi
        importoRichiesto = Self.parseImporto(try? container.decode(String.self, forKey: .importoRichiesto))
        importoLiquidato = Self.parseImporto(try? container.decode(String.self, forKey: .importoLiquidato))
        dannoAccertato = try? container.decode(Double.self, forKey: .dannoAccertato)
        massimals = (try? container.decode([Double].self, forKey: .massimals)) ?? []
        
        // Calcolo danno accertato netto
        if let accertato = dannoAccertato {
            let totaleMassimali = massimals.reduce(0, +)
            dannoAccertatoNetto = totaleMassimali > 0 ? min(accertato, totaleMassimali) : accertato
        } else {
            dannoAccertatoNetto = nil
        }
        
        // Gestione date
        if let dateString = try? container.decode(String.self, forKey: .dataSinistro) {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy"
            dataSinistro = formatter.date(from: dateString)
        } else {
            dataSinistro = nil
        }
        
        // Gestione compagnia e divisione
        let compagniaMain = try? container.decode(String.self, forKey: .compagnia)
        let compagniaSecondary = try? container.decode(String.self, forKey: .compagniaAlt)
        compagnia = compagniaMain?.isEmpty == false ? compagniaMain : compagniaSecondary
        divisione = compagniaMain?.isEmpty == false ? compagniaSecondary : nil
        
        // Gestione agenzia - il parsing corretto viene fatto in ExcelReaderService
        let agenziaFull = try? container.decode(String.self, forKey: .agenzia)
        codiceAgenzia = try? container.decode(String.self, forKey: .codiceAgenzia)
        // Il nome agenzia viene parsato correttamente in ExcelReaderService usando AgencyReaderHelper
        agenzia = agenziaFull
        
        // Altri campi
        numeroSinistro = try? container.decode(String.self, forKey: .numeroSinistro)
        nomeAssicurato = try? container.decode(String.self, forKey: .nomeAssicurato)
        indirizzoAssicurato = try? container.decode(String.self, forKey: .indirizzoAssicurato)
        telefonoAssicurato = try? container.decode(String.self, forKey: .telefonoAssicurato)
        emailAssicurato = try? container.decode(String.self, forKey: .emailAssicurato)
        iban = (try? container.decode(String.self, forKey: .iban))?.isEmpty == false
    }
    
    private static func parseImporto(_ value: String?) -> Double? {
        guard let value = value else { return nil }
        // Rimuovi simboli di valuta e spazi, poi converti in Double
        let cleanValue = value.replacingOccurrences(of: "[^0-9,.]", with: "", options: .regularExpression)
        return Double(cleanValue.replacingOccurrences(of: ",", with: "."))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(importoRichiesto, forKey: .importoRichiesto)
        try container.encode(importoLiquidato, forKey: .importoLiquidato)
        try container.encode(dataSinistro, forKey: .dataSinistro)
        try container.encode(compagnia, forKey: .compagnia)
        try container.encode(divisione, forKey: .divisione)
        try container.encode(numeroSinistro, forKey: .numeroSinistro)
        try container.encode(codiceAgenzia, forKey: .codiceAgenzia)
        try container.encode(agenzia, forKey: .agenzia)
        try container.encode(nomeAssicurato, forKey: .nomeAssicurato)
        try container.encode(indirizzoAssicurato, forKey: .indirizzoAssicurato)
        try container.encode(telefonoAssicurato, forKey: .telefonoAssicurato)
        try container.encode(emailAssicurato, forKey: .emailAssicurato)
        try container.encode(iban, forKey: .iban)
    }
} 