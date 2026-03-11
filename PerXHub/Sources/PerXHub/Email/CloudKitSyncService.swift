import Foundation
import PerXCore
import SQLite

/// Servizio per sincronizzazione CloudKit ottimizzata
/// - Sinistri attivi: email complete salvate su CK
/// - Sinistri chiusi: solo riferimenti (message-id) salvati, email scaricate on-demand
public actor CloudKitSyncService {
    public static let shared = CloudKitSyncService()
    
    private init() {}
    
    // MARK: - Sync to CloudKit
    
    /// Sincronizza email non ancora su CK
    public func syncPendingEmails() async throws -> SyncResult {
        var synced = 0
        var failed = 0
        
        // Ottieni email da sincronizzare
        let emails = try await getUnsyncedEmails(limit: 50)
        
        for email in emails {
            do {
                // Check se sinistro è attivo o chiuso
                let isActive = try await isSinistroActive(email.sinistroRef)
                
                if isActive {
                    // Sinistro attivo: sincronizza email completa
                    try await syncFullEmail(email)
                } else {
                    // Sinistro chiuso: archivia solo riferimento
                    try await archiveEmailRef(email)
                }
                
                // Marca come sincronizzata
                try await markAsSynced(messageId: email.messageId)
                synced += 1
                
            } catch {
                print("[CKSync] Failed to sync \(email.messageId): \(error)")
                failed += 1
            }
        }
        
        return SyncResult(synced: synced, failed: failed, pending: emails.count - synced - failed)
    }
    
    /// Ottiene email non ancora sincronizzate
    private func getUnsyncedEmails(limit: Int) async throws -> [StoredEmail] {
        let db = try await DatabaseManager.shared.db()
        
        let query = DatabaseSchema.emails
            .filter(DatabaseSchema.EmailsColumns.syncedToCK == false)
            .limit(limit)
        
        var results: [StoredEmail] = []
        for row in try db.prepare(query) {
            results.append(StoredEmail(
                messageId: row[DatabaseSchema.EmailsColumns.messageId],
                subject: row[DatabaseSchema.EmailsColumns.subject],
                date: Date(timeIntervalSince1970: row[DatabaseSchema.EmailsColumns.date]),
                sinistroRef: row[DatabaseSchema.EmailsColumns.sinistroRef],
                category: row[DatabaseSchema.EmailsColumns.category],
                direction: row[DatabaseSchema.EmailsColumns.direction]
            ))
        }
        
        return results
    }
    
    /// Sincronizza email completa su CloudKit
    private func syncFullEmail(_ email: StoredEmail) async throws {
        // TODO: Implementare salvataggio su CloudKit
        // Usa CKRecord per salvare tutti i campi dell'email
        print("[CKSync] Syncing full email: \(email.messageId)")
    }
    
    /// Archivia solo riferimento email (per sinistri chiusi)
    private func archiveEmailRef(_ email: StoredEmail) async throws {
        guard let sinistroRef = email.sinistroRef else { return }
        
        let db = try await DatabaseManager.shared.db()
        
        try db.run(DatabaseSchema.archivedEmailRefs.insert(or: .replace,
            DatabaseSchema.ArchivedEmailRefsColumns.sinistroRef <- sinistroRef,
            DatabaseSchema.ArchivedEmailRefsColumns.messageId <- email.messageId,
            DatabaseSchema.ArchivedEmailRefsColumns.date <- email.date.timeIntervalSince1970,
            DatabaseSchema.ArchivedEmailRefsColumns.subject <- email.subject
        ))
        
        print("[CKSync] Archived email ref: \(email.messageId)")
    }
    
    /// Marca email come sincronizzata
    private func markAsSynced(messageId: String) async throws {
        let db = try await DatabaseManager.shared.db()
        
        let query = DatabaseSchema.emails.filter(
            DatabaseSchema.EmailsColumns.messageId == messageId
        )
        
        try db.run(query.update(
            DatabaseSchema.EmailsColumns.syncedToCK <- true
        ))
    }
    
    // MARK: - Fetch from CloudKit
    
    /// Recupera email archiviate per un sinistro (on-demand)
    public func fetchArchivedEmails(sinistroRef: String) async throws -> [StoredEmail] {
        // 1. Ottieni lista riferimenti
        let refs = try await getArchivedRefs(sinistroRef: sinistroRef)
        
        if refs.isEmpty {
            return []
        }
        
        // 2. Fetch da CloudKit
        // TODO: Implementare query CloudKit per recuperare email
        print("[CKSync] Fetching \(refs.count) archived emails for \(sinistroRef)")
        
        return []
    }
    
    /// Ottiene riferimenti email archiviate
    private func getArchivedRefs(sinistroRef: String) async throws -> [ArchivedEmailRef] {
        let db = try await DatabaseManager.shared.db()
        
        let query = DatabaseSchema.archivedEmailRefs.filter(
            DatabaseSchema.ArchivedEmailRefsColumns.sinistroRef == sinistroRef
        )
        
        var refs: [ArchivedEmailRef] = []
        for row in try db.prepare(query) {
            refs.append(ArchivedEmailRef(
                sinistroRef: row[DatabaseSchema.ArchivedEmailRefsColumns.sinistroRef],
                messageId: row[DatabaseSchema.ArchivedEmailRefsColumns.messageId],
                date: Date(timeIntervalSince1970: row[DatabaseSchema.ArchivedEmailRefsColumns.date]),
                subject: row[DatabaseSchema.ArchivedEmailRefsColumns.subject]
            ))
        }
        
        return refs
    }
    
    // MARK: - Sinistro Status
    
    /// Verifica se sinistro è attivo
    private func isSinistroActive(_ sinistroRef: String?) async throws -> Bool {
        guard sinistroRef != nil else { return false }
        
        // TODO: Query a CloudKit o database locale per stato sinistro
        // Per ora assume attivo
        return true
    }
    
    /// Gestisce chiusura sinistro
    public func handleSinistroClosure(sinistroRef: String) async throws {
        // 1. Sposta email da storage completo a riferimenti
        let db = try await DatabaseManager.shared.db()
        
        let query = DatabaseSchema.emails.filter(
            DatabaseSchema.EmailsColumns.sinistroRef == sinistroRef
        )
        
        for row in try db.prepare(query) {
            let messageId = row[DatabaseSchema.EmailsColumns.messageId]
            let date = Date(timeIntervalSince1970: row[DatabaseSchema.EmailsColumns.date])
            let subject = row[DatabaseSchema.EmailsColumns.subject]
            
            // Crea riferimento
            try db.run(DatabaseSchema.archivedEmailRefs.insert(or: .replace,
                DatabaseSchema.ArchivedEmailRefsColumns.sinistroRef <- sinistroRef,
                DatabaseSchema.ArchivedEmailRefsColumns.messageId <- messageId,
                DatabaseSchema.ArchivedEmailRefsColumns.date <- date.timeIntervalSince1970,
                DatabaseSchema.ArchivedEmailRefsColumns.subject <- subject
            ))
        }
        
        // 2. Elimina email complete dal db locale (rimangono su CK)
        try db.run(query.delete())
        
        print("[CKSync] Archived \(sinistroRef) - emails moved to refs")
    }
    
    // MARK: - Stats
    
    public func getStats() async throws -> [String: Int] {
        let db = try await DatabaseManager.shared.db()
        
        let syncedQuery = DatabaseSchema.emails.filter(DatabaseSchema.EmailsColumns.syncedToCK == true)
        let unsyncedQuery = DatabaseSchema.emails.filter(DatabaseSchema.EmailsColumns.syncedToCK == false)
        let archivedQuery = DatabaseSchema.archivedEmailRefs
        
        return [
            "synced": try db.scalar(syncedQuery.count),
            "unsynced": try db.scalar(unsyncedQuery.count),
            "archived": try db.scalar(archivedQuery.count)
        ]
    }
}

// MARK: - Types

public struct SyncResult: Codable, Sendable {
    public let synced: Int
    public let failed: Int
    public let pending: Int
}

/// Email salvata nel database Hub
public struct StoredEmail: Codable, Sendable {
    public let messageId: String
    public let subject: String?
    public let date: Date
    public let sinistroRef: String?
    public let category: String?
    public let direction: String
}

/// Riferimento a email archiviata
public struct ArchivedEmailRef: Codable, Sendable {
    public let sinistroRef: String
    public let messageId: String
    public let date: Date
    public let subject: String?
}
