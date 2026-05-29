import Foundation
import UniformTypeIdentifiers
import AppKit
import QuickLook
import QuickLookThumbnailing
import Quartz

class FileService {
    static let shared = FileService()
    private let fileManager = FileManager.default
    private let logService = LogService()
    private let workspace = NSWorkspace.shared
    private let mainDirectoryBookmarkKey = "MainDirectoryBookmark"
    
    // Cartelle riservate: devono esistere (e sincronizzarsi) ma non vanno mostrate/analizzate in UI.
    // Nota: teniamo anche "cestino" per compatibilità (migrazione da vecchie strutture).
    private static let reservedFolderNamesLowercased: Set<String> = ["perx-cache", "cestino"]
    
    struct FileItem: Identifiable, Hashable {
        let id: String
        let url: URL
        let isDirectory: Bool
        let icon: NSImage?
        let size: Int64
        let modificationDate: Date
        let isDownloading: Bool
        let isNotDownloaded: Bool // File presente nel manifest ma non ancora scaricato localmente
        
        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        
        var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: modificationDate)
        }
        
        static func == (lhs: FileItem, rhs: FileItem) -> Bool {
            lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        init(id: String, url: URL, isDirectory: Bool, icon: NSImage?, size: Int64, modificationDate: Date, isDownloading: Bool = false, isNotDownloaded: Bool = false) {
            self.id = id
            self.url = url
            self.isDirectory = isDirectory
            self.icon = icon
            self.size = size
            self.modificationDate = modificationDate
            self.isDownloading = isDownloading
            self.isNotDownloaded = isNotDownloaded
        }
    }
    
    private init() {
        // Non richiedere accesso automaticamente all'avvio
        // L'accesso verrà richiesto solo quando necessario (apertura file/directory)
        // o tramite Impostazioni → Sinistri (cartella esportazione)
    }
    
    /// Restituisce il path base per i sinistri in Application Support
    func getInternalClaimsPath() -> String {
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // Fallback (non dovrebbe mai accadere)
            return NSHomeDirectory() + "/Library/Application Support/PerX/Claims"
        }
        
        let claimsPath = appSupportURL.appendingPathComponent("PerX/Claims", isDirectory: true).path
        
        // Crea la directory se non esiste
        if !fileManager.fileExists(atPath: claimsPath) {
            try? fileManager.createDirectory(atPath: claimsPath, withIntermediateDirectories: true)
        }
        
        return claimsPath
    }
    
    /// Restituisce il path della cartella sinistro in Application Support.
    /// - Parameter create: se true (default), crea la directory se non esiste.
    func getSinistroPath(riferimento: String, create: Bool = true) -> String? {
        let claimsPath = getInternalClaimsPath()
        let sinistroPath = (claimsPath as NSString).appendingPathComponent(riferimento)
        
        // Verifica se la directory esiste
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: sinistroPath, isDirectory: &isDirectory) && isDirectory.boolValue {
            return sinistroPath
        }
        
        if !create { return nil }
        
        // Se non esiste, la crea (per nuovi sinistri)
        do {
            try fileManager.createDirectory(atPath: sinistroPath, withIntermediateDirectories: true)
            return sinistroPath
        } catch {
            print("[FileService] ❌ Errore creazione directory sinistro: \(error)")
            return nil
        }
    }
    
    /// Verifica se un path è interno (Application Support) o esterno
    private func isInternalPath(_ path: String) -> Bool {
        let claimsPath = getInternalClaimsPath()
        return path.hasPrefix(claimsPath)
    }
    
    /// Trova la directory principale più vicina che dovrebbe avere un bookmark
    func findMainDirectoryForPath(_ path: String) -> String? {
        // Prima verifica se abbiamo un bookmark salvato che copre questo path
        if let (url, _) = getBookmarkForPath(path) {
            return url.path
        }
        
        // Cerca nelle directory configurate (in gestione, chiusi, ecc.)
        let configuredDirs = [
            UserDefaults.standard.string(forKey: "activeDirectory"),
            UserDefaults.standard.string(forKey: "closedDirectory")
        ].compactMap { $0 }
        
        // Trova la directory configurata più vicina che contiene il path
        for dir in configuredDirs {
            if path.hasPrefix(dir) {
                return dir
            }
        }
        
        // Se non trovata, usa la directory parent più probabile
        // (es. se path è in "in gestione/2504797", la directory principale è "in gestione")
        let pathComponents = (path as NSString).pathComponents
        if pathComponents.count >= 2 {
            // Prendi le prime N-1 componenti come directory principale
            let mainPath = "/" + pathComponents.dropLast().joined(separator: "/")
            return mainPath
        }
        
        return (path as NSString).deletingLastPathComponent
    }
    
    /// Elenco ricorsivo dei file (non directory), opzionalmente filtrati per estensioni
    func listFilesRecursive(inDirectory path: String, withExtensions extensions: [String]? = nil) -> [URL] {
        let directoryURL = URL(fileURLWithPath: path)
        var results: [URL] = []
        
        // Per file interni, non serve security-scoped access
        if isInternalPath(path) {
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return results
            }
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                   Self.reservedFolderNamesLowercased.contains(url.lastPathComponent.lowercased()) {
                    enumerator.skipDescendants()
                    continue
                }
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    if let extensions = extensions {
                        if extensions.contains(url.pathExtension.lowercased()) {
                            results.append(url)
                        }
                    } else {
                        results.append(url)
                    }
                }
            }
            return results.sorted { $0.path < $1.path }
        }
        
        // Per file esterni (durante migrazione), usa security-scoped access
        guard let (_, _) = getBookmarkForPath(path) else {
            return []
        }
        
        return withSecurityScopedAccess(to: path) {
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return results
            }
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                   Self.reservedFolderNamesLowercased.contains(url.lastPathComponent.lowercased()) {
                    enumerator.skipDescendants()
                    continue
                }
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    if let extensions = extensions {
                        if extensions.contains(url.pathExtension.lowercased()) {
                            results.append(url)
                        }
                    } else {
                        results.append(url)
                    }
                }
            }
            return results.sorted { $0.path < $1.path }
        } ?? []
    }
    
    func listFiles(inDirectory path: String, withExtensions extensions: [String]? = nil) -> [URL] {
        print("DEBUG: Tentativo di lettura directory:", path)
        
        let directoryURL = URL(fileURLWithPath: path)
        
        // Verifica se la directory esiste
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            print("DEBUG: Directory non trovata o non è una directory:", path)
            return []
        }
        
        // Trova la directory principale più vicina con bookmark
        let mainDirectory = findMainDirectoryForPath(path)
        
        // Usa i bookmark salvati, non richiedere accesso
        return withSecurityScopedAccess(to: path) {
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                
                let files = contents.filter { url in
                    (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                }
                
                if let extensions = extensions {
                    return files.filter { url in
                        extensions.contains(url.pathExtension.lowercased())
                    }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                }
                
                return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
            } catch {
                print("DEBUG: Errore nella lettura della directory:", error)
                return []
            }
        } ?? []
    }
    
    /// Cerca un bookmark valido per un path (legacy, per path esterni durante migrazione)
    private func getBookmarkForPath(_ path: String) -> (URL, Data)? {
        // Cerca nei bookmark legacy (da FolderScanService)
        if let folderScanBookmarks = UserDefaults.standard.data(forKey: "FolderScanBookmarks"),
           let bookmarksDict = try? PropertyListDecoder().decode([String: Data].self, from: folderScanBookmarks) {
            // Cerca il bookmark più specifico che contiene questo path
            for (bookmarkPath, bookmarkData) in bookmarksDict.sorted(by: { $0.key.count > $1.key.count }) {
                if path.hasPrefix(bookmarkPath) {
                    do {
                        var isStale = false
                        let url = try URL(resolvingBookmarkData: bookmarkData,
                                        options: [.withSecurityScope],
                                        relativeTo: nil,
                                        bookmarkDataIsStale: &isStale)
                        if !isStale {
                            return (url, bookmarkData)
                        }
                    } catch {
                        continue
                    }
                }
            }
        }
        
        // Fallback: cerca nel vecchio bookmark di FileService
        if let bookmarkData = UserDefaults.standard.data(forKey: mainDirectoryBookmarkKey) {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData,
                                options: .withSecurityScope,
                                relativeTo: nil,
                                bookmarkDataIsStale: &isStale)
                if !isStale {
                    let bookmarkPath = url.path
                    if path.hasPrefix(bookmarkPath) {
                        return (url, bookmarkData)
                    }
                }
            } catch {
                // Ignora
            }
        }
        
        return nil
    }
    
    /// Verifica se abbiamo accesso a un path usando i bookmark salvati
    private func hasAccessToPath(_ path: String) -> Bool {
        guard let (url, _) = getBookmarkForPath(path) else {
            return false
        }
        return url.startAccessingSecurityScopedResource()
    }
    
    /// Esegue un'operazione con accesso security-scoped al path
    private func withSecurityScopedAccess<T>(to path: String, operation: () throws -> T) -> T? {
        guard let (url, _) = getBookmarkForPath(path) else {
            return nil
        }
        
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        return try? operation()
    }
    
    /// Esegue un'operazione void con accesso security-scoped al path
    private func withSecurityScopedAccess(to path: String, operation: () -> Void) {
        guard let (url, _) = getBookmarkForPath(path) else {
            return
        }
        
        guard url.startAccessingSecurityScopedResource() else {
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        operation()
    }
    
    /// Esporta una cartella sinistro in una directory esterna (copia i file)
    func exportFolder(riferimento: String, to destinationPath: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        guard let sinistroPath = getSinistroPath(riferimento: riferimento) else {
            completion(false, "Cartella sinistro non trovata")
            return
        }
        
        // Determina la destinazione
        let exportPath: String
        if let customPath = destinationPath, !customPath.isEmpty {
            exportPath = (customPath as NSString).appendingPathComponent(riferimento)
        } else {
            // Default: Downloads/PerX_Export
            let downloadsPath = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory() + "/Downloads"
            let exportBase = (downloadsPath as NSString).appendingPathComponent("PerX_Export")
            exportPath = (exportBase as NSString).appendingPathComponent(riferimento)
        }
        
        // Crea la directory di destinazione
        do {
            try fileManager.createDirectory(atPath: exportPath, withIntermediateDirectories: true)
        } catch {
            completion(false, "Errore creazione directory esportazione: \(error.localizedDescription)")
            return
        }
        
        // Copia ricorsivamente tutti i file
        let queue = DispatchQueue(label: "exportFolder", qos: .utility)
        queue.async {
            var success = true
            var errorMessage: String?
            
            if let enumerator = self.fileManager.enumerator(at: URL(fileURLWithPath: sinistroPath), includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
                for case let sourceURL as URL in enumerator {
                    let relativePath = sourceURL.path.replacingOccurrences(of: sinistroPath + "/", with: "")
                    let destURL = URL(fileURLWithPath: exportPath).appendingPathComponent(relativePath)
                    
                    // Salta cartelle riservate
                    if Self.reservedFolderNamesLowercased.contains(sourceURL.lastPathComponent.lowercased()) {
                        enumerator.skipDescendants()
                        continue
                    }
                    
                    do {
                        // Crea directory parent se necessario
                        try self.fileManager.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        
                        // Copia file o directory
                        if (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                            if !self.fileManager.fileExists(atPath: destURL.path) {
                                try self.fileManager.createDirectory(at: destURL, withIntermediateDirectories: true)
                            }
                        } else {
                            if self.fileManager.fileExists(atPath: destURL.path) {
                                try self.fileManager.removeItem(at: destURL)
                            }
                            try self.fileManager.copyItem(at: sourceURL, to: destURL)
                        }
                    } catch {
                        print("[FileService] ⚠️ Errore copia \(relativePath): \(error)")
                        success = false
                        errorMessage = "Errore copia \(relativePath): \(error.localizedDescription)"
                    }
                }
            }
            
            DispatchQueue.main.async {
                if success {
                    // Apri la cartella esportata nel Finder
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: exportPath)
                }
                completion(success, errorMessage)
            }
        }
    }
    
    /// Determina se un file può essere aperto internamente
    private func canOpenInternally(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        
        // Formati supportati da MediaViewer
        let mediaFormats = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp", "pdf", "mp4", "mov", "avi", "mkv", "m4v"]
        if mediaFormats.contains(ext) {
            return true
        }
        
        // Altri formati supportati da QuickLook (ma non Word/Excel che apriamo esternamente)
        let officeFormats = ["doc", "docx", "xls", "xlsx", "xlsm", "ppt", "pptx"]
        if officeFormats.contains(ext) {
            return false // Apriamo esternamente
        }
        
        // Altri formati: proviamo con QuickLook
        return true
    }
    
    /// Apre un file con Preview di Apple
    func openWithPreview(_ url: URL) {
        DispatchQueue.main.async {
            let panel = QLPreviewPanel.shared()
            if panel != nil && QLPreviewPanel.sharedPreviewPanelExists() && panel!.isVisible {
                panel!.orderOut(nil)
            } else {
                panel!.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    func openFile(_ url: URL) {
        print("[FileService] Tentativo apertura file: \(url.lastPathComponent)")
        
        ensureFileDownloaded(url: url) { success in
            guard success else {
                print("[FileService] ❌ File non accessibile: \(url.path)")
                return
            }
            
            DispatchQueue.main.async {
                let ext = url.pathExtension.lowercased()
                
                // Formati supportati da MediaViewer
                let mediaFormats = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp", "pdf", "mp4", "mov", "avi", "mkv", "m4v"]
                if mediaFormats.contains(ext) {
                    // Apri con MediaViewer interno
                    MediaViewerWindowManager.shared.openMediaViewer(for: url)
                    return
                }
                
                // Word/Excel: apri con app esterna
                let officeFormats = ["doc", "docx", "xls", "xlsx", "xlsm", "ppt", "pptx"]
                if officeFormats.contains(ext) {
                    NSWorkspace.shared.open(url)
                    return
                }
                
                // Altri formati: prova con QuickLook, fallback a NSWorkspace
                if let panel = QLPreviewPanel.shared(), QLPreviewPanel.sharedPreviewPanelExists() {
                    // QuickLook richiede un datasource, usiamo NSWorkspace come fallback
                    NSWorkspace.shared.open(url)
                } else {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    /// Verifica se un file locale e' accessibile.
    /// - Parameter url: URL del file da verificare
    /// - Parameter completion: Callback chiamato quando il file è disponibile (true) o in caso di errore (false)
    func ensureFileDownloaded(url: URL, completion: @escaping (Bool) -> Void) {
        let parentPath = url.deletingLastPathComponent().path
        guard let (bookmarkURL, _) = getBookmarkForPath(parentPath) else {
            completion(true)
            return
        }

        guard bookmarkURL.startAccessingSecurityScopedResource() else {
            completion(true)
            return
        }

        bookmarkURL.stopAccessingSecurityScopedResource()
        completion(true)
    }
    
    private func ensureFileDownloadedInternal(url: URL, bookmarkURL: URL?, completion: @escaping (Bool) -> Void) {
        bookmarkURL?.stopAccessingSecurityScopedResource()
        completion(true)
    }
    
    /// Compatibilita' con la vecchia API: non effettua download da provider cloud.
    private func waitForDownload(url: URL, bookmarkURL: URL? = nil, completion: @escaping (Bool) -> Void) {
        bookmarkURL?.stopAccessingSecurityScopedResource()
        completion(true)
    }
    
    /// Compatibilita' con la vecchia API: non scarica file da iCloud.
    /// - Parameter directoryPath: Path della directory da scandire
    /// - Parameter completion: Callback chiamato quando il processo è completato (con numero di file trovati)
    func downloadAlliCloudFiles(inDirectory directoryPath: String, completion: ((Int) -> Void)? = nil) {
        if !isInternalPath(directoryPath), let (bookmarkURL, _) = getBookmarkForPath(directoryPath),
           bookmarkURL.startAccessingSecurityScopedResource() {
            bookmarkURL.stopAccessingSecurityScopedResource()
        }
        DispatchQueue.main.async {
            completion?(0)
        }
    }
    
    /// True se nella directory esiste almeno 1 file (non nascosto), anche in sottocartelle.
    /// Usa security-scoped access se disponibile.
    func hasAnyRegularFileRecursively(inDirectory path: String) -> Bool {
        let directoryURL = URL(fileURLWithPath: path)
        
        // Preferisci accesso security-scoped (sandbox)
        if let result: Bool = performWithSecurityScopedAccess(to: path, operation: {
            guard let enumerator = fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return false }
            
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                   Self.reservedFolderNamesLowercased.contains(url.lastPathComponent.lowercased()) {
                    enumerator.skipDescendants()
                    continue
                }
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    return true
                }
            }
            return false
        }) {
            return result
        }
        
        // Fallback (può fallire senza permessi, ma è meglio di niente)
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               Self.reservedFolderNamesLowercased.contains(url.lastPathComponent.lowercased()) {
                enumerator.skipDescendants()
                continue
            }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                return true
            }
        }
        return false
    }
    
    func listContents(inDirectory path: String) -> [FileItem] {
        print("DEBUG: Tentativo di lettura directory:", path)
        
        let directoryURL = URL(fileURLWithPath: path)
        
        // Verifica se la directory esiste
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            print("DEBUG: Directory non trovata o non è una directory:", path)
            return []
        }
        
        // Prova prima con security-scoped access (per directory esterne)
        if let result = withSecurityScopedAccess(to: path, operation: {
            return listContentsInternal(at: directoryURL)
        }) {
            return result
        }
        
        // Fallback: accesso diretto (per cache sandbox interna)
        print("DEBUG: Fallback accesso diretto per:", path)
        return listContentsInternal(at: directoryURL)
    }
    
    private func listContentsInternal(at directoryURL: URL) -> [FileItem] {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .typeIdentifierKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles]
            )
            
            return contents
                .filter { url in
                    !Self.reservedFolderNamesLowercased.contains(url.lastPathComponent.lowercased())
                }
                .compactMap { url in
                guard let resourceValues = try? url.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ]),
                let isDirectory = resourceValues.isDirectory else { return nil }
                
                let icon = workspace.icon(forFile: url.path)
                return FileItem(
                    id: url.path,
                    url: url,
                    isDirectory: isDirectory,
                    icon: icon,
                    size: Int64(resourceValues.fileSize ?? 0),
                    modificationDate: resourceValues.contentModificationDate ?? Date(),
                    isDownloading: false,
                    isNotDownloaded: false
                )
            }
            .sorted { $0.isDirectory && !$1.isDirectory || $0.url.lastPathComponent < $1.url.lastPathComponent }
        } catch {
            print("DEBUG: Errore nella lettura della directory:", error)
            return []
        }
    }
    
    func previewFile(at url: URL, size: CGSize = CGSize(width: 800, height: 600)) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        
        // Crea una richiesta di anteprima
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        
        // Genera l'anteprima in modo sincrono
        let generator = QLThumbnailGenerator.shared
        var thumbnail: NSImage?
        let semaphore = DispatchSemaphore(value: 0)
        
        generator.generateBestRepresentation(for: request) { thumbnailRep, error in
            if let thumbnailRep = thumbnailRep {
                thumbnail = thumbnailRep.nsImage
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 2.0)
        
        if let thumbnail = thumbnail {
            return thumbnail
        }
        
        // Se QuickLook fallisce, usiamo l'icona di sistema come fallback
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    
    func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    
    func getNextItem(after currentItem: URL, in directory: String) -> URL? {
        let items = listContents(inDirectory: directory)
        guard let currentIndex = items.firstIndex(where: { $0.url == currentItem }) else { return nil }
        let nextIndex = items.index(after: currentIndex)
        return nextIndex < items.endIndex ? items[nextIndex].url : nil
    }
    
    func getPreviousItem(before currentItem: URL, in directory: String) -> URL? {
        let items = listContents(inDirectory: directory)
        guard let currentIndex = items.firstIndex(where: { $0.url == currentItem }) else { return nil }
        let previousIndex = items.index(before: currentIndex)
        return previousIndex >= items.startIndex ? items[previousIndex].url : nil
    }
    
    /// Esegue un'operazione con accesso security-scoped (pubblico per uso in altri servizi)
    func performWithSecurityScopedAccess<T>(to path: String, operation: () throws -> T) -> T? {
        // Per i path interni (Application Support), esegui direttamente senza security-scoped access
        if isInternalPath(path) {
            return try? operation()
        }
        
        // Per path esterni, usa i bookmark
        guard let (url, _) = getBookmarkForPath(path) else {
            return nil
        }
        
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        return try? operation()
    }
    
    /// Legge i dati di un file con security-scoped access
    func readFileData(at path: String) -> Data? {
        return performWithSecurityScopedAccess(to: path) {
            try Data(contentsOf: URL(fileURLWithPath: path))
        }
    }
    
    func createFolder(at path: String, named: String) {
        let folderURL = URL(fileURLWithPath: path).appendingPathComponent(named)
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            print("DEBUG: Cartella creata con successo:", folderURL.path)
        } catch {
            print("DEBUG: Errore nella creazione della cartella:", error)
        }
    }
    
    func renameItem(_ item: FileItem, to newName: String) {
        let currentURL = item.url
        let newURL = currentURL.deletingLastPathComponent().appendingPathComponent(newName)
        
        do {
            try fileManager.moveItem(at: currentURL, to: newURL)
            print("DEBUG: File rinominato con successo")
        } catch {
            print("DEBUG: Errore nel rinominare il file:", error)
        }
    }
    
    func moveItem(_ item: FileItem, to destinationPath: String) -> Bool {
        let destinationURL = URL(fileURLWithPath: destinationPath).appendingPathComponent(item.url.lastPathComponent)
        let sourcePath = item.url.deletingLastPathComponent().path
        
        // Verifica se la destinazione è la stessa della sorgente
        if sourcePath == destinationPath {
            print("DEBUG: Sorgente e destinazione sono uguali")
            return false
        }
        
        // Se il file esiste già nella destinazione, fallisce
        if fileManager.fileExists(atPath: destinationURL.path) {
            print("DEBUG: File già esistente nella destinazione: \(destinationURL.path)")
            return false
        }
        
        // Trova la directory principale comune per entrambi i path
        let commonSourceDir = findMainDirectoryForPath(sourcePath) ?? sourcePath
        let commonDestDir = findMainDirectoryForPath(destinationPath) ?? destinationPath
        
        // Usa la directory comune (di solito la stessa per sinistri nella stessa root)
        let commonDir = commonSourceDir == commonDestDir ? commonSourceDir : commonSourceDir
        
        // Usa sempre security scoped access per operazioni su file sandbox
        return withSecurityScopedAccess(to: commonDir) {
            do {
                try fileManager.moveItem(at: item.url, to: destinationURL)
                print("DEBUG: File spostato con successo da \(item.url.path) a \(destinationURL.path)")
                return true
            } catch {
                print("DEBUG: Errore nello spostare il file: \(error)")
                return false
            }
        } ?? false
    }
    
    // MARK: - Task Validation Support
    
    /// Conta file con un tag specifico e allegare: true
    /// Utilizzato da OptionalTaskValidator per verificare se mancano documenti
    func countFilesWithTag(in folderPath: String, tag: String, allegare: Bool) -> Int {
        var count = 0
        
        // TODO: Implementare lettura metadata file quando sistema metadata sarà definito
        // Per ora ritorna 0 come fallback sicuro (nessun file trovato = task viene creata)
        
        // Quando verrà implementato il sistema metadata, questo metodo dovrà:
        // 1. Enumerare tutti i file nella cartella (recursivamente)
        // 2. Per ogni file, leggere i metadata (extended attributes, JSON sidecar, o database)
        // 3. Verificare se il tag è presente nell'array di tag
        // 4. Verificare se allegare == true
        // 5. Contare i file che soddisfano entrambe le condizioni
        
        return count
    }
    
    // MARK: - Cleanup Claims Root
    
    /// Pulisce la root di Claims spostando file/cartelle dentro le rispettive cartelle dei sinistri
    /// Gestisce pattern come:
    /// - "{riferimento} {nome}.ext" -> sposta in Claims/{riferimento}/
    /// - "{riferimento}_{numero}" -> sposta in Claims/{riferimento}/
    func cleanupClaimsRoot() {
        let claimsPath = getInternalClaimsPath()
        let fm = FileManager.default
        
        guard let contents = try? fm.contentsOfDirectory(atPath: claimsPath) else {
            print("[FileService] ⚠️ Impossibile leggere contenuto Claims root")
            return
        }
        
        var movedCount = 0
        
        for item in contents {
            let itemPath = (claimsPath as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: itemPath, isDirectory: &isDirectory) else { continue }
            
            // Estrai il riferimento dal nome (pattern: 7 cifre all'inizio)
            var riferimento: String?
            
            // Pattern 1: "{riferimento} {resto}" (es. "2600465 foto.docx")
            if item.count >= 7 {
                let prefix = String(item.prefix(7))
                if prefix.allSatisfy({ $0.isNumber }) {
                    riferimento = prefix
                }
            }
            
            // Pattern 2: "{riferimento}_{numero}" (es. "2600465_96323")
            if riferimento == nil {
                let components = item.split(separator: "_")
                if let first = components.first, first.count == 7, first.allSatisfy({ $0.isNumber }) {
                    riferimento = String(first)
                }
            }
            
            // Pattern 3: Solo riferimento (es. "2600465") - questo è corretto, skip
            if riferimento == item {
                continue // È già una cartella corretta
            }
            
            guard let rif = riferimento else { continue }
            
            // Ottieni la cartella destinazione
            guard let destFolder = getSinistroPath(riferimento: rif, create: true) else {
                print("[FileService] ⚠️ Impossibile creare cartella per sinistro \(rif)")
                continue
            }
            
            let destPath = (destFolder as NSString).appendingPathComponent(item)
            
            // Se la destinazione esiste già, rinomina
            var finalDestPath = destPath
            if fm.fileExists(atPath: finalDestPath) {
                let baseName = (item as NSString).deletingPathExtension
                let ext = (item as NSString).pathExtension
                var counter = 1
                repeat {
                    let newName = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
                    finalDestPath = (destFolder as NSString).appendingPathComponent(newName)
                    counter += 1
                } while fm.fileExists(atPath: finalDestPath)
            }
            
            // Sposta il file/cartella
            do {
                try fm.moveItem(atPath: itemPath, toPath: finalDestPath)
                movedCount += 1
                print("[FileService] ✅ Spostato '\(item)' in \(rif)/")
            } catch {
                print("[FileService] ❌ Errore spostamento '\(item)': \(error)")
            }
        }
        
        if movedCount > 0 {
            print("[FileService] 🧹 Pulizia Claims root completata: \(movedCount) elementi spostati")
        }
    }
}
