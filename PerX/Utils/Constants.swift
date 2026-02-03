import Foundation

// MARK: - App Constants

/// Costanti centralizzate per l'applicazione.
/// Sostituisce le stringhe sparse nel codebase.
enum AppConstants {
    
    // MARK: - App Info
    
    static let appName = "PerX"
    static let bundleIdentifier = "it.pernozzoli.PerX"
    static let iCloudContainerIdentifier = "iCloud.it.pernozzoli.PerX"
    
    // MARK: - Locale
    
    /// Locale italiana per formattazione
    static let italianLocale = Locale(identifier: "it_IT")
    
    /// TimeZone italiana
    static let italianTimeZone = TimeZone(identifier: "Europe/Rome")!
}

// MARK: - UserDefaults Keys

/// Chiavi UserDefaults centralizzate.
/// Sostituisce le stringhe sparse in 20+ file.
enum UserDefaultsKeys {
    
    // MARK: - CloudKit Sync
    
    static let cloudKitSyncEnabled = "cloudKitSyncEnabled"
    static let cloudKitSyncFrequencySeconds = "cloudKitSyncFrequencySeconds"
    static let cloudKitDataFormatting = "cloudKitDataFormatting"
    static let cloudKitDebugLoggingEnabled = "cloudKitDebugLoggingEnabled"
    
    // MARK: - Email Automation
    
    static let isEmailAutomationEnabled = "isEmailAutomationEnabled"
    static let defaultStatusForEmailAutomation = "defaultStatusForEmailAutomation"
    static let selectedMailboxForAutomation = "selectedMailboxForAutomation"
    
    // MARK: - Mailbox / Thread UI
    
    static let mailboxCustomizations = "MailboxCustomizations"
    static let threadCustomizations = "ThreadCustomizations"
    
    // MARK: - Email Settings
    
    static let emailAutoReadEnabled = "emailAutoReadEnabled"
    static let emailAutoReadCategories = "emailAutoReadCategories"
    static let emailSignature = "emailSignature"
    static let defaultEmailSignature = "defaultEmailSignature"
    static let readReceiptEnabled = "readReceiptEnabled"
    
    // MARK: - Work Schedule
    
    static let weekdaySchedules = "weekdaySchedules"
    static let specialDays = "specialDays"
    static let monthlyTargets = "monthlyTargets"
    
    // MARK: - WhatsApp
    
    static let whatsappBridgeBaseURL = "whatsappBridgeBaseURL"
    static let whatsappBridgeSelectedAccount = "whatsappBridgeSelectedAccount"
    
    // MARK: - Sync Agent
    
    static let syncAgentRemoteURL = "syncAgentRemoteURL"
    
    // MARK: - AI / OpenAI
    
    static let aiOpenAIApiKey = "ai_openai_api_key"
    static let aiOpenAIBaseURL = "ai_openai_base_url"
    static let aiOpenAIModel = "ai_openai_model"
    static let aiOpenAITimeout = "ai_openai_timeout"
    
    // MARK: - Claims / Sinistri
    
    static let limitaImportazioneSinistriRecenti = "limitaImportazioneSinistriRecenti"
    static let customStates = "customStates"
    static let stateCustomizations = "stateCustomizations"
    
    // MARK: - Hub
    
    static let hubBaseURL = "hubBaseURL"
    static let hubAPIKey = "hubAPIKey"
    static let hubMode = "hubMode"
    
    // MARK: - UI Preferences
    
    static let onboardingCompleted = "onboardingCompleted"
    static let sidebarCollapsed = "sidebarCollapsed"
    static let lastSelectedSinistro = "lastSelectedSinistro"
    static let dateDisplayFormat = "dateDisplayFormat"
    
    // MARK: - Cache
    
    static let lastCacheCleanupDate = "lastCacheCleanupDate"
    static let cacheRetentionDays = "cacheRetentionDays"
}

// MARK: - Notification Names

/// Nomi delle notifiche centralizzati
enum NotificationNames {
    static let sinistroUpdated = Notification.Name("sinistroUpdated")
    static let sinistroSelected = Notification.Name("sinistroSelected")
    static let emailReceived = Notification.Name("emailReceived")
    static let syncCompleted = Notification.Name("syncCompleted")
    static let authStateChanged = Notification.Name("authStateChanged")
    
    /// Emessa quando CloudKit aggiorna UserDefaults (per ricaricare manager in memoria)
    static let cloudKitSettingsUpdated = Notification.Name("cloudKitSettingsUpdated")
    
    /// Emessa quando un sinistro viene reclamato da un altro utente
    static let sinistroReclaimed = Notification.Name("sinistroReclaimed")
}

// MARK: - Error Domains

/// Domini errori centralizzati
enum ErrorDomains {
    static let sync = "it.pernozzoli.PerX.Sync"
    static let auth = "it.pernozzoli.PerX.Auth"
    static let email = "it.pernozzoli.PerX.Email"
    static let import_ = "it.pernozzoli.PerX.Import"
    static let cloudKit = "it.pernozzoli.PerX.CloudKit"
    static let hub = "it.pernozzoli.PerX.Hub"
}
