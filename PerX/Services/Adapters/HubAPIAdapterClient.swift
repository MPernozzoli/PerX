import Foundation
import Security

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
    private let keychainService = "com.perx.cloudapi"
    
    private var baseURL: String {
        HubConfigService.shared.cloudAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cloudBaseURL: String {
        HubConfigService.shared.cloudAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cloudEmail: String {
        HubConfigService.shared.cloudAPIEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    var isCloudConfigured: Bool {
        !cloudBaseURL.isEmpty && !cloudEmail.isEmpty && loadFromKeychain(forKey: "cloud_api_password") != nil
    }

    func saveCloudPassword(_ password: String) {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            removeFromKeychain(forKey: "cloud_api_password")
        } else {
            saveToKeychain(token: trimmed, forKey: "cloud_api_password")
        }
    }

    func hasStoredCloudPassword() -> Bool {
        loadFromKeychain(forKey: "cloud_api_password") != nil
    }

    func clearCloudSession() {
        removeFromKeychain(forKey: "cloud_api_access_token")
        removeFromKeychain(forKey: "cloud_api_refresh_token")
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

    // MARK: - Cloud API Requests

    func cloudGet<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(cloudBaseURL)\(path)") else {
            throw HubClientError.invalidURL
        }

        var request = try await authorizedCloudRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubClientError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            try await loginToCloud(forceRefresh: true)
            var retry = try await authorizedCloudRequest(url: url)
            retry.httpMethod = "GET"
            retry.setValue("application/json", forHTTPHeaderField: "Accept")
            let (retryData, retryResponse) = try await session.data(for: retry)
            try validateResponse(retryResponse)
            return try decoder.decode(T.self, from: retryData)
        }

        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }

    func cloudPost<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await performCloudRequest(path: path, method: "POST", body: body)
    }

    func cloudPut<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await performCloudRequest(path: path, method: "PUT", body: body)
    }

    /// POST multipart/form-data al backend cloud. `fields` finisce come form
    /// fields semplici; `file` come parte binaria con `filename` e `mimeType`.
    /// Usato per upload media (es. frame videoperizia → POST .../session/{sid}/media).
    func cloudPostMultipart<T: Decodable>(
        _ path: String,
        fileData: Data,
        fileFieldName: String,
        fileName: String,
        mimeType: String,
        fields: [String: String] = [:]
    ) async throws -> T {
        guard let url = URL(string: "\(cloudBaseURL)\(path)") else {
            throw HubClientError.invalidURL
        }

        let boundary = "perx-\(UUID().uuidString)"
        var body = Data()
        let lineBreak = "\r\n"

        for (key, value) in fields {
            body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
            body.append("\(value)\(lineBreak)".data(using: .utf8)!)
        }
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(fileData)
        body.append("\(lineBreak)--\(boundary)--\(lineBreak)".data(using: .utf8)!)

        var request = try await authorizedCloudRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let (data, response) = try await session.upload(for: request, from: body)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            try await loginToCloud(forceRefresh: true)
            var retry = try await authorizedCloudRequest(url: url)
            retry.httpMethod = "POST"
            retry.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            retry.setValue("application/json", forHTTPHeaderField: "Accept")
            retry.httpBody = body
            let (retryData, retryResponse) = try await session.upload(for: retry, from: body)
            try validateResponse(retryResponse)
            return try decoder.decode(T.self, from: retryData)
        }
        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }

    func cloudDelete(_ path: String) async throws {
        guard let url = URL(string: "\(cloudBaseURL)\(path)") else {
            throw HubClientError.invalidURL
        }

        var request = try await authorizedCloudRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubClientError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            try await loginToCloud(forceRefresh: true)
            var retry = try await authorizedCloudRequest(url: url)
            retry.httpMethod = "DELETE"
            let (_, retryResponse) = try await session.data(for: retry)
            try validateResponse(retryResponse)
            return
        }

        try validateResponse(response)
    }

    private func performCloudRequest<T: Decodable, B: Encodable>(
        path: String,
        method: String,
        body: B?
    ) async throws -> T {
        guard let url = URL(string: "\(cloudBaseURL)\(path)") else {
            throw HubClientError.invalidURL
        }

        var request = try await authorizedCloudRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubClientError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            try await loginToCloud(forceRefresh: true)
            var retry = try await authorizedCloudRequest(url: url)
            retry.httpMethod = method
            retry.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body {
                retry.setValue("application/json", forHTTPHeaderField: "Content-Type")
                retry.httpBody = try encoder.encode(body)
            }
            let (retryData, retryResponse) = try await session.data(for: retry)
            try validateResponse(retryResponse)
            return try decoder.decode(T.self, from: retryData)
        }

        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }

    private func authorizedCloudRequest(url: URL) async throws -> URLRequest {
        let token = try await loginToCloud(forceRefresh: false)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    @discardableResult
    func loginToCloud(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let token = loadFromKeychain(forKey: "cloud_api_access_token"), !token.isEmpty {
            return token
        }

        guard !cloudBaseURL.isEmpty else {
            throw HubClientError.invalidURL
        }
        guard !cloudEmail.isEmpty else {
            throw HubClientError.unauthorized
        }
        guard let password = loadFromKeychain(forKey: "cloud_api_password"), !password.isEmpty else {
            throw HubClientError.unauthorized
        }

        guard let url = URL(string: "\(cloudBaseURL)/api/v1/auth/login") else {
            throw HubClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(CloudAPILoginRequest(username: cloudEmail, password: password))

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        let tokenResponse = try decoder.decode(CloudAPITokenResponse.self, from: data)
        saveToKeychain(token: tokenResponse.access_token, forKey: "cloud_api_access_token")
        saveToKeychain(token: tokenResponse.refresh_token, forKey: "cloud_api_refresh_token")
        return tokenResponse.access_token
    }
    
    // MARK: - Specific Methods
    
    /// Associa email a sinistro
    func associateEmail(_ emailId: String, toSinistro ref: String) async throws {
        struct AssociateRequest: Encodable {
            let sinistroRef: String
        }
        
        let _: EmptyResponse = try await cloudPost("/api/v1/hub/emails/\(emailId)/associate", body: AssociateRequest(sinistroRef: ref))
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
        
        let response: ScheduledEmailDTO = try await cloudPost("/api/v1/hub/emails/schedule", body: ScheduleRequest(
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
        let _: TaskDTO = try await cloudPost("/api/v1/tasks/\(id)/complete", body: EmptyBody())
    }
    
    /// Invia heartbeat
    func sendHeartbeat(userId: String, clientInfo: String? = nil) async throws {
        struct HeartbeatRequest: Encodable {
            let user_id: String
            let client_info: String?
        }
        
        let _: EmptyResponse = try await cloudPost(
            "/api/v1/hub/heartbeat",
            body: HeartbeatRequest(user_id: userId, client_info: clientInfo)
        )
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

    private func saveToKeychain(token: String, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(token.utf8)
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private func removeFromKeychain(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Actors (anagrafica unificata)

    /// Search anagrafica. Ritorna shape minimizzata per GDPR (no contatti,
    /// CF/PIVA mascherati). `claimContextId` viene loggato sul backend per
    /// dimostrare la finalità del trattamento (sinistro in lavorazione).
    func listActors(
        query: String? = nil,
        actorType: CloudActorType? = nil,
        claimContextId: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> CloudActorSummaryListResponse {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        if let actorType { items.append(URLQueryItem(name: "actor_type", value: actorType.rawValue)) }
        if let claimContextId { items.append(URLQueryItem(name: "claim_context_id", value: claimContextId)) }

        var components = URLComponents()
        components.queryItems = items
        let qs = components.percentEncodedQuery ?? ""
        let path = "/api/v1/actors" + (qs.isEmpty ? "" : "?\(qs)")
        return try await cloudGet(path)
    }

    func createActor(_ payload: CloudActorCreate, claimContextId: String? = nil) async throws -> CloudActorResponse {
        let path: String
        if let claimContextId, let enc = claimContextId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path = "/api/v1/actors?claim_context_id=\(enc)"
        } else {
            path = "/api/v1/actors"
        }
        return try await cloudPost(path, body: payload)
    }

    func getActor(id: String, claimContextId: String? = nil) async throws -> CloudActorDetail {
        var path = "/api/v1/actors/\(id)"
        if let claimContextId, let enc = claimContextId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?claim_context_id=\(enc)"
        }
        return try await cloudGet(path)
    }

    func updateActor(id: String, payload: CloudActorUpdate) async throws -> CloudActorResponse {
        // Backend usa PATCH per gli attori
        guard let url = URL(string: "\(cloudBaseURL)/api/v1/actors/\(id)") else {
            throw HubClientError.invalidURL
        }
        var request = try await authorizedCloudRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(CloudActorResponse.self, from: data)
    }

    func addActorAddress(actorId: String, payload: CloudActorAddressCreate) async throws -> CloudActorAddress {
        try await cloudPost("/api/v1/actors/\(actorId)/addresses", body: payload)
    }

    func listActorAddresses(actorId: String) async throws -> [CloudActorAddress] {
        try await cloudGet("/api/v1/actors/\(actorId)/addresses")
    }

    func addActorIban(actorId: String, payload: CloudActorIbanCreate) async throws -> CloudActorIban {
        try await cloudPost("/api/v1/actors/\(actorId)/ibans", body: payload)
    }

    func listActorIbans(actorId: String) async throws -> [CloudActorIban] {
        try await cloudGet("/api/v1/actors/\(actorId)/ibans")
    }

    func addActorRelation(actorId: String, payload: CloudActorRelationCreate) async throws -> CloudActorRelation {
        try await cloudPost("/api/v1/actors/\(actorId)/relations", body: payload)
    }

    /// Tutti i sinistri in cui l'attore compare in uno qualsiasi dei ruoli
    /// (contraente / assicurato / danneggiato).
    func listActorClaims(actorId: String) async throws -> [CloudClaimResponse] {
        try await cloudGet("/api/v1/actors/\(actorId)/claims")
    }

    func listActorAgencies(actorId: String) async throws -> [CloudActorAgencyLink] {
        try await cloudGet("/api/v1/actors/\(actorId)/agencies")
    }

    func listActorCompanies(actorId: String) async throws -> [CloudActorCompanyLink] {
        try await cloudGet("/api/v1/actors/\(actorId)/companies")
    }

    // MARK: - Rubrica (compagnie / agenzie backend)

    func listCompagnie(query: String? = nil, limit: Int = 100) async throws -> CloudCompagniaListResponse {
        var path = "/api/v1/rubrica/compagnie?limit=\(limit)"
        if let query, !query.isEmpty,
           let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&search=\(encoded)"
        }
        return try await cloudGet(path)
    }

    func createCompagnia(_ payload: CloudCompagniaCreate) async throws -> CloudCompagniaResponse {
        try await cloudPost("/api/v1/rubrica/compagnie", body: payload)
    }

    func listAgenzieFromBackend(query: String? = nil, limit: Int = 100) async throws -> CloudAgenziaListResponse {
        var path = "/api/v1/rubrica/agenzie?limit=\(limit)"
        if let query, !query.isEmpty,
           let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&search=\(encoded)"
        }
        return try await cloudGet(path)
    }

    func createAgenziaOnBackend(_ payload: CloudAgenziaCreate) async throws -> CloudAgenziaResponse {
        try await cloudPost("/api/v1/rubrica/agenzie", body: payload)
    }

    // MARK: - Claim actor refs (PATCH dedicato)

    /// Aggiorna i riferimenti attori (contraente/assicurato/danneggiato +
    /// agency/compagnia) di un sinistro senza dover spedire l'intero ClaimUpdate.
    func patchClaimActors(
        claimId: String,
        payload: CloudClaimActorsPatch
    ) async throws -> CloudClaimResponse {
        guard let url = URL(string: "\(cloudBaseURL)/api/v1/claims/\(claimId)/actors") else {
            throw HubClientError.invalidURL
        }
        var request = try await authorizedCloudRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(CloudClaimResponse.self, from: data)
    }
}

// MARK: - Claim actor patch payload (lives here to keep DTOs colocated)

struct CloudClaimActorsPatch: Codable {
    let contraente: CloudClaimActorInput?
    let assicurato: CloudClaimActorInput?
    let danneggiato: CloudClaimActorInput?
    let agency_id: String?
    let compagnia_id: String?

    init(
        contraente: CloudClaimActorInput? = nil,
        assicurato: CloudClaimActorInput? = nil,
        danneggiato: CloudClaimActorInput? = nil,
        agency_id: String? = nil,
        compagnia_id: String? = nil
    ) {
        self.contraente = contraente
        self.assicurato = assicurato
        self.danneggiato = danneggiato
        self.agency_id = agency_id
        self.compagnia_id = compagnia_id
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
