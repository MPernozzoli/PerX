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
    
    private var baseURL: URL? {
        let urlString = HubConfigService.shared.hubBaseURL
        return URL(string: urlString)
    }
    
    private func url(path: String) throws -> URL {
        guard let base = baseURL else {
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
    
    // MARK: - Health
    
    func checkHealth() async throws -> HealthResponse {
        let url = try url(path: "health")
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        
        let health = try decoder.decode(HealthResponse.self, from: data)
        isConnected = true
        return health
    }
    
    // MARK: - Heartbeat
    
    /// Invia heartbeat per segnalare che il client è attivo
    func sendHeartbeat(userId: String, clientInfo: String? = nil) async throws {
        let url = try url(path: "heartbeat")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
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
    func listFiles(sinistroRef: String) async throws -> [VaultFileDTO] {
        let url = try url(path: "vault/sinistri/\(sinistroRef)/files")
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        return try decoder.decode([VaultFileDTO].self, from: data)
    }
    
    /// Stato cartella sinistro
    func getSinistroFolderStatus(sinistroRef: String) async throws -> SinistroFolderDTO {
        let url = try url(path: "vault/sinistri/\(sinistroRef)/status")
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        return try decoder.decode(SinistroFolderDTO.self, from: data)
    }
    
    /// Crea cartella sinistro
    func createSinistroFolder(sinistroRef: String) async throws -> SinistroFolderDTO {
        let url = try url(path: "vault/sinistri/\(sinistroRef)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(SinistroFolderDTO.self, from: data)
    }
    
    /// Garantisce che la cartella sinistro sia disponibile (crea se necessario)
    func ensureFolderAvailable(sinistroRef: String) async throws -> SinistroFolderDTO {
        do {
            return try await getSinistroFolderStatus(sinistroRef: sinistroRef)
        } catch HubAPIError.notFound {
            return try await createSinistroFolder(sinistroRef: sinistroRef)
        }
    }
    
    /// Download file
    func downloadFile(fileId: String) async throws -> Data {
        let url = try url(path: "vault/files/\(fileId)/download")
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        return data
    }
    
    /// Upload file
    func uploadFile(sinistroRef: String, filename: String, folder: String, data: Data) async throws -> VaultFileDTO {
        let url = try url(path: "vault/sinistri/\(sinistroRef)/upload")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
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
    func deleteFile(fileId: String) async throws {
        let url = try url(path: "vault/files/\(fileId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }
    
    /// Sposta file in _export
    func moveToExport(fileId: String) async throws -> VaultFileDTO {
        let url = try url(path: "vault/files/\(fileId)/export")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(VaultFileDTO.self, from: data)
    }
    
    // MARK: - Job Operations
    
    /// Lista job pendenti
    func getPendingJobs(limit: Int = 10) async throws -> [JobDTO] {
        let url = try url(path: "jobs/pending?limit=\(limit)")
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        return try decoder.decode([JobDTO].self, from: data)
    }
    
    /// Crea job import cartella
    func createImportFolderJob(sinistroRef: String, legacyPath: String) async throws -> JobDTO {
        let url = try url(path: "jobs/import/folder")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
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
    func get<T: Decodable>(endpoint: String) async throws -> T {
        let url = try url(path: endpoint)
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }
    
    /// POST generico con body e risposta decodificata
    func post<B: Encodable, T: Decodable>(endpoint: String, body: B) async throws -> T {
        let url = try url(path: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }
    
    /// POST generico con body, senza risposta (void)
    func post<B: Encodable>(endpoint: String, body: B) async throws {
        let url = try url(path: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }
    
    /// DELETE generico
    func delete(endpoint: String) async throws {
        let url = try url(path: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
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
