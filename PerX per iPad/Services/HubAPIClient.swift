//
//  HubAPIClient.swift
//  PerX per iPad
//
//  Client HTTP per comunicare con l'Hub centralizzato.
//  Versione iOS del client - condivide la stessa API del Mac.
//

import Foundation
import Combine
import Security

/// Client HTTP per comunicare con l'Hub centralizzato
@MainActor
class HubAPIClient: ObservableObject {
    static let shared = HubAPIClient()
    static let fixedCloudAPIBaseURL = "https://api.perx.it"
    
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?
    
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let keychainService = "com.perx.ipad.cloudapi"
    
    // Hub URL - da configurare nelle impostazioni
    private var _hubBaseURL: String = ""
    var hubBaseURL: String {
        get { _hubBaseURL }
        set { 
            _hubBaseURL = newValue
            UserDefaults.standard.set(newValue, forKey: "hubBaseURL")
        }
    }

    private var _cloudAPIBaseURL: String = Self.fixedCloudAPIBaseURL
    var cloudAPIBaseURL: String {
        get { Self.fixedCloudAPIBaseURL }
        set {
            _cloudAPIBaseURL = Self.fixedCloudAPIBaseURL
            UserDefaults.standard.set(Self.fixedCloudAPIBaseURL, forKey: "cloudAPIBaseURL")
        }
    }

