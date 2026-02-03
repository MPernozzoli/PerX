import Foundation

// ============================================================================
// MARK: - Email Event Protocol (copia da PerX/Services/mail/Events/EmailEvent.swift)
// ============================================================================

/// Protocollo base per tutti gli eventi email
/// Ogni evento rappresenta un'azione rilevata dall'EmailProcessor
/// che verrà processata dal ClaimEngine sull'Hub
public protocol EmailEventProtocol: Codable, Sendable {
    var eventId: UUID { get }
    var timestamp: Date { get }
    var emailId: String { get }
    var sinistroId: String? { get }
    var direction: EmailDirection { get }
    var eventType: EmailEventType { get }
}

// MARK: - Event Types

public enum EmailEventType: String, Codable, Sendable, CaseIterable {
    case assignmentReceived = "assignment_received"
    case revocationReceived = "revocation_received"
    case signedActReceived = "signed_act_received"
    case actToSignSent = "act_to_sign_sent"
    case reminderReceived = "reminder_received"
    case reminderSent = "reminder_sent"
    case documentationReceived = "documentation_received"
    case documentationRequested = "documentation_requested"
    case surveyScheduled = "survey_scheduled"
    case surveyReturned = "survey_returned"
    case videocallScheduled = "videocall_scheduled"
    case clarificationRequested = "clarification_requested"
    case controlled = "controlled"
    case revisionRequested = "revision_requested"
    case outcomeSent = "outcome_sent"
    case verbalAcceptance = "verbal_acceptance"
    case genericCommunication = "generic_communication"
}

// ============================================================================
// MARK: - Unified Email Event (per serializzazione/Hub)
// ============================================================================

/// Evento email unificato per l'Hub - contiene tutti i campi possibili
/// e il tipo di evento per discriminare
public struct HubEmailEvent: EmailEventProtocol {
    public let eventId: UUID
    public let timestamp: Date
    public let emailId: String
    public let sinistroId: String?
    public let direction: EmailDirection
    public let eventType: EmailEventType
    
    // Campi specifici per tipo evento
    public let assignmentDate: Date?
    public let riferimento: String?
    public let assigneeEmail: String?
    public let assigneeName: String?
    public let extractedData: [String: String]?
    public let reason: String?
    public let actType: String?
    public let attachmentCount: Int?
    public let attachmentTypes: [String]?
    public let recipients: [String]?
    public let senderType: EmailSenderType?
    public let scheduledDate: Date?
    public let address: String?
    public let meetingLink: String?
    public let topic: String?
    public let outcome: String?
    public let priority: String?
    public let subject: String?
    public let sender: String?
    public let hasAttachments: Bool?
    
    public init(
        eventId: UUID = UUID(),
        timestamp: Date = Date(),
        emailId: String,
        sinistroId: String?,
        direction: EmailDirection,
        eventType: EmailEventType,
        assignmentDate: Date? = nil,
        riferimento: String? = nil,
        assigneeEmail: String? = nil,
        assigneeName: String? = nil,
        extractedData: [String: String]? = nil,
        reason: String? = nil,
        actType: String? = nil,
        attachmentCount: Int? = nil,
        attachmentTypes: [String]? = nil,
        recipients: [String]? = nil,
        senderType: EmailSenderType? = nil,
        scheduledDate: Date? = nil,
        address: String? = nil,
        meetingLink: String? = nil,
        topic: String? = nil,
        outcome: String? = nil,
        priority: String? = nil,
        subject: String? = nil,
        sender: String? = nil,
        hasAttachments: Bool? = nil
    ) {
        self.eventId = eventId
        self.timestamp = timestamp
        self.emailId = emailId
        self.sinistroId = sinistroId
        self.direction = direction
        self.eventType = eventType
        self.assignmentDate = assignmentDate
        self.riferimento = riferimento
        self.assigneeEmail = assigneeEmail
        self.assigneeName = assigneeName
        self.extractedData = extractedData
        self.reason = reason
        self.actType = actType
        self.attachmentCount = attachmentCount
        self.attachmentTypes = attachmentTypes
        self.recipients = recipients
        self.senderType = senderType
        self.scheduledDate = scheduledDate
        self.address = address
        self.meetingLink = meetingLink
        self.topic = topic
        self.outcome = outcome
        self.priority = priority
        self.subject = subject
        self.sender = sender
        self.hasAttachments = hasAttachments
    }
    
    // MARK: - Factory Methods
    
