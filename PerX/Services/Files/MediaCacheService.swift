import SwiftUI
import AppKit
import PDFKit

// MARK: - Media Cache Service

/// Servizio per cache intelligente e pre-caricamento media
/// Migliora le prestazioni di MediaViewer con gestione memoria efficiente
@MainActor
class MediaCacheService: ObservableObject {
    static let shared = MediaCacheService()
    
    // MARK: - Cache Storage
    
    /// Cache per immagini
    private let imageCache = NSCache<NSString, NSImage>()
    
    /// Cache per thumbnail
    private let thumbnailCache = NSCache<NSString, NSImage>()
    
    /// Cache per pagine PDF renderizzate
    private let pdfPageCache = NSCache<NSString, NSImage>()
    
    /// Task di pre-caricamento in corso
    private var preloadTasks: [String: Task<Void, Never>] = [:]
    
    /// Files recentemente acceduti per LRU
    private var recentlyAccessed: [String] = []
    private let maxRecentFiles = 50
    
    // MARK: - Configuration
    
    private let maxImageCacheSize = 100 // Numero massimo immagini in cache
    private let maxThumbnailCacheSize = 200
    private let maxPDFPageCacheSize = 50
    private let thumbnailSize = CGSize(width: 400, height: 400)
    
    private init() {
        imageCache.countLimit = maxImageCacheSize
        thumbnailCache.countLimit = maxThumbnailCacheSize
        pdfPageCache.countLimit = maxPDFPageCacheSize
        
        // Gestione memoria warning - macOS usa notifiche diverse
        // Monitoriamo quando l'app va in background per liberare memoria
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: NSApplication.didHideNotification,
            object: nil
        )
        
