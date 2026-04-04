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
        
        try db.run(DatabaseSchema.vaultFiles.insert(or: .replace,
            DatabaseSchema.VaultFilesColumns.id <- file.id,
            DatabaseSchema.VaultFilesColumns.tenantSlug <- file.tenantSlug,
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
    
    public func getVaultFile(id: String, tenantSlug: String = "default") throws -> VaultFile? {
        let db = try db()
        let query = DatabaseSchema.vaultFiles
            .filter(DatabaseSchema.VaultFilesColumns.tenantSlug == tenantSlug)
            .filter(DatabaseSchema.VaultFilesColumns.id == id)
        
        guard let row = try db.pluck(query) else {
            return nil
        }
        
        return vaultFileFromRow(row)
    }
    
    public func listVaultFiles(sinistroRef: String, tenantSlug: String = "default") throws -> [VaultFile] {
        let db = try db()
        let query = DatabaseSchema.vaultFiles
            .filter(DatabaseSchema.VaultFilesColumns.tenantSlug == tenantSlug)
            .filter(DatabaseSchema.VaultFilesColumns.sinistroRef == sinistroRef)
            .order(DatabaseSchema.VaultFilesColumns.folder, DatabaseSchema.VaultFilesColumns.filename)
        
        return try db.prepare(query).map { vaultFileFromRow($0) }
    }
    
    public func deleteVaultFile(id: String, tenantSlug: String = "default") throws {
        let db = try db()
        let query = DatabaseSchema.vaultFiles
            .filter(DatabaseSchema.VaultFilesColumns.tenantSlug == tenantSlug)
            .filter(DatabaseSchema.VaultFilesColumns.id == id)
        try db.run(query.delete())
    }
    
    private func vaultFileFromRow(_ row: Row) -> VaultFile {
        VaultFile(
            id: row[DatabaseSchema.VaultFilesColumns.id],
            tenantSlug: row[DatabaseSchema.VaultFilesColumns.tenantSlug],
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
            DatabaseSchema.JobsColumns.tenantSlug <- job.tenantSlug,
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
    
    public func getJob(id: String, tenantSlug: String = "default") throws -> Job? {
        let db = try db()
        let query = DatabaseSchema.jobs
            .filter(DatabaseSchema.JobsColumns.tenantSlug == tenantSlug)
            .filter(DatabaseSchema.JobsColumns.id == id)
        
        guard let row = try db.pluck(query) else {
            return nil
        }
        
        return try jobFromRow(row)
    }
    
    public func getPendingJobs(limit: Int = 10, tenantSlug: String = "default") throws -> [Job] {
        let db = try db()
        let query = DatabaseSchema.jobs
            .filter(DatabaseSchema.JobsColumns.tenantSlug == tenantSlug)
            .filter(DatabaseSchema.JobsColumns.status == JobStatus.pending.rawValue)
            .order(DatabaseSchema.JobsColumns.priority.desc, DatabaseSchema.JobsColumns.createdAt.asc)
            .limit(limit)
        
        return try db.prepare(query).compactMap { try? jobFromRow($0) }
    }
    
    public func updateJobStatus(id: String, status: JobStatus, errorMessage: String? = nil, tenantSlug: String = "default") throws {
        let db = try db()
        let query = DatabaseSchema.jobs
            .filter(DatabaseSchema.JobsColumns.tenantSlug == tenantSlug)
            .filter(DatabaseSchema.JobsColumns.id == id)
        
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
            tenantSlug: row[DatabaseSchema.JobsColumns.tenantSlug],
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
            DatabaseSchema.SinistroFoldersColumns.tenantSlug <- folder.tenantSlug,
            DatabaseSchema.SinistroFoldersColumns.sinistroRef <- folder.sinistroRef,
            DatabaseSchema.SinistroFoldersColumns.status <- folder.status.rawValue,
            DatabaseSchema.SinistroFoldersColumns.lastSyncAt <- folder.lastSyncAt?.timeIntervalSince1970,
            DatabaseSchema.SinistroFoldersColumns.fileCount <- folder.fileCount,
            DatabaseSchema.SinistroFoldersColumns.totalSize <- folder.totalSize,
            DatabaseSchema.SinistroFoldersColumns.errorMessage <- folder.errorMessage
        ))
    }
    
    public func getSinistroFolder(sinistroRef: String, tenantSlug: String = "default") throws -> SinistroFolder? {
        let db = try db()
        let query = DatabaseSchema.sinistroFolders
            .filter(DatabaseSchema.SinistroFoldersColumns.tenantSlug == tenantSlug)
            .filter(DatabaseSchema.SinistroFoldersColumns.sinistroRef == sinistroRef)
        
        guard let row = try db.pluck(query) else {
            return nil
        }
        
        return SinistroFolder(
            tenantSlug: row[DatabaseSchema.SinistroFoldersColumns.tenantSlug],
            sinistroRef: row[DatabaseSchema.SinistroFoldersColumns.sinistroRef],
            status: SinistroFolderStatus(rawValue: row[DatabaseSchema.SinistroFoldersColumns.status]) ?? .pending,
            lastSyncAt: row[DatabaseSchema.SinistroFoldersColumns.lastSyncAt].map { Date(timeIntervalSince1970: $0) },
            fileCount: row[DatabaseSchema.SinistroFoldersColumns.fileCount],
            totalSize: row[DatabaseSchema.SinistroFoldersColumns.totalSize],
            errorMessage: row[DatabaseSchema.SinistroFoldersColumns.errorMessage]
        )
    }
    
    public func updateSinistroFolderStatus(sinistroRef: String, status: SinistroFolderStatus, errorMessage: String? = nil, tenantSlug: String = "default") throws {
        let db = try db()
        let query = DatabaseSchema.sinistroFolders
            .filter(DatabaseSchema.SinistroFoldersColumns.tenantSlug == tenantSlug)
            .filter(DatabaseSchema.SinistroFoldersColumns.sinistroRef == sinistroRef)
        
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

    // MARK: - Assignment Planner

    public func savePlannerSettings(_ settings: AssignmentPlannerSettingsDTO) throws {
        let db = try db()
        let payload = try JSONEncoder().encode(settings)
        let payloadJSON = String(data: payload, encoding: .utf8) ?? "{}"

        try db.run(DatabaseSchema.plannerSettings.insert(or: .replace,
            DatabaseSchema.PlannerSettingsColumns.tenantSlug <- settings.tenantSlug,
            DatabaseSchema.PlannerSettingsColumns.settingsJSON <- payloadJSON,
            DatabaseSchema.PlannerSettingsColumns.updatedAt <- Date().timeIntervalSince1970
        ))
    }

    public func getPlannerSettings(tenantSlug: String) throws -> AssignmentPlannerSettingsDTO? {
        let db = try db()
        let query = DatabaseSchema.plannerSettings.filter(DatabaseSchema.PlannerSettingsColumns.tenantSlug == tenantSlug)
        guard let row = try db.pluck(query) else { return nil }
        let payloadData = row[DatabaseSchema.PlannerSettingsColumns.settingsJSON].data(using: .utf8) ?? Data()
        return try JSONDecoder().decode(AssignmentPlannerSettingsDTO.self, from: payloadData)
    }

    public func listPlannerMemberSettings(tenantSlug: String) throws -> [AssignmentMemberSettingsDTO] {
        let db = try db()
        let query = DatabaseSchema.plannerMemberSettings
            .filter(DatabaseSchema.PlannerMemberSettingsColumns.tenantSlug == tenantSlug)
            .order(DatabaseSchema.PlannerMemberSettingsColumns.email.asc)

        let decoder = JSONDecoder()
        return try db.prepare(query).compactMap { row in
            let data = row[DatabaseSchema.PlannerMemberSettingsColumns.payloadJSON].data(using: .utf8) ?? Data()
            return try? decoder.decode(AssignmentMemberSettingsDTO.self, from: data)
        }
    }

    public func savePlannerMemberSetting(_ settings: AssignmentMemberSettingsDTO) throws {
        let db = try db()
        let payload = try JSONEncoder().encode(settings)
        let payloadJSON = String(data: payload, encoding: .utf8) ?? "{}"

        try db.run(DatabaseSchema.plannerMemberSettings.insert(or: .replace,
            DatabaseSchema.PlannerMemberSettingsColumns.tenantSlug <- settings.tenantSlug,
            DatabaseSchema.PlannerMemberSettingsColumns.email <- settings.email.lowercased(),
            DatabaseSchema.PlannerMemberSettingsColumns.payloadJSON <- payloadJSON,
            DatabaseSchema.PlannerMemberSettingsColumns.updatedAt <- Date().timeIntervalSince1970
        ))
    }

    public func replacePlannerAssignments(_ plan: AssignmentPlanDTO) throws {
        let db = try db()
        let encoder = JSONEncoder()
        try db.transaction {
            let scoped = DatabaseSchema.plannerAssignments.filter(DatabaseSchema.PlannerAssignmentsColumns.tenantSlug == plan.tenantSlug)
            try db.run(scoped.delete())
            let planPayload = try encoder.encode(plan)
            let planPayloadJSON = String(data: planPayload, encoding: .utf8) ?? "{}"
            try db.run(DatabaseSchema.plannerAssignments.insert(
                DatabaseSchema.PlannerAssignmentsColumns.tenantSlug <- plan.tenantSlug,
                DatabaseSchema.PlannerAssignmentsColumns.claimReference <- "__meta__",
                DatabaseSchema.PlannerAssignmentsColumns.payloadJSON <- planPayloadJSON,
                DatabaseSchema.PlannerAssignmentsColumns.generatedAt <- plan.generatedAt.timeIntervalSince1970
            ))
            for assignment in plan.assignments {
                let payload = try encoder.encode(assignment)
                let payloadJSON = String(data: payload, encoding: .utf8) ?? "{}"
                try db.run(DatabaseSchema.plannerAssignments.insert(
                    DatabaseSchema.PlannerAssignmentsColumns.tenantSlug <- plan.tenantSlug,
                    DatabaseSchema.PlannerAssignmentsColumns.claimReference <- assignment.claimReference,
                    DatabaseSchema.PlannerAssignmentsColumns.payloadJSON <- payloadJSON,
                    DatabaseSchema.PlannerAssignmentsColumns.generatedAt <- plan.generatedAt.timeIntervalSince1970
                ))
            }
        }
    }

    public func getPlannerPlan(tenantSlug: String) throws -> AssignmentPlanDTO? {
        let db = try db()
        let metaQuery = DatabaseSchema.plannerAssignments
            .filter(DatabaseSchema.PlannerAssignmentsColumns.tenantSlug == tenantSlug)
            .filter(DatabaseSchema.PlannerAssignmentsColumns.claimReference == "__meta__")
            .order(DatabaseSchema.PlannerAssignmentsColumns.generatedAt.desc)

        if let row = try db.pluck(metaQuery) {
            let payloadData = row[DatabaseSchema.PlannerAssignmentsColumns.payloadJSON].data(using: .utf8) ?? Data()
            return try JSONDecoder().decode(AssignmentPlanDTO.self, from: payloadData)
        }

        let query = DatabaseSchema.plannerAssignments
            .filter(DatabaseSchema.PlannerAssignmentsColumns.tenantSlug == tenantSlug)
            .order(DatabaseSchema.PlannerAssignmentsColumns.generatedAt.desc)

        let rows = Array(try db.prepare(query))
        guard !rows.isEmpty else { return nil }
        let decoder = JSONDecoder()
        let assignments = rows.compactMap { row -> AssignmentPlanEntryDTO? in
            guard row[DatabaseSchema.PlannerAssignmentsColumns.claimReference] != "__meta__" else { return nil }
            let data = row[DatabaseSchema.PlannerAssignmentsColumns.payloadJSON].data(using: .utf8) ?? Data()
            return try? decoder.decode(AssignmentPlanEntryDTO.self, from: data)
        }
        let generatedAt = Date(timeIntervalSince1970: rows.first?[DatabaseSchema.PlannerAssignmentsColumns.generatedAt] ?? Date().timeIntervalSince1970)
        return AssignmentPlanDTO(
            tenantSlug: tenantSlug,
            generatedAt: generatedAt,
            assignments: assignments,
            unassignedClaimReferences: []
        )
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
