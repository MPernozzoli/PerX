import Foundation
import SwiftUI
import PDFKit

// MARK: - PDF View State

/// Struttura per memorizzare lo stato di visualizzazione di un PDF
struct PDFViewState: Codable, Equatable {
    var scrollPosition: CGFloat
    var zoomLevel: CGFloat
    var panOffset: CGSize
    var pageIndex: Int
    
    static let defaultState = PDFViewState(
        scrollPosition: 0,
        zoomLevel: 1.0,
        panOffset: .zero,
        pageIndex: 0
    )
    
    init(scrollPosition: CGFloat = 0, zoomLevel: CGFloat = 1.0, panOffset: CGSize = .zero, pageIndex: Int = 0) {
        self.scrollPosition = scrollPosition
        self.zoomLevel = zoomLevel
        self.panOffset = panOffset
        self.pageIndex = pageIndex
    }
    
    // Custom Codable for CGSize
    enum CodingKeys: String, CodingKey {
        case scrollPosition, zoomLevel, panOffsetWidth, panOffsetHeight, pageIndex
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scrollPosition = try container.decode(CGFloat.self, forKey: .scrollPosition)
        zoomLevel = try container.decode(CGFloat.self, forKey: .zoomLevel)
        let width = try container.decode(CGFloat.self, forKey: .panOffsetWidth)
        let height = try container.decode(CGFloat.self, forKey: .panOffsetHeight)
        panOffset = CGSize(width: width, height: height)
        pageIndex = try container.decode(Int.self, forKey: .pageIndex)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scrollPosition, forKey: .scrollPosition)
        try container.encode(zoomLevel, forKey: .zoomLevel)
        try container.encode(panOffset.width, forKey: .panOffsetWidth)
        try container.encode(panOffset.height, forKey: .panOffsetHeight)
        try container.encode(pageIndex, forKey: .pageIndex)
    }
}

// MARK: - PDF State Persistence Service

/// Servizio singleton per gestire la persistenza dello stato di visualizzazione dei PDF
@MainActor
class PDFStatePersistenceService: ObservableObject {
    static let shared = PDFStatePersistenceService()
    
    private let stateKeyPrefix = "PDFState_"
    private var stateCache: [String: PDFViewState] = [:]
    private var saveDebounceTask: Task<Void, Never>?
    
    private init() {
        loadAllStates()
    }
    
    // MARK: - Public API
    
    /// Ottiene lo stato salvato per un file PDF
    func getState(for filePath: String) -> PDFViewState {
        let key = normalizedKey(for: filePath)
        return stateCache[key] ?? .defaultState
    }
    
