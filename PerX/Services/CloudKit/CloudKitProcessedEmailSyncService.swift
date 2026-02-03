import Foundation
import CloudKit
import CoreData

@MainActor
final class CloudKitProcessedEmailSyncService {
    static let shared = CloudKitProcessedEmailSyncService()

    private enum RecordType {
        static let processedEmail = "ProcessedEmail"
    }

    private enum Keys {
        static let userEmail = "userEmail"
        static let messageId = "messageId"
        static let processedAt = "processedAt"
    }

    private init() {}

    func sync(container: CKContainer, userEmail: String, context: NSManagedObjectContext) async {
        let db = container.privateCloudDatabase
        let normalizedEmail = userEmail.lowercased()

        do {
            // 1) Pull da CloudKit → CoreData
            let query = CKQuery(recordType: RecordType.processedEmail, predicate: NSPredicate(format: "%K == %@", Keys.userEmail, normalizedEmail))
            let remote = try await db.performQueryAsync(query)
            try await applyRemote(remote, context: context)

            // 2) Push CoreData → CloudKit
            let local = try await fetchLocal(context: context)
            for item in local {
                guard let messageId = item.messageId, !messageId.isEmpty else { continue }
                let recordID = CKRecord.ID(recordName: messageId)
                let record = CKRecord(recordType: RecordType.processedEmail, recordID: recordID)
                record[Keys.userEmail] = normalizedEmail as CKRecordValue
                record[Keys.messageId] = messageId as CKRecordValue
                record[Keys.processedAt] = (item.processedDate ?? Date()) as CKRecordValue
                _ = try await db.saveRecordAsync(record)
            }
        } catch {
            print("[CloudKitProcessedEmailSync] ❌ \(error)")
        }
    }

    private func fetchLocal(context: NSManagedObjectContext) async throws -> [ProcessedEmail] {
        try await context.perform {
            let req = NSFetchRequest<ProcessedEmail>(entityName: "ProcessedEmail")
            return try context.fetch(req)
        }
    }

    private func applyRemote(_ records: [CKRecord], context: NSManagedObjectContext) async throws {
        try await context.perform {
            for record in records {
                guard let messageId = record[Keys.messageId] as? String, !messageId.isEmpty else { continue }
                let processedAt = record[Keys.processedAt] as? Date

                let req = NSFetchRequest<ProcessedEmail>(entityName: "ProcessedEmail")
                req.fetchLimit = 1
                req.predicate = NSPredicate(format: "messageId == %@", messageId)
                if let existing = try? context.fetch(req).first {
                    if let processedAt, (existing.processedDate ?? .distantPast) < processedAt {
                        existing.processedDate = processedAt
                    }
                    continue
                }

                let pe = ProcessedEmail(context: context)
                pe.messageId = messageId
                pe.processedDate = processedAt ?? Date()
            }

            if context.hasChanges {
                try context.save()
            }
        }
    }

    // MARK: - CloudKit wrappers (using shared extensions)
}

