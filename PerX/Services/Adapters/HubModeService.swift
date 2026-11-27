import Foundation
import Combine

// ============================================================================
// MARK: - HubModeService
// Gestisce la modalità di funzionamento: locale vs Hub
// ============================================================================

@MainActor
final class HubModeService: ObservableObject {
    static let shared = HubModeService()
    private static let fixedHubURL = HubConfigService.fixedCloudAPIBaseURL
    
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
    @Published private(set) var hubURL: String
    
    private var cancellables = Set<AnyCancellable>()
    
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
        
        self.hubURL = Self.fixedHubURL
        UserDefaults.standard.set(Self.fixedHubURL, forKey: "hub_url")

        let config = HubConfigService.shared
        hubConnected = config.isHubReachable
        config.$isHubReachable
            .sink { [weak self] reachable in
                self?.hubConnected = reachable
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Mode Helpers
    
    /// Verifica se un servizio deve usare l'Hub
    /// Usa le impostazioni di HubConfigService (sincronizzato con UI)
    func shouldUseHub(for service: ServiceType) -> Bool {
        guard hubConnected else { return false }
        
        let config = HubConfigService.shared
        let cloudReady = config.isCloudAPIConfigured
        guard cloudReady else { return false }

        switch service {
        case .email:
            return config.emailManagementMode == .cloud || emailMode == .hub
        case .task:
            return true
        case .claim:
            return true
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
