import Foundation
import Combine

/// Servizio centralizzato per tutte le operazioni email via Hub.
/// Sostituisce GmailService, MailManager, EmailRepository per fetch/sync.
/// Il download e la classificazione avvengono sull'Hub, il client riceve solo i dati già processati.
@MainActor
class HubEmailService: ObservableObject {
    static let shared = HubEmailService()
    
    // MARK: - Published State
    
    @Published private(set) var emails: [EmailDTO] = []
    @Published private(set) var mailboxes: [MailboxDTO] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var error: String?
    
    // MARK: - Dependencies
    
    private let hubClient = HubAPIClient.shared
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    private var cancellables = Set<AnyCancellable>()
    private var pollingTask: Task<Void, Never>?
    
    // MARK: - Configuration
    
    private var baseURL: URL? {
        let urlString = HubConfigService.shared.hubBaseURL
        return URL(string: urlString)
    }
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
        
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }
    
    // MARK: - URL Helper
    
    private func url(path: String) throws -> URL {
        guard let base = baseURL else {
            throw HubEmailError.notConfigured
        }
        let baseString = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        guard let url = URL(string: baseString + path) else {
            throw HubEmailError.invalidURL
        }
        return url
    }
    
    // MARK: - Fetch Emails
    
    /// Recupera email per un sinistro specifico
    func fetchEmails(forSinistro ref: String) async throws -> [EmailDTO] {
        let url = try url(path: "emails/sinistro/\(ref)")
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        
        let emails = try decoder.decode([EmailDTO].self, from: data)
        print("[HubEmailService] 📥 Scaricate \(emails.count) email per sinistro \(ref)")
        return emails
    }
    
    /// Recupera email per l'utente corrente (con limit e opzionale mailbox filter)
    func fetchEmails(forUser userEmail: String, mailbox: String? = nil, limit: Int = 100) async throws -> [EmailDTO] {
        var path = "emails?user=\(userEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userEmail)&limit=\(limit)"
        if let mailbox = mailbox {
            path += "&mailbox=\(mailbox)"
        }
        
        let url = try url(path: path)
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        
        let emails = try decoder.decode([EmailDTO].self, from: data)
        print("[HubEmailService] 📥 Scaricate \(emails.count) email per utente \(userEmail)")
        return emails
    }
    
    /// Recupera le caselle disponibili per l'utente
    func fetchMailboxes(forUser userEmail: String) async throws -> [MailboxDTO] {
        let path = "emails/mailboxes?user=\(userEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userEmail)"
        let url = try url(path: path)
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        
        let mailboxes = try decoder.decode([MailboxDTO].self, from: data)
        print("[HubEmailService] 📬 Trovate \(mailboxes.count) caselle per \(userEmail)")
        return mailboxes
    }
    
    /// Recupera dettaglio email completo (body incluso)
    func fetchEmailDetail(messageId: String) async throws -> EmailDetailDTO {
        let url = try url(path: "emails/detail/\(messageId)")
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        return try decoder.decode(EmailDetailDTO.self, from: data)
    }
    
    // MARK: - Email Actions
    
    /// Associa email a sinistro
    func associateEmail(messageId: String, toSinistro ref: String) async throws {
        let url = try url(path: "emails/\(messageId)/associate")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct AssociateRequest: Encodable {
            let sinistroRef: String
        }
        request.httpBody = try encoder.encode(AssociateRequest(sinistroRef: ref))
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
        
        print("[HubEmailService] ✅ Email \(messageId) associata a \(ref)")
    }
    
    /// Marca email come letta
    func markAsRead(messageId: String, accountId: String? = nil) async throws {
        let url = try url(path: "emails/\(messageId)/read")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let accountId = accountId {
            struct ReadRequest: Encodable {
                let accountId: String
            }
            request.httpBody = try encoder.encode(ReadRequest(accountId: accountId))
        }
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
        
        print("[HubEmailService] ✅ Email \(messageId) marcata come letta")
    }
    
    /// Tagga email con una categoria
    func tagEmail(messageId: String, category: String, sinistroRef: String?) async throws {
        let url = try url(path: "emails/\(messageId)/tag")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct TagRequest: Encodable {
            let category: String
            let sinistroRef: String?
        }
        request.httpBody = try encoder.encode(TagRequest(category: category, sinistroRef: sinistroRef))
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
        
        print("[HubEmailService] 🏷️ Email \(messageId) taggata come \(category)")
    }
    
    // MARK: - Send Email
    
    struct SendEmailRequest: Encodable {
        let accountId: String
        let to: [String]
        let cc: [String]?
        let bcc: [String]?
        let subject: String
        let body: String
        let isHtml: Bool
        let replyToThreadId: String?
        let inReplyTo: String?
        let references: String?
        let attachments: [AttachmentData]?
        
        struct AttachmentData: Encodable {
            let filename: String
            let data: String // base64
            let mimeType: String?
        }
    }
    
    struct SendEmailResponse: Decodable {
        let success: Bool
        let messageId: String?
        let error: String?
        
        enum CodingKeys: String, CodingKey {
            case success
            case messageId = "message_id"
            case error
        }
    }
    
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
    ) async throws -> SendEmailResponse {
        let url = try url(path: "emails/send")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let attachmentData = attachments?.map { att in
            SendEmailRequest.AttachmentData(
                filename: att.filename,
                data: att.data.base64EncodedString(),
                mimeType: att.mimeType
            )
        }
        
        let sendRequest = SendEmailRequest(
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
            attachments: attachmentData
        )
        
        request.httpBody = try encoder.encode(sendRequest)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        let result = try decoder.decode(SendEmailResponse.self, from: data)
        
        if result.success {
            print("[HubEmailService] 📤 Email inviata: \(result.messageId ?? "N/A")")
        } else {
            print("[HubEmailService] ❌ Errore invio: \(result.error ?? "sconosciuto")")
        }
        
        return result
    }
    
    // MARK: - Scheduled Emails
    
    /// Programma invio email
    func scheduleEmail(
        accountId: String,
        to: [String],
        cc: [String]? = nil,
        subject: String,
        body: String,
        scheduledFor: Date,
        sinistroRef: String? = nil
    ) async throws -> ScheduledEmailDTO {
        let url = try url(path: "emails/schedule")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct ScheduleRequest: Encodable {
            let accountId: String
            let to: [String]
            let cc: [String]?
            let subject: String
            let body: String
            let scheduledFor: Date
            let sinistroRef: String?
        }
        
        request.httpBody = try encoder.encode(ScheduleRequest(
            accountId: accountId,
            to: to,
            cc: cc,
            subject: subject,
            body: body,
            scheduledFor: scheduledFor,
            sinistroRef: sinistroRef
        ))
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        let scheduled = try decoder.decode(ScheduledEmailDTO.self, from: data)
        print("[HubEmailService] 📅 Email programmata per \(scheduledFor)")
        return scheduled
    }
    
    /// Lista email programmate
    func getScheduledEmails(forAccount accountId: String) async throws -> [ScheduledEmailDTO] {
        let url = try url(path: "emails/scheduled?accountId=\(accountId)")
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        return try decoder.decode([ScheduledEmailDTO].self, from: data)
    }
    
    /// Cancella email programmata
    func cancelScheduledEmail(id: String) async throws {
        let url = try url(path: "emails/scheduled/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
        print("[HubEmailService] 🗑️ Email programmata \(id) cancellata")
    }
    
    // MARK: - Sync & Polling
    
    /// Sincronizza mailbox e email in background
    func startPolling(userEmail: String, interval: TimeInterval = 60) {
        stopPolling()
        
        pollingTask = Task {
            while !Task.isCancelled {
                await syncUserEmails(userEmail: userEmail)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
        print("[HubEmailService] 🔄 Polling avviato (ogni \(Int(interval))s)")
    }
    
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        print("[HubEmailService] ⏹️ Polling fermato")
    }
    
    /// Sincronizza email utente (chiamata manualmente o da polling)
    func syncUserEmails(userEmail: String) async {
        isLoading = true
        error = nil
        
        do {
            async let emailsTask = fetchEmails(forUser: userEmail, limit: 200)
            async let mailboxesTask = fetchMailboxes(forUser: userEmail)
            
            let (fetchedEmails, fetchedMailboxes) = try await (emailsTask, mailboxesTask)
            
            self.emails = fetchedEmails
            self.mailboxes = fetchedMailboxes
            self.lastSyncDate = Date()
            
            print("[HubEmailService] ✅ Sync completato: \(fetchedEmails.count) email, \(fetchedMailboxes.count) caselle")
        } catch {
            self.error = error.localizedDescription
            print("[HubEmailService] ❌ Errore sync: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Helpers
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubEmailError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 400:
            throw HubEmailError.badRequest
        case 401, 403:
            throw HubEmailError.unauthorized
        case 404:
            throw HubEmailError.notFound
        case 500...599:
            throw HubEmailError.serverError(httpResponse.statusCode)
        default:
            throw HubEmailError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Error Types

enum HubEmailError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case badRequest
    case unauthorized
    case notFound
    case serverError(Int)
    case httpError(Int)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Hub non configurato"
        case .invalidURL:
            return "URL non valido"
        case .invalidResponse:
            return "Risposta non valida"
        case .badRequest:
            return "Richiesta non valida"
        case .unauthorized:
            return "Non autorizzato"
        case .notFound:
            return "Email non trovata"
        case .serverError(let code):
            return "Errore server (\(code))"
        case .httpError(let code):
            return "Errore HTTP (\(code))"
        }
    }
}

// MARK: - Email DTO Helpers

extension EmailDTO {
    /// Converte EmailDTO in Email legacy per compatibilità
    func toEmail() -> Email {
        Email(
            id: id,
            isRead: isRead ?? false,
            sender: Contact(name: senderName, email: senderEmail),
            recipients: [], // Non disponibile nel DTO base
            subject: subject,
            date: date,
            body: nil // Richiede fetch dettaglio
        )
    }
}

extension EmailDetailDTO {
    /// Converte EmailDetailDTO in Email legacy
    func toEmail() -> Email {
        Email(
            id: id,
            isRead: true, // Se stiamo vedendo il dettaglio è letta
            sender: Contact(name: senderName, email: senderEmail),
            recipients: recipients.map { Contact(name: nil, email: $0) },
            subject: subject,
            date: date,
            body: bodyHtml ?? bodyText
        )
    }
}
