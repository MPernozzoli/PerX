import SwiftUI
import PDFKit

// MARK: - PDF Infinite Scroll View

/// Componente per visualizzazione PDF con scorrimento infinito e persistenza stato
struct PDFInfiniteScrollView: NSViewRepresentable {
    let url: URL
    @Binding var currentPageIndex: Int
    @Binding var showTagPopover: Bool
    @Binding var zoomLevel: CGFloat
    
    let onPageChanged: ((Int) -> Void)?
    let onZoomChanged: ((CGFloat) -> Void)?
    
    @StateObject private var statePersistence = PDFStatePersistenceService.shared
    private let fileService = FileService.shared
    
    init(
        url: URL,
        currentPageIndex: Binding<Int>,
        showTagPopover: Binding<Bool>,
        zoomLevel: Binding<CGFloat> = .constant(1.0),
        onPageChanged: ((Int) -> Void)? = nil,
        onZoomChanged: ((CGFloat) -> Void)? = nil
    ) {
        self.url = url
        self._currentPageIndex = currentPageIndex
        self._showTagPopover = showTagPopover
        self._zoomLevel = zoomLevel
        self.onPageChanged = onPageChanged
        self.onZoomChanged = onZoomChanged
    }
    
    func makeNSView(context: Context) -> InfinitePDFView {
        let pdfView = InfinitePDFView()
        pdfView.autoScales = false
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor.windowBackgroundColor
        pdfView.pageShadowsEnabled = false
        pdfView.pageBreakMargins = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        
        // Carica documento con security-scoped access
        loadDocument(into: pdfView, context: context)
        
        // Setup observers
        setupObservers(pdfView: pdfView, context: context)
        
        return pdfView
    }
    
    func updateNSView(_ nsView: InfinitePDFView, context: Context) {
        // Aggiorna URL se cambiato
        if context.coordinator.url != url {
            // Salva stato corrente prima di cambiare file
            if let oldUrl = context.coordinator.url {
                let state = nsView.captureState()
                PDFStatePersistenceService.shared.saveStateImmediately(state, for: oldUrl.path)
            }
            
            context.coordinator.url = url
            loadDocument(into: nsView, context: context)
        }
        
        // Aggiorna zoom se cambiato esternamente
        if abs(nsView.scaleFactor - zoomLevel) > 0.01 {
            NSAnimationContext.runAnimationGroup { animContext in
                animContext.duration = 0.2
                nsView.scaleFactor = zoomLevel
            }
        }
        
        // Vai alla pagina se cambiata esternamente
        if let document = nsView.document,
           currentPageIndex < document.pageCount,
           let page = document.page(at: currentPageIndex),
           nsView.currentPage != page {
            nsView.go(to: page)
        }
    }
    
    static func dismantleNSView(_ nsView: InfinitePDFView, coordinator: Coordinator) {
        coordinator.invalidate()
        
        // Salva stato finale
        if let url = coordinator.url {
            let state = nsView.captureState()
            Task { @MainActor in
                PDFStatePersistenceService.shared.saveStateImmediately(state, for: url.path)
            }
        }
    }
    
    private func loadDocument(into pdfView: InfinitePDFView, context: Context) {
        // Prova caricamento diretto
        if let document = PDFDocument(url: url) {
            setupDocument(document, in: pdfView, context: context)
            return
        }
        
        // Prova con Data
        if let data = try? Data(contentsOf: url), let document = PDFDocument(data: data) {
            setupDocument(document, in: pdfView, context: context)
            return
        }
        
        // Prova con security-scoped access
        let filePath = url.deletingLastPathComponent().path
        fileService.performWithSecurityScopedAccess(to: filePath) {
            if let document = PDFDocument(url: url) {
                setupDocument(document, in: pdfView, context: context)
            } else if let data = try? Data(contentsOf: url), let document = PDFDocument(data: data) {
                setupDocument(document, in: pdfView, context: context)
            } else {
                print("[PDFInfiniteScrollView] ❌ Impossibile caricare PDF: \(url.lastPathComponent)")
            }
        }
    }
    
