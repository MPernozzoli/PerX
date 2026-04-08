import Foundation

/// Client HTTP per comunicare con l'Hub centralizzato
@MainActor
class HubAPIClient: ObservableObject {
    static let shared = HubAPIClient()
    
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?
    
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Configuration
    
    private func baseURL(for tenantSlug: String? = nil) -> URL? {
        let urlString = HubConfigService.shared.resolvedHubBaseURL(for: tenantSlug)
        return URL(string: urlString)
    }
    
    private func url(path: String, tenantSlug: String? = nil) throws -> URL {
        guard let base = baseURL(for: tenantSlug) else {
            throw HubAPIError.notConfigured
        }
        // Usa string concatenation invece di appendingPathComponent
        // per preservare i query parameters (? e =)
        let baseString = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        guard let url = URL(string: baseString + path) else {
            throw HubAPIError.invalidURL
        }
        return url
    }

    private func currentTenantSlug(_ tenantSlug: String?) -> String {
        (tenantSlug ?? HubConfigService.shared.currentTenantSlug).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeRequest(url: URL, method: String = "GET", tenantSlug: String? = nil, contentType: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(currentTenantSlug(tenantSlug), forHTTPHeaderField: "X-PerX-Tenant")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }
    
    // MARK: - Health
    
    func checkHealth() async throws -> HealthResponse {
        let url = try url(path: "health")
        let request = makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        let health = try decoder.decode(HealthResponse.self, from: data)
        isConnected = true
        return health
    }
    
    // MARK: - Heartbeat
    
    /// Invia heartbeat per segnalare che il client è attivo
    func sendHeartbeat(userId: String, clientInfo: String? = nil, tenantSlug: String? = nil) async throws {
        let url = try url(path: "heartbeat", tenantSlug: tenantSlug)
        var request = makeRequest(url: url, method: "POST", tenantSlug: tenantSlug, contentType: "application/json")
        
        struct HeartbeatRequest: Encodable {
            let user_id: String
            let client_info: String?
        }
        
        request.httpBody = try encoder.encode(HeartbeatRequest(user_id: userId, client_info: clientInfo))
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }
    
    // MARK: - Vault Operations
    
    /// Lista file di un sinistro
    func listFiles(sinistroRef: String, tenantSlug: String? = nil) async throws -> [VaultFileDTO] {
        let url = try url(path: "vault/sinistri/\(sinistroRef)/files", tenantSlug: tenantSlug)
        let request = makeRequest(url: url, tenantSlug: tenantSlug)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode([VaultFileDTO].self, from: data)
    }
    
    /// Stato cartella sinistro
    func getSinistroFolderStatus(sinistroRef: String, tenantSlug: String? = nil) async throws -> SinistroFolderDTO {
        let url = try url(path: "vault/sinistri/\(sinistroRef)/status", tenantSlug: tenantSlug)
        let request = makeRequest(url: url, tenantSlug: tenantSlug)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(SinistroFolderDTO.self, from: data)
    }
    
    /// Crea cartella sinistro
    func createSinistroFolder(sinistroRef: String, tenantSlug: String? = nil) async throws -> SinistroFolderDTO {
        let url = try url(path: "vault/sinistri/\(sinistroRef)", tenantSlug: tenantSlug)
        var request = makeRequest(url: url, method: "POST", tenantSlug: tenantSlug)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(SinistroFolderDTO.self, from: data)
    }
    
    /// Garantisce che la cartella sinistro sia disponibile (crea se necessario)
    func ensureFolderAvailable(sinistroRef: String, tenantSlug: String? = nil) async throws -> SinistroFolderDTO {
        do {
            return try await getSinistroFolderStatus(sinistroRef: sinistroRef, tenantSlug: tenantSlug)
        } catch HubAPIError.notFound {
            return try await createSinistroFolder(sinistroRef: sinistroRef, tenantSlug: tenantSlug)
        }
    }
    
    /// Download file
    func downloadFile(fileId: String, tenantSlug: String? = nil) async throws -> Data {
        let url = try url(path: "vault/files/\(fileId)/download", tenantSlug: tenantSlug)
        let request = makeRequest(url: url, tenantSlug: tenantSlug)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return data
    }
    
    /// Upload file
    func uploadFile(sinistroRef: String, filename: String, folder: String, data: Data, tenantSlug: String? = nil) async throws -> VaultFileDTO {
        let url = try url(path: "vault/sinistri/\(sinistroRef)/upload", tenantSlug: tenantSlug)
        
        var request = makeRequest(url: url, method: "POST", tenantSlug: tenantSlug, contentType: "application/json")
        
        let uploadRequest = FileUploadRequest(
            filename: filename,
            folder: folder,
            data: data.base64EncodedString(),
            mimeType: mimeType(for: filename)
        )
        
        request.httpBody = try encoder.encode(uploadRequest)
        
        let (responseData, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(VaultFileDTO.self, from: responseData)
    }
    
    /// Elimina file
    func deleteFile(fileId: String, tenantSlug: String? = nil) async throws {
        let url = try url(path: "vault/files/\(fileId)", tenantSlug: tenantSlug)
        var request = makeRequest(url: url, method: "DELETE", tenantSlug: tenantSlug)
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }
    
    /// Sposta file in _export
    func moveToExport(fileId: String, tenantSlug: String? = nil) async throws -> VaultFileDTO {
        let url = try url(path: "vault/files/\(fileId)/export", tenantSlug: tenantSlug)
        var request = makeRequest(url: url, method: "POST", tenantSlug: tenantSlug)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(VaultFileDTO.self, from: data)
    }
    
    // MARK: - Job Operations
    
    /// Lista job pendenti
    func getPendingJobs(limit: Int = 10, tenantSlug: String? = nil) async throws -> [JobDTO] {
        let url = try url(path: "jobs/pending?limit=\(limit)", tenantSlug: tenantSlug)
        let request = makeRequest(url: url, tenantSlug: tenantSlug)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode([JobDTO].self, from: data)
    }
    
    /// Crea job import cartella
    func createImportFolderJob(sinistroRef: String, legacyPath: String, tenantSlug: String? = nil) async throws -> JobDTO {
        let url = try url(path: "jobs/import/folder", tenantSlug: tenantSlug)
        
        var request = makeRequest(url: url, method: "POST", tenantSlug: tenantSlug, contentType: "application/json")
        
        struct ImportRequest: Encodable {
            let sinistroRef: String
            let legacyPath: String
        }
        
        request.httpBody = try encoder.encode(ImportRequest(sinistroRef: sinistroRef, legacyPath: legacyPath))
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(JobDTO.self, from: data)
    }
    
    // MARK: - Generic HTTP Methods
    
    /// GET generico con risposta decodificata
    func get<T: Decodable>(endpoint: String, tenantSlug: String? = nil) async throws -> T {
        let url = try url(path: endpoint, tenantSlug: tenantSlug)
        let request = makeRequest(url: url, tenantSlug: tenantSlug)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }
    
    /// POST generico con body e risposta decodificata
    func post<B: Encodable, T: Decodable>(endpoint: String, body: B, tenantSlug: String? = nil) async throws -> T {
        let url = try url(path: endpoint, tenantSlug: tenantSlug)
        var request = makeRequest(url: url, method: "POST", tenantSlug: tenantSlug, contentType: "application/json")
        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }
    
    /// POST generico con body, senza risposta (void)
    func post<B: Encodable>(endpoint: String, body: B, tenantSlug: String? = nil) async throws {
        let url = try url(path: endpoint, tenantSlug: tenantSlug)
        var request = makeRequest(url: url, method: "POST", tenantSlug: tenantSlug, contentType: "application/json")
        request.httpBody = try encoder.encode(body)
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }
    
    /// DELETE generico
    func delete(endpoint: String, tenantSlug: String? = nil) async throws {
        let url = try url(path: endpoint, tenantSlug: tenantSlug)
        var request = makeRequest(url: url, method: "DELETE", tenantSlug: tenantSlug)
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }
    
    // MARK: - Helpers
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubAPIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
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
    
    private func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        let mimeTypes: [String: String] = [
            "pdf": "application/pdf",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "gif": "image/gif",
            "txt": "text/plain",
            "html": "text/html",
            "zip": "application/zip",
            "p7m": "application/pkcs7-mime",
        ]
        return mimeTypes[ext] ?? "application/octet-stream"
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
            return "Risorsa non trovata"
        case .serverError(let code):
            return "Errore server (\(code))"
        case .httpError(let code):
            return "Errore HTTP (\(code))"
        }
    }
}

// MARK: - DTO Types (mirror di PerXCore per il client)

struct VaultFileDTO: Codable, Identifiable {
    let id: String
    let sinistroRef: String
    let filename: String
    let folder: String
    let size: Int64
    let mimeType: String?
    let checksum: String?
    let createdAt: Date
    let modifiedAt: Date?
}

struct SinistroFolderDTO: Codable {
    let sinistroRef: String
    let status: String
    let fileCount: Int
    let totalSize: Int64
    let lastSyncAt: Date?
}

struct JobDTO: Codable, Identifiable {
    let id: String
    let type: String
    let status: String
    let priority: Int
    let createdAt: Date
    let startedAt: Date?
    let completedAt: Date?
    let errorMessage: String?
}

struct HealthResponse: Codable {
    let status: String
    let version: String
    let uptime: TimeInterval
    let timestamp: Date
}

struct FileUploadRequest: Codable {
    let filename: String
    let folder: String
    let data: String
    let mimeType: String?
}
