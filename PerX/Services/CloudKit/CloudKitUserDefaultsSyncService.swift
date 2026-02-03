import Foundation
import CloudKit

@MainActor
final class CloudKitUserDefaultsSyncService {
    static let shared = CloudKitUserDefaultsSyncService()

    private enum RecordType {
        static let userSettings = "UserSettings"
    }

    private enum Keys {
        static let userEmail = "userEmail"
        static let settingsJSON = "settingsJSON"
        static let lastSyncedAt = "lastSyncedAt"
    }

    private let defaults = UserDefaults.standard
    private let lastAppliedKey = "cloudKitUserDefaults_lastAppliedAt"

    // Whitelist chiavi rilevanti (evita token, cache, ecc.)
    private let syncedKeys: [String] = [
        // CloudKit feature flags
        "cloudKitSyncEnabled",
        "cloudKitSyncFrequencySeconds",
        "cloudKitDataFormatting",
        "cloudKitDebugLoggingEnabled",

        // Mail automation
        "isEmailAutomationEnabled",
        "defaultStatusForEmailAutomation",
        "selectedMailboxForAutomation",

        // Mailbox / thread UI
        "MailboxCustomizations",
        "ThreadCustomizations",

        // Email settings
        "emailAutoReadEnabled",
        "emailAutoReadCategories",
        "emailSignature",
        "defaultEmailSignature",
        "readReceiptEnabled",

        // Work schedule
        "weekdaySchedules",
        "specialDays",
        "monthlyTargets",
        
        // WhatsApp (per-utente)
        "whatsappBridgeSelectedAccount",
        
        // Fatturato e parametri fiscali
        "importoBase",
        "importoBaseDieciBeni",
        "fasceFatturato",
        "soglieDanno",
        "contributiINPS",
        "percentualeTasse",
        "marcaDaBolloAbilitata",
        "rivalsaINPSAbilitata",
        "rivalsaINPSPercentuale",
        "coefficienteRedditivita"
    ]

    private init() {}

    func sync(container: CKContainer, userEmail: String) async {
        let privateDB = container.privateCloudDatabase
        let recordID = CKRecord.ID(recordName: userEmail.lowercased())

        do {
            // 1) Pull
            if let remote = try? await privateDB.fetchRecordIfExists(recordID),
               let remoteJSON = remote[Keys.settingsJSON] as? String,
               let remoteAt = remote[Keys.lastSyncedAt] as? Date {
                let lastApplied = defaults.object(forKey: lastAppliedKey) as? Date ?? .distantPast
                if remoteAt > lastApplied {
                    applySnapshotJSON(remoteJSON)
                    defaults.set(remoteAt, forKey: lastAppliedKey)
                }
            }

            // 2) Push
            let snapshot = buildSnapshot()
            let json = try UserDefaultsNormalization.encodeSnapshotJSON(snapshot)

            let record = CKRecord(recordType: RecordType.userSettings, recordID: recordID)
            record[Keys.userEmail] = userEmail as CKRecordValue
            record[Keys.settingsJSON] = json as CKRecordValue
            record[Keys.lastSyncedAt] = Date() as CKRecordValue

            _ = try await privateDB.saveRecordAsync(record)
        } catch {
            print("[CloudKitUserDefaultsSync] ❌ \(error)")
        }
    }

    // MARK: - Snapshot

    private func buildSnapshot() -> [String: Any] {
        var out: [String: Any] = [:]
        for key in syncedKeys {
            guard let value = defaults.object(forKey: key) else { continue }
            out[key] = UserDefaultsNormalization.normalize(value)
        }
        return out
    }

    private func applySnapshotJSON(_ json: String) {
        guard let dict = UserDefaultsNormalization.decodeSnapshotJSON(json) else { return }

        var updatedKeys: [String] = []
        for (key, value) in dict {
            if let denorm = UserDefaultsNormalization.denormalize(value) {
                defaults.set(denorm, forKey: key)
                updatedKeys.append(key)
            }
        }
        
        // Notifica i manager che i settings sono stati aggiornati da CloudKit
        if !updatedKeys.isEmpty {
            print("[CloudKitUserDefaultsSync] 📢 Settings aggiornati da CloudKit: \(updatedKeys)")
            NotificationCenter.default.post(
                name: NotificationNames.cloudKitSettingsUpdated,
                object: nil,
                userInfo: ["keys": updatedKeys]
            )
        }
    }

    // MARK: - CloudKit wrappers (using shared extensions and normalization)
}