    private var _cloudAPIEmail: String = ""
    var cloudAPIEmail: String {
        get { _cloudAPIEmail }
        set {
            _cloudAPIEmail = newValue
            UserDefaults.standard.set(newValue, forKey: "cloudAPIEmail")
        }
    }
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        
        // Carica URL salvato
        _hubBaseURL = UserDefaults.standard.string(forKey: "hubBaseURL") ?? ""
        _cloudAPIBaseURL = Self.fixedCloudAPIBaseURL
        UserDefaults.standard.set(Self.fixedCloudAPIBaseURL, forKey: "cloudAPIBaseURL")
        _cloudAPIEmail = UserDefaults.standard.string(forKey: "cloudAPIEmail") ?? ""
    }
    
    // MARK: - Configuration
    
    private var baseURL: URL? {
        guard !hubBaseURL.isEmpty else { return nil }
        return URL(string: hubBaseURL)
    }
    
    private func url(path: String) throws -> URL {
        guard let base = baseURL else {
            throw HubAPIError.notConfigured
        }
        let baseString = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        guard let url = URL(string: baseString + path) else {
            throw HubAPIError.invalidURL
        }
        return url
    }
    
    // MARK: - Auth Token
    
    private var authToken: String? {
        loadFromKeychain(forKey: "cloud_api_access_token") ?? GoogleAuthServiceiOS.shared.accessToken
    }

    var isCloudConfigured: Bool {
        !cloudAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !cloudAPIEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        loadFromKeychain(forKey: "cloud_api_password") != nil
    }

    func saveCloudPassword(_ password: String) {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            removeFromKeychain(forKey: "cloud_api_password")
        } else {
            saveToKeychain(token: trimmed, forKey: "cloud_api_password")
        }
    }

    func clearCloudSession() {
        removeFromKeychain(forKey: "cloud_api_access_token")
        removeFromKeychain(forKey: "cloud_api_refresh_token")
    }

    func storeCloudSession(accessToken: String, refreshToken: String?, email: String, password: String) {
        cloudAPIEmail = email.lowercased()
        saveCloudPassword(password)
        saveToKeychain(token: accessToken, forKey: "cloud_api_access_token")
        if let refreshToken, !refreshToken.isEmpty {
            saveToKeychain(token: refreshToken, forKey: "cloud_api_refresh_token")
        } else {
            removeFromKeychain(forKey: "cloud_api_refresh_token")
        }
    }
    
    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
    
    // MARK: - Health
    
    func checkHealth() async throws -> HealthResponse {
        let url = try url(path: "health")
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        
        let health = try decoder.decode(HealthResponse.self, from: data)
        isConnected = true
        return health
    }
    
    // MARK: - Email Operations
    
    /// Invia email tramite Hub
    func sendEmail(_ request: SendEmailRequest) async throws -> SendEmailResponse {
        let url = try url(path: "email/send")
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try encoder.encode(request)
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return try decoder.decode(SendEmailResponse.self, from: data)
    }
    
    /// Schedula email per invio futuro
    func scheduleEmail(_ request: ScheduleEmailRequest) async throws -> ScheduleEmailResponse {
        let url = try url(path: "email/schedule")
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try encoder.encode(request)
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return try decoder.decode(ScheduleEmailResponse.self, from: data)
    }
    
    // MARK: - WhatsApp Operations
    
    /// Invia messaggio WhatsApp tramite Hub
    func sendWhatsApp(_ request: SendWhatsAppRequest) async throws -> SendWhatsAppResponse {
        let url = try url(path: "whatsapp/send")
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try encoder.encode(request)
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return try decoder.decode(SendWhatsAppResponse.self, from: data)
    }
    
    /// Schedula messaggio WhatsApp
    func scheduleWhatsApp(_ request: ScheduleWhatsAppRequest) async throws -> ScheduleWhatsAppResponse {
        let url = try url(path: "whatsapp/schedule")
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try encoder.encode(request)
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return try decoder.decode(ScheduleWhatsAppResponse.self, from: data)
    }
    
    // MARK: - Sinistri Operations
    
    /// Recupera lista sinistri assegnati all'utente
    func getSinistri() async throws -> [SinistroDTO] {
        let url = try url(path: "claims")
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return try decoder.decode([SinistroDTO].self, from: data)
    }

    func getSinistriFromCloud() async throws -> [SinistroDTO] {
        let response: CloudClaimListResponseDTO = try await cloudGet(endpoint: "/api/v1/claims")
        return response.items.map { SinistroDTO(from: $0) }
    }
    
    /// Recupera dettaglio sinistro
    func getSinistro(riferimento: String) async throws -> SinistroDTO {
        let url = try url(path: "claims/\(riferimento)")
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return try decoder.decode(SinistroDTO.self, from: data)
    }

    func getSinistroFromCloud(riferimento: String) async throws -> SinistroDTO {
        let response: CloudClaimDTO = try await cloudGet(endpoint: "/api/v1/claims/\(riferimento)")
        return SinistroDTO(from: response)
    }
    
    // MARK: - Diario Operations
    
    /// Recupera diario sinistro
    func getDiarioEntries(riferimento: String) async throws -> [DiarioEntryHubDTO] {
        let url = try url(path: "claims/\(riferimento)/diario")
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return try decoder.decode([DiarioEntryHubDTO].self, from: data)
    }
    
    /// Aggiunge nota al diario
    func addDiarioEntry(riferimento: String, entry: CreateDiarioEntryRequest) async throws -> DiarioEntryHubDTO {
        let url = try url(path: "claims/\(riferimento)/diario")
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try encoder.encode(entry)
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return try decoder.decode(DiarioEntryHubDTO.self, from: data)
    }

    func getDiarioEntriesFromCloud(riferimento: String) async throws -> [DiarioEntryDTO] {
        let response: CloudDiaryEntryListResponseDTO = try await cloudGet(endpoint: "/api/v1/claims/\(riferimento)/diary")
        return response.items.map { DiarioEntryDTO(from: $0) }
    }

    func addDiarioEntryToCloud(riferimento: String, entry: CreateDiarioEntryRequest) async throws -> DiarioEntryDTO {
        let request = CloudDiaryEntryCreateRequestDTO(
            entry_type: entry.tipo,
            title: entry.titolo,
            body_text: entry.testo,
            visibility: "internal",
            happened_at: nil
        )
        let response: CloudDiaryEntryDTO = try await cloudPost(endpoint: "/api/v1/claims/\(riferimento)/diary", body: request)
        return DiarioEntryDTO(from: response)
    }

    func getProcessedEmailsFromCloud(riferimento: String) async throws -> [ProcessedEmailDTO] {
        let response: CloudEmailListResponseDTO = try await cloudGet(endpoint: "/api/v1/emails?claim_id=\(riferimento)")
        return response.items.map { ProcessedEmailDTO(from: $0, sinistroRiferimento: riferimento) }
    }

    func getWhatsAppMessagesFromCloud(riferimento: String) async throws -> [WhatsAppMessageDTO] {
        struct WAThreadListDTO: Decodable {
            struct WAThreadDTO: Decodable { let id: String }
            let items: [WAThreadDTO]
        }
        struct WAMessageListDTO: Decodable {
            struct WAMessageDTO: Decodable {
                let id: String
                let thread_id: String
                let direction: String
                let body_text: String?
                let sender_name: String?
                let created_at: Date
                let media_type: String?
            }
            let items: [WAMessageDTO]
        }
        let threads: WAThreadListDTO = try await cloudGet(endpoint: "/api/v1/whatsapp/threads?claim_id=\(riferimento)")
        var result: [WhatsAppMessageDTO] = []
        for thread in threads.items {
            let msgs: WAMessageListDTO = try await cloudGet(endpoint: "/api/v1/whatsapp/threads/\(thread.id)/messages")
            for m in msgs.items {
                result.append(WhatsAppMessageDTO(
                    id: m.id, chatId: m.thread_id,
                    from: m.sender_name ?? "", body: m.body_text ?? "",
                    timestamp: m.created_at, direction: m.direction, mediaType: m.media_type
                ))
            }
        }
        return result
    }

    // MARK: - Internal Chat (Supabase backend)

    func getChatThreads() async throws -> [ChatRoomDTO] {
        struct ThreadListDTO: Decodable {
            struct ThreadDTO: Decodable {
                let id: String
                let title: String
                let created_at: Date
                let metadata_json: [String: String]?
            }
            let items: [ThreadDTO]
        }
        let list: ThreadListDTO = try await cloudGet(endpoint: "/api/v1/internal-chat/threads")
        return list.items.map {
            ChatRoomDTO(id: $0.id, name: $0.title, lastMessageAt: $0.created_at,
                        lastMessagePreview: nil, lastMessageSender: nil)
        }
    }

    func getChatMessages(threadId: String) async throws -> [ChatMessageDTO] {
        struct MessageListDTO: Decodable {
            struct MessageDTO: Decodable {
                let id: String
                let sender_user_id: String?
                let body_text: String?
                let created_at: Date
            }
            let items: [MessageDTO]
        }
        let list: MessageListDTO = try await cloudGet(endpoint: "/api/v1/internal-chat/threads/\(threadId)/messages")
        return list.items.map {
            ChatMessageDTO(id: $0.id, senderName: $0.sender_user_id ?? "Utente",
                           content: $0.body_text ?? "", timestamp: $0.created_at)
        }
    }

    func sendChatMessage(threadId: String, content: String) async throws -> ChatMessageDTO {
        struct CreateMsg: Encodable { let body_text: String; let message_type: String }
        struct MessageDTO: Decodable {
            let id: String; let sender_user_id: String?; let body_text: String?; let created_at: Date
        }
        let response: MessageDTO = try await cloudPost(
            endpoint: "/api/v1/internal-chat/threads/\(threadId)/messages",
            body: CreateMsg(body_text: content, message_type: "text")
        )
        return ChatMessageDTO(id: response.id, senderName: response.sender_user_id ?? "Tu",
                              content: response.body_text ?? content, timestamp: response.created_at)
    }

    func createChatThread(with otherUserEmail: String) async throws -> ChatRoomDTO {
        struct CreateThread: Encodable { let title: String; let thread_type: String }
        struct ThreadDTO: Decodable { let id: String; let title: String; let created_at: Date }
        let response: ThreadDTO = try await cloudPost(
            endpoint: "/api/v1/internal-chat/threads",
            body: CreateThread(title: otherUserEmail, thread_type: "direct")
        )
        return ChatRoomDTO(id: response.id, name: response.title, lastMessageAt: response.created_at,
                           lastMessagePreview: nil, lastMessageSender: nil)
    }

    // MARK: - Vault Operations
    
    /// Lista file di un sinistro
    func listFiles(sinistroRef: String) async throws -> [VaultFileDTO] {
        let url = try url(path: "vault/sinistri/\(sinistroRef)/files")
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return try decoder.decode([VaultFileDTO].self, from: data)
    }
    
    /// Download file
    func downloadFile(fileId: String) async throws -> Data {
        let url = try url(path: "vault/files/\(fileId)/download")
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return data
    }
    
    /// Richiedi cartella sinistro (trigger packaging sul Mac)
    func requestFolder(sinistroRef: String) async throws -> FolderRequestResponse {
        let url = try url(path: "vault/sinistri/\(sinistroRef)/request")
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "POST"
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return try decoder.decode(FolderRequestResponse.self, from: data)
    }
    
    /// Controlla stato richiesta cartella
    func checkFolderRequest(requestId: String) async throws -> FolderRequestStatus {
        let url = try url(path: "vault/requests/\(requestId)/status")
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return try decoder.decode(FolderRequestStatus.self, from: data)
    }
    
    // MARK: - Generic HTTP Methods
    
    func get<T: Decodable>(endpoint: String) async throws -> T {
        let url = try url(path: endpoint)
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }
    
    func post<B: Encodable, T: Decodable>(endpoint: String, body: B) async throws -> T {
        let url = try url(path: endpoint)
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try encoder.encode(body)
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }
    
    func post<B: Encodable>(endpoint: String, body: B) async throws {
        let url = try url(path: endpoint)
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try encoder.encode(body)
        
        let (_, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
    }

    // MARK: - Cloud API

    func cloudLogin(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh,
           let token = loadFromKeychain(forKey: "cloud_api_access_token"),
           !token.isEmpty {
            return token
        }

        let base = cloudAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = cloudAPIEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !base.isEmpty, let password = loadFromKeychain(forKey: "cloud_api_password"), !password.isEmpty else {
            throw HubAPIError.notConfigured
        }

        guard let url = URL(string: "\(base)/api/v1/auth/login") else {
            throw HubAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(CloudLoginRequest(username: email, password: password))

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        let tokenResponse = try decoder.decode(CloudTokenResponse.self, from: data)
        saveToKeychain(token: tokenResponse.access_token, forKey: "cloud_api_access_token")
        saveToKeychain(token: tokenResponse.refresh_token, forKey: "cloud_api_refresh_token")
        return tokenResponse.access_token
    }

    func cloudGet<T: Decodable>(endpoint: String) async throws -> T {
        let base = cloudAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(base)\(endpoint)") else {
            throw HubAPIError.invalidURL
        }

        var request = try await authorizedCloudRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubAPIError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            _ = try await cloudLogin(forceRefresh: true)
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

    func cloudPost<B: Encodable, T: Decodable>(endpoint: String, body: B) async throws -> T {
        let base = cloudAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(base)\(endpoint)") else {
            throw HubAPIError.invalidURL
        }

        var request = try await authorizedCloudRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubAPIError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            _ = try await cloudLogin(forceRefresh: true)
            var retry = try await authorizedCloudRequest(url: url)
            retry.httpMethod = "POST"
            retry.setValue("application/json", forHTTPHeaderField: "Content-Type")
            retry.setValue("application/json", forHTTPHeaderField: "Accept")
            retry.httpBody = try encoder.encode(body)
            let (retryData, retryResponse) = try await session.data(for: retry)
            try validateResponse(retryResponse)
            return try decoder.decode(T.self, from: retryData)
        }

        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }

    func cloudPut<B: Encodable, T: Decodable>(endpoint: String, body: B) async throws -> T {
        let base = cloudAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(base)\(endpoint)") else {
            throw HubAPIError.invalidURL
        }

        var request = try await authorizedCloudRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubAPIError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            _ = try await cloudLogin(forceRefresh: true)
            var retry = try await authorizedCloudRequest(url: url)
            retry.httpMethod = "PUT"
            retry.setValue("application/json", forHTTPHeaderField: "Content-Type")
            retry.setValue("application/json", forHTTPHeaderField: "Accept")
            retry.httpBody = try encoder.encode(body)
            let (retryData, retryResponse) = try await session.data(for: retry)
            try validateResponse(retryResponse)
            return try decoder.decode(T.self, from: retryData)
        }

        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }

    func cloudDownload(endpoint: String) async throws -> Data {
        let base = cloudAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(base)\(endpoint)") else {
            throw HubAPIError.invalidURL
        }

        var request = try await authorizedCloudRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubAPIError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            _ = try await cloudLogin(forceRefresh: true)
            var retry = try await authorizedCloudRequest(url: url)
            retry.httpMethod = "GET"
            let (retryData, retryResponse) = try await session.data(for: retry)
            try validateResponse(retryResponse)
            return retryData
        }

        try validateResponse(response)
        return data
    }

    func cloudUpload(endpoint: String, data: Data, fileName: String, mimeType: String) async throws -> CloudProfileAssetDTO {
        let base = cloudAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(base)\(endpoint)") else {
            throw HubAPIError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try await authorizedCloudRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeMultipartBody(data: data, fileName: fileName, mimeType: mimeType, boundary: boundary)

        let (responseData, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(CloudProfileAssetDTO.self, from: responseData)
    }

    func getCurrentProfileFromCloud() async throws -> CloudProfileDTO {
        try await cloudGet(endpoint: "/api/v1/profiles/me")
    }

    func getTenantSettingsFromCloud() async throws -> CloudTenantSettingsDTO {
        try await cloudGet(endpoint: "/api/v1/inspections/context")
    }

    func getInspectionRoutesFromCloud(
        statusFilter: String? = nil,
        planDate: String? = nil
    ) async throws -> CloudInspectionRouteListResponseDTO {
        var endpoint = "/api/v1/inspections/routes"
        var queryItems: [URLQueryItem] = []
        if let statusFilter, !statusFilter.isEmpty {
            queryItems.append(URLQueryItem(name: "status_filter", value: statusFilter))
        }
        if let planDate, !planDate.isEmpty {
            queryItems.append(URLQueryItem(name: "plan_date", value: planDate))
        }
        if !queryItems.isEmpty {
            var components = URLComponents()
            components.queryItems = queryItems
            endpoint += components.percentEncodedQuery.map { "?\($0)" } ?? ""
        }
        return try await cloudGet(endpoint: endpoint)
    }

    func acceptInspectionRouteOnCloud(eventID: String) async throws -> CloudInspectionRouteDTO {
        try await cloudPost(endpoint: "/api/v1/inspections/routes/\(eventID)/accept", body: EmptyCloudRequest())
    }

    func rejectInspectionRouteOnCloud(
        eventID: String,
        reasonCode: String,
        reason: String?
    ) async throws -> CloudInspectionRouteDTO {
        try await cloudPost(
            endpoint: "/api/v1/inspections/routes/\(eventID)/reject",
            body: CloudInspectionRouteDecisionRequestDTO(reason_code: reasonCode, reason: reason)
        )
    }

    func getInspectionAvailabilityFromCloud(month: String) async throws -> CloudInspectionAvailabilityMonthDTO {
        try await cloudGet(endpoint: "/api/v1/inspections/availability?month=\(month)")
    }

    func upsertInspectionAvailabilityOnCloud(
        date: String,
        payload: CloudInspectionAvailabilityOverrideRequestDTO
    ) async throws -> CloudInspectionAvailabilityDayDTO {
        try await cloudPut(endpoint: "/api/v1/inspections/availability/\(date)", body: payload)
    }

    func getProfilesFromCloud() async throws -> [CloudProfileDTO] {
        try await cloudGet(endpoint: "/api/v1/profiles")
    }

    func updateCurrentProfileOnCloud(_ profile: CloudProfileUpdateRequestDTO) async throws -> CloudProfileDTO {
        try await cloudPut(endpoint: "/api/v1/profiles/me", body: profile)
    }

    func getProfileAssetFromCloud(userID: String, assetType: String) async throws -> Data {
        try await cloudDownload(endpoint: "/api/v1/profiles/\(userID)/assets/\(assetType)")
    }

    func getMonthlyConsuntivoFromCloud(year: Int, month: Int, mineOnly: Bool = true) async throws -> CloudConsuntivoMonthDTO {
        try await cloudGet(endpoint: "/api/v1/reports/consuntivo?year=\(year)&month=\(month)&mine_only=\(mineOnly)")
    }

    private func authorizedCloudRequest(url: URL) async throws -> URLRequest {
        let token = try await cloudLogin()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
    
    // MARK: - Helpers
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubAPIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            isConnected = true
            lastError = nil
            return
        case 400:
            throw HubAPIError.badRequest
        case 401, 403:
            throw HubAPIError.unauthorized
        case 404:
            throw HubAPIError.notFound
        case 500...599:
            throw HubAPIError.serverError(httpResponse.statusCode)
        default:
            throw HubAPIError.httpError(httpResponse.statusCode)
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

    private func makeMultipartBody(data: Data, fileName: String, mimeType: String, boundary: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}

// MARK: - Error Types

enum HubAPIError: Error, LocalizedError {
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
            return "Hub non configurato. Imposta l'URL nelle impostazioni."
        case .invalidURL:
            return "URL non valido"
        case .invalidResponse:
            return "Risposta non valida dal server"
        case .badRequest:
            return "Richiesta non valida"
        case .unauthorized:
            return "Non autorizzato. Effettua nuovamente il login."
        case .notFound:
            return "Risorsa non trovata"
        case .serverError(let code):
            return "Errore server (\(code))"
        case .httpError(let code):
            return "Errore HTTP (\(code))"
        }
    }
}

