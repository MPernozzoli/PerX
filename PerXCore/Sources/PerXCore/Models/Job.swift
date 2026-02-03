import Foundation

/// Job per Windows Agent (import/export/delete/rename)
public struct Job: Codable, Identifiable, Sendable {
    public let id: String
    public let type: JobType
    public var status: JobStatus
    public let priority: Int
    public let payload: JobPayload
    public let createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var errorMessage: String?
    public var retryCount: Int
    
    public init(
        id: String = UUID().uuidString,
        type: JobType,
        status: JobStatus = .pending,
        priority: Int = 0,
        payload: JobPayload,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        errorMessage: String? = nil,
        retryCount: Int = 0
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.priority = priority
        self.payload = payload
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
        self.retryCount = retryCount
    }
}

/// Tipo di job
public enum JobType: String, Codable, Sendable {
    case importFolder       // Import cartella sinistro da legacy
    case importFile         // Import singolo file da legacy
    case exportFile         // Export file da Vault a legacy
    case deleteFile         // Elimina file da legacy
    case renameFile         // Rinomina file su legacy
    case scanLegacy         // Scansione cartella legacy per modifiche
    case updateSyncAgent    // Aggiornamento file del sync agent remoto
}

/// Stato del job
public enum JobStatus: String, Codable, Sendable {
    case pending        // In attesa di esecuzione
    case inProgress     // In esecuzione
    case completed      // Completato con successo
    case failed         // Fallito (vedi errorMessage)
    case cancelled      // Annullato
}

/// Payload del job (union type per diversi tipi di job)
public enum JobPayload: Codable, Sendable {
    case importFolder(ImportFolderPayload)
    case importFile(ImportFilePayload)
    case exportFile(ExportFilePayload)
    case deleteFile(DeleteFilePayload)
    case renameFile(RenameFilePayload)
    case scanLegacy(ScanLegacyPayload)
    case updateSyncAgent(UpdateSyncAgentPayload)
    
    enum CodingKeys: String, CodingKey {
        case type, data
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "importFolder":
            self = .importFolder(try container.decode(ImportFolderPayload.self, forKey: .data))
        case "importFile":
            self = .importFile(try container.decode(ImportFilePayload.self, forKey: .data))
        case "exportFile":
            self = .exportFile(try container.decode(ExportFilePayload.self, forKey: .data))
        case "deleteFile":
            self = .deleteFile(try container.decode(DeleteFilePayload.self, forKey: .data))
        case "renameFile":
            self = .renameFile(try container.decode(RenameFilePayload.self, forKey: .data))
        case "scanLegacy":
            self = .scanLegacy(try container.decode(ScanLegacyPayload.self, forKey: .data))
        case "updateSyncAgent":
            self = .updateSyncAgent(try container.decode(UpdateSyncAgentPayload.self, forKey: .data))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown job type: \(type)")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .importFolder(let payload):
            try container.encode("importFolder", forKey: .type)
            try container.encode(payload, forKey: .data)
        case .importFile(let payload):
            try container.encode("importFile", forKey: .type)
            try container.encode(payload, forKey: .data)
        case .exportFile(let payload):
            try container.encode("exportFile", forKey: .type)
            try container.encode(payload, forKey: .data)
        case .deleteFile(let payload):
            try container.encode("deleteFile", forKey: .type)
            try container.encode(payload, forKey: .data)
        case .renameFile(let payload):
            try container.encode("renameFile", forKey: .type)
            try container.encode(payload, forKey: .data)
        case .scanLegacy(let payload):
            try container.encode("scanLegacy", forKey: .type)
            try container.encode(payload, forKey: .data)
        case .updateSyncAgent(let payload):
            try container.encode("updateSyncAgent", forKey: .type)
            try container.encode(payload, forKey: .data)
        }
    }
}

// MARK: - Payload Types

public struct ImportFolderPayload: Codable, Sendable {
    public let sinistroRef: String
    public let legacyPath: String
    
    public init(sinistroRef: String, legacyPath: String) {
        self.sinistroRef = sinistroRef
        self.legacyPath = legacyPath
    }
}

public struct ImportFilePayload: Codable, Sendable {
    public let sinistroRef: String
    public let legacyPath: String
    public let targetFolder: String
    
    public init(sinistroRef: String, legacyPath: String, targetFolder: String) {
        self.sinistroRef = sinistroRef
        self.legacyPath = legacyPath
        self.targetFolder = targetFolder
    }
}

public struct ExportFilePayload: Codable, Sendable {
    public let vaultFileId: String
    public let legacyPath: String
    
    public init(vaultFileId: String, legacyPath: String) {
        self.vaultFileId = vaultFileId
        self.legacyPath = legacyPath
    }
}

public struct DeleteFilePayload: Codable, Sendable {
    public let legacyPath: String
    
    public init(legacyPath: String) {
        self.legacyPath = legacyPath
    }
}

public struct RenameFilePayload: Codable, Sendable {
    public let oldPath: String
    public let newPath: String
    
    public init(oldPath: String, newPath: String) {
        self.oldPath = oldPath
        self.newPath = newPath
    }
}

public struct ScanLegacyPayload: Codable, Sendable {
    public let sinistroRef: String
    public let legacyPath: String
    
    public init(sinistroRef: String, legacyPath: String) {
        self.sinistroRef = sinistroRef
        self.legacyPath = legacyPath
    }
}

public struct UpdateSyncAgentPayload: Codable, Sendable {
    /// File da aggiornare (path relativi al repo)
    public let changedFiles: [String]
    /// Path base del repository sorgente
    public let sourceBasePath: String
    /// Path di installazione sul target (Windows)
    public let targetInstallPath: String
    
    public init(changedFiles: [String], sourceBasePath: String = "", targetInstallPath: String = "") {
        self.changedFiles = changedFiles
        self.sourceBasePath = sourceBasePath
        self.targetInstallPath = targetInstallPath
    }
}
