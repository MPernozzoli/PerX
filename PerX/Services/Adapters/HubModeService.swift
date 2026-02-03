import Foundation
import Combine

// ============================================================================
// MARK: - HubModeService
// Gestisce la modalità di funzionamento: locale vs Hub
// ============================================================================

@MainActor
final class HubModeService: ObservableObject {
    static let shared = HubModeService()
    
    // MARK: - Published Properties
    
    /// Modalità email: true = Hub, false = locale
    @Published var emailMode: ServiceMode {
        didSet { UserDefaults.standard.set(emailMode.rawValue, forKey: "hub_email_mode") }
    }
    
    /// Modalità task: true = Hub, false = locale
    @Published var taskMode: ServiceMode {
        didSet { UserDefaults.standard.set(taskMode.rawValue, forKey: "hub_task_mode") }
    }
    
    /// Modalità sinistri: true = Hub, false = locale
    @Published var claimMode: ServiceMode {
        didSet { UserDefaults.standard.set(claimMode.rawValue, forKey: "hub_claim_mode") }
    }
    
    /// Modalità file: true = Hub, false = locale
    @Published var fileMode: ServiceMode {
        didSet { UserDefaults.standard.set(fileMode.rawValue, forKey: "hub_file_mode") }
    }
    
    /// Stato connessione Hub
    @Published private(set) var hubConnected: Bool = false
    
    /// URL dell'Hub
    @Published var hubURL: String {
        didSet { 
            UserDefaults.standard.set(hubURL, forKey: "hub_url")
            Task { await checkHubConnection() }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var connectionCheckTimer: Timer?
    
    // MARK: - Initialization
    
    private init() {
        // Carica impostazioni salvate
        let emailRaw = UserDefaults.standard.string(forKey: "hub_email_mode") ?? ServiceMode.local.rawValue
        self.emailMode = ServiceMode(rawValue: emailRaw) ?? .local
        
        let taskRaw = UserDefaults.standard.string(forKey: "hub_task_mode") ?? ServiceMode.local.rawValue
        self.taskMode = ServiceMode(rawValue: taskRaw) ?? .local
        
        let claimRaw = UserDefaults.standard.string(forKey: "hub_claim_mode") ?? ServiceMode.local.rawValue
        self.claimMode = ServiceMode(rawValue: claimRaw) ?? .local
        
        let fileRaw = UserDefaults.standard.string(forKey: "hub_file_mode") ?? ServiceMode.local.rawValue
        self.fileMode = ServiceMode(rawValue: fileRaw) ?? .local
        
        self.hubURL = UserDefaults.standard.string(forKey: "hub_url") ?? "https://mac-mini-di-massimo.tailca58be.ts.net"
        
        // Avvia controllo connessione
        startConnectionCheck()
    }
    
    // MARK: - Connection Check
    
    private func startConnectionCheck() {
        // Check immediato
        Task { await checkHubConnection() }
        
        // Check periodico ogni 30 secondi
        connectionCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkHubConnection()
            }
        }
    }
    
    func checkHubConnection() async {
        guard !hubURL.isEmpty,
              let url = URL(string: "\(hubURL)/health") else {
            hubConnected = false
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                hubConnected = true
                print("[HubMode] ✅ Hub connesso")
            } else {
                hubConnected = false
            }
        } catch {
            hubConnected = false
            print("[HubMode] ❌ Hub non raggiungibile: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Mode Helpers
    
    /// Verifica se un servizio deve usare l'Hub
    /// Usa le impostazioni di HubConfigService (sincronizzato con UI)
    func shouldUseHub(for service: ServiceType) -> Bool {
        guard hubConnected else { return false }
        
        let config = HubConfigService.shared
        
        switch service {
        case .email:
            return config.emailManagementMode == .cloud || emailMode == .hub
        case .task:
            return taskMode == .hub
        case .claim:
            return claimMode == .hub
        case .file:
            return config.fileManagementMode == .cloud || fileMode == .hub
        case .whatsapp:
            return config.whatsappManagementMode == .cloud
        }
    }
    
    /// Imposta tutte le modalità
    func setAllModes(_ mode: ServiceMode) {
        emailMode = mode
        taskMode = mode
        claimMode = mode
        fileMode = mode
    }
}

// MARK: - Types

enum ServiceMode: String, CaseIterable, Codable {
    case local = "local"
    case hub = "hub"
    
    var displayName: String {
        switch self {
        case .local: return "Locale"
        case .hub: return "Hub"
        }
    }
    
    var description: String {
        switch self {
        case .local: return "Elaborazione sul dispositivo"
        case .hub: return "Elaborazione su Mac Mini"
        }
    }
}

enum ServiceType {
    case email
    case task
    case claim
    case file
    case whatsapp
}