// MARK: - Request/Response DTOs

// Email
struct SendEmailRequest: Encodable {
    let to: [String]
    let cc: [String]?
    let bcc: [String]?
    let subject: String
    let body: String
    let isHtml: Bool
    let sinistroRiferimento: String?
    let attachments: [EmailAttachmentRequest]?
    let replyToMessageId: String?
}

struct EmailAttachmentRequest: Encodable {
    let filename: String
    let mimeType: String
    let data: String // base64
}

struct SendEmailResponse: Decodable {
    let messageId: String
    let threadId: String?
    let sentAt: Date
}

struct ScheduleEmailRequest: Encodable {
    let to: [String]
    let subject: String
    let body: String
    let scheduledFor: Date
    let sinistroRiferimento: String?
}

struct ScheduleEmailResponse: Decodable {
    let scheduleId: String
    let scheduledFor: Date
}

// WhatsApp
struct SendWhatsAppRequest: Encodable {
    let phoneNumber: String?
    let chatId: String?
    let message: String
    let mediaData: String? // base64
    let mediaType: String?
    let mediaFilename: String?
    let sinistroRiferimento: String?
}

struct SendWhatsAppResponse: Decodable {
    let messageId: String
    let sentAt: Date
}

struct ScheduleWhatsAppRequest: Encodable {
    let phoneNumber: String
    let message: String
    let scheduledFor: Date
    let sinistroRiferimento: String?
}

