import Foundation
import SwiftUI
import CoreData

enum StatoCategory: String, CaseIterable {
    case ingresso
    case avanzamento
    case chiusura
    case sistema
}

// MARK: - Gruppi di Stati (per unificazione UI)
/// Raggruppa stati correlati per visualizzazione unificata nei filtri
enum StateGroup: String, CaseIterable, Identifiable {
    case daScaricare = "Triage"
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
    
    var id: String { rawValue }
    
    /// Descrizione breve per UI compatta
    var shortLabel: String { rawValue }
    
    /// Icona rappresentativa del gruppo
    var icon: String {
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
    
    /// Colore rappresentativo del gruppo
    var color: Color {
        switch self {
        case .daScaricare: return .orange
        case .inAttesa: return .yellow
        case .periziaDaEseguire: return .cyan
        case .videoperizia: return .orange.opacity(0.8)
        case .inGestione: return .blue
        case .esito: return .mint
        case .atto: return .purple
        case .controllo: return .mint.opacity(0.7)
        case .sopralluogo: return .pink
        case .chiusura: return .green
        case .sistema: return .red
        }
    }
    
    /// Stati appartenenti a questo gruppo
    var members: [StatoManager.StatoSinistro] {
        StatoManager.StatoSinistro.allCases.filter { $0.stateGroup == self }
    }
    
    /// true se il gruppo ha più di una variante (sotto-stati)
    var hasVariants: Bool { members.count > 1 }
}

/// Variante di uno stato (suffisso dinamico)
enum StateVariant: String, CaseIterable {
    case tradizionale = "tradizionale"  // Perizia con sopralluogo
    case documentale = "documentale"
    case videoperizia = "videoperizia"
    case noResidui = "no residui"
    case daAssicurato = "da assicurato"
    case daAgenzia = "da agenzia"
    
    /// Suffisso da appendere alla descrizione base (es. " (documentale)")
    var suffix: String {
        self == .tradizionale ? "" : " (\(rawValue))"
    }
    
    /// true se questa è la variante "base" (tradizionale)
    var isBase: Bool { self == .tradizionale }
}

enum StatoDetailCategory: String, CaseIterable {
    case polizza = "Polizza"
    case foto = "Foto"
    case fotoubicazione = "ubicazione"
    case giustificativi = "giustificativi"
    case documentazioneGenerica = "documentazione"
    case ibanErrato = "IBAN Errato"
    case complesso = "complesso"
    case moltiBeni = "molti beni"
    case sollecitato = "sollecitato"
    case urgente = "urgente"
    case daScaricare = "da scaricare"
    case none = ""
}

enum CATInspectionWorkflowStage: String, Codable, CaseIterable {
    case automaticSchedulingInProgress = "automatic_scheduling_in_progress"
    case manualSchedulingRequired = "manual_scheduling_required"
    case scheduledAwaitingVisit = "scheduled_awaiting_visit"
    case replanningRequired = "replanning_required"
    case expertAssignmentPending = "expert_assignment_pending"

    var substateValue: String {
        "inspection:\(rawValue)"
    }

    init?(substateValue: String?) {
        guard let substateValue,
              substateValue.hasPrefix("inspection:") else { return nil }
        self.init(rawValue: String(substateValue.dropFirst("inspection:".count)))
    }
}

class StatoManager: ObservableObject {
    static let shared = StatoManager()
    
    enum StatoSinistro: String, CaseIterable, Identifiable {
        // Stati di ingresso
        case daScaricare = "SV001" // Legacy
        case inAttesaDocumentale = "SV002"
        case periziaDaEseguire = "SV003"
        case videoperiziaDaFissare = "SV004"
        case periziaDaEseguireNoResidui = "SV005"
        case istruzione = "SV006"
        case primoContatto = "SV007"
        case secondoContatto = "SV008"
        case inAttesaAssegnazione = "SV009"

        // Stati di avanzamento
        case periziaDaEseguireDocumentale = "SV010"
        case inGestioneDocumentale = "SV011"
        case inGestione = "SV012"
        case inGestioneVideoperizia = "SV013"
        case videoperiziaFissata = "SV014"
        case sopralluogoAssegnato = "SV015"
        case videoperiziaDaEseguire = "SV016"
        case daGestireVideoperizia = "SV017"
        case daGestireTradizionale = "SV018"
        case daGestireDocumentale = "SV019"
        case attoDaInviare = "SV020"
        case esitoDaComunicare = "SV021"
        case inAttesaDaAssicurato = "SV022"
        case inAttesaDaAgenzia = "SV023"
        case inAttesaDaTerzi = "SV024"
        case attesaPassiva = "SV025"
        case daGestireNoResidui = "SV026"
        case esitoComunicato = "SV030"
        case attoInviato = "SV031"
        case attoRicevutoSottoscritto = "SV032"
        case accettataVerbalmente = "SV033"
        case inControllo = "SV040"
        case controllata = "SV041"
        case richiestaAutorizzazione = "SV042"
        case supervisioneNonConcordata = "SV043"
        case daControllare = "SV044"
        case daChiudereASistema = "SV045"
        case sopralluogoFissato = "SV050"
        case sopralluogoRestituito = "SV051"
        case sopralluogoDaFissare = "SV052"
        case sopralluogoDaConcordare = "SV053"

        // Stati di chiusura
        case chiusa = "SV090"
        case richiestaRevisione = "SV091"
        case daRevisionare = "SV092"
        
        // Stati sistema
        case revocata = "SI001"
        case annullata = "SI002"
        
        var id: String { rawValue }
        
        var isSystemState: Bool {
            rawValue.starts(with: "SI")
        }
        
        var isVisible: Bool {
            rawValue.starts(with: "SV") && self != .daScaricare
        }
        
        var isCustomizable: Bool {
            isVisible
        }
        
        var descrizione: String {
            switch self {
            case .daScaricare: return "Da scaricare"
            case .inAttesaDocumentale: return "In attesa (documentale)"
            case .periziaDaEseguire: return "Perizia da eseguire"
            case .videoperiziaDaFissare: return "Videoperizia da fissare"
            case .periziaDaEseguireNoResidui: return "Perizia da eseguire (no residui)"
            case .istruzione: return "Istruzione"
            case .primoContatto: return "Primo contatto"
            case .secondoContatto: return "Secondo contatto"
            case .inAttesaAssegnazione: return "In attesa assegnazione"
            case .periziaDaEseguireDocumentale: return "Perizia da eseguire (documentale)"
            case .inGestioneDocumentale: return "In gestione (documentale)"
            case .inGestione: return "In gestione"
            case .inGestioneVideoperizia: return "In gestione (videoperizia)"
            case .videoperiziaFissata: return "Videoperizia fissata"
            case .sopralluogoAssegnato: return "Sopralluogo assegnato"
            case .videoperiziaDaEseguire: return "Videoperizia da eseguire"
            case .daGestireVideoperizia: return "Da gestire (video)"
            case .daGestireTradizionale: return "Da gestire (tradizionale)"
            case .daGestireDocumentale: return "Da gestire (documentale)"
            case .attoDaInviare: return "Atto da inviare"
            case .esitoDaComunicare: return "Esito da comunicare"
            case .inAttesaDaAssicurato: return "In attesa (da assicurato)"
            case .inAttesaDaAgenzia: return "In attesa (da agenzia)"
            case .inAttesaDaTerzi: return "In attesa da (agenzia/assicurato/terzi)"
            case .attesaPassiva: return "Attesa passiva"
            case .daGestireNoResidui: return "Da gestire (no residui)"
            case .esitoComunicato: return "Esito comunicato"
            case .attoInviato: return "Atto inviato"
            case .attoRicevutoSottoscritto: return "Atto ricevuto"
            case .accettataVerbalmente: return "Accettata verbalmente"
            case .inControllo: return "In controllo"
            case .controllata: return "Controllata"
            case .richiestaAutorizzazione: return "Richiesta autorizzazione"
            case .supervisioneNonConcordata: return "Supervisione non concordata"
            case .daControllare: return "Da controllare"
            case .daChiudereASistema: return "Da chiudere a sistema"
            case .sopralluogoFissato: return "Sopralluogo fissato"
            case .sopralluogoRestituito: return "Sopralluogo restituito"
            case .sopralluogoDaFissare: return "Sopralluogo da fissare"
            case .sopralluogoDaConcordare: return "Sopralluogo da concordare"
            case .chiusa: return "Chiusa"
            case .richiestaRevisione: return "Richiesta revisione"
            case .daRevisionare: return "Da revisionare"
            case .revocata: return "Revocata"
            case .annullata: return "Annullata"
            }
        }
        
        var category: StatoCategory {
            switch self {
            case .daScaricare, .istruzione, .primoContatto, .secondoContatto, .inAttesaAssegnazione,
                 .sopralluogoAssegnato, .videoperiziaDaEseguire, .daGestireVideoperizia, .daGestireTradizionale,
                 .daGestireDocumentale, .daGestireNoResidui, .attesaPassiva, .inAttesaDocumentale,
                 .periziaDaEseguire, .videoperiziaDaFissare, .periziaDaEseguireNoResidui:
                return .ingresso
            case .sopralluogoDaFissare, .sopralluogoDaConcordare, .sopralluogoFissato, .sopralluogoRestituito:
                return .avanzamento
            case .chiusa, .richiestaRevisione, .daRevisionare, .daChiudereASistema:
                return .chiusura
            case .revocata, .annullata:
                return .sistema
            default:
                return .avanzamento
            }
        }
        
