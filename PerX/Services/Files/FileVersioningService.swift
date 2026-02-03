import Foundation
import SwiftUI

class FileVersioningService: ObservableObject {
    static let shared = FileVersioningService()
    
    private let fileManager = FileManager.default
    private static let cacheFolderName = "PerX-cache"
    private static let legacyCacheFolderName = "perx-cache"
    private static let trashFolderName = "cestino"
    private static let versioningFolderName = "versioning"
    private let fileService = FileService.shared
    
    private init() {}
    
    /// Esegue operazioni filesystem con accesso security-scoped (se disponibile).
    private func withAccess<T>(sinistroPath: String, operation: () throws -> T) -> T? {
        if let result: T = fileService.performWithSecurityScopedAccess(to: sinistroPath, operation: operation) {
            return result
        }
        do {
            return try operation()
        } catch {
            return nil
        }
    }
    
    private func ensureCacheDirectory(for sinistroPath: String) -> String {
        let desiredCachePath = (sinistroPath as NSString).appendingPathComponent(Self.cacheFolderName)
        let legacyCachePath = (sinistroPath as NSString).appendingPathComponent(Self.legacyCacheFolderName)
        
        var isDir: ObjCBool = false
        let desiredExists = fileManager.fileExists(atPath: desiredCachePath, isDirectory: &isDir) && isDir.boolValue
        if !desiredExists {
            var legacyIsDir: ObjCBool = false
            let legacyExists = fileManager.fileExists(atPath: legacyCachePath, isDirectory: &legacyIsDir) && legacyIsDir.boolValue
            if legacyExists {
                _ = withAccess(sinistroPath: sinistroPath) {
                    try fileManager.moveItem(atPath: legacyCachePath, toPath: desiredCachePath)
                }
            } else {
                _ = withAccess(sinistroPath: sinistroPath) {
                    try fileManager.createDirectory(atPath: desiredCachePath, withIntermediateDirectories: true)
                }
            }
        }
        
        return desiredCachePath
    }
    
    /// Crea la struttura cache (`PerX-cache/cestino` e `PerX-cache/versioning`) nella cartella del sinistro.
    func ensureCacheStructure(for sinistroPath: String) {
        _ = getTrashDirectory(for: sinistroPath)
        _ = getVersionsDirectory(for: sinistroPath)
    }
    
    func getVersionsDirectory(for sinistroPath: String) -> String {
        let cachePath = ensureCacheDirectory(for: sinistroPath)
        let desiredVersionsPath = (cachePath as NSString).appendingPathComponent(Self.versioningFolderName)
        let legacyVersionsPath = (sinistroPath as NSString).appendingPathComponent(".versions")
        
        // Migrazione: se esiste ".versions" e manca "perx-cache/versioning", rinomina/sposta.
        var isDir: ObjCBool = false
        let desiredExists = fileManager.fileExists(atPath: desiredVersionsPath, isDirectory: &isDir) && isDir.boolValue
        if !desiredExists {
            var legacyIsDir: ObjCBool = false
            let legacyExists = fileManager.fileExists(atPath: legacyVersionsPath, isDirectory: &legacyIsDir) && legacyIsDir.boolValue
            if legacyExists {
                if withAccess(sinistroPath: sinistroPath, operation: {
                    try fileManager.moveItem(atPath: legacyVersionsPath, toPath: desiredVersionsPath)
                    return true
                }) != true {
                    _ = withAccess(sinistroPath: sinistroPath) {
                        try fileManager.createDirectory(atPath: desiredVersionsPath, withIntermediateDirectories: true)
                    }
                }
            } else {
                _ = withAccess(sinistroPath: sinistroPath) {
                    try fileManager.createDirectory(atPath: desiredVersionsPath, withIntermediateDirectories: true)
                }
            }
        }
        
        return desiredVersionsPath
    }
    
