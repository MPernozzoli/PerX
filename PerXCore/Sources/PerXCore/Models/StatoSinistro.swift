import Foundation

// ============================================================================
// MARK: - Stato Sinistro Models (estratto da PerX/Managers/StatoManager.swift)
// Versione condivisa senza dipendenze UI per Hub e Client
// ============================================================================

// MARK: - Stato Category

public enum StatoCategory: String, CaseIterable, Codable, Sendable {
    case ingresso
    case avanzamento
    case chiusura
    case sistema
}

// MARK: - State Group

/// Raggruppa stati correlati per visualizzazione unificata nei filtri
public enum StateGroup: String, CaseIterable, Identifiable, Codable, Sendable {
    case daScaricare = "Da scaricare"
    case inAttesa = "In attesa"
    case periziaDaEseguire = "Perizia da eseguire"
    case videoperizia = "Videoperizia"
    case inGestione = "In gestione"
    case esito = "Esito"
    case atto = "Atto"
    case controllo = "Controllo"
    case sopralluogo = "Sopralluogo"
    case chiusura = "Chiusura"
    case sistema = "Sistema"
    
    public var id: String { rawValue }
    
    /// Descrizione breve per UI compatta
    public var shortLabel: String { rawValue }
    
    /// Icona rappresentativa del gruppo (SF Symbol name)
    public var iconName: String {
        switch self {
        case .daScaricare: return "tray.and.arrow.down"
        case .inAttesa: return "hourglass.circle"
        case .periziaDaEseguire: return "doc.text.magnifyingglass"
        case .videoperizia: return "video.circle"
        case .inGestione: return "gearshape"
        case .esito: return "megaphone"
        case .atto: return "envelope.badge"
        case .controllo: return "checklist"
        case .sopralluogo: return "mappin.and.ellipse"
        case .chiusura: return "lock.circle"
        case .sistema: return "exclamationmark.triangle"
        }
    }
    
    /// Colore esadecimale del gruppo
    public var colorHex: String {
        switch self {
        case .daScaricare: return "#FFA500"      // orange
        case .inAttesa: return "#FFFF00"         // yellow
        case .periziaDaEseguire: return "#00FFFF" // cyan
        case .videoperizia: return "#FFA500CC"   // orange 0.8
        case .inGestione: return "#0000FF"       // blue
        case .esito: return "#98FF98"            // mint
        case .atto: return "#800080"             // purple
        case .controllo: return "#98FF98B3"      // mint 0.7
        case .sopralluogo: return "#FFC0CB"      // pink
        case .chiusura: return "#00FF00"         // green
        case .sistema: return "#FF0000"          // red
        }
    }
    
    /// Stati appartenenti a questo gruppo
    public var members: [StatoSinistro] {
        StatoSinistro.allCases.filter { $0.stateGroup == self }
    }
    
    /// true se il gruppo ha più di una variante (sotto-stati)
    public var hasVariants: Bool { members.count > 1 }
}

// MARK: - State Variant

/// Variante di uno stato (suffisso dinamico)
public enum StateVariant: String, CaseIterable, Codable, Sendable {
    case tradizionale = "tradizionale"  // Perizia con sopralluogo
    case documentale = "documentale"
    case videoperizia = "videoperizia"
    case noResidui = "no residui"
    case daAssicurato = "da assicurato"
    case daAgenzia = "da agenzia"
    
    /// Suffisso da appendere alla descrizione base (es. " (documentale)")
    public var suffix: String {
        self == .tradizionale ? "" : " (\(rawValue))"
    }
    
    /// true se questa è la variante "base" (tradizionale)
    public var isBase: Bool { self == .tradizionale }
}

// MARK: - Stato Sinistro

/// Enum con tutti gli stati possibili di un sinistro
public enum StatoSinistro: String, CaseIterable, Identifiable, Codable, Sendable {
    // Stati di ingresso
    case daScaricare = "SV001"
    case inAttesaDocumentale = "SV002"
    case periziaDaEseguire = "SV003"
    case videoperiziaDaFissare = "SV004"
    case periziaDaEseguireNoResidui = "SV005"
    
    // Stati di avanzamento
    case periziaDaEseguireDocumentale = "SV010"
    case inGestioneDocumentale = "SV011"
    case inGestione = "SV012"
    case inGestioneVideoperizia = "SV013"
    case videoperiziaFissata = "SV014"
    case attoDaInviare = "SV020"
    case esitoDaComunicare = "SV021"
    case inAttesaDaAssicurato = "SV022"
    case inAttesaDaAgenzia = "SV023"
    case esitoComunicato = "SV030"
    case attoInviato = "SV031"
    case attoRicevutoSottoscritto = "SV032"
    case accettataVerbalmente = "SV033"
    case inControllo = "SV040"
    case controllata = "SV041"
    case richiestaAutorizzazione = "SV042"
    case supervisioneNonConcordata = "SV043"
    case sopralluogoFissato = "SV050"
    case sopralluogoRestituito = "SV051"
    
