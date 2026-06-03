import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case http(Int, String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL non valido"
        case .unauthorized: return "Sessione scaduta, effettua nuovamente l'accesso"
        case .http(let code, let body): return "Errore \(code): \(body)"
        case .decoding(let e): return "Errore decodifica: \(e.localizedDescription)"
        case .transport(let e): return e.localizedDescription
        }
    }
}

@MainActor
final class APIClient {
    static let shared = APIClient()

    var baseURL: String {
        UserDefaults.standard.string(forKey: "lite_api_base_url") ?? "https://api.perx.it"
    }

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let tokenKey = "lite_access_token"
    private let refreshKey = "lite_refresh_token"
    private let emailKey = "lite_user_email"

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

    // MARK: - Session

    var accessToken: String? { KeychainHelper.load(tokenKey) }
    var refreshToken: String? { KeychainHelper.load(refreshKey) }
    var userEmail: String? { UserDefaults.standard.string(forKey: emailKey) }

    var isLoggedIn: Bool { accessToken != nil }

    func clearSession() {
        KeychainHelper.delete(tokenKey)
        KeychainHelper.delete(refreshKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
    }

    // MARK: - Auth

    struct LoginRequest: Encodable { let username: String; let password: String }
    struct TokenResponse: Decodable { let access_token: String; let refresh_token: String; let token_type: String? }

    func login(email: String, password: String) async throws {
        let body = LoginRequest(username: email.lowercased(), password: password)
        let token: TokenResponse = try await rawRequest(
            path: "/api/v1/auth/login",
            method: "POST",
            body: body,
            authenticated: false
        )
        KeychainHelper.save(token.access_token, for: tokenKey)
        KeychainHelper.save(token.refresh_token, for: refreshKey)
        UserDefaults.standard.set(email.lowercased(), forKey: emailKey)
    }

    private struct RefreshRequest: Encodable { let refresh_token: String }

    private func refreshAccessToken() async throws {
        guard let refresh = refreshToken else { throw APIError.unauthorized }
        let token: TokenResponse = try await rawRequest(
            path: "/api/v1/auth/refresh",
            method: "POST",
            body: RefreshRequest(refresh_token: refresh),
            authenticated: false
        )
        KeychainHelper.save(token.access_token, for: tokenKey)
        KeychainHelper.save(token.refresh_token, for: refreshKey)
    }

    // MARK: - Generic requests

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path: path, method: "GET", body: Optional<EmptyBody>.none)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await request(path: path, method: "POST", body: body)
    }

    func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await request(path: path, method: "PUT", body: body)
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await request(path: path, method: "DELETE", body: Optional<EmptyBody>.none)
    }

    private struct EmptyBody: Encodable {}
    private struct EmptyResponse: Decodable {
        init(from decoder: Decoder) throws {}
        init() {}
    }

    private func request<T: Decodable, B: Encodable>(
        path: String,
        method: String,
        body: B?
    ) async throws -> T {
        do {
            return try await rawRequest(path: path, method: method, body: body, authenticated: true)
        } catch APIError.unauthorized {
            try await refreshAccessToken()
            return try await rawRequest(path: path, method: method, body: body, authenticated: true)
        }
    }

    private func rawRequest<T: Decodable, B: Encodable>(
        path: String,
        method: String,
        body: B?,
        authenticated: Bool
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(body)
        }
        if authenticated {
            guard let token = accessToken else { throw APIError.unauthorized }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(0, "")
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, text)
        }

        if data.isEmpty, let empty = EmptyResponse() as? T { return empty }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
