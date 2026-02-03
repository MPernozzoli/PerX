import Foundation

// MARK: - ClaimEvent Protocol

/// Protocollo base per tutti gli eventi del sistema
/// Ogni evento rappresenta un'azione rilevata da un manager (Mail, WhatsApp, Diario)
/// che verrà processata dal ClaimEngine
protocol ClaimEvent {
    var eventId: UUID { get }
    var timestamp: Date { get }
    var sinistroId: String? { get }
    var source: ClaimEventSource { get }
    var metadata: [String: Any] { get }
}

// MARK: - Event Source

/// Sorgente dell'evento
enum ClaimEventSource: String, Codable {
    case email = "email"
    case whatsApp = "whatsapp"
    case userNote = "user_note"
    case system = "system"
}

// MARK: - Event Direction

/// Direzione della comunicazione
enum ClaimEventDirection: String, Codable {
    case inbound = "IN"
    case outbound = "OUT"
    case internal_ = "INTERNAL"
}

// MARK: - Sender Type

/// Tipo di mittente
enum ClaimEventSenderType: String, Codable {
    case insured = "insured"           // Assicurato
    case agency = "agency"             // Agenzia
    case studio = "studio"             // Studio peritale (noi)
    case company = "company"           // Compagnia
    case liquidator = "liquidator"     // Liquidatore
    case broker = "broker"             // Broker
    case user = "user"                 // Utente interno (nota manuale)
    case unknown = "unknown"
}

// MARK: - Event Intent

/// Intento rilevato dall'evento
enum ClaimEventIntent: String, Codable {
    case assignment = "assignment"             // Nuova assegnazione
    case revocation = "revocation"             // Revoca
    case documentation = "documentation"       // Documentazione ricevuta
    case documentationRequest = "doc_request"  // Richiesta documentazione
    case reminder = "reminder"                 // Sollecito
    case actSent = "act_sent"                  // Atto inviato
    case actReceived = "act_received"          // Atto ricevuto firmato
    case outcomeSent = "outcome_sent"          // Esito comunicato
    case verbalAcceptance = "verbal_acceptance" // Accettazione verbale
    case surveyScheduled = "survey_scheduled"  // Sopralluogo fissato
    case surveyReturned = "survey_returned"    // Sopralluogo restituito
    case videocallScheduled = "videocall"      // Videoperizia fissata
    case clarification = "clarification"       // Richiesta chiarimenti
    case control = "control"                   // Controllo perizia
    case revision = "revision"                 // Richiesta revisione
    case userTask = "user_task"                // Task da nota utente (@task)
    case userAction = "user_action"            // Azione da nota utente (@azione)
    case userReference = "user_reference"      // Riferimento da nota utente (@[...])
    case generic = "generic"                   // Comunicazione generica
}

// MARK: - Base Event Implementation

/// Implementazione base di ClaimEvent
struct BaseClaimEvent: ClaimEvent {
    let eventId: UUID
    let timestamp: Date
    let sinistroId: String?
    let source: ClaimEventSource
    let metadata: [String: Any]
    
    init(
        sinistroId: String?,
        source: ClaimEventSource,
        metadata: [String: Any] = [:]
    ) {
        self.eventId = UUID()
        self.timestamp = Date()
        self.sinistroId = sinistroId
        self.source = source
        self.metadata = metadata
    }
}

// MARK: - Email Events

/// Evento email generico
struct EmailClaimEvent: ClaimEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let sinistroId: String?
    let source: ClaimEventSource = .email
    let metadata: [String: Any]
    
    /// ID dell'email originale
    let emailId: String
    /// Direzione (in/out)
    let direction: ClaimEventDirection
    /// Intento rilevato
    let intent: ClaimEventIntent
    /// Tipo mittente
    let senderType: ClaimEventSenderType
    /// Oggetto email
    let subject: String
    /// Ha allegati
    let hasAttachments: Bool
    /// Numero allegati
    let attachmentCount: Int
    
    init(
        emailId: String,
        sinistroId: String?,
        direction: ClaimEventDirection,
        intent: ClaimEventIntent,
        senderType: ClaimEventSenderType,
        subject: String,
        hasAttachments: Bool = false,
        attachmentCount: Int = 0,
        metadata: [String: Any] = [:]
    ) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.direction = direction
        self.intent = intent
        self.senderType = senderType
        self.subject = subject
        self.hasAttachments = hasAttachments
        self.attachmentCount = attachmentCount
        self.metadata = metadata
    }
}

/// Evento assegnazione email
struct EmailAssignmentEvent: ClaimEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let sinistroId: String?
    let source: ClaimEventSource = .email
    let metadata: [String: Any]
    
    let emailId: String
    let riferimento: String
    let assignmentDate: Date
    let assigneeEmail: String?
    let assigneeName: String?
    let extractedData: [String: String]
    
    init(
        emailId: String,
        riferimento: String,
        assignmentDate: Date,
        assigneeEmail: String? = nil,
        assigneeName: String? = nil,
        extractedData: [String: String] = [:]
    ) {
        self.emailId = emailId
        self.sinistroId = riferimento
        self.riferimento = riferimento
        self.assignmentDate = assignmentDate
        self.assigneeEmail = assigneeEmail
        self.assigneeName = assigneeName
        self.extractedData = extractedData
        self.metadata = [
            "assignmentDate": assignmentDate,
            "assigneeEmail": assigneeEmail ?? "",
            "assigneeName": assigneeName ?? "",
            "extractedData": extractedData
        ]
    }
}

