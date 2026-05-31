import Foundation
import AppKit

/// Gestisce il download dei media WhatsApp e il salvataggio nella cartella sinistro
/// Ora comunica tramite Hub invece che direttamente con il Bridge
@MainActor
final class WhatsAppMediaService {
    static let shared = WhatsAppMediaService()
    
    private let hubClient = HubAPIClient.shared
    private let fileService = FileService.shared
    
    private let mediaFolderName = "da WA"
    private let indexFileName = ".perx-wa-media-index.json"
    
    private init() {}
    
    // MARK: - Download e Salvataggio
    
    /// Scarica un media dal bridge e lo salva nella cartella sinistro
    /// - Returns: Il path relativo del file salvato (es. "da WA/image_123.jpg")
    func downloadAndSaveMedia(
        accountId: String,
        messageId: String,
        sinistroRiferimento: String,
        suggestedFilename: String? = nil,
        mimeType: String? = nil
    ) async throws -> String {
        // 1. Ottieni il path della cartella sinistro
        guard let sinistroPath = fileService.getSinistroPath(riferimento: sinistroRiferimento) else {
            throw MediaError.sinistroFolderNotFound
        }
        
        // 2. Crea la sottocartella "da WA" se non esiste
        let mediaFolderPath = (sinistroPath as NSString).appendingPathComponent(mediaFolderName)
        try createDirectoryIfNeeded(at: mediaFolderPath, sinistroPath: sinistroPath)
        
        // 3. Scarica il media tramite Hub
        let mediaData = try await hubClient.localGetData(endpoint: "whatsapp/media/\(accountId)/\(messageId)")
        
        // 4. Determina il nome file stabile (ancorato al messageId)
        let filename = generateFilename(messageId: messageId, suggestedFilename: suggestedFilename, mimeType: mimeType)
        let filePath = (mediaFolderPath as NSString).appendingPathComponent(filename)
        
        // 5. Salva il file
        try saveFile(data: mediaData, to: filePath, sinistroPath: sinistroPath)
        
        // 6. Aggiorna indice locale + ritorna path relativo (legacy)
        let relative = "\(mediaFolderName)/\(filename)"
        updateIndex(mediaFolderPath: mediaFolderPath, mediaId: messageId, relativePath: relative, sinistroPath: sinistroPath)
        return relative
    }
    
