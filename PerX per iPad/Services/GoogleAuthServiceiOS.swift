//
//  GoogleAuthServiceiOS.swift
//  PerX per iPad
//
//  Servizio di autenticazione iPad backend-first.
//  Mantiene lo stesso entrypoint usato dal resto dell'app.
//

import Foundation
import Security
import Combine

@MainActor
final class GoogleAuthServiceiOS: ObservableObject {
    static let shared = GoogleAuthServiceiOS()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var userEmail: String?
    @Published private(set) var userName: String?
    @Published var errorMessage: String?

    private let service = "com.perx.ipad.auth"
    private let session: URLSession
    private let hubClient = HubAPIClient.shared

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration)
    }

    var accessToken: String? {
        loadFromKeychain(forKey: "access_token")
    }

    func checkAuthenticationState() async {
        let baseURL = normalizedBaseURL()

        if let token = loadFromKeychain(forKey: "access_token"),
           await fetchUserInfo(accessToken: token, baseURL: baseURL) {
            isAuthenticated = true
            return
        }

        if let email = loadFromKeychain(forKey: "active_email"),
           let password = AccountManager.shared.getPassword(for: email),
           !password.isEmpty {
            do {
                try await signIn(
                    email: email,
                    password: password,
                    baseURL: baseURL,
                    persistAccount: false
                )
                return
            } catch {
                print("[iPadAuth] ❌ Ripristino sessione fallito: \(error)")
            }
        }

        signOut()
    }

    func signIn() async throws {
        throw AuthError.missingCredentials
    }

    func signIn(email: String, password: String, baseURL: String? = nil) async throws {
        try await signIn(email: email, password: password, baseURL: baseURL, persistAccount: true)
    }

    func signInWithStoredCredentials(email: String, baseURL: String? = nil) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let password = AccountManager.shared.getPassword(for: normalizedEmail),
              !password.isEmpty else {
            throw AuthError.missingSavedCredentials
        }

        try await signIn(email: normalizedEmail, password: password, baseURL: baseURL, persistAccount: true)
    }

    func signOut() {
        removeFromKeychain(forKey: "access_token")
        removeFromKeychain(forKey: "refresh_token")
        removeFromKeychain(forKey: "active_email")
        hubClient.clearCloudSession()

        isAuthenticated = false
        userEmail = nil
        userName = nil

        print("[iPadAuth] 🔓 Logout completato")
    }

    func getAccessToken() async throws -> String {
        guard let token = accessToken else {
            throw AuthError.noAccessToken
        }
        return token
    }

    private func signIn(
        email: String,
        password: String,
        baseURL: String?,
        persistAccount: Bool
    ) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedEmail.isEmpty, !normalizedPassword.isEmpty else {
            throw AuthError.missingCredentials
        }

        let normalizedBaseURL = normalizedBaseURL(override: baseURL)

        let tokenResponse = try await requestToken(
            email: normalizedEmail,
            password: normalizedPassword,
            baseURL: normalizedBaseURL
        )

        saveToKeychain(token: tokenResponse.access_token, forKey: "access_token")
        saveToKeychain(token: tokenResponse.refresh_token, forKey: "refresh_token")
        saveToKeychain(token: normalizedEmail, forKey: "active_email")

        hubClient.cloudAPIBaseURL = normalizedBaseURL
        hubClient.storeCloudSession(
            accessToken: tokenResponse.access_token,
            refreshToken: tokenResponse.refresh_token,
            email: normalizedEmail,
            password: normalizedPassword
        )

        guard await fetchUserInfo(accessToken: tokenResponse.access_token, baseURL: normalizedBaseURL) else {
            signOut()
            throw AuthError.userInfoFailed
        }

        if persistAccount {
            AccountManager.shared.saveAccount(
                email: normalizedEmail,
                displayName: userName ?? userEmail ?? normalizedEmail,
                password: normalizedPassword
            )
        }

        isAuthenticated = true
        print("[iPadAuth] ✅ Login completato per: \(normalizedEmail)")
    }

    private func requestToken(email: String, password: String, baseURL: String) async throws -> TokenResponseJSON {
        guard let url = URL(string: "\(baseURL)/api/v1/auth/login") else {
            throw AuthError.invalidBackendURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(LoginRequest(username: email, password: password))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw AuthError.loginFailed(errorMessage(from: data, statusCode: httpResponse.statusCode))
        }

        return try JSONDecoder().decode(TokenResponseJSON.self, from: data)
    }

    @discardableResult
    private func fetchUserInfo(accessToken: String, baseURL: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/auth/me") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                return false
            }

            let user = try JSONDecoder().decode(UserInfoResponse.self, from: data)
            userEmail = user.email.lowercased()

            let preferredName = user.full_name.trimmingCharacters(in: .whitespacesAndNewlines)
            userName = preferredName.isEmpty
            ? user.email.components(separatedBy: "@").first
            : preferredName

            return true
        } catch {
            print("[iPadAuth] ❌ Fetch utente fallito: \(error)")
            return false
        }
    }

    private func normalizedBaseURL(override: String? = nil) -> String {
        let candidate = (override ?? HubAPIClient.fixedCloudAPIBaseURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = candidate.isEmpty ? HubAPIClient.fixedCloudAPIBaseURL : candidate
        return resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
    }

    private func errorMessage(from data: Data, statusCode: Int) -> String {
        if let backendError = try? JSONDecoder().decode(BackendErrorResponse.self, from: data),
           let detail = backendError.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty {
            return detail
        }

        switch statusCode {
        case 401:
            return "Credenziali non valide."
        case 404:
            return "Backend non trovato."
        default:
            return "Errore backend (\(statusCode))."
        }
    }

    private func saveToKeychain(token: String, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: token.data(using: .utf8) ?? Data()
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func removeFromKeychain(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum AuthError: LocalizedError {
        case missingCredentials
        case missingSavedCredentials
        case missingBackendURL
        case invalidBackendURL
        case invalidResponse
        case loginFailed(String)
        case userInfoFailed
        case noAccessToken

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "Inserisci email e password."
            case .missingSavedCredentials:
                return "Credenziali salvate mancanti per questo account."
            case .missingBackendURL:
                return "Endpoint backend non disponibile."
            case .invalidBackendURL:
                return "URL backend non valido."
            case .invalidResponse:
                return "Risposta backend non valida."
            case .loginFailed(let message):
                return message
            case .userInfoFailed:
                return "Login riuscito ma profilo utente non disponibile."
            case .noAccessToken:
                return "Nessun token di accesso disponibile."
            }
        }
    }

    private struct LoginRequest: Encodable {
        let username: String
        let password: String
    }

    private struct TokenResponseJSON: Decodable {
        let access_token: String
        let refresh_token: String
        let token_type: String
    }

    private struct UserInfoResponse: Decodable {
        let email: String
        let full_name: String
    }

    private struct BackendErrorResponse: Decodable {
        let detail: String?
    }
}
