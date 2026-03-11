import Foundation
import AppKit

@MainActor
class GoogleAuthService: ObservableObject {
    static let shared = GoogleAuthService()
    
    @Published var isAuthenticated = false
    @Published var userEmail: String?
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
    private let hostedDomain = "actsrl.it"
    
    /// Flag per evitare che il check venga rieseguito in loop
    private var hasCompletedInitialCheck = false
    /// Un solo check alla volta (evita race e risultati sbagliati)
    private var checkInProgress = false
    
    /// Risultato del check auth: nessuna modifica a @Published durante il check
    struct AuthCheckResult {
        let authenticated: Bool
        let email: String?
        let needsReAuth: Bool
    }
    
    /// Esegue il check senza toccare @Published. La view chiama poi applyAuthResult in modo differito.
    func checkAuthenticationState() async -> AuthCheckResult {
        if checkInProgress {
            return AuthCheckResult(authenticated: isAuthenticated, email: userEmail, needsReAuth: needsReAuthentication)
        }
        if hasCompletedInitialCheck && !isAuthenticated {
            return AuthCheckResult(authenticated: false, email: nil, needsReAuth: needsReAuthentication)
        }
        
        checkInProgress = true
        defer { checkInProgress = false }
        
        // Solo token locale: niente Hub per mostrare dashboard senza token valido
        guard let accessToken = loadFromKeychain(forKey: "google_access_token") else {
            hasCompletedInitialCheck = true
            return AuthCheckResult(authenticated: false, email: nil, needsReAuth: false)
        }
        
        let email = await fetchUserEmail(accessToken: accessToken)
        
        if let email = email {
            hasCompletedInitialCheck = true
            // Registra con Hub in background (non tocca @Published)
            if let refreshToken = loadFromKeychain(forKey: "google_refresh_token") {
                Task { [weak self] in
                    await self?.registerTokenWithHub(email: email, refreshToken: refreshToken)
                }
            }
            return AuthCheckResult(authenticated: true, email: email, needsReAuth: false)
        }
        
        // Token non valido (401): rimuovilo subito
        removeFromKeychain(forKey: "google_access_token")
        
        guard let refreshToken = loadFromKeychain(forKey: "google_refresh_token") else {
            saveTokenExpiry(Date.distantPast)
            hasCompletedInitialCheck = true
            return AuthCheckResult(authenticated: false, email: nil, needsReAuth: true)
        }
        
        do {
            let newToken = try await refreshAccessToken(refreshToken)
            saveToKeychain(token: newToken, forKey: "google_access_token")
            let refreshedEmail = await fetchUserEmail(accessToken: newToken)
            
            if let refreshedEmail = refreshedEmail {
                Task { [weak self] in
                    await self?.registerTokenWithHub(email: refreshedEmail, refreshToken: refreshToken)
                }
            }
            hasCompletedInitialCheck = true
            return AuthCheckResult(authenticated: true, email: refreshedEmail, needsReAuth: false)
        } catch {
            print("❌ Errore refresh token: \(error)")
            removeFromKeychain(forKey: "google_refresh_token")
            saveTokenExpiry(Date.distantPast)
            hasCompletedInitialCheck = true
            return AuthCheckResult(authenticated: false, email: nil, needsReAuth: true)
        }
    }
    
    /// Applica il risultato del check dopo un breve delay, quando il ciclo di rendering è concluso
    func applyAuthResult(_ result: AuthCheckResult) {
        let email = result.email
        let authenticated = result.authenticated
        let needsReAuth = result.needsReAuth
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.userEmail = email
            self.isAuthenticated = authenticated
            self.needsReAuthentication = needsReAuth
        }
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
        if let email = userEmail {
            let userId = email.components(separatedBy: "@").first ?? email
            Task { await deleteTokenFromHub(userId: userId) }
        }
        
        removeFromKeychain(forKey: "google_access_token")
        removeFromKeychain(forKey: "google_refresh_token")
        UserDefaults.standard.removeObject(forKey: "google_token_expiry")
        UserDefaults.standard.removeObject(forKey: "last_google_user_id")
        hasCompletedInitialCheck = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.isAuthenticated = false
            self.userEmail = nil
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
        let urlString = "https://accounts.google.com/o/oauth2/v2/auth?" +
            "client_id=\(clientId)" +
            "&redirect_uri=\(redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" +
            "&response_type=code" +
            "&scope=\(scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" +
            "&access_type=offline" +
            "&prompt=consent" +
            "&hd=\(hostedDomain)"
        
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
                self.isAuthenticated = true
                self.needsReAuthentication = false
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
