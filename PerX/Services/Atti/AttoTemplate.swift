import Foundation
import SwiftUI

// MARK: - AttoTemplate

struct AttoTemplate: Codable, Identifiable, Hashable {
    let id: String
    var nome: String
    var compagnia: String
    var tipo: AttoTipo
    var version: Int
    var pdfFileName: String
    var pages: [AttoPageTemplate]
    var createdAt: Date
    var updatedAt: Date
    var isActive: Bool
    
    init(
        id: String = UUID().uuidString,
        nome: String,
        compagnia: String,
        tipo: AttoTipo,
        version: Int = 1,
        pdfFileName: String,
        pages: [AttoPageTemplate] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isActive: Bool = true
    ) {
        self.id = id
        self.nome = nome
        self.compagnia = compagnia
        self.tipo = tipo
        self.version = version
        self.pdfFileName = pdfFileName
        self.pages = pages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
    }
}

// MARK: - AttoPageTemplate

struct AttoPageTemplate: Codable, Identifiable, Hashable {
    let id: String
    let pageNumber: Int
    var fields: [AttoFieldTemplate]
    
    init(id: String = UUID().uuidString, pageNumber: Int, fields: [AttoFieldTemplate] = []) {
        self.id = id
        self.pageNumber = pageNumber
        self.fields = fields
    }
}

// MARK: - AttoFieldTemplate

struct AttoFieldTemplate: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var rect: CodableRect
    var type: AttoFieldType
    var isRequired: Bool
    var alignment: AttoTextAlignment
    var maxLines: Int?
    var fontSize: CGFloat?
    
    init(
        id: String = UUID().uuidString,
        name: String,
        rect: CodableRect,
        type: AttoFieldType = .text,
        isRequired: Bool = false,
        alignment: AttoTextAlignment = .left,
        maxLines: Int? = nil,
        fontSize: CGFloat? = nil
    ) {
        self.id = id
        self.name = name
        self.rect = rect
        self.type = type
        self.isRequired = isRequired
        self.alignment = alignment
        self.maxLines = maxLines
        self.fontSize = fontSize
    }
}

// MARK: - CodableRect

struct CodableRect: Codable, Hashable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
    
    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    init(from cgRect: CGRect) {
        self.x = cgRect.origin.x
        self.y = cgRect.origin.y
        self.width = cgRect.size.width
        self.height = cgRect.size.height
    }
}

// MARK: - Enums

enum AttoTipo: String, Codable, CaseIterable {
    case liquidazione
    case accertamento
    case unico
    
    var displayName: String {
        switch self {
        case .liquidazione: return "Liquidazione"
        case .accertamento: return "Accertamento"
        case .unico: return "Unico (entrambi)"
        }
    }
}

enum AttoFieldType: String, Codable, CaseIterable {
    case text
    case number
    case currency
    case date
    case dateDay
    case dateMonth
    case dateYear
    case checkbox
    case ibanFull
    case ibanChar
    case signature
    
    var displayName: String {
        switch self {
        case .text: return "Testo"
        case .number: return "Numero"
        case .currency: return "Importo"
        case .date: return "Data"
        case .dateDay: return "Giorno"
        case .dateMonth: return "Mese"
        case .dateYear: return "Anno"
        case .checkbox: return "Checkbox"
        case .ibanFull: return "IBAN"
        case .ibanChar: return "IBAN char"
        case .signature: return "Firma"
        }
    }
}

enum AttoTextAlignment: String, Codable, CaseIterable, Hashable {
    case left
    case center
    case right
    
    var displayName: String {
        switch self {
        case .left: return "Sinistra"
        case .center: return "Centro"
        case .right: return "Destra"
        }
    }
    
    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

// MARK: - Campi predefiniti

enum AttoFieldName: String, CaseIterable {
    case nomeAssicurato = "nome_assicurato"
    case indirizzoAssicurato = "indirizzo_assicurato"
    case importoNumero = "importo_numero"
    case importoLettere = "importo_lettere"
    case dataSinistro = "data_sinistro"
    case numeroPolizza = "numero_polizza"
    case agenzia = "agenzia"
    case numeroSinistroCompagnia = "numero_sinistro_compagnia"
    case nomePerito = "nome_perito"
    case codiceFiscale = "codice_fiscale"
    case partitaIva = "partita_iva"
    case beneficiario = "beneficiario"
    // Tick compagnie principali
    case tickCompagniaZurich = "tick_compagnia_zurich"
    case tickCompagniaCattolica = "tick_compagnia_cattolica"
    case tickCompagniaGenerali = "tick_compagnia_generali"
    case tickCompagniaUnipol = "tick_compagnia_unipol"
    // Tick sottocompagnie Cattolica
    case tickSottocompagniaCattolica = "tick_sottocompagnia_cattolica"
    case tickSottocompagniaTua = "tick_sottocompagnia_tua"
    case tickSottocompagniaFata = "tick_sottocompagnia_fata"
    case tickSottocompagniaBcc = "tick_sottocompagnia_bcc"
    case tickSottocompagniaAbc = "tick_sottocompagnia_abc"
    // Tick tipo atto
    case tickTipoAttoLiquidazione = "tick_tipo_atto_liquidazione"
    case tickTipoAttoAccertamento = "tick_tipo_atto_accertamento"
    case tickRiserva = "tick_riserva"
    case tickOsservazioni = "tick_osservazioni"
    case noteRiservaOsservazioni = "note_riserva_osservazioni"
    case relazionePerizia = "relazione_perizia"
    case noteConclusive = "note_conclusive"
    case eventoCausatoDa = "evento_causato_da"
    case tickRiparto = "tick_riparto"
    case nomeRiparto1 = "nome_riparto_1"
    case nomeRiparto2 = "nome_riparto_2"
    case valoreRiparto1 = "valore_riparto_1"
    case valoreRiparto2 = "valore_riparto_2"
    case tickConLeSeguenti = "tick_con_le_seguenti"
    case iban = "iban"
    case dataGiorno = "data_giorno"
    case dataMese = "data_mese"
    case dataAnno = "data_anno"
    case firma = "firma"
    case dataFirma = "data_firma"
    