    /// Verifica se un media esiste già localmente
    func mediaExists(relativePath: String, sinistroRiferimento: String) -> Bool {
        guard let sinistroPath = fileService.getSinistroPath(riferimento: sinistroRiferimento) else {
            return false
        }
        let fullPath = (sinistroPath as NSString).appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: fullPath)
    }
    
    /// Ottiene il path completo di un media
    func getMediaPath(relativePath: String, sinistroRiferimento: String) -> String? {
        guard let sinistroPath = fileService.getSinistroPath(riferimento: sinistroRiferimento) else {
            return nil
        }
        let fullPath = (sinistroPath as NSString).appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: fullPath) {
            return fullPath
        }
        return nil
    }
    
    /// Carica un'immagine dal path relativo
    func loadImage(relativePath: String, sinistroRiferimento: String) -> NSImage? {
        guard let fullPath = getMediaPath(relativePath: relativePath, sinistroRiferimento: sinistroRiferimento) else {
            return nil
        }
        return NSImage(contentsOfFile: fullPath)
    }
    
    /// Carica i dati di un file dal path relativo
    func loadData(relativePath: String, sinistroRiferimento: String) -> Data? {
        guard let fullPath = getMediaPath(relativePath: relativePath, sinistroRiferimento: sinistroRiferimento) else {
            return nil
        }
        return try? Data(contentsOf: URL(fileURLWithPath: fullPath))
    }
    
    // MARK: - Media ID resolution
    
    /// Risolve un media locale tramite `mediaId` (stabile, non dipende dal path).
    /// Cerca prima nell'indice, poi fa scan della cartella "da WA" per prefisso `mediaId__`.
    func resolveLocalMediaURL(mediaId: String, sinistroRiferimento: String) -> URL? {
        guard let sinistroPath = fileService.getSinistroPath(riferimento: sinistroRiferimento) else {
            return nil
        }
        let mediaFolderPath = (sinistroPath as NSString).appendingPathComponent(mediaFolderName)
        
        // 1) Index lookup
        if let relative = loadIndex(mediaFolderPath: mediaFolderPath, sinistroPath: sinistroPath)[mediaId] {
            let fullPath = (sinistroPath as NSString).appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: fullPath) {
                return URL(fileURLWithPath: fullPath)
            }
        }
        
        // 2) Scan per prefisso stabile
        guard FileManager.default.fileExists(atPath: mediaFolderPath) else { return nil }
        let prefix = "\(mediaId)__"
        
        if let urls = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: mediaFolderPath),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            if let match = urls.first(where: { $0.lastPathComponent.hasPrefix(prefix) }) {
                let relative = "\(mediaFolderName)/\(match.lastPathComponent)"
                updateIndex(mediaFolderPath: mediaFolderPath, mediaId: mediaId, relativePath: relative, sinistroPath: sinistroPath)
                return match
            }
        }
        
        return nil
    }
    
    // MARK: - Preparazione Media per Invio
    
    /// Prepara un file locale per l'invio (converte in base64)
    func prepareMediaForSending(filePath: String) throws -> (base64: String, mimeType: String) {
        let url = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: url)
        let base64 = data.base64EncodedString()
        let mimeType = getMimeType(for: url.pathExtension)
        return (base64, mimeType)
    }
    
    /// Prepara un file dalla cartella sinistro per l'invio
    func prepareMediaForSending(relativePath: String, sinistroRiferimento: String) throws -> (base64: String, mimeType: String, relativePath: String) {
        guard let fullPath = getMediaPath(relativePath: relativePath, sinistroRiferimento: sinistroRiferimento) else {
            throw MediaError.fileNotFound
        }
        let result = try prepareMediaForSending(filePath: fullPath)
        return (result.base64, result.mimeType, relativePath)
    }
    
    // MARK: - Private Helpers
    
    private func createDirectoryIfNeeded(at path: String, sinistroPath: String) throws {
        if FileManager.default.fileExists(atPath: path) { return }
        
        // I file sono ora in Application Support, accesso diretto
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
    
    private func saveFile(data: Data, to path: String, sinistroPath: String) throws {
        // I file sono ora in Application Support, accesso diretto
        try data.write(to: URL(fileURLWithPath: path))
    }
    
    private func generateFilename(messageId: String, suggestedFilename: String?, mimeType: String?) -> String {
        let ext = getExtension(for: mimeType)
        
        if let suggested = suggestedFilename, !suggested.isEmpty {
            let clean = sanitizeFilename(suggested)
            if (clean as NSString).pathExtension.isEmpty {
                return "\(messageId)__\(clean).\(ext)"
            }
            return "\(messageId)__\(clean)"
        }
        
        let timestamp = Int(Date().timeIntervalSince1970)
        return "\(messageId)__wa_\(timestamp).\(ext)"
    }
    
    private func sanitizeFilename(_ input: String) -> String {
        // Evita slash/colon ecc. (macOS/Windows friendly)
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = input.components(separatedBy: banned).joined(separator: "_")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func indexFilePath(mediaFolderPath: String) -> String {
        (mediaFolderPath as NSString).appendingPathComponent(indexFileName)
    }
    
    private func loadIndex(mediaFolderPath: String, sinistroPath: String) -> [String: String] {
        let path = indexFilePath(mediaFolderPath: mediaFolderPath)
        guard FileManager.default.fileExists(atPath: path) else { return [:] }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let obj = try JSONSerialization.jsonObject(with: data)
            return obj as? [String: String] ?? [:]
        } catch {
            return [:]
        }
    }
    
    private func saveIndex(_ index: [String: String], mediaFolderPath: String, sinistroPath: String) {
        let path = indexFilePath(mediaFolderPath: mediaFolderPath)
        do {
            let data = try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys])
            try saveFile(data: data, to: path, sinistroPath: sinistroPath)
        } catch {
            // best effort
        }
    }
    
    private func updateIndex(mediaFolderPath: String, mediaId: String, relativePath: String, sinistroPath: String) {
        var index = loadIndex(mediaFolderPath: mediaFolderPath, sinistroPath: sinistroPath)
        index[mediaId] = relativePath
        saveIndex(index, mediaFolderPath: mediaFolderPath, sinistroPath: sinistroPath)
    }
    
    private func getExtension(for mimeType: String?) -> String {
        guard let mimeType = mimeType else { return "bin" }
        
        switch mimeType.lowercased() {
        case let m where m.contains("jpeg") || m.contains("jpg"): return "jpg"
        case let m where m.contains("png"): return "png"
        case let m where m.contains("gif"): return "gif"
        case let m where m.contains("webp"): return "webp"
        case let m where m.contains("mp4"): return "mp4"
        case let m where m.contains("mov"): return "mov"
        case let m where m.contains("avi"): return "avi"
        case let m where m.contains("mp3"): return "mp3"
        case let m where m.contains("ogg"): return "ogg"
        case let m where m.contains("wav"): return "wav"
        case let m where m.contains("pdf"): return "pdf"
        case let m where m.contains("doc"): return "doc"
        case let m where m.contains("docx"): return "docx"
        case let m where m.contains("xls"): return "xls"
        case let m where m.contains("xlsx"): return "xlsx"
        case let m where m.contains("zip"): return "zip"
        default: return "bin"
        }
    }
    
    private func getMimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "avi": return "video/x-msvideo"
        case "mp3": return "audio/mpeg"
        case "ogg": return "audio/ogg"
        case "wav": return "audio/wav"
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Errors

enum MediaError: LocalizedError {
    case sinistroFolderNotFound
    case cannotCreateFolder
    case cannotSaveFile
    case fileNotFound
    
    var errorDescription: String? {
        switch self {
        case .sinistroFolderNotFound: return "Cartella sinistro non trovata"
        case .cannotCreateFolder: return "Impossibile creare la cartella media"
        case .cannotSaveFile: return "Impossibile salvare il file"
        case .fileNotFound: return "File non trovato"
        }
    }
}
