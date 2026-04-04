//
//  GoogleAuthServiceiOS.swift
//  PerX per iPad
//
//  Autenticazione Google per iOS usando ASWebAuthenticationSession.
//  Non usa server locale, ma redirect scheme custom.
//

import Foundation
import AuthenticationServices
import Security
import Combine

@MainActor
final class GoogleAuthServiceiOS: NSObject, ObservableObject {
    static let shared = GoogleAuthServiceiOS()
    
    // MARK: - Published State
    
    @Published private(set) var isAuthenticated = false
    @Published private(set) var userEmail: String?
    @Published private(set) var userName: String?
    @Published var errorMessage: String?
    
    // MARK: - OAuth Config
    
    // iOS Client ID da Google Cloud Console
    private let clientId = "150443834793-vn4s39ofgbgr695vq3h5k2agf2asomcu.apps.googleusercontent.com"
    private let redirectScheme = "com.googleusercontent.apps.150443834793-vn4s39ofgbgr695vq3h5k2agf2asomcu"
    private let redirectUri: String
    
    // Scope: solo identity (NO gmail.readonly/modify su iPad - usa CK)
    private let scope = "email profile openid"
    
    private let service = "com.perx.googleauth.ipad"
    
    // MARK: - Web Auth Session
    
    private var webAuthSession: ASWebAuthenticationSession?
    private var presentationAnchor: ASPresentationAnchor?
    
    // MARK: - Init
    
    private override init() {
        self.redirectUri = "\(redirectScheme):/oauth2callback"
        super.init()
    }
    
    // MARK: - Sync Token Access
    
    /// Token corrente (senza refresh, per uso sync)
    var accessToken: String? {
        loadFromKeychain(forKey: "access_token")
    }
    
    // MARK: - Public API
    
    func checkAuthenticationState() async {
        guard let accessToken = loadFromKeychain(forKey: "access_token") else {
            isAuthenticated = false
            return
        }
        
        // Verifica token con userinfo
        if await fetchUserInfo(accessToken: accessToken) {
            isAuthenticated = true
        } else {
            // Prova refresh
            if let refreshToken = loadFromKeychain(forKey: "refresh_token") {
                do {
                    let newToken = try await refreshAccessToken(refreshToken)
                    saveToKeychain(token: newToken, forKey: "access_token")
                    if await fetchUserInfo(accessToken: newToken) {
                        isAuthenticated = true
                        return
                    }
                } catch {
                    print("[GoogleAuthiOS] ❌ Refresh token fallito: \(error)")
                }
            }
            
            // Token non valido
            signOut()
        }
    }
    
