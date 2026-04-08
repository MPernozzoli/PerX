import Vapor
import PerXCore
import SQLite
import CryptoKit

private extension Request {
    func perxTenantSlug() -> String {
        let headerTenant = headers.first(name: "X-PerX-Tenant")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryTenant = query[String.self, at: "tenant"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([headerTenant, queryTenant, HubConfiguration.defaultTenantSlug].compactMap { $0 }.first { !$0.isEmpty }) ?? "default"
    }
}

private struct HubTenantDescriptor: Content {
    let tenantSlug: String
    let hubId: String
    let isDedicated: Bool
}

private struct InternalEnsureClaimRequest: Content {
    let tenantId: String
    let claimRef: String
}

private struct InternalUploadRequest: Content {
    let tenantId: String
    let claimRef: String
    let relativePath: String
    let data: String
    let mimeType: String?
}

private struct InternalPathRequest: Content {
    let relativePath: String
    let missingOk: Bool?
}

private struct InternalMoveCopyRequest: Content {
    let sourcePath: String
    let destinationPath: String
    let overwrite: Bool?
}

private struct InternalStorageResponse: Content {
    let relativePath: String
    let sizeBytes: Int64
    let checksumSHA256: String
}

private struct InternalDownloadResponse: Content {
    let relativePath: String
    let data: String
}

private func requireStorageAccess(_ req: Request) throws {
    let configured = HubConfiguration.storageSharedSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !configured.isEmpty else {
        throw Abort(.internalServerError, reason: "Storage shared secret not configured")
    }
    let provided = req.headers.first(name: "X-PerX-Storage-Token")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard provided == configured else {
        throw Abort(.unauthorized, reason: "Invalid storage token")
    }
}

private func absoluteVaultPath(for relativePath: String) throws -> String {
    let clean = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !clean.isEmpty, !clean.contains("..") else {
        throw Abort(.badRequest, reason: "Invalid relative path")
    }
    return "\(HubConfiguration.vaultPath)/\(clean)"
}

private func ensureParentDirectory(for fullPath: String) throws {
    let directory = URL(fileURLWithPath: fullPath).deletingLastPathComponent().path
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
}

// MARK: - WhatsApp QR Code Storage

/// Actor per gestire i QR codes WhatsApp in modo thread-safe
actor WhatsAppQRStorage {
    static let shared = WhatsAppQRStorage()
    
    private var qrCodes: [String: String] = [:]  // accountId -> qrCode
    private var statuses: [String: String] = [:]  // accountId -> status
    
    func setQRCode(for accountId: String, qr: String) {
        qrCodes[accountId] = qr
        statuses[accountId] = "waitingQR"
    }
    
    func getQRCode(for accountId: String) -> String? {
        return qrCodes[accountId]
    }
    
    func clearQRCode(for accountId: String) {
        qrCodes.removeValue(forKey: accountId)
    }
    
    func setStatus(for accountId: String, status: String) {
        statuses[accountId] = status
        // Se ready, pulisce il QR
        if status == "ready" || status == "disconnected" {
            qrCodes.removeValue(forKey: accountId)
        }
    }
    
    func getStatus(for accountId: String) -> String {
        return statuses[accountId] ?? "disconnected"
    }
}

/// Configura tutte le routes dell'Hub
func configureRoutes(_ app: Application, startTime: Date) throws {
    
    // MARK: - Health
    
    app.get("health") { req -> HealthResponse in
        let uptime = Date().timeIntervalSince(startTime)
        return HealthResponse(
            status: "ok",
            version: "1.2.0",
            uptime: uptime
        )
    }

    app.get("tenant-context") { req -> HubTenantDescriptor in
        let tenantSlug = req.perxTenantSlug()
        return HubTenantDescriptor(
            tenantSlug: tenantSlug,
            hubId: HubConfiguration.hubID,
            isDedicated: HubConfiguration.dedicatedTenantSlug == tenantSlug
        )
    }

    let internalStorage = app.grouped("internal", "storage")

    internalStorage.post("claims", "ensure") { req async throws -> HTTPStatus in
        try requireStorageAccess(req)
        let payload = try req.content.decode(InternalEnsureClaimRequest.self)
        try await VaultManager.shared.createSinistroFolder(sinistroRef: payload.claimRef, tenantSlug: payload.tenantId)
        return .ok
    }

    internalStorage.post("files", "upload", body: .collect(maxSize: "100mb")) { req async throws -> InternalStorageResponse in
        try requireStorageAccess(req)
        let payload = try req.content.decode(InternalUploadRequest.self)
        guard let data = Data(base64Encoded: payload.data) else {
            throw Abort(.badRequest, reason: "Invalid base64 data")
        }
        let filePath = try absoluteVaultPath(for: payload.relativePath)
        try ensureParentDirectory(for: filePath)
        try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return InternalStorageResponse(
            relativePath: payload.relativePath,
            sizeBytes: Int64(data.count),
            checksumSHA256: checksum
        )
    }

    internalStorage.post("files", "download") { req async throws -> InternalDownloadResponse in
        try requireStorageAccess(req)
        let payload = try req.content.decode(InternalPathRequest.self)
        let filePath = try absoluteVaultPath(for: payload.relativePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw Abort(.notFound, reason: "File not found")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        return InternalDownloadResponse(
            relativePath: payload.relativePath,
            data: data.base64EncodedString()
        )
    }

    internalStorage.post("files", "copy") { req async throws -> HTTPStatus in
        try requireStorageAccess(req)
        let payload = try req.content.decode(InternalMoveCopyRequest.self)
        let sourcePath = try absoluteVaultPath(for: payload.sourcePath)
        let destinationPath = try absoluteVaultPath(for: payload.destinationPath)
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw Abort(.notFound, reason: "Source file not found")
        }
        try ensureParentDirectory(for: destinationPath)
        if FileManager.default.fileExists(atPath: destinationPath) {
            guard payload.overwrite == true else {
                throw Abort(.conflict, reason: "Destination already exists")
            }
            try FileManager.default.removeItem(atPath: destinationPath)
        }
        try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
        return .ok
    }

    internalStorage.post("files", "move") { req async throws -> HTTPStatus in
        try requireStorageAccess(req)
        let payload = try req.content.decode(InternalMoveCopyRequest.self)
        let sourcePath = try absoluteVaultPath(for: payload.sourcePath)
        let destinationPath = try absoluteVaultPath(for: payload.destinationPath)
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw Abort(.notFound, reason: "Source file not found")
        }
        try ensureParentDirectory(for: destinationPath)
        if FileManager.default.fileExists(atPath: destinationPath) {
            guard payload.overwrite == true else {
                throw Abort(.conflict, reason: "Destination already exists")
            }
            try FileManager.default.removeItem(atPath: destinationPath)
        }
        try FileManager.default.moveItem(atPath: sourcePath, toPath: destinationPath)
        return .ok
    }

    internalStorage.post("files", "delete") { req async throws -> HTTPStatus in
        try requireStorageAccess(req)
        let payload = try req.content.decode(InternalPathRequest.self)
        let filePath = try absoluteVaultPath(for: payload.relativePath)
        if FileManager.default.fileExists(atPath: filePath) {
            try FileManager.default.removeItem(atPath: filePath)
            return .ok
        }
        if payload.missingOk == true {
            return .ok
        }
        throw Abort(.notFound, reason: "File not found")
    }
    
    // MARK: - Heartbeat (per tracking utenti connessi)
    
    struct HeartbeatRequest: Content {
        let user_id: String
        let client_info: String?
    }
    
    app.post("heartbeat") { req async throws -> HTTPStatus in
        let request = try req.content.decode(HeartbeatRequest.self)
        let db = try await DatabaseManager.shared.db()
        let tenantSlug = req.perxTenantSlug()
        
        // Upsert: insert or update last_seen
        try db.run(DatabaseSchema.connectedClients.upsert(
            DatabaseSchema.ConnectedClientsColumns.tenantSlug <- tenantSlug,
            DatabaseSchema.ConnectedClientsColumns.userId <- request.user_id,
            DatabaseSchema.ConnectedClientsColumns.lastSeen <- Date().timeIntervalSince1970,
            DatabaseSchema.ConnectedClientsColumns.clientInfo <- request.client_info,
            onConflictOf: DatabaseSchema.ConnectedClientsColumns.tenantSlug, DatabaseSchema.ConnectedClientsColumns.userId
        ))
        
        print("[Hub] Heartbeat from \(request.user_id) tenant=\(tenantSlug)")
        return .ok
    }
    
    // MARK: - Stats (per Monitor)
    
    app.get("stats") { req async throws -> HubStatsResponse in
        let db = try await DatabaseManager.shared.db()
        let tenantSlug = req.perxTenantSlug()
        
        // Job stats
        let pendingJobsCount = try db.scalar(
            DatabaseSchema.jobs
                .filter(DatabaseSchema.JobsColumns.tenantSlug == tenantSlug)
                .filter(DatabaseSchema.JobsColumns.status == "pending").count
        )
        let inProgressJobsCount = try db.scalar(
            DatabaseSchema.jobs
                .filter(DatabaseSchema.JobsColumns.tenantSlug == tenantSlug)
                .filter(DatabaseSchema.JobsColumns.status == JobStatus.inProgress.rawValue).count
        )
        
        // Email stats
        let totalEmails = try db.scalar(DatabaseSchema.emails.filter(DatabaseSchema.EmailsColumns.tenantSlug == tenantSlug).count)
        let unsyncedEmails = try db.scalar(
            DatabaseSchema.emails
                .filter(DatabaseSchema.EmailsColumns.tenantSlug == tenantSlug)
                .filter(DatabaseSchema.EmailsColumns.syncedToCK == false).count
        )
        
        // Attachments stats
        let pendingAttachments = try db.scalar(
            DatabaseSchema.attachments
                .filter(DatabaseSchema.AttachmentsColumns.tenantSlug == tenantSlug)
                .filter(DatabaseSchema.AttachmentsColumns.status == "pending").count
        )
        let processingAttachments = try db.scalar(
            DatabaseSchema.attachments
                .filter(DatabaseSchema.AttachmentsColumns.tenantSlug == tenantSlug)
                .filter(DatabaseSchema.AttachmentsColumns.status == "processing").count
        )
        
        // Sinistri count
        let sinistroFolders = try db.scalar(
            DatabaseSchema.sinistroFolders.filter(DatabaseSchema.SinistroFoldersColumns.tenantSlug == tenantSlug).count
        )
        
        // Connected users (heartbeat negli ultimi 5 minuti)
        let fiveMinutesAgo = Date().timeIntervalSince1970 - 300 // 5 minuti
        let connectedUsersCount = try db.scalar(
            DatabaseSchema.connectedClients.filter(
                DatabaseSchema.ConnectedClientsColumns.tenantSlug == tenantSlug &&
                DatabaseSchema.ConnectedClientsColumns.lastSeen > fiveMinutesAgo
            ).count
        )
        
        // WhatsApp stats
        let totalWAMessages = try db.scalar(
            DatabaseSchema.whatsappMessages.filter(DatabaseSchema.WhatsAppMessagesColumns.tenantSlug == tenantSlug).count
        )
        
        // Messaggi di oggi
        let startOfToday = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let todayWAMessages = try db.scalar(
            DatabaseSchema.whatsappMessages
                .filter(DatabaseSchema.WhatsAppMessagesColumns.tenantSlug == tenantSlug)
                .filter(DatabaseSchema.WhatsAppMessagesColumns.timestamp >= startOfToday)
                .count
        )
        
        // Chat non lette
        let unreadChats = try db.scalar(
            DatabaseSchema.whatsappChats
                .filter(DatabaseSchema.WhatsAppChatsColumns.tenantSlug == tenantSlug)
                .filter(DatabaseSchema.WhatsAppChatsColumns.unreadCount > 0)
                .count
        )
        
        // Messaggi schedulati pending
        let scheduledPending = try db.scalar(
            DatabaseSchema.scheduledWhatsApp
                .filter(DatabaseSchema.ScheduledWhatsAppColumns.tenantSlug == tenantSlug)
                .filter(DatabaseSchema.ScheduledWhatsAppColumns.status == "pending")
                .count
        )
        
        let waStats = HubStatsResponse.WhatsAppStats(
            totalMessages: totalWAMessages,
            todayMessages: todayWAMessages,
            unreadChats: unreadChats,
            scheduledPending: scheduledPending
        )
        
        // Sync stats (cartelle monitorate e jobs di sync)
        let activeFolders = try db.scalar(
            DatabaseSchema.sinistroFolders
                .filter(DatabaseSchema.SinistroFoldersColumns.tenantSlug == tenantSlug)
                .filter(DatabaseSchema.SinistroFoldersColumns.status == SinistroFolderStatus.ready.rawValue)
                .count
        )
        let pendingSyncJobs = try db.scalar(
            DatabaseSchema.jobs
                .filter(DatabaseSchema.JobsColumns.tenantSlug == tenantSlug)
                .filter(DatabaseSchema.JobsColumns.status == "pending")
                .filter(DatabaseSchema.JobsColumns.type.like("%import%") || DatabaseSchema.JobsColumns.type.like("%export%") || DatabaseSchema.JobsColumns.type.like("%scan%"))
                .count
        )
        let syncStats = HubStatsResponse.SyncStats(
            activeFolders: activeFolders,
            pendingSyncs: pendingSyncJobs,
            lastSyncAt: nil  // TODO: tracciare l'ultimo sync completato
        )
        
        // Chrome Extension stats (entry diario e sync JFish di oggi)
        // Per ora contiamo le email con source "jfish" o diario entries recenti
        let todayScheduledEmails = try db.scalar(
            DatabaseSchema.scheduledEmails
                .filter(DatabaseSchema.ScheduledEmailsColumns.tenantSlug == tenantSlug)
                .filter(DatabaseSchema.ScheduledEmailsColumns.createdAt >= startOfToday)
                .count
        )
        let chromeStats = HubStatsResponse.ChromeExtStats(
            todayDiarioEntries: todayScheduledEmails,  // Proxy per attività
            todayJFishSyncs: 0  // TODO: aggiungere contatore JFish syncs
        )
        
        return HubStatsResponse(
            jobs: HubStatsResponse.JobStats(
                pending: pendingJobsCount,
                inProgress: inProgressJobsCount
            ),
            emails: HubStatsResponse.EmailStats(
                total: totalEmails,
                unsynced: unsyncedEmails
            ),
            attachments: HubStatsResponse.AttachmentStats(
                pending: pendingAttachments,
                processing: processingAttachments
            ),
            whatsapp: waStats,
            sync: syncStats,
            chromeExt: chromeStats,
            sinistri: sinistroFolders,
            uptime: Date().timeIntervalSince(startTime),
            connectedUsers: connectedUsersCount
        )
    }
    