    /// Crea evento di assegnazione ricevuta
    public static func assignmentReceived(
        emailId: String,
        riferimento: String,
        assignmentDate: Date,
        assigneeEmail: String? = nil,
        assigneeName: String? = nil,
        extractedData: [String: String] = [:]
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: riferimento,
            direction: .inbound,
            eventType: .assignmentReceived,
            assignmentDate: assignmentDate,
            riferimento: riferimento,
            assigneeEmail: assigneeEmail,
            assigneeName: assigneeName,
            extractedData: extractedData
        )
    }
    
    /// Crea evento di revoca ricevuta
    public static func revocationReceived(
        emailId: String,
        riferimento: String,
        reason: String? = nil
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: riferimento,
            direction: .inbound,
            eventType: .revocationReceived,
            riferimento: riferimento,
            reason: reason
        )
    }
    
    /// Crea evento di atto firmato ricevuto
    public static func signedActReceived(
        emailId: String,
        sinistroId: String?,
        actType: String? = nil,
        attachmentCount: Int = 0
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: .inbound,
            eventType: .signedActReceived,
            actType: actType,
            attachmentCount: attachmentCount
        )
    }
    
    /// Crea evento di atto inviato
    public static func actToSignSent(
        emailId: String,
        sinistroId: String?,
        actType: String? = nil,
        recipients: [String] = []
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: .outbound,
            eventType: .actToSignSent,
            actType: actType,
            recipients: recipients
        )
    }
    
    /// Crea evento di sollecito ricevuto
    public static func reminderReceived(
        emailId: String,
        sinistroId: String?,
        senderType: EmailSenderType,
        subject: String
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: .inbound,
            eventType: .reminderReceived,
            senderType: senderType,
            subject: subject
        )
    }
    
    /// Crea evento di sollecito inviato
    public static func reminderSent(
        emailId: String,
        sinistroId: String?,
        recipients: [String],
        reason: String? = nil
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: .outbound,
            eventType: .reminderSent,
            reason: reason,
            recipients: recipients
        )
    }
    
    /// Crea evento di documentazione ricevuta
    public static func documentationReceived(
        emailId: String,
        sinistroId: String?,
        attachmentCount: Int,
        attachmentTypes: [String],
        senderType: EmailSenderType
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: .inbound,
            eventType: .documentationReceived,
            attachmentCount: attachmentCount,
            attachmentTypes: attachmentTypes,
            senderType: senderType
        )
    }
    
    /// Crea evento di richiesta documentazione
    public static func documentationRequested(
        emailId: String,
        sinistroId: String?,
        direction: EmailDirection,
        senderType: EmailSenderType
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: direction,
            eventType: .documentationRequested,
            senderType: senderType
        )
    }
    
    /// Crea evento di sopralluogo fissato
    public static func surveyScheduled(
        emailId: String,
        sinistroId: String?,
        direction: EmailDirection,
        scheduledDate: Date? = nil,
        address: String? = nil
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: direction,
            eventType: .surveyScheduled,
            scheduledDate: scheduledDate,
            address: address
        )
    }
    
    /// Crea evento di sopralluogo restituito
    public static func surveyReturned(
        emailId: String,
        sinistroId: String?
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: .inbound,
            eventType: .surveyReturned
        )
    }
    
    /// Crea evento di videoperizia fissata
    public static func videocallScheduled(
        emailId: String,
        sinistroId: String?,
        direction: EmailDirection,
        scheduledDate: Date? = nil,
        meetingLink: String? = nil
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: direction,
            eventType: .videocallScheduled,
            scheduledDate: scheduledDate,
            meetingLink: meetingLink
        )
    }
    
    /// Crea evento di richiesta chiarimenti
    public static func clarificationRequested(
        emailId: String,
        sinistroId: String?,
        direction: EmailDirection,
        senderType: EmailSenderType,
        topic: String? = nil
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: direction,
            eventType: .clarificationRequested,
            senderType: senderType,
            topic: topic
        )
    }
    
    /// Crea evento di perizia controllata
    public static func controlled(
        emailId: String,
        sinistroId: String?,
        outcome: String? = nil
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: .inbound,
            eventType: .controlled,
            outcome: outcome
        )
    }
    
    /// Crea evento di richiesta revisione
    public static func revisionRequested(
        emailId: String,
        sinistroId: String?,
        reason: String? = nil,
        priority: String? = nil
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: .inbound,
            eventType: .revisionRequested,
            reason: reason,
            priority: priority
        )
    }
    
    /// Crea evento di esito comunicato
    public static func outcomeSent(
        emailId: String,
        sinistroId: String?,
        outcome: String? = nil,
        recipients: [String] = []
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: .outbound,
            eventType: .outcomeSent,
            recipients: recipients,
            outcome: outcome
        )
    }
    
    /// Crea evento di accettazione verbale
    public static func verbalAcceptance(
        emailId: String,
        sinistroId: String?
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: .inbound,
            eventType: .verbalAcceptance
        )
    }
    
    /// Crea evento di comunicazione generica
    public static func genericCommunication(
        emailId: String,
        sinistroId: String?,
        direction: EmailDirection,
        subject: String,
        sender: String,
        hasAttachments: Bool
    ) -> HubEmailEvent {
        HubEmailEvent(
            emailId: emailId,
            sinistroId: sinistroId,
            direction: direction,
            eventType: .genericCommunication,
            subject: subject,
            sender: sender,
            hasAttachments: hasAttachments
        )
    }
}