/// Evento revoca email
struct EmailRevocationEvent: ClaimEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let sinistroId: String?
    let source: ClaimEventSource = .email
    let metadata: [String: Any]
    
    let emailId: String
    let riferimento: String
    let reason: String?
    
    init(emailId: String, riferimento: String, reason: String? = nil) {
        self.emailId = emailId
        self.sinistroId = riferimento
        self.riferimento = riferimento
        self.reason = reason
        self.metadata = ["reason": reason ?? ""]
    }
}

// MARK: - WhatsApp Events

/// Evento WhatsApp generico
struct WhatsAppClaimEvent: ClaimEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let sinistroId: String?
    let source: ClaimEventSource = .whatsApp
    let metadata: [String: Any]
    
    /// ID della chat
    let chatId: String
    /// ID messaggi inclusi
    let messageIds: [String]
    /// Direzione
    let direction: ClaimEventDirection
    /// Intento rilevato
    let intent: ClaimEventIntent
    /// Tipo mittente
    let senderType: ClaimEventSenderType
    /// Ha media allegati
    let hasMedia: Bool
    /// Numero messaggi
    let messageCount: Int
    
    init(
        chatId: String,
        messageIds: [String],
        sinistroId: String?,
        direction: ClaimEventDirection,
        intent: ClaimEventIntent,
        senderType: ClaimEventSenderType,
        hasMedia: Bool = false,
        messageCount: Int = 1,
        metadata: [String: Any] = [:]
    ) {
        self.chatId = chatId
        self.messageIds = messageIds
        self.sinistroId = sinistroId
        self.direction = direction
        self.intent = intent
        self.senderType = senderType
        self.hasMedia = hasMedia
        self.messageCount = messageCount
        self.metadata = metadata
    }
}

// MARK: - User Note Events

/// Tag estratto da nota utente
struct ParsedTag: Codable {
    enum TagType: String, Codable {
        case task = "task"
        case action = "azione"
        case reference = "reference"
    }
    
    enum TimeType: String, Codable {
        case deadline = "deadline"      // "entro le 16" - scadenza
        case scheduledTime = "scheduledTime"  // "alle 14" - orario programmato
    }
    
    let type: TagType
    let body: String
    let deadline: Date?           // Scadenza (quando deve essere completato entro)
    let scheduledTime: Date?      // Orario programmato (quando deve essere eseguito)
    let timeType: TimeType?       // Tipo di tempo: deadline o scheduledTime
    let range: Range<String.Index>?
    
    enum CodingKeys: String, CodingKey {
        case type, body, deadline, scheduledTime, timeType
    }
    
    init(type: TagType, body: String, deadline: Date? = nil, scheduledTime: Date? = nil, timeType: TimeType? = nil, range: Range<String.Index>? = nil) {
        self.type = type
        self.body = body
        self.deadline = deadline
        self.scheduledTime = scheduledTime
        self.timeType = timeType
        self.range = range
    }
    
    // Implementazione manuale di Decodable perché Range<String.Index> non è Codable
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(TagType.self, forKey: .type)
        body = try container.decode(String.self, forKey: .body)
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        scheduledTime = try container.decodeIfPresent(Date.self, forKey: .scheduledTime)
        timeType = try container.decodeIfPresent(TimeType.self, forKey: .timeType)
        range = nil  // Non può essere decodificato
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(deadline, forKey: .deadline)
        try container.encodeIfPresent(scheduledTime, forKey: .scheduledTime)
        try container.encodeIfPresent(timeType, forKey: .timeType)
        // range non viene codificato
    }
}

/// Evento nota utente
struct UserNoteClaimEvent: ClaimEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let sinistroId: String?
    let source: ClaimEventSource = .userNote
    let metadata: [String: Any]
    
    /// Testo completo della nota
    let noteText: String
    /// Tag estratti (@task, @azione, @[riferimento])
    let parsedTags: [ParsedTag]
    /// Intento primario (basato sul primo tag trovato)
    let primaryIntent: ClaimEventIntent
    /// ID dell'entry diario generata
    let diarioEntryId: UUID?
    
    init(
        noteText: String,
        sinistroId: String?,
        parsedTags: [ParsedTag],
        diarioEntryId: UUID? = nil,
        metadata: [String: Any] = [:]
    ) {
        self.noteText = noteText
        self.sinistroId = sinistroId
        self.parsedTags = parsedTags
        self.diarioEntryId = diarioEntryId
        self.metadata = metadata
        
        // Determina intento primario dal primo tag
        if let firstTag = parsedTags.first {
            switch firstTag.type {
            case .task:
                self.primaryIntent = .userTask
            case .action:
                self.primaryIntent = .userAction
            case .reference:
                self.primaryIntent = .userReference
            }
        } else {
            self.primaryIntent = .generic
        }
    }
}