    func getTrashDirectory(for sinistroPath: String) -> String {
        let cachePath = ensureCacheDirectory(for: sinistroPath)
        let desiredTrashPath = (cachePath as NSString).appendingPathComponent(Self.trashFolderName)
        let legacyTrashPath = (sinistroPath as NSString).appendingPathComponent(".trash")
        let legacyVisibleTrashPath = (sinistroPath as NSString).appendingPathComponent(Self.trashFolderName)
        
        // Migrazione: se esiste il vecchio ".trash" o il vecchio "cestino" in root e manca "perx-cache/cestino", rinomina/sposta.
        var isDir: ObjCBool = false
        let desiredExists = fileManager.fileExists(atPath: desiredTrashPath, isDirectory: &isDir) && isDir.boolValue
        if !desiredExists {
            var legacyVisibleIsDir: ObjCBool = false
            let legacyVisibleExists = fileManager.fileExists(atPath: legacyVisibleTrashPath, isDirectory: &legacyVisibleIsDir) && legacyVisibleIsDir.boolValue
            if legacyVisibleExists {
                if withAccess(sinistroPath: sinistroPath, operation: {
                    try fileManager.moveItem(atPath: legacyVisibleTrashPath, toPath: desiredTrashPath)
                    return true
                }) != true {
                    _ = withAccess(sinistroPath: sinistroPath) {
                        try fileManager.createDirectory(atPath: desiredTrashPath, withIntermediateDirectories: true)
                    }
                }
                return desiredTrashPath
            }
            
            var legacyIsDir: ObjCBool = false
            let legacyExists = fileManager.fileExists(atPath: legacyTrashPath, isDirectory: &legacyIsDir) && legacyIsDir.boolValue
            if legacyExists {
                if withAccess(sinistroPath: sinistroPath, operation: {
                    try fileManager.moveItem(atPath: legacyTrashPath, toPath: desiredTrashPath)
                    return true
                }) != true {
                    _ = withAccess(sinistroPath: sinistroPath) {
                        try fileManager.createDirectory(atPath: desiredTrashPath, withIntermediateDirectories: true)
                    }
                }
            } else {
                _ = withAccess(sinistroPath: sinistroPath) {
                    try fileManager.createDirectory(atPath: desiredTrashPath, withIntermediateDirectories: true)
                }
            }
        }
        
        return desiredTrashPath
    }
    
    func createVersion(of fileURL: URL, in sinistroPath: String, description: String? = nil) -> Bool {
        // Evita versioning su directory (potenzialmente enorme / non desiderato)
        if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return false
        }
        
        let versionsDir = getVersionsDirectory(for: sinistroPath)
        let fileName = fileURL.lastPathComponent
        let timestamp = Int(Date().timeIntervalSince1970)
        let versionFileName = "\(fileName).v\(timestamp)"
        let versionPath = (versionsDir as NSString).appendingPathComponent(versionFileName)
        
        do {
            let ok = withAccess(sinistroPath: sinistroPath, operation: {
                try fileManager.copyItem(at: fileURL, to: URL(fileURLWithPath: versionPath))
                return true
            }) ?? false
            guard ok else { return false }
            
            // Salva metadati della versione
            let metadataPath = (versionsDir as NSString).appendingPathComponent("\(versionFileName).meta")
            var metadata: [String: Any] = [
                "originalPath": fileURL.path,
                "fileName": fileName,
                "timestamp": timestamp,
                "size": (try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
            ]
            
            if let description = description {
                metadata["description"] = description
            }
            
            _ = withAccess(sinistroPath: sinistroPath) {
                (metadata as NSDictionary).write(toFile: metadataPath, atomically: true)
            }
            
            return true
        } catch {
            print("Errore creazione versione: \(error)")
            return false
        }
    }
    
    func getVersions(for fileURL: URL, in sinistroPath: String) -> [FileVersion] {
        let versionsDir = getVersionsDirectory(for: sinistroPath)
        let fileName = fileURL.lastPathComponent
        
        guard let files = try? fileManager.contentsOfDirectory(atPath: versionsDir) else {
            return []
        }
        
        var versions: [FileVersion] = []
        
        for file in files {
            if file.hasPrefix(fileName + ".v") && !file.hasSuffix(".meta") {
                let versionPath = (versionsDir as NSString).appendingPathComponent(file)
                let metadataPath = (versionsDir as NSString).appendingPathComponent("\(file).meta")
                
                var timestamp: Int = 0
                var size: Int64 = 0
                
                var description: String? = nil
                
                if let metadata = NSDictionary(contentsOfFile: metadataPath) {
                    timestamp = metadata["timestamp"] as? Int ?? 0
                    size = metadata["size"] as? Int64 ?? 0
                    description = metadata["description"] as? String
                } else {
                    // Fallback: estrai timestamp dal nome file
                    if let timestampStr = file.components(separatedBy: ".v").last {
                        timestamp = Int(timestampStr) ?? 0
                    }
                    if let attrs = try? fileManager.attributesOfItem(atPath: versionPath) {
                        size = attrs[.size] as? Int64 ?? 0
                    }
                }
                
                versions.append(FileVersion(
                    path: versionPath,
                    timestamp: timestamp,
                    size: size,
                    description: description
                ))
            }
        }
        
        return versions.sorted { $0.timestamp > $1.timestamp }
    }
    
