import Foundation
import AppKit
import CloudKit
import PDFKit

@MainActor
final class SignatureService: ObservableObject {
    static let shared = SignatureService()
    
    @Published var individualSignature: NSImage?
    @Published var studioSignature: NSImage?
    @Published var isLoadingStudioSignature = false
    
    private let defaults = UserDefaults.standard
    private let individualSignatureKey = "signature_individual"
    private let container: CKContainer
    
    private enum RecordType {
        static let studioSignature = "StudioSignature"
    }
    
    private enum RecordNames {
        static let studioSignature = "studio-signature"
    }
    
    private enum Keys {
        static let signatureData = "signatureData"
        static let lastSyncedAt = "lastSyncedAt"
    }
    
    private init() {
        container = CKContainer(identifier: "iCloud.it.pernozzoli.PerX")
        loadIndividualSignature()
        Task {
            await refreshIndividualSignatureFromCloud()
            await loadStudioSignature()
        }
    }
    
    // MARK: - Firma Individuale
    
    func setIndividualSignature(_ image: NSImage?) {
        guard let image = image else {
            defaults.removeObject(forKey: individualSignatureKey)
            individualSignature = nil
            if BackendAPIClient.shared.isConfigured && BackendAPIClient.shared.hasAccessToken {
                Task {
                    do {
                        try await BackendAPIClient.shared.delete("profiles/me/assets/signature_image")
                    } catch {
                        print("[SignatureService] ⚠️ Rimozione firma cloud fallita: \(error)")
                    }
                }
            }
            print("[SignatureService] 🗑️ Firma individuale rimossa")
            return
        }
        
        print("[SignatureService] 💾 Salvataggio firma individuale...")
        
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            print("[SignatureService] ❌ Errore conversione immagine in PNG")
            return
        }
        