struct ScheduleWhatsAppResponse: Decodable {
    let scheduleId: String
    let scheduledFor: Date
}

struct CloudProfileDTO: Codable {
    let id: String
    let email: String
    let full_name: String
    let first_name: String
    let last_name: String
    let roles: [String]
    let avatar_type: String
    let avatar_asset_url: String?
    let avatar_gif_url: String?
    let signature_image_url: String?
    let enable_badges: Bool
    let send_read_receipts: Bool
    let email_signature_html: String?
    let email_signature_text: String?

    var displayName: String {
        let name = "\(first_name) \(last_name)".trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? full_name : name
    }
}

struct CloudProfileUpdateRequestDTO: Encodable {
    let first_name: String
    let last_name: String
    let job_title: String?
    let phone_number: String?
    let birth_date: Date?
    let birthday_visibility: String
    let notify_birthday: Bool
    let contract_type: String?
    let roles: [String]
    let avatar_type: String
    let avatar_photo_base64: String?
    let generated_avatar_color: String?
    let generated_avatar_icon: String?
    let avatar_gif_url: String?
    let enable_badges: Bool
    let send_read_receipts: Bool
    let email_signature_html: String?
    let email_signature_text: String?
}

private struct EmptyCloudRequest: Encodable {}

struct CloudProfileAssetDTO: Decodable {
    let asset_type: String
    let file_name: String
    let mime_type: String?
    let size_bytes: Int
    let asset_url: String
}