    // MARK: - Vault Routes
    
    let vault = app.grouped("vault")
    
    // Lista file di un sinistro
    vault.get("sinistri", ":ref", "files") { req async throws -> [VaultFileDTO] in
        guard let ref = req.parameters.get("ref") else {
            throw Abort(.badRequest, reason: "Missing sinistro ref")
        }
        
        let files = try await VaultManager.shared.listFiles(sinistroRef: ref, tenantSlug: req.perxTenantSlug())
        return files.map { VaultFileDTO(from: $0) }
    }
    
    // Stato cartella sinistro
    vault.get("sinistri", ":ref", "status") { req async throws -> SinistroFolderDTO in
        guard let ref = req.parameters.get("ref") else {
            throw Abort(.badRequest, reason: "Missing sinistro ref")
        }
        
        guard let folder = try await DatabaseManager.shared.getSinistroFolder(sinistroRef: ref, tenantSlug: req.perxTenantSlug()) else {
            throw Abort(.notFound, reason: "Sinistro folder not found")
        }
        
        return SinistroFolderDTO(from: folder)
    }
    
    // Crea cartella sinistro
    vault.post("sinistri", ":ref") { req async throws -> SinistroFolderDTO in
        guard let ref = req.parameters.get("ref") else {
            throw Abort(.badRequest, reason: "Missing sinistro ref")
        }
        
        let tenantSlug = req.perxTenantSlug()
        try await VaultManager.shared.createSinistroFolder(sinistroRef: ref, tenantSlug: tenantSlug)
        
        guard let folder = try await DatabaseManager.shared.getSinistroFolder(sinistroRef: ref, tenantSlug: tenantSlug) else {
            throw Abort(.internalServerError, reason: "Failed to create folder")
        }
        
        return SinistroFolderDTO(from: folder)
    }
    
    // Download file
    vault.get("files", ":id", "download") { req async throws -> Response in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing file id")
        }
        
