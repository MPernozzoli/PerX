import SwiftUI
import AppKit
import CoreData

// MARK: - Media Viewer Window Manager

/// Gestisce l'apertura di finestre MediaViewer con supporto per:
/// - Finestre separate per sinistri diversi
/// - Tab multipli per file dello stesso sinistro
/// - Intestazione distintiva per sinistro
@MainActor
class MediaViewerWindowManager: ObservableObject {
    static let shared = MediaViewerWindowManager()
    
    private static let windowIdentifierPrefix = "MediaViewer"
    
    @Published var isAlwaysOnTop: Bool = true
    @Published private(set) var openWindows: [String: WindowInfo] = [:] // windowIdentifier -> WindowInfo
    
    struct WindowInfo {
        let sinistroReference: String?
        let insuredName: String?
        var fileURLs: [URL]
        
        var displayTitle: String {
            if let ref = sinistroReference {
                if let name = insuredName {
                    return "\(ref) - \(name)"
                }
                return "Sinistro \(ref)"
            }
            return "Media Viewer"
        }
        
        var headerColor: Color {
            guard let ref = sinistroReference else {
                return .accentColor
            }
            let hash = ref.hashValue
            let hue = Double(abs(hash) % 360) / 360.0
            return Color(hue: hue, saturation: 0.6, brightness: 0.8)
        }
    }
    
    private init() {}
    
    // MARK: - Reference Extraction
    
    func extractReference(from url: URL) -> String? {
        let components = url.pathComponents
        for component in components {
            if component.count == 7 && component.allSatisfy({ $0.isNumber }) {
                return component
            }
        }
        return nil
    }
    