    // Stati di chiusura
    case chiusa = "SV090"
    case richiestaRevisione = "SV091"
    
    // Stati sistema
    case revocata = "SI001"
    case annullata = "SI002"
    
    public var id: String { rawValue }
    
    public var isSystemState: Bool {
        rawValue.starts(with: "SI")
    }
    
    public var isVisible: Bool {
        rawValue.starts(with: "SV")
    }
    
    public var isCustomizable: Bool {
        isVisible
    }
    
    public var descrizione: String {
        switch self {
        case .daScaricare: return "Da scaricare"
        case .inAttesaDocumentale: return "In attesa (documentale)"
        case .periziaDaEseguire: return "Perizia da eseguire"
        case .videoperiziaDaFissare: return "Videoperizia da fissare"
        case .periziaDaEseguireNoResidui: return "Perizia da eseguire (no residui)"
        case .periziaDaEseguireDocumentale: return "Perizia da eseguire (documentale)"
        case .inGestioneDocumentale: return "In gestione (documentale)"
        case .inGestione: return "In gestione"
        case .inGestioneVideoperizia: return "In gestione (videoperizia)"
        case .videoperiziaFissata: return "Videoperizia fissata"
        case .attoDaInviare: return "Atto da inviare"
        case .esitoDaComunicare: return "Esito da comunicare"
        case .inAttesaDaAssicurato: return "In attesa (da assicurato)"
        case .inAttesaDaAgenzia: return "In attesa (da agenzia)"
        case .esitoComunicato: return "Esito comunicato"
        case .attoInviato: return "Atto inviato"
        case .attoRicevutoSottoscritto: return "Atto ricevuto sottoscritto"
        case .accettataVerbalmente: return "Accettata verbalmente"
        case .inControllo: return "In controllo"
        case .controllata: return "Controllata"
        case .richiestaAutorizzazione: return "Richiesta autorizzazione"
        case .supervisioneNonConcordata: return "Supervisione non concordata"
        case .sopralluogoFissato: return "Sopralluogo fissato"
        case .sopralluogoRestituito: return "Sopralluogo restituito"
        case .chiusa: return "Chiusa"
        case .richiestaRevisione: return "Richiesta revisione"
        case .revocata: return "Revocata"
        case .annullata: return "Annullata"
        }
    }
    
    public var category: StatoCategory {
        switch self {
        case .daScaricare, .inAttesaDocumentale, .periziaDaEseguire, .videoperiziaDaFissare, .periziaDaEseguireNoResidui:
            return .ingresso
        case .chiusa, .richiestaRevisione:
            return .chiusura
        case .revocata, .annullata:
            return .sistema
        default:
            return .avanzamento
        }
    }
    
    public var distanceFromClosure: Int {
        switch self {
        case .chiusa: return 0
        case .controllata, .inControllo, .richiestaAutorizzazione, .supervisioneNonConcordata: return 1
        case .attoRicevutoSottoscritto, .accettataVerbalmente: return 2
        case .attoInviato, .esitoComunicato: return 3
        case .esitoDaComunicare, .attoDaInviare: return 4
        case .videoperiziaFissata, .sopralluogoRestituito, .inGestione, .inGestioneVideoperizia, .inGestioneDocumentale: return 5
        case .periziaDaEseguireDocumentale, .periziaDaEseguire, .periziaDaEseguireNoResidui, .sopralluogoFissato: return 6
        case .inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia, .videoperiziaDaFissare: return 7
        case .daScaricare: return 8
        case .richiestaRevisione: return 4
        case .revocata, .annullata: return 10
        }
    }
    
    public var isSystem: Bool {
        switch self {
        case .revocata, .annullata: return true
        default: return false
        }
    }
    
