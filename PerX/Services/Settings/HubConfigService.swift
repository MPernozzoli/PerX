import Foundation
import Combine

/// Configurazione per la connessione all'Hub centralizzato
/// Gestisce lo switch tra modalità locale (legacy) e cloud (Hub)
@MainActor
final class HubConfigService: ObservableObject {
    static let shared = HubConfigService()
    static let fixedCloudAPIBaseURL = "https://api.perx.it"

    struct TenantHubOverride: Codable, Equatable, Identifiable {
        var id: String { tenantSlug }
        var tenantSlug: String
        var baseURL: String
    }
    
    // MARK: - Published Properties
    
    /// Modalità gestione file: .local = ClaimSyncService legacy, .cloud = Vault su Hub
    @Published var fileManagementMode: ManagementMode {
        didSet {
            UserDefaults.standard.set(fileManagementMode.rawValue, forKey: "hub.fileManagementMode")
            UserDefaults.standard.set(Date(), forKey: "localEditAt.hub.fileManagementMode")
        }
    }
    
    /// Modalità gestione email: .local = MailManager locale, .cloud = Hub
    @Published var emailManagementMode: ManagementMode {
        didSet {
            UserDefaults.standard.set(emailManagementMode.rawValue, forKey: "hub.emailManagementMode")
            UserDefaults.standard.set(Date(), forKey: "localEditAt.hub.emailManagementMode")
        }
    }
    
    /// Modalità gestione WhatsApp: .local = Bridge locale, .cloud = Hub
    @Published var whatsappManagementMode: ManagementMode {
        didSet {
            UserDefaults.standard.set(whatsappManagementMode.rawValue, forKey: "hub.whatsappManagementMode")
            UserDefaults.standard.set(Date(), forKey: "localEditAt.hub.whatsappManagementMode")
        }
    }
    
    /// URL base dell'Hub (es. http://mac-mini.tailnet:8080)
    @Published private(set) var hubBaseURL: String {
        didSet {
            UserDefaults.standard.set(hubBaseURL, forKey: "hub.baseURL")
            UserDefaults.standard.set(Date(), forKey: "localEditAt.hub.baseURL")
            
            // Avvia/ferma timer quando URL cambia
            if !hubBaseURL.isEmpty {
                startHealthCheckTimer()
                startHeartbeatTimer()
            } else {
                stopHealthCheckTimer()
                stopHeartbeatTimer()
            }
        }
    }

    @Published private(set) var tenantHubOverrides: [String: TenantHubOverride] = [:]

    /// URL base del backend cloud (es. https://api.example.com)
    @Published private(set) var cloudAPIBaseURL: String

    /// Email usata per autenticarsi al backend cloud
    @Published var cloudAPIEmail: String {
        didSet {
            UserDefaults.standard.set(cloudAPIEmail, forKey: "cloud.api.email")
        }
    }
    
    /// Stato connessione Hub
    @Published private(set) var isHubReachable: Bool = false
    
    /// Ultimo controllo connessione
    @Published private(set) var lastHealthCheck: Date?
    
    /// Messaggio errore ultimo health check
    @Published private(set) var lastHealthCheckError: String?
    
    // MARK: - Private
    
    private var healthCheckTimer: Timer?
    private var heartbeatTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let tenantHubOverridesKey = "hub.tenantOverrides"
    
    // MARK: - Init
    
    private init() {
        // Solo Hub: default cloud per file e email; impostazioni condivise
        let savedFileMode = UserDefaults.standard.string(forKey: "hub.fileManagementMode") ?? ManagementMode.cloud.rawValue
        let savedEmailMode = UserDefaults.standard.string(forKey: "hub.emailManagementMode") ?? ManagementMode.cloud.rawValue
        let savedWAMode = UserDefaults.standard.string(forKey: "hub.whatsappManagementMode") ?? ManagementMode.cloud.rawValue
        let savedURL = UserDefaults.standard.string(forKey: "hub.baseURL") ?? Self.fixedCloudAPIBaseURL
        let savedCloudEmail = UserDefaults.standard.string(forKey: "cloud.api.email") ?? ""
        let savedOverrides = UserDefaults.standard.data(forKey: tenantHubOverridesKey)
        
        self.fileManagementMode = ManagementMode(rawValue: savedFileMode) ?? .cloud
        self.emailManagementMode = ManagementMode(rawValue: savedEmailMode) ?? .cloud
        self.whatsappManagementMode = ManagementMode(rawValue: savedWAMode) ?? .cloud
        self.hubBaseURL = savedURL.isEmpty ? Self.fixedCloudAPIBaseURL : Self.fixedCloudAPIBaseURL
        self.cloudAPIBaseURL = Self.fixedCloudAPIBaseURL
        self.cloudAPIEmail = savedCloudEmail
        UserDefaults.standard.set(Self.fixedCloudAPIBaseURL, forKey: "cloud.api.baseURL")
        UserDefaults.standard.set(Self.fixedCloudAPIBaseURL, forKey: "hub.baseURL")
        if let savedOverrides,
           let decoded = try? JSONDecoder().decode([String: TenantHubOverride].self, from: savedOverrides) {
            self.tenantHubOverrides = decoded
        }
        
        // Avvia health check e heartbeat periodici se URL configurato
        if !hubBaseURL.isEmpty {
            startHealthCheckTimer()
            startHeartbeatTimer()
        }
    }
    