        var distanceFromClosure: Int {
            switch self {
            case .chiusa: return 0
            case .daChiudereASistema: return 1
            case .controllata, .inControllo, .richiestaAutorizzazione, .supervisioneNonConcordata, .daControllare, .daRevisionare: return 2
            case .attoRicevutoSottoscritto, .accettataVerbalmente: return 3
            case .attoInviato, .esitoComunicato: return 3
            case .esitoDaComunicare, .attoDaInviare: return 4
            case .videoperiziaFissata, .sopralluogoRestituito, .inGestione, .inGestioneVideoperizia, .inGestioneDocumentale: return 5
            case .periziaDaEseguireDocumentale, .periziaDaEseguire, .periziaDaEseguireNoResidui, .sopralluogoFissato: return 6
            case .inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia, .inAttesaDaTerzi, .videoperiziaDaFissare, .attesaPassiva, .sopralluogoDaFissare, .sopralluogoDaConcordare: return 7
            case .daGestireVideoperizia, .daGestireTradizionale, .daGestireDocumentale, .daGestireNoResidui: return 8
            case .videoperiziaDaEseguire, .sopralluogoAssegnato, .inAttesaAssegnazione: return 9
            case .secondoContatto: return 10
            case .primoContatto: return 11
            case .istruzione, .daScaricare: return 12
            case .richiestaRevisione: return 4
            case .revocata, .annullata: return 10
            }
        }
        
        var isSystem: Bool {
            switch self {
            case .revocata, .annullata: return true
            default: return false
            }
        }

        var requiredRole: UserRole {
            switch self {
            case .istruzione, .primoContatto, .secondoContatto, .inAttesaAssegnazione, .sopralluogoAssegnato,
                 .videoperiziaDaEseguire, .daGestireVideoperizia, .daGestireTradizionale,
                 .daGestireDocumentale, .daGestireNoResidui, .attesaPassiva, .inAttesaDaTerzi,
                 .daControllare, .daChiudereASistema, .daRevisionare, .sopralluogoDaFissare,
                 .sopralluogoDaConcordare, .sopralluogoFissato, .sopralluogoRestituito:
                return .manager
            default:
                return .expert
            }
        }

        var additionalAllowedRoles: [UserRole] {
            switch self {
            case .sopralluogoDaFissare, .sopralluogoDaConcordare, .sopralluogoFissato, .sopralluogoRestituito:
                return [.cat]
            default:
                return []
            }
        }

        func isAccessible(to roles: [UserRole]) -> Bool {
            guard !isSystem else { return true }
            if roles.contains(.admin) { return true }
            if roles.contains(requiredRole) { return true }
            return roles.contains { additionalAllowedRoles.contains($0) }
        }
        
        // MARK: - Raggruppamento Stati
        
        /// Gruppo di appartenenza (per filtri unificati)
        var stateGroup: StateGroup {
            switch self {
            case .daScaricare, .istruzione, .primoContatto, .secondoContatto, .inAttesaAssegnazione,
                 .sopralluogoAssegnato, .videoperiziaDaEseguire, .daGestireVideoperizia,
                 .daGestireTradizionale, .daGestireDocumentale, .daGestireNoResidui, .attesaPassiva:
                return .daScaricare
            case .inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia, .inAttesaDaTerzi:
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
            case .inControllo, .controllata, .richiestaAutorizzazione, .supervisioneNonConcordata, .daControllare:
                return .controllo
            case .sopralluogoDaFissare, .sopralluogoDaConcordare, .sopralluogoFissato, .sopralluogoRestituito:
                return .sopralluogo
            case .chiusa, .richiestaRevisione, .daChiudereASistema, .daRevisionare:
                return .chiusura
            case .revocata, .annullata:
                return .sistema
            }
        }
        
        /// Variante specifica (suffisso)
        var variant: StateVariant {
            switch self {
            case .inAttesaDocumentale, .periziaDaEseguireDocumentale, .inGestioneDocumentale, .daGestireDocumentale:
                return .documentale
            case .inGestioneVideoperizia, .daGestireVideoperizia:
                return .videoperizia
            case .periziaDaEseguireNoResidui, .daGestireNoResidui:
                return .noResidui
            case .inAttesaDaAssicurato:
                return .daAssicurato
            case .inAttesaDaAgenzia, .inAttesaDaTerzi:
                return .daAgenzia
            default:
                return .tradizionale
            }
        }
        
        /// Stato "base" del gruppo (senza variante)
        var baseState: StatoSinistro {
            switch stateGroup {
            case .daScaricare: return .istruzione
            case .inAttesa: return .inAttesaDocumentale // default del gruppo
            case .periziaDaEseguire: return .periziaDaEseguire
            case .inGestione: return .inGestione
            default: return self
            }
        }
        
        /// true se questo stato è il "base" del proprio gruppo
        var isBaseOfGroup: Bool { self == baseState }
        
        /// Descrizione breve (senza variante) per UI compatta
        var shortDescrizione: String {
            stateGroup.shortLabel
        }
        
        // MARK: - Filtri per Tipo Perizia
        
        /// true se questo stato è esclusivamente per sinistri DOCUMENTALI (senza sopralluogo)
        /// Questi stati NON devono essere disponibili per sinistri tradizionali
        var isDocumentaleOnly: Bool {
            switch self {
            case .inAttesaDocumentale, .periziaDaEseguireDocumentale, .inGestioneDocumentale, .daGestireDocumentale:
                return true
            default:
                return false
            }
        }
        
        /// true se questo stato è esclusivamente per sinistri TRADIZIONALI (con sopralluogo)
        /// Questi stati NON devono essere disponibili per sinistri documentali
        var isTradizionaleOnly: Bool {
            switch self {
            case .sopralluogoDaFissare, .sopralluogoDaConcordare, .sopralluogoFissato, .sopralluogoRestituito:
                return true
            default:
                return false
            }
        }
        