        defaults.set(pngData, forKey: individualSignatureKey)
        individualSignature = image
        if BackendAPIClient.shared.isConfigured && BackendAPIClient.shared.hasAccessToken {
            Task {
                do {
                    let _: SignatureAssetUploadResponse = try await BackendAPIClient.shared.upload(
                        "profiles/me/assets/signature_image",
                        data: pngData,
                        fileName: "signature.png",
                        mimeType: "image/png"
                    )
                } catch {
                    print("[SignatureService] ⚠️ Upload firma cloud fallito: \(error)")
                }
            }
        }
        print("[SignatureService] ✅ Firma individuale salvata (dimensione: \(pngData.count) bytes)")
    }
    
    private func loadIndividualSignature() {
        guard let data = defaults.data(forKey: individualSignatureKey),
              let image = NSImage(data: data) else {
            individualSignature = nil
            return
        }
        individualSignature = image
    }

    private func refreshIndividualSignatureFromCloud() async {
        guard BackendAPIClient.shared.isConfigured && BackendAPIClient.shared.hasAccessToken else { return }
        do {
            let data = try await BackendAPIClient.shared.download("profiles/me/assets/signature_image")
            if let image = NSImage(data: data) {
                defaults.set(data, forKey: individualSignatureKey)
                individualSignature = image
            }
        } catch {
            print("[SignatureService] ℹ️ Nessuna firma cloud utente disponibile: \(error)")
        }
    }
    
    // MARK: - Firma Studio (CloudKit)
    
    func setStudioSignature(_ image: NSImage?) async {
        guard let image = image else {
            // Rimuovi dal CloudKit
            await deleteStudioSignature()
            studioSignature = nil
            return
        }
        
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return
        }
        
        await uploadStudioSignature(pngData)
    }
    
    private func loadStudioSignature() async {
        isLoadingStudioSignature = true
        defer { isLoadingStudioSignature = false }
        
        let publicDB = container.publicCloudDatabase
        let recordID = CKRecord.ID(recordName: RecordNames.studioSignature)
        
        do {
            if let record = try? await fetchRecordIfExists(recordID: recordID, db: publicDB),
               let asset = record[Keys.signatureData] as? CKAsset,
               let fileURL = asset.fileURL,
               let data = try? Data(contentsOf: fileURL),
               let image = NSImage(data: data) {
                studioSignature = image
            } else {
                studioSignature = nil
            }
        } catch {
            print("[SignatureService] ❌ Errore caricamento firma studio: \(error)")
            studioSignature = nil
        }
    }
    
    private func uploadStudioSignature(_ data: Data) async {
        let publicDB = container.publicCloudDatabase
        let recordID = CKRecord.ID(recordName: RecordNames.studioSignature)
        
        do {
            // Crea file temporaneo in una sottocartella dedicata per evitare conflitti
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Signatures", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempURL = tempDir.appendingPathComponent("\(UUID().uuidString).png")
            try data.write(to: tempURL)
            
            let asset = CKAsset(fileURL: tempURL)
            
            // Carica o aggiorna record
            let record: CKRecord
            do {
                if let existingRecord = try await fetchRecordIfExists(recordID: recordID, db: publicDB) {
                    record = existingRecord
                } else {
                    record = CKRecord(recordType: RecordType.studioSignature, recordID: recordID)
                }
            } catch {
                print("[SignatureService] ⚠️ Errore durante il fetch, provo a creare un nuovo record: \(error)")
                record = CKRecord(recordType: RecordType.studioSignature, recordID: recordID)
            }
            
            record[Keys.signatureData] = asset
            record[Keys.lastSyncedAt] = Date() as CKRecordValue
            
            // Usa una modifica atomica se possibile, o gestisci il conflitto
            let modifyOp = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            modifyOp.savePolicy = .changedKeys
            modifyOp.qualityOfService = .userInitiated
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                modifyOp.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                publicDB.add(modifyOp)
            }
            
            // Aggiorna immagine locale
            if let image = NSImage(data: data) {
                studioSignature = image
            }
            
            print("[SignatureService] ✅ Firma studio caricata con successo")
            
            // Rimuovi file temporaneo
            try? FileManager.default.removeItem(at: tempURL)
            
        } catch {
            print("[SignatureService] ❌ Errore upload firma studio: \(error)")
            if let ckError = error as? CKError {
                print("[SignatureService] ℹ️ Dettagli CloudKit: \(ckError.localizedDescription)")
                if let partialError = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                    for (id, error) in partialError {
                        print("[SignatureService] 🔴 Errore per \(id): \(error)")
                    }
                }
            }
        }
    }
    
    private func deleteStudioSignature() async {
        let publicDB = container.publicCloudDatabase
        let recordID = CKRecord.ID(recordName: RecordNames.studioSignature)
        
        do {
            if let record = try? await fetchRecordIfExists(recordID: recordID, db: publicDB) {
                try await publicDB.deleteRecord(withID: recordID)
                studioSignature = nil
            }
        } catch {
            print("[SignatureService] ❌ Errore eliminazione firma studio: \(error)")
        }
    }
    
    // MARK: - CloudKit Helpers
    
    private func saveRecord(_ record: CKRecord, db: CKDatabase) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            db.save(record) { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: saved ?? record)
            }
        }
    }
    
    private func fetchRecordIfExists(recordID: CKRecord.ID, db: CKDatabase) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { continuation in
            db.fetch(withRecordID: recordID) { record, error in
                if let error {
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: record)
            }
        }
    }
    
    // MARK: - Utility
    
    func getAvailableSignatures() -> [NSImage] {
        var signatures: [NSImage] = []
        if let individual = individualSignature {
            signatures.append(individual)
        }
        if let studio = studioSignature {
            signatures.append(studio)
        }
        return signatures
    }
}

private struct SignatureAssetUploadResponse: Decodable {
    let asset_type: String
    let file_name: String
    let mime_type: String?
    let size_bytes: Int
    let asset_url: String
}
