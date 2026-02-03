import Foundation
import SQLite

/// Manager per il database SQLite dell'Hub
public actor DatabaseManager {
    public static let shared = DatabaseManager()
    
    private var connection: Connection?
    private var dbPath: String?
    
    private init() {}
    
    /// Inizializza il database con il path specificato
    public func initialize(path: String) throws {
        self.dbPath = path
        
        // Crea directory se non esiste
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        
        // Connessione
        connection = try Connection(path)
        
        // Crea tabelle
        try DatabaseSchema.createTables(db: connection!)
        
        // Esegui migrazioni per database esistenti
        try DatabaseSchema.runMigrations(db: connection!)
        
        print("[DatabaseManager] Initialized at: \(path)")
    }
    
    /// Connessione al database
    public func db() throws -> Connection {
        guard let connection = connection else {
            throw DatabaseError.notInitialized
        }
        return connection
    }
    
    // MARK: - VaultFile Operations
    
    public func saveVaultFile(_ file: VaultFile) throws {
        let db = try db()
        let encoder = JSONEncoder()
        
        try db.run(DatabaseSchema.vaultFiles.insert(or: .replace,
            DatabaseSchema.VaultFilesColumns.id <- file.id,
            DatabaseSchema.VaultFilesColumns.sinistroRef <- file.sinistroRef,
            DatabaseSchema.VaultFilesColumns.relativePath <- file.relativePath,
            DatabaseSchema.VaultFilesColumns.filename <- file.filename,
            DatabaseSchema.VaultFilesColumns.folder <- file.folder,
            DatabaseSchema.VaultFilesColumns.size <- file.size,
            DatabaseSchema.VaultFilesColumns.mimeType <- file.mimeType,
            DatabaseSchema.VaultFilesColumns.checksum <- file.checksum,
            DatabaseSchema.VaultFilesColumns.source <- file.source.rawValue,
            DatabaseSchema.VaultFilesColumns.sourceId <- file.sourceId,
            DatabaseSchema.VaultFilesColumns.createdAt <- file.createdAt.timeIntervalSince1970,
            DatabaseSchema.VaultFilesColumns.modifiedAt <- file.modifiedAt?.timeIntervalSince1970
        ))
    }
    
    public func getVaultFile(id: String) throws -> VaultFile? {
        let db = try db()
        let query = DatabaseSchema.vaultFiles.filter(DatabaseSchema.VaultFilesColumns.id == id)
        
        guard let row = try db.pluck(query) else {
            return nil
        }
        
        return vaultFileFromRow(row)
    }
    
    public func listVaultFiles(sinistroRef: String) throws -> [VaultFile] {
        let db = try db()
        let query = DatabaseSchema.vaultFiles
            .filter(DatabaseSchema.VaultFilesColumns.sinistroRef == sinistroRef)
            .order(DatabaseSchema.VaultFilesColumns.folder, DatabaseSchema.VaultFilesColumns.filename)
        
        return try db.prepare(query).map { vaultFileFromRow($0) }
    }
    
    public func deleteVaultFile(id: String) throws {
        let db = try db()
        let query = DatabaseSchema.vaultFiles.filter(DatabaseSchema.VaultFilesColumns.id == id)
        try db.run(query.delete())
    }
    
    private func vaultFileFromRow(_ row: Row) -> VaultFile {
        VaultFile(
            id: row[DatabaseSchema.VaultFilesColumns.id],
            sinistroRef: row[DatabaseSchema.VaultFilesColumns.sinistroRef],
            relativePath: row[DatabaseSchema.VaultFilesColumns.relativePath],
            filename: row[DatabaseSchema.VaultFilesColumns.filename],
            folder: row[DatabaseSchema.VaultFilesColumns.folder],
            size: row[DatabaseSchema.VaultFilesColumns.size],
            mimeType: row[DatabaseSchema.VaultFilesColumns.mimeType],
            checksum: row[DatabaseSchema.VaultFilesColumns.checksum],
            source: VaultFileSource(rawValue: row[DatabaseSchema.VaultFilesColumns.source]) ?? .upload,
            sourceId: row[DatabaseSchema.VaultFilesColumns.sourceId],
            createdAt: Date(timeIntervalSince1970: row[DatabaseSchema.VaultFilesColumns.createdAt]),
            modifiedAt: row[DatabaseSchema.VaultFilesColumns.modifiedAt].map { Date(timeIntervalSince1970: $0) }
        )
    }
    
    // MARK: - Job Operations
    
    public func saveJob(_ job: Job) throws {
        let db = try db()
        let encoder = JSONEncoder()
        let payloadData = try encoder.encode(job.payload)
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"
        
        try db.run(DatabaseSchema.jobs.insert(or: .replace,
            DatabaseSchema.JobsColumns.id <- job.id,
            DatabaseSchema.JobsColumns.type <- job.type.rawValue,
            DatabaseSchema.JobsColumns.status <- job.status.rawValue,
            DatabaseSchema.JobsColumns.priority <- job.priority,
            DatabaseSchema.JobsColumns.payload <- payloadString,
            DatabaseSchema.JobsColumns.createdAt <- job.createdAt.timeIntervalSince1970,
            DatabaseSchema.JobsColumns.startedAt <- job.startedAt?.timeIntervalSince1970,
            DatabaseSchema.JobsColumns.completedAt <- job.completedAt?.timeIntervalSince1970,
            DatabaseSchema.JobsColumns.errorMessage <- job.errorMessage,
            DatabaseSchema.JobsColumns.retryCount <- job.retryCount
        ))
    }
    
    public func getJob(id: String) throws -> Job? {
        let db = try db()
        let query = DatabaseSchema.jobs.filter(DatabaseSchema.JobsColumns.id == id)
        
        guard let row = try db.pluck(query) else {
            return nil
        }
        
        return try jobFromRow(row)
    }
    
    public func getPendingJobs(limit: Int = 10) throws -> [Job] {
        let db = try db()
        let query = DatabaseSchema.jobs
            .filter(DatabaseSchema.JobsColumns.status == JobStatus.pending.rawValue)
            .order(DatabaseSchema.JobsColumns.priority.desc, DatabaseSchema.JobsColumns.createdAt.asc)
            .limit(limit)
        
        return try db.prepare(query).compactMap { try? jobFromRow($0) }
    }
    
    public func updateJobStatus(id: String, status: JobStatus, errorMessage: String? = nil) throws {
        let db = try db()
        let query = DatabaseSchema.jobs.filter(DatabaseSchema.JobsColumns.id == id)
        
        var updates: [Setter] = [
            DatabaseSchema.JobsColumns.status <- status.rawValue
        ]
        
        switch status {
        case .inProgress:
            updates.append(DatabaseSchema.JobsColumns.startedAt <- Date().timeIntervalSince1970)
        case .completed, .failed:
            updates.append(DatabaseSchema.JobsColumns.completedAt <- Date().timeIntervalSince1970)
        default:
            break
        }
        
        if let error = errorMessage {
            updates.append(DatabaseSchema.JobsColumns.errorMessage <- error)
        }
        
        try db.run(query.update(updates))
    }
    
    private func jobFromRow(_ row: Row) throws -> Job {
        let decoder = JSONDecoder()
        let payloadString = row[DatabaseSchema.JobsColumns.payload]
        let payloadData = payloadString.data(using: .utf8) ?? Data()
        let payload = try decoder.decode(JobPayload.self, from: payloadData)
        
        return Job(
            id: row[DatabaseSchema.JobsColumns.id],
            type: JobType(rawValue: row[DatabaseSchema.JobsColumns.type]) ?? .scanLegacy,
            status: JobStatus(rawValue: row[DatabaseSchema.JobsColumns.status]) ?? .pending,
            priority: row[DatabaseSchema.JobsColumns.priority],
            payload: payload,
            createdAt: Date(timeIntervalSince1970: row[DatabaseSchema.JobsColumns.createdAt]),
            startedAt: row[DatabaseSchema.JobsColumns.startedAt].map { Date(timeIntervalSince1970: $0) },
            completedAt: row[DatabaseSchema.JobsColumns.completedAt].map { Date(timeIntervalSince1970: $0) },
            errorMessage: row[DatabaseSchema.JobsColumns.errorMessage],
            retryCount: row[DatabaseSchema.JobsColumns.retryCount]
        )
    }
    
    // MARK: - SinistroFolder Operations
    
    public func saveSinistroFolder(_ folder: SinistroFolder) throws {
        let db = try db()
        
        try db.run(DatabaseSchema.sinistroFolders.insert(or: .replace,
            DatabaseSchema.SinistroFoldersColumns.sinistroRef <- folder.sinistroRef,
            DatabaseSchema.SinistroFoldersColumns.status <- folder.status.rawValue,
            DatabaseSchema.SinistroFoldersColumns.lastSyncAt <- folder.lastSyncAt?.timeIntervalSince1970,
            DatabaseSchema.SinistroFoldersColumns.fileCount <- folder.fileCount,
            DatabaseSchema.SinistroFoldersColumns.totalSize <- folder.totalSize,
            DatabaseSchema.SinistroFoldersColumns.errorMessage <- folder.errorMessage
        ))
    }
    
    public func getSinistroFolder(sinistroRef: String) throws -> SinistroFolder? {
        let db = try db()
        let query = DatabaseSchema.sinistroFolders.filter(DatabaseSchema.SinistroFoldersColumns.sinistroRef == sinistroRef)
        
        guard let row = try db.pluck(query) else {
            return nil
        }
        
        return SinistroFolder(
            sinistroRef: row[DatabaseSchema.SinistroFoldersColumns.sinistroRef],
            status: SinistroFolderStatus(rawValue: row[DatabaseSchema.SinistroFoldersColumns.status]) ?? .pending,
            lastSyncAt: row[DatabaseSchema.SinistroFoldersColumns.lastSyncAt].map { Date(timeIntervalSince1970: $0) },
            fileCount: row[DatabaseSchema.SinistroFoldersColumns.fileCount],
            totalSize: row[DatabaseSchema.SinistroFoldersColumns.totalSize],
            errorMessage: row[DatabaseSchema.SinistroFoldersColumns.errorMessage]
        )
    }
    
    public func updateSinistroFolderStatus(sinistroRef: String, status: SinistroFolderStatus, errorMessage: String? = nil) throws {
        let db = try db()
        let query = DatabaseSchema.sinistroFolders.filter(DatabaseSchema.SinistroFoldersColumns.sinistroRef == sinistroRef)
        
        var updates: [Setter] = [
            DatabaseSchema.SinistroFoldersColumns.status <- status.rawValue
        ]
        
        if let error = errorMessage {
            updates.append(DatabaseSchema.SinistroFoldersColumns.errorMessage <- error)
        }
        
        if status == .ready {
            updates.append(DatabaseSchema.SinistroFoldersColumns.lastSyncAt <- Date().timeIntervalSince1970)
        }
        
        try db.run(query.update(updates))
    }
}

// MARK: - Errors

public enum DatabaseError: Error, LocalizedError {
    case notInitialized
    case notFound
    case invalidData
    
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database not initialized. Call initialize(path:) first."
        case .notFound:
            return "Record not found."
        case .invalidData:
            return "Invalid data format."
        }
    }
}