// MARK: - System Events

/// Evento di sistema (cambio stato automatico, trigger interni, etc.)
struct SystemClaimEvent: ClaimEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let sinistroId: String?
    let source: ClaimEventSource = .system
    let metadata: [String: Any]
    
    /// Tipo di evento sistema
    enum SystemEventType: String, Codable {
        case stateChange = "state_change"
        case folderDownloaded = "folder_downloaded"
        case fileTagged = "file_tagged"
        case taskCompleted = "task_completed"
        case deadlineApproaching = "deadline_approaching"
        case syncCompleted = "sync_completed"
    }
    
    let systemEventType: SystemEventType
    let description: String
    
    init(
        systemEventType: SystemEventType,
        sinistroId: String?,
        description: String,
        metadata: [String: Any] = [:]
    ) {
        self.systemEventType = systemEventType
        self.sinistroId = sinistroId
        self.description = description
        self.metadata = metadata
    }
}

// MARK: - Engine Decision

/// Decisione del ClaimEngine dopo l'analisi di un evento
struct ClaimEngineDecision {
    /// Tipo di azione da eseguire
    enum ActionType {
        case none                           // Nessuna azione richiesta
        case autoStateChange                // Cambio stato automatico
        case createTask                     // Crea task manuale
        case createUrgentTask               // Crea task urgente
        case downloadAttachment             // Scarica allegati
        case saveToFolder                   // Salva file in cartella
        case logToDiary                     // Solo log nel diario
        case notifyUser                     // Notifica all'utente
    }
    
    let actionType: ActionType
    let targetState: StatoManager.StatoSinistro?
    let taskTitle: String?
    let taskDescription: String?
    let taskDeadline: Date?
    let taskScheduledTime: Date?
    let priority: Double
    let reason: String
    let additionalMetadata: [String: Any]
    
    // Nuovi campi per sistema goal e invalidazione
    let taskActionType: TaskActionType?
    let taskGoal: TaskGoal?
    let taskInvalidation: TaskInvalidation?
    let taskPriorityLevel: TaskPriorityLevel
    
    init(
        actionType: ActionType,
        targetState: StatoManager.StatoSinistro? = nil,
        taskTitle: String? = nil,
        taskDescription: String? = nil,
        taskDeadline: Date? = nil,
        taskScheduledTime: Date? = nil,
        priority: Double = 0.5,
        reason: String = "",
        additionalMetadata: [String: Any] = [:],
        taskActionType: TaskActionType? = nil,
        taskGoal: TaskGoal? = nil,
        taskInvalidation: TaskInvalidation? = nil,
        taskPriorityLevel: TaskPriorityLevel = .essential
    ) {
        self.actionType = actionType
        self.targetState = targetState
        self.taskTitle = taskTitle
        self.taskDescription = taskDescription
        self.taskDeadline = taskDeadline
        self.taskScheduledTime = taskScheduledTime
        self.priority = priority
        self.reason = reason
        self.additionalMetadata = additionalMetadata
        self.taskActionType = taskActionType
        self.taskGoal = taskGoal
        self.taskInvalidation = taskInvalidation
        self.taskPriorityLevel = taskPriorityLevel
    }
    
    /// Decisione di default: nessuna azione
    static let noAction = ClaimEngineDecision(actionType: .none, reason: "Nessuna azione richiesta")
}

// MARK: - ClaimEngine Result

/// Risultato del processamento di un evento da parte di ClaimEngine
struct ClaimEngineResult {
    /// ID dell'evento processato
    let eventId: UUID
    /// Email ID associato (se disponibile)
    let emailId: String?
    /// Tipo di risultato
    enum ResultType {
        case success                    // Azione completata con successo
        case partialSuccess             // Azione parzialmente completata
        case unexpectedAction          // Azione diversa da quella attesa
        case error                      // Errore durante il processamento
        case ignored                    // Evento ignorato (es. duplicato)
        case timeout                    // Timeout in attesa della risposta
    }
    let resultType: ResultType
    /// Tipo di azione eseguita
    let actionType: ClaimEngineDecision.ActionType
    /// Messaggio descrittivo
    let message: String
    /// Dettagli aggiuntivi
    let details: [String: Any]
    /// Timestamp del risultato
    let timestamp: Date
    
    init(
        eventId: UUID,
        emailId: String? = nil,
        resultType: ResultType,
        actionType: ClaimEngineDecision.ActionType,
        message: String,
        details: [String: Any] = [:]
    ) {
        self.eventId = eventId
        self.emailId = emailId
        self.resultType = resultType
        self.actionType = actionType
        self.message = message
        self.details = details
        self.timestamp = Date()
    }
    
    /// Verifica se il risultato corrisponde all'azione attesa
    func matchesExpectedAction(_ expectedAction: ClaimEngineDecision.ActionType) -> Bool {
        return actionType == expectedAction
    }
}

