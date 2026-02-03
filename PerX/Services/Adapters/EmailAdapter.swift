import Foundation
import Combine

// ============================================================================
// MARK: - EmailAdapter
// Adapter per email con routing locale/Hub
// ============================================================================

@MainActor
final class EmailAdapter: ObservableObject {
    static let shared = EmailAdapter()
    
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    
    private let hubMode = HubModeService.shared
    private let hubClient = HubAPIAdapterClient.shared
    
    private init() {}
    
    // MARK: - Fetch Emails
    
    /// Recupera email per sinistro
    func getEmails(sinistroRef: String) async throws -> [EmailListItem] {
        if hubMode.shouldUseHub(for: .email) {
            return try await fetchFromHub(sinistroRef: sinistroRef)
        } else {
            return try await fetchFromLocal(sinistroRef: sinistroRef)
        }
    }
    
    /// Recupera email per utente
    func getEmails(userEmail: String, limit: Int = 100) async throws -> [EmailListItem] {
        if hubMode.shouldUseHub(for: .email) {
            return try await fetchFromHub(userEmail: userEmail, limit: limit)
        } else {
            return try await fetchFromLocal(userEmail: userEmail, limit: limit)
        }
    }
    
    /// Recupera dettaglio email
    func getEmailDetail(id: String) async throws -> EmailDetail {
        if hubMode.shouldUseHub(for: .email) {
            return try await fetchDetailFromHub(id: id)
        } else {
            return try await fetchDetailFromLocal(id: id)
        }
    }
    
    // MARK: - Actions
    
    /// Associa email a sinistro
    func associateEmail(_ emailId: String, toSinistro ref: String) async throws {
        if hubMode.shouldUseHub(for: .email) {
            try await hubClient.associateEmail(emailId, toSinistro: ref)
        } else {
            // Logica locale esistente
            // EmailAssociationService.shared.associate(...)
        }
    }
    
    /// Programma invio email
    func scheduleEmail(
        to: [String],
        cc: [String]?,
        subject: String,
        body: String,
        scheduledFor: Date,
        sinistroRef: String?
    ) async throws -> String {
        if hubMode.shouldUseHub(for: .email) {
            return try await hubClient.scheduleEmail(
                to: to,
                cc: cc,
                subject: subject,
                body: body,
                scheduledFor: scheduledFor,
                sinistroRef: sinistroRef
            )
        } else {
            // Logica locale - non supportata, richiede Hub
            throw AdapterError.featureRequiresHub("Invio programmato richiede Hub attivo")
        }
    }
    
    // MARK: - Hub Implementation
    
    private func fetchFromHub(sinistroRef: String) async throws -> [EmailListItem] {
        let response: [EmailDTO] = try await hubClient.get("/emails/sinistro/\(sinistroRef)")
        return response.map { EmailListItem(from: $0) }
    }
    
    private func fetchFromHub(userEmail: String, limit: Int) async throws -> [EmailListItem] {
        let response: [EmailDTO] = try await hubClient.get("/emails?user=\(userEmail)&limit=\(limit)")
        return response.map { EmailListItem(from: $0) }
    }
    
    private func fetchDetailFromHub(id: String) async throws -> EmailDetail {
        let response: EmailDetailDTO = try await hubClient.get("/emails/\(id)")
        return EmailDetail(from: response)
    }
    
    // MARK: - Local Implementation
    
    private func fetchFromLocal(sinistroRef: String) async throws -> [EmailListItem] {
        // Usa la logica esistente di MailManager
        let emails = await MailManager.shared.getEmailsForAdapter(sinistroRef: sinistroRef)
        return emails.map { EmailListItem(from: $0) }
    }
    
    private func fetchFromLocal(userEmail: String, limit: Int) async throws -> [EmailListItem] {
        // Usa la logica esistente di MailManager
        let emails = await MailManager.shared.getRecentEmailsForAdapter(limit: limit)
        return emails.map { EmailListItem(from: $0) }
    }
    
    private func fetchDetailFromLocal(id: String) async throws -> EmailDetail {
        // Usa la logica esistente
        guard let email = await MailManager.shared.getEmailForAdapter(id: id) else {
            throw AdapterError.notFound("Email non trovata")
        }
        return EmailDetail(from: email)
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
    
    init(from dto: EmailDTO) {
        self.id = dto.id
        self.subject = dto.subject
        self.senderEmail = dto.senderEmail
        self.senderName = dto.senderName
        self.date = dto.date
        self.category = dto.category
        self.sinistroRef = dto.sinistroRef
        self.direction = dto.direction
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
