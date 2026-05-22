import Foundation
import Security

/// Risposta dell'endpoint /tenants/me/ai-keys
private struct TenantAIKeysDTO: Decodable {
    let openai_api_key: String
    let openai_model: String
    let anthropic_api_key: String
    let anthropic_model: String
}

/// Chiavi AI per il tenant corrente, caricate dal backend e cachate nel Keychain
@MainActor
final class TenantAIKeysService {
    static let shared = TenantAIKeysService()

    private(set) var openAIKey: String = ""
    private(set) var openAIModel: String = "gpt-4o"
    private(set) var anthropicKey: String = ""
    private(set) var anthropicModel: String = "claude-opus-4-7"

    private let keychainService = "com.perx.ai.keys"
    private let openAIKeyAccount = "openai_api_key"
    private let anthropicKeyAccount = "anthropic_api_key"

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
            saveToKeychain()
            lastFetchTime = Date()
            print("[TenantAIKeysService] ✅ Chiavi AI caricate: openai=\(!openAIKey.isEmpty), anthropic=\(!anthropicKey.isEmpty)")
        } catch {
            print("[TenantAIKeysService] ⚠️ Fetch chiavi AI fallito, uso cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Keychain

    private func saveToKeychain() {
        save(key: openAIKey, account: openAIKeyAccount)
        save(key: anthropicKey, account: anthropicKeyAccount)
    }

    private func loadFromKeychain() {
        openAIKey = load(account: openAIKeyAccount) ?? ""
        anthropicKey = load(account: anthropicKeyAccount) ?? ""
    }

    private func save(key: String, account: String) {
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

    private func load(account: String) -> String? {
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