        /// true se questo stato è compatibile con il tipo di perizia specificato
        /// - Parameter isTradizionale: true se il sinistro prevede sopralluogo
        func isCompatible(withTipoPerizia isTradizionale: Bool) -> Bool {
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
        func equivalentState(forTipoPerizia isTradizionale: Bool) -> StatoSinistro? {
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
                case .inGestioneDocumentale, .daGestireDocumentale:
                    return .inGestione
                default:
                    return nil
                }
            } else {
                // Da tradizionale a documentale
                switch self {
                case .sopralluogoDaFissare, .sopralluogoDaConcordare, .sopralluogoFissato, .sopralluogoRestituito:
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

        var catInspectionWorkflowStage: CATInspectionWorkflowStage? {
            switch self {
            case .sopralluogoDaFissare:
                return .automaticSchedulingInProgress
            case .sopralluogoDaConcordare:
                return .manualSchedulingRequired
            case .sopralluogoFissato:
                return .scheduledAwaitingVisit
            case .sopralluogoRestituito:
                return .replanningRequired
            default:
                return nil
            }
        }

        var isCATInspectionWorkflowState: Bool {
            catInspectionWorkflowStage != nil
        }
        
        var color: Color {
            if let customization = StatoManager.shared.customizations[id] {
                return Color(hex: customization.color)
            }
            
            switch self {
            case .daScaricare, .istruzione, .primoContatto, .secondoContatto, .inAttesaAssegnazione, .sopralluogoAssegnato,
                 .videoperiziaDaEseguire, .daGestireVideoperizia, .daGestireTradizionale, .daGestireDocumentale,
                 .daGestireNoResidui, .attesaPassiva, .daControllare, .daChiudereASistema, .daRevisionare:
                return .teal
            case .inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia, .inAttesaDaTerzi: return .yellow
            case .periziaDaEseguire, .periziaDaEseguireDocumentale, .periziaDaEseguireNoResidui: return .cyan
            case .inGestione, .inGestioneDocumentale, .inGestioneVideoperizia: return .blue
            case .videoperiziaDaFissare, .videoperiziaFissata: return .orange.opacity(0.8)
            case .sopralluogoDaFissare: return .pink.opacity(0.8)
            case .sopralluogoDaConcordare: return .orange
            case .sopralluogoFissato, .sopralluogoRestituito: return .pink
            case .attoDaInviare: return .indigo
            case .esitoDaComunicare, .esitoComunicato: return .mint
            case .attoInviato: return .purple
            case .attoRicevutoSottoscritto, .accettataVerbalmente: return .green.opacity(0.8)
            case .inControllo, .controllata, .richiestaAutorizzazione, .supervisioneNonConcordata: return .mint.opacity(0.7)
            case .chiusa: return .green
            case .richiestaRevisione: return .red.opacity(0.8)
            case .revocata: return .red
            case .annullata: return .gray
            }
        }
        
        var icon: String {
            if let customization = StatoManager.shared.customizations[id] {
                return customization.icon
            }
            
            switch self {
            case .daScaricare: return "tray.and.arrow.down"
            case .istruzione: return "tray.full"
            case .primoContatto: return "phone"
            case .secondoContatto: return "phone.arrow.up.right"
            case .inAttesaAssegnazione: return "person.crop.circle.badge.clock"
            case .inAttesaDocumentale: return "hourglass.circle"
            case .periziaDaEseguire: return "doc.text.magnifyingglass"
            case .videoperiziaDaFissare: return "video.badge.plus"
            case .periziaDaEseguireNoResidui: return "doc.text"
            case .periziaDaEseguireDocumentale: return "doc.text.fill"
            case .inGestioneDocumentale: return "gearshape.2"
            case .inGestione: return "gearshape"
            case .inGestioneVideoperizia: return "gearshape.2.fill"
            case .videoperiziaFissata: return "video.circle.fill"
            case .sopralluogoAssegnato: return "mappin.circle"
            case .videoperiziaDaEseguire: return "video.circle"
            case .daGestireVideoperizia: return "video.badge.checkmark"
            case .daGestireTradizionale: return "briefcase.circle"
            case .daGestireDocumentale: return "doc.badge.gearshape"
            case .attoDaInviare: return "envelope.badge"
            case .esitoDaComunicare: return "megaphone"
            case .inAttesaDaAssicurato: return "person.crop.circle.badge.clock"
            case .inAttesaDaAgenzia: return "building.2.crop.circle"
            case .inAttesaDaTerzi: return "person.2.badge.gearshape"
            case .attesaPassiva: return "pause.circle"
            case .daGestireNoResidui: return "shippingbox"
            case .esitoComunicato: return "paperplane.circle"
            case .attoInviato: return "paperplane.circle.fill"
            case .attoRicevutoSottoscritto: return "tray.full.fill"
            case .accettataVerbalmente: return "bubble.left.and.exclamationmark.bubble.right"
            case .inControllo: return "checklist"
            case .controllata: return "checkmark.circle"
            case .richiestaAutorizzazione: return "person.badge.clock"
            case .supervisioneNonConcordata: return "exclamationmark.triangle"
            case .daControllare: return "checklist.unchecked"
            case .daChiudereASistema: return "externaldrive.badge.checkmark"
            case .sopralluogoDaFissare: return "calendar.badge.clock"
            case .sopralluogoDaConcordare: return "calendar.badge.exclamationmark"
            case .sopralluogoFissato: return "mappin.and.ellipse"
            case .sopralluogoRestituito: return "mappin.circle.fill"
            case .chiusa: return "lock.circle"
            case .richiestaRevisione: return "arrow.counterclockwise.circle"
            case .daRevisionare: return "arrow.triangle.2.circlepath"
            case .revocata: return "xmark.circle"
            case .annullata: return "trash.circle"
            }
        }
        
        var validTransitions: [StatoSinistro] {
            switch self {
            case .daScaricare:
                return [.istruzione, .inAttesaDocumentale, .videoperiziaDaFissare, .periziaDaEseguireNoResidui, .sopralluogoDaFissare]

            case .istruzione:
                return [.primoContatto, .sopralluogoDaFissare]

            case .primoContatto:
                return [.secondoContatto, .inAttesaAssegnazione, .sopralluogoDaFissare, .videoperiziaDaEseguire, .daGestireTradizionale, .daGestireDocumentale, .daGestireNoResidui]

            case .secondoContatto:
                return [.inAttesaAssegnazione, .sopralluogoDaFissare, .videoperiziaDaEseguire, .daGestireTradizionale, .daGestireDocumentale, .daGestireNoResidui]

            case .inAttesaAssegnazione:
                return [.sopralluogoAssegnato, .sopralluogoDaFissare, .videoperiziaDaEseguire, .daGestireDocumentale, .daGestireNoResidui]

            case .sopralluogoAssegnato:
                return [.daGestireTradizionale]

            case .videoperiziaDaEseguire:
                return [.daGestireVideoperizia, .daGestireNoResidui]

            case .daGestireVideoperizia:
                return [.attesaPassiva, .inAttesaDaAssicurato, .inAttesaDaAgenzia, .inAttesaDaTerzi, .inGestione]

            case .daGestireTradizionale:
                return [.attesaPassiva, .inAttesaDaAssicurato, .inAttesaDaAgenzia, .inAttesaDaTerzi, .inGestione]

            case .daGestireDocumentale:
                return [.attesaPassiva, .inAttesaDaAssicurato, .inAttesaDaAgenzia, .inAttesaDaTerzi, .inGestione]

            case .daGestireNoResidui:
                return [.attesaPassiva, .inAttesaDaAssicurato, .inAttesaDaAgenzia, .inAttesaDaTerzi, .inGestione]

            case .attesaPassiva:
                return [.inGestione]
            
            case .inAttesaDocumentale:
                return [.daGestireDocumentale, .periziaDaEseguireDocumentale, .periziaDaEseguire]
            
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
                return [.attoDaInviare, .esitoDaComunicare, .daControllare, .richiestaRevisione]
            
            case .inGestioneVideoperizia:
                return [.videoperiziaFissata, .attoDaInviare, .esitoDaComunicare, .daControllare, .richiestaRevisione]
            
            case .videoperiziaFissata:
                return [.inGestioneVideoperizia, .attoDaInviare, .esitoDaComunicare]
            
            case .attoDaInviare:
                return [.attoInviato]
            
            case .esitoDaComunicare:
                return [.esitoComunicato]
            
            case .inAttesaDaAssicurato, .inAttesaDaAgenzia, .inAttesaDaTerzi:
                return [.attesaPassiva, .inGestione, .inGestioneDocumentale, .periziaDaEseguireDocumentale, .esitoDaComunicare]
            
            case .esitoComunicato:
                return [.attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa, .inGestione, .richiestaAutorizzazione, .supervisioneNonConcordata, .daChiudereASistema]
            
            case .attoInviato:
                return [.attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa, .inGestione, .richiestaAutorizzazione, .supervisioneNonConcordata, .daChiudereASistema]
            
            case .attoRicevutoSottoscritto:
                return [.chiusa, .richiestaAutorizzazione, .supervisioneNonConcordata, .daChiudereASistema]
            
            case .accettataVerbalmente:
                return [.chiusa, .richiestaAutorizzazione, .supervisioneNonConcordata, .daChiudereASistema]

            case .daControllare:
                return [.controllata, .daRevisionare]
            
            case .inControllo:
                return [.controllata]
            
            case .controllata:
                return [.inGestione, .periziaDaEseguire, .chiusa, .richiestaRevisione, .daChiudereASistema]
            
            case .richiestaAutorizzazione:
                return [.chiusa, .controllata, .inGestione, .daChiudereASistema]
            
            case .supervisioneNonConcordata:
                return [.chiusa, .controllata, .inGestione, .daChiudereASistema]
            
            case .sopralluogoFissato:
                return [.sopralluogoRestituito, .sopralluogoDaConcordare, .periziaDaEseguire]
            
            case .sopralluogoRestituito:
                return [.sopralluogoDaFissare, .sopralluogoDaConcordare, .sopralluogoFissato]

            case .sopralluogoDaFissare:
                return [.sopralluogoFissato, .sopralluogoDaConcordare]

            case .sopralluogoDaConcordare:
                return [.sopralluogoDaFissare, .sopralluogoFissato]

            case .chiusa:
                return [.richiestaRevisione, .daRevisionare]
            
            case .richiestaRevisione:
                return [.inGestione, .chiusa]

            case .daRevisionare:
                return [.daChiudereASistema, .inGestione, .chiusa]

            case .daChiudereASistema:
                return [.chiusa]
            
            case .revocata:
                return [.istruzione]
            
            case .annullata:
                return []
            }
        }
    }
    
    // Struttura per gli stati personalizzati
    struct CustomState: Codable, Identifiable {
        let id: String          // SP[xxx]
        var descrizione: String
        var icon: String
        var color: String
        var isActive: Bool      // Indica se lo stato è attualmente utilizzabile
        var lastUsed: Date?     // Ultima volta che lo stato è stato usato
        
        init(id: String, descrizione: String, icon: String, color: String) {
            self.id = id
            self.descrizione = descrizione
            self.icon = icon
            self.color = color
            self.isActive = true
            self.lastUsed = nil
        }
    }
    
    // Struttura per le personalizzazioni degli stati di sistema
    private struct StateCustomization: Codable {
        var icon: String
        var color: String
    }
    
    @Published private var customizations: [String: StateCustomization] = [:]
    @Published private var customStates: [CustomState] = []
    @Published private var updateCounter = 0
    
    private let customStatesKey = "customStates"
    private let customizationsKey = "stateCustomizations"
    
    private var nextCustomStateId: String {
        let existingIds = customStates.map { $0.id }
        var counter = 1
        var newId: String
        
        repeat {
            newId = String(format: "SP%03d", counter)
            counter += 1
        } while existingIds.contains(newId)
        
        return newId
    }
    
    init() {
        loadCustomStates()
        loadCustomizations()
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        // Osserva quando viene aggiunto un tag "atto_da_firmare" per cambiare lo stato
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAttoDaFirmareTagged(_:)),
            name: .attoDaFirmareTagged,
            object: nil
        )
    }
    