    private func fetchInsuredName(for reference: String) -> String? {
        let context = PersistenceController.shared.container.viewContext
        let request = Sinistro.fetchRequest
        request.predicate = NSPredicate(format: "riferimento == %@", reference)
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            return results.first?.nomeAssicurato
        } catch {
            print("[MediaViewerWindowManager] ❌ Errore fetch sinistro: \(error)")
            return nil
        }
    }
    
    private func windowIdentifier(for reference: String?) -> String {
        if let ref = reference {
            return "\(Self.windowIdentifierPrefix)-\(ref)"
        }
        return "\(Self.windowIdentifierPrefix)-Generic"
    }
    
    // MARK: - Open Media Viewer
    
    func openMediaViewer(for url: URL) {
        openMediaViewer(for: url, files: nil)
    }
    
    func openMediaViewer(for url: URL, files: [URL]?) {
        let reference = extractReference(from: url)
        let windowId = windowIdentifier(for: reference)
        let insuredName = reference != nil ? fetchInsuredName(for: reference!) : nil
        
        let windowTitle: String
        if let ref = reference {
            windowTitle = insuredName != nil ? "\(ref) - \(insuredName!)" : "Sinistro \(ref)"
        } else {
            windowTitle = "Media Viewer"
        }
        
        let tabId = url.path
        let tabTitle = url.lastPathComponent
        
        // Aggiorna tracking finestre
        if var windowInfo = openWindows[windowId] {
            if !windowInfo.fileURLs.contains(url) {
                windowInfo.fileURLs.append(url)
                openWindows[windowId] = windowInfo
            }
        } else {
            openWindows[windowId] = WindowInfo(
                sinistroReference: reference,
                insuredName: insuredName,
                fileURLs: [url]
            )
        }
        
        // Configurazione finestra
        let configuration = WindowConfiguration(
            identifier: windowId,
            title: windowTitle,
            minSize: CGSize(width: 800, height: 600),
            defaultSize: CGSize(width: 1200, height: 800),
            isAlwaysOnTop: isAlwaysOnTop
        )
        
        // Usa il nuovo MediaViewer2 con design glassmorphism
        let contentView = MediaViewer2(url: url, predefinedFiles: files)
            .environmentObject(self)
        
        // Apri tramite WindowManager centralizzato
        WindowManager.shared.openWindow(
            identifier: windowId,
            content: contentView,
            configuration: configuration,
            tabId: tabId,
            tabTitle: tabTitle
        )
    }
    
    /// Apre file multipli: se appartengono allo stesso sinistro li apre come tab,
    /// altrimenti apre finestre separate
    func openMediaViewer(forMultipleFiles urls: [URL]) {
        // Raggruppa file per sinistro
        var filesByReference: [String?: [URL]] = [:]
        
        for url in urls {
            let reference = extractReference(from: url)
            if filesByReference[reference] != nil {
                filesByReference[reference]?.append(url)
            } else {
                filesByReference[reference] = [url]
            }
        }
        
        // Apri finestra per ogni gruppo
        for (_, groupFiles) in filesByReference {
            guard let firstFile = groupFiles.first else { continue }
            
            // Apri il primo file con tutti i file del gruppo come predefiniti
            openMediaViewer(for: firstFile, files: groupFiles)
            
            // Aggiungi gli altri file come tab (se più di uno)
            if groupFiles.count > 1 {
                for file in groupFiles.dropFirst() {
                    addTabToExistingWindow(file)
                }
            }
        }
    }
    
    /// Aggiunge un file come tab a una finestra esistente (se dello stesso sinistro)
    func addTabToExistingWindow(_ url: URL) {
        let reference = extractReference(from: url)
        let windowId = windowIdentifier(for: reference)
        
        guard var windowInfo = openWindows[windowId] else {
            // Nessuna finestra esistente, aprila normalmente
            openMediaViewer(for: url)
            return
        }
        
        // Controlla se il file è già aperto
        if windowInfo.fileURLs.contains(url) {
            // Porta la finestra in primo piano
            if let window = WindowManager.shared.getWindow(identifier: windowId) {
                window.makeKeyAndOrderFront(nil)
            }
            return
        }
        
        // Aggiungi come nuova tab usando openWindow che gestisce già l'aggiunta
        windowInfo.fileURLs.append(url)
        openWindows[windowId] = windowInfo
        
        let insuredName = reference != nil ? fetchInsuredName(for: reference!) : nil
        let windowTitle = reference != nil ? (insuredName != nil ? "\(reference!) - \(insuredName!)" : "Sinistro \(reference!)") : "Media Viewer"
        
        let configuration = WindowConfiguration(
            identifier: windowId,
            title: windowTitle,
            minSize: CGSize(width: 800, height: 600),
            defaultSize: CGSize(width: 1200, height: 800),
            isAlwaysOnTop: isAlwaysOnTop
        )
        
        let contentView = MediaViewer2(url: url, predefinedFiles: nil)
            .environmentObject(self)
        
        WindowManager.shared.openWindow(
            identifier: windowId,
            content: contentView,
            configuration: configuration,
            tabId: url.path,
            tabTitle: url.lastPathComponent
        )
    }
    
    /// Apre un file in una nuova finestra (anche se dello stesso sinistro)
    func openMediaViewerInNewWindow(for url: URL) {
        let reference = extractReference(from: url)
        let insuredName = reference != nil ? fetchInsuredName(for: reference!) : nil
        
        // Genera un identificatore univoco per la nuova finestra
        let uniqueId = UUID().uuidString
        let baseWindowId = windowIdentifier(for: reference)
        let windowId = "\(baseWindowId)-\(uniqueId)"
        
        let windowTitle: String
        if let ref = reference {
            windowTitle = insuredName != nil ? "\(ref) - \(insuredName!)" : "Sinistro \(ref)"
        } else {
            windowTitle = "Media Viewer"
        }
        
        // Aggiungi al tracking
        openWindows[windowId] = WindowInfo(
            sinistroReference: reference,
            insuredName: insuredName,
            fileURLs: [url]
        )
        
        // Configurazione finestra
        let configuration = WindowConfiguration(
            identifier: windowId,
            title: windowTitle,
            minSize: CGSize(width: 800, height: 600),
            defaultSize: CGSize(width: 1200, height: 800),
            isAlwaysOnTop: isAlwaysOnTop
        )
        
        // Usa il nuovo MediaViewer2 con design glassmorphism
        let contentView = MediaViewer2(url: url, predefinedFiles: nil)
            .environmentObject(self)
        
        // Apri tramite WindowManager centralizzato
        WindowManager.shared.openWindow(
            identifier: windowId,
            content: contentView,
            configuration: configuration,
            tabId: url.path,
            tabTitle: url.lastPathComponent
        )
    }
    
    // MARK: - Close & Update
    
    func closeMediaViewer(for url: URL) {
        let reference = extractReference(from: url)
        let windowId = windowIdentifier(for: reference)
        
        // Rimuovi dal tracking
        if var windowInfo = openWindows[windowId] {
            windowInfo.fileURLs.removeAll { $0 == url }
            if windowInfo.fileURLs.isEmpty {
                openWindows.removeValue(forKey: windowId)
            } else {
                openWindows[windowId] = windowInfo
            }
        }
        
        WindowManager.shared.closeTab(identifier: windowId, tabId: url.path)
    }
    
    func closeAllForSinistro(_ reference: String) {
        let windowId = windowIdentifier(for: reference)
        openWindows.removeValue(forKey: windowId)
        WindowManager.shared.closeWindow(identifier: windowId)
    }
    
    func updateAlwaysOnTop(_ value: Bool) {
        isAlwaysOnTop = value
        
        // Aggiorna tutte le finestre aperte
        for windowId in openWindows.keys {
            WindowManager.shared.updateAlwaysOnTop(identifier: windowId, value: value)
        }
    }
    
    func updateFile(_ url: URL, previousURL: URL) {
        let reference = extractReference(from: url)
        let windowId = windowIdentifier(for: reference)
        
        WindowManager.shared.updateTabTitle(
            identifier: windowId,
            tabId: previousURL.path,
            newTitle: url.lastPathComponent
        )
    }
    
    // MARK: - Queries
    
    /// Restituisce true se una finestra per quel sinistro è già aperta
    func hasOpenWindow(for sinistroReference: String) -> Bool {
        let windowId = windowIdentifier(for: sinistroReference)
        return openWindows[windowId] != nil
    }
    
    /// Restituisce i file aperti per un sinistro
    func openFiles(for sinistroReference: String) -> [URL] {
        let windowId = windowIdentifier(for: sinistroReference)
        return openWindows[windowId]?.fileURLs ?? []
    }
    
    /// Restituisce le info della finestra per un sinistro
    func windowInfo(for sinistroReference: String) -> WindowInfo? {
        let windowId = windowIdentifier(for: sinistroReference)
        return openWindows[windowId]
    }
    
    /// Restituisce tutte le finestre aperte per un sinistro
    func windowsForSinistro(_ reference: String) -> [String: WindowInfo] {
        openWindows.filter { key, _ in
            key.hasPrefix("\(Self.windowIdentifierPrefix)-\(reference)")
        }
    }
    
    /// Rimuove una finestra dal tracking
    func removeWindow(_ windowId: String) {
        openWindows.removeValue(forKey: windowId)
    }
    
    /// Aggiorna le info di una finestra
    func updateWindowInfo(_ windowId: String, fileURLs: [URL]) {
        if var windowInfo = openWindows[windowId] {
            windowInfo.fileURLs = fileURLs
            openWindows[windowId] = windowInfo
        }
    }
}

