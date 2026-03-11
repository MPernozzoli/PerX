import Foundation
import PerXCore
import SQLite

/// Servizio per gestire il manifest file (tracking sync con legacy)
public actor ManifestService {
    public static let shared = ManifestService()
    
    private init() {}
    
    // MARK: - Query
    
    /// Ottiene entry del manifest per un path legacy
    public func getEntry(legacyPath: String) async throws -> FileManifestEntry? {
        let db = try await DatabaseManager.shared.db()
        let query = DatabaseSchema.fileManifest.filter(
            DatabaseSchema.FileManifestColumns.legacyPath == legacyPath
        )
        
        guard let row = try db.pluck(query) else {
            return nil
        }
        
        return entryFromRow(row)
    }
    
    /// Ottiene tutte le entry per un sinistro (basato su path prefix)
    public func getEntriesForSinistro(sinistroRef: String) async throws -> [FileManifestEntry] {
        let db = try await DatabaseManager.shared.db()
        let query = DatabaseSchema.fileManifest.filter(
            DatabaseSchema.FileManifestColumns.legacyPath.like("%/\(sinistroRef)/%")
        )
        
        return try db.prepare(query).map { entryFromRow($0) }
    }
    
    // MARK: - Update
    
    /// Salva o aggiorna entry del manifest
    public func saveEntry(_ entry: FileManifestEntry) async throws {
        let db = try await DatabaseManager.shared.db()
        
        try db.run(DatabaseSchema.fileManifest.insert(or: .replace,
            DatabaseSchema.FileManifestColumns.legacyPath <- entry.legacyPath,
            DatabaseSchema.FileManifestColumns.vaultFileId <- entry.vaultFileId,
            DatabaseSchema.FileManifestColumns.lastKnownChecksum <- entry.lastKnownChecksum,
            DatabaseSchema.FileManifestColumns.lastKnownSize <- entry.lastKnownSize,
            DatabaseSchema.FileManifestColumns.lastKnownModified <- entry.lastKnownModified?.timeIntervalSince1970,
            DatabaseSchema.FileManifestColumns.lastSyncAt <- entry.lastSyncAt.timeIntervalSince1970,
            DatabaseSchema.FileManifestColumns.syncDirection <- entry.syncDirection.rawValue
        ))
    }
    
    /// Elimina entry del manifest
    public func deleteEntry(legacyPath: String) async throws {
        let db = try await DatabaseManager.shared.db()
        let query = DatabaseSchema.fileManifest.filter(
            DatabaseSchema.FileManifestColumns.legacyPath == legacyPath
        )
        try db.run(query.delete())
    }
    
    // MARK: - Sync Detection
    
    /// Verifica se un file legacy è cambiato rispetto all'ultima sync
    public func hasFileChanged(legacyPath: String, currentChecksum: String?, currentSize: Int64?, currentModified: Date?) async throws -> Bool {
        guard let entry = try await getEntry(legacyPath: legacyPath) else {
            // Non esiste nel manifest = è nuovo
            return true
        }
        
        // Confronta checksum se disponibile
        if let current = currentChecksum, let known = entry.lastKnownChecksum {
            return current != known
        }
        
        // Fallback su size + modified date
        if let currentSize = currentSize, let knownSize = entry.lastKnownSize {
            if currentSize != knownSize {
                return true
            }
        }
        
        if let currentMod = currentModified, let knownMod = entry.lastKnownModified {
            // Tolleranza di 1 secondo per differenze di timestamp
            return abs(currentMod.timeIntervalSince(knownMod)) > 1.0
        }
        
        return false
    }
    
    /// Processa un scan result e determina i cambiamenti
    public func processLegacyScan(_ scanResult: LegacyScanResult) async throws -> LegacyChanges {
        var added: [String] = []
        var modified: [String] = []
        var deleted: [String] = []
        
        // Ottieni entry esistenti per questo sinistro
        let existingEntries = try await getEntriesForSinistro(sinistroRef: scanResult.sinistroRef)
        var existingPaths = Set(existingEntries.map { $0.legacyPath })
        
        // Controlla ogni file scanato
        for file in scanResult.files {
            if existingPaths.contains(file.path) {
                // File esistente - controlla se modificato
                let changed = try await hasFileChanged(
                    legacyPath: file.path,
                    currentChecksum: file.checksum,
                    currentSize: file.size,
                    currentModified: file.modifiedAt
                )
                if changed {
                    modified.append(file.path)
                }
                existingPaths.remove(file.path)
            } else {
                // Nuovo file
                added.append(file.path)
            }
        }
        
        // I path rimasti in existingPaths sono stati eliminati
        deleted = Array(existingPaths)
        
        return LegacyChanges(
            sinistroRef: scanResult.sinistroRef,
            added: added,
            modified: modified,
            deleted: deleted
        )
    }
    
    /// Aggiorna manifest dopo import da legacy
    public func recordImport(legacyPath: String, vaultFileId: String, checksum: String?, size: Int64, modifiedAt: Date?) async throws {
        let entry = FileManifestEntry(
            legacyPath: legacyPath,
            vaultFileId: vaultFileId,
            lastKnownChecksum: checksum,
            lastKnownSize: size,
            lastKnownModified: modifiedAt,
            lastSyncAt: Date(),
            syncDirection: .fromLegacy
        )
        try await saveEntry(entry)
    }
    
    /// Aggiorna manifest dopo export a legacy
    public func recordExport(legacyPath: String, vaultFileId: String, checksum: String?, size: Int64) async throws {
        let entry = FileManifestEntry(
            legacyPath: legacyPath,
            vaultFileId: vaultFileId,
            lastKnownChecksum: checksum,
            lastKnownSize: size,
            lastKnownModified: Date(),
            lastSyncAt: Date(),
            syncDirection: .toLegacy
        )
        try await saveEntry(entry)
    }
    
    // MARK: - Compare With Scan (per SyncAgent)
    
    public struct ScannedFile {
        public let path: String
        public let relativePath: String
        public let size: Int64
        public let modifiedAt: Date?
        
        public init(path: String, relativePath: String, size: Int64, modifiedAt: Date?) {
            self.path = path
            self.relativePath = relativePath
            self.size = size
            self.modifiedAt = modifiedAt
        }
    }
    
    public struct ScanChanges {
        public let newFiles: [String]
        public let modifiedFiles: [String]
        public let deletedFiles: [String]
    }
    
    /// Confronta risultato scan con manifest esistente
    public func compareWithScan(sinistroRef: String, files: [ScannedFile]) async throws -> ScanChanges {
        var newFiles: [String] = []
        var modifiedFiles: [String] = []
        var deletedFiles: [String] = []
        
        // Ottieni entry esistenti per questo sinistro
        let existingEntries = try await getEntriesForSinistro(sinistroRef: sinistroRef)
        var existingPaths = Set(existingEntries.map { $0.legacyPath })
        
        // Controlla ogni file scanato
        for file in files {
            if existingPaths.contains(file.path) {
                // File esistente - controlla se modificato
                let changed = try await hasFileChanged(
                    legacyPath: file.path,
                    currentChecksum: nil,
                    currentSize: file.size,
                    currentModified: file.modifiedAt
                )
                if changed {
                    modifiedFiles.append(file.path)
                }
                existingPaths.remove(file.path)
            } else {
                // Nuovo file
                newFiles.append(file.path)
            }
        }
        
        // I path rimasti in existingPaths sono stati eliminati
        deletedFiles = Array(existingPaths)
        
        return ScanChanges(newFiles: newFiles, modifiedFiles: modifiedFiles, deletedFiles: deletedFiles)
    }
    
    // MARK: - Helpers
    
    private func entryFromRow(_ row: Row) -> FileManifestEntry {
        FileManifestEntry(
            legacyPath: row[DatabaseSchema.FileManifestColumns.legacyPath],
            vaultFileId: row[DatabaseSchema.FileManifestColumns.vaultFileId],
            lastKnownChecksum: row[DatabaseSchema.FileManifestColumns.lastKnownChecksum],
            lastKnownSize: row[DatabaseSchema.FileManifestColumns.lastKnownSize],
            lastKnownModified: row[DatabaseSchema.FileManifestColumns.lastKnownModified].map { Date(timeIntervalSince1970: $0) },
            lastSyncAt: Date(timeIntervalSince1970: row[DatabaseSchema.FileManifestColumns.lastSyncAt]),
            syncDirection: SyncDirection(rawValue: row[DatabaseSchema.FileManifestColumns.syncDirection]) ?? .fromLegacy
        )
    }
}
