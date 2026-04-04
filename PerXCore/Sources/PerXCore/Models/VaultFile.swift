import Foundation

/// Rappresenta un file nel Vault dell'Hub
public struct VaultFile: Codable, Identifiable, Sendable {
    public let id: String
    public let tenantSlug: String
    public let sinistroRef: String
    public let relativePath: String
    public let filename: String
    public let folder: String
    public let size: Int64
    public let mimeType: String?
    public let checksum: String?
    public let source: VaultFileSource
    public let sourceId: String?
    public let createdAt: Date
    public let modifiedAt: Date?
    
    public init(
        id: String = UUID().uuidString,
        tenantSlug: String = "default",
        sinistroRef: String,
        relativePath: String,
        filename: String,
        folder: String,
        size: Int64,
        mimeType: String? = nil,
        checksum: String? = nil,
        source: VaultFileSource = .upload,
        sourceId: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.tenantSlug = tenantSlug
        self.sinistroRef = sinistroRef
        self.relativePath = relativePath
        self.filename = filename
        self.folder = folder
        self.size = size
        self.mimeType = mimeType
        self.checksum = checksum
        self.source = source
        self.sourceId = sourceId
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// Origine del file nel Vault
public enum VaultFileSource: String, Codable, Sendable {
    case upload     // Caricato manualmente da client
    case email      // Allegato email
    case whatsapp   // Allegato WhatsApp
    case importJob  // Importato da legacy filesystem
}

/// Stato della cartella sinistro nel Vault
public enum SinistroFolderStatus: String, Codable, Sendable {
    case pending    // In attesa di import iniziale
    case importing  // Import in corso dal legacy
    case ready      // Pronta per lavorazione
    case syncing    // Sync in corso (upload/download)
    case exporting  // Export finale in corso
    case archived   // Sinistro chiuso, cartella archiviata
    case error      // Errore durante operazioni
}

/// Metadati della cartella sinistro nel Vault
public struct SinistroFolder: Codable, Sendable {
    public let tenantSlug: String
    public let sinistroRef: String
    public var status: SinistroFolderStatus
    public var lastSyncAt: Date?
    public var fileCount: Int
    public var totalSize: Int64
    public var errorMessage: String?
    
    public init(
        tenantSlug: String = "default",
        sinistroRef: String,
        status: SinistroFolderStatus = .pending,
        lastSyncAt: Date? = nil,
        fileCount: Int = 0,
        totalSize: Int64 = 0,
        errorMessage: String? = nil
    ) {
        self.tenantSlug = tenantSlug
        self.sinistroRef = sinistroRef
        self.status = status
        self.lastSyncAt = lastSyncAt
        self.fileCount = fileCount
        self.totalSize = totalSize
        self.errorMessage = errorMessage
    }
}