    @objc private func handleAttoDaFirmareTagged(_ notification: Notification) {
        guard let filePath = notification.userInfo?["filePath"] as? String else { return }
        
        // Estrai il riferimento sinistro dal path
        let riferimento = extractRiferimentoFromPath(filePath)
        guard let riferimento = riferimento else {
            print("[StatoManager] ⚠️ Impossibile estrarre riferimento dal path: \(filePath)")
            return
        }
        
        // Trova il sinistro corrispondente
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        request.fetchLimit = 1
        
        guard let sinistro = try? context.fetch(request).first else {
            print("[StatoManager] ⚠️ Sinistro non trovato per riferimento: \(riferimento)")
            return
        }
        
        // Verifica se la transizione a "attoDaInviare" è valida
        let currentStateDesc = sinistro.stato ?? ""
        guard let currentStateId = getStatoId(fromDescrizione: currentStateDesc),
              let currentState = StatoSinistro(rawValue: currentStateId) else {
            print("[StatoManager] ⚠️ Stato corrente non riconosciuto: \(currentStateDesc)")
            return
        }
        
        // Verifica se la transizione è valida
        if currentState.validTransitions.contains(.attoDaInviare) {
            Task {
                do {
                    try await changeState(for: sinistro, to: .attoDaInviare, context: context, skipValidation: true)
                    print("[StatoManager] ✅ Stato cambiato in 'Atto da inviare' per sinistro \(riferimento)")
                } catch {
                    print("[StatoManager] ❌ Errore cambio stato: \(error)")
                }
            }
        } else {
            print("[StatoManager] ⏭️ Transizione a 'attoDaInviare' non valida da stato: \(currentState.descrizione)")
        }
    }
    
    /// Estrae il riferimento sinistro dal path del file
    private func extractRiferimentoFromPath(_ path: String) -> String? {
        // Il path tipico è: .../Pratiche/[riferimento]/...
        // Cerca la cartella "Pratiche" e prendi il nome della cartella successiva
        let components = path.components(separatedBy: "/")
        if let praticheIndex = components.firstIndex(of: "Pratiche"),
           praticheIndex + 1 < components.count {
            return components[praticheIndex + 1]
        }
        return nil
    }
    
    private func loadCustomStates() {
        if let data = UserDefaults.standard.data(forKey: customStatesKey),
           let decoded = try? JSONDecoder().decode([CustomState].self, from: data) {
            customStates = decoded
        }
    }
    
    private func saveCustomStates() {
        if let encoded = try? JSONEncoder().encode(customStates) {
            UserDefaults.standard.set(encoded, forKey: customStatesKey)
        }
        updateCounter += 1
        objectWillChange.send()
    }
    
    private func loadCustomizations() {
        if let data = UserDefaults.standard.data(forKey: customizationsKey),
           let decoded = try? JSONDecoder().decode([String: StateCustomization].self, from: data) {
            customizations = decoded
        }
    }
    
    private func saveCustomizations() {
        if let encoded = try? JSONEncoder().encode(customizations) {
            UserDefaults.standard.set(encoded, forKey: customizationsKey)
        }
        updateCounter += 1
        objectWillChange.send()
    }
    
    func addCustomState(descrizione: String, icon: String, color: Color) {
        let newId = nextCustomStateId
        let newState = CustomState(
            id: newId,
            descrizione: descrizione,
            icon: icon,
            color: color.toHex() ?? "#000000"
        )
        
        customStates.append(newState)
        saveCustomStates()
    }
    
    func deactivateCustomState(_ stateId: String) {
        if let index = customStates.firstIndex(where: { $0.id == stateId }) {
            var state = customStates[index]
            state.isActive = false
            state.lastUsed = Date()
            customStates[index] = state
            saveCustomStates()
        }
    }
    
    func reactivateCustomState(_ stateId: String) {
        if let index = customStates.firstIndex(where: { $0.id == stateId }) {
            var state = customStates[index]
            state.isActive = true
            customStates[index] = state
            saveCustomStates()
        }
    }
    
    func updateStateIcon(for stato: StatoSinistro, newIcon: String) {
        guard stato.isCustomizable else { return }
        
        let currentCustomization = customizations[stato.id] ?? StateCustomization(
            icon: stato.icon,
            color: stato.color.toHex() ?? "#000000"
        )
        
        customizations[stato.id] = StateCustomization(
            icon: newIcon,
            color: currentCustomization.color
        )
        
        saveCustomizations()
    }
    
    func updateStateColor(for stato: StatoSinistro, newColor: Color) {
        guard stato.isCustomizable else { return }
        
        let currentCustomization = customizations[stato.id] ?? StateCustomization(
            icon: stato.icon,
            color: stato.color.toHex() ?? "#000000"
        )
        
        customizations[stato.id] = StateCustomization(
            icon: currentCustomization.icon,
            color: newColor.toHex() ?? "#000000"
        )
        
        saveCustomizations()
    }
    
    // Helper per ottenere tutti gli stati disponibili
    var availableStates: [StatoInfo] {
        var states = StatoSinistro.allCases
            .filter { $0.isVisible || $0.isSystem }
            .map { stato in
            StatoInfo(
                id: stato.id,
                descrizione: stato.descrizione,
                icon: stato.icon,
                color: stato.color,
                isSystem: true,
                isActive: true,
                requiredRole: stato.requiredRole
            )
            }
        
        // Aggiungi gli stati personalizzati attivi
        states.append(contentsOf: customStates
            .filter { $0.isActive }
            .map { stato in
                StatoInfo(
                    id: stato.id,
                    descrizione: stato.descrizione,
                    icon: stato.icon,
                    color: Color(hex: stato.color) ?? .gray,
                    isSystem: false,
                    isActive: true,
                    requiredRole: .expert
                )
            })
        
        return states
    }
    
    // Helper per ottenere tutti gli stati, inclusi quelli disattivati
    var allStates: [StatoInfo] {
        var states = availableStates
        
        // Aggiungi gli stati personalizzati disattivati
        states.append(contentsOf: customStates
            .filter { !$0.isActive }
            .map { stato in
                StatoInfo(
                    id: stato.id,
                    descrizione: stato.descrizione,
                    icon: stato.icon,
                    color: Color(hex: stato.color) ?? .gray,
                    isSystem: false,
                    isActive: false,
                    requiredRole: .expert
                )
            })
        
        return states
    }
    
    struct StatoInfo: Identifiable, Equatable {
        let id: String
        let descrizione: String
        let icon: String
        let color: Color
        let isSystem: Bool
        let isActive: Bool
        let requiredRole: UserRole
        
        static func == (lhs: StatoInfo, rhs: StatoInfo) -> Bool {
            lhs.id == rhs.id &&
            lhs.descrizione == rhs.descrizione &&
            lhs.icon == rhs.icon &&
            lhs.isSystem == rhs.isSystem &&
            lhs.isActive == rhs.isActive &&
            lhs.requiredRole == rhs.requiredRole
        }
    }
    
    var availableCustomStates: [CustomState] {
        customStates.filter { $0.isActive }
    }
    
    var allAvailableStates: [StatoInfo] {
        var states = StatoSinistro.allCases.map { stato in
            StatoInfo(
                id: stato.id,
                descrizione: stato.descrizione,
                icon: stato.icon,
                color: stato.color,
                isSystem: true,
                isActive: true,
                requiredRole: stato.requiredRole
            )
        }
        
        states.append(contentsOf: customStates.filter { $0.isActive }.map { stato in
            StatoInfo(
                id: stato.id,
                descrizione: stato.descrizione,
                icon: stato.icon,
                color: Color(hex: stato.color) ?? .gray,
                isSystem: false,
                isActive: stato.isActive,
                requiredRole: .expert
            )
        })
        
        return states
    }
    
    func updateCustomStateIcon(_ id: String, newIcon: String) {
        if let index = customStates.firstIndex(where: { $0.id == id }) {
            var stato = customStates[index]
            stato.icon = newIcon
            customStates[index] = stato
            saveCustomStates()
            objectWillChange.send()
        }
    }
    
    func updateCustomStateColor(_ id: String, newColor: Color) {
        if let index = customStates.firstIndex(where: { $0.id == id }) {
            var stato = customStates[index]
            stato.color = newColor.toHex() ?? "#000000"
            customStates[index] = stato
            saveCustomStates()
            objectWillChange.send()
        }
    }
    
    // Metodo per migrare i vecchi stati ai nuovi
    func migrateOldStates() {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        
        do {
            let sinistri = try context.fetch(request)
            for sinistro in sinistri {
                if let oldStato = sinistro.stato {
                    // Mappa i vecchi stati ai nuovi
                    switch oldStato {
                    case "Chiuso":
                        sinistro.stato = StatoSinistro.chiusa.descrizione
                    case "In Gestione":
                        sinistro.stato = StatoSinistro.inGestione.descrizione
                    case "Da Scaricare":
                        sinistro.stato = StatoSinistro.istruzione.descrizione
                    case "Atto Inviato":
                        sinistro.stato = StatoSinistro.attoInviato.descrizione
                    case "Revocato":
                        sinistro.stato = StatoSinistro.revocata.descrizione
                    default:
                        // Se lo stato non è riconosciuto, cerca una corrispondenza nelle descrizioni
                        if let matchingState = StatoSinistro.allCases.first(where: { $0.descrizione.lowercased() == oldStato.lowercased() }) {
                            sinistro.stato = matchingState.descrizione
                        }
                    }
                }
            }
            try context.save()
        } catch {
            print("Errore durante la migrazione degli stati: \(error)")
        }
    }
    
