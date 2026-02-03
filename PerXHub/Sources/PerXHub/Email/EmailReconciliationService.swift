import Foundation
import PerXCore
import SQLite

/// Servizio per riconciliazione email
/// Gestisce email inviate da altri canali (Gmail web, mobile app, etc.)
public actor EmailReconciliationService {
    public static let shared = EmailReconciliationService()
    
    private init() {}
    
    // MARK: - Reconciliation
    
    /// Riconcilia email dal folder SENT di un account
    /// - Parameters:
    ///   - accountId: ID dell'account
    ///   - emails: Email da riconciliare (ricevute dal worker Python)
    ///   - emailProcessor: Processor per classificare le email
    /// - Returns: Risultato riconciliazione
    public func reconcileSentEmails(
        accountId: String,
        emails: [Email],
        emailProcessor: EmailProcessor
    ) async throws -> ReconciliationResult {
        var newCount = 0
        var duplicateCount = 0
        var processedIds: [String] = []
        
        for email in emails {
            // Check if already exists
            let exists = try await emailExists(messageId: email.id)
            
            if exists {
                duplicateCount += 1
            } else {
                // Nuova email inviata da altro canale
                _ = try await emailProcessor.processEmail(email, accountId: accountId, mailboxId: "SENT")
                
                newCount += 1
                processedIds.append(email.id)
            }
        }
        
        print("[Reconciliation] Account \(accountId): \(newCount) new, \(duplicateCount) duplicates")
        
        return ReconciliationResult(
            accountId: accountId,
            newEmails: newCount,
            duplicates: duplicateCount,
            processedMessageIds: processedIds
        )
    }
    
    /// Verifica che email non sia duplicata
    private func emailExists(messageId: String) async throws -> Bool {
        let db = try await DatabaseManager.shared.db()
        let query = DatabaseSchema.emails.filter(
            DatabaseSchema.EmailsColumns.messageId == messageId
        )
        
        let count = try db.scalar(query.count)
        return count > 0
    }
    
    /// Riconcilia email tra più account (per email in CC)
    public func deduplicateAcrossAccounts(messageId: String, accounts: [String]) async throws {
        // L'email esiste già, aggiungi solo i mapping per gli altri account
        let db = try await DatabaseManager.shared.db()
        
        for accountId in accounts {
            // Check if mapping exists
            let query = DatabaseSchema.emailAccounts.filter(
                DatabaseSchema.EmailAccountsColumns.messageId == messageId &&
                DatabaseSchema.EmailAccountsColumns.accountId == accountId
            )
            
            let exists = try db.scalar(query.count) > 0
            
            if !exists {
                try db.run(DatabaseSchema.emailAccounts.insert(
                    DatabaseSchema.EmailAccountsColumns.messageId <- messageId,
                    DatabaseSchema.EmailAccountsColumns.accountId <- accountId,
                    DatabaseSchema.EmailAccountsColumns.mailbox <- nil,
                    DatabaseSchema.EmailAccountsColumns.isRead <- false
                ))
                
                print("[Reconciliation] Added account mapping: \(messageId) -> \(accountId)")
            }
        }
    }
    
    /// Sincronizza stato letto tra account
    public func syncReadStatus(messageId: String, isRead: Bool, forAccounts accounts: [String]) async throws {
        let db = try await DatabaseManager.shared.db()
        
        for accountId in accounts {
            let query = DatabaseSchema.emailAccounts.filter(
                DatabaseSchema.EmailAccountsColumns.messageId == messageId &&
                DatabaseSchema.EmailAccountsColumns.accountId == accountId
            )
            
            try db.run(query.update(
                DatabaseSchema.EmailAccountsColumns.isRead <- isRead
            ))
        }
    }
    
    /// Trova email potenzialmente duplicate in base a subject + date
    public func findPotentialDuplicates(subject: String?, date: Date, tolerance: TimeInterval = 60) async throws -> [String] {
        guard let subject = subject, !subject.isEmpty else {
            return []
        }
        
        let db = try await DatabaseManager.shared.db()
        
        let minDate = date.addingTimeInterval(-tolerance)
        let maxDate = date.addingTimeInterval(tolerance)
        
        let query = DatabaseSchema.emails
            .filter(DatabaseSchema.EmailsColumns.subject == subject)
            .filter(DatabaseSchema.EmailsColumns.date >= minDate.timeIntervalSince1970)
            .filter(DatabaseSchema.EmailsColumns.date <= maxDate.timeIntervalSince1970)
        
        var results: [String] = []
        for row in try db.prepare(query) {
            results.append(row[DatabaseSchema.EmailsColumns.messageId])
        }
        
        return results
    }
    
    /// Ottiene statistiche riconciliazione
    public func getReconciliationStats() async throws -> [String: Int] {
        let db = try await DatabaseManager.shared.db()
        
        // Conta email per direzione
        let inboundQuery = DatabaseSchema.emails.filter(DatabaseSchema.EmailsColumns.direction == "IN")
        let outboundQuery = DatabaseSchema.emails.filter(DatabaseSchema.EmailsColumns.direction == "OUT")
        
        let inboundCount = try db.scalar(inboundQuery.count)
        let outboundCount = try db.scalar(outboundQuery.count)
        
        // Conta email multi-account
        // Simplified: just count distinct message_ids with multiple accounts
        let totalMappings = try db.scalar(DatabaseSchema.emailAccounts.count)
        let distinctEmails = try db.scalar(DatabaseSchema.emails.count)
        let multiAccountEstimate = totalMappings - distinctEmails
        
        return [
            "inbound": inboundCount,
            "outbound": outboundCount,
            "multiAccount": max(0, multiAccountEstimate),
            "total": inboundCount + outboundCount
        ]
    }
}

// MARK: - Types

public struct ReconciliationResult: Codable, Sendable {
    public let accountId: String
    public let newEmails: Int
    public let duplicates: Int
    public let processedMessageIds: [String]
}