    func restoreVersion(_ version: FileVersion, to originalURL: URL) -> Bool {
        do {
            // Crea una versione del file corrente prima di ripristinare
            if let sinistroPath = getSinistroPath(for: originalURL) {
                _ = createVersion(of: originalURL, in: sinistroPath)
            }
            
            // Sostituisci il file con la versione
            try fileManager.removeItem(at: originalURL)
            try fileManager.copyItem(at: URL(fileURLWithPath: version.path), to: originalURL)
            
            return true
        } catch {
            print("Errore ripristino versione: \(error)")
            return false
        }
    }
    
    func moveToTrash(_ fileURL: URL, in sinistroPath: String) -> Bool {
        let trashDir = getTrashDirectory(for: sinistroPath)
        let fileName = fileURL.lastPathComponent
        let timestamp = Int(Date().timeIntervalSince1970)
        let trashFileName = "\(timestamp)_\(fileName)"
        let trashPath = (trashDir as NSString).appendingPathComponent(trashFileName)
        
        // Verifica se è una directory
        let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        
        do {
            // Crea una versione prima di spostare nel cestino (solo per file, non per cartelle)
            if !isDirectory {
                _ = createVersion(of: fileURL, in: sinistroPath)
            }
            
            // Sposta nel cestino
            let moved = withAccess(sinistroPath: sinistroPath, operation: {
                try fileManager.moveItem(at: fileURL, to: URL(fileURLWithPath: trashPath))
                return true
            }) ?? false
            guard moved else { return false }
            
            // Calcola il path relativo rispetto alla root del sinistro
            let relativePath = getRelativePath(from: sinistroPath, to: fileURL.path)
            
            // Salva metadati
            let metadataPath = (trashDir as NSString).appendingPathComponent("\(trashFileName).meta")
            let metadata: [String: Any] = [
                "originalPath": fileURL.path,
                "relativePath": relativePath,
                "fileName": fileName,
                "isDirectory": isDirectory,
                "timestamp": timestamp,
                "deletedAt": Date().timeIntervalSince1970
            ]
            _ = withAccess(sinistroPath: sinistroPath) {
                (metadata as NSDictionary).write(toFile: metadataPath, atomically: true)
            }
            
            // Notifica l'eliminazione per la sincronizzazione
            NotificationCenter.default.post(
                name: .fileOrFolderDeleted,
                object: nil,
                userInfo: [
                    "sinistroPath": sinistroPath,
                    "originalPath": fileURL.path,
                    "relativePath": relativePath,
                    "isDirectory": isDirectory
                ]
            )
            
            return true
        } catch {
            print("Errore spostamento nel cestino: \(error)")
            return false
        }
    }
    
    /// Calcola il path relativo di un file/cartella rispetto alla root del sinistro
    private func getRelativePath(from sinistroPath: String, to fullPath: String) -> String {
        let sinistroURL = URL(fileURLWithPath: sinistroPath).standardizedFileURL
        let fullURL = URL(fileURLWithPath: fullPath).standardizedFileURL
        
        // Normalizza i path per il confronto
        let sinistroPathNormalized = sinistroURL.path
        let fullPathNormalized = fullURL.path
        
        // Verifica che il file sia dentro la cartella del sinistro
        guard fullPathNormalized.hasPrefix(sinistroPathNormalized) else {
            // Se non è dentro, restituisci solo il nome
            return fullURL.lastPathComponent
        }
        
        // Se il file è nella root del sinistro, restituisci solo il nome
        if fullURL.deletingLastPathComponent().path == sinistroPathNormalized {
            return fullURL.lastPathComponent
        }
        
        // Calcola il path relativo rimuovendo il prefisso del sinistro
        let relativePath = String(fullPathNormalized.dropFirst(sinistroPathNormalized.count))
        // Rimuovi lo slash iniziale se presente
        return relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
    }
    