    // Helper per ottenere la descrizione corretta dello stato
    func getStatoDescrizione(_ statoId: String) -> String {
        if let stato = StatoSinistro.allCases.first(where: { $0.id == statoId }) {
            return stato.descrizione
        }
        return statoId
    }
    
    // Helper per ottenere l'ID dello stato dalla descrizione
    func getStatoId(fromDescrizione descrizione: String) -> String? {
        if let stato = StatoSinistro.allCases.first(where: { $0.descrizione == descrizione }) {
            return stato.id
        }
        return nil
    }

    @MainActor
    func canCurrentUserAccess(state: StatoSinistro) -> Bool {
        let roles = CurrentUserService.shared.currentRoles
        return state.isAccessible(to: roles)
    }

    @MainActor
    func canCurrentUserAccess(stateInfo: StatoInfo) -> Bool {
        if let state = StatoSinistro(rawValue: stateInfo.id) {
            return canCurrentUserAccess(state: state)
        }
        let roles = CurrentUserService.shared.currentRoles
        if roles.contains(.admin) { return true }
        return roles.contains(stateInfo.requiredRole)
    }
    
    /// Verifica se una transizione è permessa con validazioni condizionali
    /// - Parameters:
    ///   - from: Stato di partenza
    ///   - to: Stato di destinazione
    ///   - sinistro: Il sinistro per cui verificare le condizioni
    ///   - context: Context per eventuali query
    /// - Returns: true se la transizione è permessa, false altrimenti
    func canTransition(
        from: StatoSinistro,
        to: StatoSinistro,
        for sinistro: Sinistro,
        context: NSManagedObjectContext
    ) -> Bool {
        // Verifica base: la transizione deve essere nelle validTransitions
        guard from.validTransitions.contains(to) else {
            return false
        }
        
        // Validazioni condizionali specifiche
        switch to {
        case .inAttesaDocumentale:
            // Solo se è stata inviata mail "richiesta documentazione"
            // Questa validazione sarà fatta nei handler che chiamano changeState
            // Qui restituiamo true se la transizione base è valida
            return true
            
        case .periziaDaEseguireDocumentale:
            // Solo se stato precedente era "in attesa documentale"
            let currentStateDesc = sinistro.stato ?? ""
            let currentStateId = getStatoId(fromDescrizione: currentStateDesc)
            let currentState = currentStateId.flatMap { StatoSinistro(rawValue: $0) }
            return currentState == .inAttesaDocumentale
            
        case .videoperiziaFissata:
            // Solo da "videoperizia da fissare"
            let currentStateDesc = sinistro.stato ?? ""
            let currentStateId = getStatoId(fromDescrizione: currentStateDesc)
            let currentState = currentStateId.flatMap { StatoSinistro(rawValue: $0) }
            return currentState == .videoperiziaDaFissare
            
        case .attoDaInviare:
            // Solo quando esiste file "atto da firmare" in cartella
            // Questa validazione sarà fatta nel servizio che rileva il file
            return true
            
        case .richiestaRevisione:
            // Solo da "chiusa"
            let currentStateDesc = sinistro.stato ?? ""
            let currentStateId = getStatoId(fromDescrizione: currentStateDesc)
            let currentState = currentStateId.flatMap { StatoSinistro(rawValue: $0) }
            return currentState == .chiusa
            
        case .supervisioneNonConcordata:
            // Solo se la definizione del sinistro è "non concordata"
            return isDefinizioneNonConcordata(sinistro)
            
        default:
            return true
        }
    }
    
    /// Verifica se la definizione del sinistro è "non concordata"
    private func isDefinizioneNonConcordata(_ sinistro: Sinistro) -> Bool {
        guard let definizione = sinistro.definizione?.uppercased() else { return false }
        return definizione.starts(with: "NON CONCORDATO") || definizione.contains("NON CONCORDAT")
    }
    
    /// Verifica se uno stato può essere usato come stato iniziale
    func isInitialState(_ state: StatoSinistro) -> Bool {
        switch state {
        case .istruzione:
            return true
        default:
            return false
        }
    }
    
    // MARK: - Risoluzione Automatica Variante
    
    /// Determina la variante corretta di uno stato in base al contesto del sinistro.
    /// Chiamare questo metodo quando si vuole passare a uno stato "generico" (es. .inGestione)
    /// e si vuole che il sistema scelga automaticamente la variante appropriata.
    /// - Parameters:
    ///   - targetGroup: Il gruppo di stato desiderato
    ///   - sinistro: Il sinistro per cui determinare la variante
    /// - Returns: Lo stato specifico (con variante) da usare
    func resolveStateVariant(for targetGroup: StateGroup, sinistro: Sinistro) -> StatoSinistro {
        // Determina il "tipo" del sinistro dal suo storico/contesto
        let isVideoperizia = detectIsVideoperizia(sinistro)
        let isDocumentale = detectIsDocumentale(sinistro)
        let isNoResidui = detectIsNoResidui(sinistro)
        
        switch targetGroup {
        case .inGestione:
            if isVideoperizia { return .inGestioneVideoperizia }
            if isDocumentale { return .inGestioneDocumentale }
            return .inGestione
            
        case .periziaDaEseguire:
            if isDocumentale { return .periziaDaEseguireDocumentale }
            if isNoResidui { return .periziaDaEseguireNoResidui }
            return .periziaDaEseguire
            
        case .inAttesa:
            // Per "in attesa" la variante dipende da chi si attende risposta
            // Default a documentale (richiesta documentazione)
            return .inAttesaDocumentale
            
        default:
            // Per gruppi senza varianti, restituisci il primo membro
            return targetGroup.members.first ?? .istruzione
        }
    }
    
    /// Determina la variante corretta basandosi sullo stato di partenza.
    /// Utile per transizioni automatiche che devono "ereditare" la variante.
    func resolveStateVariant(for targetGroup: StateGroup, fromCurrentState currentState: StatoSinistro) -> StatoSinistro {
        // Eredita la variante dallo stato corrente se compatibile
        let currentVariant = currentState.variant
        
        switch targetGroup {
        case .inGestione:
            switch currentVariant {
            case .videoperizia: return .inGestioneVideoperizia
            case .documentale: return .inGestioneDocumentale
            default: return .inGestione
            }
            
        case .periziaDaEseguire:
            switch currentVariant {
            case .documentale: return .periziaDaEseguireDocumentale
            case .noResidui: return .periziaDaEseguireNoResidui
            default: return .periziaDaEseguire
            }
            
        default:
            return targetGroup.members.first ?? .istruzione
        }
    }
    
    // MARK: - Rilevamento Tipo Sinistro
    
    /// Rileva se il sinistro è di tipo videoperizia
    private func detectIsVideoperizia(_ sinistro: Sinistro) -> Bool {
        // 1. Verifica stato corrente/precedente
        if let statoDesc = sinistro.stato {
            let statoLower = statoDesc.lowercased()
            if statoLower.contains("videoperizia") || statoLower.contains("video") {
                return true
            }
        }
        
        // 2. Verifica diario per tracce di videoperizia
        let diario = sinistro.diarioArray
        for entry in diario {
            let testo = (entry.testo + (entry.contenutoCompleto ?? "")).lowercased()
            if testo.contains("videoperizia") || testo.contains("video call") || testo.contains("videocall") {
                return true
            }
        }
        
        // 3. Verifica complessità (se impostata come "videoperizia")
        if sinistro.complessita?.lowercased().contains("video") == true {
            return true
        }
        
        return false
    }
    
    /// Rileva se il sinistro è di tipo documentale (senza sopralluogo fisico)
    private func detectIsDocumentale(_ sinistro: Sinistro) -> Bool {
        // 1. Verifica stato corrente/precedente
        if let statoDesc = sinistro.stato {
            let statoLower = statoDesc.lowercased()
            if statoLower.contains("documentale") {
                return true
            }
        }
        
        // 2. Verifica sopralluogo (se false → potenzialmente documentale)
        // Ma attenzione: sopralluogo = false può significare anche "non ancora deciso"
        // Quindi usiamo solo se c'è evidenza positiva
        
        // 3. Verifica diario
        let diario = sinistro.diarioArray
        for entry in diario {
            let testo = (entry.testo + (entry.contenutoCompleto ?? "")).lowercased()
            if testo.contains("perizia documentale") || testo.contains("senza sopralluogo") {
                return true
            }
        }
        
        // 4. Verifica complessità
        if sinistro.complessita?.lowercased().contains("documentale") == true {
            return true
        }
        
        return false
    }
    