struct CloudConsuntivoMonthDTO: Codable {
    let anno: Int
    let mese: Int
    let scope: String
    let sinistri_assegnati: Int
    let sinistri_chiusi: Int
    let tot_liquidato: Double
    let tot_compensi: Double
    let tot_danno: Double
    let atti_inviati: Int
    let media_giornaliera: Double
    let daily_stats: [CloudConsuntivoDailyStatDTO]
    let company_stats: [CloudConsuntivoCompanyStatDTO]
    let sinistri_del_mese: [CloudConsuntivoClaimItemDTO]
}

struct CloudConsuntivoDailyStatDTO: Codable {
    let giorno: Int
    let assegnazioni: Int
    let chiusure: Int
    let atti_inviati: Int
}

struct CloudConsuntivoCompanyStatDTO: Codable {
    let codice_compagnia: String
    let nome_compagnia: String
    let gruppo_compagnia: String?
    let assegnazioni: Int
    let chiusure: Int
    let atti_inviati: Int
    let liquidato_totale: Double
}

struct CloudConsuntivoClaimItemDTO: Codable {
    let id: String
    let riferimento: String
    let stato: String
    let nome_assicurato: String
    let nome_compagnia: String
    let data_assegnazione: Date?
    let data_chiusura: Date?
    let stima_danno: Double?
    let liquidato: Double?
}

