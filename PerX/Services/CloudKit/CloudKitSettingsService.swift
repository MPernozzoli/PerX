import Foundation
import Combine

@MainActor
final class CloudKitSettingsService: ObservableObject {
    static let shared = CloudKitSettingsService()

    private enum Keys {
        static let isEnabled = "cloudKitSyncEnabled"
        static let syncFrequencySeconds = "cloudKitSyncFrequencySeconds"
        static let dataFormatting = "cloudKitDataFormatting"
        static let debugLoggingEnabled = "cloudKitDebugLoggingEnabled"
    }

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }
  /// Frequenza pull (secondi). Default: 30.
    @Published var syncFrequencySeconds: Double {
        didSet { defaults.set(syncFrequencySeconds, forKey: Keys.syncFrequencySeconds) }
    }

    /// Opzione “test”: controlla normalizzazione/formattazione record.
    @Published var dataFormatting: String {
        didSet { defaults.set(dataFormatting, forKey: Keys.dataFormatting) }
    }
    @Published var debugLoggingEnabled: Bool {
        didSet { defaults.set(debugLoggingEnabled, forKey: Keys.debugLoggingEnabled) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        // Default: ON (richiesta: abilitata di default nell'app)
        self.isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        self.syncFrequencySeconds = defaults.object(forKey: Keys.syncFrequencySeconds) as? Double ?? 30
        self.dataFormatting = defaults.string(forKey: Keys.dataFormatting) ?? "default"
        self.debugLoggingEnabled = defaults.object(forKey: Keys.debugLoggingEnabled) as? Bool ?? false
    }
}

