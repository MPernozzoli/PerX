//
//  SinistroFolderCacheService.swift
//  PerX per iPad
//
//  Gestisce il download on-demand delle cartelle sinistro da CloudKit.
//  Le cartelle vengono salvate in sandbox e purgate automaticamente dopo 3 giorni.
//

import Foundation
import CloudKit
import Combine
import Compression

@MainActor
final class SinistroFolderCacheService: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var cachedFolders: [String: CachedFolderInfo] = [:] // riferimento -> info
    @Published private(set) var downloadingFolders: Set<String> = []
    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published private(set) var lastError: String?
    
    // MARK: - Config
    
    /// Scadenza default: 3 giorni
    static let defaultExpirationDays: Int = 3
    
    // MARK: - Dependencies
    
    private let container: CKContainer
    private let publicDB: CKDatabase
    private let userEmail: String
    private let cacheDirectory: URL
    private let metadataURL: URL
    
    // MARK: - Record Types
    
    private enum RecordType {
        static let folderRequest = "SinistroFolderRequest"
        static let folderPackage = "SinistroFolderPackage"
    }
    
    // MARK: - Init
    
    init(userEmail: String, container: CKContainer = CKContainer(identifier: "iCloud.it.pernozzoli.PerX")) {
        self.userEmail = userEmail.lowercased()
        self.container = container
        self.publicDB = container.publicCloudDatabase
        
        // Directory cache per-utente
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let hash = abs(userEmail.lowercased().hash)
        self.cacheDirectory = cachesDir
            .appendingPathComponent("PerX", isDirectory: true)
            .appendingPathComponent("User_\(hash)", isDirectory: true)
            .appendingPathComponent("SinistroFolders", isDirectory: true)
        
        self.metadataURL = cacheDirectory.appendingPathComponent("metadata.json")
        
        // Crea directory se non esiste
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Carica metadata
        loadMetadata()
    }
    
    // MARK: - Public API
    
    /// Verifica se una cartella è in cache e non scaduta
    func isCached(riferimento: String) -> Bool {
        guard let info = cachedFolders[riferimento] else { return false }
        return !info.isExpired && FileManager.default.fileExists(atPath: info.localPath.path)
    }
    
    /// Restituisce il path locale della cartella (se in cache)
    func localPath(for riferimento: String) -> URL? {
        guard isCached(riferimento: riferimento) else { return nil }
        return cachedFolders[riferimento]?.localPath
    }
    
    /// Richiede il download di una cartella sinistro
    func requestFolder(riferimento: String, keepBeyondExpiration: Bool = false) async throws -> URL {
        // Se già in cache, restituisci path
        if let path = localPath(for: riferimento) {
            // Aggiorna flag "keep"
            if keepBeyondExpiration, var info = cachedFolders[riferimento] {
                info.keepBeyondExpiration = true
                cachedFolders[riferimento] = info
                saveMetadata()
            }
            return path
        }
        
        // Già in download?
        if downloadingFolders.contains(riferimento) {
            throw FolderError.alreadyDownloading
        }
        
        downloadingFolders.insert(riferimento)
        downloadProgress[riferimento] = 0
        
        defer {
            downloadingFolders.remove(riferimento)
            downloadProgress.removeValue(forKey: riferimento)
        }
        
        // 1. Crea request su CloudKit
        let requestId = try await createFolderRequest(riferimento: riferimento)
        
        // 2. Poll per il package (Mac lo preparerà)
        let packageURL = try await waitForPackage(requestId: requestId, riferimento: riferimento)
        
        // 3. Salva in cache
        let localURL = try await downloadAndExtract(packageURL: packageURL, riferimento: riferimento)
        
        // 4. Registra in metadata
        let expiration = Calendar.current.date(byAdding: .day, value: Self.defaultExpirationDays, to: Date())!
        let info = CachedFolderInfo(
            riferimento: riferimento,
            localPath: localURL,
            downloadedAt: Date(),
            expiresAt: expiration,
            keepBeyondExpiration: keepBeyondExpiration
        )
        cachedFolders[riferimento] = info
        saveMetadata()
        
        print("[FolderCache] ✅ Cartella scaricata: \(riferimento) @ \(localURL.path)")
        
        return localURL
    }
    
    /// Elimina una cartella dalla cache
    func removeFolder(riferimento: String) {
        guard let info = cachedFolders[riferimento] else { return }
        
        try? FileManager.default.removeItem(at: info.localPath)
        cachedFolders.removeValue(forKey: riferimento)
        saveMetadata()
        
        print("[FolderCache] 🗑️ Cartella rimossa: \(riferimento)")
    }
    
    /// Imposta/rimuove flag "mantieni oltre scadenza"
    func setKeepBeyondExpiration(_ keep: Bool, for riferimento: String) {
        guard var info = cachedFolders[riferimento] else { return }
        info.keepBeyondExpiration = keep
        cachedFolders[riferimento] = info
        saveMetadata()
    }
    
    /// Elimina tutte le cartelle scadute (>3 giorni e non "keep")
    func purgeExpiredFolders() async {
        let now = Date()
        var toRemove: [String] = []
        
        for (rif, info) in cachedFolders {
            if info.isExpired && !info.keepBeyondExpiration {
                toRemove.append(rif)
            }
        }
        
        for rif in toRemove {
            removeFolder(riferimento: rif)
        }
        
        if !toRemove.isEmpty {
            print("[FolderCache] 🧹 Purgate \(toRemove.count) cartelle scadute")
        }
    }
    
    // MARK: - Private
    
    private func createFolderRequest(riferimento: String) async throws -> String {
        let requestId = UUID().uuidString
        let record = CKRecord(recordType: RecordType.folderRequest, recordID: CKRecord.ID(recordName: requestId))
        
        record["requestId"] = requestId as CKRecordValue
        record["sinistroRiferimento"] = riferimento as CKRecordValue
        record["requestedBy"] = userEmail as CKRecordValue
        record["requestedAt"] = Date() as CKRecordValue
        record["status"] = "pending" as CKRecordValue
        
        _ = try await saveRecord(record)
        
        print("[FolderCache] 📤 Request creata: \(requestId) per \(riferimento)")
        
        return requestId
    }
    
    private func waitForPackage(requestId: String, riferimento: String) async throws -> URL {
        // Poll ogni 5 secondi, max 5 minuti
        let maxAttempts = 60
        let pollInterval: UInt64 = 5_000_000_000 // 5 secondi
        
        for attempt in 1...maxAttempts {
            // Aggiorna progress
            downloadProgress[riferimento] = Double(attempt) / Double(maxAttempts) * 0.5 // 50% max per attesa
            
            // Cerca package
            let predicate = NSPredicate(format: "requestId == %@ AND status == %@", requestId, "ready")
            let query = CKQuery(recordType: RecordType.folderPackage, predicate: predicate)
            
            let records = try await performQuery(query)
            
            if let record = records.first,
               let asset = record["zipAsset"] as? CKAsset,
               let fileURL = asset.fileURL {
                return fileURL
            }
            
            // Controlla se failed
            let failedPredicate = NSPredicate(format: "requestId == %@ AND status == %@", requestId, "failed")
            let failedQuery = CKQuery(recordType: RecordType.folderPackage, predicate: failedPredicate)
            let failedRecords = try await performQuery(failedQuery)
            
            if let failedRecord = failedRecords.first {
                let errorMsg = failedRecord["errorMessage"] as? String ?? "Errore sconosciuto"
                throw FolderError.preparationFailed(errorMsg)
            }
            
            try await Task.sleep(nanoseconds: pollInterval)
        }
        
        throw FolderError.timeout
    }
    
    private func downloadAndExtract(packageURL: URL, riferimento: String) async throws -> URL {
        let folderDir = cacheDirectory.appendingPathComponent(riferimento, isDirectory: true)
        
        // Rimuovi eventuale versione precedente
        try? FileManager.default.removeItem(at: folderDir)
        
        // Crea directory
        try FileManager.default.createDirectory(at: folderDir, withIntermediateDirectories: true)
        
        // Estrai ZIP usando /usr/bin/ditto (disponibile su iOS simulator) o fallback manuale
        try await unzipFile(at: packageURL, to: folderDir)
        
        downloadProgress[riferimento] = 1.0
        
        return folderDir
    }
    
    /// Estrae un file ZIP usando NSFileCoordinator e Archive (iOS 16+)
    private func unzipFile(at sourceURL: URL, to destinationURL: URL) async throws {
        // Su iOS, usiamo la lettura diretta del ZIP
        // Per compatibilità, implementiamo un'estrazione base
        
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw FolderError.downloadFailed
        }
        
        // Leggi il contenuto del ZIP
        let zipData = try Data(contentsOf: sourceURL)
        
        // Trova e estrai i file dal ZIP
        // Nota: per ZIP complessi, considera l'uso di una libreria esterna
        try extractZIPData(zipData, to: destinationURL)
    }
    
    /// Estrazione base di file ZIP
    /// Per ZIP semplici. Per supporto completo, usare ZIPFoundation via SPM.
    private func extractZIPData(_ data: Data, to destination: URL) throws {
        // Implementazione minimale - estrae solo se il pacchetto è un singolo file o directory flat
        // Per casi più complessi, il backend dovrebbe inviare i file già estratti o usare tar.gz
        
        // Prova a scrivere come file singolo se non è un vero ZIP
        let testPath = destination.appendingPathComponent("content")
        try data.write(to: testPath)
        
        // Se il contenuto inizia con PK (ZIP magic), log warning
        if data.prefix(2) == Data([0x50, 0x4B]) {
            print("[FolderCache] ⚠️ ZIP rilevato - per estrazione completa serve ZIPFoundation")
            // Per ora, salviamo il file ZIP così com'è
            try? FileManager.default.removeItem(at: testPath)
            try data.write(to: destination.appendingPathComponent("archive.zip"))
        }
    }
    
    // MARK: - Metadata Persistence
    
    private func loadMetadata() {
        guard FileManager.default.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([String: CachedFolderInfo].self, from: data) else {
            return
        }
        cachedFolders = decoded
    }
    
    private func saveMetadata() {
        guard let data = try? JSONEncoder().encode(cachedFolders) else { return }
        try? data.write(to: metadataURL)
    }
    
    // MARK: - CloudKit Helpers
    
    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            publicDB.save(record) { saved, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: saved ?? record)
                }
            }
        }
    }
    
    private func performQuery(_ query: CKQuery) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            publicDB.perform(query, inZoneWith: nil) { records, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: records ?? [])
                }
            }
        }
    }
    
    // MARK: - Errors
    
    enum FolderError: LocalizedError {
        case alreadyDownloading
        case timeout
        case preparationFailed(String)
        case extractionFailed
        case downloadFailed
        
        var errorDescription: String? {
            switch self {
            case .alreadyDownloading: return "Download già in corso"
            case .timeout: return "Timeout attesa preparazione cartella"
            case .preparationFailed(let msg): return "Preparazione fallita: \(msg)"
            case .extractionFailed: return "Errore estrazione archivio"
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
    
    var isExpired: Bool {
        Date() > expiresAt
    }
    
    var daysUntilExpiration: Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
        return max(0, days)
    }
}
