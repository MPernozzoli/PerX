import Foundation
import Combine

/// Gestisce il download on-demand delle cartelle sinistro via Hub/backend.
/// CloudKit rimosso: le richieste passano per il Vault del backend Supabase.
@MainActor
final class SinistroFolderCacheService: ObservableObject {

    @Published private(set) var cachedFolders: [String: CachedFolderInfo] = [:]
    @Published private(set) var downloadingFolders: Set<String> = []
    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published private(set) var lastError: String?

    static let defaultExpirationDays: Int = 3

    private let hubClient = HubAPIClient.shared
    private let userEmail: String
    private let cacheDirectory: URL
    private let metadataURL: URL

    init(userEmail: String) {
        self.userEmail = userEmail.lowercased()
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let hash = abs(userEmail.lowercased().hash)
        self.cacheDirectory = cachesDir
            .appendingPathComponent("PerX", isDirectory: true)
            .appendingPathComponent("User_\(hash)", isDirectory: true)
            .appendingPathComponent("SinistroFolders", isDirectory: true)
        self.metadataURL = cacheDirectory.appendingPathComponent("metadata.json")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        loadMetadata()
    }

    // MARK: - Public API

    func isCached(riferimento: String) -> Bool {
        guard let info = cachedFolders[riferimento] else { return false }
        return !info.isExpired && FileManager.default.fileExists(atPath: info.localPath.path)
    }

    func localPath(for riferimento: String) -> URL? {
        guard isCached(riferimento: riferimento) else { return nil }
        return cachedFolders[riferimento]?.localPath
    }

    func requestFolder(riferimento: String, keepBeyondExpiration: Bool = false) async throws -> URL {
        if let path = localPath(for: riferimento) {
            if keepBeyondExpiration, var info = cachedFolders[riferimento] {
                info.keepBeyondExpiration = true
                cachedFolders[riferimento] = info
                saveMetadata()
            }
            return path
        }
        guard !downloadingFolders.contains(riferimento) else { throw FolderError.alreadyDownloading }

        downloadingFolders.insert(riferimento)
        downloadProgress[riferimento] = 0
        defer {
            downloadingFolders.remove(riferimento)
            downloadProgress.removeValue(forKey: riferimento)
        }

        // 1. Richiesta al backend
        let requestResponse = try await hubClient.requestFolder(sinistroRef: riferimento)
        downloadProgress[riferimento] = 0.1

        // 2. Poll status
        let downloadURL = try await waitForFolder(requestId: requestResponse.requestId, riferimento: riferimento)

        // 3. Scarica e salva
        let localURL = try await downloadAndSave(from: downloadURL, riferimento: riferimento)

        let expiration = Calendar.current.date(byAdding: .day, value: Self.defaultExpirationDays, to: Date())!
        cachedFolders[riferimento] = CachedFolderInfo(
            riferimento: riferimento, localPath: localURL,
            downloadedAt: Date(), expiresAt: expiration,
            keepBeyondExpiration: keepBeyondExpiration
        )
        saveMetadata()
        print("[FolderCache] ✅ Cartella scaricata: \(riferimento)")
        return localURL
    }

    func removeFolder(riferimento: String) {
        guard let info = cachedFolders[riferimento] else { return }
        try? FileManager.default.removeItem(at: info.localPath)
        cachedFolders.removeValue(forKey: riferimento)
        saveMetadata()
    }

    func setKeepBeyondExpiration(_ keep: Bool, for riferimento: String) {
        guard var info = cachedFolders[riferimento] else { return }
        info.keepBeyondExpiration = keep
        cachedFolders[riferimento] = info
        saveMetadata()
    }

    func purgeExpiredFolders() async {
        let toRemove = cachedFolders.filter { $0.value.isExpired && !$0.value.keepBeyondExpiration }.map { $0.key }
        toRemove.forEach { removeFolder(riferimento: $0) }
        if !toRemove.isEmpty { print("[FolderCache] 🧹 Purgate \(toRemove.count) cartelle scadute") }
    }

    // MARK: - Private

    private func waitForFolder(requestId: String, riferimento: String) async throws -> URL {
        let maxAttempts = 60
        for attempt in 1...maxAttempts {
            downloadProgress[riferimento] = 0.1 + Double(attempt) / Double(maxAttempts) * 0.7
            let statusResponse = try await hubClient.checkFolderRequest(requestId: requestId)
            switch statusResponse.status {
            case "ready":
                guard let urlString = statusResponse.downloadUrl, let url = URL(string: urlString) else {
                    throw FolderError.preparationFailed("URL download mancante")
                }
                return url
            case "failed":
                throw FolderError.preparationFailed(statusResponse.errorMessage ?? "Errore sconosciuto")
            default:
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        throw FolderError.timeout
    }

    private func downloadAndSave(from url: URL, riferimento: String) async throws -> URL {
        let folderDir = cacheDirectory.appendingPathComponent(riferimento, isDirectory: true)
        try? FileManager.default.removeItem(at: folderDir)
        try FileManager.default.createDirectory(at: folderDir, withIntermediateDirectories: true)

        let (tmpURL, _) = try await URLSession.shared.download(from: url)
        let destURL = folderDir.appendingPathComponent("archive.zip")
        try FileManager.default.moveItem(at: tmpURL, to: destURL)
        downloadProgress[riferimento] = 1.0
        return folderDir
    }

    // MARK: - Metadata

    private func loadMetadata() {
        guard FileManager.default.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([String: CachedFolderInfo].self, from: data) else { return }
        cachedFolders = decoded
    }

    private func saveMetadata() {
        if let data = try? JSONEncoder().encode(cachedFolders) { try? data.write(to: metadataURL) }
    }

    // MARK: - Errors

    enum FolderError: LocalizedError {
        case alreadyDownloading, timeout, preparationFailed(String), downloadFailed

        var errorDescription: String? {
            switch self {
            case .alreadyDownloading: return "Download già in corso"
            case .timeout: return "Timeout attesa preparazione cartella"
            case .preparationFailed(let msg): return "Preparazione fallita: \(msg)"
            case .downloadFailed: return "Download cartella fallito"
            }
        }
    }
}

// MARK: - CachedFolderInfo

struct CachedFolderInfo: Codable {
    let riferimento: String
    let localPath: URL
    let downloadedAt: Date
    let expiresAt: Date
    var keepBeyondExpiration: Bool

    var isExpired: Bool { Date() > expiresAt }
    var daysUntilExpiration: Int { max(0, Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0) }
}