    func getTrashedFiles(in sinistroPath: String) -> [TrashedFile] {
        let trashDir = getTrashDirectory(for: sinistroPath)
        
        guard let files = try? fileManager.contentsOfDirectory(atPath: trashDir) else {
            return []
        }
        
        var trashedFiles: [TrashedFile] = []
        
        for file in files {
            if !file.hasSuffix(".meta") {
                let filePath = (trashDir as NSString).appendingPathComponent(file)
                let metadataPath = (trashDir as NSString).appendingPathComponent("\(file).meta")
                
                var originalPath: String = ""
                var fileName: String = ""
                var deletedAt: TimeInterval = 0
                
                if let metadata = NSDictionary(contentsOfFile: metadataPath) {
                    originalPath = metadata["originalPath"] as? String ?? ""
                    fileName = metadata["fileName"] as? String ?? file
                    deletedAt = metadata["deletedAt"] as? TimeInterval ?? 0
                } else {
                    fileName = file
                }
                
                trashedFiles.append(TrashedFile(
                    path: filePath,
                    originalPath: originalPath,
                    fileName: fileName,
                    deletedAt: deletedAt
                ))
            }
        }
        
        return trashedFiles.sorted { $0.deletedAt > $1.deletedAt }
    }
    
    func restoreFromTrash(_ trashedFile: TrashedFile, to originalPath: String) -> Bool {
        do {
            let sourceURL = URL(fileURLWithPath: trashedFile.path)
            let destinationURL = URL(fileURLWithPath: originalPath)
            
            // Crea directory se non esiste
            let destinationDir = destinationURL.deletingLastPathComponent().path
            if !fileManager.fileExists(atPath: destinationDir) {
                try fileManager.createDirectory(atPath: destinationDir, withIntermediateDirectories: true)
            }
            
            // Se il file esiste già, crea una versione
            if fileManager.fileExists(atPath: originalPath) {
                if let sinistroPath = getSinistroPath(for: destinationURL) {
                    _ = createVersion(of: destinationURL, in: sinistroPath)
                }
                try fileManager.removeItem(at: destinationURL)
            }
            
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            
            // Rimuovi metadati
            let metadataPath = (trashedFile.path as NSString).appendingPathExtension("meta") ?? ""
            try? fileManager.removeItem(atPath: metadataPath)
            
            return true
        } catch {
            print("Errore ripristino dal cestino: \(error)")
            return false
        }
    }
    
    func permanentlyDelete(_ trashedFile: TrashedFile) -> Bool {
        do {
            try fileManager.removeItem(atPath: trashedFile.path)
            let metadataPath = (trashedFile.path as NSString).appendingPathExtension("meta") ?? ""
            try? fileManager.removeItem(atPath: metadataPath)
            return true
        } catch {
            print("Errore eliminazione permanente: \(error)")
            return false
        }
    }
    
    private func getSinistroPath(for url: URL) -> String? {
        let pathComponents = url.pathComponents
        for (index, component) in pathComponents.enumerated() {
            if component.count == 7 && component.allSatisfy({ $0.isNumber }) {
                let components = Array(pathComponents.prefix(index + 1))
                return "/" + components.joined(separator: "/")
            }
        }
        return nil
    }
}

struct FileVersion: Identifiable {
    let id = UUID()
    let path: String
    let timestamp: Int
    let size: Int64
    let description: String?
    
    init(path: String, timestamp: Int, size: Int64, description: String? = nil) {
        self.path = path
        self.timestamp = timestamp
        self.size = size
        self.description = description
    }
    
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var displayName: String {
        description ?? formattedDate
    }
}

struct TrashedFile: Identifiable {
    let id = UUID()
    let path: String
    let originalPath: String
    let fileName: String
    let deletedAt: TimeInterval
    
    var deletedDate: Date {
        Date(timeIntervalSince1970: deletedAt)
    }
    
    var formattedDeletedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: deletedDate)
    }
}

