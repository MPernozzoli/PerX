import Foundation

// MARK: - Vault File DTOs

/// DTO per risposta lista file
public struct VaultFileDTO: Codable, Sendable {
    public let id: String
    public let sinistroRef: String
    public let filename: String
    public let folder: String
    public let size: Int64
    public let mimeType: String?
    public let checksum: String?
    public let createdAt: Date
    public let modifiedAt: Date?
    
    public init(from file: VaultFile) {
        self.id = file.id
        self.sinistroRef = file.sinistroRef
        self.filename = file.filename
        self.folder = file.folder
        self.size = file.size
        self.mimeType = file.mimeType
        self.checksum = file.checksum
        self.createdAt = file.createdAt
        self.modifiedAt = file.modifiedAt
    }
    
    public init(
        id: String,
        sinistroRef: String,
        filename: String,
        folder: String,
        size: Int64,
        mimeType: String? = nil,
        checksum: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.sinistroRef = sinistroRef
        self.filename = filename
        self.folder = folder
        self.size = size
        self.mimeType = mimeType
        self.checksum = checksum
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// DTO per upload file
public struct FileUploadRequest: Codable, Sendable {
    public let filename: String
    public let folder: String
    public let data: String // Base64 encoded
    public let mimeType: String?
    
    public init(filename: String, folder: String, data: String, mimeType: String? = nil) {
        self.filename = filename
        self.folder = folder
        self.data = data
        self.mimeType = mimeType
    }
}

/// DTO per stato cartella sinistro
public struct SinistroFolderDTO: Codable, Sendable {
    public let sinistroRef: String
    public let status: SinistroFolderStatus
    public let fileCount: Int
    public let totalSize: Int64
    public let lastSyncAt: Date?
    
    public init(from folder: SinistroFolder) {
        self.sinistroRef = folder.sinistroRef
        self.status = folder.status
        self.fileCount = folder.fileCount
        self.totalSize = folder.totalSize
        self.lastSyncAt = folder.lastSyncAt
    }
    
    public init(
        sinistroRef: String,
        status: SinistroFolderStatus,
        fileCount: Int,
        totalSize: Int64,
        lastSyncAt: Date?
    ) {
        self.sinistroRef = sinistroRef
        self.status = status
        self.fileCount = fileCount
        self.totalSize = totalSize
        self.lastSyncAt = lastSyncAt
    }
}

// MARK: - Job DTOs

/// DTO per risposta job
public struct JobDTO: Codable, Sendable {
    public let id: String
    public let type: JobType
    public let status: JobStatus
    public let priority: Int
    public let payload: JobPayload
    public let createdAt: Date
    public let startedAt: Date?
    public let completedAt: Date?
    public let errorMessage: String?
    
    public init(from job: Job) {
        self.id = job.id
        self.type = job.type
        self.status = job.status
        self.priority = job.priority
        self.payload = job.payload
        self.createdAt = job.createdAt
        self.startedAt = job.startedAt
        self.completedAt = job.completedAt
        self.errorMessage = job.errorMessage
    }
}

/// DTO per completamento job
public struct JobCompleteRequest: Codable, Sendable {
    public let result: JobResult?
    
    public init(result: JobResult? = nil) {
        self.result = result
    }
}

/// Risultato job (per import restituisce file uploadati)
public struct JobResult: Codable, Sendable {
    public let filesUploaded: Int?
    public let totalBytes: Int64?
    public let details: String?
    
    public init(filesUploaded: Int? = nil, totalBytes: Int64? = nil, details: String? = nil) {
        self.filesUploaded = filesUploaded
        self.totalBytes = totalBytes
        self.details = details
    }
}

/// DTO per errore job
public struct JobFailRequest: Codable, Sendable {
    public let message: String
    
    public init(message: String) {
        self.message = message
    }
}

// MARK: - API Response DTOs

/// Risposta generica API
public struct APIResponse<T: Codable & Sendable>: Codable, Sendable {
    public let success: Bool
    public let data: T?
    public let error: String?
    
    public init(success: Bool, data: T? = nil, error: String? = nil) {
        self.success = success
        self.data = data
        self.error = error
    }
    
    public static func ok(_ data: T) -> APIResponse {
        APIResponse(success: true, data: data)
    }
    
    public static func error(_ message: String) -> APIResponse {
        APIResponse(success: false, error: message)
    }
}

/// Health check response
public struct HealthResponse: Codable, Sendable {
    public let status: String
    public let version: String
    public let uptime: TimeInterval
    public let timestamp: Date
    
    public init(status: String = "ok", version: String, uptime: TimeInterval, timestamp: Date = Date()) {
        self.status = status
        self.version = version
        self.uptime = uptime
        self.timestamp = timestamp
    }
}

/// DTO per cambiamenti rilevati nel legacy
public struct LegacyChangesDTO: Codable, Sendable {
    public let sinistroRef: String
    public let added: [String]
    public let modified: [String]
    public let deleted: [String]
    public let totalChanges: Int
    
    public init(from changes: LegacyChanges) {
        self.sinistroRef = changes.sinistroRef
        self.added = changes.added
        self.modified = changes.modified
        self.deleted = changes.deleted
        self.totalChanges = changes.totalChanges
    }
    
    public init(sinistroRef: String, added: [String], modified: [String], deleted: [String]) {
        self.sinistroRef = sinistroRef
        self.added = added
        self.modified = modified
        self.deleted = deleted
        self.totalChanges = added.count + modified.count + deleted.count
    }
}

/// DTO per email programmata
public struct ScheduledEmailDTO: Codable, Sendable {
    public let id: String
    public let accountId: String
    public let to: [String]
    public let cc: [String]?
    public let subject: String
    public let body: String
    public let attachmentIds: [String]?
    public let scheduledAt: Date
    public let status: String
    public let sentAt: Date?
    public let errorMessage: String?
    public let createdAt: Date
    
    public init(from scheduled: ScheduledEmail) {
        self.id = scheduled.id
        self.accountId = scheduled.accountId
        self.to = scheduled.to
        self.cc = scheduled.cc
        self.subject = scheduled.subject
        self.body = scheduled.body
        self.attachmentIds = scheduled.attachmentIds
        self.scheduledAt = scheduled.scheduledAt
        self.status = scheduled.status.rawValue
        self.sentAt = scheduled.sentAt
        self.errorMessage = scheduled.errorMessage
        self.createdAt = scheduled.createdAt
    }
    
    /// Memberwise initializer for direct construction
    public init(
        id: String,
        accountId: String,
        to: [String],
        cc: [String]? = nil,
        subject: String,
        body: String,
        attachmentIds: [String]? = nil,
        scheduledAt: Date,
        status: String,
        sentAt: Date? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.attachmentIds = attachmentIds
        self.scheduledAt = scheduledAt
        self.status = status
        self.sentAt = sentAt
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }
}

/// DTO per allegato in processing sull'Hub
public struct AttachmentDTO: Codable, Sendable {
    public let id: String
    public let messageId: String
    public let filename: String
    public let size: Int64
    public let mimeType: String?
    public let status: String
    public let vaultFileId: String?
    public let sinistroRef: String?
    public let errorMessage: String?
    public let createdAt: Date
    public let processedAt: Date?
    
    public init(from attachment: HubAttachment) {
        self.id = attachment.id
        self.messageId = attachment.messageId
        self.filename = attachment.filename
        self.size = attachment.size
        self.mimeType = attachment.mimeType
        self.status = attachment.status.rawValue
        self.vaultFileId = attachment.vaultFileId
        self.sinistroRef = attachment.sinistroRef
        self.errorMessage = attachment.errorMessage
        self.createdAt = attachment.createdAt
        self.processedAt = attachment.processedAt
    }
    
    /// Init per allegati email base (dalla struttura client)
    public init(from emailAttachment: EmailAttachment) {
        self.id = emailAttachment.attachmentId
        self.messageId = "" // Non disponibile su EmailAttachment base
        self.filename = emailAttachment.filename
        self.size = Int64(emailAttachment.size)
        self.mimeType = nil
        self.status = "pending"
        self.vaultFileId = nil
        self.sinistroRef = nil
        self.errorMessage = nil
        self.createdAt = Date()
        self.processedAt = nil
    }
}

// MARK: - Email Processed Response

/// Risposta dopo processing email
public struct EmailProcessedResponse: Codable, Sendable {
    public let messageId: String
    public let category: String
    public let sinistroRef: String?
    public let confidence: Double
    public let eventGenerated: Bool
    
    public init(
        messageId: String,
        category: String,
        sinistroRef: String?,
        confidence: Double,
        eventGenerated: Bool = false
    ) {
        self.messageId = messageId
        self.category = category
        self.sinistroRef = sinistroRef
        self.confidence = confidence
        self.eventGenerated = eventGenerated
    }
}

// MARK: - Hub Stats Response (per Monitor)

/// Risposta con statistiche complete dell'Hub
public struct HubStatsResponse: Codable, Sendable {
    public let jobs: JobStats
    public let emails: EmailStats
    public let attachments: AttachmentStats
    public let whatsapp: WhatsAppStats?
    public let sync: SyncStats?
    public let chromeExt: ChromeExtStats?
    public let sinistri: Int
    public let uptime: TimeInterval
    public let connectedUsers: Int
    
    public init(
        jobs: JobStats,
        emails: EmailStats,
        attachments: AttachmentStats,
        whatsapp: WhatsAppStats? = nil,
        sync: SyncStats? = nil,
        chromeExt: ChromeExtStats? = nil,
        sinistri: Int,
        uptime: TimeInterval,
        connectedUsers: Int = 0
    ) {
        self.jobs = jobs
        self.emails = emails
        self.attachments = attachments
        self.whatsapp = whatsapp
        self.sync = sync
        self.chromeExt = chromeExt
        self.sinistri = sinistri
        self.uptime = uptime
        self.connectedUsers = connectedUsers
    }
    
    public struct JobStats: Codable, Sendable {
        public let pending: Int
        public let inProgress: Int
        
        public init(pending: Int, inProgress: Int) {
            self.pending = pending
            self.inProgress = inProgress
        }
    }
    
    public struct EmailStats: Codable, Sendable {
        public let total: Int
        public let unsynced: Int
        
        public init(total: Int, unsynced: Int) {
            self.total = total
            self.unsynced = unsynced
        }
    }
    
    public struct AttachmentStats: Codable, Sendable {
        public let pending: Int
        public let processing: Int
        
        public init(pending: Int, processing: Int) {
            self.pending = pending
            self.processing = processing
        }
    }
    
    public struct WhatsAppStats: Codable, Sendable {
        public let totalMessages: Int
        public let todayMessages: Int
        public let unreadChats: Int
        public let scheduledPending: Int
        
        public init(totalMessages: Int, todayMessages: Int, unreadChats: Int, scheduledPending: Int) {
            self.totalMessages = totalMessages
            self.todayMessages = todayMessages
            self.unreadChats = unreadChats
            self.scheduledPending = scheduledPending
        }
    }
    
    public struct SyncStats: Codable, Sendable {
        public let activeFolders: Int
        public let pendingSyncs: Int
        public let lastSyncAt: Date?
        
        public init(activeFolders: Int, pendingSyncs: Int, lastSyncAt: Date?) {
            self.activeFolders = activeFolders
            self.pendingSyncs = pendingSyncs
            self.lastSyncAt = lastSyncAt
        }
    }
    
    public struct ChromeExtStats: Codable, Sendable {
        public let todayDiarioEntries: Int
        public let todayJFishSyncs: Int
        
        public init(todayDiarioEntries: Int, todayJFishSyncs: Int) {
            self.todayDiarioEntries = todayDiarioEntries
            self.todayJFishSyncs = todayJFishSyncs
        }
    }
}
