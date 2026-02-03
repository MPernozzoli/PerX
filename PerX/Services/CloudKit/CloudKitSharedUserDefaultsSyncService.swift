import Foundation
import CloudKit

/// Sync di impostazioni "comuni" tra tutti gli utenti PerX (Public DB).
/// Usata per: OpenAI key/baseURL/model/timeout, SyncAgent URL/porta, WhatsApp Bridge URL/porta.
@MainActor
final class CloudKitSharedUserDefaultsSyncService {
    static let shared = CloudKitSharedUserDefaultsSyncService()

    private enum RecordType {
        static let sharedSettings = "SharedSettings"
    }

    private enum RecordNames {
        /// Un recordName dedicato, per evitare collisioni con altri recordType che usano il Public DB.
        static let sharedSettings = "shared-settings"
    }

    private enum Keys {
        static let settingsJSON = "settingsJSON"
        static let lastSyncedAt = "lastSyncedAt"
    }

    private let defaults = UserDefaults.standard
    private let lastAppliedKey = "cloudKitSharedUserDefaults_lastAppliedAt"

    // Whitelist: solo quello che vogliamo condividere tra tutti
    private let syncedKeys: [String] = [
        // WhatsApp bridge (porta/host)
        "whatsappBridgeBaseURL",

        // Sync Agent (porta/host)
        "syncAgentRemoteURL",

        // OpenAI (comune)
        "ai_openai_api_key",
        "ai_openai_base_url",
        "ai_openai_model",
        "ai_openai_timeout"
    ]

    private init() {}

    func sync(container: CKContainer) async {
        let publicDB = container.publicCloudDatabase
        let recordID = CKRecord.ID(recordName: RecordNames.sharedSettings)

        do {
            // 1) Pull
            if let remote = try? await publicDB.fetchRecordIfExists(recordID),
               let remoteJSON = remote[Keys.settingsJSON] as? String,
               let remoteAt = remote[Keys.lastSyncedAt] as? Date {
                let lastApplied = defaults.object(forKey: lastAppliedKey) as? Date ?? .distantPast
                if remoteAt > lastApplied {
                    applySnapshotJSON(remoteJSON, remoteAt: remoteAt)
                    defaults.set(remoteAt, forKey: lastAppliedKey)
                }
            }

            // 2) Push
            let snapshot = buildSnapshot()
            let json = try UserDefaultsNormalization.encodeSnapshotJSON(snapshot)

            _ = try await upsertSharedSettings(recordID: recordID, settingsJSON: json, db: publicDB)
        } catch {
            print("[CloudKitSharedUserDefaultsSync] ❌ \(error)")
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

    private func applySnapshotJSON(_ json: String, remoteAt: Date) {
        guard let dict = UserDefaultsNormalization.decodeSnapshotJSON(json) else { return }

        for (key, value) in dict {
            if let denorm = UserDefaultsNormalization.denormalize(value) {
                // Merge policy: per alcuni campi, se l'utente ha modificato localmente dopo il remoteAt,
                // NON sovrascrivere (evita che CloudKit rimetta :8000 o valori vuoti).
                if key == "syncAgentRemoteURL" {
                    let localEditedAt = defaults.object(forKey: "localEditAt.syncAgentRemoteURL") as? Date ?? .distantPast
                    if localEditedAt > remoteAt { continue }
                    if let s = denorm as? String, s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                }
                defaults.set(denorm, forKey: key)
            }
        }
    }

    // MARK: - CloudKit wrappers (using shared extensions)

    private func upsertSharedSettings(recordID: CKRecord.ID, settingsJSON: String, db: CKDatabase) async throws -> CKRecord {
        // Modello: aggiorna il record esistente (mantiene recordChangeTag), altrimenti crea.
        let now = Date()
        let baseRecord = try await db.fetchRecordIfExists(recordID) ?? CKRecord(recordType: RecordType.sharedSettings, recordID: recordID)

        baseRecord[Keys.settingsJSON] = settingsJSON as CKRecordValue
        baseRecord[Keys.lastSyncedAt] = now as CKRecordValue

        do {
            return try await db.saveRecordAsync(baseRecord)
        } catch let ckError as CKError where ckError.code == .serverRecordChanged {
            // Merge semplice: last-write-wins sui campi che gestiamo.
            if let serverRecord = ckError.serverRecord {
                serverRecord[Keys.settingsJSON] = settingsJSON as CKRecordValue
                serverRecord[Keys.lastSyncedAt] = now as CKRecordValue
                return try await db.saveRecordAsync(serverRecord)
            }
            throw ckError
        }
    }
}