    var displayName: String {
        switch self {
        case .nomeAssicurato: return "Nome Assicurato"
        case .indirizzoAssicurato: return "Indirizzo Assicurato"
        case .importoNumero: return "Importo (numero)"
        case .importoLettere: return "Importo (lettere)"
        case .dataSinistro: return "Data Sinistro"
        case .numeroPolizza: return "Numero Polizza"
        case .agenzia: return "Agenzia"
        case .numeroSinistroCompagnia: return "N. Sinistro Compagnia"
        case .nomePerito: return "Nome Perito"
        case .codiceFiscale: return "Codice Fiscale"
        case .partitaIva: return "Partita IVA"
        case .beneficiario: return "Beneficiario"
        case .tickCompagniaZurich: return "Tick Zurich"
        case .tickCompagniaCattolica: return "Tick Cattolica"
        case .tickCompagniaGenerali: return "Tick Generali"
        case .tickCompagniaUnipol: return "Tick Unipol"
        case .tickSottocompagniaCattolica: return "Tick Sottocomp. Cattolica"
        case .tickSottocompagniaTua: return "Tick Sottocomp. TUA"
        case .tickSottocompagniaFata: return "Tick Sottocomp. FATA"
        case .tickSottocompagniaBcc: return "Tick Sottocomp. BCC"
        case .tickSottocompagniaAbc: return "Tick Sottocomp. ABC"
        case .tickTipoAttoLiquidazione: return "Tick Liquidazione"
        case .tickTipoAttoAccertamento: return "Tick Accertamento"
        case .tickRiserva: return "Tick Riserva"
        case .tickOsservazioni: return "Tick Osservazioni"
        case .noteRiservaOsservazioni: return "Note Riserva/Osservazioni"
        case .relazionePerizia: return "Relazione Perizia"
        case .noteConclusive: return "Note Conclusive"
        case .eventoCausatoDa: return "Evento Causato Da"
        case .tickRiparto: return "Tick Riparto"
        case .nomeRiparto1: return "Nome Riparto 1"
        case .nomeRiparto2: return "Nome Riparto 2"
        case .valoreRiparto1: return "Valore Riparto 1"
        case .valoreRiparto2: return "Valore Riparto 2"
        case .tickConLeSeguenti: return "Tick Con Le Seguenti"
        case .iban: return "IBAN"
        case .dataGiorno: return "Giorno"
        case .dataMese: return "Mese"
        case .dataAnno: return "Anno"
        case .firma: return "Firma"
        case .dataFirma: return "Data Firma"
        }
    }
    
    var fieldType: AttoFieldType {
        switch self {
        case .nomeAssicurato, .indirizzoAssicurato, .agenzia, .numeroPolizza,
             .numeroSinistroCompagnia, .nomePerito, .eventoCausatoDa,
             .nomeRiparto1, .nomeRiparto2, .importoLettere, .relazionePerizia,
             .noteConclusive, .noteRiservaOsservazioni, .codiceFiscale, .partitaIva,
             .beneficiario:
            return .text
        case .importoNumero, .valoreRiparto1, .valoreRiparto2:
            return .currency
        case .dataSinistro, .dataFirma:
            return .date
        case .dataGiorno:
            return .dateDay
        case .dataMese:
            return .dateMonth
        case .dataAnno:
            return .dateYear
        case .tickCompagniaZurich, .tickCompagniaCattolica, .tickCompagniaGenerali,
             .tickCompagniaUnipol, .tickTipoAttoLiquidazione, .tickTipoAttoAccertamento,
             .tickRiserva, .tickOsservazioni, .tickRiparto, .tickConLeSeguenti,
             .tickSottocompagniaCattolica, .tickSottocompagniaTua, .tickSottocompagniaFata,
             .tickSottocompagniaBcc, .tickSottocompagniaAbc:
            return .checkbox
        case .iban:
            return .ibanFull
        case .firma:
            return .signature
        }
    }
    
    /// Restituisce i campi compatibili con il tipo specificato
    static func fieldsForType(_ type: AttoFieldType) -> [AttoFieldName] {
        return allCases.filter { $0.fieldType == type }
    }
}

// MARK: - Templates Storage

struct AttoTemplatesStorage: Codable {
    var templates: [AttoTemplate]
    var lastUpdated: Date
    
    init(templates: [AttoTemplate] = [], lastUpdated: Date = Date()) {
        self.templates = templates
        self.lastUpdated = lastUpdated
    }
}
