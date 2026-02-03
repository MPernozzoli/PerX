//
//  HubAPIClient.swift
//  PerX per iPad
//
//  Client HTTP per comunicare con l'Hub centralizzato.
//  Versione iOS del client - condivide la stessa API del Mac.
//

import Foundation
import Combine

/// Client HTTP per comunicare con l'Hub centralizzato
@MainActor
class HubAPIClient: ObservableObject {
    static let shared = HubAPIClient()
    
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?
    
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // Hub URL - da configurare nelle impostazioni
    private var _hubBaseURL: String = ""
    var hubBaseURL: String {
        get { _hubBaseURL }
        set { 
            _hubBaseURL = newValue
            UserDefaults.standard.set(newValue, forKey: "hubBaseURL")
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
        // Recupera token da GoogleAuthServiceiOS
        return GoogleAuthServiceiOS.shared.accessToken
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
    
    /// Recupera dettaglio sinistro
    func getSinistro(riferimento: String) async throws -> SinistroDTO {
        let url = try url(path: "claims/\(riferimento)")
        var httpRequest = authorizedRequest(url: url)
        httpRequest.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        return try decoder.decode(SinistroDTO.self, from: data)
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

// Sinistri
struct SinistroDTO: Codable, Identifiable {
    let id: String
    let riferimento: String
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
