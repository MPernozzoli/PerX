import Foundation
import PerXCore

/// Servizio per gestire la job queue
public actor JobService {
    public static let shared = JobService()
    
    private init() {}
    
    // MARK: - Create Jobs
    
    /// Crea job di import cartella sinistro
    public func createImportFolderJob(sinistroRef: String, legacyPath: String, priority: Int = 0, tenantSlug: String = "default") async throws -> Job {
        let job = Job(
            tenantSlug: tenantSlug,
            type: .importFolder,
            priority: priority,
            payload: .importFolder(ImportFolderPayload(sinistroRef: sinistroRef, legacyPath: legacyPath))
        )
        
        try await DatabaseManager.shared.saveJob(job)
        print("[JobService] Created import folder job: \(job.id) for \(sinistroRef)")
        
        // Aggiorna stato cartella
        try await DatabaseManager.shared.updateSinistroFolderStatus(sinistroRef: sinistroRef, status: .importing, tenantSlug: tenantSlug)
        
        return job
    }
    
    /// Crea job di import singolo file
    public func createImportFileJob(sinistroRef: String, legacyPath: String, targetFolder: String, priority: Int = 0, tenantSlug: String = "default") async throws -> Job {
        let job = Job(
            tenantSlug: tenantSlug,
            type: .importFile,
            priority: priority,
            payload: .importFile(ImportFilePayload(sinistroRef: sinistroRef, legacyPath: legacyPath, targetFolder: targetFolder))
        )
        
        try await DatabaseManager.shared.saveJob(job)
        print("[JobService] Created import file job: \(job.id)")
        
        return job
    }
    
    /// Crea job di export file
    public func createExportFileJob(vaultFileId: String, legacyPath: String, priority: Int = 0, tenantSlug: String = "default") async throws -> Job {
        let job = Job(
            tenantSlug: tenantSlug,
            type: .exportFile,
            priority: priority,
            payload: .exportFile(ExportFilePayload(vaultFileId: vaultFileId, legacyPath: legacyPath))
        )
        
        try await DatabaseManager.shared.saveJob(job)
        print("[JobService] Created export file job: \(job.id)")
        
        return job
    }
    
    /// Crea job di delete file
    public func createDeleteFileJob(legacyPath: String, priority: Int = 0, tenantSlug: String = "default") async throws -> Job {
        let job = Job(
            tenantSlug: tenantSlug,
            type: .deleteFile,
            priority: priority,
            payload: .deleteFile(DeleteFilePayload(legacyPath: legacyPath))
        )
        
        try await DatabaseManager.shared.saveJob(job)
        print("[JobService] Created delete file job: \(job.id)")
        
        return job
    }
    
    /// Crea job di rename file
    public func createRenameFileJob(oldPath: String, newPath: String, priority: Int = 0, tenantSlug: String = "default") async throws -> Job {
        let job = Job(
            tenantSlug: tenantSlug,
            type: .renameFile,
            priority: priority,
            payload: .renameFile(RenameFilePayload(oldPath: oldPath, newPath: newPath))
        )
        
        try await DatabaseManager.shared.saveJob(job)
        print("[JobService] Created rename file job: \(job.id)")
        
        return job
    }
    
    /// Crea job di scan legacy
    public func createScanLegacyJob(sinistroRef: String, legacyPath: String, priority: Int = 5, tenantSlug: String = "default") async throws -> Job {
        let job = Job(
            tenantSlug: tenantSlug,
            type: .scanLegacy,
            priority: priority,
            payload: .scanLegacy(ScanLegacyPayload(sinistroRef: sinistroRef, legacyPath: legacyPath))
        )
        
        try await DatabaseManager.shared.saveJob(job)
        print("[JobService] Created scan legacy job: \(job.id)")
        
        return job
    }
    
    // MARK: - Query Jobs
    
    /// Ottiene job pendenti
    public func getPendingJobs(limit: Int = 10, tenantSlug: String = "default") async throws -> [Job] {
        return try await DatabaseManager.shared.getPendingJobs(limit: limit, tenantSlug: tenantSlug)
    }
    
    /// Ottiene un job per ID
    public func getJob(id: String, tenantSlug: String = "default") async throws -> Job? {
        return try await DatabaseManager.shared.getJob(id: id, tenantSlug: tenantSlug)
    }
    
    // MARK: - Update Jobs
    
    /// Marca job come in progress
    public func startJob(id: String, tenantSlug: String = "default") async throws -> Job {
        try await DatabaseManager.shared.updateJobStatus(id: id, status: .inProgress, tenantSlug: tenantSlug)
        
        guard let job = try await DatabaseManager.shared.getJob(id: id, tenantSlug: tenantSlug) else {
            throw JobServiceError.jobNotFound(id)
        }
        
        print("[JobService] Started job: \(id)")
        return job
    }
    
    /// Marca job come completato
    public func completeJob(id: String, tenantSlug: String = "default") async throws -> Job {
        guard let job = try await DatabaseManager.shared.getJob(id: id, tenantSlug: tenantSlug) else {
            throw JobServiceError.jobNotFound(id)
        }
        
        try await DatabaseManager.shared.updateJobStatus(id: id, status: .completed, tenantSlug: tenantSlug)
        
        // Se era un import folder, aggiorna stato cartella
        if case .importFolder(let payload) = job.payload {
            try await DatabaseManager.shared.updateSinistroFolderStatus(sinistroRef: payload.sinistroRef, status: .ready, tenantSlug: tenantSlug)
        }
        
        print("[JobService] Completed job: \(id)")
        
        guard let updatedJob = try await DatabaseManager.shared.getJob(id: id, tenantSlug: tenantSlug) else {
            throw JobServiceError.jobNotFound(id)
        }
        
        return updatedJob
    }
    
    /// Marca job come fallito
    public func failJob(id: String, errorMessage: String, tenantSlug: String = "default") async throws -> Job {
        guard let job = try await DatabaseManager.shared.getJob(id: id, tenantSlug: tenantSlug) else {
            throw JobServiceError.jobNotFound(id)
        }
        
        try await DatabaseManager.shared.updateJobStatus(id: id, status: .failed, errorMessage: errorMessage, tenantSlug: tenantSlug)
        
        // Se era un import folder, aggiorna stato cartella
        if case .importFolder(let payload) = job.payload {
            try await DatabaseManager.shared.updateSinistroFolderStatus(sinistroRef: payload.sinistroRef, status: .error, errorMessage: errorMessage, tenantSlug: tenantSlug)
        }
        
        print("[JobService] Failed job: \(id) - \(errorMessage)")
        
        guard let updatedJob = try await DatabaseManager.shared.getJob(id: id, tenantSlug: tenantSlug) else {
            throw JobServiceError.jobNotFound(id)
        }
        
        return updatedJob
    }
    
    /// Annulla un job
    public func cancelJob(id: String, tenantSlug: String = "default") async throws -> Job {
        try await DatabaseManager.shared.updateJobStatus(id: id, status: .cancelled, tenantSlug: tenantSlug)
        
        guard let job = try await DatabaseManager.shared.getJob(id: id, tenantSlug: tenantSlug) else {
            throw JobServiceError.jobNotFound(id)
        }
        
        print("[JobService] Cancelled job: \(id)")
        return job
    }
}

// MARK: - Errors

public enum JobServiceError: Error, LocalizedError {
    case jobNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .jobNotFound(let id):
            return "Job not found: \(id)"
        }
    }
}
