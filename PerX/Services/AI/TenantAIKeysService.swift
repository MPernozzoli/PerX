import Foundation
import Security

/// Risposta dell'endpoint /tenants/me/ai-keys
private struct TenantAIKeysDTO: Decodable {
    let openai_api_key: String
    let openai_model: String
    let anthropic_api_key: String
    let anthropic_model: String
}

struct TenantAIKeysSnapshot {
    let openAIKey: String
    let openAIModel: String
    let anthropicKey: String
    let anthropicModel: String

    var hasOpenAIKey: Bool { !openAIKey.isEmpty }
    var hasAnthropicKey: Bool { !anthropicKey.isEmpty }
}

enum TenantAIKeysCache {
    private static let keychainService = "com.perx.ai.keys"
    private static let openAIKeyAccount = "openai_api_key"
    private static let anthropicKeyAccount = "anthropic_api_key"
    private static let openAIModelDefaultsKey = "tenant_ai_openai_model"
    private static let anthropicModelDefaultsKey = "tenant_ai_anthropic_model"

    static func snapshot() -> TenantAIKeysSnapshot {
        TenantAIKeysSnapshot(
            openAIKey: load(account: openAIKeyAccount) ?? "",
            openAIModel: model(forKey: openAIModelDefaultsKey, fallback: "gpt-4o"),
            anthropicKey: load(account: anthropicKeyAccount) ?? "",
            anthropicModel: model(forKey: anthropicModelDefaultsKey, fallback: "claude-opus-4-7")
        )
    }

    static func save(snapshot: TenantAIKeysSnapshot) {
        save(key: snapshot.openAIKey, account: openAIKeyAccount)
        save(key: snapshot.anthropicKey, account: anthropicKeyAccount)
        UserDefaults.standard.set(snapshot.openAIModel, forKey: openAIModelDefaultsKey)
        UserDefaults.standard.set(snapshot.anthropicModel, forKey: anthropicModelDefaultsKey)
    }

    private static func model(forKey key: String, fallback: String) -> String {
        let model = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return model.isEmpty ? fallback : model
    }

    private static func save(key: String, account: String) {
        let data = key.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty else { return nil }
        return string
    }
}

/// Chiavi AI per il tenant corrente, caricate dal backend e cachate nel Keychain
@MainActor
final class TenantAIKeysService {
    static let shared = TenantAIKeysService()

    private(set) var openAIKey: String = ""
    private(set) var openAIModel: String = "gpt-4o"
    private(set) var anthropicKey: String = ""
    private(set) var anthropicModel: String = "claude-opus-4-7"

    private var fetchTask: Task<Void, Never>?
    private var lastFetchTime: Date?
    private let cacheTTL: TimeInterval = 300 // 5 minuti

    private init() {
        loadFromKeychain()
    }

    // MARK: - Public API

    var hasOpenAIKey: Bool { !openAIKey.isEmpty }
    var hasAnthropicKey: Bool { !anthropicKey.isEmpty }

    /// Carica le chiavi dal backend. Non-throwing: in caso di errore usa quelle cachate.
    func fetchIfNeeded() async {
        if let last = lastFetchTime, Date().timeIntervalSince(last) < cacheTTL {
            return
        }
        guard fetchTask == nil else { return }
        fetchTask = Task { await fetch() }
        await fetchTask?.value
        fetchTask = nil
    }

    func forceRefresh() async {
        lastFetchTime = nil
        await fetch()
    }

    // MARK: - Private

    private func fetch() async {
        guard BackendAPIClient.shared.isConfigured && BackendAPIClient.shared.hasAccessToken else {
            return
        }
        do {
            let dto: TenantAIKeysDTO = try await BackendAPIClient.shared.get("tenants/me/ai-keys")
            openAIKey = dto.openai_api_key
            openAIModel = dto.openai_model.isEmpty ? "gpt-4o" : dto.openai_model
            anthropicKey = dto.anthropic_api_key
            anthropicModel = dto.anthropic_model.isEmpty ? "claude-opus-4-7" : dto.anthropic_model
            saveToCache()
            lastFetchTime = Date()
            print("[TenantAIKeysService] ✅ Chiavi AI caricate: openai=\(!openAIKey.isEmpty), anthropic=\(!anthropicKey.isEmpty)")
        } catch {
            print("[TenantAIKeysService] ⚠️ Fetch chiavi AI fallito, uso cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Keychain

    private func saveToCache() {
        TenantAIKeysCache.save(snapshot: TenantAIKeysSnapshot(
            openAIKey: openAIKey,
            openAIModel: openAIModel,
            anthropicKey: anthropicKey,
            anthropicModel: anthropicModel
        ))
    }

    private func loadFromKeychain() {
        let snapshot = TenantAIKeysCache.snapshot()
        openAIKey = snapshot.openAIKey
        openAIModel = snapshot.openAIModel
        anthropicKey = snapshot.anthropicKey
        anthropicModel = snapshot.anthropicModel
    }
}