    /// Gruppo di appartenenza (per filtri unificati)
    public var stateGroup: StateGroup {
        switch self {
        case .daScaricare:
            return .daScaricare
        case .inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia:
            return .inAttesa
        case .periziaDaEseguire, .periziaDaEseguireDocumentale, .periziaDaEseguireNoResidui:
            return .periziaDaEseguire
        case .videoperiziaDaFissare, .videoperiziaFissata:
            return .videoperizia
        case .inGestione, .inGestioneDocumentale, .inGestioneVideoperizia:
            return .inGestione
        case .attoDaInviare, .attoInviato, .attoRicevutoSottoscritto, .accettataVerbalmente:
            return .atto
        case .esitoDaComunicare, .esitoComunicato:
            return .esito
        case .inControllo, .controllata, .richiestaAutorizzazione, .supervisioneNonConcordata:
            return .controllo
        case .sopralluogoFissato, .sopralluogoRestituito:
            return .sopralluogo
        case .chiusa, .richiestaRevisione:
            return .chiusura
        case .revocata, .annullata:
            return .sistema
        }
    }
    
    /// Variante specifica (suffisso)
    public var variant: StateVariant {
        switch self {
        case .inAttesaDocumentale, .periziaDaEseguireDocumentale, .inGestioneDocumentale:
            return .documentale
        case .inGestioneVideoperizia:
            return .videoperizia
        case .periziaDaEseguireNoResidui:
            return .noResidui
        case .inAttesaDaAssicurato:
            return .daAssicurato
        case .inAttesaDaAgenzia:
            return .daAgenzia
        default:
            return .tradizionale
        }
    }
    
    /// Stato "base" del gruppo (senza variante)
    public var baseState: StatoSinistro {
        switch stateGroup {
        case .inAttesa: return .inAttesaDocumentale
        case .periziaDaEseguire: return .periziaDaEseguire
        case .inGestione: return .inGestione
        default: return self
        }
    }
    
    /// true se questo stato è il "base" del proprio gruppo
    public var isBaseOfGroup: Bool { self == baseState }
    
    /// Descrizione breve (senza variante) per UI compatta
    public var shortDescrizione: String {
        stateGroup.shortLabel
    }
    
    // MARK: - Filtri per Tipo Perizia
    
    /// true se questo stato è esclusivamente per sinistri DOCUMENTALI (senza sopralluogo)
    /// Questi stati NON devono essere disponibili per sinistri tradizionali
    public var isDocumentaleOnly: Bool {
        switch self {
        case .inAttesaDocumentale, .periziaDaEseguireDocumentale, .inGestioneDocumentale:
            return true
        default:
            return false
        }
    }
    
    /// true se questo stato è esclusivamente per sinistri TRADIZIONALI (con sopralluogo)
    /// Questi stati NON devono essere disponibili per sinistri documentali
    public var isTradizionaleOnly: Bool {
        switch self {
        case .sopralluogoFissato, .sopralluogoRestituito:
            return true
        default:
            return false
        }
    }
    
    /// true se questo stato è compatibile con il tipo di perizia specificato
    /// - Parameter isTradizionale: true se il sinistro prevede sopralluogo
    public func isCompatible(withTipoPerizia isTradizionale: Bool) -> Bool {
        if isTradizionale {
            // Sinistro tradizionale: escludi stati documentali
            return !isDocumentaleOnly
        } else {
            // Sinistro documentale: escludi stati tradizionali (sopralluogo)
            return !isTradizionaleOnly
        }
    }
    
    /// Restituisce l'equivalente dello stato per l'altro tipo di perizia, se esiste
    /// Es: inGestioneDocumentale → inGestione, periziaDaEseguire → periziaDaEseguireDocumentale
    public func equivalentState(forTipoPerizia isTradizionale: Bool) -> StatoSinistro? {
        // Se già compatibile, restituisci self
        if isCompatible(withTipoPerizia: isTradizionale) {
            return self
        }
        
        // Mappature dirette
        if isTradizionale {
            // Da documentale a tradizionale
            switch self {
            case .inAttesaDocumentale:
                return .periziaDaEseguire // In attesa documentale non ha equivalente tradizionale diretto
            case .periziaDaEseguireDocumentale:
                return .periziaDaEseguire
            case .inGestioneDocumentale:
                return .inGestione
            default:
                return nil
            }
        } else {
            // Da tradizionale a documentale
            switch self {
            case .sopralluogoFissato, .sopralluogoRestituito:
                return .periziaDaEseguireDocumentale // Nessun equivalente, torna a perizia documentale
            case .periziaDaEseguire:
                return .periziaDaEseguireDocumentale
            case .inGestione:
                return .inGestioneDocumentale
            default:
                return nil
            }
        }
    }
    