// Sinistri
struct SinistroDTO: Codable, Identifiable {
    let id: String
    let riferimento: String
    let garanzia: String?
    let nomeAssicurato: String
    let nomeContraente: String?
    let nomeCompagnia: String
    let stato: String
    let statoDetail: String?
    let dataAssegnazione: Date?
    let dataChiusura: Date?
    let dataSinistro: Date?
    let luogoSinistro: String?
    let numeroPolizza: String?
    let tipoPolizza: String?
    let stimaDanno: Double?
    let liquidato: Double?
    let telefonoContraente: String?
    let emailContraente: String?
    let telefonoAssicurato: String?
    let emailAssicurato: String?
    let assignedToUserEmail: String?
    let ownerEmail: String?
    
    var isOpen: Bool {
        let closedStates = ["chiuso", "definito", "revocato", "annullato"]
        return !closedStates.contains(stato.lowercased())
    }

    init(from dto: CloudClaimDTO) {
        self.id = dto.id
        self.riferimento = dto.external_ref ?? dto.id
        self.garanzia = dto.garanzia
        self.nomeAssicurato = dto.nome_assicurato ?? ""
        self.nomeContraente = nil
        self.nomeCompagnia = dto.compagnia ?? ""
        self.stato = dto.stato_corrente
        self.statoDetail = nil
        self.dataAssegnazione = dto.created_at
        self.dataChiusura = dto.closed_at
        self.dataSinistro = dto.data_sinistro
        self.luogoSinistro = nil
        self.numeroPolizza = dto.numero_polizza
        self.tipoPolizza = dto.tipo_polizza
        self.stimaDanno = nil
        self.liquidato = dto.liquidato
        self.telefonoContraente = nil
        self.emailContraente = nil
        self.telefonoAssicurato = nil
        self.emailAssicurato = nil
        self.assignedToUserEmail = nil
        self.ownerEmail = nil
    }
}

