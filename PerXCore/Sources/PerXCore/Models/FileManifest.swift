import Foundation

/// Entry del manifest per tracking sync con legacy filesystem
public struct FileManifestEntry: Codable, Sendable {
    public let legacyPath: String
    public let vaultFileId: String?
    public let lastKnownChecksum: String?
    public let lastKnownSize: Int64?
    public let lastKnownModified: Date?
    public let lastSyncAt: Date
    public var syncDirection: SyncDirection
    
    public init(
        legacyPath: String,
        vaultFileId: String? = nil,
        lastKnownChecksum: String? = nil,
        lastKnownSize: Int64? = nil,
        lastKnownModified: Date? = nil,
        lastSyncAt: Date = Date(),
        syncDirection: SyncDirection = .fromLegacy
    ) {
        self.legacyPath = legacyPath
        self.vaultFileId = vaultFileId
        self.lastKnownChecksum = lastKnownChecksum
        self.lastKnownSize = lastKnownSize
        self.lastKnownModified = lastKnownModified
        self.lastSyncAt = lastSyncAt
        self.syncDirection = syncDirection
    }
}

/// Direzione dell'ultima sync
public enum SyncDirection: String, Codable, Sendable {
    case fromLegacy // Import: legacy -> vault
    case toLegacy   // Export: vault -> legacy
}

/// Risultato scan legacy
public struct LegacyScanResult: Codable, Sendable {
    public let sinistroRef: String
    public let scannedAt: Date
    public let files: [LegacyFileInfo]
    
    public init(sinistroRef: String, scannedAt: Date = Date(), files: [LegacyFileInfo]) {
        self.sinistroRef = sinistroRef
        self.scannedAt = scannedAt
        self.files = files
    }
}

/// Info su file nel legacy filesystem
public struct LegacyFileInfo: Codable, Sendable {
    public let path: String
    public let size: Int64
    public let modifiedAt: Date
    public let checksum: String?
    
    public init(path: String, size: Int64, modifiedAt: Date, checksum: String? = nil) {
        self.path = path
        self.size = size
        self.modifiedAt = modifiedAt
        self.checksum = checksum
    }
}

/// Cambiamenti rilevati nel legacy
public struct LegacyChanges: Codable, Sendable {
    public let sinistroRef: String
    public let added: [String]
    public let modified: [String]
    public let deleted: [String]
    
    public init(sinistroRef: String, added: [String] = [], modified: [String] = [], deleted: [String] = []) {
        self.sinistroRef = sinistroRef
        self.added = added
        self.modified = modified
        self.deleted = deleted
    }
    
    public var isEmpty: Bool {
        added.isEmpty && modified.isEmpty && deleted.isEmpty
    }
    
    public var totalChanges: Int {
        added.count + modified.count + deleted.count
    }
}
