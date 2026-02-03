import Foundation
import CloudKit

@MainActor
final class CloudKitTasksSyncService {
    static let shared = CloudKitTasksSyncService()

    private enum RecordType {
        static let scheduledTask = "ScheduledTask"
    }

    private enum Keys {
        static let userEmail = "userEmail"
        static let taskJSON = "taskJSON"
        static let lastSyncedAt = "lastSyncedAt"
    }

    private let defaults = UserDefaults.standard
    private let lastAppliedKey = "cloudKitTasks_lastAppliedAt"

    private init() {}

    func sync(container: CKContainer, userEmail: String) async {
        let db = container.privateCloudDatabase
        let normalizedEmail = userEmail.lowercased()
        let recordID = CKRecord.ID(recordName: normalizedEmail)

        do {
            // 1) Pull
            if let remote = try? await db.fetchRecordIfExists(recordID),
               let remoteJSON = remote[Keys.taskJSON] as? String,
               let remoteAt = remote[Keys.lastSyncedAt] as? Date {
                let lastApplied = defaults.object(forKey: lastAppliedKey) as? Date ?? .distantPast
                if remoteAt > lastApplied {
                    applyTasksJSON(remoteJSON)
                    defaults.set(remoteAt, forKey: lastAppliedKey)
                }
            }

            // 2) Push
            let json = encodeTasksJSON()
            let record = CKRecord(recordType: RecordType.scheduledTask, recordID: recordID)
            record[Keys.userEmail] = normalizedEmail as CKRecordValue
            record[Keys.taskJSON] = json as CKRecordValue
            record[Keys.lastSyncedAt] = Date() as CKRecordValue
            _ = try await db.saveRecordAsync(record)
        } catch {
            print("[CloudKitTasksSync] ❌ \(error)")
        }
    }

    private func encodeTasksJSON() -> String {
        let tasks = TaskManager.shared.tasks
        if let data = try? JSONEncoder().encode(tasks),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "[]"
    }

    private func applyTasksJSON(_ json: String) {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([DailyTask].self, from: data) else {
            return
        }
        TaskManager.shared.tasks = decoded
        TaskManager.shared.saveTasks()
        TaskManager.shared.updateCounter += 1
    }

    // MARK: - CloudKit wrappers (using shared extensions)
}