    /// Rileva se il sinistro è senza residui (beni già sostituiti/riparati)
    private func detectIsNoResidui(_ sinistro: Sinistro) -> Bool {
        // 1. Verifica stato corrente
        if let statoDesc = sinistro.stato {
            if statoDesc.lowercased().contains("no residui") {
                return true
            }
        }
        
        // 2. Verifica diario
        let diario = sinistro.diarioArray
        for entry in diario {
            let testo = (entry.testo + (entry.contenutoCompleto ?? "")).lowercased()
            if testo.contains("no residui") || testo.contains("senza residui") || 
               testo.contains("beni non più presenti") || testo.contains("già sostituiti") {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Helper per Gruppi
    
    /// Restituisce tutti gli stati che appartengono a un gruppo
    func statesInGroup(_ group: StateGroup) -> [StatoSinistro] {
        group.members
    }

    func currentCATInspectionWorkflowStage(for sinistro: Sinistro) -> CATInspectionWorkflowStage? {
        CATInspectionWorkflowStage(substateValue: sinistro.substate) ??
        stateEnum(for: sinistro)?.catInspectionWorkflowStage
    }

    func operationalEntryState(for sinistro: Sinistro) -> StatoSinistro {
        sinistro.sopralluogo ? .sopralluogoDaFissare : .inAttesaDocumentale
    }

    func startCATAutomaticScheduling(
        for sinistro: Sinistro,
        context: NSManagedObjectContext,
        userEmail: String? = nil
    ) async throws {
        sinistro.sopralluogo = true
        try await changeState(
            for: sinistro,
            to: .sopralluogoDaFissare,
            context: context,
            userEmail: userEmail
        )
    }

    func markCATSchedulingForManualAgreement(
        for sinistro: Sinistro,
        context: NSManagedObjectContext,
        userEmail: String? = nil
    ) async throws {
        sinistro.sopralluogo = true
        try await changeState(
            for: sinistro,
            to: .sopralluogoDaConcordare,
            context: context,
            userEmail: userEmail
        )
    }

    func confirmCATAppointment(
        for sinistro: Sinistro,
        scheduledAt: Date? = nil,
        context: NSManagedObjectContext,
        userEmail: String? = nil
    ) async throws {
        sinistro.sopralluogo = true
        if let scheduledAt {
            sinistro.dataSopralluogo = scheduledAt
        }
        try await changeState(
            for: sinistro,
            to: .sopralluogoFissato,
            context: context,
            userEmail: userEmail
        )
    }

    func completeCATInspection(
        for sinistro: Sinistro,
        completedAt: Date? = nil,
        context: NSManagedObjectContext,
        userEmail: String? = nil
    ) async throws {
        if let completedAt {
            sinistro.dataSopralluogo = completedAt
        }
        try await changeState(
            for: sinistro,
            to: .periziaDaEseguire,
            context: context,
            userEmail: userEmail
        )
    }
    
    /// Restituisce le descrizioni di tutti gli stati in un gruppo (per filtri)
    func stateDescriptionsInGroup(_ group: StateGroup) -> [String] {
        group.members.map { $0.descrizione }
    }
    
    /// Conta i sinistri per gruppo (somma di tutte le varianti)
    func countSinistri(inGroup group: StateGroup, from sinistri: [Sinistro]) -> Int {
        let descriptions = stateDescriptionsInGroup(group)
        return sinistri.filter { descriptions.contains($0.stato ?? "") }.count
    }

    private func stateEnum(for sinistro: Sinistro) -> StatoSinistro? {
        guard let stato = sinistro.stato,
              let stateID = getStatoId(fromDescrizione: stato) else { return nil }
        return StatoSinistro(rawValue: stateID)
    }
    
    // MARK: - Filtri per Tipo Perizia (Documentale vs Tradizionale)
    
    /// Restituisce gli stati disponibili filtrati in base al tipo di perizia del sinistro
    /// - Parameter isTradizionale: true se il sinistro prevede sopralluogo (ha cartella Sopralluogo)
    /// - Returns: Array di stati compatibili con il tipo di perizia
    func availableStatesForTipoPerizia(isTradizionale: Bool) -> [StatoSinistro] {
        return StatoSinistro.allCases.filter { $0.isCompatible(withTipoPerizia: isTradizionale) }
    }
    
    /// Restituisce le transizioni valide filtrate in base al tipo di perizia
    /// - Parameters:
    ///   - state: Lo stato corrente
    ///   - isTradizionale: true se il sinistro prevede sopralluogo
    /// - Returns: Transizioni valide e compatibili con il tipo di perizia
    func validTransitionsForTipoPerizia(from state: StatoSinistro, isTradizionale: Bool) -> [StatoSinistro] {
        return state.validTransitions.filter { $0.isCompatible(withTipoPerizia: isTradizionale) }
    }
    
    /// Aggiorna lo stato del sinistro quando cambia il tipo di perizia (da documentale a tradizionale o viceversa)
    /// Questo metodo dovrebbe essere chiamato quando:
    /// - Si rileva la cartella "Sopralluogo" (documentale → tradizionale)
    /// - Si esegue un sopralluogo su un sinistro originariamente documentale
    /// - Si rimuove la cartella "Sopralluogo" (tradizionale → documentale)
    /// - Parameter sinistro: Il sinistro di cui è cambiato il tipo
    /// - Parameter isTradizionale: Il nuovo tipo di perizia (true = tradizionale con sopralluogo)
    /// - Parameter context: Il contesto Core Data
    func handleTipoPeriziaChanged(
        for sinistro: Sinistro,
        isTradizionale: Bool,
        context: NSManagedObjectContext
    ) async throws {
        guard let currentStateDesc = sinistro.stato,
              let currentStateId = getStatoId(fromDescrizione: currentStateDesc),
              let currentState = StatoSinistro(rawValue: currentStateId) else {
            print("[StatoManager] ⚠️ Impossibile determinare stato corrente per cambio tipo perizia")
            return
        }
        
        // Verifica se lo stato corrente è compatibile con il nuovo tipo
        if currentState.isCompatible(withTipoPerizia: isTradizionale) {
            print("[StatoManager] ✅ Stato '\(currentState.descrizione)' già compatibile con tipo perizia \(isTradizionale ? "tradizionale" : "documentale")")
            return
        }
        
        // Trova lo stato equivalente per il nuovo tipo di perizia
        guard let equivalentState = currentState.equivalentState(forTipoPerizia: isTradizionale) else {
            print("[StatoManager] ⚠️ Nessuno stato equivalente trovato per '\(currentState.descrizione)' → tipo \(isTradizionale ? "tradizionale" : "documentale")")
            return
        }
        
        // Aggiorna il flag sopralluogo
        sinistro.sopralluogo = isTradizionale
        
        // Esegui il cambio stato
        print("[StatoManager] 🔄 Cambio tipo perizia: \(currentState.descrizione) → \(equivalentState.descrizione)")
        
        try await changeState(
            for: sinistro,
            to: equivalentState,
            context: context,
            skipValidation: true // Skip perché è un cambio di variante, non una transizione normale
        )
        
        // Notifica il cambio tipo perizia
        await MainActor.run {
            NotificationCenter.default.post(
                name: .tipoPeriziaChanged,
                object: nil,
                userInfo: [
                    "sinistroID": sinistro.riferimento ?? "",
                    "isTradizionale": isTradizionale,
                    "oldState": currentState.descrizione,
                    "newState": equivalentState.descrizione
                ]
            )
        }
    }
    
    /// Verifica e aggiorna automaticamente lo stato quando viene rilevata la cartella Sopralluogo
    /// Chiamare questo metodo dopo aver sincronizzato/scaricato la cartella del sinistro
    /// - Parameters:
    ///   - sinistro: Il sinistro da verificare
    ///   - hasSopralluogoFolder: true se è stata rilevata la cartella "Sopralluogo"
    ///   - hasFoto: true se sono presenti foto nella cartella
    ///   - context: Il contesto Core Data
    func updateStateBasedOnFolderStructure(
        for sinistro: Sinistro,
        hasSopralluogoFolder: Bool,
        hasFoto: Bool,
        context: NSManagedObjectContext
    ) async throws {
        let previousIsTradizionale = sinistro.sopralluogo
        let newIsTradizionale = hasSopralluogoFolder
        
        // Se il tipo non è cambiato, non fare nulla
        guard previousIsTradizionale != newIsTradizionale else {
            print("[StatoManager] ℹ️ Tipo perizia invariato (\(newIsTradizionale ? "tradizionale" : "documentale"))")
            return
        }
        
        // Il tipo è cambiato, aggiorna lo stato
        if newIsTradizionale {
            // Da documentale a tradizionale (rilevata cartella Sopralluogo)
            print("[StatoManager] 📁 Rilevata cartella 'Sopralluogo' → Cambio a TRADIZIONALE")
            try await handleTipoPeriziaChanged(for: sinistro, isTradizionale: true, context: context)
        } else {
            // Da tradizionale a documentale (rimossa cartella Sopralluogo - caso raro)
            print("[StatoManager] 📁 Cartella 'Sopralluogo' rimossa → Cambio a DOCUMENTALE")
            try await handleTipoPeriziaChanged(for: sinistro, isTradizionale: false, context: context)
            
            // Se documentale e mancano le foto, metti in attesa documentale
            if !hasFoto {
                guard let currentStateDesc = sinistro.stato,
                      let currentStateId = getStatoId(fromDescrizione: currentStateDesc),
                      let currentState = StatoSinistro(rawValue: currentStateId) else { return }
                
                // Se è in uno stato di "perizia da eseguire", cambia in "in attesa documentale"
                if currentState.stateGroup == .periziaDaEseguire {
                    try await changeState(
                        for: sinistro,
                        to: .inAttesaDocumentale,
                        context: context,
                        skipValidation: true
                    )
                    print("[StatoManager] 📷 Foto mancanti → Stato cambiato in 'In attesa (documentale)'")
                }
            }
        }
    }
    
    // MARK: - Change State con Risoluzione Automatica
    
    /// Cambia lo stato risolvendo automaticamente la variante corretta in base al contesto del sinistro.
    /// Usare questo metodo quando si vuole passare a uno stato "generico" (es. "in gestione")
    /// e lasciare che il sistema scelga la variante appropriata.
    /// - Parameters:
    ///   - sinistro: Il sinistro da aggiornare
    ///   - targetGroup: Il gruppo di stato desiderato
    ///   - context: Contesto Core Data
    ///   - userEmail: Email utente per logging
    func changeStateToGroup(
        for sinistro: Sinistro,
        to targetGroup: StateGroup,
        context: NSManagedObjectContext,
        userEmail: String? = nil
    ) async throws {
        // Risolvi la variante corretta
        let resolvedState = resolveStateVariant(for: targetGroup, sinistro: sinistro)
        
        // Esegui il cambio stato
        try await changeState(
            for: sinistro,
            to: resolvedState,
            context: context,
            userEmail: userEmail,
            skipValidation: false
        )
        
        print("[StatoManager] 🎯 Stato risolto automaticamente: \(targetGroup.shortLabel) → \(resolvedState.descrizione)")
    }
    
    /// Cambia lo stato ereditando la variante dallo stato corrente quando appropriato.
    /// Utile per transizioni che devono mantenere il "tipo" di perizia (documentale, videoperizia, ecc.)
    func changeStatePreservingVariant(
        for sinistro: Sinistro,
        to targetGroup: StateGroup,
        context: NSManagedObjectContext,
        userEmail: String? = nil
    ) async throws {
        // Ottieni lo stato corrente
        let currentStateDesc = sinistro.stato ?? ""
        let currentStateId = getStatoId(fromDescrizione: currentStateDesc)
        let currentState = currentStateId.flatMap { StatoSinistro(rawValue: $0) } ?? .istruzione
        
        // Risolvi la variante ereditando dal corrente
        let resolvedState = resolveStateVariant(for: targetGroup, fromCurrentState: currentState)
        
        // Esegui il cambio stato
        try await changeState(
            for: sinistro,
            to: resolvedState,
            context: context,
            userEmail: userEmail,
            skipValidation: false
        )
        
        print("[StatoManager] 🔄 Stato con variante ereditata: \(currentState.descrizione) → \(resolvedState.descrizione)")
    }
    
    /// Cambia lo stato di un sinistro, aggiornando le date, memorizzando nei metadati e avviando la lettura Excel quando necessario
    func changeState(
        for sinistro: Sinistro,
        to newState: StatoSinistro,
        context: NSManagedObjectContext,
        userEmail: String? = nil,
        skipValidation: Bool = false
    ) async throws {
        let oldStateDesc = sinistro.stato ?? "Non specificato"
        let oldStateId = getStatoId(fromDescrizione: oldStateDesc)
        let oldStateEnum = oldStateId.flatMap { StatoSinistro(rawValue: $0) }
        let oggi = Date()
        
        // Snapshot owner/assegnatario prima di eventuali modifiche (serve per revoca/trasferimenti)
        let previousOwnerEmail = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let previousOwnerName = sinistro.assignedToUserName?.trimmingCharacters(in: .whitespacesAndNewlines)

        if userEmail != nil {
            let currentRoles = await MainActor.run { CurrentUserService.shared.currentRoles }
            let isCATWorkflowCompletion =
                currentRoles.contains(.cat) &&
                oldStateEnum?.isCATInspectionWorkflowState == true &&
                newState == .periziaDaEseguire

            guard newState.isAccessible(to: currentRoles) || isCATWorkflowCompletion else {
                let errorMsg = "Ruolo non autorizzato per lo stato \(newState.descrizione)"
                print("[StatoManager] ❌ \(errorMsg)")
                throw NSError(domain: "StatoManager", code: 3, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
        }
        
        // Valida la transizione se lo stato precedente è noto
        if let oldState = oldStateEnum, !skipValidation {
            // Verifica validazione base
            guard oldState.validTransitions.contains(newState) else {
                let errorMsg = "Transizione non permessa: da \(oldState.descrizione) a \(newState.descrizione)"
                print("[StatoManager] ❌ \(errorMsg)")
                throw NSError(domain: "StatoManager", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
            
            // Verifica validazioni condizionali
            guard canTransition(from: oldState, to: newState, for: sinistro, context: context) else {
                let errorMsg = "Transizione condizionale non soddisfatta: da \(oldState.descrizione) a \(newState.descrizione)"
                print("[StatoManager] ❌ \(errorMsg)")
                throw NSError(domain: "StatoManager", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
        }
        
        // Aggiorna lo stato
        sinistro.stato = newState.descrizione
        
        // Gestione speciale: se si passa da "chiusa" a "richiesta revisione", rimuovi dataChiusura
        if let oldState = oldStateEnum, oldState == .chiusa && newState == .richiestaRevisione {
            sinistro.dataChiusura = nil
            print("[StatoManager] 🔄 Data chiusura rimossa (passaggio da chiusa a richiesta revisione)")
        }
        
        // Se si esce dallo stato "revocata", pulisci metadati di revoca (se presenti)
        if oldStateEnum == .revocata, newState != .revocata,
           sinistro.substate?.hasPrefix("revocationFrom=") == true {
            sinistro.substate = nil
        }
        
        // Aggiorna le date in base al nuovo stato
        switch newState {
        case .sopralluogoDaFissare:
            sinistro.sopralluogo = true
            if oldStateEnum?.isCATInspectionWorkflowState != true {
                sinistro.dataSopralluogo = nil
            }
            sinistro.substate = CATInspectionWorkflowStage.automaticSchedulingInProgress.substateValue

        case .sopralluogoDaConcordare:
            sinistro.sopralluogo = true
            sinistro.substate = CATInspectionWorkflowStage.manualSchedulingRequired.substateValue

        case .sopralluogoFissato:
            sinistro.sopralluogo = true
            sinistro.substate = CATInspectionWorkflowStage.scheduledAwaitingVisit.substateValue

        case .sopralluogoRestituito:
            sinistro.sopralluogo = true
            sinistro.substate = CATInspectionWorkflowStage.replanningRequired.substateValue

        case .periziaDaEseguire:
            if oldStateEnum?.isCATInspectionWorkflowState == true {
                sinistro.assignedToUserEmail = nil
                sinistro.assignedToUserName = nil
                sinistro.ownerEmail = nil
                sinistro.dataAssegnazione = nil
                sinistro.substate = CATInspectionWorkflowStage.expertAssignmentPending.substateValue
            } else if CATInspectionWorkflowStage(substateValue: sinistro.substate) != nil {
                sinistro.substate = nil
            }

        case .attoInviato:
            // Atto inviato → valorizza dataInvioAtto (sovrascrive sempre)
            sinistro.dataInvioAtto = oggi
            print("[StatoManager] 📅 dataInvioAtto aggiornata a \(oggi) per stato \(newState.descrizione)")
            
        case .esitoComunicato:
            // Esito comunicato → valorizza dataComunicazioneEsito (e dataInvioAtto per retrocompatibilità)
            sinistro.dataComunicazioneEsito = oggi
            sinistro.dataInvioAtto = oggi // Retrocompatibilità
            print("[StatoManager] 📅 dataComunicazioneEsito aggiornata a \(oggi) per stato \(newState.descrizione)")
            
        case .attoRicevutoSottoscritto:
            // Atto ricevuto sottoscritto → valorizza dataRitornoAtto e dataRicezioneAttoSottoscritto
            sinistro.dataRitornoAtto = oggi
            sinistro.dataRicezioneAttoSottoscritto = oggi
            print("[StatoManager] 📅 dataRitornoAtto/dataRicezioneAttoSottoscritto aggiornate a \(oggi)")
            
        case .accettataVerbalmente:
            // Accettazione verbale → valorizza dataAccettazioneVerbale
            sinistro.dataAccettazioneVerbale = oggi
            print("[StatoManager] 📅 dataAccettazioneVerbale aggiornata a \(oggi)")
            
        case .chiusa:
            if sinistro.dataChiusura == nil {
                sinistro.dataChiusura = oggi
            }
            
        case .revocata:
            if sinistro.dataRevoca == nil {
                sinistro.dataRevoca = oggi
            }
            
            // Revoca = disassegnazione dell'owner/assegnatario corrente
            let actorEmail = userEmail?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            
            let revokedFromEmail = previousOwnerEmail ?? actorEmail
            let revokedFromName: String? = {
                if let n = previousOwnerName, !n.isEmpty { return n }
                guard let e = revokedFromEmail, let local = e.split(separator: "@").first else { return nil }
                return String(local).replacingOccurrences(of: ".", with: " ").capitalized
            }()
            
            // Persistiamo un minimo di info per "passaggio owner" al reincarico (usiamo substate, già syncato)
            let safeEmail = revokedFromEmail ?? ""
            let safeName = revokedFromName ?? ""
            sinistro.substate = "revocationFrom=\(safeEmail)|\(safeName)"
            
            sinistro.assignedToUserEmail = nil
            sinistro.assignedToUserName = nil
            sinistro.ownerEmail = nil
            
            let revokedDisplay = (revokedFromName?.isEmpty == false ? revokedFromName : revokedFromEmail) ?? "perito"
            sinistro.addDiarioEntry(
                DiarioEntry(
                    testo: "Sinistro revocato a \(revokedDisplay)",
                    tipo: .assegnazione,
                    createdByEmail: actorEmail ?? revokedFromEmail
                )
            )
            
        case .inGestione, .inGestioneDocumentale, .inGestioneVideoperizia:
            if sinistro.dataAssegnazione == nil {
                sinistro.dataAssegnazione = oggi
            }

        case .istruzione:
            if sinistro.dataCreazione == nil {
                sinistro.dataCreazione = oggi
            }
            
        default:
            if oldStateEnum?.isCATInspectionWorkflowState == true,
               newState.isCATInspectionWorkflowState == false,
               newState != .periziaDaEseguire,
               CATInspectionWorkflowStage(substateValue: sinistro.substate) != nil {
                sinistro.substate = nil
            }
            break
        }
        
        // MARK: - Gestione Cicli di Controllo
        
        // Stati di CONTROLLO (tutti gli stati che fanno parte di un ciclo di controllo)
        let statiControllo: [StatoSinistro: CicloControllo.TipoControllo] = [
            .inControllo: .inControllo,
            .richiestaAutorizzazione: .richiestaAutorizzazione,
            .supervisioneNonConcordata: .supervisioneNonConcordata
        ]
        
        // Stati di USCITA controllo (stati che chiudono un ciclo)
        let statiUscitaControllo: [StatoSinistro: CicloControllo.TipoUscitaControllo] = [
            .controllata: .controllata,
            .chiusa: .chiusa,
            .attoInviato: .attoInviato,
            .esitoComunicato: .esitoComunicato,
            .inGestione: .inGestione,
            .inGestioneDocumentale: .inGestione,
            .inGestioneVideoperizia: .inGestione
        ]
        
        let venivaDaControllo = oldStateEnum.flatMap { statiControllo[$0] } != nil
        let vaInControllo = statiControllo[newState] != nil
        
        if vaInControllo {
            if let tipoNuovo = statiControllo[newState] {
                if venivaDaControllo {
                    // Transizione tra stati di controllo → aggiorna il tipo del ciclo aperto
                    sinistro.aggiornaTipoControllo(tipo: tipoNuovo)
                } else {
                    // Entrata in controllo da stato non-controllo → apri nuovo ciclo
                    sinistro.registraEntrataControllo(tipo: tipoNuovo)
                }
            }
        } else if venivaDaControllo {
            // Uscita da controllo → chiudi il ciclo
            let tipoUscita = statiUscitaControllo[newState] ?? .altro
            sinistro.registraUscitaControllo(tipo: tipoUscita)
        }
        
        // Crea entry nel diario per memorizzare il cambio stato
        let userName = userEmail?.components(separatedBy: "@").first?.capitalized ?? "Sistema"
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "it_IT")
        let dataOra = dateFormatter.string(from: oggi)
        
        let notaTesto = "Stato cambiato da \"\(oldStateDesc)\" a \"\(newState.descrizione)\""
        let contenutoCompleto = "Utente: \(userName)\nAvvenimento: \(notaTesto)\nData e ora: \(dataOra)"
        
        let diarioEntry = DiarioEntry(
            timestamp: oggi,
            tipo: .cambioStato,
            titolo: "Cambio Stato",
            riassunto: notaTesto,
            contenutoCompleto: contenutoCompleto
        )
        
        sinistro.addDiarioEntry(diarioEntry)
        
        // Aggiorna il timestamp CloudKit per evitare che il server sovrascriva modifiche locali
        sinistro.cloudKitLastModified = oggi
        
        // Salva le modifiche sul main thread per evitare crash con FetchRequest
        // Il viewContext deve essere salvato sempre sul main thread
        try await MainActor.run {
            guard context.hasChanges else { return }
            try context.save()
        }
        
        // Notifica cambio stato sul main thread
        await MainActor.run {
            NotificationCenter.default.post(
                name: .sinistroStatoChanged,
                object: nil,
                userInfo: [
                    "sinistroID": sinistro.riferimento ?? "",
                    "oldState": oldStateEnum as Any,
                    "newState": newState
                ]
            )
        }
        
        // Avvia la lettura Excel per "atto inviato" e "chiusa"
        if newState == .attoInviato || newState == .chiusa {
            Task {
                do {
                    print("[StatoManager] 📊 Avvio lettura Excel per sinistro \(sinistro.riferimento ?? "N/A") - stato: \(newState.descrizione)")
                    let excelURL = try await ExcelFinderService.shared.findElaboratoPeritale(forSinistro: sinistro)
                    print("[StatoManager] ✅ Trovato file Excel: \(excelURL.lastPathComponent)")
                    await AutoCheckService.shared.readAndUpdateExcel(excelURL: excelURL, sinistro: sinistro)
                    print("[StatoManager] ✅ Lettura Excel completata per sinistro \(sinistro.riferimento ?? "N/A")")
                } catch {
                    print("[StatoManager] ⚠️ Errore nella lettura Excel per sinistro \(sinistro.riferimento ?? "N/A"): \(error.localizedDescription)")
                }
            }
        }
        
        // Genera automaticamente i file di chiusura quando lo stato diventa "chiusa"
        if newState == .chiusa {
            generateClosureFilesForSinistro(sinistro)
        }
    }
    
    // MARK: - Generazione File Chiusura
    
    /// Genera automaticamente i file di chiusura e invia notifica se ci sono problemi
    private func generateClosureFilesForSinistro(_ sinistro: Sinistro) {
        print("[StatoManager] 📁 Avvio generazione file di chiusura per \(sinistro.riferimento ?? "N/A")")
        
        // Verifica prima i file mancanti
        Task { @MainActor in
            let missingFiles = await ClosureFilesService.shared.checkMissingEssentialFiles(for: sinistro)
            if !missingFiles.isEmpty {
                print("[StatoManager] ⚠️ File essenziali mancanti: \(missingFiles)")
                NotificationService.shared.sendMissingFilesNotification(sinistro: sinistro, missingFiles: missingFiles)
            }
            
            // Genera i file
            ClosureFilesService.shared.generateClosureFiles(for: sinistro) { result in
                if !result.errors.isEmpty {
                    print("[StatoManager] ❌ Errori generazione file: \(result.errors)")
                    NotificationService.shared.sendClosureErrorNotification(sinistro: sinistro, errors: result.errors)
                } else {
                    print("[StatoManager] ✅ File di chiusura generati: \(result.generatedFiles.count) file")
                    // Notifica solo in caso di successo se ci sono file generati
                    NotificationCenter.default.post(
                        name: .closureFilesGenerated,
                        object: nil,
                        userInfo: [
                            "sinistroID": sinistro.riferimento ?? "",
                            "files": result.generatedFiles
                        ]
                    )
                }
            }
        }
    }
    
    // MARK: - Helper Methods for Task System
    
    /// Ottiene lo stato attuale di un sinistro come enum
    func getCurrentState(sinistro: Sinistro) -> StatoSinistro {
        guard let statoDesc = sinistro.stato else { return .istruzione }
        return StatoSinistro.allCases.first { $0.descrizione == statoDesc } ?? .istruzione
    }
    
    /// Ottiene lo stato attuale di un sinistro tramite ID
    @MainActor
    func getCurrentState(sinistroID: String) -> StatoSinistro? {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
        
        guard let sinistro = try? context.fetch(request).first else { return nil }
        return getCurrentState(sinistro: sinistro)
    }
}

// Estensione per le notifiche
extension Notification.Name {
    static let sinistroStatoChanged = Notification.Name("sinistroStatoChanged")
    static let sinistroUpdated = Notification.Name("sinistroUpdated")
    static let sinistroCreated = Notification.Name("sinistroCreated")
    static let taskCreated = Notification.Name("taskCreated")
    static let emailReceived = Notification.Name("emailReceived")
    static let emailSent = Notification.Name("emailSent")
    static let documentationReceived = Notification.Name("documentationReceived")
    static let emailAssociated = Notification.Name("emailAssociated")
    static let workScheduleChanged = Notification.Name("workScheduleChanged")
    static let attoDaFirmareTagged = Notification.Name("attoDaFirmareTagged")
    static let closureFilesGenerated = Notification.Name("closureFilesGenerated")
    static let claimFolderChanged = Notification.Name("claimFolderChanged")
    /// Emessa quando un sinistro con sync attiva passa a chiuso e richiede decisione utente
    static let sinistroClosedNeedsSyncDecision = Notification.Name("sinistroClosedNeedsSyncDecision")
    /// Emessa quando un file o cartella viene eliminato (spostato nel cestino)
    static let fileOrFolderDeleted = Notification.Name("fileOrFolderDeleted")
    /// Emessa quando cambia il tipo di perizia di un sinistro (documentale ↔ tradizionale)
    static let tipoPeriziaChanged = Notification.Name("tipoPeriziaChanged")
} 