        let (file, data) = try await VaultManager.shared.getFile(id: id, tenantSlug: req.perxTenantSlug())
        
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: file.mimeType ?? "application/octet-stream")
        headers.add(name: .contentDisposition, value: "attachment; filename=\"\(file.filename)\"")
        headers.add(name: .contentLength, value: String(data.count))
        
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }
    
    // Upload file
    vault.on(.POST, "sinistri", ":ref", "upload", body: .collect(maxSize: "100mb")) { req async throws -> VaultFileDTO in
        guard let ref = req.parameters.get("ref") else {
            throw Abort(.badRequest, reason: "Missing sinistro ref")
        }
        
        let upload = try req.content.decode(FileUploadRequest.self)
        
        guard let data = Data(base64Encoded: upload.data) else {
            throw Abort(.badRequest, reason: "Invalid base64 data")
        }
        
        let file = try await VaultManager.shared.uploadFile(
            sinistroRef: ref,
            folder: upload.folder,
            filename: upload.filename,
            data: data,
            tenantSlug: req.perxTenantSlug(),
            source: .upload
        )
        
        return VaultFileDTO(from: file)
    }
    
    // Delete file
    vault.delete("files", ":id") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing file id")
        }
        
        try await VaultManager.shared.deleteFile(id: id, tenantSlug: req.perxTenantSlug())
        return .noContent
    }
    
    // Move to export
    vault.post("files", ":id", "export") { req async throws -> VaultFileDTO in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing file id")
        }
        
        let file = try await VaultManager.shared.moveToExport(id: id, tenantSlug: req.perxTenantSlug())
        return VaultFileDTO(from: file)
    }
    
    // MARK: - Jobs Routes
    
    let jobs = app.grouped("jobs")
    
    // Lista job pendenti
    jobs.get("pending") { req async throws -> [JobDTO] in
        let limit = req.query[Int.self, at: "limit"] ?? 10
        let pending = try await JobService.shared.getPendingJobs(limit: limit, tenantSlug: req.perxTenantSlug())
        return pending.map { JobDTO(from: $0) }
    }
    
    // Ottieni job per ID
    jobs.get(":id") { req async throws -> JobDTO in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing job id")
        }
        
        guard let job = try await JobService.shared.getJob(id: id, tenantSlug: req.perxTenantSlug()) else {
            throw Abort(.notFound, reason: "Job not found")
        }
        
        return JobDTO(from: job)
    }
    
    // Marca job come iniziato
    jobs.post(":id", "start") { req async throws -> JobDTO in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing job id")
        }
        
        let job = try await JobService.shared.startJob(id: id, tenantSlug: req.perxTenantSlug())
        return JobDTO(from: job)
    }
    
    // Marca job come completato
    jobs.post(":id", "complete") { req async throws -> JobDTO in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing job id")
        }
        
        let job = try await JobService.shared.completeJob(id: id, tenantSlug: req.perxTenantSlug())
        return JobDTO(from: job)
    }
    
    // Marca job come fallito
    jobs.post(":id", "fail") { req async throws -> JobDTO in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing job id")
        }
        
        let failRequest = try req.content.decode(JobFailRequest.self)
        let job = try await JobService.shared.failJob(id: id, errorMessage: failRequest.message, tenantSlug: req.perxTenantSlug())
        return JobDTO(from: job)
    }
    
    // Crea job di import cartella
    jobs.post("import", "folder") { req async throws -> JobDTO in
        struct ImportFolderRequest: Content {
            let sinistroRef: String
            let legacyPath: String
            let priority: Int?
        }
        
        let request = try req.content.decode(ImportFolderRequest.self)
        let job = try await JobService.shared.createImportFolderJob(
            sinistroRef: request.sinistroRef,
            legacyPath: request.legacyPath,
            priority: request.priority ?? 0,
            tenantSlug: req.perxTenantSlug()
        )
        return JobDTO(from: job)
    }
    
    // Crea job di export file
    jobs.post("export", "file") { req async throws -> JobDTO in
        struct ExportFileRequest: Content {
            let vaultFileId: String
            let legacyPath: String
            let priority: Int?
        }
        
        let request = try req.content.decode(ExportFileRequest.self)
        let job = try await JobService.shared.createExportFileJob(
            vaultFileId: request.vaultFileId,
            legacyPath: request.legacyPath,
            priority: request.priority ?? 0,
            tenantSlug: req.perxTenantSlug()
        )
        return JobDTO(from: job)
    }
    
    // Crea job di scan legacy
    jobs.post("scan", "legacy") { req async throws -> JobDTO in
        struct ScanRequest: Content {
            let sinistroRef: String
            let legacyPath: String
        }
        
        let request = try req.content.decode(ScanRequest.self)
        let job = try await JobService.shared.createScanLegacyJob(
            sinistroRef: request.sinistroRef,
            legacyPath: request.legacyPath,
            tenantSlug: req.perxTenantSlug()
        )
        return JobDTO(from: job)
    }
    
    // Upload file da job (per Windows Agent)
    jobs.on(.POST, ":id", "upload", body: .collect(maxSize: "100mb")) { req async throws -> VaultFileDTO in
        guard let jobId = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing job id")
        }
        
        let tenantSlug = req.perxTenantSlug()
        guard let job = try await JobService.shared.getJob(id: jobId, tenantSlug: tenantSlug) else {
            throw Abort(.notFound, reason: "Job not found")
        }
        
        let upload = try req.content.decode(FileUploadRequest.self)
        
        guard let data = Data(base64Encoded: upload.data) else {
            throw Abort(.badRequest, reason: "Invalid base64 data")
        }
        
        // Estrai sinistroRef dal payload del job
        let sinistroRef: String
        switch job.payload {
        case .importFolder(let payload):
            sinistroRef = payload.sinistroRef
        case .importFile(let payload):
            sinistroRef = payload.sinistroRef
        default:
            throw Abort(.badRequest, reason: "Job type does not support upload")
        }
        
        let file = try await VaultManager.shared.uploadFile(
            sinistroRef: sinistroRef,
            folder: upload.folder,
            filename: upload.filename,
            data: data,
            tenantSlug: tenantSlug,
            source: .importJob,
            sourceId: jobId
        )
        
        return VaultFileDTO(from: file)
    }

    // MARK: - Planner Routes

    let planner = app.grouped("planner")

    planner.get("settings") { req async throws -> AssignmentPlannerSettingsDTO in
        try await AssignmentPlannerService.shared.getSettings(tenantSlug: req.perxTenantSlug())
    }

    planner.post("settings") { req async throws -> AssignmentPlannerSettingsDTO in
        var settings = try req.content.decode(AssignmentPlannerSettingsDTO.self)
        settings = AssignmentPlannerSettingsDTO(
            tenantSlug: req.perxTenantSlug(),
            planningHorizonDays: settings.planningHorizonDays,
            defaultMonthlyTarget: settings.defaultMonthlyTarget,
            maxLoadRatioPerExpert: settings.maxLoadRatioPerExpert,
            rebalancePriorityMargin: settings.rebalancePriorityMargin,
            workingPenalty: settings.workingPenalty,
            offlinePenalty: settings.offlinePenalty,
            enabled: settings.enabled
        )
        return try await AssignmentPlannerService.shared.updateSettings(settings)
    }

    planner.get("members") { req async throws -> [AssignmentMemberSettingsDTO] in
        try await AssignmentPlannerService.shared.listMembers(tenantSlug: req.perxTenantSlug())
    }

    planner.post("members") { req async throws -> AssignmentMemberSettingsDTO in
        let member = try req.content.decode(AssignmentMemberSettingsDTO.self)
        let scopedMember = AssignmentMemberSettingsDTO(
            tenantSlug: req.perxTenantSlug(),
            email: member.email.lowercased(),
            displayName: member.displayName,
            assignedCompanies: member.assignedCompanies,
            roleOverrides: member.roleOverrides,
            monthlyClaimTarget: member.monthlyClaimTarget,
            maxAuthority: member.maxAuthority,
            preferredAgencyCodes: member.preferredAgencyCodes,
            preferredPolicyNumbers: member.preferredPolicyNumbers,
            preferredInsureds: member.preferredInsureds,
            isActive: member.isActive
        )
        return try await AssignmentPlannerService.shared.upsertMember(scopedMember)
    }

    planner.get("plan") { req async throws -> AssignmentPlanDTO in
        if let plan = try await AssignmentPlannerService.shared.currentPlan(tenantSlug: req.perxTenantSlug()) {
            return plan
        }
        return AssignmentPlanDTO(tenantSlug: req.perxTenantSlug(), assignments: [], unassignedClaimReferences: [])
    }

    planner.post("recompute") { req async throws -> AssignmentPlanDTO in
        let request = try? req.content.decode(AssignmentPlanRecomputeRequest.self)
        return try await AssignmentPlannerService.shared.recomputePlan(
            tenantSlug: req.perxTenantSlug(),
            reason: request?.reason
        )
    }
    
    // MARK: - Manifest Routes (per sync tracking)
    
    let manifest = app.grouped("manifest")
    
    // Processa scan result e ritorna cambiamenti
    manifest.post("scan-result") { req async throws -> LegacyChangesDTO in
        let scanResult = try req.content.decode(LegacyScanResult.self)
        let changes = try await ManifestService.shared.processLegacyScan(scanResult)
        return LegacyChangesDTO(from: changes)
    }
    
    // Registra import completato
    manifest.post("record-import") { req async throws -> HTTPStatus in
        struct RecordImportRequest: Content {
            let legacyPath: String
            let vaultFileId: String
            let checksum: String?
            let size: Int64
            let modifiedAt: Date?
        }
        
        let request = try req.content.decode(RecordImportRequest.self)
        try await ManifestService.shared.recordImport(
            legacyPath: request.legacyPath,
            vaultFileId: request.vaultFileId,
            checksum: request.checksum,
            size: request.size,
            modifiedAt: request.modifiedAt
        )
        return .ok
    }
    
    // Registra export completato
    manifest.post("record-export") { req async throws -> HTTPStatus in
        struct RecordExportRequest: Content {
            let legacyPath: String
            let vaultFileId: String
            let checksum: String?
            let size: Int64
        }
        
        let request = try req.content.decode(RecordExportRequest.self)
        try await ManifestService.shared.recordExport(
            legacyPath: request.legacyPath,
            vaultFileId: request.vaultFileId,
            checksum: request.checksum,
            size: request.size
        )
        return .ok
    }
    
    // MARK: - Internal Routes (per Python workers)
    
    let internalRoutes = app.grouped("internal")
    
    // Riceve email dal worker IMAP
    internalRoutes.post("email", "received") { req async throws -> EmailProcessedResponse in
        struct EmailReceivedRequest: Content {
            let message_id: String
            let account_id: String
            let subject: String?
            let from: EmailAddressRequest
            let to: [EmailAddressRequest]
            let cc: [EmailAddressRequest]?
            let date: String
            let body_text: String?
            let body_html: String?
            let attachments: [AttachmentRequest]?
            let mailbox: String?
        }
        
        struct EmailAddressRequest: Content {
            let email: String
            let name: String?
        }
        
        struct AttachmentRequest: Content {
            let filename: String
            let data: String  // base64
            let size: Int64
            let mime_type: String?
        }
        
        let request = try req.content.decode(EmailReceivedRequest.self)
        
        print("[Internal] Received email: \(request.message_id) - \(request.subject ?? "No subject")")
        
        // Converti in modello Email
        let sender = Contact(name: request.from.name, email: request.from.email)
        let recipients = request.to.map { Contact(name: $0.name, email: $0.email) }
        let cc = request.cc?.map { Contact(name: $0.name, email: $0.email) }
        
        // Converti allegati
        let emailAttachments: [EmailAttachment]? = request.attachments?.map {
            EmailAttachment(attachmentId: UUID().uuidString, filename: $0.filename, size: Int($0.size))
        }
        
        // Parse date
        let dateFormatter = ISO8601DateFormatter()
        let emailDate = dateFormatter.date(from: request.date) ?? Date()
        
        // Usa body_text o estrai testo da body_html
        let body = request.body_text ?? request.body_html?.stripHTML()
        
        let email = Email(
            id: request.message_id,
            isRead: false,
            sender: sender,
            recipients: recipients,
            cc: cc,
            subject: request.subject ?? "",
            date: emailDate,
            body: body,
            attachments: emailAttachments
        )
        
        // Processa con EmailProcessor
        let processor = EmailProcessor(db: DatabaseManager.shared, vaultManager: VaultManager.shared)
        let classified = try await processor.processEmail(email, accountId: request.account_id, mailboxId: request.mailbox)
        
        // Genera evento per ClaimEngine
        if let event = await processor.generateEvent(from: classified) {
            try await processor.saveEvent(event)
            
            // Notifica ClaimEngine (se disponibile)
            // await ClaimEngine.shared.processEvent(event)
        }
        
        // Salva allegati se presenti
        // Passa il sinistroRef dalla classificazione per salvare direttamente nel vault
        if let attachments = request.attachments {
            for att in attachments {
                let attachment = try await AttachmentManager.shared.createAttachment(
                    messageId: request.message_id,
                    sourceType: .email,
                    filename: att.filename,
                    size: att.size,
                    mimeType: att.mime_type,
                    sinistroRef: classified.sinistroId  // Passa sinistro se presente
                )
                
                // Se c'è data, salva il file
                // Se c'è sinistroRef, saveDownloadedData lo sposterà automaticamente nel vault
                if let data = Data(base64Encoded: att.data) {
                    _ = try await AttachmentManager.shared.saveDownloadedData(
                        attachment.id,
                        data: data
                    )
                }
            }
        }
        
        return EmailProcessedResponse(
            messageId: request.message_id,
            category: classified.category.rawValue,
            sinistroRef: classified.sinistroId,
            confidence: classified.confidence
        )
    }
    
    // Lista email programmate pending (pronte per invio)
    internalRoutes.get("email", "scheduled", "pending") { req async throws -> [ScheduledEmailDTO] in
        let db = try await DatabaseManager.shared.db()
        let now = Date().timeIntervalSince1970
        
        // Query: status == "pending" AND scheduledAt <= now
        let query = DatabaseSchema.scheduledEmails
            .filter(DatabaseSchema.ScheduledEmailsColumns.status == "pending")
            .filter(DatabaseSchema.ScheduledEmailsColumns.scheduledAt <= now)
            .order(DatabaseSchema.ScheduledEmailsColumns.scheduledAt.asc)
            .limit(20)
        
        var scheduled: [ScheduledEmailDTO] = []
        for row in try db.prepare(query) {
            let dto = ScheduledEmailDTO(
                id: row[DatabaseSchema.ScheduledEmailsColumns.id],
                accountId: row[DatabaseSchema.ScheduledEmailsColumns.accountId],
                to: row[DatabaseSchema.ScheduledEmailsColumns.toAddresses].components(separatedBy: ","),
                cc: row[DatabaseSchema.ScheduledEmailsColumns.ccAddresses]?.components(separatedBy: ","),
                subject: row[DatabaseSchema.ScheduledEmailsColumns.subject],
                body: row[DatabaseSchema.ScheduledEmailsColumns.body],
                scheduledAt: Date(timeIntervalSince1970: row[DatabaseSchema.ScheduledEmailsColumns.scheduledAt]),
                status: row[DatabaseSchema.ScheduledEmailsColumns.status]
            )
            scheduled.append(dto)
        }
        
        print("[Internal] Found \(scheduled.count) scheduled emails ready to send")
        return scheduled
    }
    
    // Marca email programmata come inviata
    internalRoutes.post("email", "scheduled", ":id", "sent") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing id")
        }
        
        struct SentRequest: Content {
            let messageId: String
        }
        
        let request = try req.content.decode(SentRequest.self)
        
        let db = try await DatabaseManager.shared.db()
        let now = Date().timeIntervalSince1970
        
        try db.run(
            DatabaseSchema.scheduledEmails
                .filter(DatabaseSchema.ScheduledEmailsColumns.id == id)
                .update(
                    DatabaseSchema.ScheduledEmailsColumns.status <- "sent",
                    DatabaseSchema.ScheduledEmailsColumns.sentAt <- now
                )
        )
        
        print("[Internal] ✅ Scheduled email sent: \(id) -> messageId: \(request.messageId)")
        
        // Notifica i client connessi via CrossUserNotificationService
        await CrossUserNotificationService.shared.notifyScheduledEmailSent(
            scheduledId: id,
            sentMessageId: request.messageId
        )
        
        return .ok
    }
    
    // Marca email programmata come fallita
    internalRoutes.post("email", "scheduled", ":id", "failed") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing id")
        }
        
        struct FailedRequest: Content {
            let error: String
        }
        
        let request = try req.content.decode(FailedRequest.self)
        
        let db = try await DatabaseManager.shared.db()
        
        try db.run(
            DatabaseSchema.scheduledEmails
                .filter(DatabaseSchema.ScheduledEmailsColumns.id == id)
                .update(
                    DatabaseSchema.ScheduledEmailsColumns.status <- "failed",
                    DatabaseSchema.ScheduledEmailsColumns.errorMessage <- request.error
                )
        )
        
        print("[Internal] ❌ Scheduled email failed: \(id) - \(request.error)")
        
        // Notifica i client connessi
        await CrossUserNotificationService.shared.notifyScheduledEmailFailed(
            scheduledId: id,
            error: request.error
        )
        
        return .ok
    }
    
    // MARK: - WhatsApp Internal Routes (from WA Bridge)
    
    // Riceve QR code dal WA Bridge
    internalRoutes.post("whatsapp", ":accountId", "qr") { req async throws -> HTTPStatus in
        guard let accountId = req.parameters.get("accountId") else {
            throw Abort(.badRequest, reason: "Missing accountId")
        }
        
        struct QRRequest: Content {
            let qr: String
        }
        
        let request = try req.content.decode(QRRequest.self)
        await WhatsAppQRStorage.shared.setQRCode(for: accountId, qr: request.qr)
        
        print("[Hub] Received WhatsApp QR code for \(accountId)")
        return .ok
    }
    
    // Riceve status update dal WA Bridge
    internalRoutes.post("whatsapp", ":accountId", "status") { req async throws -> HTTPStatus in
        guard let accountId = req.parameters.get("accountId") else {
            throw Abort(.badRequest, reason: "Missing accountId")
        }
        
        struct StatusRequest: Content {
            let status: String
            let reason: String?
        }
        
        let request = try req.content.decode(StatusRequest.self)
        await WhatsAppQRStorage.shared.setStatus(for: accountId, status: request.status)
        
        print("[Hub] WhatsApp status for \(accountId): \(request.status)")
        return .ok
    }
    
    // Riceve messaggio WhatsApp dal WA Bridge
    internalRoutes.post("whatsapp", "message") { req async throws -> HTTPStatus in
        struct IncomingWhatsAppMessage: Content {
            let accountId: String
            let messageId: String
            let from: String
            let to: String
            let body: String?
            let timestamp: Int?
            let type: String?
            let hasMedia: Bool?
            let isGroup: Bool?
            let author: String?
            let media: IncomingMedia?
            let isOutgoing: Bool?
        }
        
        struct IncomingMedia: Content {
            let mimetype: String
            let data: String
            let filename: String?
        }
        
        let message = try req.content.decode(IncomingWhatsAppMessage.self)
        let db = try await DatabaseManager.shared.db()
        
        // Determina chatId e direction
        let isOutgoing = message.isOutgoing ?? false
        let chatId = isOutgoing ? message.to : message.from  // Per messaggi in uscita, il chatId è il destinatario
        let direction = isOutgoing ? "out" : "in"
        
        // Genera ID univoco
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970
        
        // Estrai sinistro ref dal body (pattern 7 cifre)
        var sinistroRef: String? = nil
        if let body = message.body {
            let pattern = #"\b(\d{7})\b"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let range = Range(match.range(at: 1), in: body) {
                sinistroRef = String(body[range])
            }
        }
        
        // Salva messaggio
        try db.run(DatabaseSchema.whatsappMessages.insert(
            DatabaseSchema.WhatsAppMessagesColumns.id <- id,
            DatabaseSchema.WhatsAppMessagesColumns.accountId <- message.accountId,
            DatabaseSchema.WhatsAppMessagesColumns.chatId <- chatId,
            DatabaseSchema.WhatsAppMessagesColumns.waMessageId <- message.messageId,
            DatabaseSchema.WhatsAppMessagesColumns.fromNumber <- message.from,
            DatabaseSchema.WhatsAppMessagesColumns.toNumber <- message.to,
            DatabaseSchema.WhatsAppMessagesColumns.body <- message.body,
            DatabaseSchema.WhatsAppMessagesColumns.timestamp <- Double(message.timestamp ?? Int(now)),
            DatabaseSchema.WhatsAppMessagesColumns.direction <- direction,
            DatabaseSchema.WhatsAppMessagesColumns.type <- (message.type ?? "chat"),
            DatabaseSchema.WhatsAppMessagesColumns.mediaType <- message.media?.mimetype,
            DatabaseSchema.WhatsAppMessagesColumns.mediaFilename <- message.media?.filename,
            DatabaseSchema.WhatsAppMessagesColumns.mediaData <- message.media?.data,
            DatabaseSchema.WhatsAppMessagesColumns.isRead <- false,
            DatabaseSchema.WhatsAppMessagesColumns.sinistroRef <- sinistroRef,
            DatabaseSchema.WhatsAppMessagesColumns.createdAt <- now
        ))
        
        // Upsert chat
        let isGroup = message.isGroup ?? false
        let chatName = isGroup ? (message.author ?? chatId) : chatId.replacingOccurrences(of: "@c.us", with: "")
        let chatIdDb = UUID().uuidString
        
        // Prova a fare update, se non esiste inserisce
        let existingChat = try db.pluck(
            DatabaseSchema.whatsappChats
                .filter(DatabaseSchema.WhatsAppChatsColumns.accountId == message.accountId)
                .filter(DatabaseSchema.WhatsAppChatsColumns.chatId == chatId)
        )
        
        if existingChat != nil {
            // Update - incrementa unread solo per messaggi in entrata
            if isOutgoing {
                try db.run(
                    DatabaseSchema.whatsappChats
                        .filter(DatabaseSchema.WhatsAppChatsColumns.accountId == message.accountId)
                        .filter(DatabaseSchema.WhatsAppChatsColumns.chatId == chatId)
                        .update(
                            DatabaseSchema.WhatsAppChatsColumns.lastMessageBody <- message.body,
                            DatabaseSchema.WhatsAppChatsColumns.lastMessageAt <- Double(message.timestamp ?? Int(now)),
                            DatabaseSchema.WhatsAppChatsColumns.updatedAt <- now
                        )
                )
            } else {
                try db.run(
                    DatabaseSchema.whatsappChats
                        .filter(DatabaseSchema.WhatsAppChatsColumns.accountId == message.accountId)
                        .filter(DatabaseSchema.WhatsAppChatsColumns.chatId == chatId)
                        .update(
                            DatabaseSchema.WhatsAppChatsColumns.lastMessageBody <- message.body,
                            DatabaseSchema.WhatsAppChatsColumns.lastMessageAt <- Double(message.timestamp ?? Int(now)),
                            DatabaseSchema.WhatsAppChatsColumns.unreadCount <- DatabaseSchema.WhatsAppChatsColumns.unreadCount + 1,
                            DatabaseSchema.WhatsAppChatsColumns.updatedAt <- now
                        )
                )
            }
        } else {
            // Insert - unread 0 per messaggi in uscita, 1 per messaggi in entrata
            try db.run(DatabaseSchema.whatsappChats.insert(
                DatabaseSchema.WhatsAppChatsColumns.id <- chatIdDb,
                DatabaseSchema.WhatsAppChatsColumns.accountId <- message.accountId,
                DatabaseSchema.WhatsAppChatsColumns.chatId <- chatId,
                DatabaseSchema.WhatsAppChatsColumns.name <- chatName,
                DatabaseSchema.WhatsAppChatsColumns.phoneNumber <- chatId.replacingOccurrences(of: "@c.us", with: ""),
                DatabaseSchema.WhatsAppChatsColumns.isGroup <- isGroup,
                DatabaseSchema.WhatsAppChatsColumns.lastMessageBody <- message.body,
                DatabaseSchema.WhatsAppChatsColumns.lastMessageAt <- Double(message.timestamp ?? Int(now)),
                DatabaseSchema.WhatsAppChatsColumns.unreadCount <- (isOutgoing ? 0 : 1),
                DatabaseSchema.WhatsAppChatsColumns.sinistroRef <- sinistroRef,
                DatabaseSchema.WhatsAppChatsColumns.createdAt <- now,
                DatabaseSchema.WhatsAppChatsColumns.updatedAt <- now
            ))
        }
        
        let directionEmoji = isOutgoing ? "📤" : "📨"
        print("[Hub] \(directionEmoji) WhatsApp \(direction) from \(message.from) to \(message.to): \(message.body?.prefix(50) ?? "media")")
        
        // Se il messaggio ha un sinistroRef, aggiungilo al diario come conversazione
        if let sinistroRef = sinistroRef, !sinistroRef.isEmpty {
            Task {
                await WhatsAppDiarioService.shared.processMessage(
                    sinistroRef: sinistroRef,
                    chatId: chatId,
                    messageBody: message.body,
                    direction: direction,
                    timestamp: Date(timeIntervalSince1970: Double(message.timestamp ?? Int(now))),
                    fromNumber: message.from,
                    toNumber: message.to
                )
            }
        }
        
        return .ok
    }
    
    // Riceve ACK (read receipts) dal WA Bridge
    internalRoutes.post("whatsapp", "message-ack") { req async throws -> HTTPStatus in
        struct MessageAck: Content {
            let accountId: String
            let messageId: String
            let ack: Int
            let ackName: String
            let timestamp: Double?
        }
        
        let ackData = try req.content.decode(MessageAck.self)
        let db = try await DatabaseManager.shared.db()
        
        // Aggiorna lo stato ACK del messaggio
        // ack: -1=error, 0=pending, 1=sent, 2=delivered, 3=read, 4=played
        let updated = try db.run(
            DatabaseSchema.whatsappMessages
                .filter(DatabaseSchema.WhatsAppMessagesColumns.waMessageId == ackData.messageId)
                .update(
                    DatabaseSchema.WhatsAppMessagesColumns.ackStatus <- ackData.ack,
                    DatabaseSchema.WhatsAppMessagesColumns.ackTimestamp <- ackData.timestamp
                )
        )
        
        if updated > 0 {
            print("[Hub] 📬 ACK \(ackData.ackName) for message \(ackData.messageId)")
        }
        
        return .ok
    }
    
    // MARK: - Scheduled WhatsApp Routes
    
    // Lista messaggi WhatsApp programmati pending (pronte per invio)
    internalRoutes.get("whatsapp", "scheduled", "pending") { req async throws -> [ScheduledWhatsAppDTO] in
        let db = try await DatabaseManager.shared.db()
        let now = Date().timeIntervalSince1970
        
        let query = DatabaseSchema.scheduledWhatsApp
            .filter(DatabaseSchema.ScheduledWhatsAppColumns.status == "pending")
            .filter(DatabaseSchema.ScheduledWhatsAppColumns.scheduledAt <= now)
            .order(DatabaseSchema.ScheduledWhatsAppColumns.scheduledAt.asc)
            .limit(20)
        
        var scheduled: [ScheduledWhatsAppDTO] = []
        for row in try db.prepare(query) {
            let dto = ScheduledWhatsAppDTO(
                id: row[DatabaseSchema.ScheduledWhatsAppColumns.id],
                accountId: row[DatabaseSchema.ScheduledWhatsAppColumns.accountId],
                phoneNumber: row[DatabaseSchema.ScheduledWhatsAppColumns.phoneNumber],
                body: row[DatabaseSchema.ScheduledWhatsAppColumns.body],
                mediaData: row[DatabaseSchema.ScheduledWhatsAppColumns.mediaData],
                mediaType: row[DatabaseSchema.ScheduledWhatsAppColumns.mediaType],
                mediaFilename: row[DatabaseSchema.ScheduledWhatsAppColumns.mediaFilename],
                scheduledAt: Date(timeIntervalSince1970: row[DatabaseSchema.ScheduledWhatsAppColumns.scheduledAt]),
                status: row[DatabaseSchema.ScheduledWhatsAppColumns.status],
                sinistroRef: row[DatabaseSchema.ScheduledWhatsAppColumns.sinistroRef]
            )
            scheduled.append(dto)
        }
        
        print("[Internal] Found \(scheduled.count) scheduled WhatsApp messages ready to send")
        
        // Chiudi conversazioni WhatsApp scadute (ogni chiamata = ogni 30s circa)
        Task {
            await WhatsAppDiarioService.shared.closeExpiredConversations()
        }
        
        return scheduled
    }
    
    // Marca messaggio WhatsApp programmato come inviato
    internalRoutes.post("whatsapp", "scheduled", ":id", "sent") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing id")
        }
        
        struct SentRequest: Content {
            let messageId: String
        }
        
        let request = try req.content.decode(SentRequest.self)
        
        let db = try await DatabaseManager.shared.db()
        let now = Date().timeIntervalSince1970
        
        try db.run(
            DatabaseSchema.scheduledWhatsApp
                .filter(DatabaseSchema.ScheduledWhatsAppColumns.id == id)
                .update(
                    DatabaseSchema.ScheduledWhatsAppColumns.status <- "sent",
                    DatabaseSchema.ScheduledWhatsAppColumns.sentAt <- now,
                    DatabaseSchema.ScheduledWhatsAppColumns.sentMessageId <- request.messageId
                )
        )
        
        print("[Internal] ✅ Scheduled WhatsApp sent: \(id) -> messageId: \(request.messageId)")
        
        await CrossUserNotificationService.shared.notifyScheduledWhatsAppSent(
            scheduledId: id,
            sentMessageId: request.messageId
        )
        
        return .ok
    }
    
    // Marca messaggio WhatsApp programmato come fallito
    internalRoutes.post("whatsapp", "scheduled", ":id", "failed") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing id")
        }
        
        struct FailedRequest: Content {
            let error: String
        }
        
        let request = try req.content.decode(FailedRequest.self)
        
        let db = try await DatabaseManager.shared.db()
        
        try db.run(
            DatabaseSchema.scheduledWhatsApp
                .filter(DatabaseSchema.ScheduledWhatsAppColumns.id == id)
                .update(
                    DatabaseSchema.ScheduledWhatsAppColumns.status <- "failed",
                    DatabaseSchema.ScheduledWhatsAppColumns.errorMessage <- request.error
                )
        )
        
        print("[Internal] ❌ Scheduled WhatsApp failed: \(id) - \(request.error)")
        
        await CrossUserNotificationService.shared.notifyScheduledWhatsAppFailed(
            scheduledId: id,
            error: request.error
        )
        
        return .ok
    }
    
    // MARK: - Events Polling (per notifiche client real-time)
    
    internalRoutes.get("events") { req async throws -> [BroadcastEventDTO] in
        // Timestamp da cui iniziare a cercare eventi
        let sinceTimestamp = req.query[Double.self, at: "since"] ?? (Date().timeIntervalSince1970 - 60)
        let since = Date(timeIntervalSince1970: sinceTimestamp)
        
        let events = await EventBroadcaster.shared.getEventsSince(since)
        
        return events.map { event in
            BroadcastEventDTO(
                id: event.id,
                type: event.type,
                payload: event.payload,
                timestamp: event.timestamp
            )
        }
    }
    
    // MARK: - AutoUpdater Routes (per notifiche aggiornamenti)
    
    // Stato degli aggiornamenti pendenti (in-memory per semplicità)
    struct PendingUpdate: Content {
        let component: String
        var changedFiles: [String]
        var timestamp: Date
    }
    
    // Riceve notifica di aggiornamento dal worker AutoUpdater
    internalRoutes.post("updates", "notify") { req async throws -> HTTPStatus in
        struct UpdateNotifyRequest: Content {
            let component: String
            let changed_files: [String]
            let timestamp: String
        }
        
        let request = try req.content.decode(UpdateNotifyRequest.self)
        
        // Salva in memoria (UpdatesManager è un actor globale)
        await UpdatesManager.shared.recordUpdate(
            component: request.component,
            changedFiles: request.changed_files
        )
        
        print("[Updates] 🔄 Update notified for \(request.component): \(request.changed_files.count) files")
        
        // Se è sync_agent (remoto), crea job per trasferire i file
        if request.component == "perx_sync_agent" {
            // Crea job per sincronizzare i file aggiornati verso Windows
            _ = try await JobService.shared.createUpdateSyncAgentJob(
                changedFiles: request.changed_files
            )
            print("[Updates] Created sync job for sync_agent files")
        }
        
        return .ok
    }
    
    // Restituisce aggiornamenti pendenti (per Monitor)
    internalRoutes.get("updates") { req async throws -> [String: [String]] in
        return await UpdatesManager.shared.getPendingUpdates()
    }
    
    // Conferma che un aggiornamento è stato applicato
    internalRoutes.post("updates", "ack") { req async throws -> HTTPStatus in
        struct AckRequest: Content {
            let component: String
        }
        
        let request = try req.content.decode(AckRequest.self)
        
        await UpdatesManager.shared.acknowledgeUpdate(component: request.component)
        
        print("[Updates] ✅ Update acknowledged for \(request.component)")
        return .ok
    }
    
    // Scarica file di aggiornamento (per SyncAgent)
    internalRoutes.get("updates", "file") { req async throws -> Response in
        guard let filePath = req.query[String.self, at: "path"] else {
            throw Abort(.badRequest, reason: "Missing path parameter")
        }
        
        let repoBase = HubConfiguration.repoBasePath
        let fullPath = "\(repoBase)/perx_sync_agent/\(filePath)"
        
        guard FileManager.default.fileExists(atPath: fullPath) else {
            throw Abort(.notFound, reason: "File not found")
        }
        
        guard let data = FileManager.default.contents(atPath: fullPath) else {
            throw Abort(.internalServerError, reason: "Cannot read file")
        }
        
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/octet-stream")
        headers.add(name: .contentDisposition, value: "attachment; filename=\"\(URL(fileURLWithPath: fullPath).lastPathComponent)\"")
        
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }
    
    // Notifica che SyncAgent ha ricevuto i file (pronto per restart)
    internalRoutes.post("updates", "sync-agent-ready") { req async throws -> HTTPStatus in
        struct SyncAgentReadyRequest: Content {
            let files_updated: Int
        }
        
        let request = try req.content.decode(SyncAgentReadyRequest.self)
        
        await UpdatesManager.shared.markSyncAgentFilesTransferred()
        
        print("[Updates] ✅ SyncAgent received \(request.files_updated) files, ready for restart")
        return .ok
    }
    
    // MARK: - Attachment Routes
    
    let attachments = app.grouped("attachments")
    
    // Lista allegati per messaggio
    attachments.get("message", ":messageId") { req async throws -> [AttachmentDTO] in
        guard let messageId = req.parameters.get("messageId") else {
            throw Abort(.badRequest, reason: "Missing messageId")
        }
        
        let list = try await AttachmentManager.shared.getAttachments(messageId: messageId)
        return list.map { AttachmentDTO(from: $0) }
    }
    
    // Allegati pending
    attachments.get("pending") { req async throws -> [AttachmentDTO] in
        let limit = req.query[Int.self, at: "limit"] ?? 50
        let list = try await AttachmentManager.shared.getAllPendingAttachments(limit: limit)
        return list.map { AttachmentDTO(from: $0) }
    }
    
    // Allegati non associati
    attachments.get("unassociated") { req async throws -> [AttachmentDTO] in
        let limit = req.query[Int.self, at: "limit"] ?? 50
        let list = try await AttachmentManager.shared.getUnassociatedAttachments(limit: limit)
        return list.map { AttachmentDTO(from: $0) }
    }
    
    // Associa allegato a sinistro
    attachments.post(":id", "associate") { req async throws -> AttachmentDTO in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing attachment id")
        }
        
        struct AssociateRequest: Content {
            let sinistroRef: String
        }
        
        let request = try req.content.decode(AssociateRequest.self)
        let attachment = try await AttachmentManager.shared.associateToSinistro(id, sinistroRef: request.sinistroRef)
        return AttachmentDTO(from: attachment)
    }
    
    // Aggiorna stato allegato
    attachments.post(":id", "status") { req async throws -> AttachmentDTO in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing attachment id")
        }
        
        struct StatusRequest: Content {
            let status: String
            let errorMessage: String?
        }
        
        let request = try req.content.decode(StatusRequest.self)
        guard let status = AttachmentStatus(rawValue: request.status) else {
            throw Abort(.badRequest, reason: "Invalid status")
        }
        
        let attachment = try await AttachmentManager.shared.updateStatus(id, status: status, errorMessage: request.errorMessage)
        return AttachmentDTO(from: attachment)
    }
    
    // MARK: - Sinistri Routes (Client API)
    
    let sinistri = app.grouped("sinistri")
    
    // Lista sinistri per utente (user = username, email opzionale per retrocompat)
    sinistri.get { req async throws -> [SinistroDTO] in
        guard let user = req.query[String.self, at: "user"] else {
            throw Abort(.badRequest, reason: "Missing user")
        }
        let email = req.query[String.self, at: "email"]
        return try await CloudKitWebService.shared.fetchSinistri(forUser: user, fallbackEmail: email)
    }
    
    // Dettaglio sinistro (fetch per riferimento)
    sinistri.get(":ref") { req async throws -> SinistroDTO in
        guard let ref = req.parameters.get("ref") else {
            throw Abort(.badRequest, reason: "Missing sinistro ref")
        }
        guard let sinistro = try await CloudKitWebService.shared.fetchSinistro(riferimento: ref) else {
            throw Abort(.notFound, reason: "Sinistro not found")
        }
        return sinistro
    }
    
    // Cambia stato sinistro
    sinistri.post(":ref", "stato") { req async throws -> StateChangeResponse in
        guard let ref = req.parameters.get("ref") else {
            throw Abort(.badRequest, reason: "Missing sinistro ref")
        }
        
        let request = try req.content.decode(StateChangeRequest.self)
        
        // Usa HubStatoManager per validare e cambiare stato
        let newState = request.newState ?? .daScaricare
        try await HubStatoManager.shared.changeState(
            sinistroRef: ref,
            to: newState,
            reason: request.reason,
            userEmail: request.userEmail
        )
        
        return StateChangeResponse(
            success: true,
            sinistroRef: ref,
            oldState: "", // TODO: recuperare da DB
            newState: request.newStateId
        )
    }
    
    // MARK: - Email Routes (Client API)
    
    let emails = app.grouped("emails")
    
    // Lista email per sinistro (con mailbox)
    emails.get("sinistro", ":ref") { req async throws -> [EmailDTO] in
        guard let ref = req.parameters.get("ref") else {
            throw Abort(.badRequest, reason: "Missing sinistro ref")
        }
        
        let db = try await DatabaseManager.shared.db()
        let emailRows = try db.prepare(
            DatabaseSchema.emails.filter(DatabaseSchema.EmailsColumns.sinistroRef == ref)
        )
        
        // Raccogli tutti i messageId per fare lookup delle mailbox
        var emails: [(messageId: String, subject: String, senderEmail: String, senderName: String?, date: Date, category: String, sinistroRef: String?, direction: String, accountId: String)] = []
        for row in emailRows {
            emails.append((
                messageId: row[DatabaseSchema.EmailsColumns.messageId],
                subject: row[DatabaseSchema.EmailsColumns.subject] ?? "",
                senderEmail: row[DatabaseSchema.EmailsColumns.senderEmail],
                senderName: row[DatabaseSchema.EmailsColumns.senderName],
                date: Date(timeIntervalSince1970: row[DatabaseSchema.EmailsColumns.date]),
                category: row[DatabaseSchema.EmailsColumns.category] ?? "generic",
                sinistroRef: row[DatabaseSchema.EmailsColumns.sinistroRef],
                direction: row[DatabaseSchema.EmailsColumns.direction],
                accountId: row[DatabaseSchema.EmailsColumns.accountId]
            ))
        }
        
        // Recupera le mailbox dalla tabella email_accounts
        var mailboxByKey: [String: String] = [:]
        let messageIds = emails.map { $0.messageId }
        if !messageIds.isEmpty {
            let accountRows = try db.prepare(
                DatabaseSchema.emailAccounts.filter(messageIds.contains(DatabaseSchema.EmailAccountsColumns.messageId))
            )
            for row in accountRows {
                let key = "\(row[DatabaseSchema.EmailAccountsColumns.messageId])_\(row[DatabaseSchema.EmailAccountsColumns.accountId])"
                if let mailbox = row[DatabaseSchema.EmailAccountsColumns.mailbox] {
                    mailboxByKey[key] = mailbox
                }
            }
        }
        
        return emails.map { email -> EmailDTO in
            let key = "\(email.messageId)_\(email.accountId)"
            let mailbox = mailboxByKey[key] ?? (email.direction == "OUT" ? "SENT" : "INBOX")
            
            return EmailDTO(
                id: email.messageId,
                subject: email.subject,
                senderEmail: email.senderEmail,
                senderName: email.senderName,
                date: email.date,
                category: email.category,
                sinistroRef: email.sinistroRef,
                direction: email.direction,
                mailbox: mailbox
            )
        }
    }
    
    // Lista email per utente (con mailbox)
    emails.get { req async throws -> [EmailDTO] in
        guard let userEmail = req.query[String.self, at: "user"] else {
            throw Abort(.badRequest, reason: "Missing user (email per accountId)")
        }
        let limit = req.query[Int.self, at: "limit"] ?? 100
        
        // Supporta sia email completa che solo accountId (parte locale)
        let accountId: String
        if userEmail.contains("@") {
            // Estrai la parte locale dell'email
            accountId = userEmail.lowercased().components(separatedBy: "@").first ?? userEmail.lowercased()
        } else {
            accountId = userEmail.lowercased()
        }

        let db = try await DatabaseManager.shared.db()
        
        // Prima recupera le email
        let emailRows = try db.prepare(
            DatabaseSchema.emails
                .filter(DatabaseSchema.EmailsColumns.accountId == accountId)
                .order(DatabaseSchema.EmailsColumns.date.desc)
                .limit(limit)
        )
        
        // Poi recupera le mailbox dalla tabella email_accounts
        var mailboxByMessageId: [String: String] = [:]
        let accountRows = try db.prepare(
            DatabaseSchema.emailAccounts
                .filter(DatabaseSchema.EmailAccountsColumns.accountId == accountId)
        )
        for row in accountRows {
            let messageId = row[DatabaseSchema.EmailAccountsColumns.messageId]
            if let mailbox = row[DatabaseSchema.EmailAccountsColumns.mailbox] {
                mailboxByMessageId[messageId] = mailbox
            }
        }
        
        return emailRows.map { row -> EmailDTO in
            let messageId = row[DatabaseSchema.EmailsColumns.messageId]
            let direction = row[DatabaseSchema.EmailsColumns.direction]
            // Usa la mailbox se disponibile, altrimenti inferisci dalla direction
            let mailbox = mailboxByMessageId[messageId] ?? (direction == "OUT" ? "SENT" : "INBOX")
            
            return EmailDTO(
                id: messageId,
                subject: row[DatabaseSchema.EmailsColumns.subject] ?? "",
                senderEmail: row[DatabaseSchema.EmailsColumns.senderEmail],
                senderName: row[DatabaseSchema.EmailsColumns.senderName],
                date: Date(timeIntervalSince1970: row[DatabaseSchema.EmailsColumns.date]),
                category: row[DatabaseSchema.EmailsColumns.category] ?? "generic",
                sinistroRef: row[DatabaseSchema.EmailsColumns.sinistroRef],
                direction: direction,
                mailbox: mailbox
            )
        }
    }
    
    // Dettaglio email - TODO: fix ambiguity issue
    // emails.get("detail", ":id") returns email detail
    // Disabled temporarily due to type inference issues
    
    // Lista caselle disponibili per utente
    emails.get("mailboxes") { req async throws -> [MailboxDTO] in
        guard let userEmail = req.query[String.self, at: "user"] else {
            throw Abort(.badRequest, reason: "Missing user (email per accountId)")
        }
        
        // Supporta sia email completa che solo accountId (parte locale)
        let accountId: String
        if userEmail.contains("@") {
            accountId = userEmail.lowercased().components(separatedBy: "@").first ?? userEmail.lowercased()
        } else {
            accountId = userEmail.lowercased()
        }
        
        let db = try await DatabaseManager.shared.db()
        
        // Recupera tutte le mailbox distinte per l'utente
        var mailboxCounts: [String: (total: Int, unread: Int)] = [:]
        
        let accountRows = try db.prepare(
            DatabaseSchema.emailAccounts.filter(DatabaseSchema.EmailAccountsColumns.accountId == accountId)
        )
        
        for row in accountRows {
            let mailbox = row[DatabaseSchema.EmailAccountsColumns.mailbox] ?? "INBOX"
            let isRead = row[DatabaseSchema.EmailAccountsColumns.isRead]
            
            var counts = mailboxCounts[mailbox] ?? (total: 0, unread: 0)
            counts.total += 1
            if !isRead {
                counts.unread += 1
            }
            mailboxCounts[mailbox] = counts
        }
        
        // Se non ci sono mailbox ma ci sono email, usa la tabella emails per inferire
        if mailboxCounts.isEmpty {
            let emailRows = try db.prepare(
                DatabaseSchema.emails.filter(DatabaseSchema.EmailsColumns.accountId == accountId)
            )
            
            for row in emailRows {
                let direction = row[DatabaseSchema.EmailsColumns.direction]
                let isRead = row[DatabaseSchema.EmailsColumns.isRead]
                let mailbox = direction == "OUT" ? "SENT" : "INBOX"
                
                var counts = mailboxCounts[mailbox] ?? (total: 0, unread: 0)
                counts.total += 1
                if !isRead {
                    counts.unread += 1
                }
                mailboxCounts[mailbox] = counts
            }
        }
        
        // Ordina per priorità: INBOX prima, poi SENT, poi altri alfabeticamente
        let orderedMailboxes = mailboxCounts.keys.sorted { a, b in
            if a == "INBOX" { return true }
            if b == "INBOX" { return false }
            if a == "SENT" { return true }
            if b == "SENT" { return false }
            return a < b
        }
        
        return orderedMailboxes.map { mailbox in
            let counts = mailboxCounts[mailbox]!
            return MailboxDTO(
                id: mailbox,
                name: mailbox,
                totalCount: counts.total,
                unreadCount: counts.unread
            )
        }
    }
    
    // Associa email a sinistro
    emails.post(":id", "associate") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing email id")
        }
        
        struct AssociateEmailRequest: Content {
            let sinistroRef: String
        }
        
        let request = try req.content.decode(AssociateEmailRequest.self)
        
        let db = try await DatabaseManager.shared.db()
        
        // Aggiorna sinistroRef nell'email
        try db.run(
            DatabaseSchema.emails
                .filter(DatabaseSchema.EmailsColumns.messageId == id)
                .update(DatabaseSchema.EmailsColumns.sinistroRef <- request.sinistroRef)
        )
        
        // Sposta allegati dal temp al vault del sinistro
        let attachments = try await AttachmentManager.shared.getAttachments(messageId: id)
        for attachment in attachments {
            // Solo se non già salvato nel vault
            if attachment.status == .downloaded || attachment.status == .pending {
                _ = try await AttachmentManager.shared.associateToSinistro(
                    attachment.id,
                    sinistroRef: request.sinistroRef
                )
            }
        }
        
        print("[Emails] Email \(id) associata a sinistro \(request.sinistroRef), \(attachments.count) allegati spostati")
        return .ok
    }
    
    // Marca email come letta - chiamato dal client iPad quando l'utente apre l'email
    emails.post(":id", "read") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing email id")
        }
        
        // Aggiorna stato locale in database Hub
        let db = try await DatabaseManager.shared.db()
        try db.run(
            DatabaseSchema.emails
                .filter(DatabaseSchema.EmailsColumns.messageId == id)
                .update(DatabaseSchema.EmailsColumns.isRead <- true)
        )
        
        // Forward al Mail Worker per marcare come letta su IMAP
        let workerURL = HubConfiguration.emailWorkerURL
        guard let url = URL(string: "\(workerURL)/email/mark-read") else {
            throw Abort(.internalServerError, reason: "Invalid worker URL")
        }
        
        struct MarkReadRequest: Codable {
            let message_id: String
        }
        
        var workerRequest = URLRequest(url: url)
        workerRequest.httpMethod = "POST"
        workerRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        workerRequest.httpBody = try JSONEncoder().encode(MarkReadRequest(message_id: id))
        workerRequest.timeoutInterval = 10
        
        do {
            let (_, response) = try await URLSession.shared.data(for: workerRequest)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("[Emails] ✅ Email \(id) marcata come letta su IMAP")
            } else {
                print("[Emails] ⚠️ Mail worker non ha marcato email \(id) come letta su IMAP")
            }
        } catch {
            // Non fallire se il worker non è raggiungibile, l'email è comunque marcata localmente
            print("[Emails] ⚠️ Impossibile contattare mail worker per marcare email \(id) come letta: \(error)")
        }
        
        return .ok
    }
    
    // Programma invio email
    emails.post("schedule") { req async throws -> ScheduledEmailDTO in
        struct ScheduleEmailRequest: Content {
            let accountId: String
            let to: [String]
            let cc: [String]?
            let subject: String
            let body: String
            let scheduledFor: Date
            let sinistroRef: String?
        }
        
        let request = try req.content.decode(ScheduleEmailRequest.self)
        
        let id = UUID().uuidString
        let db = try await DatabaseManager.shared.db()
        
        try db.run(DatabaseSchema.scheduledEmails.insert(
            DatabaseSchema.ScheduledEmailsColumns.id <- id,
            DatabaseSchema.ScheduledEmailsColumns.accountId <- request.accountId,
            DatabaseSchema.ScheduledEmailsColumns.toAddresses <- request.to.joined(separator: ","),
            DatabaseSchema.ScheduledEmailsColumns.ccAddresses <- request.cc?.joined(separator: ","),
            DatabaseSchema.ScheduledEmailsColumns.subject <- request.subject,
            DatabaseSchema.ScheduledEmailsColumns.body <- request.body,
            DatabaseSchema.ScheduledEmailsColumns.scheduledAt <- request.scheduledFor.timeIntervalSince1970,
            DatabaseSchema.ScheduledEmailsColumns.status <- "pending",
            DatabaseSchema.ScheduledEmailsColumns.createdAt <- Date().timeIntervalSince1970
        ))
        
        print("[Emails] Scheduled email \(id) for \(request.scheduledFor)")
        
        let scheduled = ScheduledEmail(
            id: id,
            accountId: request.accountId,
            to: request.to,
            cc: request.cc,
            subject: request.subject,
            body: request.body,
            attachmentIds: nil,
            scheduledAt: request.scheduledFor,
            status: .pending,
            sentAt: nil,
            errorMessage: nil,
            createdBy: nil,
            createdAt: Date()
        )
        
        return ScheduledEmailDTO(from: scheduled)
    }
    
    // Invio email immediato (forward al Mail Worker)
    emails.post("send") { req async throws -> SendEmailResponseDTO in
        struct SendEmailRequest: Content {
            let accountId: String
            let to: [String]
            let cc: [String]?
            let bcc: [String]?
            let subject: String
            let body: String
            let isHtml: Bool?
            let replyToThreadId: String?
            let inReplyTo: String?
            let references: String?
            let attachments: [[String: String]]?
        }
        
        let request = try req.content.decode(SendEmailRequest.self)
        
        // Forward al Mail Worker
        let workerURL = HubConfiguration.emailWorkerURL
        guard let url = URL(string: "\(workerURL)/email/send") else {
            throw Abort(.internalServerError, reason: "Invalid worker URL")
        }
        
        // Prepara payload per il worker
        var workerPayload: [String: Any] = [
            "account_id": request.accountId,
            "to": request.to,
            "subject": request.subject,
            "body": request.body,
            "is_html": request.isHtml ?? true
        ]
        
        if let cc = request.cc, !cc.isEmpty {
            workerPayload["cc"] = cc
        }
        if let bcc = request.bcc, !bcc.isEmpty {
            workerPayload["bcc"] = bcc
        }
        if let threadId = request.replyToThreadId {
            workerPayload["reply_to_thread_id"] = threadId
        }
        if let inReplyTo = request.inReplyTo {
            workerPayload["in_reply_to"] = inReplyTo
        }
        if let references = request.references {
            workerPayload["references"] = references
        }
        if let attachments = request.attachments {
            workerPayload["attachments"] = attachments
        }
        
        var workerRequest = URLRequest(url: url)
        workerRequest.httpMethod = "POST"
        workerRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        workerRequest.httpBody = try JSONSerialization.data(withJSONObject: workerPayload)
        workerRequest.timeoutInterval = 60
        
        let (data, response) = try await URLSession.shared.data(for: workerRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Abort(.internalServerError, reason: "Invalid worker response")
        }
        
        if httpResponse.statusCode == 200 {
            let workerResponse = try JSONDecoder().decode(SendEmailResponseDTO.self, from: data)
            print("[Emails] ✅ Email sent via worker: \(request.subject) -> \(request.to)")
            return workerResponse
        } else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[Emails] ❌ Email send failed: \(errorMessage)")
            return SendEmailResponseDTO(success: false, messageId: nil, error: errorMessage)
        }
    }
    
    // MARK: - WhatsApp Client Routes
    
    let whatsapp = app.grouped("whatsapp")
    
    // Programma invio messaggio WhatsApp
    whatsapp.post("schedule") { req async throws -> ScheduledWhatsAppDTO in
        struct ScheduleWhatsAppRequest: Content {
            let accountId: String
            let phoneNumber: String
            let body: String
            let mediaData: String?
            let mediaType: String?
            let mediaFilename: String?
            let scheduledFor: Date
            let sinistroRef: String?
            let createdBy: String?
        }
        
        let request = try req.content.decode(ScheduleWhatsAppRequest.self)
        
        let id = UUID().uuidString
        let db = try await DatabaseManager.shared.db()
        
        try db.run(DatabaseSchema.scheduledWhatsApp.insert(
            DatabaseSchema.ScheduledWhatsAppColumns.id <- id,
            DatabaseSchema.ScheduledWhatsAppColumns.accountId <- request.accountId,
            DatabaseSchema.ScheduledWhatsAppColumns.phoneNumber <- request.phoneNumber,
            DatabaseSchema.ScheduledWhatsAppColumns.body <- request.body,
            DatabaseSchema.ScheduledWhatsAppColumns.mediaData <- request.mediaData,
            DatabaseSchema.ScheduledWhatsAppColumns.mediaType <- request.mediaType,
            DatabaseSchema.ScheduledWhatsAppColumns.mediaFilename <- request.mediaFilename,
            DatabaseSchema.ScheduledWhatsAppColumns.scheduledAt <- request.scheduledFor.timeIntervalSince1970,
            DatabaseSchema.ScheduledWhatsAppColumns.status <- "pending",
            DatabaseSchema.ScheduledWhatsAppColumns.sinistroRef <- request.sinistroRef,
            DatabaseSchema.ScheduledWhatsAppColumns.createdBy <- request.createdBy,
            DatabaseSchema.ScheduledWhatsAppColumns.createdAt <- Date().timeIntervalSince1970
        ))
        
        print("[WhatsApp] Scheduled message \(id) for \(request.scheduledFor) to \(request.phoneNumber)")
        
        return ScheduledWhatsAppDTO(
            id: id,
            accountId: request.accountId,
            phoneNumber: request.phoneNumber,
            body: request.body,
            mediaData: request.mediaData,
            mediaType: request.mediaType,
            mediaFilename: request.mediaFilename,
            scheduledAt: request.scheduledFor,
            status: "pending",
            sinistroRef: request.sinistroRef
        )
    }
    
    // Lista messaggi programmati per utente
    whatsapp.get("scheduled") { req async throws -> [ScheduledWhatsAppDTO] in
        guard let accountId = req.query[String.self, at: "accountId"] else {
            throw Abort(.badRequest, reason: "Missing accountId")
        }
        
        let db = try await DatabaseManager.shared.db()
        let query = DatabaseSchema.scheduledWhatsApp
            .filter(DatabaseSchema.ScheduledWhatsAppColumns.accountId == accountId)
            .order(DatabaseSchema.ScheduledWhatsAppColumns.scheduledAt.desc)
            .limit(50)
        
        var scheduled: [ScheduledWhatsAppDTO] = []
        for row in try db.prepare(query) {
            let dto = ScheduledWhatsAppDTO(
                id: row[DatabaseSchema.ScheduledWhatsAppColumns.id],
                accountId: row[DatabaseSchema.ScheduledWhatsAppColumns.accountId],
                phoneNumber: row[DatabaseSchema.ScheduledWhatsAppColumns.phoneNumber],
                body: row[DatabaseSchema.ScheduledWhatsAppColumns.body],
                mediaData: row[DatabaseSchema.ScheduledWhatsAppColumns.mediaData],
                mediaType: row[DatabaseSchema.ScheduledWhatsAppColumns.mediaType],
                mediaFilename: row[DatabaseSchema.ScheduledWhatsAppColumns.mediaFilename],
                scheduledAt: Date(timeIntervalSince1970: row[DatabaseSchema.ScheduledWhatsAppColumns.scheduledAt]),
                status: row[DatabaseSchema.ScheduledWhatsAppColumns.status],
                sinistroRef: row[DatabaseSchema.ScheduledWhatsAppColumns.sinistroRef]
            )
            scheduled.append(dto)
        }
        
        return scheduled
    }
    
    // Cancella messaggio programmato (solo se ancora pending)
    whatsapp.delete("scheduled", ":id") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing id")
        }
        
        let db = try await DatabaseManager.shared.db()
        
        // Solo se status è pending
        let deleted = try db.run(
            DatabaseSchema.scheduledWhatsApp
                .filter(DatabaseSchema.ScheduledWhatsAppColumns.id == id)
                .filter(DatabaseSchema.ScheduledWhatsAppColumns.status == "pending")
                .delete()
        )
        
        if deleted > 0 {
            print("[WhatsApp] Cancelled scheduled message \(id)")
            return .ok
        } else {
            throw Abort(.conflict, reason: "Message already sent or not found")
        }
    }
    
    // MARK: - WhatsApp Messages & Chats
    
    // Lista chat per account
    whatsapp.get("chats") { req async throws -> [WhatsAppChatDTO] in
        guard let accountId = req.query[String.self, at: "accountId"] else {
            throw Abort(.badRequest, reason: "Missing accountId")
        }
        
        let db = try await DatabaseManager.shared.db()
        let query = DatabaseSchema.whatsappChats
            .filter(DatabaseSchema.WhatsAppChatsColumns.accountId == accountId)
            .order(DatabaseSchema.WhatsAppChatsColumns.lastMessageAt.desc)
            .limit(100)
        
        var chats: [WhatsAppChatDTO] = []
        for row in try db.prepare(query) {
            let dto = WhatsAppChatDTO(
                id: row[DatabaseSchema.WhatsAppChatsColumns.id],
                accountId: row[DatabaseSchema.WhatsAppChatsColumns.accountId],
                chatId: row[DatabaseSchema.WhatsAppChatsColumns.chatId],
                name: row[DatabaseSchema.WhatsAppChatsColumns.name],
                phoneNumber: row[DatabaseSchema.WhatsAppChatsColumns.phoneNumber],
                isGroup: row[DatabaseSchema.WhatsAppChatsColumns.isGroup],
                lastMessageBody: row[DatabaseSchema.WhatsAppChatsColumns.lastMessageBody],
                lastMessageAt: row[DatabaseSchema.WhatsAppChatsColumns.lastMessageAt].map { Date(timeIntervalSince1970: $0) },
                unreadCount: row[DatabaseSchema.WhatsAppChatsColumns.unreadCount],
                sinistroRef: row[DatabaseSchema.WhatsAppChatsColumns.sinistroRef]
            )
            chats.append(dto)
        }
        
        return chats
    }
    
    // Messaggi per chat
    whatsapp.get("messages") { req async throws -> [WhatsAppMessageDTO] in
        guard let accountId = req.query[String.self, at: "accountId"] else {
            throw Abort(.badRequest, reason: "Missing accountId")
        }
        
        let chatId = req.query[String.self, at: "chatId"]
        let sinistroRef = req.query[String.self, at: "sinistroRef"]
        let limit = req.query[Int.self, at: "limit"] ?? 100
        
        let db = try await DatabaseManager.shared.db()
        
        var query = DatabaseSchema.whatsappMessages
            .filter(DatabaseSchema.WhatsAppMessagesColumns.accountId == accountId)
        
        if let chatId = chatId {
            query = query.filter(DatabaseSchema.WhatsAppMessagesColumns.chatId == chatId)
        }
        
        if let sinistroRef = sinistroRef {
            query = query.filter(DatabaseSchema.WhatsAppMessagesColumns.sinistroRef == sinistroRef)
        }
        
        query = query.order(DatabaseSchema.WhatsAppMessagesColumns.timestamp.desc).limit(limit)
        
        var messages: [WhatsAppMessageDTO] = []
        for row in try db.prepare(query) {
            let dto = WhatsAppMessageDTO(
                id: row[DatabaseSchema.WhatsAppMessagesColumns.id],
                accountId: row[DatabaseSchema.WhatsAppMessagesColumns.accountId],
                chatId: row[DatabaseSchema.WhatsAppMessagesColumns.chatId],
                waMessageId: row[DatabaseSchema.WhatsAppMessagesColumns.waMessageId],
                fromNumber: row[DatabaseSchema.WhatsAppMessagesColumns.fromNumber],
                toNumber: row[DatabaseSchema.WhatsAppMessagesColumns.toNumber],
                body: row[DatabaseSchema.WhatsAppMessagesColumns.body],
                timestamp: Date(timeIntervalSince1970: row[DatabaseSchema.WhatsAppMessagesColumns.timestamp]),
                direction: row[DatabaseSchema.WhatsAppMessagesColumns.direction],
                type: row[DatabaseSchema.WhatsAppMessagesColumns.type],
                mediaType: row[DatabaseSchema.WhatsAppMessagesColumns.mediaType],
                mediaFilename: row[DatabaseSchema.WhatsAppMessagesColumns.mediaFilename],
                hasMedia: row[DatabaseSchema.WhatsAppMessagesColumns.mediaData] != nil,
                isRead: row[DatabaseSchema.WhatsAppMessagesColumns.isRead],
                sinistroRef: row[DatabaseSchema.WhatsAppMessagesColumns.sinistroRef],
                ackStatus: row[DatabaseSchema.WhatsAppMessagesColumns.ackStatus],
                ackTimestamp: row[DatabaseSchema.WhatsAppMessagesColumns.ackTimestamp].map { Date(timeIntervalSince1970: $0) }
            )
            messages.append(dto)
        }
        
        // Ordina cronologicamente per la UI
        return messages.reversed()
    }
    
    // Download media WhatsApp
    whatsapp.get("media", ":accountId", ":messageId") { req async throws -> Response in
        guard let accountId = req.parameters.get("accountId"),
              let messageId = req.parameters.get("messageId") else {
            throw Abort(.badRequest, reason: "Missing parameters")
        }
        
        let db = try await DatabaseManager.shared.db()
        
        guard let row = try db.pluck(
            DatabaseSchema.whatsappMessages
                .filter(DatabaseSchema.WhatsAppMessagesColumns.accountId == accountId)
                .filter(DatabaseSchema.WhatsAppMessagesColumns.waMessageId == messageId)
        ) else {
            throw Abort(.notFound, reason: "Message not found")
        }
        
        guard let mediaData = row[DatabaseSchema.WhatsAppMessagesColumns.mediaData],
              let data = Data(base64Encoded: mediaData) else {
            throw Abort(.notFound, reason: "No media in message")
        }
        
        let mimeType = row[DatabaseSchema.WhatsAppMessagesColumns.mediaType] ?? "application/octet-stream"
        let filename = row[DatabaseSchema.WhatsAppMessagesColumns.mediaFilename] ?? "media"
        
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: mimeType)
        headers.add(name: .contentDisposition, value: "attachment; filename=\"\(filename)\"")
        
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }
    
    // Associa chat a sinistro
    whatsapp.post("chats", ":chatId", "associate") { req async throws -> HTTPStatus in
        guard let chatId = req.parameters.get("chatId") else {
            throw Abort(.badRequest, reason: "Missing chatId")
        }
        
        struct AssociateRequest: Content {
            let sinistroRef: String
        }
        
        let request = try req.content.decode(AssociateRequest.self)
        let db = try await DatabaseManager.shared.db()
        
        try db.run(
            DatabaseSchema.whatsappChats
                .filter(DatabaseSchema.WhatsAppChatsColumns.chatId == chatId)
                .update(DatabaseSchema.WhatsAppChatsColumns.sinistroRef <- request.sinistroRef)
        )
        
        // Aggiorna anche i messaggi non associati di questa chat
        try db.run(
            DatabaseSchema.whatsappMessages
                .filter(DatabaseSchema.WhatsAppMessagesColumns.chatId == chatId)
                .filter(DatabaseSchema.WhatsAppMessagesColumns.sinistroRef == nil)
                .update(DatabaseSchema.WhatsAppMessagesColumns.sinistroRef <- request.sinistroRef)
        )
        
        print("[WhatsApp] Chat \(chatId) associata a sinistro \(request.sinistroRef)")
        return .ok
    }
    
    // Marca messaggi come letti
    whatsapp.post("chats", ":chatId", "read") { req async throws -> HTTPStatus in
        guard let chatId = req.parameters.get("chatId") else {
            throw Abort(.badRequest, reason: "Missing chatId")
        }
        
        let db = try await DatabaseManager.shared.db()
        
        // Marca messaggi come letti
        try db.run(
            DatabaseSchema.whatsappMessages
                .filter(DatabaseSchema.WhatsAppMessagesColumns.chatId == chatId)
                .filter(DatabaseSchema.WhatsAppMessagesColumns.isRead == false)
                .update(DatabaseSchema.WhatsAppMessagesColumns.isRead <- true)
        )
        
        // Reset contatore unread
        try db.run(
            DatabaseSchema.whatsappChats
                .filter(DatabaseSchema.WhatsAppChatsColumns.chatId == chatId)
                .update(DatabaseSchema.WhatsAppChatsColumns.unreadCount <- 0)
        )
        
        return .ok
    }
    
    // MARK: - WhatsApp Client Management (Proxy to WA Bridge)
    
    let waClients = whatsapp.grouped("clients")
    let waBridgeURL = HubConfiguration.waBridgeURL
    
    // Inizializza client WhatsApp
    waClients.post(":accountId", "init") { req async throws -> Response in
        guard let accountId = req.parameters.get("accountId") else {
            throw Abort(.badRequest, reason: "Missing accountId")
        }
        
        struct InitRequest: Content {
            let phoneNumber: String?
        }
        
        let initReq = try? req.content.decode(InitRequest.self)
        
        let bridgeURL = URL(string: "\(waBridgeURL)/clients/\(accountId)/init")!
        var bridgeRequest = URLRequest(url: bridgeURL)
        bridgeRequest.httpMethod = "POST"
        bridgeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        bridgeRequest.timeoutInterval = 30
        
        let body: [String: Any] = ["phoneNumber": initReq?.phoneNumber ?? ""]
        bridgeRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: bridgeRequest)
            guard let http = response as? HTTPURLResponse else {
                var r = Response(status: .serviceUnavailable, body: .init(string: #"{"error":"WA Bridge non raggiungibile"}"#))
                r.headers.contentType = .json
                return r
            }
            print("[Hub] WhatsApp client init for \(accountId) -> \(http.statusCode)")
            var resp = Response(status: HTTPResponseStatus(statusCode: http.statusCode))
            resp.body = .init(data: data)
            resp.headers.contentType = .json
            return resp
        } catch {
            print("[Hub] WA Bridge unreachable for init \(accountId): \(error)")
            let details = error.localizedDescription.replacingOccurrences(of: "\"", with: "\\\"")
            var resp = Response(status: .serviceUnavailable, body: .init(string: "{\"error\":\"WA Bridge non raggiungibile\",\"details\":\"\(details)\"}"))
            resp.headers.contentType = .json
            return resp
        }
    }
    
    // Stato client WhatsApp
    waClients.get(":accountId", "status") { req async throws -> Response in
        guard let accountId = req.parameters.get("accountId") else {
            throw Abort(.badRequest, reason: "Missing accountId")
        }
        
        let bridgeURL = URL(string: "\(waBridgeURL)/clients/\(accountId)/status")!
        
        do {
            let (data, response) = try await URLSession.shared.data(from: bridgeURL)
            
            guard let http = response as? HTTPURLResponse else {
                throw Abort(.serviceUnavailable, reason: "WA Bridge not reachable")
            }
            
            var resp = Response(status: HTTPResponseStatus(statusCode: http.statusCode))
            resp.body = .init(data: data)
            resp.headers.contentType = .json
            return resp
        } catch {
            // Client non esiste
            return Response(status: .notFound, body: .init(string: "{\"status\": \"disconnected\"}"))
        }
    }
    
    // QR Code e status per client WhatsApp (proxy diretto al WA Bridge)
    waClients.get(":accountId", "qr") { req async throws -> Response in
        guard let accountId = req.parameters.get("accountId") else {
            throw Abort(.badRequest, reason: "Missing accountId")
        }
        
        // Prima prova a ottenere lo status direttamente dal WA Bridge
        let bridgeURL = URL(string: "\(waBridgeURL)/clients/\(accountId)/status")!
        
        do {
            let (data, response) = try await URLSession.shared.data(from: bridgeURL)
            
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                // Client non esiste nel bridge, restituisci status disconnected
                return Response(status: .ok, body: .init(string: "{\"qr\": null, \"status\": \"disconnected\"}"))
            }
            
            // Decodifica la risposta del bridge
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String {
                
                // Se in attesa QR, recupera anche il QR code dallo storage
                if status == "waitingQR", let qr = await WhatsAppQRStorage.shared.getQRCode(for: accountId) {
                    let jsonResponse = """
                    {"qr": "\(qr)", "status": "waitingQR"}
                    """
                    return Response(status: .ok, body: .init(string: jsonResponse))
                }
                
                // Altrimenti restituisci solo lo status
                let jsonResponse = """
                {"qr": null, "status": "\(status)"}
                """
                return Response(status: .ok, body: .init(string: jsonResponse))
            }
            
            // Fallback: restituisci la risposta del bridge così com'è
            var resp = Response(status: .ok)
            resp.body = .init(data: data)
            resp.headers.contentType = .json
            return resp
            
        } catch {
            // Bridge non raggiungibile, usa lo storage locale come fallback
            if let qr = await WhatsAppQRStorage.shared.getQRCode(for: accountId) {
                let jsonResponse = """
                {"qr": "\(qr)", "status": "waitingQR"}
                """
                return Response(status: .ok, body: .init(string: jsonResponse))
            } else {
                let status = await WhatsAppQRStorage.shared.getStatus(for: accountId)
                let jsonResponse = """
                {"qr": null, "status": "\(status)"}
                """
                return Response(status: .ok, body: .init(string: jsonResponse))
            }
        }
    }
    
    // Verifica se un numero è registrato su WhatsApp
    waClients.post(":accountId", "check-number") { req async throws -> Response in
        guard let accountId = req.parameters.get("accountId") else {
            throw Abort(.badRequest, reason: "Missing accountId")
        }
        
        let bridgeURL = URL(string: "\(waBridgeURL)/clients/\(accountId)/check-number")!
        var bridgeRequest = URLRequest(url: bridgeURL)
        bridgeRequest.httpMethod = "POST"
        bridgeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Forward body as-is
        if let body = req.body.data {
            bridgeRequest.httpBody = Data(buffer: body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: bridgeRequest)
        
        guard let http = response as? HTTPURLResponse else {
            throw Abort(.serviceUnavailable, reason: "WA Bridge not reachable")
        }
        
        print("[Hub] WhatsApp check-number for \(accountId) -> \(http.statusCode)")
        
        var resp = Response(status: HTTPResponseStatus(statusCode: http.statusCode))
        resp.body = .init(data: data)
        resp.headers.contentType = .json
        return resp
    }
    
    // Ottieni foto profilo contatto
    waClients.get(":accountId", "profile-pic", ":contactId") { req async throws -> Response in
        guard let accountId = req.parameters.get("accountId"),
              let contactId = req.parameters.get("contactId") else {
            throw Abort(.badRequest, reason: "Missing parameters")
        }
        
        let bridgeURL = URL(string: "\(waBridgeURL)/clients/\(accountId)/profile-pic/\(contactId)")!
        var bridgeRequest = URLRequest(url: bridgeURL)
        bridgeRequest.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: bridgeRequest)
        
        guard let http = response as? HTTPURLResponse else {
            throw Abort(.serviceUnavailable, reason: "WA Bridge not reachable")
        }
        
        var resp = Response(status: HTTPResponseStatus(statusCode: http.statusCode))
        resp.body = .init(data: data)
        resp.headers.contentType = .json
        return resp
    }
    
    // Invia messaggio WhatsApp
    waClients.post(":accountId", "send") { req async throws -> Response in
        guard let accountId = req.parameters.get("accountId") else {
            throw Abort(.badRequest, reason: "Missing accountId")
        }
        
        let bridgeURL = URL(string: "\(waBridgeURL)/clients/\(accountId)/send")!
        var bridgeRequest = URLRequest(url: bridgeURL)
        bridgeRequest.httpMethod = "POST"
        bridgeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Forward body as-is
        if let body = req.body.data {
            bridgeRequest.httpBody = Data(buffer: body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: bridgeRequest)
        
        guard let http = response as? HTTPURLResponse else {
            throw Abort(.serviceUnavailable, reason: "WA Bridge not reachable")
        }
        
        print("[Hub] WhatsApp send for \(accountId) -> \(http.statusCode)")
        
        var resp = Response(status: HTTPResponseStatus(statusCode: http.statusCode))
        resp.body = .init(data: data)
        resp.headers.contentType = .json
        return resp
    }
    
    // Disconnetti client WhatsApp
    waClients.post(":accountId", "disconnect") { req async throws -> Response in
        guard let accountId = req.parameters.get("accountId") else {
            throw Abort(.badRequest, reason: "Missing accountId")
        }
        
        let bridgeURL = URL(string: "\(waBridgeURL)/clients/\(accountId)/disconnect")!
        var bridgeRequest = URLRequest(url: bridgeURL)
        bridgeRequest.httpMethod = "POST"
        
        let (data, response) = try await URLSession.shared.data(for: bridgeRequest)
        
        guard let http = response as? HTTPURLResponse else {
            throw Abort(.serviceUnavailable, reason: "WA Bridge not reachable")
        }
        
        print("[Hub] WhatsApp disconnect for \(accountId) -> \(http.statusCode)")
        
        var resp = Response(status: HTTPResponseStatus(statusCode: http.statusCode))
        resp.body = .init(data: data)
        resp.headers.contentType = .json
        return resp
    }
    
    // Tag email (per notifica nuova documentazione)
    emails.post(":id", "tag") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing email id")
        }
        
        struct EmailTagRequest: Content {
            let tag: String
            let sinistroRef: String?
        }
        
        let request = try req.content.decode(EmailTagRequest.self)
        
        // Se tag è "nuova_documentazione", crea job scan
        if request.tag == "nuova_documentazione" {
            if let sinistroRef = request.sinistroRef {
                let processor = EmailProcessor(db: DatabaseManager.shared, vaultManager: VaultManager.shared)
                try await processor.reclassifyAsFileNotification(emailId: id, sinistroRef: sinistroRef)
            }
        }
        
        // Salva tag in database
        let db = try await DatabaseManager.shared.db()
        try db.run(
            DatabaseSchema.emails
                .filter(DatabaseSchema.EmailsColumns.messageId == id)
                .update(DatabaseSchema.EmailsColumns.category <- request.tag)
        )
        
        print("[Emails] Tagged email \(id) as \(request.tag)")
        return .ok
    }
    
    // MARK: - Task Routes (Client API)
    
    let tasks = app.grouped("tasks")
    
    // Lista task per utente (user = username, email opzionale per retrocompat)
    tasks.get { req async throws -> [TaskDTO] in
        guard let user = req.query[String.self, at: "user"] else {
            throw Abort(.badRequest, reason: "Missing user")
        }
        let email = req.query[String.self, at: "email"]
        let tasks = try await CloudKitWebService.shared.fetchTasks(forUser: user, fallbackEmail: email)
        return tasks.map { TaskDTO(from: $0) }
    }
    
    // Lista task per sinistro
    tasks.get("sinistro", ":ref") { req async throws -> [TaskDTO] in
        guard let ref = req.parameters.get("ref") else {
            throw Abort(.badRequest, reason: "Missing sinistro ref")
        }
        
        let allTasks = try await CloudKitWebService.shared.fetchTasks(forUser: "")
        let filtered = allTasks.filter { $0.sinistroRef == ref }
        return filtered.map { TaskDTO(from: $0) }
    }
    
    // Crea task
    tasks.post { req async throws -> TaskDTO in
        let request = try req.content.decode(CreateTaskRequest.self)
        
        let task = HubTask(
            id: UUID().uuidString,
            title: request.title,
            description: request.description,
            type: request.type,
            priority: request.priority,
            sinistroRef: request.sinistroRef,
            dueDate: request.dueDate,
            status: .pending,
            assignedTo: request.assignedTo,
            createdBy: request.createdBy,
            createdAt: Date(),
            completedAt: nil,
            syncedToCK: false
        )
        
        // Salva su CloudKit
        try await CloudKitWebService.shared.saveTask(task)
        
        // Crea anche sul TaskEngine locale
        _ = try await TaskEngine.shared.createTask(task)
        
        return TaskDTO(from: task)
    }
    
    // Aggiorna task
    tasks.put(":id") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing task id")
        }
        
        let request = try req.content.decode(UpdateTaskRequest.self)
        
        // Costruisci HubTask con i campi aggiornati
        let task = HubTask(
            id: id,
            title: request.title ?? "",
            description: request.description,
            type: .generic,
            priority: request.priority ?? .medium,
            sinistroRef: nil,
            dueDate: request.dueDate,
            status: request.status ?? .pending,
            assignedTo: nil,
            createdBy: nil,
            createdAt: Date(),
            completedAt: nil,
            syncedToCK: false
        )
        
        _ = try await TaskEngine.shared.updateTask(task)
        return .ok
    }
    
    // Completa task
    tasks.post(":id", "complete") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing task id")
        }
        
        try await TaskEngine.shared.completeTask(id)
        return .ok
    }
    
    // MARK: - AI Routes (Client API)
    
    let ai = app.grouped("ai")
    
    // Stato provider AI
    ai.get("status") { req async throws -> [AIProviderStatus] in
        return await HubAIManager.shared.getProvidersStatus()
    }
    
    // Classifica email con AI
    ai.post("classify-email") { req async throws -> AIEmailClassification in
        struct ClassifyRequest: Content {
            let subject: String
            let body: String
            let senderEmail: String
        }
        
        let request = try req.content.decode(ClassifyRequest.self)
        
        return try await HubAIManager.shared.classifyEmail(
            subject: request.subject,
            body: request.body,
            senderEmail: request.senderEmail
        )
    }
    
    // Estrai info assegnazione
    ai.post("extract-assignment") { req async throws -> [String: String] in
        struct ExtractRequest: Content {
            let body: String
        }
        
        let request = try req.content.decode(ExtractRequest.self)
        return try await HubAIManager.shared.extractAssignmentInfo(body: request.body)
    }
    
    // MARK: - SyncAgent Routes
    
    let syncagent = app.grouped("syncagent")
    
    // Lista cartelle attive da monitorare
    syncagent.get("active-folders") { req async throws -> [ActiveFolderDTO] in
        let db = try await DatabaseManager.shared.db()
        
        // Cartelle con stato attivo (non chiuso)
        let query = DatabaseSchema.sinistri
            .filter(DatabaseSchema.SinistriColumns.stato != StatoSinistro.chiusa.descrizione)
            .filter(DatabaseSchema.SinistriColumns.legacyPath != nil)
        
        var folders: [ActiveFolderDTO] = []
        for row in try db.prepare(query) {
            let folder = ActiveFolderDTO(
                sinistroRef: row[DatabaseSchema.SinistriColumns.riferimento],
                legacyPath: row[DatabaseSchema.SinistriColumns.legacyPath] ?? "",
                lastSyncAt: row[DatabaseSchema.SinistriColumns.lastModifiedAt]
            )
            folders.append(folder)
        }
        
        return folders
    }
    
    // Riceve risultato scansione dal SyncAgent
    syncagent.post("scan-result") { req async throws -> ScanResultResponseDTO in
        struct ScanResultRequest: Content {
            let sinistroRef: String
            let scannedAt: String
            let files: [ScannedFileDTO]
        }
        
        struct ScannedFileDTO: Content {
            let path: String
            let relativePath: String
            let size: Int64
            let modifiedAt: String
        }
        
        let request = try req.content.decode(ScanResultRequest.self)
        
        // Confronta con manifest esistente
        let changes = try await ManifestService.shared.compareWithScan(
            sinistroRef: request.sinistroRef,
            files: request.files.map {
                ManifestService.ScannedFile(
                    path: $0.path,
                    relativePath: $0.relativePath,
                    size: $0.size,
                    modifiedAt: ISO8601DateFormatter().date(from: $0.modifiedAt)
                )
            }
        )
        
        print("[SyncAgent] Scan result for \(request.sinistroRef): \(changes.newFiles.count) new, \(changes.modifiedFiles.count) modified, \(changes.deletedFiles.count) deleted")
        
        return ScanResultResponseDTO(
            changes: changes.newFiles.count + changes.modifiedFiles.count + changes.deletedFiles.count,
            newFiles: changes.newFiles.count,
            modifiedFiles: changes.modifiedFiles.count,
            deletedFiles: changes.deletedFiles.count
        )
    }
    
    // Richiedi scan on-demand
    syncagent.post("request-scan", ":ref") { req async throws -> HTTPStatus in
        guard let ref = req.parameters.get("ref") else {
            throw Abort(.badRequest, reason: "Missing sinistro ref")
        }
        
        // Ottieni legacy path dal sinistro
        let db = try await DatabaseManager.shared.db()
        let query = DatabaseSchema.sinistri.filter(DatabaseSchema.SinistriColumns.riferimento == ref)
        
        guard let row = try db.pluck(query),
              let legacyPath = row[DatabaseSchema.SinistriColumns.legacyPath] else {
            throw Abort(.notFound, reason: "Sinistro not found or no legacy path")
        }
        
        // Crea job di scan
        _ = try await JobService.shared.createScanLegacyJob(
            sinistroRef: ref,
            legacyPath: legacyPath,
            priority: 5
        )
        
        return .accepted
    }
    
    // MARK: - Debug Routes (solo per development)
    
    #if DEBUG
    let debug = app.grouped("debug")
    
    debug.get("stats") { req async throws -> [String: String] in
        return [
            "status": "ok",
            "vault_path": HubConfiguration.vaultPath,
            "db_path": HubConfiguration.dbPath
        ]
    }
    #endif
    
    // MARK: - Auth Routes (gestione token OAuth per Mail Worker)
    
    let auth = app.grouped("auth")
    
    /// Registra token OAuth da client
    /// Il client invia il refresh_token dopo il login Google,
    /// l'Hub lo passa al Mail Worker per accedere a Gmail
    auth.post("register-token") { req async throws -> HTTPStatus in
        let request = try req.content.decode(RegisterTokenRequest.self)
        
        // Forward al Mail Worker
        let workerURL = HubConfiguration.emailWorkerURL
        guard let url = URL(string: "\(workerURL)/auth/register-token") else {
            throw Abort(.internalServerError, reason: "Invalid worker URL")
        }
        
        var workerRequest = URLRequest(url: url)
        workerRequest.httpMethod = "POST"
        workerRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        workerRequest.httpBody = try JSONEncoder().encode(request)
        workerRequest.timeoutInterval = 30
        
        let (_, response) = try await URLSession.shared.data(for: workerRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Abort(.internalServerError)
        }
        
        if httpResponse.statusCode == 200 {
            print("[Auth] Token registered for user: \(request.userId)")
            return .ok
        } else {
            throw Abort(.init(statusCode: httpResponse.statusCode))
        }
    }
    
    /// Verifica stato token per un utente
    auth.get("status", ":userId") { req async throws -> TokenStatusResponse in
        guard let userId = req.parameters.get("userId") else {
            throw Abort(.badRequest)
        }
        
        // Forward al Mail Worker
        let workerURL = HubConfiguration.emailWorkerURL
        guard let url = URL(string: "\(workerURL)/auth/status/\(userId)") else {
            throw Abort(.internalServerError, reason: "Invalid worker URL")
        }
        
        var workerRequest = URLRequest(url: url)
        workerRequest.httpMethod = "GET"
        workerRequest.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: workerRequest)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            // Worker non raggiungibile o errore
            return TokenStatusResponse(userId: userId, email: nil, isValid: false, hasToken: false)
        }
        
        return try JSONDecoder().decode(TokenStatusResponse.self, from: data)
    }
    
    /// Elimina token (logout)
    auth.delete("token", ":userId") { req async throws -> HTTPStatus in
        guard let userId = req.parameters.get("userId") else {
            throw Abort(.badRequest)
        }
        
        // Forward al Mail Worker
        let workerURL = HubConfiguration.emailWorkerURL
        guard let url = URL(string: "\(workerURL)/auth/token/\(userId)") else {
            throw Abort(.internalServerError, reason: "Invalid worker URL")
        }
        
        var workerRequest = URLRequest(url: url)
        workerRequest.httpMethod = "DELETE"
        workerRequest.timeoutInterval = 10
        
        let (_, response) = try await URLSession.shared.data(for: workerRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Abort(.internalServerError)
        }
        
        if httpResponse.statusCode == 200 {
            print("[Auth] Token deleted for user: \(userId)")
            return .ok
        } else {
            throw Abort(.init(statusCode: httpResponse.statusCode))
        }
    }
    
    /// Lista utenti con token
    auth.get("users") { req async throws -> [UserTokenInfo] in
        // Forward al Mail Worker
        let workerURL = HubConfiguration.emailWorkerURL
        guard let url = URL(string: "\(workerURL)/auth/users") else {
            throw Abort(.internalServerError, reason: "Invalid worker URL")
        }
        
        var workerRequest = URLRequest(url: url)
        workerRequest.httpMethod = "GET"
        workerRequest.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: workerRequest)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return []
        }
        
        return try JSONDecoder().decode([UserTokenInfo].self, from: data)
    }
    
    // MARK: - JFish Sync Routes (Chrome Extension API)
    
    let jfish = app.grouped("jfish")
    
    /// Confronta dati JFish con PerX e restituisce differenze
    /// POST /jfish/compare
    jfish.post("compare") { req async throws -> JFishCompareResult in
        let jfishData = try req.content.decode(JFishSinistroDTO.self)
        
        // Cerca sinistro in PerX
        let perxData = try? await CloudKitWebService.shared.fetchSinistro(riferimento: jfishData.riferimento)
        
        // Confronta
        let result = await JFishSyncService.shared.compare(jfishData: jfishData, perxData: perxData)
        
        print("[JFish] Confronto per \(jfishData.riferimento): \(result.differences.count) differenze")
        return result
    }
    
    /// Recupera dati sinistro da PerX per il confronto
    /// GET /jfish/sinistro/:ref
    jfish.get("sinistro", ":ref") { req async throws -> SinistroDTO in
        guard let ref = req.parameters.get("ref") else {
            throw Abort(.badRequest, reason: "Missing sinistro ref")
        }
        
        print("[JFish] GET sinistro: \(ref)")
        
        guard let sinistro = try await CloudKitWebService.shared.fetchSinistro(riferimento: ref) else {
            print("[JFish] Sinistro non trovato: \(ref)")
            throw Abort(.notFound, reason: "Sinistro non trovato in PerX")
        }
        
        print("[JFish] Sinistro trovato: \(ref), stato: \(sinistro.stato)")
        return sinistro
    }
    
    /// Aggiorna sinistro PerX con dati da JFish
    /// PUT /jfish/sinistro/:ref
    jfish.put("sinistro", ":ref") { req async throws -> JFishUpdateResult in
        guard let ref = req.parameters.get("ref") else {
            throw Abort(.badRequest, reason: "Missing sinistro ref")
        }
        
        let updates = try req.content.decode(JFishUpdateRequest.self)
        
        do {
            let result = try await JFishSyncService.shared.updateFromJFish(riferimento: ref, updates: updates)
            print("[JFish] Aggiornamento \(ref): \(result.updatedFields.count) campi")
            return result
        } catch let error as JFishSyncError {
            throw Abort(.badRequest, reason: error.localizedDescription)
        }
    }
    
    /// Importa tutti i dati da JFish a PerX
    /// POST /jfish/sinistro/:ref/import
    jfish.post("sinistro", ":ref", "import") { req async throws -> JFishUpdateResult in
        guard let ref = req.parameters.get("ref") else {
            throw Abort(.badRequest, reason: "Missing sinistro ref")
        }
        
        let jfishData = try req.content.decode(JFishSinistroDTO.self)
        
        // Costruisci lista di tutti i campi da aggiornare
        var fieldUpdates: [JFishFieldUpdate] = []
        
        // Stato
        if let stato = jfishData.stato {
            fieldUpdates.append(JFishFieldUpdate(field: "stato", value: stato))
        }
        
        // Numero sinistro
        if let numero = jfishData.numeroSinistro {
            fieldUpdates.append(JFishFieldUpdate(field: "numeroSinistroCompagnia", value: numero))
        }
        
        // Date
        if let date = jfishData.dataSinistro { fieldUpdates.append(JFishFieldUpdate(field: "dataSinistro", value: date)) }
        if let date = jfishData.dataDenuncia { fieldUpdates.append(JFishFieldUpdate(field: "dataDenuncia", value: date)) }
        if let date = jfishData.dataIncarico { fieldUpdates.append(JFishFieldUpdate(field: "dataIncarico", value: date)) }
        if let date = jfishData.dataSopralluogo { fieldUpdates.append(JFishFieldUpdate(field: "dataSopralluogo", value: date)) }
        if let date = jfishData.dataInvioAtto { fieldUpdates.append(JFishFieldUpdate(field: "dataInvioAtto", value: date)) }
        if let date = jfishData.dataChiusura { fieldUpdates.append(JFishFieldUpdate(field: "dataChiusura", value: date)) }
        if let date = jfishData.dataPagamentoPremio { fieldUpdates.append(JFishFieldUpdate(field: "dataPagamentoPremio", value: date)) }
        
        // Attori
        if let assicurato = jfishData.assicurato {
            if let nome = assicurato.nome { fieldUpdates.append(JFishFieldUpdate(field: "nomeAssicurato", value: nome)) }
            if let tel = assicurato.telefono { fieldUpdates.append(JFishFieldUpdate(field: "telefonoAssicurato", value: tel)) }
            if let email = assicurato.email { fieldUpdates.append(JFishFieldUpdate(field: "emailAssicurato", value: email)) }
        }
        if let contraente = jfishData.contraente {
            if let nome = contraente.nome { fieldUpdates.append(JFishFieldUpdate(field: "nomeContraente", value: nome)) }
            if let tel = contraente.telefono { fieldUpdates.append(JFishFieldUpdate(field: "telefonoContraente", value: tel)) }
            if let email = contraente.email { fieldUpdates.append(JFishFieldUpdate(field: "emailContraente", value: email)) }
        }
        if let danneggiato = jfishData.danneggiato {
            if let nome = danneggiato.nome { fieldUpdates.append(JFishFieldUpdate(field: "nomeDanneggiato", value: nome)) }
            if let tel = danneggiato.telefono { fieldUpdates.append(JFishFieldUpdate(field: "telefonoDanneggiato", value: tel)) }
            if let email = danneggiato.email { fieldUpdates.append(JFishFieldUpdate(field: "emailDanneggiato", value: email)) }
            if let cf = danneggiato.codiceFiscale { fieldUpdates.append(JFishFieldUpdate(field: "codiceFiscaleAssicurato", value: cf)) }
        }
        
        // Polizza
        if let polizza = jfishData.polizza {
            if let gruppo = polizza.gruppo { fieldUpdates.append(JFishFieldUpdate(field: "gruppo", value: gruppo)) }
            if let compagnia = polizza.compagnia { fieldUpdates.append(JFishFieldUpdate(field: "nomeCompagnia", value: compagnia)) }
            if let garanzia = polizza.garanzia { fieldUpdates.append(JFishFieldUpdate(field: "fulminazione", value: garanzia)) }
            if let numero = polizza.numero { fieldUpdates.append(JFishFieldUpdate(field: "numeroPolizza", value: numero)) }
        }
        
        // Agenzia
        if let amm = jfishData.amministratore {
            if let nome = amm.nome { fieldUpdates.append(JFishFieldUpdate(field: "agenzia", value: nome)) }
            if let tel = amm.telefono { fieldUpdates.append(JFishFieldUpdate(field: "telefonoAgenzia", value: tel)) }
            if let email = amm.email { fieldUpdates.append(JFishFieldUpdate(field: "emailAgenzia", value: email)) }
        }
        
        // Importi
        if let richiesta = jfishData.richiestaDenuncia {
            fieldUpdates.append(JFishFieldUpdate(field: "richiesta", value: String(format: "%.2f", richiesta)))
        }
        
        // Esito
        if let esito = jfishData.esitoPerizia {
            fieldUpdates.append(JFishFieldUpdate(field: "definizione", value: esito))
        }
        
        let updates = JFishUpdateRequest(fields: fieldUpdates)
        
        do {
            let result = try await JFishSyncService.shared.updateFromJFish(riferimento: ref, updates: updates)
            print("[JFish] Import completo \(ref): \(result.updatedFields.count) campi")
            return result
        } catch let error as JFishSyncError {
            throw Abort(.badRequest, reason: error.localizedDescription)
        }
    }
    
    /// Recupera diario da PerX
    /// GET /jfish/sinistro/:ref/diario
    jfish.get("sinistro", ":ref", "diario") { req async throws -> [JFishDiarioResponseEntry] in
        guard let ref = req.parameters.get("ref") else {
            throw Abort(.badRequest, reason: "Missing sinistro ref")
        }
        
        // Recupera diario da CloudKit
        let entries = try await CloudKitWebService.shared.fetchDiario(sinistroRef: ref)
        
        // Converti in formato JFish-compatibile
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        
        return entries.map { entry in
            JFishDiarioResponseEntry(
                id: entry.id,
                data: formatter.string(from: entry.timestamp),
                tipo: entry.tipo,
                nota: entry.testo,
                autore: entry.createdByEmail
            )
        }
    }
    
    /// Sincronizza diario da JFish a PerX
    /// POST /jfish/sinistro/:ref/diario/sync
    jfish.post("sinistro", ":ref", "diario", "sync") { req async throws -> JFishDiarioSyncResult in
        guard let ref = req.parameters.get("ref") else {
            throw Abort(.badRequest, reason: "Missing sinistro ref")
        }
        
        struct DiarioSyncRequest: Content {
            let entries: [JFishDiarioEntry]
        }
        
        let request = try req.content.decode(DiarioSyncRequest.self)
        
        // Recupera diario esistente
        let existingEntries = try await CloudKitWebService.shared.fetchDiario(sinistroRef: ref)
        
        // Formatter per parsing date
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        
        var addedCount = 0
        var skippedCount = 0
        
        for jfishEntry in request.entries {
            // Controlla se esiste già (per data e nota simile)
            let jfishDate = formatter.date(from: jfishEntry.data ?? "") ?? Date()
            let exists = existingEntries.contains { existing in
                let sameDay = Calendar.current.isDate(existing.timestamp, inSameDayAs: jfishDate)
                let sameText = existing.testo.prefix(50) == (jfishEntry.nota ?? "").prefix(50)
                return sameDay && sameText
            }
            
            if exists {
                skippedCount += 1
            } else {
                // Aggiungi nuova entry usando DiarioEntryDTO esistente
                let entry = DiarioEntryDTO(
                    id: jfishEntry.id ?? UUID().uuidString,
                    timestamp: jfishDate,
                    testo: jfishEntry.nota ?? "",
                    tipo: jfishEntry.tipo ?? "nota",
                    createdByEmail: "jfish-import@perx.it"
                )
                
                try await CloudKitWebService.shared.addDiarioEntry(sinistroRef: ref, entry: entry)
                addedCount += 1
            }
        }
        
        print("[JFish] Sync diario \(ref): \(addedCount) aggiunte, \(skippedCount) saltate")
        
        return JFishDiarioSyncResult(
            success: true,
            riferimento: ref,
            addedEntries: addedCount,
            skippedEntries: skippedCount,
            message: "Sincronizzate \(addedCount) entry, \(skippedCount) già presenti"
        )
    }
    
    print("[Routes] Configured all routes")
}