    /// Salva lo stato per un file PDF (con debounce)
    func saveState(_ state: PDFViewState, for filePath: String) {
        let key = normalizedKey(for: filePath)
        stateCache[key] = state
        
        // Debounce per evitare scritture frequenti
        saveDebounceTask?.cancel()
        saveDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            guard !Task.isCancelled else { return }
            persistState(state, forKey: key)
        }
    }
    
    /// Salva lo stato immediatamente (senza debounce) - usare su chiusura finestra
    func saveStateImmediately(_ state: PDFViewState, for filePath: String) {
        saveDebounceTask?.cancel()
        let key = normalizedKey(for: filePath)
        stateCache[key] = state
        persistState(state, forKey: key)
    }
    
    /// Aggiorna solo la posizione scroll
    func updateScrollPosition(_ position: CGFloat, for filePath: String) {
        var state = getState(for: filePath)
        state.scrollPosition = position
        saveState(state, for: filePath)
    }
    
    /// Aggiorna solo il livello di zoom
    func updateZoomLevel(_ zoom: CGFloat, for filePath: String) {
        var state = getState(for: filePath)
        state.zoomLevel = zoom
        saveState(state, for: filePath)
    }
    
    /// Aggiorna solo l'offset di pan
    func updatePanOffset(_ offset: CGSize, for filePath: String) {
        var state = getState(for: filePath)
        state.panOffset = offset
        saveState(state, for: filePath)
    }
    
    /// Aggiorna solo l'indice della pagina
    func updatePageIndex(_ index: Int, for filePath: String) {
        var state = getState(for: filePath)
        state.pageIndex = index
        saveState(state, for: filePath)
    }
    
    // MARK: - Reset Functions
    
    /// Reset completo: pagina 1, zoom 1.0, offset zero
    func resetToTop(for filePath: String) {
        saveStateImmediately(.defaultState, for: filePath)
    }
    
    /// Reset solo zoom a 1.0 (mantiene scroll e offset)
    func resetZoom(for filePath: String) {
        var state = getState(for: filePath)
        state.zoomLevel = 1.0
        saveStateImmediately(state, for: filePath)
    }
    
    /// Reset solo offset (mantiene zoom e scroll)
    func resetPanOffset(for filePath: String) {
        var state = getState(for: filePath)
        state.panOffset = .zero
        saveStateImmediately(state, for: filePath)
    }
    
    /// Rimuove lo stato salvato per un file
    func clearState(for filePath: String) {
        let key = normalizedKey(for: filePath)
        stateCache.removeValue(forKey: key)
        UserDefaults.standard.removeObject(forKey: stateKeyPrefix + key)
    }
    
    /// Rimuove tutti gli stati salvati
    func clearAllStates() {
        stateCache.removeAll()
        
        // Rimuovi tutti i valori con il prefisso
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(stateKeyPrefix) }
        keys.forEach { defaults.removeObject(forKey: $0) }
    }
    
    // MARK: - Private Helpers
    
    private func normalizedKey(for filePath: String) -> String {
        // Usa un hash del path per chiavi più corte
        return String(filePath.hashValue)
    }
    
    private func persistState(_ state: PDFViewState, forKey key: String) {
        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: stateKeyPrefix + key)
        } catch {
            print("[PDFStatePersistence] ❌ Errore salvataggio stato: \(error)")
        }
    }
    
    private func loadAllStates() {
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(stateKeyPrefix) }
        
        for fullKey in keys {
            let key = String(fullKey.dropFirst(stateKeyPrefix.count))
            if let data = defaults.data(forKey: fullKey),
               let state = try? JSONDecoder().decode(PDFViewState.self, from: data) {
                stateCache[key] = state
            }
        }
        
        print("[PDFStatePersistence] ✅ Caricati \(stateCache.count) stati PDF")
    }
}

// MARK: - PDFView Extension for State Management

extension PDFView {
    /// Applica uno stato salvato a questa PDFView
    func applyState(_ state: PDFViewState, animated: Bool = true) {
        guard let document = self.document else { return }
        
        // Vai alla pagina
        if state.pageIndex < document.pageCount,
           let page = document.page(at: state.pageIndex) {
            if animated {
                // Animazione fluida
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.go(to: page)
                }
            } else {
                self.go(to: page)
            }
        }
        
        // Applica zoom
        if state.zoomLevel != self.scaleFactor {
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    self.scaleFactor = state.zoomLevel
                }
            } else {
                self.scaleFactor = state.zoomLevel
            }
        }
        
        // Applica scroll position
        if state.scrollPosition > 0, let scrollView = self.enclosingScrollView {
            let point = NSPoint(x: state.panOffset.width, y: state.scrollPosition)
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    scrollView.contentView.scroll(to: point)
                }
            } else {
                scrollView.contentView.scroll(to: point)
            }
        }
    }
    
    /// Cattura lo stato corrente della PDFView
    func captureState() -> PDFViewState {
        var state = PDFViewState.defaultState
        
        // Pagina corrente
        if let currentPage = self.currentPage,
           let document = self.document {
            state.pageIndex = document.index(for: currentPage)
        }
        
        // Zoom level
        state.zoomLevel = self.scaleFactor
        
        // Scroll position
        if let scrollView = self.enclosingScrollView {
            let visibleRect = scrollView.contentView.documentVisibleRect
            state.scrollPosition = visibleRect.origin.y
            state.panOffset = CGSize(width: visibleRect.origin.x, height: 0)
        }
        
        return state
    }
}
