//
//  AccountManager.swift
//  PerX per iPad
//
//  Gestisce gli account salvati per login stile Netflix.
//  Mantiene gli account anche dopo logout per riutilizzo rapido.
//

import Foundation
import Security
import Combine

@MainActor
class AccountManager: ObservableObject {
    static let shared = AccountManager()
    
    @Published private(set) var savedAccounts: [SavedAccount] = []
    @Published var selectedAccountForLogin: SavedAccount?
    
    private let accountsKey = "perx_saved_accounts"
    private let keychainService = "com.perx.accounts"
    
    private init() {
        loadAccounts()
    }
    
    // MARK: - Account Model
    
    struct SavedAccount: Codable, Identifiable, Hashable {
        let id: String
        let email: String
        let displayName: String
        let avatarInitials: String
        var lastLoginDate: Date
        var hasPasscode: Bool
        var colorIndex: Int // Per avatar colorato
        
        init(email: String, displayName: String) {
            self.id = email.lowercased()
            self.email = email.lowercased()
            self.displayName = displayName
            self.avatarInitials = String(displayName.prefix(2)).uppercased()
            self.lastLoginDate = Date()
            self.hasPasscode = false
            self.colorIndex = abs(email.hashValue) % 6
        }
        
        var avatarColor: String {
            let colors = ["blue", "green", "orange", "purple", "red", "teal"]
            return colors[colorIndex % colors.count]
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(email)
        }
        
        static func == (lhs: SavedAccount, rhs: SavedAccount) -> Bool {
            lhs.email == rhs.email
        }
    }
    
    // MARK: - Account Management
    
    /// Salva o aggiorna un account dopo login
    func saveAccount(email: String, displayName: String, refreshToken: String?) {
        var account = SavedAccount(email: email, displayName: displayName)
        
        // Se esiste già, mantieni le impostazioni
        if let existing = savedAccounts.first(where: { $0.email == email.lowercased() }) {
            account.hasPasscode = existing.hasPasscode
            account.colorIndex = existing.colorIndex
        }
        
        // Aggiorna last login
        account.lastLoginDate = Date()
        
        // Rimuovi vecchia entry se esiste
        savedAccounts.removeAll { $0.email == email.lowercased() }
        
        // Aggiungi in cima (più recente)
        savedAccounts.insert(account, at: 0)
        
        // Salva refresh token se disponibile
        if let token = refreshToken {
            saveRefreshToken(token, for: email)
        }
        
        persistAccounts()
    }
    
    /// Rimuove un account salvato
    func removeAccount(_ account: SavedAccount) {
        savedAccounts.removeAll { $0.email == account.email }
        deleteRefreshToken(for: account.email)
        deletePasscode(for: account.email)
        persistAccounts()
    }
    
    /// Recupera il refresh token per un account
    func getRefreshToken(for email: String) -> String? {
        loadFromKeychain(key: "refresh_\(email.lowercased())")
    }
    
    /// Imposta passcode per un account
    func setPasscode(_ passcode: String, for email: String) {
        saveToKeychain(value: passcode, key: "passcode_\(email.lowercased())")
        
        if let idx = savedAccounts.firstIndex(where: { $0.email == email.lowercased() }) {
            savedAccounts[idx].hasPasscode = true
            persistAccounts()
        }
    }
    
    /// Verifica passcode
    func verifyPasscode(_ passcode: String, for email: String) -> Bool {
        let stored = loadFromKeychain(key: "passcode_\(email.lowercased())")
        return stored == passcode
    }
    
    /// Rimuove passcode
    func removePasscode(for email: String) {
        deletePasscode(for: email)
        
        if let idx = savedAccounts.firstIndex(where: { $0.email == email.lowercased() }) {
            savedAccounts[idx].hasPasscode = false
            persistAccounts()
        }
    }
    
    // MARK: - Persistence
    
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
    
    // MARK: - Keychain
    
    private func saveRefreshToken(_ token: String, for email: String) {
        saveToKeychain(value: token, key: "refresh_\(email.lowercased())")
    }
    
    private func deleteRefreshToken(for email: String) {
        deleteFromKeychain(key: "refresh_\(email.lowercased())")
    }
    
    private func deletePasscode(for email: String) {
        deleteFromKeychain(key: "passcode_\(email.lowercased())")
    }
    
    private func saveToKeychain(value: String, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: value.data(using: .utf8)!
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
        
        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        return nil
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