    /// Icona dello stato (SF Symbol)
    public var iconName: String {
        switch self {
        case .daScaricare: return "tray.and.arrow.down"
        case .inAttesaDocumentale: return "hourglass.circle"
        case .periziaDaEseguire: return "doc.text.magnifyingglass"
        case .videoperiziaDaFissare: return "video.badge.plus"
        case .periziaDaEseguireNoResidui: return "doc.text"
        case .periziaDaEseguireDocumentale: return "doc.text.fill"
        case .inGestioneDocumentale: return "gearshape.2"
        case .inGestione: return "gearshape"
        case .inGestioneVideoperizia: return "gearshape.2.fill"
        case .videoperiziaFissata: return "video.circle.fill"
        case .attoDaInviare: return "envelope.badge"
        case .esitoDaComunicare: return "megaphone"
        case .inAttesaDaAssicurato: return "person.crop.circle.badge.clock"
        case .inAttesaDaAgenzia: return "building.2.crop.circle"
        case .esitoComunicato: return "paperplane.circle"
        case .attoInviato: return "paperplane.circle.fill"
        case .attoRicevutoSottoscritto: return "checkmark.seal"
        case .accettataVerbalmente: return "bubble.left.and.exclamationmark.bubble.right"
        case .inControllo: return "checklist"
        case .controllata: return "checkmark.circle"
        case .richiestaAutorizzazione: return "person.badge.clock"
        case .supervisioneNonConcordata: return "exclamationmark.triangle"
        case .sopralluogoFissato: return "mappin.and.ellipse"
        case .sopralluogoRestituito: return "mappin.circle.fill"
        case .chiusa: return "lock.circle"
        case .richiestaRevisione: return "arrow.counterclockwise.circle"
        case .revocata: return "xmark.circle"
        case .annullata: return "trash.circle"
        }
    }
    
    /// Colore esadecimale dello stato
    public var colorHex: String {
        switch self {
        case .daScaricare: return "#FFA500"
        case .inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia: return "#FFFF00"
        case .periziaDaEseguire, .periziaDaEseguireDocumentale, .periziaDaEseguireNoResidui: return "#00FFFF"
        case .inGestione, .inGestioneDocumentale, .inGestioneVideoperizia: return "#0000FF"
        case .videoperiziaDaFissare, .videoperiziaFissata: return "#FFA500CC"
        case .sopralluogoFissato, .sopralluogoRestituito: return "#FFC0CB"
        case .attoDaInviare: return "#4B0082"
        case .esitoDaComunicare, .esitoComunicato: return "#98FF98"
        case .attoInviato: return "#800080"
        case .attoRicevutoSottoscritto, .accettataVerbalmente: return "#00FF00CC"
        case .inControllo, .controllata, .richiestaAutorizzazione, .supervisioneNonConcordata: return "#98FF98B3"
        case .chiusa: return "#00FF00"
        case .richiestaRevisione: return "#FF0000CC"
        case .revocata: return "#FF0000"
        case .annullata: return "#808080"
        }
    }
    
    /// Transizioni valide da questo stato
    public var validTransitions: [StatoSinistro] {
        switch self {
        case .daScaricare:
            return [.inAttesaDocumentale, .periziaDaEseguire, .videoperiziaDaFissare, .periziaDaEseguireNoResidui]
        case .inAttesaDocumentale:
            return [.periziaDaEseguireDocumentale, .periziaDaEseguire]
        case .periziaDaEseguire:
            return [.inGestione, .attoDaInviare, .esitoDaComunicare]
        case .videoperiziaDaFissare:
            return [.videoperiziaFissata, .inGestioneVideoperizia]
        case .periziaDaEseguireNoResidui:
            return [.inGestione, .esitoDaComunicare, .attoDaInviare]
        case .periziaDaEseguireDocumentale:
            return [.inGestioneDocumentale, .inGestione, .esitoDaComunicare]
        case .inGestioneDocumentale:
            return [.esitoDaComunicare, .attoDaInviare, .richiestaRevisione]
        case .inGestione:
            return [.attoDaInviare, .esitoDaComunicare, .richiestaRevisione]
        case .inGestioneVideoperizia:
            return [.videoperiziaFissata, .attoDaInviare, .esitoDaComunicare, .richiestaRevisione]
        case .videoperiziaFissata:
            return [.inGestioneVideoperizia, .attoDaInviare, .esitoDaComunicare]
        case .attoDaInviare:
            return [.attoInviato]
        case .esitoDaComunicare:
            return [.esitoComunicato]
        case .inAttesaDaAssicurato, .inAttesaDaAgenzia:
            return [.inGestione, .inGestioneDocumentale, .periziaDaEseguireDocumentale, .esitoDaComunicare]
        case .esitoComunicato:
            return [.attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa, .inGestione, .richiestaAutorizzazione, .supervisioneNonConcordata]
        case .attoInviato:
            return [.attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa, .inGestione, .richiestaAutorizzazione, .supervisioneNonConcordata]
        case .attoRicevutoSottoscritto:
            return [.chiusa, .richiestaAutorizzazione, .supervisioneNonConcordata]
        case .accettataVerbalmente:
            return [.chiusa, .richiestaAutorizzazione, .supervisioneNonConcordata]
        case .inControllo:
            return [.controllata]
        case .controllata:
            return [.inGestione, .periziaDaEseguire, .chiusa, .richiestaRevisione]
        case .richiestaAutorizzazione:
            return [.chiusa, .controllata, .inGestione]
        case .supervisioneNonConcordata:
            return [.chiusa, .controllata, .inGestione]
        case .sopralluogoFissato:
            return [.sopralluogoRestituito, .inGestione]
        case .sopralluogoRestituito:
            return [.inGestione, .periziaDaEseguire, .attoDaInviare, .esitoDaComunicare]
        case .chiusa:
            return [.richiestaRevisione]
        case .richiestaRevisione:
            return [.inGestione, .chiusa]
        case .revocata:
            return [.daScaricare]
        case .annullata:
            return []
        }
    }
    
