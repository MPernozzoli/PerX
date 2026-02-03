import Foundation

// ============================================================================
// MARK: - Email Models (copia fedele da PerX/Models/Communication/MailModels.swift)
// ============================================================================

/// Email - modello principale (identico al client)
public struct Email: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var isRead: Bool
    public var isDownloaded: Bool?
    public let sender: Contact
    public let recipients: [Contact]
    public let cc: [Contact]?
    public let subject: String
    public let date: Date
    public var body: String?
    public var attachments: [EmailAttachment]?
    public let claimNumber: String?
    public let insuredName: String?
    public var associationStatus: EmailAssociationStatus?
    
    public init(
        id: String,
        isRead: Bool,
        isDownloaded: Bool? = nil,
        sender: Contact,
        recipients: [Contact],
        cc: [Contact]? = nil,
        subject: String,
        date: Date,
        body: String? = nil,
        attachments: [EmailAttachment]? = nil,
        claimNumber: String? = nil,
        insuredName: String? = nil,
        associationStatus: EmailAssociationStatus? = nil
    ) {
        self.id = id
        self.isRead = isRead
        self.isDownloaded = isDownloaded
        self.sender = sender
        self.recipients = recipients
        self.cc = cc
        self.subject = subject
        self.date = date
        self.body = body
        self.attachments = attachments
        self.claimNumber = claimNumber
        self.insuredName = insuredName
        self.associationStatus = associationStatus
    }
}

/// Allegato email (identico al client)
public struct EmailAttachment: Identifiable, Hashable, Codable, Sendable {
    public var id: String { attachmentId }
    public let attachmentId: String
    public let filename: String
    public let size: Int
    
    public init(attachmentId: String, filename: String, size: Int) {
        self.attachmentId = attachmentId
        self.filename = filename
        self.size = size
    }
}

/// Stato associazione email (identico al client)
public enum EmailAssociationStatus: String, Codable, Sendable {
    case associated
    case maybe
    case unassociated
}

/// Contatto (identico al client)
public struct Contact: Identifiable, Hashable, Codable, Sendable {
    public var id: String { email }
    public let name: String?
    public let email: String
    
    public var displayName: String {
        name ?? email
    }
    
    public init(name: String?, email: String) {
        self.name = name
        self.email = email
    }
}

// ============================================================================
// MARK: - Email Direction (copia da PerX/Services/mail/Events/EmailEvent.swift)
// ============================================================================

public enum EmailDirection: String, Codable, Sendable {
    case inbound = "IN"
    case outbound = "OUT"
}

// ============================================================================
// MARK: - Email Sender Type (copia da PerX/Services/mail/Events/EmailEvent.swift)
// ============================================================================

public enum EmailSenderType: String, Codable, Sendable {
    case insured = "insured"           // Assicurato
    case agency = "agency"             // Agenzia
    case studio = "studio"             // Studio peritale (noi)
    case company = "company"           // Compagnia (info@actsrl.it)
    case liquidator = "liquidator"     // Liquidatore
    case broker = "broker"             // Broker
    case unknown = "unknown"
}

// ============================================================================
// MARK: - Email Category (copia da PerX/Services/mail/Core/EmailCategory.swift)
// ============================================================================

public enum EmailCategory: String, CaseIterable, Codable, Sendable {
    // MARK: - Inbound from Company
    case assignment = "assignment"                    // Assegnazione perito
    case revocation = "revocation"                    // Revoca incarico
    case controlled = "controlled"                    // Perizia controllata
    case revisionRequested = "revision_requested"     // Richiesta revisione
    
    // MARK: - Documentation
    case documentationRequest = "documentation_request"   // Richiesta documentazione
    case documentationReceived = "documentation_received" // Documentazione ricevuta
    
    // MARK: - Reminders
    case reminderReceived = "reminder_received"       // Sollecito ricevuto
    case reminderSent = "reminder_sent"               // Sollecito inviato
    
    // MARK: - Survey
    case surveyScheduled = "survey_scheduled"         // Sopralluogo fissato
    case surveyReturned = "survey_returned"           // Sopralluogo restituito
    case videocallScheduled = "videocall_scheduled"   // Videoperizia fissata
    
    // MARK: - Acts
    case actSent = "act_sent"                         // Atto da firmare inviato
    case actReceived = "act_received"                 // Atto firmato ricevuto
    
    // MARK: - Clarification
    case clarificationRequest = "clarification_request" // Richiesta chiarimenti
    
    // MARK: - Outcome
    case outcomeSent = "outcome_sent"                 // Esito comunicato
    case verbalAcceptance = "verbal_acceptance"       // Accettazione verbale assicurato
    
    // MARK: - Generic
    case genericCommunication = "generic"             // Comunicazione generica
    
    // MARK: - File Notification
    case fileNotification = "file_notification"       // Notifica nuovi file caricati
    
    // MARK: - Studio (non sinistro)
    case studioNews = "studio_news"                   // Notizie dello studio
    case internalInfo = "internal_info"               // Info interne
    case procedure = "procedure"                      // Procedure
    case meeting = "meeting"                          // Riunioni
    case training = "training"                        // Formazione
    case administrative = "administrative"            // Amministrativo (fatture, pagamenti)
    case newsletter = "newsletter"                    // Newsletter
    case spam = "spam"                                // Spam/Pubblicità
    
