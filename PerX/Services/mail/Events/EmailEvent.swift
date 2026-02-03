import Foundation

// MARK: - Email Event Protocol

/// Protocollo base per tutti gli eventi email
/// Ogni evento rappresenta un'azione rilevata dal MailManager
/// che verrà processata dal ClaimEngine
protocol EmailEvent {
    var eventId: UUID { get }
    var timestamp: Date { get }
    var emailId: String { get }
    var sinistroId: String? { get }
    var direction: EmailDirection { get }
    var metadata: [String: Any] { get }
}

// MARK: - Email Direction

enum EmailDirection: String, Codable {
    case inbound = "IN"
    case outbound = "OUT"
}

// MARK: - Sender Type (per discriminare solleciti)

enum EmailSenderType: String, Codable {
    case insured = "insured"           // Assicurato
    case agency = "agency"             // Agenzia
    case studio = "studio"             // Studio peritale (noi)
    case company = "company"           // Compagnia (info@actsrl.it)
    case liquidator = "liquidator"     // Liquidatore
    case broker = "broker"             // Broker
    case unknown = "unknown"
}

// MARK: - Base Event Implementation

/// Struttura base che implementa EmailEvent con valori comuni
struct BaseEmailEvent: EmailEvent {
    let eventId: UUID
    let timestamp: Date
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection
    let metadata: [String: Any]
    
    init(
        emailId: String,
        sinistroId: String?,
        direction: EmailDirection,
        metadata: [String: Any] = [:]
    ) {
        self.eventId = UUID()
        self.timestamp = Date()
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.direction = direction
        self.metadata = metadata
    }
}

// MARK: - Assignment Events

/// Nuova perizia assegnata
struct EmailAssignmentReceived: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection = .inbound
    let metadata: [String: Any]
    
    /// Data di assegnazione estratta dall'email
    let assignmentDate: Date
    /// Riferimento sinistro estratto
    let riferimento: String
    /// Email assegnatario (chi riceve la mail di assegnazione)
    let assigneeEmail: String?
    /// Nome assegnatario (per UI)
    let assigneeName: String?
    /// Dati estratti dall'email (nome, telefono, ecc.)
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

// MARK: - Revocation Events

/// Perizia revocata
struct EmailRevocationReceived: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection = .inbound
    let metadata: [String: Any]
    
    /// Riferimento sinistro revocato
    let riferimento: String
    /// Motivo della revoca (se presente)
    let reason: String?
    
    init(emailId: String, riferimento: String, reason: String? = nil) {
        self.emailId = emailId
        self.sinistroId = riferimento
        self.riferimento = riferimento
        self.reason = reason
        self.metadata = [
            "reason": reason ?? ""
        ]
    }
}

// MARK: - Act Events

/// Atto firmato ricevuto
struct EmailSignedActReceived: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection = .inbound
    let metadata: [String: Any]
    
    /// Tipo di atto (liquidazione, accertamento, ecc.)
    let actType: String?
    /// URL degli allegati
    let attachmentURLs: [URL]
    
    init(emailId: String, sinistroId: String?, actType: String? = nil, attachmentURLs: [URL] = []) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.actType = actType
        self.attachmentURLs = attachmentURLs
        self.metadata = [
            "actType": actType ?? "",
            "attachmentCount": attachmentURLs.count
        ]
    }
}

/// Atto da firmare inviato
struct EmailActToSignSent: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection = .outbound
    let metadata: [String: Any]
    
    /// Tipo di atto inviato
    let actType: String?
    /// Destinatari
    let recipients: [String]
    
    init(emailId: String, sinistroId: String?, actType: String? = nil, recipients: [String] = []) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.actType = actType
        self.recipients = recipients
        self.metadata = [
            "actType": actType ?? "",
            "recipients": recipients
        ]
    }
}

// MARK: - Reminder Events

/// Sollecito ricevuto (con tipo mittente)
struct EmailReminderReceived: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection = .inbound
    let metadata: [String: Any]
    
    /// Tipo di mittente del sollecito
    let senderType: EmailSenderType
    /// Oggetto del sollecito
    let subject: String
    
    init(emailId: String, sinistroId: String?, senderType: EmailSenderType, subject: String) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.senderType = senderType
        self.subject = subject
        self.metadata = [
            "senderType": senderType.rawValue,
            "subject": subject
        ]
    }
}

/// Convenience per solleciti specifici
typealias EmailInsuredReminderReceived = EmailReminderReceived
typealias EmailAgencyReminderReceived = EmailReminderReceived
typealias EmailBrokerReminderReceived = EmailReminderReceived
typealias EmailStudioReminderReceived = EmailReminderReceived
typealias EmailCompanyReminderReceived = EmailReminderReceived

/// Sollecito inviato
struct EmailReminderSent: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection = .outbound
    let metadata: [String: Any]
    
    /// Destinatari
    let recipients: [String]
    /// Tipo di sollecito (documentazione, atto, ecc.)
    let reminderType: String
    /// Tipo di destinatario (agenzia o broker)
    let recipientType: EmailSenderType?
    
    init(emailId: String, sinistroId: String?, recipients: [String], reminderType: String, recipientType: EmailSenderType? = nil) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.recipients = recipients
        self.reminderType = reminderType
        self.recipientType = recipientType
        var metadataDict: [String: Any] = [
            "recipients": recipients,
            "reminderType": reminderType
        ]
        if let recipientType = recipientType {
            metadataDict["recipientType"] = recipientType.rawValue
        }
        self.metadata = metadataDict
    }
}

// MARK: - Documentation Events