        // Monitora anche quando il sistema va in standby
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWillSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        
        // Monitora quando l'app va in background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
    }
    
    // MARK: - Image Cache
    
    /// Ottiene un'immagine dalla cache o la carica
    func getImage(for url: URL) async -> NSImage? {
        let key = url.path as NSString
        
        // Check cache
        if let cached = imageCache.object(forKey: key) {
            markAsAccessed(url.path)
            return cached
        }
        
        // Carica immagine
        let image = await loadImage(from: url)
        
        if let image = image {
            imageCache.setObject(image, forKey: key)
            markAsAccessed(url.path)
        }
        
        return image
    }
    
    /// Pre-carica immagini adiacenti
    func preloadImages(around currentURL: URL, in files: [URL], radius: Int = 2) {
        guard let currentIndex = files.firstIndex(of: currentURL) else { return }
        
        let startIndex = max(0, currentIndex - radius)
        let endIndex = min(files.count - 1, currentIndex + radius)
        
        for index in startIndex...endIndex {
            guard index != currentIndex else { continue }
            
            let fileURL = files[index]
            let key = fileURL.path
            
            // Già in cache?
            if imageCache.object(forKey: key as NSString) != nil {
                continue
            }
            
            // Già in pre-caricamento?
            if preloadTasks[key] != nil {
                continue
            }
            
            // Avvia pre-caricamento
            preloadTasks[key] = Task.detached(priority: .utility) { [weak self] in
                let _ = await self?.loadImage(from: fileURL)
                await MainActor.run {
                    self?.preloadTasks.removeValue(forKey: key)
                }
            }
        }
    }
    
    /// Cancella pre-caricamenti non più necessari
    func cancelPreloads(except urls: [URL]) {
        let keysToKeep = Set(urls.map { $0.path })
        
        for (key, task) in preloadTasks {
            if !keysToKeep.contains(key) {
                task.cancel()
                preloadTasks.removeValue(forKey: key)
            }
        }
    }
    
    // MARK: - Thumbnail Cache
    
    /// Ottiene thumbnail dalla cache o la genera
    func getThumbnail(for url: URL, size: CGSize? = nil) async -> NSImage? {
        let targetSize = size ?? thumbnailSize
        let key = "\(url.path)_\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
        
        // Check cache
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        
        // Genera thumbnail
        let thumbnail = await generateThumbnail(from: url, size: targetSize)
        
        if let thumbnail = thumbnail {
            thumbnailCache.setObject(thumbnail, forKey: key)
        }
        
        return thumbnail
    }
    
    // MARK: - PDF Page Cache
    
    /// Ottiene pagina PDF renderizzata dalla cache
    func getPDFPage(url: URL, pageIndex: Int, scale: CGFloat = 1.0) async -> NSImage? {
        let key = "\(url.path)_p\(pageIndex)_s\(Int(scale * 100))" as NSString
        
        // Check cache
        if let cached = pdfPageCache.object(forKey: key) {
            return cached
        }
        
        // Renderizza pagina
        let pageImage = await renderPDFPage(url: url, pageIndex: pageIndex, scale: scale)
        
        if let pageImage = pageImage {
            pdfPageCache.setObject(pageImage, forKey: key)
        }
        
        return pageImage
    }
    
    /// Pre-carica pagine PDF adiacenti
    func preloadPDFPages(url: URL, currentPage: Int, totalPages: Int, radius: Int = 3) {
        let startPage = max(0, currentPage - radius)
        let endPage = min(totalPages - 1, currentPage + radius)
        
        for pageIndex in startPage...endPage {
            guard pageIndex != currentPage else { continue }
            
            let key = "\(url.path)_p\(pageIndex)"
            
            // Già in cache?
            if pdfPageCache.object(forKey: "\(key)_s100" as NSString) != nil {
                continue
            }
            
            // Già in pre-caricamento?
            if preloadTasks[key] != nil {
                continue
            }
            
            // Avvia pre-caricamento
            preloadTasks[key] = Task.detached(priority: .utility) { [weak self] in
                let _ = await self?.getPDFPage(url: url, pageIndex: pageIndex)
                await MainActor.run {
                    self?.preloadTasks.removeValue(forKey: key)
                }
            }
        }
    }
    
    // MARK: - Memory Management
    
    /// Rimuove file dalla cache
    func removeFromCache(url: URL) {
        let key = url.path as NSString
        imageCache.removeObject(forKey: key)
        
        // Rimuovi anche thumbnail e pagine PDF correlate
        // (NSCache non supporta prefix matching, quindi dobbiamo usare un approccio diverso)
        recentlyAccessed.removeAll { $0 == url.path }
    }
    
    /// Pulisce la cache per liberare memoria
    func clearCache() {
        imageCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        pdfPageCache.removeAllObjects()
        recentlyAccessed.removeAll()
        
        // Cancella tutti i pre-caricamenti
        for task in preloadTasks.values {
            task.cancel()
        }
        preloadTasks.removeAll()
    }
    
    /// Pulisce le entries meno recenti
    func trimCache() {
        // Rimuovi files meno recenti se superiamo il limite
        if recentlyAccessed.count > maxRecentFiles {
            let toRemove = Array(recentlyAccessed.prefix(recentlyAccessed.count - maxRecentFiles))
            for path in toRemove {
                imageCache.removeObject(forKey: path as NSString)
            }
            recentlyAccessed = Array(recentlyAccessed.suffix(maxRecentFiles))
        }
    }
    
    @objc private func handleMemoryWarning() {
        print("[MediaCacheService] ⚠️ Memory warning - clearing cache")
        clearCache()
    }
    
    @objc private func handleSystemWillSleep() {
        print("[MediaCacheService] 💤 Sistema in standby - pulizia cache")
        clearCache()
    }
    
    @objc private func handleAppWillResignActive() {
        print("[MediaCacheService] 🔄 App in background - pulizia cache")
        clearCache()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    // MARK: - Private Helpers
    
    private func markAsAccessed(_ path: String) {
        // Rimuovi se già presente e aggiungi alla fine (LRU)
        recentlyAccessed.removeAll { $0 == path }
        recentlyAccessed.append(path)
        
        // Trim se necessario
        if recentlyAccessed.count > maxRecentFiles * 2 {
            trimCache()
        }
    }
    
    private func loadImage(from url: URL) async -> NSImage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Prova caricamento diretto
                if let image = NSImage(contentsOf: url) {
                    continuation.resume(returning: image)
                    return
                }
                
                // Prova con Data
                if let data = try? Data(contentsOf: url),
                   let image = NSImage(data: data) {
                    continuation.resume(returning: image)
                    return
                }
                
                // Prova con security-scoped access
                let fileService = FileService.shared
                let directoryPath = url.deletingLastPathComponent().path
                
                let result: NSImage? = fileService.performWithSecurityScopedAccess(to: directoryPath) {
                    if let image = NSImage(contentsOf: url) {
                        return image
                    }
                    if let data = try? Data(contentsOf: url),
                       let image = NSImage(data: data) {
                        return image
                    }
                    return nil
                } ?? nil
                
                continuation.resume(returning: result)
            }
        }
    }
    
    private func generateThumbnail(from url: URL, size: CGSize) async -> NSImage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let ext = url.pathExtension.lowercased()
                
                if ext == "pdf" {
                    // Thumbnail da PDF
                    if let document = PDFDocument(url: url),
                       let page = document.page(at: 0) {
                        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
                        continuation.resume(returning: thumbnail)
                        return
                    }
                } else {
                    // Thumbnail da immagine
                    if let image = NSImage(contentsOf: url) {
                        let aspectRatio = image.size.width / image.size.height
                        let targetWidth = min(size.width, size.height * aspectRatio)
                        let targetHeight = targetWidth / aspectRatio
                        let targetSize = CGSize(width: targetWidth, height: targetHeight)
                        
                        let thumbnail = NSImage(size: targetSize)
                        thumbnail.lockFocus()
                        image.draw(in: NSRect(origin: .zero, size: targetSize))
                        thumbnail.unlockFocus()
                        
                        continuation.resume(returning: thumbnail)
                        return
                    }
                }
                
                continuation.resume(returning: nil)
            }
        }
    }
    
    private func renderPDFPage(url: URL, pageIndex: Int, scale: CGFloat) async -> NSImage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let document = PDFDocument(url: url),
                      let page = document.page(at: pageIndex) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let pageRect = page.bounds(for: .mediaBox)
                let scaledSize = CGSize(
                    width: pageRect.width * scale,
                    height: pageRect.height * scale
                )
                
                let image = NSImage(size: scaledSize)
                image.lockFocus()
                
                if let context = NSGraphicsContext.current?.cgContext {
                    context.setFillColor(NSColor.white.cgColor)
                    context.fill(CGRect(origin: .zero, size: scaledSize))
                    context.scaleBy(x: scale, y: scale)
                    page.draw(with: .mediaBox, to: context)
                }
                
                image.unlockFocus()
                continuation.resume(returning: image)
            }
        }
    }
}

// MARK: - Preloader for File Lists

@MainActor
class FileListPreloader: ObservableObject {
    private var preloadTask: Task<Void, Never>?
    private let cacheService = MediaCacheService.shared
    
    /// Pre-carica thumbnail per una lista di file
    func preloadThumbnails(for urls: [URL], size: CGSize? = nil) {
        preloadTask?.cancel()
        
        preloadTask = Task {
            for url in urls {
                guard !Task.isCancelled else { break }
                let _ = await cacheService.getThumbnail(for: url, size: size)
            }
        }
    }
    
    /// Cancella pre-caricamento in corso
    func cancelPreload() {
        preloadTask?.cancel()
        preloadTask = nil
    }
    
    deinit {
        preloadTask?.cancel()
    }
}