    /// Crea uno StatoSinistro dalla sua descrizione testuale
    public static func fromDescrizione(_ descrizione: String) -> StatoSinistro? {
        return allCases.first { $0.descrizione == descrizione }
    }
}

// MARK: - Sinistro DTO (per API Hub-Client)

/// DTO sinistro minimale per comunicazione Hub-Client
public struct SinistroDTO: Codable, Identifiable, Sendable {
    public let id: String
    public let riferimento: String
    public let stato: String
    public let statoId: String
    public let assicurato: String?
    public let polizza: String?
    public let agenzia: String?
    public let dataAssegnazione: Date?
    public let dataEvento: Date?
    public let dataChiusura: Date?
    public let ownerEmail: String?
    public let ownerName: String?
    public let complessita: String?
    public let definizione: String?
    public let importoLiquidato: Double?
    public let lastModified: Date
    
    public init(
        id: String = UUID().uuidString,
        riferimento: String,
        stato: String,
        statoId: String,
        assicurato: String? = nil,
        polizza: String? = nil,
        agenzia: String? = nil,
        dataAssegnazione: Date? = nil,
        dataEvento: Date? = nil,
        dataChiusura: Date? = nil,
        ownerEmail: String? = nil,
        ownerName: String? = nil,
        complessita: String? = nil,
        definizione: String? = nil,
        importoLiquidato: Double? = nil,
        lastModified: Date = Date()
    ) {
        self.id = id
        self.riferimento = riferimento
        self.stato = stato
        self.statoId = statoId
        self.assicurato = assicurato
        self.polizza = polizza
        self.agenzia = agenzia
        self.dataAssegnazione = dataAssegnazione
        self.dataEvento = dataEvento
        self.dataChiusura = dataChiusura
        self.ownerEmail = ownerEmail
        self.ownerName = ownerName
        self.complessita = complessita
        self.definizione = definizione
        self.importoLiquidato = importoLiquidato
        self.lastModified = lastModified
    }
    
    /// Ottiene l'enum StatoSinistro dal DTO
    public var statoEnum: StatoSinistro? {
        StatoSinistro(rawValue: statoId)
    }
}

// MARK: - State Change Request

/// Request per cambio stato da client all'Hub
public struct StateChangeRequest: Codable, Sendable {
    public let sinistroRef: String
    public let newStateId: String
    public let reason: String?
    public let userEmail: String
    
    public init(sinistroRef: String, newStateId: String, reason: String? = nil, userEmail: String) {
        self.sinistroRef = sinistroRef
        self.newStateId = newStateId
        self.reason = reason
        self.userEmail = userEmail
    }
    
    public var newState: StatoSinistro? {
        StatoSinistro(rawValue: newStateId)
    }
}

// MARK: - State Change Response

/// Response dopo cambio stato
public struct StateChangeResponse: Codable, Sendable {
    public let success: Bool
    public let sinistroRef: String
    public let oldState: String
    public let newState: String
    public let timestamp: Date
    public let errorMessage: String?
    
    public init(
        success: Bool,
        sinistroRef: String,
        oldState: String,
        newState: String,
        timestamp: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.success = success
        self.sinistroRef = sinistroRef
        self.oldState = oldState
        self.newState = newState
        self.timestamp = timestamp
        self.errorMessage = errorMessage
    }
}
