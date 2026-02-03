import Foundation

/// Servizio per gestione email via Hub (invio immediato e programmato)
@MainActor
class ScheduledEmailService {
    static let shared = ScheduledEmailService()
    
    private let hubService = HubService.shared
    
    private init() {}
    
    // MARK: - Send Email (Immediate)
    
    struct SendEmailResponse: Codable {
        let success: Bool
        let messageId: String?
        let error: String?
        
        enum CodingKeys: String, CodingKey {
            case success
            case messageId = "message_id"
            case error
        }
    }
    
    /// Invia email immediatamente via Hub -> Mail Worker
    func sendEmail(
        accountId: String,
        to: [String],
        cc: [String]?,
        bcc: [String]?,
        subject: String,
        body: String,
        isHtml: Bool = true,
        replyToThreadId: String? = nil,
        inReplyTo: String? = nil,
        references: String? = nil,
        attachments: [[String: String]]? = nil
    ) async throws -> SendEmailResponse {
        let endpoint = "/emails/send"
        
        var payload: [String: Any] = [
            "accountId": accountId,
            "to": to,
            "subject": subject,
            "body": body,
            "isHtml": isHtml
        ]
        
        if let cc = cc, !cc.isEmpty {
            payload["cc"] = cc
        }
        if let bcc = bcc, !bcc.isEmpty {
            payload["bcc"] = bcc
        }
        if let threadId = replyToThreadId {
            payload["replyToThreadId"] = threadId
        }
        if let inReplyTo = inReplyTo {
            payload["inReplyTo"] = inReplyTo
        }
        if let references = references {
            payload["references"] = references
        }
        if let attachments = attachments {
            payload["attachments"] = attachments
        }
        
        let data = try await hubService.post(endpoint: endpoint, payload: payload)
        
        let decoder = JSONDecoder()
        return try decoder.decode(SendEmailResponse.self, from: data)
    }
    
    // MARK: - Schedule Email
    
    struct ScheduledEmail: Codable, Identifiable {
        let id: String
        let accountId: String
        let to: [String]
        let cc: [String]?
        let subject: String
        let body: String?
        let scheduledAt: Date
        let status: String
        let sinistroRef: String?
        let sentAt: Date?
        let errorMessage: String?
        
        var isScheduled: Bool { status == "pending" }
        var isSent: Bool { status == "sent" }
        var isFailed: Bool { status == "failed" }
        
        var scheduledAtFormatted: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: "it_IT")
            return formatter.string(from: scheduledAt)
        }
    }
    
    /// Programma invio di una email
    func scheduleEmail(
        accountId: String,
        to: [String],
        cc: [String]?,
        subject: String,
        body: String,
        scheduledFor: Date,
        sinistroRef: String?
    ) async throws -> ScheduledEmail {
        let endpoint = "/emails/schedule"
        
        let payload: [String: Any] = [
            "accountId": accountId,
            "to": to,
            "cc": cc ?? [],
            "subject": subject,
            "body": body,
            "scheduledFor": ISO8601DateFormatter().string(from: scheduledFor),
            "sinistroRef": sinistroRef ?? NSNull()
        ]
        
        let data = try await hubService.post(endpoint: endpoint, payload: payload)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(ScheduledEmail.self, from: data)
    }
    
    /// Ottiene lista email programmate per utente
    func getScheduledEmails(accountId: String) async throws -> [ScheduledEmail] {
        let endpoint = "/emails/scheduled?accountId=\(accountId)"
        
        let data = try await hubService.get(endpoint: endpoint)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode([ScheduledEmail].self, from: data)
    }
    
    /// Cancella email programmata (solo se pending)
    func cancelScheduledEmail(id: String) async throws {
        let endpoint = "/emails/scheduled/\(id)"
        
        try await hubService.delete(endpoint: endpoint)
    }
}

// MARK: - HubService Extension (se non esiste già)

class HubService {
    static let shared = HubService()
    
    private let session: URLSession
    
    /// URL base dell'Hub - usa la stessa configurazione di HubModeService
    private var baseURL: String {
        // Prima prova hub_url (usato da HubModeService), poi hubURL, poi default
        UserDefaults.standard.string(forKey: "hub_url") 
            ?? UserDefaults.standard.string(forKey: "hubURL") 
            ?? "https://mac-mini-di-massimo.tailca58be.ts.net"
    }
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }
    
    func get(endpoint: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw HubError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw HubError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return data
    }
    
    func post(endpoint: String, payload: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw HubError.invalidURL
        }
        
        print("[HubService] POST \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw HubError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return data
    }
    
    func delete(endpoint: String) async throws {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw HubError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw HubError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

enum HubError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL non valido"
        case .invalidResponse:
            return "Risposta non valida dal server"
        case .httpError(let statusCode):
            return "Errore HTTP: \(statusCode)"
        }
    }
}
