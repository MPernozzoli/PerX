import Foundation
import Combine
#if os(macOS)
import AppKit
#endif

/// Adapter che seleziona automaticamente il servizio file corretto
/// basandosi sullo switch in HubConfigService
@MainActor
class FileManagementAdapter: ObservableObject {
    static let shared = FileManagementAdapter()
    
    // MARK: - Published
    
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var currentMode: ManagementMode
    
    // MARK: - Dependencies
    
    private let config = HubConfigService.shared
    private let vaultService = VaultService.shared
    // ClaimSyncService verrebbe iniettato qui per il mode .local
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        self.currentMode = config.fileManagementMode
        
        // Osserva cambiamenti di modalità
        config.$fileManagementMode
            .sink { [weak self] newMode in
                self?.currentMode = newMode
                print("[FileManagementAdapter] Mode changed to: \(newMode)")
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public API
    
    /// True se attualmente in modalità cloud
    var isCloudMode: Bool {
        currentMode == .cloud
    }
    
    /// Descrizione modalità attuale per UI
    var modeDescription: String {
        switch currentMode {
        case .local:
            return "I file sono gestiti localmente"
        case .cloud:
            return "I file sono gestiti dall'Hub centralizzato"
        }
    }
    
    // MARK: - File Operations
    
    /// Lista file di un sinistro
    /// - In modalità cloud: usa VaultService
    /// - In modalità locale: usa ClaimSyncService (legacy)
    func listFiles(sinistroRef: String, forceRefresh: Bool = false) async throws -> [FileItem] {
        isLoading = true
        defer { isLoading = false }
        
        switch currentMode {
        case .cloud:
            let vaultFiles = try await vaultService.listFiles(sinistroRef: sinistroRef, forceRefresh: forceRefresh)
            return vaultFiles.map { FileItem(from: $0) }
            
        case .local:
            // TODO: Implementare chiamata a ClaimSyncService esistente
            // Per ora ritorna array vuoto - in produzione qui si userebbe il servizio legacy
            return []
        }
    }
    
    /// Download file
    func downloadFile(_ item: FileItem) async throws -> URL {
        isLoading = true
        defer { isLoading = false }
        
        switch currentMode {
        case .cloud:
            guard let vaultFile = item.vaultFileDTO else {
                throw FileManagementError.invalidFileItem
            }
            return try await vaultService.downloadFile(vaultFile)
            
        case .local:
            // TODO: Implementare con ClaimSyncService
            throw FileManagementError.notImplemented
        }
    }
    
    /// Upload file
    func uploadFile(sinistroRef: String, localURL: URL, folder: String) async throws -> FileItem {
        isLoading = true
        defer { isLoading = false }
        
        switch currentMode {
        case .cloud:
            let vaultFile = try await vaultService.uploadFile(sinistroRef: sinistroRef, localURL: localURL, folder: folder)
            return FileItem(from: vaultFile)
            
        case .local:
            // TODO: Implementare con ClaimSyncService
            throw FileManagementError.notImplemented
        }
    }
    
    /// Elimina file
    func deleteFile(_ item: FileItem) async throws {
        isLoading = true
        defer { isLoading = false }
        
        switch currentMode {
        case .cloud:
            guard let vaultFile = item.vaultFileDTO else {
                throw FileManagementError.invalidFileItem
            }
            try await vaultService.deleteFile(vaultFile)
            
        case .local:
            // TODO: Implementare con ClaimSyncService
            throw FileManagementError.notImplemented
        }
    }
    
    /// Apre file in app esterna
    func openFile(_ item: FileItem) async throws {
        switch currentMode {
        case .cloud:
            guard let vaultFile = item.vaultFileDTO else {
                throw FileManagementError.invalidFileItem
            }
            try await vaultService.openFile(vaultFile)
            
        case .local:
            // Per locale, il file è già sul disco
            if let path = item.localPath {
                #if os(macOS)
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                #endif
            }
        }
    }
    
    /// Sposta file in cartella export (solo cloud)
    func moveToExport(_ item: FileItem) async throws -> FileItem {
        guard currentMode == .cloud else {
            throw FileManagementError.operationNotAvailable
        }
        
        guard let vaultFile = item.vaultFileDTO else {
            throw FileManagementError.invalidFileItem
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let movedFile = try await vaultService.moveToExport(vaultFile)
        return FileItem(from: movedFile)
    }
    
    /// Stato cartella sinistro (solo cloud)
    func getFolderStatus(sinistroRef: String) async throws -> FolderStatus {
        switch currentMode {
        case .cloud:
            let status = try await vaultService.getFolderStatus(sinistroRef: sinistroRef)
            return FolderStatus(from: status)
            
        case .local:
            // In locale non abbiamo questo concetto
            return FolderStatus(status: .ready, fileCount: 0, totalSize: 0)
        }
    }
}

// MARK: - Unified Models

/// Modello file unificato usato dall'adapter
struct FileItem: Identifiable {
    let id: String
    let filename: String
    let folder: String
    let size: Int64
    let mimeType: String?
    let createdAt: Date
    let modifiedAt: Date?
    
    // Per cloud mode
    var vaultFileDTO: VaultFileDTO?
    
    // Per local mode
    var localPath: String?
    
    init(from dto: VaultFileDTO) {
        self.id = dto.id
        self.filename = dto.filename
        self.folder = dto.folder
        self.size = dto.size
        self.mimeType = dto.mimeType
        self.createdAt = dto.createdAt
        self.modifiedAt = dto.modifiedAt
        self.vaultFileDTO = dto
        self.localPath = nil
    }
    
    init(id: String, filename: String, folder: String, size: Int64, mimeType: String?, 
         createdAt: Date, modifiedAt: Date?, localPath: String?) {
        self.id = id
        self.filename = filename
        self.folder = folder
        self.size = size
        self.mimeType = mimeType
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.vaultFileDTO = nil
        self.localPath = localPath
    }
    
    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var icon: String {
        switch mimeType?.split(separator: "/").first {
        case "image":
            return "photo"
        case "application" where filename.hasSuffix(".pdf"):
            return "doc.text"
        case "application" where filename.hasSuffix(".p7m"):
            return "signature"
        default:
            return "doc"
        }
    }
}

/// Stato cartella unificato
struct FolderStatus {
    enum Status: String {
        case pending, importing, ready, syncing, exporting, archived, error
    }
    
    let status: Status
    let fileCount: Int
    let totalSize: Int64
    let lastSyncAt: Date?
    let errorMessage: String?
    
    init(from dto: SinistroFolderDTO) {
        self.status = Status(rawValue: dto.status) ?? .ready
        self.fileCount = dto.fileCount
        self.totalSize = dto.totalSize
        self.lastSyncAt = dto.lastSyncAt
        self.errorMessage = nil
    }
    
    init(status: Status, fileCount: Int, totalSize: Int64, lastSyncAt: Date? = nil, errorMessage: String? = nil) {
        self.status = status
        self.fileCount = fileCount
        self.totalSize = totalSize
        self.lastSyncAt = lastSyncAt
        self.errorMessage = errorMessage
    }
    
    var isReady: Bool {
        status == .ready
    }
    
    var statusDescription: String {
        switch status {
        case .pending:
            return "In attesa"
        case .importing:
            return "Import in corso..."
        case .ready:
            return "Pronta"
        case .syncing:
            return "Sincronizzazione..."
        case .exporting:
            return "Export in corso..."
        case .archived:
            return "Archiviata"
        case .error:
            return errorMessage ?? "Errore"
        }
    }
}

// MARK: - Errors

enum FileManagementError: Error, LocalizedError {
    case invalidFileItem
    case notImplemented
    case operationNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidFileItem:
            return "File item non valido"
        case .notImplemented:
            return "Funzionalità non ancora implementata per questa modalità"
        case .operationNotAvailable:
            return "Operazione non disponibile in questa modalità"
        }
    }
}