    // MARK: - Health Check
    
    /// Verifica connessione all'Hub
    func checkHubHealth() async {
        let resolvedURL = resolvedHubBaseURL()
        guard !resolvedURL.isEmpty else {
            isHubReachable = false
            lastHealthCheckError = "URL Hub non configurato"
            return
        }
        
        guard let url = URL(string: "\(resolvedURL)/health") else {
            isHubReachable = false
            lastHealthCheckError = "URL non valido"
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                isHubReachable = false
                lastHealthCheckError = "Risposta non HTTP"
                return
            }
            
            if httpResponse.statusCode == 200 {
                isHubReachable = true
                lastHealthCheck = Date()
                lastHealthCheckError = nil
                
                // Parse response per debug
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("[HubConfig] Health OK: \(json)")
                }
            } else {
                isHubReachable = false
                lastHealthCheckError = "HTTP \(httpResponse.statusCode)"
            }
        } catch {
            isHubReachable = false
            lastHealthCheckError = error.localizedDescription
            print("[HubConfig] Health check failed: \(error)")
        }
    }
    
    /// Avvia timer health check (ogni 5 minuti)
    func startHealthCheckTimer() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await CPUThrottler.shared.runWithThrottle { await self?.checkHubHealth() }
            }
        }
        Task {
            await CPUThrottler.shared.runWithThrottle { await checkHubHealth() }
        }
    }
    
    /// Ferma timer health check
    func stopHealthCheckTimer() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }
    
    // MARK: - Heartbeat
    
    /// Avvia timer heartbeat (ogni 60 secondi)
    func startHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await CPUThrottler.shared.runWithThrottle { await self?.sendHeartbeat() }
            }
        }
        Task {
            await CPUThrottler.shared.runWithThrottle { await sendHeartbeat() }
        }
    }
    
    /// Ferma timer heartbeat
    func stopHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    /// Invia heartbeat all'Hub
    func sendHeartbeat() async {
        guard !resolvedHubBaseURL().isEmpty, isHubReachable else { return }
        
        guard let userId = CurrentUserService.shared.currentUsername, !userId.isEmpty else { return }
        
        do {
            // Informazioni client (opzionale)
            let clientInfo = "PerX macOS v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")"
            
            try await HubAPIClient.shared.sendHeartbeat(userId: userId, clientInfo: clientInfo)
            print("[HubConfig] Heartbeat inviato per \(userId)")
        } catch {
            print("[HubConfig] Heartbeat fallito: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Convenience
    
    /// True se almeno una funzionalità usa l'Hub
    var isUsingHub: Bool {
        fileManagementMode == .cloud ||
        emailManagementMode == .cloud ||
        whatsappManagementMode == .cloud
    }
    
    /// True se tutte le funzionalità usano l'Hub
    var isFullyCloud: Bool {
        fileManagementMode == .cloud &&
        emailManagementMode == .cloud &&
        whatsappManagementMode == .cloud
    }
    
    /// Verifica se l'Hub è configurato e raggiungibile
    var isHubReady: Bool {
        !resolvedHubBaseURL().isEmpty && isHubReachable
    }
    
    /// Descrizione stato Hub per UI
    var hubStatusDescription: String {
        if resolvedHubBaseURL().isEmpty {
            return "Non configurato"
        } else if isHubReachable {
            return "Online"
        } else if let error = lastHealthCheckError {
            return "Offline: \(error)"
        } else {
            return "Verifica in corso..."
        }
    }

    var isCloudAPIConfigured: Bool {
        !cloudAPIEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var currentTenantSlug: String {
        let slug = TenantMailSettingsService.shared.settings.tenantSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        return slug.isEmpty ? "default" : slug
    }

    func resolvedHubBaseURL(for tenantSlug: String? = nil) -> String {
        cloudAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func tenantOverride(for tenantSlug: String? = nil) -> TenantHubOverride? {
        tenantHubOverrides[(tenantSlug ?? currentTenantSlug).trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    func setTenantOverride(baseURL: String, for tenantSlug: String? = nil) {
        let slug = (tenantSlug ?? currentTenantSlug).trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty {
            tenantHubOverrides.removeValue(forKey: slug)
        } else {
            tenantHubOverrides[slug] = TenantHubOverride(tenantSlug: slug, baseURL: trimmedURL)
        }
        persistTenantOverrides()
    }

    private func persistTenantOverrides() {
        guard let data = try? JSONEncoder().encode(tenantHubOverrides) else { return }
        UserDefaults.standard.set(data, forKey: tenantHubOverridesKey)
    }
}

// MARK: - ManagementMode

enum ManagementMode: String, Codable, CaseIterable {
    case local  // Gestione locale (legacy)
    case cloud  // Gestione via Hub
    
    var displayName: String {
        switch self {
        case .local:
            return "Locale"
        case .cloud:
            return "Cloud (Hub)"
        }
    }
    
    var description: String {
        switch self {
        case .local:
            return "Elaborazione sul dispositivo"
        case .cloud:
            return "Elaborazione centralizzata su Hub"
        }
    }
    
    var icon: String {
        switch self {
        case .local:
            return "desktopcomputer"
        case .cloud:
            return "cloud"
        }
    }
}
