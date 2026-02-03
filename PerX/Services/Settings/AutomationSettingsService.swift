import Foundation

/// Gestisce la persistenza delle impostazioni per l'automazione delle email.
class AutomationSettingsService {
    
    static let shared = AutomationSettingsService()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let isAutomationEnabled = "isEmailAutomationEnabled"
        static let defaultStatusForAutomation = "defaultStatusForEmailAutomation"
        static let selectedMailboxForAutomation = "selectedMailboxForAutomation"
    }
    
    private init() {}
    
    // MARK: - Automation Enabled
    
    var isAutomationEnabled: Bool {
        get {
            return defaults.bool(forKey: Keys.isAutomationEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.isAutomationEnabled)
        }
    }
    
    // MARK: - Default Status
    
    var defaultStatus: String {
        get {
            // Ritorna "Da Scaricare" se non è mai stato impostato un valore.
            return defaults.string(forKey: Keys.defaultStatusForAutomation) ?? "Da Scaricare"
        }
        set {
            defaults.set(newValue, forKey: Keys.defaultStatusForAutomation)
        }
    }
    
    // MARK: - Selected Mailbox
    
    var selectedMailbox: String? {
        get {
            return defaults.string(forKey: Keys.selectedMailboxForAutomation)
        }
        set {
            defaults.set(newValue, forKey: Keys.selectedMailboxForAutomation)
        }
    }
} 