/// Documentazione ricevuta
struct EmailDocumentationReceived: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection = .inbound
    let metadata: [String: Any]
    
    /// Numero di allegati
    let attachmentCount: Int
    /// Tipi di allegati (pdf, jpg, ecc.)
    let attachmentTypes: [String]
    /// Mittente
    let senderType: EmailSenderType
    
    init(emailId: String, sinistroId: String?, attachmentCount: Int, attachmentTypes: [String], senderType: EmailSenderType) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.attachmentCount = attachmentCount
        self.attachmentTypes = attachmentTypes
        self.senderType = senderType
        self.metadata = [
            "attachmentCount": attachmentCount,
            "attachmentTypes": attachmentTypes,
            "senderType": senderType.rawValue
        ]
    }
}

/// Richiesta documentazione
struct EmailDocumentationRequested: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection
    let metadata: [String: Any]
    
    /// Tipo di documentazione richiesta
    let documentationType: String?
    /// Richiedente (noi o compagnia)
    let requestedBy: EmailSenderType
    
    init(emailId: String, sinistroId: String?, direction: EmailDirection, documentationType: String? = nil, requestedBy: EmailSenderType) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.direction = direction
        self.documentationType = documentationType
        self.requestedBy = requestedBy
        self.metadata = [
            "documentationType": documentationType ?? "",
            "requestedBy": requestedBy.rawValue
        ]
    }
}

// MARK: - Survey Events

/// Sopralluogo fissato
struct EmailSurveyScheduled: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection
    let metadata: [String: Any]
    
    /// Data/ora del sopralluogo (se estratta)
    let scheduledDate: Date?
    /// Indirizzo del sopralluogo
    let address: String?
    
    init(emailId: String, sinistroId: String?, direction: EmailDirection, scheduledDate: Date? = nil, address: String? = nil) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.direction = direction
        self.scheduledDate = scheduledDate
        self.address = address
        self.metadata = [
            "scheduledDate": scheduledDate?.description ?? "",
            "address": address ?? ""
        ]
    }
}

/// Sopralluogo restituito
struct EmailSurveyReturned: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection = .inbound
    let metadata: [String: Any]
    
    init(emailId: String, sinistroId: String?) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.metadata = [:]
    }
}

/// Videoperizia fissata
struct EmailVideocallScheduled: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection
    let metadata: [String: Any]
    
    /// Data/ora della videoperizia
    let scheduledDate: Date?
    /// Link della videochiamata
    let meetingLink: String?
    
    init(emailId: String, sinistroId: String?, direction: EmailDirection, scheduledDate: Date? = nil, meetingLink: String? = nil) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.direction = direction
        self.scheduledDate = scheduledDate
        self.meetingLink = meetingLink
        self.metadata = [
            "scheduledDate": scheduledDate?.description ?? "",
            "meetingLink": meetingLink ?? ""
        ]
    }
}

// MARK: - Clarification Events

/// Richiesta chiarimenti
struct EmailClarificationRequested: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection
    let metadata: [String: Any]
    
    /// Chi ha richiesto i chiarimenti
    let requestedBy: EmailSenderType
    /// Argomento dei chiarimenti
    let topic: String?
    
    init(emailId: String, sinistroId: String?, direction: EmailDirection, requestedBy: EmailSenderType, topic: String? = nil) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.direction = direction
        self.requestedBy = requestedBy
        self.topic = topic
        self.metadata = [
            "requestedBy": requestedBy.rawValue,
            "topic": topic ?? ""
        ]
    }
}

// MARK: - Control & Revision Events

/// Perizia controllata
struct EmailControlled: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection = .inbound
    let metadata: [String: Any]
    
    /// Esito del controllo (approvata, da rivedere, ecc.)
    let outcome: String?
    
    init(emailId: String, sinistroId: String?, outcome: String? = nil) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.outcome = outcome
        self.metadata = [
            "outcome": outcome ?? ""
        ]
    }
}

/// Richiesta revisione
struct EmailRevisionRequested: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection = .inbound
    let metadata: [String: Any]
    
    /// Motivo della revisione
    let reason: String?
    /// Priorità (se indicata)
    let priority: String?
    
    init(emailId: String, sinistroId: String?, reason: String? = nil, priority: String? = nil) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.reason = reason
        self.priority = priority
        self.metadata = [
            "reason": reason ?? "",
            "priority": priority ?? ""
        ]
    }
}

// MARK: - Outcome Events

/// Esito comunicato
struct EmailOutcomeSent: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection = .outbound
    let metadata: [String: Any]
    
    /// Tipo di esito
    let outcomeType: String?
    /// Destinatari
    let recipients: [String]
    
    init(emailId: String, sinistroId: String?, outcomeType: String? = nil, recipients: [String] = []) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.outcomeType = outcomeType
        self.recipients = recipients
        self.metadata = [
            "outcomeType": outcomeType ?? "",
            "recipients": recipients
        ]
    }
}

// MARK: - Generic Event

/// Comunicazione generica (non classificata in modo specifico)
struct EmailGenericCommunicationReceived: EmailEvent {
    let eventId: UUID = UUID()
    let timestamp: Date = Date()
    let emailId: String
    let sinistroId: String?
    let direction: EmailDirection
    let metadata: [String: Any]
    
    /// Oggetto dell'email
    let subject: String
    /// Mittente
    let sender: String
    /// Ha allegati
    let hasAttachments: Bool
    
    init(emailId: String, sinistroId: String?, direction: EmailDirection, subject: String, sender: String, hasAttachments: Bool) {
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.direction = direction
        self.subject = subject
        self.sender = sender
        self.hasAttachments = hasAttachments
        self.metadata = [
            "subject": subject,
            "sender": sender,
            "hasAttachments": hasAttachments
        ]
    }
}

