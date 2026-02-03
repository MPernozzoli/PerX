import Foundation

// ============================================================================
// MARK: - HubAPIAdapterClient
// Client HTTP per comunicare con l'Hub (Adapters)
// ============================================================================

@MainActor
final class HubAPIAdapterClient {
    static let shared = HubAPIAdapterClient()
    
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    private var baseURL: String {
        HubModeService.shared.hubURL
    }
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Generic Requests
    
    func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw HubClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        try validateResponse(response)
        
        return try decoder.decode(T.self, from: data)
    }
    
    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw HubClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        try validateResponse(response)
        
        return try decoder.decode(T.self, from: data)
    }
    
    func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw HubClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        try validateResponse(response)
        
        return try decoder.decode(T.self, from: data)
    }
    
    func delete(_ path: String) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw HubClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (_, response) = try await session.data(for: request)
        
        try validateResponse(response)
    }
    
    // MARK: - Specific Methods
    
    /// Associa email a sinistro
    func associateEmail(_ emailId: String, toSinistro ref: String) async throws {
        struct AssociateRequest: Encodable {
            let sinistroRef: String
        }
        
        let _: EmptyResponse = try await post("/emails/\(emailId)/associate", body: AssociateRequest(sinistroRef: ref))
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
        struct ScheduleRequest: Encodable {
            let accountId: String
            let to: [String]
            let cc: [String]?
            let subject: String
            let body: String
            let scheduledFor: Date
            let sinistroRef: String?
        }
        
        // Ottieni account corrente
        let accountId = UserDefaults.standard.string(forKey: "current_user_email") ?? ""
        
        let response: ScheduledEmailDTO = try await post("/emails/schedule", body: ScheduleRequest(
            accountId: accountId,
            to: to,
            cc: cc,
            subject: subject,
            body: body,
            scheduledFor: scheduledFor,
            sinistroRef: sinistroRef
        ))
        
        return response.id
    }
    
    /// Completa task
    func completeTask(id: String) async throws {
        let _: TaskDTO = try await post("/tasks/\(id)/complete", body: EmptyBody())
    }
    
    /// Invia heartbeat
    func sendHeartbeat(userId: String, clientInfo: String? = nil) async throws {
        struct HeartbeatRequest: Encodable {
            let user_id: String
            let client_info: String?
        }
        
        guard let url = URL(string: "\(baseURL)/heartbeat") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(HeartbeatRequest(user_id: userId, client_info: clientInfo))
        
        _ = try await session.data(for: request)
    }
    
    // MARK: - Helpers
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubClientError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200..<300:
            return // OK
        case 401:
            throw HubClientError.unauthorized
        case 404:
            throw HubClientError.notFound
        case 500..<600:
            throw HubClientError.serverError(httpResponse.statusCode)
        default:
            throw HubClientError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Types

private struct EmptyBody: Encodable {}

private struct EmptyResponse: Decodable {}

enum HubClientError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case serverError(Int)
    case httpError(Int)
    case decodingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL non valido"
        case .invalidResponse: return "Risposta non valida"
        case .unauthorized: return "Non autorizzato"
        case .notFound: return "Risorsa non trovata"
        case .serverError(let code): return "Errore server: \(code)"
        case .httpError(let code): return "Errore HTTP: \(code)"
        case .decodingError(let msg): return "Errore decodifica: \(msg)"
        }
    }
}
