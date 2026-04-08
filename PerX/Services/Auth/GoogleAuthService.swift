import Foundation
import AppKit

@MainActor
class GoogleAuthService: ObservableObject {
    static let shared = GoogleAuthService()
    
    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var userName: String?
    @Published var errorMessage: String?
    @Published var needsReAuthentication = false
    
    var hasValidToken: Bool {
        if let token = getTokenFromKeychain(forKey: "google_access_token") {
            return !token.isEmpty
        }
        return false
    }
    
    private let service = "com.perx.googleauth"
    private let clientId = "150443834793-qcmmpkvm29tddfb9keirh3tevf78ansj.apps.googleusercontent.com"
    private let clientSecret = "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"
    private let redirectUri = "http://127.0.0.1:3000"
    private let scope = "email https://mail.google.com/ https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/userinfo.email openid"
    private let backendService = "com.perx.macos.auth"
    private let session = URLSession.shared
    private let decoder = JSONDecoder()
    
    /// Flag per evitare che il check venga rieseguito in loop
    private var hasCompletedInitialCheck = false
    /// Un solo check alla volta (evita race e risultati sbagliati)
    private var checkInProgress = false
    
    /// Risultato del check auth: nessuna modifica a @Published durante il check
    struct AuthCheckResult {
        let authenticated: Bool
        let email: String?
        let userName: String?
        let needsReAuth: Bool
    }
    
    /// Esegue il check senza toccare @Published. La view chiama poi applyAuthResult in modo differito.
    func checkAuthenticationState() async -> AuthCheckResult {
        if checkInProgress {
            return AuthCheckResult(authenticated: isAuthenticated, email: userEmail, userName: userName, needsReAuth: needsReAuthentication)
        }
        if hasCompletedInitialCheck && !isAuthenticated {
            return AuthCheckResult(authenticated: false, email: nil, userName: nil, needsReAuth: needsReAuthentication)
        }
        
        checkInProgress = true
        defer { checkInProgress = false }
        
        if let baseURL = normalizedBackendBaseURL(),
           let accessToken = loadBackendValue(forKey: "access_token"),
           let user = await fetchBackendUserInfo(accessToken: accessToken, baseURL: baseURL) {
            hasCompletedInitialCheck = true
            persistAuthenticatedUser(email: user.email, fullName: user.full_name)
            return AuthCheckResult(
                authenticated: true,
                email: user.email,
                userName: Self.resolveDisplayName(email: user.email, fullName: user.full_name),
                needsReAuth: false
            )
        }

        // Se c'è una sessione salvata ma non più valida, puliscila e richiedi selezione esplicita account.
        if loadBackendValue(forKey: "access_token") != nil {
            clearBackendSession()
        }

        hasCompletedInitialCheck = true
        return AuthCheckResult(authenticated: false, email: nil, userName: nil, needsReAuth: false)
    }
    
