import Foundation
import Security

@MainActor
final class BackendAPIClient {
    static let shared = BackendAPIClient()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let tokenService = "com.perx.backend.auth"
    private let tokenKey = "perx_backend_access_token"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    var isConfigured: Bool {
        !resolvedBaseURLString.isEmpty
    }

    var hasAccessToken: Bool {
        backendAccessToken != nil
    }

    func storeAccessToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearAccessToken()
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: trimmed.data(using: .utf8) ?? Data()
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func clearAccessToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenKey
        ]

        SecItemDelete(query as CFDictionary)
    }

    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        var request = try makeRequest(path: path, method: "GET", queryItems: queryItems)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    func put<B: Encodable, T: Decodable>(_ path: String, body: B, queryItems: [URLQueryItem] = []) async throws -> T {
        var request = try makeRequest(path: path, method: "PUT", queryItems: queryItems)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    func post<B: Encodable, T: Decodable>(_ path: String, body: B, queryItems: [URLQueryItem] = []) async throws -> T {
        var request = try makeRequest(path: path, method: "POST", queryItems: queryItems)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    func delete(_ path: String, queryItems: [URLQueryItem] = []) async throws {
        let request = try makeRequest(path: path, method: "DELETE", queryItems: queryItems)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    func download(_ path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        let request = try makeRequest(path: path, method: "GET", queryItems: queryItems)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    func upload<T: Decodable>(_ path: String, data: Data, fileName: String, mimeType: String) async throws -> T {
        var request = try makeRequest(path: path, method: "PUT", queryItems: [])
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeMultipartBody(
            data: data,
            fileName: fileName,
            mimeType: mimeType,
            boundary: boundary
        )

        let (responseData, response) = try await session.data(for: request)
        try validate(response: response, data: responseData)
        return try decoder.decode(T.self, from: responseData)
    }

    private func makeRequest(path: String, method: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        guard !resolvedBaseURLString.isEmpty else {
            throw BackendAPIError.notConfigured
        }

        var base = resolvedBaseURLString
        if !base.hasSuffix("/") {
            base += "/"
        }

        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(string: base + normalizedPath) else {
            throw BackendAPIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw BackendAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token = backendAccessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw BackendAPIError.unauthorized
        case 404:
            throw BackendAPIError.notFound
        default:
            let body = String(data: data, encoding: .utf8)
            throw BackendAPIError.server(body ?? "HTTP \(httpResponse.statusCode)")
        }
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

    private var resolvedBaseURLString: String {
        let raw = HubConfigService.shared.cloudAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "" }
        if raw.contains("/api/") {
            return raw
        }
        return raw + "/api/v1"
    }

    private var backendAccessToken: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }
}

enum BackendAPIError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Backend FastAPI non configurato"
        case .invalidURL:
            return "URL backend non valido"
        case .invalidResponse:
            return "Risposta backend non valida"
        case .unauthorized:
            return "Autenticazione backend richiesta"
        case .notFound:
            return "Risorsa backend non trovata"
        case .server(let message):
            return message
        }
    }
}
