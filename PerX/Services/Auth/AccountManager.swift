import Foundation
import Security

@MainActor
final class AccountManager: ObservableObject {
    static let shared = AccountManager()

    @Published private(set) var savedAccounts: [SavedAccount] = []

    private let accountsKey = "perx_saved_accounts"
    private let keychainService = "com.perx.accounts"
    private let didSeedDemoAccountsKey = "perx_demo_accounts_seeded_v1"

    private init() {
        loadAccounts()
        seedDemoAccountsIfNeeded()
    }

    struct SavedAccount: Codable, Identifiable, Hashable {
        let id: String
        let email: String
        let displayName: String
        let avatarInitials: String
        var lastLoginDate: Date
        var hasPasscode: Bool
        var colorIndex: Int

        init(email: String, displayName: String) {
            let normalizedEmail = email.lowercased()
            let resolvedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? normalizedEmail
            : displayName.trimmingCharacters(in: .whitespacesAndNewlines)

            self.id = normalizedEmail
            self.email = normalizedEmail
            self.displayName = resolvedName
            self.avatarInitials = String(resolvedName.prefix(2)).uppercased()
            self.lastLoginDate = Date()
            self.hasPasscode = false
            self.colorIndex = abs(normalizedEmail.hashValue) % 6
        }
    }

    private struct DemoAccountDefinition {
        let email: String
        let displayName: String
        let password: String
    }

    private static let demoAccounts: [DemoAccountDefinition] = [
        DemoAccountDefinition(email: "cat@demo.com", displayName: "CAT Demo", password: "cat123"),
        DemoAccountDefinition(email: "admin@demo.com", displayName: "Admin Demo", password: "admin123"),
        DemoAccountDefinition(email: "perito@demo.com", displayName: "Perito Demo", password: "perito123"),
        DemoAccountDefinition(email: "info@pynkstudio.it", displayName: "Pynk Studio Admin", password: "change-me-now")
    ]

    func saveAccount(email: String, displayName: String, password: String?) {
        upsertAccount(email: email, displayName: displayName)

        if let password, !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            savePassword(password, for: email)
        }
    }

    func saveAccount(email: String, displayName: String, refreshToken: String?) {
        saveAccount(email: email, displayName: displayName, password: refreshToken)
    }

    func removeAccount(_ account: SavedAccount) {
        savedAccounts.removeAll { $0.email == account.email }
        deletePasscode(for: account.email)
        deletePassword(for: account.email)
        persistAccounts()
    }

    func getPassword(for email: String) -> String? {
        loadFromKeychain(key: "password_\(email.lowercased())") ??
        loadFromKeychain(key: "refresh_\(email.lowercased())")
    }

    func getRefreshToken(for email: String) -> String? {
        getPassword(for: email)
    }

    func setPasscode(_ passcode: String, for email: String) {
        saveToKeychain(value: passcode, key: "passcode_\(email.lowercased())")

        if let index = savedAccounts.firstIndex(where: { $0.email == email.lowercased() }) {
            savedAccounts[index].hasPasscode = true
            persistAccounts()
        }
    }

    func verifyPasscode(_ passcode: String, for email: String) -> Bool {
        loadFromKeychain(key: "passcode_\(email.lowercased())") == passcode
    }

    func removePasscode(for email: String) {
        deletePasscode(for: email)

        if let index = savedAccounts.firstIndex(where: { $0.email == email.lowercased() }) {
            savedAccounts[index].hasPasscode = false
            persistAccounts()
        }
    }

    func updateDisplayName(_ displayName: String, for email: String) {
        guard let index = savedAccounts.firstIndex(where: { $0.email == email.lowercased() }) else { return }
        var account = SavedAccount(email: savedAccounts[index].email, displayName: displayName)
        account.lastLoginDate = savedAccounts[index].lastLoginDate
        account.hasPasscode = savedAccounts[index].hasPasscode
        account.colorIndex = savedAccounts[index].colorIndex
        savedAccounts[index] = account
        persistAccounts()
    }

    private func loadAccounts() {
        guard let data = UserDefaults.standard.data(forKey: accountsKey),
              let accounts = try? JSONDecoder().decode([SavedAccount].self, from: data) else {
            return
        }
        savedAccounts = accounts
    }

    private func persistAccounts() {
        guard let data = try? JSONEncoder().encode(savedAccounts) else { return }
        UserDefaults.standard.set(data, forKey: accountsKey)
    }

    private func savePassword(_ password: String, for email: String) {
        let normalizedEmail = email.lowercased()
        saveToKeychain(value: password, key: "password_\(normalizedEmail)")
        deleteFromKeychain(key: "refresh_\(normalizedEmail)")
    }

    private func deletePassword(for email: String) {
        let normalizedEmail = email.lowercased()
        deleteFromKeychain(key: "password_\(normalizedEmail)")
        deleteFromKeychain(key: "refresh_\(normalizedEmail)")
    }

    private func deletePasscode(for email: String) {
        deleteFromKeychain(key: "passcode_\(email.lowercased())")
    }

    private func saveToKeychain(value: String, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: value.data(using: .utf8) ?? Data()
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    private func upsertAccount(email: String, displayName: String) {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var account = SavedAccount(email: normalizedEmail, displayName: displayName)

        if let existing = savedAccounts.first(where: { $0.email == normalizedEmail }) {
            account.hasPasscode = existing.hasPasscode
            account.colorIndex = existing.colorIndex
        }

        account.lastLoginDate = Date()
        savedAccounts.removeAll { $0.email == normalizedEmail }
        savedAccounts.insert(account, at: 0)
        persistAccounts()
    }

    private func seedDemoAccountsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: didSeedDemoAccountsKey) else { return }

        for account in Self.demoAccounts.reversed() {
            saveAccount(email: account.email, displayName: account.displayName, password: account.password)
        }

        UserDefaults.standard.set(true, forKey: didSeedDemoAccountsKey)
    }
}
