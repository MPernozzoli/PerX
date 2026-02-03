//
//  CloudKitFolderPackagerService.swift
//  PerX (Mac)
//
//  Worker che processa le richieste di cartelle sinistro da iPad.
//  Monitora CloudKit per nuove richieste, crea lo ZIP e lo carica come CKAsset.
//

import Foundation
import CloudKit

@MainActor
final class CloudKitFolderPackagerService: ObservableObject {
    static let shared = CloudKitFolderPackagerService()
    
    // MARK: - Published State
    
    @Published private(set) var isRunning = false
    @Published private(set) var processedCount = 0
    @Published private(set) var lastError: String?
    
    // MARK: - Dependencies
    
    private let container: CKContainer
    private let publicDB: CKDatabase
    private var pollTimer: Timer?
    
    private let pollInterval: TimeInterval = 30
    
    // MARK: - Record Types
    
    private enum RecordType {
        static let folderRequest = "SinistroFolderRequest"
        static let folderPackage = "SinistroFolderPackage"
    }
    
    // MARK: - Init
    
    private init(container: CKContainer = CKContainer(identifier: "iCloud.it.pernozzoli.PerX")) {
        self.container = container
        self.publicDB = container.publicCloudDatabase
    }
    
    // MARK: - Lifecycle
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        print("[FolderPackager] ▶️ Avvio worker")
        startPolling()
        
        Task { await processPendingRequests() }
    }
    
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        isRunning = false
        print("[FolderPackager] ⏹️ Worker stoppato")
    }
    
    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processPendingRequests()
            }
        }
    }
    
    // MARK: - Processing
    
    private func processPendingRequests() async {
        do {
            let predicate = NSPredicate(format: "status == %@", "pending")
            let query = CKQuery(recordType: RecordType.folderRequest, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "requestedAt", ascending: true)]
            
            let records = try await performQuery(query)
            
            for record in records {
                await processRequest(record)
            }
            
        } catch {
            lastError = error.localizedDescription
            print("[FolderPackager] ❌ Errore fetch requests: \(error)")
        }
    }
    
    private func processRequest(_ record: CKRecord) async {
        let requestId = record["requestId"] as? String ?? record.recordID.recordName
        let riferimento = record["sinistroRiferimento"] as? String ?? ""
        
        print("[FolderPackager] 📦 Processando request: \(requestId) per \(riferimento)")
        
        // 1. Aggiorna status a "processing"
        record["status"] = "processing" as CKRecordValue
        record["processedBy"] = (GoogleAuthService.shared.userEmail ?? "mac-packager") as CKRecordValue
        
        do {
            _ = try await saveRecord(record)
        } catch {
            return
        }
        
        // 2. Trova la cartella locale del sinistro
        guard let folderPath = findSinistroFolder(riferimento: riferimento) else {
            await markRequestFailed(record, requestId: requestId, error: "Cartella sinistro non trovata")
            return
        }
        
        // 3. Crea ZIP
        let zipURL: URL
        do {
            zipURL = try createZipArchive(from: folderPath, riferimento: riferimento)
        } catch {
            await markRequestFailed(record, requestId: requestId, error: "Errore creazione ZIP: \(error.localizedDescription)")
            return
        }
        
        // 4. Crea package con CKAsset
        do {
            let packageRecord = CKRecord(recordType: RecordType.folderPackage, recordID: CKRecord.ID(recordName: "pkg_\(requestId)"))
            packageRecord["requestId"] = requestId as CKRecordValue
            packageRecord["sinistroRiferimento"] = riferimento as CKRecordValue
            packageRecord["status"] = "ready" as CKRecordValue
            packageRecord["createdAt"] = Date() as CKRecordValue
            packageRecord["createdBy"] = (GoogleAuthService.shared.userEmail ?? "mac") as CKRecordValue
            packageRecord["zipAsset"] = CKAsset(fileURL: zipURL)
            
            // Scadenza: 24 ore (iPad deve scaricare entro questo tempo)
            let expiresAt = Calendar.current.date(byAdding: .hour, value: 24, to: Date())!
            packageRecord["expiresAt"] = expiresAt as CKRecordValue
            
            _ = try await saveRecord(packageRecord)
            
            // 5. Aggiorna request a "completed"
            record["status"] = "completed" as CKRecordValue
            record["completedAt"] = Date() as CKRecordValue
            _ = try await saveRecord(record)
            
            processedCount += 1
            print("[FolderPackager] ✅ Package creato: \(requestId)")
            
            // 6. Cleanup ZIP temporaneo
            try? FileManager.default.removeItem(at: zipURL)
            
        } catch {
            await markRequestFailed(record, requestId: requestId, error: "Errore upload: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: zipURL)
        }
    }
    
    private func markRequestFailed(_ record: CKRecord, requestId: String, error: String) async {
        record["status"] = "failed" as CKRecordValue
        record["errorMessage"] = error as CKRecordValue
        record["completedAt"] = Date() as CKRecordValue
        
        try? await saveRecord(record)
        
        // Crea anche un package record con status failed
        let packageRecord = CKRecord(recordType: RecordType.folderPackage, recordID: CKRecord.ID(recordName: "pkg_\(requestId)"))
        packageRecord["requestId"] = requestId as CKRecordValue
        packageRecord["status"] = "failed" as CKRecordValue
        packageRecord["errorMessage"] = error as CKRecordValue
        packageRecord["createdAt"] = Date() as CKRecordValue
        
        try? await saveRecord(packageRecord)
        
        lastError = error
        print("[FolderPackager] ❌ Request fallita: \(requestId) - \(error)")
    }
    
    private func findSinistroFolder(riferimento: String) -> URL? {
        // Prova a trovare la cartella del sinistro nel percorso configurato
        // 1. Controlla UserDefaults per il path base
        guard let basePath = UserDefaults.standard.string(forKey: "sinistroBasePath"),
              !basePath.isEmpty else {
            print("[FolderPackager] ⚠️ sinistroBasePath non configurato")
            return nil
        }
        
        let baseURL = URL(fileURLWithPath: basePath)
        
        // 2. Pattern tipici: basePath/2024/riferimento, basePath/riferimento, ecc.
        let possiblePaths = [
            baseURL.appendingPathComponent(riferimento),
            baseURL.appendingPathComponent(String(riferimento.prefix(4))).appendingPathComponent(riferimento),
            baseURL.appendingPathComponent("Sinistri").appendingPathComponent(riferimento)
        ]
        
        for path in possiblePaths {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir), isDir.boolValue {
                return path
            }
        }
        
        // 3. Cerca ricorsivamente (più lento, usa solo se necessario)
        if let found = findFolderRecursively(in: baseURL, named: riferimento) {
            return found
        }
        
        return nil
    }
    
    private func findFolderRecursively(in directory: URL, named name: String, maxDepth: Int = 3) -> URL? {
        guard maxDepth > 0 else { return nil }
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        
        for item in contents {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            
            if item.lastPathComponent == name {
                return item
            }
            
            // Cerca ricorsivamente
            if let found = findFolderRecursively(in: item, named: name, maxDepth: maxDepth - 1) {
                return found
            }
        }
        
        return nil
    }
    
    private func createZipArchive(from folder: URL, riferimento: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let zipURL = tempDir.appendingPathComponent("\(riferimento)_\(Date().timeIntervalSince1970).zip")
        
        // Usa Process per chiamare zip (più affidabile per cartelle grandi)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-q", zipURL.path, "."]
        process.currentDirectoryURL = folder
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "FolderPackager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "zip command failed"])
        }
        
        return zipURL
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
}
