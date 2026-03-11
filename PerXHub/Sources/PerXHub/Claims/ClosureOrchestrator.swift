import Foundation
import PerXCore
import SQLite

/// Orchestratore per la chiusura e riapertura sinistri
/// Gestisce il flusso: Client -> CK -> Hub -> Vault -> SyncAgent -> FS Legacy
public actor ClosureOrchestrator {
    public static let shared = ClosureOrchestrator()
    
    /// Giorni prima di rimuovere cartella dal Vault dopo chiusura
    private let vaultCleanupDelayDays = 30
    
    private init() {}
    
    // MARK: - Closure Flow
    
    /// Gestisce la chiusura di un sinistro
    public func handleClosure(sinistroRef: String) async throws -> ClosureResult {
        print("[ClosureOrchestrator] Starting closure for: \(sinistroRef)")
        
        var result = ClosureResult(sinistroRef: sinistroRef)
        
        // 1. Crea job per export file dalla _export folder verso FS Legacy
        let exportJobs = try await createExportJobs(sinistroRef: sinistroRef)
        result.exportJobsCreated = exportJobs.count
        
        // 2. Schedula rimozione cartella dal Vault
        let cleanupDate = Calendar.current.date(byAdding: .day, value: vaultCleanupDelayDays, to: Date())!
        try await scheduleVaultCleanup(sinistroRef: sinistroRef, cleanupDate: cleanupDate)
        result.vaultCleanupScheduled = cleanupDate
        
        // 3. Archivia riferimenti email (rimuovi body, mantieni messageId)
        let archivedEmails = try await archiveEmails(sinistroRef: sinistroRef)
        result.emailsArchived = archivedEmails
        
        // 4. Aggiorna stato sinistro
        try await updateSinistroStatus(sinistroRef: sinistroRef, status: "chiuso")
        
        print("[ClosureOrchestrator] Closure completed for: \(sinistroRef)")
        return result
    }
    
    // MARK: - Reopen Flow
    
    /// Gestisce la riapertura di un sinistro chiuso
    public func handleReopen(sinistroRef: String, triggeredBy: ReopenTrigger) async throws -> ReopenResult {
        print("[ClosureOrchestrator] Starting reopen for: \(sinistroRef), trigger: \(triggeredBy)")
        
        var result = ReopenResult(sinistroRef: sinistroRef)
        
        // 1. Cancella eventuale cleanup schedulato
        try await cancelScheduledCleanup(sinistroRef: sinistroRef)
        
        // 2. Verifica se cartella è ancora nel Vault
        let folderStatus = try await checkFolderStatus(sinistroRef: sinistroRef)
        
        if folderStatus == .notInVault {
            // 3a. Cartella non presente: crea job import da FS Legacy
            let legacyPath = try await getLegacyPath(sinistroRef: sinistroRef)
            let job = try await JobService.shared.createImportFolderJob(
                sinistroRef: sinistroRef,
                legacyPath: legacyPath,
                priority: 8
            )
            result.importJobCreated = job.id
            result.folderStatus = "importing"
        } else {
            // 3b. Cartella presente: già disponibile
            result.folderStatus = "available"
        }
        
        // 4. Ripristina email archiviate (scarica body on-demand)
        result.emailsRestored = try await restoreEmailReferences(sinistroRef: sinistroRef)
        
        // 5. Aggiorna stato sinistro (torna a stato precedente o default)
        try await updateSinistroStatus(sinistroRef: sinistroRef, status: "riaperto")
        
        print("[ClosureOrchestrator] Reopen completed for: \(sinistroRef)")
        return result
    }
    
    /// Verifica stato cartella e avvia sync se necessario (per apertura SinistroDetailView)
    public func ensureFolderAvailable(sinistroRef: String) async throws -> FolderAvailabilityResult {
        let folderStatus = try await checkFolderStatus(sinistroRef: sinistroRef)
        
        switch folderStatus {
        case .available:
            return FolderAvailabilityResult(status: .available, jobId: nil)
            
        case .importing:
            // Già in corso
            return FolderAvailabilityResult(status: .importing, jobId: nil)
            
        case .notInVault:
            // Avvia import
            let legacyPath = try await getLegacyPath(sinistroRef: sinistroRef)
            let job = try await JobService.shared.createImportFolderJob(
                sinistroRef: sinistroRef,
                legacyPath: legacyPath,
                priority: 5
            )
            return FolderAvailabilityResult(status: .importing, jobId: job.id)
            
        case .error:
            return FolderAvailabilityResult(status: .error, jobId: nil)
        }
    }
    
    // MARK: - Private Methods
    
    private func createExportJobs(sinistroRef: String) async throws -> [String] {
        // Ottieni file dalla cartella _export
        let files = try await VaultManager.shared.listFiles(sinistroRef: sinistroRef)
        let exportFiles = files.filter { $0.folder == "_export" }
        
        var jobIds: [String] = []
        
        for file in exportFiles {
            let legacyPath = try await calculateLegacyPathForFile(sinistroRef: sinistroRef, file: file)
            
            let job = try await JobService.shared.createExportFileJob(
                vaultFileId: file.id,
                legacyPath: legacyPath,
                priority: 3
            )
            jobIds.append(job.id)
        }
        
        return jobIds
    }
    
    private func scheduleVaultCleanup(sinistroRef: String, cleanupDate: Date) async throws {
        let conn = try await DatabaseManager.shared.db()
        
        // Aggiorna folder con data cleanup schedulata
        try conn.run(
            DatabaseSchema.sinistroFolders
                .filter(DatabaseSchema.SinistroFoldersColumns.sinistroRef == sinistroRef)
                .update(
                    DatabaseSchema.SinistroFoldersColumns.status <- "scheduled_cleanup",
                    DatabaseSchema.SinistroFoldersColumns.lastSyncAt <- cleanupDate.timeIntervalSince1970
                )
        )
    }
    
    private func cancelScheduledCleanup(sinistroRef: String) async throws {
        let conn = try await DatabaseManager.shared.db()
        
        try conn.run(
            DatabaseSchema.sinistroFolders
                .filter(DatabaseSchema.SinistroFoldersColumns.sinistroRef == sinistroRef)
                .update(DatabaseSchema.SinistroFoldersColumns.status <- "ready")
        )
    }
    
    private func archiveEmails(sinistroRef: String) async throws -> Int {
        let conn = try await DatabaseManager.shared.db()
        
        // Sposta riferimenti email nella tabella archived
        let query = DatabaseSchema.emails.filter(DatabaseSchema.EmailsColumns.sinistroRef == sinistroRef)
        var count = 0
        
        for row in try conn.prepare(query) {
            try conn.run(DatabaseSchema.archivedEmailRefs.insert(or: .replace,
                DatabaseSchema.ArchivedEmailRefsColumns.sinistroRef <- sinistroRef,
                DatabaseSchema.ArchivedEmailRefsColumns.messageId <- row[DatabaseSchema.EmailsColumns.messageId],
                DatabaseSchema.ArchivedEmailRefsColumns.date <- row[DatabaseSchema.EmailsColumns.date],
                DatabaseSchema.ArchivedEmailRefsColumns.subject <- row[DatabaseSchema.EmailsColumns.subject]
            ))
            count += 1
        }
        
        // Rimuovi body dalle email (mantieni metadati)
        try conn.run(
            query.update(DatabaseSchema.EmailsColumns.body <- nil)
        )
        
        return count
    }
    
    private func restoreEmailReferences(sinistroRef: String) async throws -> Int {
        let conn = try await DatabaseManager.shared.db()
        
        // Conta email archiviate da ripristinare
        let count = try conn.scalar(
            DatabaseSchema.archivedEmailRefs
                .filter(DatabaseSchema.ArchivedEmailRefsColumns.sinistroRef == sinistroRef)
                .count
        )
        
        // Il body verrà scaricato on-demand quando l'utente apre la mail
        return count
    }
    
    private func updateSinistroStatus(sinistroRef: String, status: String) async throws {
        let conn = try await DatabaseManager.shared.db()
        
        let newState: StatoSinistro = status == "chiuso" ? .chiusa : .daScaricare
        
        try conn.run(
            DatabaseSchema.sinistri
                .filter(DatabaseSchema.SinistriColumns.riferimento == sinistroRef)
                .update(
                    DatabaseSchema.SinistriColumns.stato <- newState.descrizione,
                    DatabaseSchema.SinistriColumns.lastModifiedAt <- Date().timeIntervalSince1970,
                    DatabaseSchema.SinistriColumns.syncedToCK <- false
                )
        )
    }
    
    private func checkFolderStatus(sinistroRef: String) async throws -> FolderStatus {
        guard let folder = try await DatabaseManager.shared.getSinistroFolder(sinistroRef: sinistroRef) else {
            return .notInVault
        }
        
        switch folder.status {
        case .ready:
            return .available
        case .importing:
            return .importing
        case .error:
            return .error
        default:
            return .notInVault
        }
    }
    
    private func getLegacyPath(sinistroRef: String) async throws -> String {
        let conn = try await DatabaseManager.shared.db()
        
        let query = DatabaseSchema.sinistri.filter(DatabaseSchema.SinistriColumns.riferimento == sinistroRef)
        
        guard let row = try conn.pluck(query),
              let legacyPath = row[DatabaseSchema.SinistriColumns.legacyPath] else {
            throw ClosureError.legacyPathNotFound
        }
        
        return legacyPath
    }
    
    private func calculateLegacyPathForFile(sinistroRef: String, file: VaultFile) async throws -> String {
        let basePath = try await getLegacyPath(sinistroRef: sinistroRef)
        // I file in _export vanno nella root della cartella legacy
        return "\(basePath)\\\(file.filename)"
    }
}

// MARK: - Types

public enum FolderStatus {
    case available
    case importing
    case notInVault
    case error
}

public enum ReopenTrigger: String, Codable {
    case userAction       // Utente clicca "Riapri"
    case viewOpened       // Utente apre SinistroDetailView
    case newEmail         // Arriva nuova mail per sinistro chiuso
    case newWhatsApp      // Arriva nuovo messaggio WA
}

public struct ClosureResult: Codable, Sendable {
    let sinistroRef: String
    var exportJobsCreated: Int = 0
    var vaultCleanupScheduled: Date?
    var emailsArchived: Int = 0
}

public struct ReopenResult: Codable, Sendable {
    let sinistroRef: String
    var importJobCreated: String?
    var folderStatus: String = "unknown"
    var emailsRestored: Int = 0
}

public struct FolderAvailabilityResult: Codable, Sendable {
    public enum Status: String, Codable {
        case available
        case importing
        case error
    }
    
    let status: Status
    let jobId: String?
}

public enum ClosureError: Error, LocalizedError {
    case legacyPathNotFound
    
    public var errorDescription: String? {
        switch self {
        case .legacyPathNotFound:
            return "Legacy path not found for sinistro"
        }
    }
}
