import Foundation

// MARK: - Manifest & Metadata

/// Manifest completo restituito da GET /api/claims/{claim_id}/metadata
struct ClaimMetadata: Codable {
    let userId: String
    let claimId: String
    let totalFiles: Int
    let totalBytes: Int
    let directoryCount: Int
    let relativeRoot: String
    /// Lista file con hash per sync differenziale
    let files: [ClaimFileEntry]?
    /// Lista cartelle (incluse quelle vuote) per creazione struttura
    let directories: [String]?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case claimId = "claim_id"
        case totalFiles = "total_files"
        case totalBytes = "total_bytes"
        case directoryCount = "directory_count"
        case relativeRoot = "relative_root"
        case files
        case directories
    }
}

/// Singolo file nel manifest per sync differenziale
struct ClaimFileEntry: Codable, Hashable {
    let relativePath: String
    let size: Int64
    let md5: String
    let modifiedAt: Date?
    
    // Pydantic v1 serializza i campi Python usando i nomi esatti.
    // I campi Python sono `relativePath` e `modifiedAt` (camelCase),
    // quindi Pydantic serializza in camelCase, non snake_case.
    // Nessun CodingKeys necessario: Swift usa i nomi delle proprietà per default.
}

// MARK: - API Responses

struct GenericAPIResponse: Codable {
    let success: Bool
    let message: String
    let details: [String: String]?
}

/// Risposta health check - GET /health
struct HealthCheckResponse: Codable {
    let status: String
    let version: String?
    let uptime: Double?
}

// MARK: - Download Progress Info

/// Informazioni dettagliate sul progresso del download
struct DownloadProgressInfo: Equatable {
    let progress: Double           // 0.0 - 1.0 (solo fase download effettivo)
    let overallProgress: Double    // 0.0 - 1.0 (progresso totale includendo tutte le fasi)
    let bytesDownloaded: Int64
    let bytesTotal: Int64
    let bytesPerSecond: Double     // Velocità download
    
    /// Dimensione scaricata formattata
    var downloadedFormatted: String {
        ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
    }
    
    /// Dimensione totale formattata
    var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: bytesTotal, countStyle: .file)
    }
    
    /// Velocità formattata (es. "2.5 MB/s")
    var speedFormatted: String {
        let speed = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file)
        return "\(speed)/s"
    }
    
    static let zero = DownloadProgressInfo(progress: 0, overallProgress: 0, bytesDownloaded: 0, bytesTotal: 0, bytesPerSecond: 0)
}

// MARK: - Sync Status

enum ClaimSyncStatus: Equatable {
    case notDownloaded                      // Cartella non esiste localmente
    case notSynced                          // Cartella esiste ma mai sincronizzata
    case registering                        // 0-10%: contatto server
    case fetchingMetadata                   // parte del 10%
    case comparing                          // Confronto manifest con cache locale
    case downloading(info: DownloadProgressInfo)  // 10-90%: download effettivo con info dettagliate
    case downloadingFile(name: String, current: Int, total: Int)
    case extracting(progress: Double)       // 90-100%: decompressione
    case uploading(progress: Double)
    case uploadingFile(name: String, current: Int, total: Int)
    case upToDate
    case error(String)
    
    var isActive: Bool {
        switch self {
        case .registering, .fetchingMetadata, .comparing,
             .downloading, .downloadingFile, .extracting, .uploading, .uploadingFile:
            return true
        default:
            return false
        }
    }
}

// MARK: - Local Cache

/// Cache locale del manifest per confronto.
/// - files: vista server (o override per keep-local).
/// - localSnapshot: stato locale all’ultima sync (path+hash) per detect delete/move.
struct LocalManifestCache: Codable {
    let claimId: String
    let lastSync: Date
    let files: [ClaimFileEntry]
    /// Path → hash (e modifiedAt) che avevamo localmente all’ultima sync. Usato per eliminazioni e spostamenti.
    let localSnapshot: [ClaimFileEntry]?
    
    init(claimId: String, lastSync: Date, files: [ClaimFileEntry], localSnapshot: [ClaimFileEntry]? = nil) {
        self.claimId = claimId
        self.lastSync = lastSync
        self.files = files
        self.localSnapshot = localSnapshot
    }
    
    enum CodingKeys: String, CodingKey {
        case claimId, lastSync, files, localSnapshot
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        claimId = try c.decode(String.self, forKey: .claimId)
        lastSync = try c.decode(Date.self, forKey: .lastSync)
        files = try c.decode([ClaimFileEntry].self, forKey: .files)
        localSnapshot = try c.decodeIfPresent([ClaimFileEntry].self, forKey: .localSnapshot)
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(claimId, forKey: .claimId)
        try c.encode(lastSync, forKey: .lastSync)
        try c.encode(files, forKey: .files)
        try c.encodeIfPresent(localSnapshot, forKey: .localSnapshot)
    }
}

