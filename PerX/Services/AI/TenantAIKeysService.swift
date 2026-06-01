import Foundation
import Security

/// Compatibilita temporanea per i servizi AI legacy.
/// Le chiavi provider non devono mai essere disponibili al client.
struct TenantAIKeysSnapshot {
    let openAIKey = ""
    let openAIModel = ""
    let anthropicKey = ""
    let anthropicModel = ""

    var hasOpenAIKey: Bool { false }
    var hasAnthropicKey: Bool { false }
}

enum TenantAIKeysCache {
    private static let keychainService = "com.perx.ai.keys"
    private static let legacyAccounts = ["openai_api_key", "anthropic_api_key"]
    private static let legacyDefaultsKeys = [
        "tenant_ai_openai_model",
        "tenant_ai_anthropic_model",
        "ai_openai_api_key",
    ]

    static func snapshot() -> TenantAIKeysSnapshot {
        TenantAIKeysSnapshot()
    }

    /// Rimuove eventuali segreti salvati da versioni precedenti dell'app.
    static func clear() {
        for account in legacyAccounts {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
        for key in legacyDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

@MainActor
final class TenantAIKeysService {
    static let shared = TenantAIKeysService()

    private init() {
        TenantAIKeysCache.clear()
    }

    func purgeLegacyClientKeys() {
        TenantAIKeysCache.clear()
    }
}
