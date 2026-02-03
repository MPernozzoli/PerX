import Foundation
import CloudKit

/// Sync di segreti che stanno in Keychain (API key) su CloudKit.
/// - Shared (Public DB): SyncAgent API Key (comune per tutti)
/// - User (Private DB): WhatsApp Bridge API Key (individuale per utente PerX)
@MainActor
final class CloudKitKeychainSyncService {
    static let shared = CloudKitKeychainSyncService()

    private enum RecordType {
        static let sharedSecrets = "SharedSecrets"
        static let userSecrets = "UserSecrets"
    }

    private enum RecordNames {
        /// Un recordName dedicato, per evitare collisioni con altri recordType nel Public DB.
        static let sharedSecrets = "shared-secrets"
    }

    private enum SharedKeys {
        static let syncAgentApiKey = "syncAgentApiKey"
        static let lastSyncedAt = "lastSyncedAt"
    }

    private enum UserKeys {
        static let whatsAppBridgeApiKey = "whatsAppBridgeApiKey"
        static let lastSyncedAt = "lastSyncedAt"
    }

    private let defaults = UserDefaults.standard
    private let lastAppliedSharedKey = "cloudKitKeychainShared_lastAppliedAt"
    private let lastAppliedUserKeyPrefix = "cloudKitKeychainUser_lastAppliedAt."

    private init() {}

    func syncSharedSecrets(container: CKContainer) async {
        let publicDB = container.publicCloudDatabase
        let recordID = CKRecord.ID(recordName: RecordNames.sharedSecrets)

        do {
            // 1) Pull
            if let remote = try? await publicDB.fetchRecordIfExists(recordID),
               let remoteAt = remote[SharedKeys.lastSyncedAt] as? Date {
                let lastApplied = defaults.object(forKey: lastAppliedSharedKey) as? Date ?? .distantPast
                if remoteAt > lastApplied {
                    if let key = remote[SharedKeys.syncAgentApiKey] as? String {
                        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Se dal cloud arriva vuoto/nil NON sovrascrive il locale
                        if !trimmed.isEmpty {
                            SyncAgentConfig.shared.apiKey = trimmed
                        }
                    }
                    defaults.set(remoteAt, forKey: lastAppliedSharedKey)
                }
            }

            // 2) Push
            let localKey = SyncAgentConfig.shared.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            // Se locale vuoto, non pushiamo (evita wipe del cloud e del locale)
            if !localKey.isEmpty {
                _ = try await upsertSharedSecrets(recordID: recordID, syncAgentApiKey: localKey, db: publicDB)
            }
        } catch {
            print("[CloudKitKeychainSync] ❌ shared \(error)")
        }
    }

    func syncUserSecrets(container: CKContainer, userEmail: String) async {
        let privateDB = container.privateCloudDatabase
        let recordID = CKRecord.ID(recordName: userEmail.lowercased())
        let lastAppliedKey = lastAppliedUserKeyPrefix + userEmail.lowercased()

        do {
            // 1) Pull
            if let remote = try? await privateDB.fetchRecordIfExists(recordID),
               let remoteAt = remote[UserKeys.lastSyncedAt] as? Date {
                let lastApplied = defaults.object(forKey: lastAppliedKey) as? Date ?? .distantPast
                if remoteAt > lastApplied {
                    // WhatsApp ora è gestito tramite Hub, non più config locale
                    defaults.set(remoteAt, forKey: lastAppliedKey)
                }
            }
            
            // 2) Push - nulla da pushare per WhatsApp (gestito da Hub)
        } catch {
            print("[CloudKitKeychainSync] ❌ user \(error)")
        }
    }

    // MARK: - CloudKit helpers (using shared extensions)

    private func upsertSharedSecrets(recordID: CKRecord.ID, syncAgentApiKey: String?, db: CKDatabase) async throws -> CKRecord {
        let now = Date()
        let baseRecord = try await db.fetchRecordIfExists(recordID) ?? CKRecord(recordType: RecordType.sharedSecrets, recordID: recordID)

        if let syncAgentApiKey, !syncAgentApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseRecord[SharedKeys.syncAgentApiKey] = syncAgentApiKey as CKRecordValue
        } else {
            // Non salvare stringa vuota: rimuovi il campo
            baseRecord[SharedKeys.syncAgentApiKey] = nil
        }
        baseRecord[SharedKeys.lastSyncedAt] = now as CKRecordValue

        do {
            return try await db.saveRecordAsync(baseRecord)
        } catch let ckError as CKError where ckError.code == .serverRecordChanged {
            if let serverRecord = ckError.serverRecord {
                if let syncAgentApiKey, !syncAgentApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    serverRecord[SharedKeys.syncAgentApiKey] = syncAgentApiKey as CKRecordValue
                } else {
                    serverRecord[SharedKeys.syncAgentApiKey] = nil
                }
                serverRecord[SharedKeys.lastSyncedAt] = now as CKRecordValue
                return try await db.saveRecordAsync(serverRecord)
            }
            throw ckError
        }
    }

    private func upsertUserSecrets(recordID: CKRecord.ID, whatsAppBridgeApiKey: String?, db: CKDatabase) async throws -> CKRecord {
        let now = Date()
        let baseRecord = try await db.fetchRecordIfExists(recordID) ?? CKRecord(recordType: RecordType.userSecrets, recordID: recordID)

        if let whatsAppBridgeApiKey, !whatsAppBridgeApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseRecord[UserKeys.whatsAppBridgeApiKey] = whatsAppBridgeApiKey as CKRecordValue
        } else {
            baseRecord[UserKeys.whatsAppBridgeApiKey] = nil
        }
        baseRecord[UserKeys.lastSyncedAt] = now as CKRecordValue

        do {
            return try await db.saveRecordAsync(baseRecord)
        } catch let ckError as CKError where ckError.code == .serverRecordChanged {
            if let serverRecord = ckError.serverRecord {
                if let whatsAppBridgeApiKey, !whatsAppBridgeApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    serverRecord[UserKeys.whatsAppBridgeApiKey] = whatsAppBridgeApiKey as CKRecordValue
                } else {
                    serverRecord[UserKeys.whatsAppBridgeApiKey] = nil
                }
                serverRecord[UserKeys.lastSyncedAt] = now as CKRecordValue
                return try await db.saveRecordAsync(serverRecord)
            }
            throw ckError
        }
    }
}

