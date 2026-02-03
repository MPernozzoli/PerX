import Foundation
import Security
import Combine

/// Configurazione centralizzata del Sync Agent (URL LAN/remoto + API key).
final class SyncAgentConfig: ObservableObject {
    static let shared = SyncAgentConfig()

    @Published var remoteURL: String {
        didSet {
            UserDefaults.standard.set(remoteURL, forKey: "syncAgentRemoteURL")
            // Traccia l'ultima modifica locale per evitare che CloudKit sovrascriva con valori vuoti/vecchi
            UserDefaults.standard.set(Date(), forKey: "localEditAt.syncAgentRemoteURL")
        }
    }

    private let apiKeyKeychainKey = "syncAgent.apiKey"

    var apiKey: String {
        get { readKeychainValue(forKey: apiKeyKeychainKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                deleteKeychainValue(forKey: apiKeyKeychainKey)
            } else {
                saveKeychainValue(trimmed, forKey: apiKeyKeychainKey)
            }
        }
    }

    private init() {
        let savedRemote = UserDefaults.standard.string(forKey: "syncAgentRemoteURL") ?? ""
        // Default: host remoto (es. Tailscale) se non configurato
        remoteURL = savedRemote.isEmpty ? "https://perx-sync-agent.tailca58be.ts.net:8000" : savedRemote
    }

    /// Base URL remota (Tailscale). Nessun probing: gli errori vengono gestiti dalle chiamate HTTP.
    func bestBaseURL() async -> URL? {
        URL(string: remoteURL.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Keychain helpers
    private func saveKeychainValue(_ value: String, forKey key: String) {
        let data = value.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func deleteKeychainValue(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func readKeychainValue(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