    func signIn() async throws {
        let authURL = buildAuthURL()
        
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: redirectScheme
            ) { [weak self] callbackURL, error in
                guard let self else {
                    continuation.resume(throwing: AuthError.unknown)
                    return
                }
                
                if let error = error as? ASWebAuthenticationSessionError {
                    if error.code == .canceledLogin {
                        continuation.resume(throwing: AuthError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                
                guard let callbackURL,
                      let code = self.extractCode(from: callbackURL) else {
                    continuation.resume(throwing: AuthError.noCode)
                    return
                }
                
                Task { @MainActor in
                    do {
                        try await self.handleAuthCode(code)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            
            self.webAuthSession = session
            
            if !session.start() {
                continuation.resume(throwing: AuthError.sessionFailed)
            }
        }
    }
    
    func signOut() {
        removeFromKeychain(forKey: "access_token")
        removeFromKeychain(forKey: "refresh_token")
        UserDefaults.standard.removeObject(forKey: "google_token_expiry_ipad")
        
        isAuthenticated = false
        userEmail = nil
        userName = nil
        
        print("[GoogleAuthiOS] 🔓 Logout completato")
    }
    
    func getAccessToken() async throws -> String {
        // Verifica scadenza
        if let expiry = loadTokenExpiry(), expiry.timeIntervalSinceNow < 300 {
            // Refresh preventivo
            if let refreshToken = loadFromKeychain(forKey: "refresh_token") {
                let newToken = try await refreshAccessToken(refreshToken)
                saveToKeychain(token: newToken, forKey: "access_token")
                return newToken
            }
        }
        
        if let token = loadFromKeychain(forKey: "access_token") {
            return token
        }
        
        throw AuthError.noAccessToken
    }
    
    // MARK: - Private
    
    private func buildAuthURL() -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components.url!
    }
    
    private func extractCode(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "code" })?.value
    }
    
    private func handleAuthCode(_ code: String) async throws {
        let tokenResponse = try await exchangeCodeForToken(code: code)
        
        saveToKeychain(token: tokenResponse.accessToken, forKey: "access_token")
        if let refreshToken = tokenResponse.refreshToken {
            saveToKeychain(token: refreshToken, forKey: "refresh_token")
        }
        
        let expiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        saveTokenExpiry(expiry)
        
        guard await fetchUserInfo(accessToken: tokenResponse.accessToken) else {
            throw AuthError.userInfoFailed
        }
        
        // Salva account per login futuro
        await AccountManager.shared.saveAccount(
            email: userEmail ?? "",
            displayName: userName ?? userEmail ?? "",
            refreshToken: tokenResponse.refreshToken
        )
        
        isAuthenticated = true
        print("[GoogleAuthiOS] ✅ Login completato per: \(userEmail ?? "?")")
    }
    
    /// Login con refresh token salvato (per account già registrati)
    func signInWithRefreshToken(_ refreshToken: String) async throws {
        let newToken = try await refreshAccessToken(refreshToken)
        saveToKeychain(token: newToken, forKey: "access_token")
        
        guard await fetchUserInfo(accessToken: newToken) else {
            throw AuthError.userInfoFailed
        }
        
        // Aggiorna account
        await AccountManager.shared.saveAccount(
            email: userEmail ?? "",
            displayName: userName ?? userEmail ?? "",
            refreshToken: refreshToken
        )
        
        isAuthenticated = true
        print("[GoogleAuthiOS] ✅ Login con refresh token per: \(userEmail ?? "?")")
    }
    
    private func exchangeCodeForToken(code: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let params = [
            "client_id": clientId,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirectUri
            // Nota: su iOS non serve client_secret per app native
        ]
        
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[GoogleAuthiOS] ❌ Token exchange failed: \(body)")
            throw AuthError.tokenExchangeFailed
        }
        
        let json = try JSONDecoder().decode(TokenResponseJSON.self, from: data)
        return TokenResponse(
            accessToken: json.access_token,
            refreshToken: json.refresh_token,
            expiresIn: json.expires_in ?? 3600
        )
    }
    
    private func refreshAccessToken(_ refreshToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let params = [
            "client_id": clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = params
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.refreshFailed
        }
        
        let json = try JSONDecoder().decode(TokenResponseJSON.self, from: data)
        let expiry = Date().addingTimeInterval(TimeInterval(json.expires_in ?? 3600))
        saveTokenExpiry(expiry)
        
        return json.access_token
    }
    
    @discardableResult
    private func fetchUserInfo(accessToken: String) async -> Bool {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }
            
            let json = try JSONDecoder().decode(UserInfoResponse.self, from: data)
            self.userEmail = json.email
            self.userName = json.name ?? json.email.components(separatedBy: "@").first
            return true
        } catch {
            print("[GoogleAuthiOS] ❌ Fetch userinfo failed: \(error)")
            return false
        }
    }
    
    // MARK: - Keychain
    
    private func saveToKeychain(token: String, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: token.data(using: .utf8)!
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
        
        if status == errSecSuccess,
           let data = result as? Data,
           let token = String(data: data, encoding: .utf8) {
            return token
        }
        return nil
    }
    
    private func removeFromKeychain(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    private func saveTokenExpiry(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "google_token_expiry_ipad")
    }
    
    private func loadTokenExpiry() -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: "google_token_expiry_ipad")
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }
    
    // MARK: - Types
    
    enum AuthError: LocalizedError {
        case cancelled
        case noCode
        case sessionFailed
        case tokenExchangeFailed
        case refreshFailed
        case userInfoFailed
        case noAccessToken
        case unknown
        
        var errorDescription: String? {
            switch self {
            case .cancelled: return "Login annullato"
            case .noCode: return "Codice autorizzazione mancante"
            case .sessionFailed: return "Impossibile avviare la sessione di autenticazione"
            case .tokenExchangeFailed: return "Errore scambio token"
            case .refreshFailed: return "Impossibile rinnovare il token"
            case .userInfoFailed: return "Impossibile ottenere informazioni utente"
            case .noAccessToken: return "Nessun token di accesso disponibile"
            case .unknown: return "Errore sconosciuto"
            }
        }
    }
    
    struct TokenResponse {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
    }
    
    private struct TokenResponseJSON: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int?
    }
    
    private struct UserInfoResponse: Decodable {
        let email: String
        let name: String?
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleAuthServiceiOS: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Su iOS, restituisce la prima window della scena attiva
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return UIWindow()
        }
        return window
    }
}
