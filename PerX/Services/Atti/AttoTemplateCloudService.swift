import Foundation
import AppKit

/// Servizio per gestire i PDF dei template atti con sincronizzazione iCloud Drive
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
    
    /// Directory iCloud per i PDF condivisi
    private var iCloudPDFDirectory: URL? {
        guard let iCloudURL = fileManager.url(forUbiquityContainerIdentifier: "iCloud.it.pernozzoli.PerX") else {
            print("[AttoTemplateCloudService] iCloud container non disponibile")
            return nil
        }
        return iCloudURL.appendingPathComponent("Documents/Atti", isDirectory: true)
    }
    
    private func createDirectoriesIfNeeded() {
        // Directory locale
        if let localDir = localPDFDirectory {
            if !fileManager.fileExists(atPath: localDir.path) {
                try? fileManager.createDirectory(at: localDir, withIntermediateDirectories: true)
            }
        }
        
        // Directory iCloud
        if let iCloudDir = iCloudPDFDirectory {
            if !fileManager.fileExists(atPath: iCloudDir.path) {
                try? fileManager.createDirectory(at: iCloudDir, withIntermediateDirectories: true)
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
    
    // MARK: - iCloud Sync
    
    /// Sincronizzazione veloce con iCloud - non bloccante
    func syncWithiCloud() async {
        // Non bloccare la UI durante la sync
        errorMessage = nil
        
        guard let iCloudDir = iCloudPDFDirectory,
              let localDir = localPDFDirectory else {
            print("[AttoTemplateCloudService] iCloud non disponibile")
            return
        }
        
        do {
            // Assicura che la directory iCloud esista
            if !fileManager.fileExists(atPath: iCloudDir.path) {
                try fileManager.createDirectory(at: iCloudDir, withIntermediateDirectories: true)
            }
            
            // Scansiona i file iCloud (veloce, non aspetta download)
            let iCloudFiles = try fileManager.contentsOfDirectory(atPath: iCloudDir.path)
            
            for file in iCloudFiles where file.hasSuffix(".pdf") {
                let iCloudFilePath = iCloudDir.appendingPathComponent(file)
                let localFilePath = localDir.appendingPathComponent(file)
                
                // Trigger download in background (non aspetta)
                try? fileManager.startDownloadingUbiquitousItem(at: iCloudFilePath)
                
                // Se il file locale non esiste ma quello iCloud sì (e non è placeholder)
                if !fileManager.fileExists(atPath: localFilePath.path) {
                    let resourceValues = try? iCloudFilePath.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                    if let status = resourceValues?.ubiquitousItemDownloadingStatus,
                       status == .current {
                        try? fileManager.copyItem(at: iCloudFilePath, to: localFilePath)
                    }
                }
                
                // Aggiungi alla lista se non presente
                if !availablePDFs.contains(where: { $0.fileName == file }) {
                    let attrs = try? fileManager.attributesOfItem(atPath: iCloudFilePath.path)
                    let size = attrs?[.size] as? Int64 ?? 0
                    
                    availablePDFs.append(AttoPDFInfo(
                        id: UUID().uuidString,
                        fileName: file,
                        displayName: file.replacingOccurrences(of: ".pdf", with: ""),
                        uploadedBy: "iCloud",
                        uploadedAt: (attrs?[.modificationDate] as? Date) ?? Date(),
                        fileSize: size,
                        isFromCloud: true
                    ))
                }
            }
            
            // Carica metadata da iCloud (veloce)
            let metadataPath = iCloudDir.appendingPathComponent(metadataFileName)
            try? fileManager.startDownloadingUbiquitousItem(at: metadataPath)
            if let data = try? Data(contentsOf: metadataPath),
               let cloudMetadata = try? JSONDecoder().decode([AttoPDFInfo].self, from: data) {
                for info in cloudMetadata {
                    if let index = availablePDFs.firstIndex(where: { $0.fileName == info.fileName }) {
                        availablePDFs[index] = info
                    } else if !availablePDFs.contains(where: { $0.fileName == info.fileName }) {
                        availablePDFs.append(info)
                    }
                }
            }
            
            availablePDFs.sort { $0.uploadedAt > $1.uploadedAt }
            saveCachedMetadata()
            
        } catch {
            print("[AttoTemplateCloudService] Errore sync iCloud: \(error)")
        }
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
            
            // 2. Copia in iCloud se disponibile
            if let iCloudDir = iCloudPDFDirectory {
                let iCloudPath = iCloudDir.appendingPathComponent(fileName)
                
                // Rimuovi file esistente se presente
                if fileManager.fileExists(atPath: iCloudPath.path) {
                    try? fileManager.removeItem(at: iCloudPath)
                }
                
                try fileManager.copyItem(at: localPath, to: iCloudPath)
                
                uploadProgress = 0.8
            }
            
            // 3. Aggiorna metadata
            let newInfo = AttoPDFInfo(
                id: UUID().uuidString,
                fileName: fileName,
                displayName: displayName,
                uploadedBy: userEmail,
                uploadedAt: Date(),
                fileSize: fileSize,
                isFromCloud: iCloudPDFDirectory != nil
            )
            
            // Rimuovi versione precedente se esiste
            availablePDFs.removeAll { $0.fileName == fileName }
            availablePDFs.insert(newInfo, at: 0)
            
            saveCachedMetadata()
            saveMetadataToiCloud()
            
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
            
            // Elimina da iCloud
            if let iCloudDir = iCloudPDFDirectory {
                let iCloudPath = iCloudDir.appendingPathComponent(info.fileName)
                if fileManager.fileExists(atPath: iCloudPath.path) {
                    try fileManager.removeItem(at: iCloudPath)
                }
            }
            
            // Rimuovi da lista
            availablePDFs.removeAll { $0.id == info.id }
            
            saveCachedMetadata()
            saveMetadataToiCloud()
            
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
        
        // 2. Cerca in iCloud
        if let iCloudDir = iCloudPDFDirectory {
            let iCloudPath = iCloudDir.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: iCloudPath.path) {
                // Trigger download se necessario
                try? fileManager.startDownloadingUbiquitousItem(at: iCloudPath)
                return iCloudPath
            }
        }
        
        // 3. Cerca nel bundle
        if let bundleURL = Bundle.main.url(forResource: fileName.replacingOccurrences(of: ".pdf", with: ""),
                                            withExtension: "pdf",
                                            subdirectory: "Atti") {
            return bundleURL
        }
        
        // 4. Cerca in Resources/Atti del progetto
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
    
    private func saveMetadataToiCloud() {
        guard let iCloudDir = iCloudPDFDirectory else { return }
        
        let metadataPath = iCloudDir.appendingPathComponent(metadataFileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(availablePDFs)
            try data.write(to: metadataPath, options: .atomic)
        } catch {
            print("[AttoTemplateCloudService] Errore salvataggio metadata iCloud: \(error)")
        }
    }
}