    /// Applica il risultato del check dopo un breve delay, quando il ciclo di rendering è concluso
    func applyAuthResult(_ result: AuthCheckResult) {
        let email = result.email
        let userName = result.userName
        let authenticated = result.authenticated
        let needsReAuth = result.needsReAuth
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.userEmail = email
            self.userName = userName
            self.isAuthenticated = authenticated
            self.needsReAuthentication = needsReAuth
        }
    }

    func signIn(email: String, password: String, baseURL: String? = nil) async throws {
        let resolvedBaseURL = try requiredBackendBaseURL(override: baseURL)
        _ = try await performBackendLogin(
            email: email,
            password: password,
            baseURL: resolvedBaseURL,
            persistAccount: true
        )
    }

    func signInWithStoredCredentials(email: String, baseURL: String? = nil) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let password = AccountManager.shared.getPassword(for: normalizedEmail),
              !password.isEmpty else {
            throw AuthError.missingSavedCredentials
        }

        try await signIn(email: normalizedEmail, password: password, baseURL: baseURL)
    }
    
    private func refreshAccessToken(_ refreshToken: String) async throws -> String {
        let tokenEndpoint = "https://oauth2.googleapis.com/token"
        let parameters = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Verifica se la risposta è un errore
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[GoogleAuth] ❌ Errore refresh token: \(httpResponse.statusCode) - \(errorBody)")
            throw NSError(domain: "GoogleAuth", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Errore refresh token: \(errorBody)"])
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        // Aggiorna data di scadenza
        let expirySeconds = tokenResponse.expires_in > 0 ? TimeInterval(tokenResponse.expires_in) : 3600
        saveTokenExpiry(Date().addingTimeInterval(expirySeconds))
        return tokenResponse.access_token
    }
    
    private func saveToKeychain(token: String, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: token.data(using: .utf8)!
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("❌ Errore salvataggio keychain: \(status)")
        }
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
    
    func getAccessToken() async throws -> String {
        // Verifica se il token è scaduto e refreshalo se necessario
        if let tokenExpiry = loadTokenExpiry() {
            // Se il token scade tra meno di 5 minuti, refreshalo preventivamente
            if tokenExpiry.timeIntervalSinceNow < 300 {
                print("[GoogleAuth] 🔄 Token in scadenza, refresh preventivo...")
                if let refreshToken = loadFromKeychain(forKey: "google_refresh_token") {
                    do {
                        let newToken = try await refreshAccessToken(refreshToken)
                        saveToKeychain(token: newToken, forKey: "google_access_token")
                        // Salva nuova data di scadenza (tokens OAuth durano ~1 ora)
                        saveTokenExpiry(Date().addingTimeInterval(3600))
                        print("[GoogleAuth] ✅ Token refreshato preventivamente")
                        return newToken
                    } catch {
                        print("[GoogleAuth] ❌ Errore refresh preventivo: \(error)")
                        // Continua con il token esistente, potrebbe ancora essere valido
                    }
                }
            }
        }
        
        if let token = loadFromKeychain(forKey: "google_access_token") {
            return token
        }
        throw GoogleAuthError.noAccessToken
    }
    
    /// Refresh automatico del token quando si riceve un 401
    func refreshTokenIfNeeded() async -> Bool {
        guard let refreshToken = loadFromKeychain(forKey: "google_refresh_token") else {
            print("[GoogleAuth] ⚠️ Nessun refresh token disponibile, richiesta riautenticazione")
            requireReAuthentication()
            return false
        }
        
        do {
            let newToken = try await refreshAccessToken(refreshToken)
            saveToKeychain(token: newToken, forKey: "google_access_token")
            // Salva nuova data di scadenza (tokens OAuth durano ~1 ora)
            saveTokenExpiry(Date().addingTimeInterval(3600))
            print("[GoogleAuth] ✅ Token refreshato automaticamente dopo errore 401")
            return true
        } catch {
            print("[GoogleAuth] ❌ Errore refresh token: \(error) - richiesta riautenticazione")
            requireReAuthentication()
            return false
        }
    }
    
    /// Forza la riautenticazione: pulisce i token e riporta alla SplashScreen
    func requireReAuthentication() {
        print("[GoogleAuth] 🔒 Sessione scaduta - richiesta riautenticazione all'utente")
        
        removeFromKeychain(forKey: "google_access_token")
        removeFromKeychain(forKey: "google_refresh_token")
        saveTokenExpiry(Date.distantPast)
        hasCompletedInitialCheck = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.needsReAuthentication = true
            self.isAuthenticated = false
            self.userEmail = nil
            NotificationCenter.default.post(
                name: .init("GoogleAuthStateChanged"),
                object: nil,
                userInfo: ["signedOut": true, "sessionExpired": true]
            )
        }
    }
    
    private func saveTokenExpiry(_ date: Date) {
        let expiryTimestamp = date.timeIntervalSince1970
        UserDefaults.standard.set(expiryTimestamp, forKey: "google_token_expiry")
    }
    
    private func loadTokenExpiry() -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: "google_token_expiry")
        if timestamp > 0 {
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }
    
    func signOut() {
        if let email = userEmail, loadFromKeychain(forKey: "google_refresh_token") != nil {
            let userId = email.components(separatedBy: "@").first ?? email
            Task { await deleteTokenFromHub(userId: userId) }
        }
        
        clearBackendSession()
        removeFromKeychain(forKey: "google_access_token")
        removeFromKeychain(forKey: "google_refresh_token")
        UserDefaults.standard.removeObject(forKey: "google_token_expiry")
        UserDefaults.standard.removeObject(forKey: "last_google_user_id")
        UserDefaults.standard.removeObject(forKey: "current_user_email")
        UserDefaults.standard.removeObject(forKey: "userEmail")
        hasCompletedInitialCheck = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.isAuthenticated = false
            self.userEmail = nil
            self.userName = nil
            NotificationCenter.default.post(name: .init("GoogleAuthStateChanged"), object: nil, userInfo: ["signedOut": true])
        }
    }
    
    /// Elimina il token dall'Hub
    private func deleteTokenFromHub(userId: String) async {
        do {
            let hubClient = HubAPIClient.shared
            try await hubClient.delete(endpoint: "/auth/token/\(userId)")
            print("[GoogleAuth] ✅ Token eliminato dall'Hub per: \(userId)")
        } catch {
            print("[GoogleAuth] ⚠️ Impossibile eliminare token dall'Hub: \(error)")
        }
    }
    
    func signIn() {
        let configuredEmail = HubConfigService.shared.cloudAPIEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let storedPassword = AccountManager.shared.getPassword(for: configuredEmail),
           !configuredEmail.isEmpty,
           !storedPassword.isEmpty {
            Task {
                do {
                    try await signIn(email: configuredEmail, password: storedPassword)
                } catch {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
            return
        }

        let urlString = "https://accounts.google.com/o/oauth2/v2/auth?" +
            "client_id=\(clientId)" +
            "&redirect_uri=\(redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" +
            "&response_type=code" +
            "&scope=\(scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" +
            "&access_type=offline" +
            "&prompt=consent"
        
        if let url = URL(string: urlString) {
            print("🔐 Apertura URL di autenticazione: \(url.absoluteString)")
            NSWorkspace.shared.open(url)
            
            // Avvia il server locale per gestire il callback
            LocalServer.shared.onCodeReceived = { [weak self] code in
                Task {
                    await self?.handleAuthCode(code)
                }
            }
            LocalServer.shared.start()
        }
    }
    
    private func handleAuthCode(_ code: String) async {
        do {
            let tokenResponse = try await exchangeCodeForToken(code: code)
            saveToKeychain(token: tokenResponse.access_token, forKey: "google_access_token")
            // Salva data di scadenza (tokens OAuth durano ~1 ora, ma usiamo expires_in se disponibile)
            let expirySeconds = tokenResponse.expires_in > 0 ? TimeInterval(tokenResponse.expires_in) : 3600
            saveTokenExpiry(Date().addingTimeInterval(expirySeconds))
            
            if let refreshToken = tokenResponse.refresh_token {
                // Salva il refresh token per mantenere l'accesso
                saveToKeychain(token: refreshToken, forKey: "google_refresh_token")
            }
            
            let email = await fetchUserEmail(accessToken: tokenResponse.access_token)
            
            if let email = email {
                let userId = email.components(separatedBy: "@").first ?? email
                UserDefaults.standard.set(userId, forKey: "last_google_user_id")
            }
            if let refreshToken = tokenResponse.refresh_token, let email = email {
                Task { [weak self] in
                    await self?.registerTokenWithHub(email: email, refreshToken: refreshToken)
                }
            }
            
            let capturedEmail = email
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                self.userEmail = capturedEmail
                self.userName = capturedEmail.map { Self.resolveDisplayName(email: $0, fullName: nil) }
                self.isAuthenticated = true
                self.needsReAuthentication = false
                if let capturedEmail {
                    self.persistAuthenticatedUser(email: capturedEmail, fullName: nil)
                }
                NotificationCenter.default.post(name: .init("GoogleAuthStateChanged"), object: nil, userInfo: ["signedOut": false])
            }
            
            LocalServer.shared.stop()
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Errore autenticazione: \(error)")
        }
    }
    
    /// Registra il token con l'Hub per il Mail Worker
    private func registerTokenWithHub(email: String, refreshToken: String) async {
        do {
            let hubClient = HubAPIClient.shared
            
            // Estrai user_id dall'email (local-part)
            let userId = email.components(separatedBy: "@").first ?? email
            
            let payload: [String: String] = [
                "user_id": userId,
                "email": email,
                "refresh_token": refreshToken
            ]
            
            try await hubClient.post(endpoint: "/auth/register-token", body: payload)
            print("[GoogleAuth] ✅ Token registrato con Hub per: \(userId)")
            
        } catch {
            // Non blocchiamo l'autenticazione se l'Hub non è raggiungibile
            print("[GoogleAuth] ⚠️ Impossibile registrare token con Hub: \(error)")
        }
    }
    
    private func exchangeCodeForToken(code: String) async throws -> TokenResponse {
        let tokenEndpoint = "https://oauth2.googleapis.com/token"
        let parameters = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirectUri
        ]
        
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
    
    /// Recupera le info utente da Google e restituisce l'email (senza modificare @Published)
    private func fetchUserEmail(accessToken: String) async -> String? {
        let userInfoEndpoint = "https://www.googleapis.com/oauth2/v2/userinfo"
        var request = URLRequest(url: URL(string: userInfoEndpoint)!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Verifica status HTTP
            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
                    print("❌ Errore recupero info utente - Status: \(httpResponse.statusCode), Body: \(errorBody)")
                    return nil
                }
            }
            
            let userInfo = try JSONDecoder().decode(UserInfo.self, from: data)
            
            if userInfo.email == nil {
                print("⚠️ Risposta userinfo valida ma senza email")
            }
            return userInfo.email
        } catch {
            print("❌ Errore recupero info utente: \(error)")
            return nil
        }
    }
    
    private func getTokenFromKeychain(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
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

    private func normalizedBackendBaseURL(override: String? = nil) -> String? {
        let candidate = (override ?? HubConfigService.fixedCloudAPIBaseURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !candidate.isEmpty else { return nil }
        return candidate.hasSuffix("/") ? String(candidate.dropLast()) : candidate
    }

    private func requiredBackendBaseURL(override: String? = nil) throws -> String {
        guard let baseURL = normalizedBackendBaseURL(override: override) else {
            throw AuthError.missingBackendURL
        }
        return baseURL
    }

    private func performBackendLogin(
        email: String,
        password: String,
        baseURL: String,
        persistAccount: Bool
    ) async throws -> BackendLoginResult {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedEmail.isEmpty, !normalizedPassword.isEmpty else {
            throw AuthError.missingCredentials
        }

        guard let url = URL(string: "\(baseURL)/api/v1/auth/login") else {
            throw AuthError.invalidBackendURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(CloudAPILoginRequest(username: normalizedEmail, password: normalizedPassword))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw AuthError.loginFailed(errorMessage(from: data, statusCode: httpResponse.statusCode))
        }

        let tokenResponse = try decoder.decode(CloudAPITokenResponse.self, from: data)
        saveBackendValue(tokenResponse.access_token, forKey: "access_token")
        saveBackendValue(tokenResponse.refresh_token, forKey: "refresh_token")
        saveBackendValue(normalizedEmail, forKey: "active_email")

        BackendAPIClient.shared.storeAccessToken(tokenResponse.access_token)
        HubConfigService.shared.cloudAPIEmail = normalizedEmail
        HubAPIAdapterClient.shared.saveCloudPassword(normalizedPassword)
        HubAPIAdapterClient.shared.clearCloudSession()

        guard let user = await fetchBackendUserInfo(accessToken: tokenResponse.access_token, baseURL: baseURL) else {
            clearBackendSession()
            throw AuthError.userInfoFailed
        }

        let displayName = Self.resolveDisplayName(email: user.email, fullName: user.full_name)
        persistAuthenticatedUser(email: user.email, fullName: user.full_name)

        if persistAccount {
            AccountManager.shared.saveAccount(email: user.email, displayName: displayName, password: normalizedPassword)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.userEmail = user.email
            self.userName = displayName
            self.isAuthenticated = true
            self.needsReAuthentication = false
            NotificationCenter.default.post(name: .init("GoogleAuthStateChanged"), object: nil, userInfo: ["signedOut": false])
        }

        return BackendLoginResult(email: user.email, displayName: displayName)
    }

    private func fetchBackendUserInfo(accessToken: String, baseURL: String) async -> CloudAPIUserResponse? {
        guard let url = URL(string: "\(baseURL)/api/v1/auth/me") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                return nil
            }
            return try decoder.decode(CloudAPIUserResponse.self, from: data)
        } catch {
            print("[GoogleAuth] ❌ Fetch profilo backend fallito: \(error)")
            return nil
        }
    }

    private func saveBackendValue(_ value: String, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: backendService,
            kSecAttrAccount as String: key,
            kSecValueData as String: value.data(using: .utf8) ?? Data()
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadBackendValue(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: backendService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func removeBackendValue(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: backendService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func clearBackendSession() {
        removeBackendValue(forKey: "access_token")
        removeBackendValue(forKey: "refresh_token")
        removeBackendValue(forKey: "active_email")
        BackendAPIClient.shared.clearAccessToken()
        HubAPIAdapterClient.shared.clearCloudSession()
    }

    private func persistAuthenticatedUser(email: String, fullName: String?) {
        let normalizedEmail = email.lowercased()
        UserDefaults.standard.set(normalizedEmail, forKey: "current_user_email")
        UserDefaults.standard.set(normalizedEmail, forKey: "userEmail")

        let resolvedName = Self.resolveDisplayName(email: normalizedEmail, fullName: fullName)
        userEmail = normalizedEmail
        userName = resolvedName
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

    private static func resolveDisplayName(email: String, fullName: String?) -> String {
        let trimmed = fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return email.components(separatedBy: "@").first ?? email
    }
}

struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
    let token_type: String
}

struct UserInfo: Codable {
    let email: String?
    let id: String?
    let verified_email: Bool?
    let picture: String?
}

private struct BackendErrorResponse: Codable {
    let detail: String?
}

private struct BackendLoginResult {
    let email: String
    let displayName: String
}

extension GoogleAuthService {
    enum AuthError: LocalizedError {
        case missingCredentials
        case missingSavedCredentials
        case missingBackendURL
        case invalidBackendURL
        case invalidResponse
        case loginFailed(String)
        case userInfoFailed

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "Inserisci email e password."
            case .missingSavedCredentials:
                return "Credenziali salvate mancanti per questo account."
            case .missingBackendURL:
                return "Configura l'URL del backend prima di accedere."
            case .invalidBackendURL:
                return "URL backend non valido."
            case .invalidResponse:
                return "Risposta backend non valida."
            case .loginFailed(let message):
                return message
            case .userInfoFailed:
                return "Login riuscito ma profilo utente non disponibile."
            }
        }
    }
}
