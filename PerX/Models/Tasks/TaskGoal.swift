import Foundation

// MARK: - Task Goal Type

/// Tipo di obiettivo per una task
/// Definisce quale evento deve verificarsi per completare automaticamente la task
enum TaskGoalType: String, Codable, CaseIterable {
    case sendReminderEmail      // Inviare sollecito
    case sendActEmail           // Inviare atto
    case receiveActSigned       // Ricevere atto firmato
    case receiveDocumentation   // Ricevere documentazione
    case changeState            // Cambio stato sinistro
    case performCall            // Effettuare chiamata
    case sendEmail              // Inviare email generica
    case attendMeeting          // Partecipare a riunione/videoperizia
    case closeClaim             // Chiudere sinistro
    case requestDocumentation   // Richiedere documentazione
    
    var displayName: String {
        switch self {
        case .sendReminderEmail: return "Inviare sollecito"
        case .sendActEmail: return "Inviare atto"
        case .receiveActSigned: return "Ricevere atto firmato"
        case .receiveDocumentation: return "Ricevere documentazione"
        case .changeState: return "Cambio stato"
        case .performCall: return "Effettuare chiamata"
        case .sendEmail: return "Inviare email"
        case .attendMeeting: return "Partecipare a riunione"
        case .closeClaim: return "Chiudere sinistro"
        case .requestDocumentation: return "Richiedere documentazione"
        }
    }
}

// MARK: - Invalidation Condition

/// Condizione che invalida automaticamente una task
/// Quando una di queste condizioni si verifica, la task viene cancellata silenziosamente
enum InvalidationCondition: String, Codable, CaseIterable {
    case sinistroClosedOrRevoked    // Sinistro chiuso/revocato/annullato
    case stateProgressed            // Stato progredito oltre fase target
    case documentationReceived      // Documentazione ricevuta
    case actReceived                // Atto ricevuto/sottoscritto
    case reminderSent               // Sollecito già inviato
    case emailReplied               // Email già risposta
    case policyReceived             // Polizza ricevuta
    
    var displayName: String {
        switch self {
        case .sinistroClosedOrRevoked: return "Sinistro chiuso/revocato"
        case .stateProgressed: return "Stato progredito"
        case .documentationReceived: return "Documentazione ricevuta"
        case .actReceived: return "Atto ricevuto"
        case .reminderSent: return "Sollecito inviato"
        case .emailReplied: return "Email risposta"
        case .policyReceived: return "Polizza ricevuta"
        }
    }
}

// MARK: - Task Action Type

/// Tipo di azione da compiere per la task
/// Utilizzato per standardizzare i titoli e mostrare tasti contestuali
enum TaskActionType: String, Codable, CaseIterable {
    case call           // "Chiamare"
    case email          // "Scrivere"
    case reply          // "Rispondere"
    case remind         // "Sollecitare"
    case verify         // "Verificare"
    case request        // "Richiedere"
    case attend         // "Partecipare"
    case review         // "Controllare"
    case close          // "Chiudere"
    case send           // "Inviare"
    
    /// Verbo italiano per il titolo standardizzato
    var verb: String {
        switch self {
        case .call: return "Chiamare"
        case .email: return "Scrivere"
        case .reply: return "Rispondere"
        case .remind: return "Sollecitare"
        case .verify: return "Verificare"
        case .request: return "Richiedere"
        case .attend: return "Partecipare"
        case .review: return "Controllare"
        case .close: return "Chiudere"
        case .send: return "Inviare"
        }
    }
    
    /// Nome icona SF Symbol per il tasto contestuale
    var iconName: String {
        switch self {
        case .call: return "phone.fill"
        case .email: return "envelope.fill"
        case .reply: return "arrowshape.turn.up.left.fill"
        case .remind: return "bell.fill"
        case .verify: return "checkmark.circle.fill"
        case .request: return "arrow.down.doc.fill"
        case .attend: return "video.fill"
        case .review: return "doc.text.magnifyingglass"
        case .close: return "lock.fill"
        case .send: return "paperplane.fill"
        }
    }
    
    /// Etichetta per il tasto contestuale
    var buttonLabel: String {
        switch self {
        case .call: return "Chiama"
        case .email: return "Scrivi"
        case .reply: return "Rispondi"
        case .remind: return "Sollecita"
        case .verify: return "Verifica"
        case .request: return "Richiedi"
        case .attend: return "Partecipa"
        case .review: return "Controlla"
        case .close: return "Chiudi"
        case .send: return "Invia"
        }
    }
}

// MARK: - Task Priority Level

/// Livello di priorità per lo scheduling delle task
enum TaskPriorityLevel: String, Codable, CaseIterable {
    case essential  // Task essenziale (alta priorità scheduling)
    case optional   // Task opzionale (bassa priorità scheduling)
    
    var displayName: String {
        switch self {
        case .essential: return "Essenziale"
        case .optional: return "Opzionale"
        }
    }
}

// MARK: - Task Goal

/// Obiettivo di una task
/// Definisce quando la task può essere completata automaticamente
struct TaskGoal: Codable, Equatable {
    /// Tipo di obiettivo
    let type: TaskGoalType
    
