import Foundation
import AppKit
import PDFKit

@MainActor
final class SignatureService: ObservableObject {
    static let shared = SignatureService()
    
    @Published var individualSignature: NSImage?
    @Published var studioSignature: NSImage?
    @Published var isLoadingStudioSignature = false
    
    private let defaults = UserDefaults.standard
    private let individualSignatureKey = "signature_individual"
    private let studioSignatureKey = "signature_studio"
    
    private init() {
        loadIndividualSignature()
        loadStudioSignatureFromLocalCache()
        Task {
            await refreshIndividualSignatureFromCloud()
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
    
    // MARK: - Firma Studio
    
    func setStudioSignature(_ image: NSImage?) async {
        guard let image = image else {
            defaults.removeObject(forKey: studioSignatureKey)
            studioSignature = nil
            return
        }
        
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return
        }
        
        defaults.set(pngData, forKey: studioSignatureKey)
        studioSignature = NSImage(data: pngData)
    }

    private func loadStudioSignatureFromLocalCache() {
        guard let data = defaults.data(forKey: studioSignatureKey),
              let image = NSImage(data: data) else {
            studioSignature = nil
            return
        }
        studioSignature = image
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
