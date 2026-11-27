import Foundation

/// Archivio locale di un account: preferenze, calendario e database.
@MainActor
enum AccountVault {
    private static let activeEmailKey = "perx.accountVault.activeEmail"
    private static let legacyOwnerKey = "perx.accountVault.legacyOwner"
    private static let demoEmails: Set<String> = [
        "cat@perx.it", "admin@perx.it", "perito@perx.it", "info@pynkstudio.it"
    ]

    static func activate(email: String) {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        let previous = UserDefaults.standard.string(forKey: activeEmailKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let destination = storeURL(for: normalized)
        if previous == normalized,
           PersistenceController.shared.storeURL?.standardizedFileURL == destination.standardizedFileURL {
            return
        }
        if let previous, previous != normalized {
            savePreferences(for: previous)
        } else if previous == nil {
            savePreferences(for: legacyOwner(activating: normalized))
        }
        claimLegacyStoreIfNeeded(activating: normalized)
        restorePreferences(for: normalized)
        UserDefaults.standard.set(normalized, forKey: activeEmailKey)
        if PersistenceController.shared.storeURL?.standardizedFileURL != destination.standardizedFileURL {
            do {
                try PersistenceController.shared.replaceStore(with: destination)
            } catch {
                print("[AccountVault] Apertura archivio non riuscita: \(error.localizedDescription)")
            }
        }
        reloadMemory(for: normalized)
    }

    static func suspend() {
        guard let email = UserDefaults.standard.string(forKey: activeEmailKey) else { return }
        savePreferences(for: email)
    }

    private static func legacyOwner(activating email: String) -> String {
        if let saved = UserDefaults.standard.string(forKey: legacyOwnerKey), !saved.isEmpty {
            return saved
        }
        let previous = AccountManager.shared.savedAccounts
            .map(\.email)
            .first { $0 != email && !demoEmails.contains($0) }
        return previous ?? email
    }

    private static func claimLegacyStoreIfNeeded(activating email: String) {
        guard UserDefaults.standard.string(forKey: legacyOwnerKey) == nil else { return }
        guard let source = PersistenceController.shared.storeURL,
              FileManager.default.fileExists(atPath: source.path),
              !source.path.contains("/Accounts/") else { return }
        let owner = legacyOwner(activating: email)
        let destination = storeURL(for: owner)
        guard source.standardizedFileURL != destination.standardizedFileURL else {
            UserDefaults.standard.set(owner, forKey: legacyOwnerKey)
            return
        }
        do {
            try PersistenceController.shared.relocateOpenStore(to: destination)
            UserDefaults.standard.set(owner, forKey: legacyOwnerKey)
        } catch {
            print("[AccountVault] Archivio precedente non spostato: \(error.localizedDescription)")
        }
    }

    private static func storeURL(for email: String) -> URL {
        let folder = directory(for: email)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("PerX.sqlite")
    }

    private static func directory(for email: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let safe = email
            .replacingOccurrences(of: "@", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return base
            .appendingPathComponent("PerX", isDirectory: true)
            .appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true)
    }

    private static func preferencesURL(for email: String) -> URL {
        directory(for: email).appendingPathComponent("preferences.plist")
    }

    private static func isAccountKey(_ key: String) -> Bool {
        if key.hasPrefix("Apple") || key.hasPrefix("NS") || key.hasPrefix("AK")
            || key.hasPrefix("com.apple") || key.hasPrefix("PK") || key.hasPrefix("WebKit") {
            return false
        }
        let global: Set<String> = [
            "perx_saved_accounts",
            "perx_demo_accounts_seeded_v1",
            "perx.activeTenantId",
            activeEmailKey,
            legacyOwnerKey
        ]
        return !global.contains(key)
    }

    private static func savePreferences(for email: String) {
        let values = UserDefaults.standard.dictionaryRepresentation().filter { isAccountKey($0.key) }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: directory(for: email),
            withIntermediateDirectories: true
        )
        try? data.write(to: preferencesURL(for: email), options: .atomic)
    }

    private static func restorePreferences(for email: String) {
        let defaults = UserDefaults.standard
        let currentKeys = defaults.dictionaryRepresentation().keys.filter(isAccountKey)
        for key in currentKeys {
            defaults.removeObject(forKey: key)
        }
        guard let data = try? Data(contentsOf: preferencesURL(for: email)),
              let stored = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return
        }
        for (key, value) in stored where isAccountKey(key) {
            defaults.set(value, forKey: key)
        }
    }

    private static func reloadMemory(for email: String) {
        ImportService.configure(with: PersistenceController.shared.viewContext)
        WorkScheduleManager.shared.replaceFromDefaults()
        SmartSchedulePreferences.shared.reloadForAccount()
        StudioNewsService.shared.reloadForAccount()
        NotificationCenter.default.post(name: .tenantSettingsChanged, object: nil)
        NotificationCenter.default.post(name: .accountClaimScopeChanged, object: nil)
        MailViewModel.shared.bind(to: email)
    }
}