    /// Valore target per il completamento (es: riferimento sinistro, stato target, emailId)
    let targetValue: String?
    
    /// Data di completamento (se già completata da evento)
    var completionDate: Date?
    
    /// Fonte del completamento (es: emailId che ha completato la task)
    var completionSource: String?
    
    init(
        type: TaskGoalType,
        targetValue: String? = nil,
        completionDate: Date? = nil,
        completionSource: String? = nil
    ) {
        self.type = type
        self.targetValue = targetValue
        self.completionDate = completionDate
        self.completionSource = completionSource
    }
    
    /// Verifica se l'obiettivo è stato raggiunto
    var isAchieved: Bool {
        return completionDate != nil
    }
    
    static func == (lhs: TaskGoal, rhs: TaskGoal) -> Bool {
        lhs.type == rhs.type &&
        lhs.targetValue == rhs.targetValue &&
        lhs.completionDate == rhs.completionDate &&
        lhs.completionSource == rhs.completionSource
    }
}

// MARK: - Task Invalidation

/// Regole di invalidazione per una task
/// Definisce quando la task deve essere cancellata automaticamente
struct TaskInvalidation: Codable, Equatable {
    /// Condizioni che invalidano la task (basta una per invalidare)
    let conditions: [InvalidationCondition]
    
    /// Stato soglia per la condizione stateProgressed (raw value)
    /// La task si invalida se lo stato progredisce oltre questa soglia
    let stateThreshold: String?
    
    init(
        conditions: [InvalidationCondition],
        stateThreshold: StatoManager.StatoSinistro? = nil
    ) {
        self.conditions = conditions
        self.stateThreshold = stateThreshold?.rawValue
    }
    
    /// Inizializzatore con stato raw value
    init(conditions: [InvalidationCondition], stateThresholdRaw: String?) {
        self.conditions = conditions
        self.stateThreshold = stateThresholdRaw
    }
    
    /// Converte stateThreshold in StatoSinistro
    var stateThresholdEnum: StatoManager.StatoSinistro? {
        guard let raw = stateThreshold else { return nil }
        return StatoManager.StatoSinistro(rawValue: raw)
    }
    
    static func == (lhs: TaskInvalidation, rhs: TaskInvalidation) -> Bool {
        lhs.conditions == rhs.conditions &&
        lhs.stateThreshold == rhs.stateThreshold
    }
}

// MARK: - StatoSinistro Extensions

/// Estensioni per supportare progressione stati
extension StatoManager.StatoSinistro {
    /// Ordine numerico per confronto progressione
    /// Stati con ordine maggiore sono considerati "più avanti" nel flusso
    var progressionOrder: Int {
        switch self {
        // Ingresso (0-9)
        case .daScaricare: return 0
        case .istruzione: return 1
        case .primoContatto: return 2
        case .secondoContatto: return 3
        case .inAttesaAssegnazione: return 4
        case .periziaDaEseguire: return 5
        case .periziaDaEseguireNoResidui: return 5
        case .periziaDaEseguireDocumentale: return 5
        case .videoperiziaDaFissare: return 5
        case .sopralluogoAssegnato: return 6
        case .videoperiziaDaEseguire: return 6
        case .daGestireVideoperizia: return 7
        case .daGestireTradizionale: return 7
        case .daGestireDocumentale: return 7
        case .daGestireNoResidui: return 7
        case .inAttesaDocumentale: return 8
        case .inAttesaDaAssicurato: return 9
        case .inAttesaDaAgenzia: return 9
        case .inAttesaDaTerzi: return 9
        case .attesaPassiva: return 9
        
        // Avanzamento (10-29)
        case .sopralluogoFissato: return 10
        case .sopralluogoRestituito: return 11
        case .videoperiziaFissata: return 12
        case .inGestione: return 15
        case .inGestioneDocumentale: return 15
        case .inGestioneVideoperizia: return 15
        
        // Esito/Atto (30-49)
        case .esitoDaComunicare: return 30
        case .esitoComunicato: return 31
        case .attoDaInviare: return 35
        case .attoInviato: return 40
        case .accettataVerbalmente: return 41
        case .attoRicevutoSottoscritto: return 45
        
        // Controllo (50-59)
        case .daControllare: return 50
        case .inControllo: return 50
        case .controllata: return 51
        case .richiestaAutorizzazione: return 52
        case .supervisioneNonConcordata: return 53
        
        // Chiusura (90+)
        case .daChiudereASistema: return 89
        case .chiusa: return 90
        case .richiestaRevisione: return 91
        case .daRevisionare: return 92
        case .revocata: return 95
        case .annullata: return 96
        }
    }
    
    /// Verifica se questo stato è dopo un altro nella progressione
    func isAfter(_ other: StatoManager.StatoSinistro) -> Bool {
        return self.progressionOrder > other.progressionOrder
    }
    
    /// Verifica se questo stato è uno stato di chiusura
    var isClosureState: Bool {
        switch self {
        case .chiusa, .revocata, .annullata, .richiestaRevisione:
            return true
        default:
            return false
        }
    }
}