// MARK: - JFish DTOs

struct JFishSinistroNotFound: Content {
    let error: Bool
    let riferimento: String
    let message: String
}

/// Entry diario in formato JFish-compatibile per response API
struct JFishDiarioResponseEntry: Content {
    let id: String
    let data: String  // Formato italiano dd/MM/yyyy
    let tipo: String?
    let nota: String?
    let autore: String?
}

// MARK: - SyncAgent DTOs

struct ActiveFolderDTO: Content {
    let sinistroRef: String
    let legacyPath: String
    let lastSyncAt: Double
}

struct ScanResultResponseDTO: Content {
    let changes: Int
    let newFiles: Int
    let modifiedFiles: Int
    let deletedFiles: Int
}

// MARK: - Email Send DTO

struct SendEmailResponseDTO: Content, Decodable {
    let success: Bool
    let messageId: String?
    let error: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case messageId = "message_id"
        case error
    }
}

// MARK: - Auth DTOs

struct RegisterTokenRequest: Content, Encodable {
    let userId: String
    let email: String
    let refreshToken: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case refreshToken = "refresh_token"
    }
}

struct TokenStatusResponse: Content, Decodable {
    let userId: String
    let email: String?
    let isValid: Bool
    let hasToken: Bool
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case isValid = "is_valid"
        case hasToken = "has_token"
    }
}