// Diario
struct DiarioEntryHubDTO: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let tipo: String
    let titolo: String?
    let riassunto: String
    let contenutoCompleto: String?
    let createdBy: String?
    let emailMessageId: String?
    let whatsAppChatId: String?
}

struct CreateDiarioEntryRequest: Encodable {
    let tipo: String
    let titolo: String?
    let testo: String
}

// Vault
struct VaultFileDTO: Codable, Identifiable {
    let id: String
    let sinistroRef: String
    let filename: String
    let folder: String
    let size: Int64
    let mimeType: String?
    let createdAt: Date
}

struct FolderRequestResponse: Decodable {
    let requestId: String
    let status: String
    let estimatedReadyAt: Date?
}

struct FolderRequestStatus: Decodable {
    let requestId: String
    let status: String // pending, processing, ready, failed
    let downloadUrl: String?
    let expiresAt: Date?
    let errorMessage: String?
}

// Health
struct HealthResponse: Codable {
    let status: String
    let version: String
    let uptime: TimeInterval?
    let timestamp: Date?
}

struct CloudLoginRequest: Encodable {
    let username: String
    let password: String
}

struct CloudTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let token_type: String
}

struct CloudClaimListResponseDTO: Decodable {
    let items: [CloudClaimDTO]
    let total: Int
    let page: Int
    let page_size: Int
}

