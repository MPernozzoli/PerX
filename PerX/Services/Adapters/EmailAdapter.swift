import Foundation
import Combine

// ============================================================================
// MARK: - EmailAdapter
// Adapter per email - TUTTE le operazioni passano dall'Hub
// Nessun processamento locale - l'Hub gestisce download, classificazione e storage
// ============================================================================

@MainActor
final class EmailAdapter: ObservableObject {
    static let shared = EmailAdapter()
    
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    
    private let hubEmailService = HubEmailService.shared
    private let hubClient = HubAPIAdapterClient.shared
    
    private init() {}
    
    // MARK: - Fetch Emails (sempre da Hub)
    
    /// Recupera email per sinistro
    func getEmails(sinistroRef: String) async throws -> [EmailListItem] {
        isLoading = true
        defer { isLoading = false }
        
        let emails = try await hubEmailService.fetchEmails(forSinistro: sinistroRef)
        return emails.map { EmailListItem(from: $0) }
    }
    
    /// Recupera email per utente
    func getEmails(userEmail: String, limit: Int = 100) async throws -> [EmailListItem] {
        isLoading = true
        defer { isLoading = false }
        
        let emails = try await hubEmailService.fetchEmails(forUser: userEmail, limit: limit)
        return emails.map { EmailListItem(from: $0) }
    }
    
    /// Recupera email per mailbox specifica
    func getEmails(userEmail: String, mailbox: String, limit: Int = 100) async throws -> [EmailListItem] {
        isLoading = true
        defer { isLoading = false }
        
        let emails = try await hubEmailService.fetchEmails(forUser: userEmail, mailbox: mailbox, limit: limit)
        return emails.map { EmailListItem(from: $0) }
    }
    
    /// Recupera dettaglio email
    func getEmailDetail(id: String) async throws -> EmailDetail {
        isLoading = true
        defer { isLoading = false }
        
        let detail = try await hubEmailService.fetchEmailDetail(messageId: id)
        return EmailDetail(from: detail)
    }
    
    /// Recupera mailbox disponibili per utente
    func getMailboxes(userEmail: String) async throws -> [MailboxDTO] {
        isLoading = true
        defer { isLoading = false }
        
        return try await hubEmailService.fetchMailboxes(forUser: userEmail)
    }
    
    // MARK: - Actions
    
    /// Associa email a sinistro
    func associateEmail(_ emailId: String, toSinistro ref: String) async throws {
        try await hubEmailService.associateEmail(messageId: emailId, toSinistro: ref)
    }
    
    /// Marca email come letta
    func markAsRead(_ emailId: String, accountId: String? = nil) async throws {
        try await hubEmailService.markAsRead(messageId: emailId, accountId: accountId)
    }
    
    /// Tagga email
    func tagEmail(_ emailId: String, category: String, sinistroRef: String?) async throws {
        try await hubEmailService.tagEmail(messageId: emailId, category: category, sinistroRef: sinistroRef)
    }
    
    // MARK: - Send Email
    
    /// Invia email immediatamente via Hub
    func sendEmail(
        accountId: String,
        to: [String],
        cc: [String]? = nil,
        bcc: [String]? = nil,
        subject: String,
        body: String,
        isHtml: Bool = true,
        replyToThreadId: String? = nil,
        inReplyTo: String? = nil,
        references: String? = nil,
        attachments: [(filename: String, data: Data, mimeType: String?)]? = nil
    ) async throws -> HubEmailService.SendEmailResponse {
        isLoading = true
        defer { isLoading = false }
        
        return try await hubEmailService.sendEmail(
            accountId: accountId,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            body: body,
            isHtml: isHtml,
            replyToThreadId: replyToThreadId,
            inReplyTo: inReplyTo,
            references: references,
            attachments: attachments
        )
    }
    