    private func setupDocument(_ document: PDFDocument, in pdfView: InfinitePDFView, context: Context) {
        pdfView.document = document
        context.coordinator.pdfView = pdfView
        context.coordinator.document = document
        context.coordinator.url = url
        
        // Ripristina stato salvato
        Task { @MainActor in
            let savedState = PDFStatePersistenceService.shared.getState(for: url.path)
            
            // Applica stato con leggero delay per permettere il layout
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                pdfView.applyState(savedState, animated: true)
                
                // Aggiorna bindings
                currentPageIndex = savedState.pageIndex
                zoomLevel = savedState.zoomLevel
            }
        }
    }
    
    private func setupObservers(pdfView: InfinitePDFView, context: Context) {
        // Osserva cambio pagina
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        // Osserva cambio zoom
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scaleChanged),
            name: .PDFViewScaleChanged,
            object: pdfView
        )
        
        // Osserva ricaricamento file
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.reloadDocument),
            name: NSNotification.Name("MediaViewerReloadFile"),
            object: nil
        )
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentPageIndex: $currentPageIndex,
            showTagPopover: $showTagPopover,
            zoomLevel: $zoomLevel,
            url: url,
            fileService: fileService,
            onPageChanged: onPageChanged,
            onZoomChanged: onZoomChanged
        )
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject {
        weak var pdfView: InfinitePDFView?
        var document: PDFDocument?
        var url: URL?
        let fileService: FileService
        
        @Binding var currentPageIndex: Int
        @Binding var showTagPopover: Bool
        @Binding var zoomLevel: CGFloat
        
        let onPageChanged: ((Int) -> Void)?
        let onZoomChanged: ((CGFloat) -> Void)?
        
        private var isInvalidated = false
        private var saveStateDebounceTask: Task<Void, Never>?
        
        init(
            currentPageIndex: Binding<Int>,
            showTagPopover: Binding<Bool>,
            zoomLevel: Binding<CGFloat>,
            url: URL,
            fileService: FileService,
            onPageChanged: ((Int) -> Void)?,
            onZoomChanged: ((CGFloat) -> Void)?
        ) {
            _currentPageIndex = currentPageIndex
            _showTagPopover = showTagPopover
            _zoomLevel = zoomLevel
            self.url = url
            self.fileService = fileService
            self.onPageChanged = onPageChanged
            self.onZoomChanged = onZoomChanged
        }
        
        func invalidate() {
            isInvalidated = true
            saveStateDebounceTask?.cancel()
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func pageChanged(_ notification: Notification) {
            guard !isInvalidated, let pdfView = pdfView else { return }
            
            if let currentPage = pdfView.currentPage,
               let document = pdfView.document {
                let pageIndex = document.index(for: currentPage)
                
                if currentPageIndex != pageIndex && pageIndex >= 0 && pageIndex < document.pageCount {
                    DispatchQueue.main.async {
                        self.currentPageIndex = pageIndex
                        self.onPageChanged?(pageIndex)
                        self.scheduleStateSave()
                    }
                }
            }
        }
        
        @objc func scaleChanged(_ notification: Notification) {
            guard !isInvalidated, let pdfView = pdfView else { return }
            
            let newZoom = pdfView.scaleFactor
            if abs(zoomLevel - newZoom) > 0.01 {
                DispatchQueue.main.async {
                    self.zoomLevel = newZoom
                    self.onZoomChanged?(newZoom)
                    self.scheduleStateSave()
                }
            }
        }
        
        @objc func reloadDocument() {
            guard !isInvalidated, let pdfView = pdfView, let url = url else { return }
            
            // Salva stato corrente
            let currentState = pdfView.captureState()
            
            // Prova caricamento diretto
            if let newDocument = PDFDocument(url: url) {
                updatePDFView(pdfView, with: newDocument, restoreState: currentState)
                return
            }
            
            // Prova con Data
            if let data = try? Data(contentsOf: url), let newDocument = PDFDocument(data: data) {
                updatePDFView(pdfView, with: newDocument, restoreState: currentState)
                return
            }
            
            // Prova con security-scoped access
            let filePath = url.deletingLastPathComponent().path
            fileService.performWithSecurityScopedAccess(to: filePath) {
                if let newDocument = PDFDocument(url: url) {
                    updatePDFView(pdfView, with: newDocument, restoreState: currentState)
                } else if let data = try? Data(contentsOf: url), let newDocument = PDFDocument(data: data) {
                    updatePDFView(pdfView, with: newDocument, restoreState: currentState)
                }
            }
        }
        
        private func updatePDFView(_ pdfView: InfinitePDFView, with newDocument: PDFDocument, restoreState: PDFViewState) {
            pdfView.document = newDocument
            document = newDocument
            
            // Ripristina stato dopo un breve delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                pdfView.applyState(restoreState, animated: false)
            }
        }
        
        private func scheduleStateSave() {
            guard let pdfView = pdfView, let url = url else { return }
            
            saveStateDebounceTask?.cancel()
            saveStateDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                guard !Task.isCancelled else { return }
                
                let state = pdfView.captureState()
                PDFStatePersistenceService.shared.saveState(state, for: url.path)
            }
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// MARK: - Infinite PDF View (Custom PDFView)

class InfinitePDFView: PDFView {
    
    // Pre-caricamento pagine per performance
    private var preloadedPages: Set<Int> = []
    private let preloadRadius = 3 // Numero di pagine da precaricare in ogni direzione
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupInfiniteScroll()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupInfiniteScroll()
    }
    
    private func setupInfiniteScroll() {
        // Abilita scroll fluido
        if let scrollView = self.enclosingScrollView {
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
            
            // Elasticità per feedback visivo
            scrollView.verticalScrollElasticity = .allowed
            scrollView.horizontalScrollElasticity = .allowed
        }
    }
    
    override func layout() {
        super.layout()
        preloadAdjacentPages()
    }
    
    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        
        // Pre-carica pagine adiacenti durante lo scroll
        if event.phase == .ended || event.momentumPhase == .ended {
            preloadAdjacentPages()
        }
    }
    
    private func preloadAdjacentPages() {
        guard let document = self.document,
              let currentPage = self.currentPage else { return }
        
        let currentIndex = document.index(for: currentPage)
        let pageCount = document.pageCount
        
        // Calcola range di pagine da precaricare
        let startIndex = max(0, currentIndex - preloadRadius)
        let endIndex = min(pageCount - 1, currentIndex + preloadRadius)
        
        // Pre-carica le pagine
        for index in startIndex...endIndex {
            if !preloadedPages.contains(index),
               let page = document.page(at: index) {
                preloadPage(page)
                preloadedPages.insert(index)
            }
        }
        
        // Pulisci pagine lontane dalla memoria
        cleanupDistantPages(currentIndex: currentIndex, pageCount: pageCount)
    }
    
    private func preloadPage(_ page: PDFPage) {
        // Forza il rendering della pagina in background
        DispatchQueue.global(qos: .utility).async {
            let _ = page.thumbnail(of: CGSize(width: 200, height: 280), for: .mediaBox)
        }
    }
    
    private func cleanupDistantPages(currentIndex: Int, pageCount: Int) {
        // Rimuovi riferimenti a pagine troppo lontane
        let cleanupRadius = preloadRadius * 2
        preloadedPages = preloadedPages.filter { index in
            abs(index - currentIndex) <= cleanupRadius
        }
    }
    
    // MARK: - Zoom Gesture Handling
    
    override func magnify(with event: NSEvent) {
        // Calcola punto focale per zoom centrato sul mouse
        let locationInWindow = event.locationInWindow
        let locationInView = self.convert(locationInWindow, from: nil)
        
        // Calcola nuovo zoom
        let magnification = event.magnification
        let currentZoom = scaleFactor
        let newZoom = max(0.25, min(5.0, currentZoom * (1 + magnification)))
        
        // Applica zoom con animazione fluida
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.scaleFactor = newZoom
        }
        
        // Mantieni il punto focale centrato
        if let scrollView = enclosingScrollView {
            let zoomRatio = newZoom / currentZoom
            let newContentPoint = NSPoint(
                x: locationInView.x * zoomRatio,
                y: locationInView.y * zoomRatio
            )
            
            DispatchQueue.main.async {
                scrollView.contentView.scroll(to: newContentPoint)
            }
        }
    }
}

// MARK: - PDF Reset Controls View

struct PDFResetControlsView: View {
    let filePath: String
    let onResetToTop: () -> Void
    let onResetZoom: () -> Void
    let onResetPan: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            GlassmorphicIconButton(icon: "arrow.up.to.line", size: 24) {
                PDFStatePersistenceService.shared.resetToTop(for: filePath)
                onResetToTop()
            }
            .help("Torna in cima (⌘↑)")
            
            GlassmorphicIconButton(icon: "1.magnifyingglass", size: 24) {
                PDFStatePersistenceService.shared.resetZoom(for: filePath)
                onResetZoom()
            }
            .help("Reset Zoom (⌘0)")
            
            GlassmorphicIconButton(icon: "arrow.up.left.and.arrow.down.right", size: 24) {
                PDFStatePersistenceService.shared.resetPanOffset(for: filePath)
                onResetPan()
            }
            .help("Reset Posizionamento (⌘R)")
        }
    }
}