    /// Indica se la categoria è legata a un sinistro
    public var isSinistroRelated: Bool {
        switch self {
        case .studioNews, .internalInfo, .procedure, .meeting, .training,
             .administrative, .newsletter, .spam:
            return false
        default:
            return true
        }
    }
}

// ============================================================================
// MARK: - Classified Email (copia da PerX/Services/mail/Core/EmailCategory.swift)
// ============================================================================

public struct ClassifiedEmail: Codable, Sendable {
    public let originalEmail: Email
    public let category: EmailCategory
    public let direction: EmailDirection
    public let senderType: EmailSenderType
    public let sinistroId: String?
    public let confidence: Double
    public let matchedPatterns: [String]
    
    public init(
        originalEmail: Email,
        category: EmailCategory,
        direction: EmailDirection,
        senderType: EmailSenderType,
        sinistroId: String?,
        confidence: Double,
        matchedPatterns: [String]
    ) {
        self.originalEmail = originalEmail
        self.category = category
        self.direction = direction
        self.senderType = senderType
        self.sinistroId = sinistroId
        self.confidence = confidence
        self.matchedPatterns = matchedPatterns
    }
    
    /// Email ha allegati
    public var hasAttachments: Bool {
        return originalEmail.attachments?.isEmpty == false
    }
    
    /// Tipi di allegati
    public var attachmentTypes: [String] {
        return originalEmail.attachments?.compactMap { attachment in
            let filename = attachment.filename
            return (filename as NSString).pathExtension.lowercased()
        } ?? []
    }
}

// ============================================================================
// MARK: - Hub Attachment (per processing interno Hub)
// ============================================================================

/// Allegato in processing sull'Hub (esteso rispetto a EmailAttachment base)
public struct HubAttachment: Codable, Identifiable, Sendable {
    public let id: String
    public let messageId: String
    public let filename: String
    public let size: Int64
    public let mimeType: String?
    public var status: AttachmentStatus
    public var vaultFileId: String?
    public var sinistroRef: String?
    public var errorMessage: String?
    public let createdAt: Date
    public var processedAt: Date?
    
    public init(
        id: String = UUID().uuidString,
        messageId: String,
        filename: String,
        size: Int64,
        mimeType: String? = nil,
        status: AttachmentStatus = .pending,
        vaultFileId: String? = nil,
        sinistroRef: String? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        processedAt: Date? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.filename = filename
        self.size = size
        self.mimeType = mimeType
        self.status = status
        self.vaultFileId = vaultFileId
        self.sinistroRef = sinistroRef
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.processedAt = processedAt
    }
}

/// Stato allegato
public enum AttachmentStatus: String, Codable, Sendable {
    case pending        // In attesa di download
    case downloading    // Download in corso
    case downloaded     // Scaricato in temp
    case processing     // In elaborazione (salvataggio vault)
    case saved          // Salvato nel vault
    case error          // Errore
}

/// Email programmata per invio futuro
public struct ScheduledEmail: Codable, Identifiable, Sendable {
    public let id: String
    public let accountId: String
    public let to: [String]
    public let cc: [String]?
    public let subject: String
    public let body: String
    public let attachmentIds: [String]?
    public let scheduledAt: Date
    public var status: ScheduledEmailStatus
    public var sentAt: Date?
    public var errorMessage: String?
    public let createdBy: String?
    public let createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        accountId: String,
        to: [String],
        cc: [String]? = nil,
        subject: String,
        body: String,
        attachmentIds: [String]? = nil,
        scheduledAt: Date,
        status: ScheduledEmailStatus = .pending,
        sentAt: Date? = nil,
        errorMessage: String? = nil,
        createdBy: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.attachmentIds = attachmentIds
        self.scheduledAt = scheduledAt
        self.status = status
        self.sentAt = sentAt
        self.errorMessage = errorMessage
        self.createdBy = createdBy
        self.createdAt = createdAt
    }
}

/// Stato email programmata
public enum ScheduledEmailStatus: String, Codable, Sendable {
    case pending        // In attesa
    case sending        // Invio in corso
    case sent           // Inviata
    case failed         // Fallita
    case cancelled      // Annullata
}

/// Mapping email -> account (per gestire CC/deduplicazione)
public struct EmailAccountMapping: Codable, Sendable {
    public let messageId: String
    public let accountId: String
    public let mailbox: String?
    public var isRead: Bool
    
    public init(messageId: String, accountId: String, mailbox: String? = nil, isRead: Bool = false) {
        self.messageId = messageId
        self.accountId = accountId
        self.mailbox = mailbox
        self.isRead = isRead
    }
}

/// Riferimento email archiviata (per sinistri chiusi)
public struct ArchivedEmailRef: Codable, Sendable {
    public let sinistroRef: String
    public let messageId: String
    public let date: Date
    public let subject: String?
    
    public init(sinistroRef: String, messageId: String, date: Date, subject: String?) {
        self.sinistroRef = sinistroRef
        self.messageId = messageId
        self.date = date
        self.subject = subject
    }
}
