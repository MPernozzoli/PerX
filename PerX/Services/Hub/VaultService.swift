import Foundation
import Combine
#if os(macOS)
import AppKit
#endif

/// Servizio per accesso ai file tramite Vault Hub
/// Sostituisce ClaimSyncService quando lo switch è su "cloud"
@MainActor
class VaultService: ObservableObject {
    static let shared = VaultService()
    
    // MARK: - Published Properties
    
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    
    // MARK: - Dependencies
    
    private let api = HubAPIClient.shared
    private let config = HubConfigService.shared
    private let cache = VaultFileCache.shared
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Lista file di un sinistro (con cache)
    func listFiles(sinistroRef: String, forceRefresh: Bool = false) async throws -> [VaultFileDTO] {
        // Controlla se dobbiamo usare l'Hub
        guard config.fileManagementMode == .cloud else {
            throw VaultServiceError.notInCloudMode
        }
        
        // Prova cache
        if !forceRefresh, let cached = cache.getCachedFileList(sinistroRef: sinistroRef) {
            return cached
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let files = try await api.listFiles(sinistroRef: sinistroRef)
            cache.cacheFileList(sinistroRef: sinistroRef, files: files)
            lastError = nil
            return files
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
    
    /// Stato cartella sinistro
    func getFolderStatus(sinistroRef: String) async throws -> SinistroFolderDTO {
        guard config.fileManagementMode == .cloud else {
            throw VaultServiceError.notInCloudMode
        }
        
        return try await api.getSinistroFolderStatus(sinistroRef: sinistroRef)
    }
    
    /// Crea cartella sinistro nel Vault
    func createFolder(sinistroRef: String) async throws -> SinistroFolderDTO {
        guard config.fileManagementMode == .cloud else {
            throw VaultServiceError.notInCloudMode
        }
        
        isLoading = true
        defer { isLoading = false }
        
        return try await api.createSinistroFolder(sinistroRef: sinistroRef)
    }
    
    /// Download file (con cache locale)
    func downloadFile(_ file: VaultFileDTO) async throws -> URL {
        guard config.fileManagementMode == .cloud else {
            throw VaultServiceError.notInCloudMode
        }
        
        // Controlla cache locale
        if let cachedURL = cache.getCachedFile(fileId: file.id),
           cache.isValid(fileId: file.id, checksum: file.checksum) {
            return cachedURL
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Download da Hub
        let data = try await api.downloadFile(fileId: file.id)
        
        // Salva in cache
        let localURL = cache.store(fileId: file.id, filename: file.filename, data: data, checksum: file.checksum)
        
        return localURL
    }
    
    /// Upload file al Vault
    func uploadFile(sinistroRef: String, localURL: URL, folder: String) async throws -> VaultFileDTO {
        guard config.fileManagementMode == .cloud else {
            throw VaultServiceError.notInCloudMode
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let data = try Data(contentsOf: localURL)
        let filename = localURL.lastPathComponent
        
        let file = try await api.uploadFile(
            sinistroRef: sinistroRef,
            filename: filename,
            folder: folder,
            data: data
        )
        
        // Invalida cache lista
        cache.invalidateFileList(sinistroRef: sinistroRef)
        
        return file
    }
    
    /// Elimina file dal Vault
    func deleteFile(_ file: VaultFileDTO) async throws {
        guard config.fileManagementMode == .cloud else {
            throw VaultServiceError.notInCloudMode
        }
        
        isLoading = true
        defer { isLoading = false }
        
        try await api.deleteFile(fileId: file.id)
        
        // Rimuovi da cache
        cache.removeCachedFile(fileId: file.id)
        cache.invalidateFileList(sinistroRef: file.sinistroRef)
    }
    
    /// Sposta file in cartella _export (per sync verso legacy)
    func moveToExport(_ file: VaultFileDTO) async throws -> VaultFileDTO {
        guard config.fileManagementMode == .cloud else {
            throw VaultServiceError.notInCloudMode
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let movedFile = try await api.moveToExport(fileId: file.id)
        cache.invalidateFileList(sinistroRef: file.sinistroRef)
        
        return movedFile
    }
    
    /// Apre file in app esterna
    func openFile(_ file: VaultFileDTO) async throws {
        let localURL = try await downloadFile(file)
        
        #if os(macOS)
        NSWorkspace.shared.open(localURL)
        #endif
    }
    
    /// Richiede import cartella da legacy
    func requestImportFromLegacy(sinistroRef: String, legacyPath: String) async throws -> JobDTO {
        guard config.fileManagementMode == .cloud else {
            throw VaultServiceError.notInCloudMode
        }
        
        return try await api.createImportFolderJob(sinistroRef: sinistroRef, legacyPath: legacyPath)
    }
}

// MARK: - Errors

enum VaultServiceError: Error, LocalizedError {
    case notInCloudMode
    case fileNotCached
    
    var errorDescription: String? {
        switch self {
        case .notInCloudMode:
            return "La gestione file non è in modalità cloud"
        case .fileNotCached:
            return "File non presente in cache"
        }
    }
}

// MARK: - File Cache

/// Cache locale per file scaricati dal Vault
class VaultFileCache {
    static let shared = VaultFileCache()
    
    private let cacheDir: URL
    private let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500 MB
    
    private var fileListCache: [String: (files: [VaultFileDTO], cachedAt: Date)] = [:]
    private var fileChecksums: [String: String] = [:] // fileId -> checksum
    
    private init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = cachesDir.appendingPathComponent("PerXVaultCache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }
    
    // MARK: - File List Cache
    
    func getCachedFileList(sinistroRef: String) -> [VaultFileDTO]? {
        guard let cached = fileListCache[sinistroRef] else { return nil }
        
        // Cache valida per 60 secondi
        if Date().timeIntervalSince(cached.cachedAt) < 60 {
            return cached.files
        }
        
        return nil
    }
    
    func cacheFileList(sinistroRef: String, files: [VaultFileDTO]) {
        fileListCache[sinistroRef] = (files, Date())
    }
    
    func invalidateFileList(sinistroRef: String) {
        fileListCache.removeValue(forKey: sinistroRef)
    }
    
    // MARK: - File Cache
    
    func getCachedFile(fileId: String) -> URL? {
        let fileURL = cacheDir.appendingPathComponent(fileId)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }
    
    func isValid(fileId: String, checksum: String?) -> Bool {
        guard let cached = fileChecksums[fileId], let check = checksum else {
            return false
        }
        return cached == check
    }
    
    func store(fileId: String, filename: String, data: Data, checksum: String?) -> URL {
        let fileURL = cacheDir.appendingPathComponent(fileId)
        try? data.write(to: fileURL)
        
        if let checksum = checksum {
            fileChecksums[fileId] = checksum
        }
        
        // Pulizia cache se troppo grande
        Task {
            await cleanupIfNeeded()
        }
        
        return fileURL
    }
    
    func removeCachedFile(fileId: String) {
        let fileURL = cacheDir.appendingPathComponent(fileId)
        try? FileManager.default.removeItem(at: fileURL)
        fileChecksums.removeValue(forKey: fileId)
    }
    
    // MARK: - Cleanup
    
    private func cleanupIfNeeded() async {
        let fm = FileManager.default
        
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey]) else {
            return
        }
        
        var totalSize: Int64 = 0
        var fileInfos: [(url: URL, size: Int64, accessed: Date)] = []
        
        for file in files {
            guard let resourceValues = try? file.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey]),
                  let size = resourceValues.fileSize,
                  let accessed = resourceValues.contentAccessDate else {
                continue
            }
            
            totalSize += Int64(size)
            fileInfos.append((file, Int64(size), accessed))
        }
        
        // Se supera il limite, elimina i file più vecchi
        if totalSize > maxCacheSize {
            let sorted = fileInfos.sorted { $0.accessed < $1.accessed }
            var freed: Int64 = 0
            let target = totalSize - (maxCacheSize / 2) // Libera fino a metà del limite
            
            for info in sorted {
                if freed >= target { break }
                try? fm.removeItem(at: info.url)
                freed += info.size
                
                // Rimuovi anche dal dizionario checksum
                let fileId = info.url.lastPathComponent
                fileChecksums.removeValue(forKey: fileId)
            }
        }
    }
}