struct UserTokenInfo: Content, Decodable {
    let userId: String
    let email: String
    let storedAt: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case storedAt = "stored_at"
    }
}

// MARK: - Scheduled Message DTOs

struct ScheduledWhatsAppDTO: Content {
    let id: String
    let accountId: String
    let phoneNumber: String
    let body: String
    let mediaData: String?
    let mediaType: String?
    let mediaFilename: String?
    let scheduledAt: Date
    let status: String
    let sinistroRef: String?
}

struct BroadcastEventDTO: Content {
    let id: String
    let type: String
    let payload: [String: String]
    let timestamp: Date
}

// MARK: - WhatsApp DTOs

struct WhatsAppChatDTO: Content {
    let id: String
    let accountId: String
    let chatId: String
    let name: String?
    let phoneNumber: String?
    let isGroup: Bool
    let lastMessageBody: String?
    let lastMessageAt: Date?
    let unreadCount: Int
    let sinistroRef: String?
}

struct WhatsAppMessageDTO: Content {
    let id: String
    let accountId: String
    let chatId: String
    let waMessageId: String
    let fromNumber: String
    let toNumber: String?
    let body: String?
    let timestamp: Date
    let direction: String
    let type: String
    let mediaType: String?
    let mediaFilename: String?
    let hasMedia: Bool
    let isRead: Bool
    let sinistroRef: String?
    // ACK status: -1=error, 0=pending, 1=sent, 2=delivered, 3=read, 4=played
    let ackStatus: Int?
    let ackTimestamp: Date?
}
