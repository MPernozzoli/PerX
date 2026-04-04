import Foundation
import PerXCore
import CryptoKit

/// Manager per il Vault filesystem
public actor VaultManager {
    public static let shared = VaultManager()
    
    private var basePath: String?
    
    private init() {}
    
    /// Inizializza il VaultManager
    public func initialize(basePath: String) throws {
        self.basePath = basePath
        
        // Verifica che la directory esista
        let fm = FileManager.default
        guard fm.fileExists(atPath: basePath) else {
            throw VaultError.pathNotFound(basePath)
        }
        
        print("[VaultManager] Initialized at: \(basePath)")
    }
    
    // MARK: - Directory Operations

    private func tenantVaultPath(_ tenantSlug: String) -> String {
        "\(basePath ?? "")/tenants/\(tenantSlug)"
    }

    private func sinistriPath(for tenantSlug: String) -> String {
        "\(tenantVaultPath(tenantSlug))/sinistri"
    }
    
    /// Crea la struttura cartelle per un sinistro
    public func createSinistroFolder(sinistroRef: String, tenantSlug: String = "default") async throws {
        let sinistroPath = "\(sinistriPath(for: tenantSlug))/\(sinistroRef)"
        let fm = FileManager.default
        
        // Cartelle standard
        let folders = ["da_mail", "da_whatsapp", "documenti", "perizia", "atti", "gestione", "_export"]
        
        for folder in folders {
            let folderPath = "\(sinistroPath)/\(folder)"
            if !fm.fileExists(atPath: folderPath) {
                try fm.createDirectory(atPath: folderPath, withIntermediateDirectories: true)
            }
        }
        
        // Crea record nel DB
        let folder = SinistroFolder(tenantSlug: tenantSlug, sinistroRef: sinistroRef, status: .pending)
        try await DatabaseManager.shared.saveSinistroFolder(folder)
        
        print("[VaultManager] Created folder structure for: \(sinistroRef)")
    }
    
    /// Path assoluto per un file nel vault
    private func absolutePath(tenantSlug: String, sinistroRef: String, folder: String, filename: String) -> String {
        "\(sinistriPath(for: tenantSlug))/\(sinistroRef)/\(folder)/\(filename)"
    }
    
    /// Path relativo per un file nel vault
    private func relativePath(tenantSlug: String, sinistroRef: String, folder: String, filename: String) -> String {
        "tenants/\(tenantSlug)/sinistri/\(sinistroRef)/\(folder)/\(filename)"
    }
    
    // MARK: - File Operations
    
    /// Lista file di un sinistro
    public func listFiles(sinistroRef: String, tenantSlug: String = "default") async throws -> [VaultFile] {
        return try await DatabaseManager.shared.listVaultFiles(sinistroRef: sinistroRef, tenantSlug: tenantSlug)
    }
    
    /// Ottiene un file per ID
    public func getFile(id: String, tenantSlug: String = "default") async throws -> (VaultFile, Data) {
        guard let file = try await DatabaseManager.shared.getVaultFile(id: id, tenantSlug: tenantSlug) else {
            throw VaultError.fileNotFound(id)
        }
        
        let filePath = "\(basePath ?? "")/\(file.relativePath)"
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        
        return (file, data)
    }
    
    /// Scarica un file dal vault a un path temporaneo
    public func downloadToTemp(fileId: String, tenantSlug: String = "default") async throws -> URL {
        let (file, data) = try await getFile(id: fileId, tenantSlug: tenantSlug)
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(file.filename)
        
        try data.write(to: tempURL)
        
        return tempURL
    }
    
    /// Carica un file nel vault
    public func uploadFile(
        sinistroRef: String,
        folder: String,
        filename: String,
        data: Data,
        tenantSlug: String = "default",
        source: VaultFileSource = .upload,
        sourceId: String? = nil
    ) async throws -> VaultFile {
        // Assicura che la cartella sinistro esista
        let sinistroPath = "\(sinistriPath(for: tenantSlug))/\(sinistroRef)"
        let fm = FileManager.default
        
        if !fm.fileExists(atPath: sinistroPath) {
            try await createSinistroFolder(sinistroRef: sinistroRef, tenantSlug: tenantSlug)
        }
        
        let folderPath = "\(sinistroPath)/\(folder)"
        if !fm.fileExists(atPath: folderPath) {
            try fm.createDirectory(atPath: folderPath, withIntermediateDirectories: true)
        }
        
        // Genera filename unico se esiste già
        var finalFilename = filename
        var filePath = absolutePath(tenantSlug: tenantSlug, sinistroRef: sinistroRef, folder: folder, filename: finalFilename)
        var counter = 1
        
        while fm.fileExists(atPath: filePath) {
            let name = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            finalFilename = ext.isEmpty ? "\(name)_\(counter)" : "\(name)_\(counter).\(ext)"
            filePath = absolutePath(tenantSlug: tenantSlug, sinistroRef: sinistroRef, folder: folder, filename: finalFilename)
            counter += 1
        }
        
        // Scrivi file
        try data.write(to: URL(fileURLWithPath: filePath))
        
        // Calcola checksum
        let checksum = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        
        // Determina MIME type
        let mimeType = mimeTypeForExtension((finalFilename as NSString).pathExtension)
        
        // Crea record
        let vaultFile = VaultFile(
            id: UUID().uuidString,
            tenantSlug: tenantSlug,
            sinistroRef: sinistroRef,
            relativePath: relativePath(tenantSlug: tenantSlug, sinistroRef: sinistroRef, folder: folder, filename: finalFilename),
            filename: finalFilename,
            folder: folder,
            size: Int64(data.count),
            mimeType: mimeType,
            checksum: checksum,
            source: source,
            sourceId: sourceId,
            createdAt: Date()
        )
        
        try await DatabaseManager.shared.saveVaultFile(vaultFile)
        
        // Aggiorna stats cartella
        try await updateFolderStats(sinistroRef: sinistroRef, tenantSlug: tenantSlug)
        
        print("[VaultManager] Uploaded: \(vaultFile.relativePath) (\(data.count) bytes)")
        
        return vaultFile
    }
    
    /// Elimina un file dal vault
    public func deleteFile(id: String, tenantSlug: String = "default") async throws {
        guard let file = try await DatabaseManager.shared.getVaultFile(id: id, tenantSlug: tenantSlug) else {
            throw VaultError.fileNotFound(id)
        }
        
        let filePath = "\(basePath ?? "")/\(file.relativePath)"
        let fm = FileManager.default
        
        if fm.fileExists(atPath: filePath) {
            try fm.removeItem(atPath: filePath)
        }
        
        try await DatabaseManager.shared.deleteVaultFile(id: id, tenantSlug: tenantSlug)
        
        // Aggiorna stats cartella
        try await updateFolderStats(sinistroRef: file.sinistroRef, tenantSlug: tenantSlug)
        
        print("[VaultManager] Deleted: \(file.relativePath)")
    }
    
    /// Sposta un file nella cartella _export (per sync con legacy)
    public func moveToExport(id: String, tenantSlug: String = "default") async throws -> VaultFile {
        guard let file = try await DatabaseManager.shared.getVaultFile(id: id, tenantSlug: tenantSlug) else {
            throw VaultError.fileNotFound(id)
        }
        
        let (_, data) = try await getFile(id: id, tenantSlug: tenantSlug)
        
        // Elimina il vecchio
        try await deleteFile(id: id, tenantSlug: tenantSlug)
        
        // Crea nella cartella _export
        return try await uploadFile(
            sinistroRef: file.sinistroRef,
            folder: "_export",
            filename: file.filename,
            data: data,
            tenantSlug: tenantSlug,
            source: file.source,
            sourceId: file.sourceId
        )
    }
    
    // MARK: - Folder Stats
    
    private func updateFolderStats(sinistroRef: String, tenantSlug: String) async throws {
        let files = try await listFiles(sinistroRef: sinistroRef, tenantSlug: tenantSlug)
        let totalSize = files.reduce(0) { $0 + $1.size }
        
        var folder = try await DatabaseManager.shared.getSinistroFolder(sinistroRef: sinistroRef, tenantSlug: tenantSlug)
            ?? SinistroFolder(tenantSlug: tenantSlug, sinistroRef: sinistroRef)
        
        folder.fileCount = files.count
        folder.totalSize = totalSize
        
        try await DatabaseManager.shared.saveSinistroFolder(folder)
    }
    
    // MARK: - Helpers
    
    private func mimeTypeForExtension(_ ext: String) -> String {
        let mimeTypes: [String: String] = [
            "pdf": "application/pdf",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "gif": "image/gif",
            "txt": "text/plain",
            "html": "text/html",
            "zip": "application/zip",
            "p7m": "application/pkcs7-mime",
        ]
        
        return mimeTypes[ext.lowercased()] ?? "application/octet-stream"
    }
}

// MARK: - Errors

public enum VaultError: Error, LocalizedError {
    case notInitialized
    case pathNotFound(String)
    case fileNotFound(String)
    case fileExists(String)
    case writeError(String)
    
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "VaultManager not initialized"
        case .pathNotFound(let path):
            return "Path not found: \(path)"
        case .fileNotFound(let id):
            return "File not found: \(id)"
        case .fileExists(let path):
            return "File already exists: \(path)"
        case .writeError(let message):
            return "Write error: \(message)"
        }
    }
}
