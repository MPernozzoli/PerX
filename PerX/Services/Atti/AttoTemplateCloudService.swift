import Foundation
import AppKit

/// Servizio per gestire i PDF dei template atti su storage locale.
@MainActor
class AttoTemplateCloudService: ObservableObject {
    static let shared = AttoTemplateCloudService()
    
    @Published var availablePDFs: [AttoPDFInfo] = []
    @Published var isLoading = false
    @Published var uploadProgress: Double = 0
    @Published var errorMessage: String?
    
    private let fileManager = FileManager.default
    private let metadataFileName = "pdfs_metadata.json"
    
    struct AttoPDFInfo: Codable, Identifiable, Hashable {
        let id: String
        var fileName: String
        var displayName: String
        var uploadedBy: String
        var uploadedAt: Date
        var fileSize: Int64
        var isFromCloud: Bool
        
        var isLocal: Bool {
            !isFromCloud
        }
    }
    
    private init() {
        // Crea le directory necessarie
        createDirectoriesIfNeeded()
        
        // Carica i PDF
        loadAllPDFs()
        
        print("[AttoTemplateCloudService] Init completato con \(availablePDFs.count) PDF")
    }
    
    // MARK: - Directories
    
    /// Directory locale per i PDF (Application Support)
    private var localPDFDirectory: URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("PerX/Atti/PDFs", isDirectory: true)
    }
    
    private func createDirectoriesIfNeeded() {
        if let localDir = localPDFDirectory {
            if !fileManager.fileExists(atPath: localDir.path) {
                try? fileManager.createDirectory(at: localDir, withIntermediateDirectories: true)
            }
        }
    }
    
    // MARK: - Load PDFs
    
    func loadAllPDFs() {
        print("[AttoTemplateCloudService] loadAllPDFs() chiamato")
        var allPDFs: [AttoPDFInfo] = []
        
        // 1. Carica da cache locale (metadata salvati)
        if let cached = loadCachedMetadata() {
            print("[AttoTemplateCloudService] Cache trovata con \(cached.count) PDF")
            allPDFs = cached
        }
        
        // 2. Aggiungi PDF dal bundle (sistema)
        let bundlePDFs = loadBundlePDFs()
        print("[AttoTemplateCloudService] Bundle PDF trovati: \(bundlePDFs.count)")
        for pdf in bundlePDFs {
            if !allPDFs.contains(where: { $0.fileName == pdf.fileName }) {
                allPDFs.append(pdf)
            }
        }
        
        // 3. Scansiona directory locale per PDF non in metadata
        if let localDir = localPDFDirectory {
            print("[AttoTemplateCloudService] Directory locale: \(localDir.path)")
            if let files = try? fileManager.contentsOfDirectory(atPath: localDir.path) {
                print("[AttoTemplateCloudService] File nella directory locale: \(files)")
                for file in files where file.hasSuffix(".pdf") {
                    if !allPDFs.contains(where: { $0.fileName == file }) {
                        let filePath = localDir.appendingPathComponent(file)
                        let attrs = try? fileManager.attributesOfItem(atPath: filePath.path)
                        let size = attrs?[.size] as? Int64 ?? 0
                        
                        allPDFs.append(AttoPDFInfo(
                            id: UUID().uuidString,
                            fileName: file,
                            displayName: file.replacingOccurrences(of: ".pdf", with: ""),
                            uploadedBy: "Locale",
                            uploadedAt: Date(),
                            fileSize: size,
                            isFromCloud: false
                        ))
                    }
                }
            }
        }
        
        print("[AttoTemplateCloudService] Totale PDF caricati: \(allPDFs.count)")
        availablePDFs = allPDFs.sorted { $0.uploadedAt > $1.uploadedAt }
    }
    
    private func loadBundlePDFs() -> [AttoPDFInfo] {
        var bundlePDFs: [AttoPDFInfo] = []
        
        // Cerca PDF nel bundle
        if let bundlePath = Bundle.main.resourcePath {
            let attiPath = (bundlePath as NSString).appendingPathComponent("Atti")
            if let files = try? fileManager.contentsOfDirectory(atPath: attiPath) {
                for file in files where file.hasSuffix(".pdf") {
                    let fullPath = (attiPath as NSString).appendingPathComponent(file)
                    let attrs = try? fileManager.attributesOfItem(atPath: fullPath)
                    let size = attrs?[.size] as? Int64 ?? 0
                    
                    bundlePDFs.append(AttoPDFInfo(
                        id: UUID().uuidString,
                        fileName: file,
                        displayName: file.replacingOccurrences(of: ".pdf", with: ""),
                        uploadedBy: "Sistema",
                        uploadedAt: Date(),
                        fileSize: size,
                        isFromCloud: false
                    ))
                }
            }
        }
        
        // Cerca in Resources/Atti del progetto (per sviluppo)
        let projectPath = "/Users/mpernozzoli/Documents/Attività Peritali/App/PerX BKP16 - fulminazioni Recupero/PerX/Resources/Atti"
        if let files = try? fileManager.contentsOfDirectory(atPath: projectPath) {
            for file in files where file.hasSuffix(".pdf") {
                if !bundlePDFs.contains(where: { $0.fileName == file }) {
                    let fullPath = (projectPath as NSString).appendingPathComponent(file)
                    let attrs = try? fileManager.attributesOfItem(atPath: fullPath)
                    let size = attrs?[.size] as? Int64 ?? 0
                    
                    bundlePDFs.append(AttoPDFInfo(
                        id: UUID().uuidString,
                        fileName: file,
                        displayName: file.replacingOccurrences(of: ".pdf", with: ""),
                        uploadedBy: "Sistema",
                        uploadedAt: Date(),
                        fileSize: size,
                        isFromCloud: false
                    ))
                }
            }
        }
        
        return bundlePDFs
    }
    
    // MARK: - Sync
    
    /// Compatibilita' con la vecchia API: ricarica lo storage locale.
    func syncWithiCloud() async {
        errorMessage = nil
        loadAllPDFs()
    }
    
    // MARK: - Upload
    
    func uploadPDF(from sourceURL: URL, displayName: String) async -> Bool {
        isLoading = true
        uploadProgress = 0
        errorMessage = nil
        
        let fileName = sourceURL.lastPathComponent
        let userEmail = UserDefaults.standard.string(forKey: "userEmail") ?? "Sconosciuto"
        
        do {
            let fileData = try Data(contentsOf: sourceURL)
            let fileSize = Int64(fileData.count)
            
            uploadProgress = 0.2
            
            // 1. Salva in locale
            guard let localDir = localPDFDirectory else {
                errorMessage = "Directory locale non disponibile"
                isLoading = false
                return false
            }
            
            let localPath = localDir.appendingPathComponent(fileName)
            try fileData.write(to: localPath)
            
            uploadProgress = 0.5
            
            uploadProgress = 0.8

            let newInfo = AttoPDFInfo(
                id: UUID().uuidString,
                fileName: fileName,
                displayName: displayName,
                uploadedBy: userEmail,
                uploadedAt: Date(),
                fileSize: fileSize,
                isFromCloud: false
            )
            
            // Rimuovi versione precedente se esiste
            availablePDFs.removeAll { $0.fileName == fileName }
            availablePDFs.insert(newInfo, at: 0)
            
            saveCachedMetadata()
            
            uploadProgress = 1.0
            isLoading = false
            
            return true
            
        } catch {
            print("[AttoTemplateCloudService] Errore upload: \(error)")
            errorMessage = "Errore caricamento: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }
    
    // MARK: - Delete
    
    func deletePDF(_ info: AttoPDFInfo) async -> Bool {
        // Non eliminare PDF di sistema
        if info.uploadedBy == "Sistema" {
            errorMessage = "Non è possibile eliminare i PDF di sistema"
            return false
        }
        
        isLoading = true
        
        do {
            // Elimina da locale
            if let localDir = localPDFDirectory {
                let localPath = localDir.appendingPathComponent(info.fileName)
                if fileManager.fileExists(atPath: localPath.path) {
                    try fileManager.removeItem(at: localPath)
                }
            }
            
            // Rimuovi da lista
            availablePDFs.removeAll { $0.id == info.id }
            
            saveCachedMetadata()
            
            isLoading = false
            return true
            
        } catch {
            print("[AttoTemplateCloudService] Errore eliminazione: \(error)")
            errorMessage = "Errore eliminazione: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }
    
    // MARK: - Get PDF URL
    
    func getPDFURL(for info: AttoPDFInfo) -> URL? {
        return getPDFURL(forFileName: info.fileName)
    }
    
    func getPDFURL(forFileName fileName: String) -> URL? {
        // 1. Cerca in locale (priorità)
        if let localDir = localPDFDirectory {
            let localPath = localDir.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: localPath.path) {
                return localPath
            }
        }
        
        // 2. Cerca nel bundle
        if let bundleURL = Bundle.main.url(forResource: fileName.replacingOccurrences(of: ".pdf", with: ""),
                                            withExtension: "pdf",
                                            subdirectory: "Atti") {
            return bundleURL
        }
        
        // 3. Cerca in Resources/Atti del progetto
        let projectPath = "/Users/mpernozzoli/Documents/Attività Peritali/App/PerX BKP16 - fulminazioni Recupero/PerX/Resources/Atti"
        let pdfPath = (projectPath as NSString).appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: pdfPath) {
            return URL(fileURLWithPath: pdfPath)
        }
        
        return nil
    }
    
    // MARK: - Metadata Cache
    
    private var localMetadataURL: URL? {
        localPDFDirectory?.appendingPathComponent(metadataFileName)
    }
    
    private func loadCachedMetadata() -> [AttoPDFInfo]? {
        guard let metadataURL = localMetadataURL,
              fileManager.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let pdfs = try? JSONDecoder().decode([AttoPDFInfo].self, from: data) else {
            return nil
        }
        return pdfs
    }
    
    private func saveCachedMetadata() {
        guard let metadataURL = localMetadataURL else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(availablePDFs)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            print("[AttoTemplateCloudService] Errore salvataggio cache metadata: \(error)")
        }
    }
}