    /// Programma invio email
    func scheduleEmail(
        accountId: String,
        to: [String],
        cc: [String]?,
        subject: String,
        body: String,
        scheduledFor: Date,
        sinistroRef: String?
    ) async throws -> ScheduledEmailDTO {
        isLoading = true
        defer { isLoading = false }
        
        return try await hubEmailService.scheduleEmail(
            accountId: accountId,
            to: to,
            cc: cc,
            subject: subject,
            body: body,
            scheduledFor: scheduledFor,
            sinistroRef: sinistroRef
        )
    }
    
    /// Lista email programmate
    func getScheduledEmails(accountId: String) async throws -> [ScheduledEmailDTO] {
        return try await hubEmailService.getScheduledEmails(forAccount: accountId)
    }
    
    /// Cancella email programmata
    func cancelScheduledEmail(id: String) async throws {
        try await hubEmailService.cancelScheduledEmail(id: id)
    }
    
    // MARK: - Sync
    
    /// Avvia polling email in background
    func startPolling(userEmail: String, interval: TimeInterval = 60) {
        hubEmailService.startPolling(userEmail: userEmail, interval: interval)
    }
    
    /// Ferma polling
    func stopPolling() {
        hubEmailService.stopPolling()
    }
    
    /// Sync manuale
    func syncEmails(userEmail: String) async {
        await hubEmailService.syncUserEmails(userEmail: userEmail)
    }
}

// MARK: - View Models

struct EmailListItem: Identifiable {
    let id: String
    let subject: String
    let senderEmail: String
    let senderName: String?
    let date: Date
    let category: String
    let sinistroRef: String?
    let direction: String?
    let mailbox: String?
    let isRead: Bool
    
    init(from dto: EmailDTO) {
        self.id = dto.id
        self.subject = dto.subject
        self.senderEmail = dto.senderEmail
        self.senderName = dto.senderName
        self.date = dto.date
        self.category = dto.category
        self.sinistroRef = dto.sinistroRef
        self.direction = dto.direction
        self.mailbox = dto.mailbox
        self.isRead = dto.isRead ?? true
    }
    
    init(from email: Email) {
        self.id = email.id
        self.subject = email.subject
        self.senderEmail = email.sender.email
        self.senderName = email.sender.name
        self.date = email.date
        self.category = "generic"
        self.sinistroRef = nil
        self.direction = nil
        self.mailbox = nil
        self.isRead = email.isRead
    }
}

struct EmailDetail: Identifiable {
    let id: String
    let subject: String
    let senderEmail: String
    let senderName: String?
    let recipients: [String]
    let date: Date
    let bodyText: String?
    let bodyHtml: String?
    let category: String
    let sinistroRef: String?
    
    init(from dto: EmailDetailDTO) {
        self.id = dto.id
        self.subject = dto.subject
        self.senderEmail = dto.senderEmail
        self.senderName = dto.senderName
        self.recipients = dto.recipients
        self.date = dto.date
        self.bodyText = dto.bodyText
        self.bodyHtml = dto.bodyHtml
        self.category = dto.category
        self.sinistroRef = dto.sinistroRef
    }
    
    init(from email: Email) {
        self.id = email.id
        self.subject = email.subject
        self.senderEmail = email.sender.email
        self.senderName = email.sender.name
        self.recipients = email.recipients.map { $0.email }
        self.date = email.date
        self.bodyText = email.body
        self.bodyHtml = nil
        self.category = "generic"
        self.sinistroRef = nil
    }
}

// MARK: - Errors

enum AdapterError: Error, LocalizedError {
    case notFound(String)
    case featureRequiresHub(String)
    case hubNotConnected
    case networkError(String)
    case operationFailed(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notFound(let msg): return msg
        case .featureRequiresHub(let msg): return msg
        case .hubNotConnected: return "Hub non connesso"
        case .networkError(let msg): return "Errore di rete: \(msg)"
        case .operationFailed(let msg): return "Operazione fallita: \(msg)"
        case .invalidResponse: return "Risposta non valida dal server"
        }
    }
}