struct CloudClaimDTO: Decodable {
    let id: String
    let external_ref: String?
    let numero_sinistro: String?
    let compagnia: String?
    let stato_corrente: String
    let garanzia: String?
    let agenzia: String?
    let nome_assicurato: String?
    let data_sinistro: Date?
    let numero_polizza: String?
    let tipo_polizza: String?
    let richiesta: Double?
    let liquidato: Double?
    let closed_at: Date?
    let created_at: Date
}

struct CloudDiaryEntryListResponseDTO: Decodable {
    let items: [CloudDiaryEntryDTO]
    let total: Int
}

struct CloudDiaryEntryDTO: Decodable {
    let id: String
    let tenant_id: String
    let claim_id: String
    let entry_type: String
    let title: String?
    let body_text: String?
    let visibility: String
    let happened_at: Date
    let created_at: Date
    let created_by_user_id: String?
}

struct CloudDiaryEntryCreateRequestDTO: Encodable {
    let entry_type: String
    let title: String?
    let body_text: String?
    let visibility: String
    let happened_at: Date?
}

struct CloudEmailListResponseDTO: Decodable {
    let items: [CloudEmailDTO]
    let total: Int
}

struct CloudEmailDTO: Decodable {
    let id: String
    let tenant_id: String
    let message_id: String
    let thread_id: String?
    let from_address: String
    let to_addresses: String?
    let cc_addresses: String?
    let subject: String?
    let body_text: String?
    let body_html: String?
    let received_at: Date
    let ingested_at: Date
    let status: String
    let mailbox_id: String?
    let provider_id: String?
}

// MARK: - Programmazione DTOs (usati localmente, sincronizzati via CloudKit KV Store)

struct WorkDayDTO: Codable, Identifiable {
    var id: String { "\(anno)-\(mese)-\(giorno)" }
    let anno: Int
    let mese: Int
    let giorno: Int
    let isLavorativo: Bool
    let orari: [OrarioDTO]?
    let nota: String?
    let isFestivo: Bool
    let nomeFestivita: String?
}

struct OrarioDTO: Codable, Identifiable {
    let id: String
    let inizio: String // "HH:mm"
    let fine: String // "HH:mm"
    let luogo: String // "office" | "remote"
}

struct WorkDayUpdateDTO: Codable {
    let isLavorativo: Bool
    let orari: [OrarioDTO]?
    let nota: String?
}
