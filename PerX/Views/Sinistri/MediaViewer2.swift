import SwiftUI
import PDFKit
import AVKit

// MARK: - Media Viewer 2.0

/// MediaViewer completamente ridisegnato con:
/// - Design glassmorphism macOS 26
/// - Sistema tabbar multifile (stesso sinistro)
/// - Zoom persistente per foto/video/PDF
/// - Scorrimento PDF infinito
/// - Persistenza stato scroll/zoom/pan
struct MediaViewer2: View {
    let initialURL: URL
    let initialPredefinedFiles: [URL]?
    
    @EnvironmentObject var windowManager: MediaViewerWindowManager
    @ObservedObject private var fileTagManager = FileTagManager.shared
    @StateObject private var pdfStatePersistence = PDFStatePersistenceService.shared
    
    // Tab management
    @State private var tabs: [MediaTab] = []
    @State private var activeTabId: String = ""
    
    // Navigation
    @State private var currentURL: URL
    @State private var predefinedFiles: [URL]?
    @State private var currentFileIndex: Int = 0
    @State private var navigableFiles: [URL] = []
    @State private var navigationScope: NavigationScope = .currentFolder
    @State private var typeFilter: TypeFilter = .all
    @State private var tagFilter: TagFilter = .all
    
    // PDF state
    @State private var currentPageIndex: Int = 0
    @State private var totalPages: Int = 1
    @State private var zoomLevel: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    
    // UI state
    @State private var showTagPopover = false
    @State private var showQuickPhotoTagPanel = false
    @State private var showNavigationSettings = false
    @State private var showCompressionSheet = false
    @State private var isEditingTextField = false
    @State private var isViewActive = true
    
    // Search state
    @State private var searchText: String = ""
    @State private var searchResults: [OCRCacheService.SearchResult] = []
    @State private var currentSearchIndex: Int = 0
    
    // Edit state
    @State private var showCropSheet = false
    @State private var showHighlightSheet = false
    @State private var showOCRSheet = false
    @State private var showSignatureSheet = false
    @State private var showSignaturePopover = false
    @State private var ocrText: String = ""
    @State private var signatureOverlay: SignatureOverlayData?
    
    // Annotation state
    @State private var annotationMode: AnnotationMode? = nil
    @State private var annotationStrokeColor: Color = .yellow
    @State private var annotationFillColor: Color? = nil
    @State private var annotationStrokeWidth: CGFloat = 2.0
    @State private var annotationIsFilled: Bool = false
    @State private var annotationObfuscationIntensity: CGFloat = 0.8
    @State private var pdfViewReference: InfinitePDFView?
    
    @FocusState private var isViewFocused: Bool
    
    private let fileService = FileService.shared
    private let editorService = MediaEditorService.shared
    @StateObject private var signatureService = SignatureService.shared
    @StateObject private var placementService = SignaturePlacementService.shared
    @StateObject private var ocrCacheService = OCRCacheService.shared
    
    init(url: URL, predefinedFiles: [URL]? = nil) {
        self.initialURL = url
        self.initialPredefinedFiles = predefinedFiles
        _currentURL = State(initialValue: url)
        _predefinedFiles = State(initialValue: predefinedFiles)
    }
    
    /// File corrente - usa currentURL che è @State e quindi tracciato da SwiftUI
    private var currentFile: URL {
        currentURL
    }
    
    private var currentFileType: MediaFileType {
        MediaFileType(from: currentFile)
    }
    
    private var sinistroReference: String? {
        extractSinistroReference(from: currentFile)
    }
    
    private var windowIdentifier: String {
        if let ref = sinistroReference {
            return "MediaViewer-\(ref)"
        }
        return "MediaViewer-Generic"
    }
    
    private var shouldShowQuickPhotoTagPanel: Bool {
        currentFileType == .image && showQuickPhotoTagPanel
    }
    
    private var isCurrentFileUntagged: Bool {
        fileTagManager.getTagsForFile(at: currentFile.path).isEmpty
    }
    
    private var currentSinistroPath: String? {
        extractSinistroPath(from: currentFile)
    }
    
    // MARK: - Body
    
    var body: some View {
        mainContent
            .onAppear { setupView() }
            .modifier(ViewChangeHandlers(
                navigationScope: $navigationScope,
                typeFilter: $typeFilter,
                tagFilter: $tagFilter,
                currentFileIndex: $currentFileIndex,
                currentPageIndex: $currentPageIndex,
                predefinedFiles: predefinedFiles,
                onNavigationChange: loadNavigableFiles,
                onFileChange: handleFileChange,
                onPageChange: handlePageChange
            ))
            .modifier(PopoversAndSheets(
                showTagPopover: $showTagPopover,
                showNavigationSettings: $showNavigationSettings,
                showCompressionSheet: $showCompressionSheet,
                showCropSheet: $showCropSheet,
                showHighlightSheet: $showHighlightSheet,
                showOCRSheet: $showOCRSheet,
                showSignatureSheet: $showSignatureSheet,
                showSignaturePopover: $showSignaturePopover,
                ocrText: $ocrText,
                currentFile: currentFile,
                currentFileType: currentFileType,
                currentPageIndex: currentPageIndex,
                currentSinistroPath: currentSinistroPath,
                navigationScope: $navigationScope,
                typeFilter: $typeFilter,
                tagFilter: $tagFilter,
                navigableFilesCount: navigableFiles.count,
                onLoadNavigableFiles: loadNavigableFiles,
                onSignatureSelection: handleSignatureSelection
            ))
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MediaViewerReloadFile"))) { _ in
                guard isViewActive else { return }
                windowManager.updateFile(currentFile, previousURL: initialURL)
                updateTabTitle()
            }
            .onReceive(fileTagManager.objectWillChange) { _ in
                // Aggiorna titoli tab quando cambiano i tag
                updateTabTitle()
                updateWindowTitle()
            }
            .onDisappear {
                isViewActive = false
                saveCurrentState()
            }
            .modifier(KeyboardShortcuts(
                tabs: $tabs,
                activeTabId: $activeTabId,
                isEditingTextField: isEditingTextField,
                onTabSelect: handleTabSelect,
                onPrevious: navigateToPrevious,
                onNext: navigateToNext,
                onResetToTop: handleResetToTop,
                onResetZoom: handleResetZoom,
                onResetPan: handleResetPan,
                onSearchNext: handleSearchNext,
                onSearchPrevious: handleSearchPrevious
            ))
            .focusable()
            .focused($isViewFocused)
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            VisualEffectBlur(material: .sidebar)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Tabbar e toolbar sempre in alto con zIndex alto
                VStack(spacing: 0) {
                    tabBarSection
                    
                    // Annotation toolbar (se attiva)
                    if annotationMode != nil && currentFileType == .pdf {
                        PDFAnnotationToolbar(
                            annotationMode: $annotationMode,
                            strokeColor: $annotationStrokeColor,
                            fillColor: $annotationFillColor,
                            strokeWidth: $annotationStrokeWidth,
                            isFilled: $annotationIsFilled,
                            obfuscationIntensity: $annotationObfuscationIntensity
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    toolbarSection
                    GlassmorphicDivider()
                }
                .zIndex(100) // Assicura che rimanga sopra il contenuto zoommato
                
                // Contenuto principale
                contentSection
                
                // Photo tag panel sempre in fondo
                photoTagPanelSection
            }
        }
    }
    
    @ViewBuilder
    private var tabBarSection: some View {
        if tabs.count > 1 {
            MediaViewerTabBar(
                tabs: $tabs,
                activeTabId: $activeTabId,
                sinistroReference: sinistroReference,
                onTabClose: handleTabClose,
                onTabSelect: handleTabSelect,
                onTabOpenInNewWindow: handleTabOpenInNewWindow,
                onMergeWindows: hasMultipleWindowsForSinistro ? handleMergeWindows : nil
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    private var hasMultipleWindowsForSinistro: Bool {
        guard let ref = sinistroReference else { return false }
        let windowsForSinistro = windowManager.windowsForSinistro(ref)
        return windowsForSinistro.count > 1
    }
    
    private var toolbarSection: some View {
        MediaViewerToolbar2(
            url: currentFile,
            fileType: currentFileType,
            currentIndex: currentFileIndex + 1,
            totalFiles: navigableFiles.count,
            currentPageIndex: currentPageIndex,
            totalPages: totalPages,
            zoomLevel: zoomLevel,
            isPDF: currentFileType == .pdf,
            showTagPopover: $showTagPopover,
            showQuickPhotoTagPanel: $showQuickPhotoTagPanel,
            showNavigationSettings: $showNavigationSettings,
            navigationScope: $navigationScope,
            typeFilter: $typeFilter,
            tagFilter: $tagFilter,
            onClose: handleClose,
            onPrevious: navigateToPrevious,
            onNext: navigateToNext,
            onRotate: handleRotate,
            onCrop: { showCropSheet = true },
            onOCR: handleOCR,
            onSignature: handleSignature,
            onCompress: { showCompressionSheet = true },
            onResetToTop: handleResetToTop,
            onResetZoom: handleResetZoom,
            onResetPan: handleResetPan,
            onRemovePage: currentFileType == .pdf ? handleRemovePage : nil,
            onHighlight: currentFileType == .pdf ? { showHighlightSheet = true } : nil,
            onToggleAlwaysOnTop: handleToggleAlwaysOnTop,
            onAnnotationToggle: currentFileType == .pdf ? handleAnnotationToggle : nil,
            onSearch: handleSearch,
            onSearchNext: handleSearchNext,
            onSearchPrevious: handleSearchPrevious,
            isAlwaysOnTop: windowManager.isAlwaysOnTop,
            annotationMode: annotationMode,
            searchText: searchText.isEmpty ? nil : searchText,
            searchResultCount: searchResults.isEmpty ? nil : searchResults.count,
            currentSearchIndex: searchResults.isEmpty ? nil : currentSearchIndex
        )
    }
    
    private var contentSection: some View {
        contentView
            .id(currentURL.path) // Usa currentURL.path per forzare il refresh quando cambia file
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .animation(GlassmorphismDesignSystem.Animations.easeInOut, value: currentURL)
    }
    
    @ViewBuilder
    private var photoTagPanelSection: some View {
        if shouldShowQuickPhotoTagPanel {
            VStack(spacing: 0) {
                GlassmorphicDivider()
                
                ScrollView {
                    PhotoClassificationPanel(
                        filePath: currentFile.path,
                        sinistroPath: currentSinistroPath,
                        fileTagManager: fileTagManager,
                        isEditingTextField: $isEditingTextField
                    )
                    .padding(16)
                }
                .frame(maxHeight: 350)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        Group {
            switch currentFileType {
            case .image:
                ZoomableImageView(url: currentFile, showTagPopover: $showTagPopover)
                    .overlay {
                        if let overlay = signatureOverlay {
                            SignatureOverlayView(
                                overlay: Binding(
                                    get: { overlay },
                                    set: { signatureOverlay = $0; saveSignaturePlacement() }
                                ),
                                onRemove: removeSignaturePlacement
                            )
                        }
                    }
                    .overlay {
                        if !searchResults.isEmpty {
                            SearchHighlightOverlay(
                                searchResults: searchResults.filter { $0.filePath == currentFile.path },
                                currentSearchIndex: currentSearchIndex,
                                filePath: currentFile.path,
                                pageIndex: 0,
                                isPDF: false
                            )
                        }
                    }
                
            case .pdf:
                PDFInfiniteScrollView(
                    url: currentFile,
                    currentPageIndex: $currentPageIndex,
                    showTagPopover: $showTagPopover,
                    zoomLevel: $zoomLevel,
                    onPageChanged: { index in
                        currentPageIndex = index
                    },
                    onZoomChanged: { zoom in
                        zoomLevel = zoom
                    }
                )
                .overlay {
                    if let overlay = signatureOverlay,
                       let placement = placementService.getPlacement(for: currentFile.path),
                       placement.pageIndex == currentPageIndex {
                        SignatureOverlayView(
                            overlay: Binding(
                                get: { overlay },
                                set: { signatureOverlay = $0; saveSignaturePlacement() }
                            ),
                            onRemove: removeSignaturePlacement
                        )
                    }
                }
                .overlay {
                    // Annotation overlay (quando annotationMode è attivo)
                    if annotationMode != nil {
                        AnnotationOverlayWrapper(
                            filePath: currentFile.path,
                            pageIndex: currentPageIndex,
                            annotationMode: annotationMode,
                            strokeColor: $annotationStrokeColor,
                            fillColor: $annotationFillColor,
                            strokeWidth: $annotationStrokeWidth,
                            isFilled: $annotationIsFilled,
                            obfuscationIntensity: $annotationObfuscationIntensity
                        )
                    }
                }
                .overlay {
                    // Search highlight overlay
                    if !searchResults.isEmpty {
                        SearchHighlightOverlay(
                            searchResults: searchResults.filter { $0.filePath == currentFile.path && $0.pageIndex == currentPageIndex },
                            currentSearchIndex: currentSearchIndex,
                            filePath: currentFile.path,
                            pageIndex: currentPageIndex,
                            isPDF: true
                        )
                    }
                }
                .onAppear {
                    loadPDFInfo()
                }
                
            case .video:
                ZoomableVideoView(
                    url: currentFile,
                    scale: $zoomLevel,
                    offset: $panOffset
                )
                
            case .unknown:
                VStack(spacing: 12) {
                    Image(systemName: "doc.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Formato non supportato")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(navigationOverlay)
    }
    
    private var navigationOverlay: some View {
        HStack {
            if currentFileIndex > 0 {
                navigationButton(direction: .previous)
            } else {
                Spacer().frame(width: 60)
            }
            
            Spacer()
            
            if currentFileIndex < navigableFiles.count - 1 {
                navigationButton(direction: .next)
            } else {
                Spacer().frame(width: 60)
            }
        }
    }
    
    private func navigationButton(direction: NavigationDirection) -> some View {
        Button {
            if direction == .previous {
                navigateToPrevious()
            } else {
                navigateToNext()
            }
        } label: {
            Image(systemName: direction == .previous ? "chevron.left.circle.fill" : "chevron.right.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.white)
                .background(Circle().fill(Color.black.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .opacity(0.7)
    }
    
    private enum NavigationDirection {
        case previous, next
    }
    
    // MARK: - Setup & Navigation
    
    private func setupView() {
        // Inizializza tab con file corrente
        let initialTabTitle = getTabTitle(for: initialURL)
        tabs = [MediaTab(url: initialURL, title: initialTabTitle)]
        activeTabId = initialURL.path
        
        // Carica file navigabili
        if let predefined = predefinedFiles, !predefined.isEmpty {
            navigableFiles = predefined.sorted { $0.lastPathComponent < $1.lastPathComponent }
            if let index = navigableFiles.firstIndex(of: currentURL) {
                currentFileIndex = index
            }
        } else {
            if navigableFiles.isEmpty {
                navigableFiles = [currentURL]
                currentFileIndex = 0
            }
            loadNavigableFiles()
        }
        
        // Carica stato PDF se necessario
        if currentFileType == .pdf {
            restorePDFState()
        }
        
        // Aggiorna titolo finestra
        updateWindowTitle()
        
        // Focus per keyboard navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isViewFocused = true
        }
    }
    
    private func loadNavigableFiles() {
        if let predefined = predefinedFiles, !predefined.isEmpty {
            navigableFiles = predefined.sorted { $0.lastPathComponent < $1.lastPathComponent }
            if let index = navigableFiles.firstIndex(of: currentURL) {
                currentFileIndex = index
            }
            return
        }
        
        let directoryPath: String
        if navigationScope == .currentFolder {
            directoryPath = currentURL.deletingLastPathComponent().path
        } else {
            directoryPath = extractSinistroPath(from: currentURL) ?? currentURL.deletingLastPathComponent().path
        }
        
        var allFiles: [URL] = []
        if navigationScope == .sinistroDirectory {
            allFiles = getAllFilesRecursively(in: directoryPath)
        } else {
            let allItems = fileService.listContents(inDirectory: directoryPath)
            allFiles = allItems.filter { !$0.isDirectory }.map { $0.url }
        }
        
        // Applica filtri
        var files = allFiles
        
        switch typeFilter {
        case .pdf:
            files = files.filter { $0.pathExtension.lowercased() == "pdf" }
        case .media:
            let mediaExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp", "mp4", "mov", "avi", "mkv", "m4v"]
            files = files.filter { mediaExtensions.contains($0.pathExtension.lowercased()) }
        case .all:
            break
        }
        
        switch tagFilter {
        case .tagged:
            files = files.filter { !fileTagManager.getTagsForFile(at: $0.path).isEmpty }
        case .untagged:
            files = files.filter { fileTagManager.getTagsForFile(at: $0.path).isEmpty }
        case .all:
            break
        }
        
        navigableFiles = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        if let index = navigableFiles.firstIndex(of: currentURL) {
            currentFileIndex = index
        } else if !navigableFiles.isEmpty {
            currentFileIndex = 0
            currentURL = navigableFiles[0]
        }
    }
    
    private func navigateToPrevious() {
        guard isViewActive, currentFileIndex > 0 else { return }
        saveCurrentState()
        currentFileIndex -= 1
        currentPageIndex = 0
        let newFile = navigableFiles[currentFileIndex]
        currentURL = newFile
        
        // Aggiungi come tab se non esiste già
        if !tabs.contains(where: { $0.id == newFile.path }) {
            let tabTitle = getTabTitle(for: newFile)
            tabs.append(MediaTab(url: newFile, title: tabTitle))
        }
        
        // Attiva la tab del nuovo file
        activeTabId = newFile.path
        handleFileChange()
    }
    
    private func navigateToNext() {
        guard isViewActive, currentFileIndex < navigableFiles.count - 1 else { return }
        saveCurrentState()
        currentFileIndex += 1
        currentPageIndex = 0
        let newFile = navigableFiles[currentFileIndex]
        currentURL = newFile
        
        // Aggiungi come tab se non esiste già
        if !tabs.contains(where: { $0.id == newFile.path }) {
            let tabTitle = getTabTitle(for: newFile)
            tabs.append(MediaTab(url: newFile, title: tabTitle))
        }
        
        // Attiva la tab del nuovo file
        activeTabId = newFile.path
        handleFileChange()
    }
    
    // MARK: - Tab Handling
    
    private func handleTabClose(_ tabId: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        
        // Salva stato prima di chiudere
        if currentFileType == .pdf {
            saveCurrentState()
        }
        
        tabs.remove(at: index)
        
        if tabs.isEmpty {
            handleClose()
        } else if activeTabId == tabId {
            // Seleziona tab adiacente
            let newIndex = min(index, tabs.count - 1)
            activeTabId = tabs[newIndex].id
            currentURL = tabs[newIndex].url
            
            // Aggiorna currentFileIndex se il file è in navigableFiles
            if let fileIndex = navigableFiles.firstIndex(of: tabs[newIndex].url) {
                currentFileIndex = fileIndex
            }
            
            // Aggiorna titolo finestra
            updateWindowTitle()
            
            // Gestisci cambio file
            handleFileChange()
        }
    }
    
    private func handleTabSelect(_ tabId: String) {
        guard let tab = tabs.first(where: { $0.id == tabId }) else { return }
        
        // Salva stato del file corrente
        saveCurrentState()
        
        // Cambia al nuovo tab
        activeTabId = tabId
        currentURL = tab.url
        
        // Aggiorna currentFileIndex se il file è in navigableFiles
        if let index = navigableFiles.firstIndex(of: tab.url) {
            currentFileIndex = index
        }
        
        // Aggiorna titolo finestra
        updateWindowTitle()
        
        // Gestisci cambio file
        handleFileChange()
        
        // Ripristina stato se è un PDF
        if MediaFileType(from: tab.url) == .pdf {
            restorePDFState()
        }
    }
    
    // MARK: - File Change Handling
    
    private func handleFileChange() {
        // Apri automaticamente la barra rapida per foto non taggate solo se non è già aperta
        if currentFileType == .image {
            if !showQuickPhotoTagPanel {
                showQuickPhotoTagPanel = isCurrentFileUntagged
            }
        } else {
            showQuickPhotoTagPanel = false
        }
        
        // Carica firma per il nuovo file
        loadSignaturePlacement()
        
        // Aggiorna titolo finestra
        updateWindowTitle()
        
        // Aggiorna titolo tab se necessario
        updateTabTitle()
        
        // Ripristina stato PDF
        if currentFileType == .pdf {
            restorePDFState()
        }
    }
    
    private func handlePageChange() {
        if currentFileType == .pdf {
            loadSignaturePlacement()
        }
    }
    
    // MARK: - PDF State Management
    
    private func loadPDFInfo() {
        guard let document = PDFDocument(url: currentFile) else { return }
        totalPages = document.pageCount
    }
    
    private func restorePDFState() {
        let state = pdfStatePersistence.getState(for: currentFile.path)
        currentPageIndex = state.pageIndex
        zoomLevel = state.zoomLevel
        panOffset = state.panOffset
    }
    
    private func saveCurrentState() {
        guard currentFileType == .pdf else { return }
        
        let state = PDFViewState(
            scrollPosition: 0, // Gestito internamente da PDFInfiniteScrollView
            zoomLevel: zoomLevel,
            panOffset: panOffset,
            pageIndex: currentPageIndex
        )
        pdfStatePersistence.saveStateImmediately(state, for: currentFile.path)
    }
    
    private func handleResetToTop() {
        withAnimation(GlassmorphismDesignSystem.Animations.spring) {
            currentPageIndex = 0
            zoomLevel = 1.0
            panOffset = .zero
        }
        pdfStatePersistence.resetToTop(for: currentFile.path)
    }
    
    private func handleResetZoom() {
        withAnimation(GlassmorphismDesignSystem.Animations.spring) {
            zoomLevel = 1.0
        }
        pdfStatePersistence.resetZoom(for: currentFile.path)
    }
    
    private func handleResetPan() {
        withAnimation(GlassmorphismDesignSystem.Animations.spring) {
            panOffset = .zero
        }
        pdfStatePersistence.resetPanOffset(for: currentFile.path)
    }
    
    // MARK: - Actions
    
    private func handleClose() {
        guard isViewActive else { return }
        isViewActive = false
        saveCurrentState()
        windowManager.closeMediaViewer(for: initialURL)
    }
    
    private func handleRotate() {
        let fileType = currentFileType
        
        if fileType == .image {
            let success = editorService.rotateImage(at: currentFile, degrees: 90)
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
                }
            }
        } else if fileType == .pdf {
            let success = editorService.rotatePDFPage(at: currentFile, pageIndex: currentPageIndex, degrees: 90)
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
                }
            }
        }
    }
    
    private func handleRemovePage() {
        let alert = NSAlert()
        alert.messageText = "Rimuovere questa pagina?"
        alert.informativeText = "La pagina \(currentPageIndex + 1) verrà rimossa dal PDF. Questa azione non può essere annullata."
        alert.addButton(withTitle: "Rimuovi")
        alert.addButton(withTitle: "Annulla")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            let success = editorService.removePDFPage(at: currentFile, pageIndex: currentPageIndex)
            if success {
                if currentPageIndex > 0 {
                    currentPageIndex -= 1
                }
                NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
            }
        }
    }
    
    private func handleOCR() {
        showOCRSheet = true
        ocrText = ""
        
        if currentFileType == .image {
            // Controlla se è già in cache
            if let cachedText = ocrCacheService.getOCRText(for: currentFile.path) {
                ocrText = cachedText
            } else {
                editorService.performOCRWithCoordinates(on: currentFile) { result in
                    DispatchQueue.main.async {
                        guard let result = result else {
                            self.ocrText = "Nessun testo riconosciuto"
                            return
                        }
                        self.ocrText = result.text
                        self.ocrCacheService.saveOCRText(result.text, for: self.currentFile.path, textRanges: result.textRanges)
                    }
                }
            }
        } else if currentFileType == .pdf {
            // Controlla se è già in cache
            if let cachedText = ocrCacheService.getOCRText(for: currentFile.path, pageIndex: currentPageIndex) {
                ocrText = cachedText
            } else {
                editorService.performOCROnPDFPageWithCoordinates(at: currentFile, pageIndex: currentPageIndex) { result in
                    DispatchQueue.main.async {
                        guard let result = result else {
                            self.ocrText = "Nessun testo riconosciuto"
                            return
                        }
                        self.ocrText = result.text
                        self.ocrCacheService.saveOCRText(result.text, for: self.currentFile.path, pageIndex: self.currentPageIndex, textRanges: result.textRanges)
                    }
                }
            }
        }
    }
    
    private func handleSignature() {
        let availableSignatures = signatureService.getAvailableSignatures()
        
        if availableSignatures.isEmpty {
            return
        } else if availableSignatures.count == 1 {
            let signatureType = signatureService.individualSignature != nil ? "individual" : "studio"
            handleSignatureSelection(signatureType: signatureType)
        } else {
            showSignaturePopover = true
        }
    }
    
    private func handleSignatureSelection(signatureType: String) {
        showSignaturePopover = false
        
        let pageIndex = currentFileType == .pdf ? currentPageIndex : nil
        let savedPlacement = placementService.getPlacement(for: currentFile.path)
        let useSaved = savedPlacement != nil && savedPlacement?.pageIndex == pageIndex
        
        let defaultPosition = useSaved ? savedPlacement!.position : CGPoint(x: 50, y: 50)
        let defaultSize = useSaved ? savedPlacement!.size : CGSize(width: 150, height: 60)
        
        let signatureImage: NSImage?
        if signatureType == "individual" {
            signatureImage = signatureService.individualSignature
        } else {
            signatureImage = signatureService.studioSignature
        }
        
        guard let image = signatureImage else { return }
        
        signatureOverlay = SignatureOverlayData(
            image: image,
            signatureType: signatureType,
            position: defaultPosition,
            size: defaultSize
        )
        
        if currentFileType == .pdf {
            Task { @MainActor in
                _ = editorService.addSignatureToPDF(
                    at: currentFile,
                    pageIndex: currentPageIndex,
                    signature: image,
                    position: defaultPosition,
                    size: defaultSize,
                    createVersion: false,
                    asAnnotation: true
                )
                NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
            }
        }
    }
    
    private func saveSignaturePlacement() {
        guard let overlay = signatureOverlay else { return }
        
        let signatureImageData: Data?
        if let tiffData = overlay.image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            signatureImageData = pngData
        } else {
            signatureImageData = nil
        }
        
        let placement = SignaturePlacementService.SignaturePlacement(
            filePath: currentFile.path,
            signatureType: overlay.signatureType,
            position: overlay.position,
            size: overlay.size,
            pageIndex: currentFileType == .pdf ? currentPageIndex : nil,
            signatureImageData: signatureImageData
        )
        
        placementService.setPlacement(placement)
    }
    
    private func removeSignaturePlacement() {
        signatureOverlay = nil
        placementService.removePlacement(for: currentFile.path)
    }
    
    private func loadSignaturePlacement() {
        let fileType = currentFileType
        let pageIndex = fileType == .pdf ? currentPageIndex : nil
        
        if let placement = placementService.getPlacement(for: currentFile.path),
           placement.pageIndex == pageIndex {
            let signatureImage: NSImage?
            if placement.signatureType == "individual" {
                signatureImage = signatureService.individualSignature
            } else {
                signatureImage = signatureService.studioSignature
            }
            
            if let image = signatureImage {
                signatureOverlay = SignatureOverlayData(
                    image: image,
                    signatureType: placement.signatureType,
                    position: placement.position,
                    size: placement.size
                )
            }
        } else {
            signatureOverlay = nil
        }
    }
    
    private func handleToggleAlwaysOnTop() {
        let newValue = !windowManager.isAlwaysOnTop
        windowManager.updateAlwaysOnTop(newValue)
        WindowManager.shared.updateAlwaysOnTop(identifier: windowIdentifier, value: newValue)
    }
    
    private func handleAnnotationToggle() {
        withAnimation(GlassmorphismDesignSystem.Animations.spring) {
            if annotationMode == nil {
                // Attiva modalità evidenziazione di default
                annotationMode = .highlight
            } else {
                // Disattiva
                annotationMode = nil
            }
        }
    }
    
    // MARK: - Helpers
    
    private func extractSinistroReference(from url: URL) -> String? {
        let components = url.pathComponents
        for component in components {
            if component.count == 7 && component.allSatisfy({ $0.isNumber }) {
                return component
            }
        }
        return nil
    }
    
    private func extractSinistroPath(from url: URL) -> String? {
        let components = url.pathComponents
        for (index, component) in components.enumerated() {
            if component.count == 7 && component.allSatisfy({ $0.isNumber }) {
                let prefix = Array(components[0...index])
                if prefix.first == "/" {
                    return "/" + prefix.dropFirst().joined(separator: "/")
                }
                return prefix.joined(separator: "/")
            }
        }
        return nil
    }
    
    private func getAllFilesRecursively(in directoryPath: String) -> [URL] {
        var files: [URL] = []
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(atPath: directoryPath) else {
            return files
        }
        
        for case let path as String in enumerator {
            let fullPath = (directoryPath as NSString).appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            
            if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) && !isDirectory.boolValue {
                files.append(URL(fileURLWithPath: fullPath))
            }
        }
        
        return files
    }
    
    // MARK: - Window Title & Tab Title Management
    
    private func updateWindowTitle(retryCount: Int = 0) {
        // Trova la finestra - prova prima con l'identificatore esatto, poi cerca finestre con prefisso
        let reference = sinistroReference
        var window: NSWindow? = nil
        
        if let ref = reference {
            // Cerca finestre per questo sinistro
            let windowsForSinistro = windowManager.windowsForSinistro(ref)
            for (windowId, _) in windowsForSinistro {
                if let w = WindowManager.shared.getWindow(identifier: windowId) {
                    window = w
                    break
                }
            }
        }
        
        // Fallback all'identificatore base
        if window == nil {
            window = WindowManager.shared.getWindow(identifier: windowIdentifier)
        }
        
        guard let window = window else {
            // La finestra potrebbe non essere ancora stata creata, riprova dopo un breve delay
            if retryCount < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
                    updateWindowTitle(retryCount: retryCount + 1)
                }
            }
            return
        }
        
        guard let ref = reference else {
            // Nessun riferimento, usa titolo generico
            window.title = "Media Viewer - \(currentFile.lastPathComponent)"
            return
        }
        
        // Recupera dati sinistro
        let context = PersistenceController.shared.container.viewContext
        let request = Sinistro.fetchRequest
        request.predicate = NSPredicate(format: "riferimento == %@", ref)
        request.fetchLimit = 1
        
        var insuredName: String?
        var dataSinistro: Date?
        
        do {
            if let sinistro = try context.fetch(request).first {
                insuredName = sinistro.nomeAssicurato
                dataSinistro = sinistro.dataSinistro
            }
        } catch {
            print("[MediaViewer2] ❌ Errore fetch sinistro: \(error)")
        }
        
        // Costruisci titolo: [riferimento] - [nome assicurato] - [data sinistro] - [nome file]
        var titleParts: [String] = [ref]
        
        if let name = insuredName, !name.isEmpty {
            titleParts.append(name)
        }
        
        if let data = dataSinistro {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            formatter.locale = Locale(identifier: "it_IT")
            titleParts.append(formatter.string(from: data))
        }
        
        titleParts.append(currentFile.lastPathComponent)
        
        window.title = titleParts.joined(separator: " - ")
    }
    
    private func getTabTitle(for url: URL) -> String {
        let tags = fileTagManager.getTagsForFile(at: url.path)
        if let firstTag = tags.first {
            return firstTag.name
        }
        return url.lastPathComponent
    }
    
    private func updateTabTitle() {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == activeTabId }) else { return }
        
        let tabTitle = getTabTitle(for: currentFile)
        
        // Aggiorna il titolo della tab se è cambiato
        if tabs[tabIndex].title != tabTitle {
            tabs[tabIndex].title = tabTitle
            
            // Aggiorna anche il titolo della tab nel WindowManager
            let reference = sinistroReference
            let windowId = windowIdentifier
            WindowManager.shared.updateTabTitle(
                identifier: windowId,
                tabId: activeTabId,
                newTitle: tabTitle
            )
        }
    }
    
    // MARK: - Tab Actions
    
    private func handleTabOpenInNewWindow(_ tabId: String) {
        guard let tab = tabs.first(where: { $0.id == tabId }) else { return }
        
        // Apri il file in una nuova finestra
        windowManager.openMediaViewerInNewWindow(for: tab.url)
    }
    
    private func handleMergeWindows() {
        guard let ref = sinistroReference else { return }
        
        // Raccogli tutte le tab da tutte le finestre per questo sinistro
        var allTabs: [MediaTab] = []
        var windowsToClose: [String] = []
        let currentWindowId = windowIdentifier
        
        // Aggiungi le tab della finestra corrente
        allTabs.append(contentsOf: tabs)
        
        // Trova tutte le altre finestre per questo sinistro
        let allWindows = windowManager.windowsForSinistro(ref)
        for (windowId, windowInfo) in allWindows {
            if windowId != currentWindowId {
                // Raccogli le tab da questa finestra
                for fileURL in windowInfo.fileURLs {
                    let tabTitle = getTabTitle(for: fileURL)
                    if !allTabs.contains(where: { $0.id == fileURL.path }) {
                        allTabs.append(MediaTab(url: fileURL, title: tabTitle))
                    }
                }
                windowsToClose.append(windowId)
            }
        }
        
        // Aggiorna le tab della finestra corrente
        tabs = allTabs
        
        // Aggiorna il tracking nel windowManager
        windowManager.updateWindowInfo(currentWindowId, fileURLs: allTabs.map { $0.url })
        
        // Chiudi le altre finestre
        for windowId in windowsToClose {
            windowManager.removeWindow(windowId)
            WindowManager.shared.closeWindow(identifier: windowId)
        }
        
        // Aggiorna il titolo della finestra
        updateWindowTitle()
    }
    
    // MARK: - Search
    
    private func handleSearch(_ text: String) {
        searchText = text
        
        if text.isEmpty {
            searchResults = []
            currentSearchIndex = 0
        } else {
            // Cerca in tutti i file navigabili
            let filePaths = navigableFiles.map { $0.path }
            let allResults = ocrCacheService.searchInCache(text, in: filePaths)
            
            // Filtra risultati per file/pagina corrente e ordina
            var filteredResults: [OCRCacheService.SearchResult] = []
            for result in allResults {
                if result.filePath == currentFile.path {
                    if currentFileType == .pdf {
                        if result.pageIndex == currentPageIndex {
                            filteredResults.append(result)
                        }
                    } else {
                        filteredResults.append(result)
                    }
                }
            }
            
            // Se non ci sono risultati nel file corrente, prendi tutti i risultati
            if filteredResults.isEmpty {
                searchResults = allResults
            } else {
                searchResults = filteredResults
            }
            
            currentSearchIndex = 0
            
            // Se ci sono risultati, vai al primo
            if !searchResults.isEmpty {
                navigateToSearchResult(at: 0)
            }
        }
    }
    
    private func handleSearchNext() {
        guard !searchResults.isEmpty else { return }
        
        // Trova il prossimo risultato (anche in altri file/pagine)
        let currentResult = searchResults[currentSearchIndex]
        var nextIndex = currentSearchIndex + 1
        
        if nextIndex >= searchResults.count {
            // Cerca nel prossimo file/pagina
            let allFilePaths = navigableFiles.map { $0.path }
            let allResults = ocrCacheService.searchInCache(searchText, in: allFilePaths)
            
            // Trova il prossimo risultato dopo quello corrente
            if let currentIndexInAll = allResults.firstIndex(where: { 
                $0.filePath == currentResult.filePath && 
                $0.pageIndex == currentResult.pageIndex &&
                $0.occurrenceIndex == currentResult.occurrenceIndex
            }) {
                nextIndex = currentIndexInAll + 1
                if nextIndex < allResults.count {
                    searchResults = allResults
                    currentSearchIndex = nextIndex
                    navigateToSearchResult(at: nextIndex)
                    return
                }
            }
            
            // Torna al primo
            nextIndex = 0
        }
        
        currentSearchIndex = nextIndex
        navigateToSearchResult(at: nextIndex)
    }
    
    private func handleSearchPrevious() {
        guard !searchResults.isEmpty else { return }
        
        // Trova il risultato precedente
        let currentResult = searchResults[currentSearchIndex]
        var prevIndex = currentSearchIndex - 1
        
        if prevIndex < 0 {
            // Cerca nel file/pagina precedente
            let allFilePaths = navigableFiles.map { $0.path }
            let allResults = ocrCacheService.searchInCache(searchText, in: allFilePaths)
            
            // Trova il risultato precedente
            if let currentIndexInAll = allResults.firstIndex(where: { 
                $0.filePath == currentResult.filePath && 
                $0.pageIndex == currentResult.pageIndex &&
                $0.occurrenceIndex == currentResult.occurrenceIndex
            }) {
                prevIndex = currentIndexInAll - 1
                if prevIndex >= 0 {
                    searchResults = allResults
                    currentSearchIndex = prevIndex
                    navigateToSearchResult(at: prevIndex)
                    return
                }
            }
            
            // Vai all'ultimo
            prevIndex = allResults.count - 1
            searchResults = allResults
        }
        
        currentSearchIndex = prevIndex
        navigateToSearchResult(at: prevIndex)
    }
    
    private func navigateToSearchResult(at index: Int) {
        guard index < searchResults.count else { return }
        let result = searchResults[index]
        
        // Naviga al file se necessario
        if let fileURL = navigableFiles.first(where: { $0.path == result.filePath }) {
            // Se non è il file corrente, cambia file
            if fileURL != currentFile {
                // Aggiungi come tab se non esiste
                if !tabs.contains(where: { $0.id == fileURL.path }) {
                    let tabTitle = getTabTitle(for: fileURL)
                    tabs.append(MediaTab(url: fileURL, title: tabTitle))
                }
                
                // Attiva la tab
                activeTabId = fileURL.path
                currentURL = fileURL
                
                if let fileIndex = navigableFiles.firstIndex(of: fileURL) {
                    currentFileIndex = fileIndex
                }
                
                handleFileChange()
            }
            
            // Se è un PDF, vai alla pagina corretta
            if currentFileType == .pdf && result.pageIndex != currentPageIndex {
                currentPageIndex = result.pageIndex
                handlePageChange()
            }
            
            // Aggiorna i risultati filtrati per il file/pagina corrente
            let allFilePaths = navigableFiles.map { $0.path }
            let allResults = ocrCacheService.searchInCache(searchText, in: allFilePaths)
            var filteredResults: [OCRCacheService.SearchResult] = []
            for res in allResults {
                if res.filePath == result.filePath {
                    if currentFileType == .pdf {
                        if res.pageIndex == result.pageIndex {
                            filteredResults.append(res)
                        }
                    } else {
                        filteredResults.append(res)
                    }
                }
            }
            
            // Trova l'indice corretto nei risultati filtrati
            if let localIndex = filteredResults.firstIndex(where: {
                $0.occurrenceIndex == result.occurrenceIndex
            }) {
                searchResults = filteredResults
                currentSearchIndex = localIndex
            }
        }
    }
}

// MARK: - MediaFileType Extension

extension MediaFileType {
    var toOldFileType: MediaViewer.FileType {
        switch self {
        case .image: return .image
        case .pdf: return .pdf
        case .video: return .video
        case .unknown: return .unknown
        }
    }
}

// MARK: - Helper Modifiers

private struct ViewChangeHandlers: ViewModifier {
    @Binding var navigationScope: NavigationScope
    @Binding var typeFilter: TypeFilter
    @Binding var tagFilter: TagFilter
    @Binding var currentFileIndex: Int
    @Binding var currentPageIndex: Int
    let predefinedFiles: [URL]?
    let onNavigationChange: () -> Void
    let onFileChange: () -> Void
    let onPageChange: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onChange(of: navigationScope) { _ in
                guard predefinedFiles == nil else { return }
                onNavigationChange()
            }
            .onChange(of: typeFilter) { _ in
                guard predefinedFiles == nil else { return }
                onNavigationChange()
            }
            .onChange(of: tagFilter) { _ in
                guard predefinedFiles == nil else { return }
                onNavigationChange()
            }
            .onChange(of: currentFileIndex) { _ in
                onFileChange()
            }
            .onChange(of: currentPageIndex) { _ in
                onPageChange()
            }
    }
}

private struct PopoversAndSheets: ViewModifier {
    @Binding var showTagPopover: Bool
    @Binding var showNavigationSettings: Bool
    @Binding var showCompressionSheet: Bool
    @Binding var showCropSheet: Bool
    @Binding var showHighlightSheet: Bool
    @Binding var showOCRSheet: Bool
    @Binding var showSignatureSheet: Bool
    @Binding var showSignaturePopover: Bool
    @Binding var ocrText: String
    
    let currentFile: URL
    let currentFileType: MediaFileType
    let currentPageIndex: Int
    let currentSinistroPath: String?
    @Binding var navigationScope: NavigationScope
    @Binding var typeFilter: TypeFilter
    @Binding var tagFilter: TagFilter
    let navigableFilesCount: Int
    let onLoadNavigableFiles: () -> Void
    let onSignatureSelection: (String) -> Void
    
    func body(content: Content) -> some View {
        content
            .popover(isPresented: $showTagPopover, attachmentAnchor: .point(.top), arrowEdge: .top) {
                tagPopoverContent
            }
            .popover(isPresented: $showNavigationSettings) {
                navigationPopoverContent
            }
            .sheet(isPresented: $showCompressionSheet) {
                CompressionSheet(url: currentFile, fileType: currentFileType.toOldFileType)
            }
            .sheet(isPresented: $showCropSheet) {
                CropSheet(url: currentFile, fileType: currentFileType.toOldFileType, currentPageIndex: currentPageIndex)
            }
            .sheet(isPresented: $showHighlightSheet) {
                HighlightSheet(url: currentFile, pageIndex: currentPageIndex)
            }
            .sheet(isPresented: $showOCRSheet) {
                OCRSheet(text: $ocrText)
            }
            .sheet(isPresented: $showSignatureSheet) {
                SignatureSheet(url: currentFile, fileType: currentFileType.toOldFileType, pageIndex: currentPageIndex)
            }
            .popover(isPresented: $showSignaturePopover, attachmentAnchor: .point(.center)) {
                SignatureSelectionPopover(onSelect: onSignatureSelection)
            }
    }
    
    @ViewBuilder
    private var tagPopoverContent: some View {
        let context: UnifiedTagView.Context = currentFileType == .pdf ?
            .pdfPage(currentFile, pageIndex: currentPageIndex) :
            .file(currentFile)
        UnifiedTagView(context: context, sinistroPath: currentSinistroPath)
    }
    
    private var navigationPopoverContent: some View {
        NavigationFiltersPopover(
            navigationScope: $navigationScope,
            typeFilter: $typeFilter,
            tagFilter: $tagFilter,
            totalFiles: navigableFilesCount,
            filteredCount: navigableFilesCount,
            onReset: onLoadNavigableFiles
        )
    }
}

private struct KeyboardShortcuts: ViewModifier {
    @Binding var tabs: [MediaTab]
    @Binding var activeTabId: String
    let isEditingTextField: Bool
    let onTabSelect: (String) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onResetToTop: () -> Void
    let onResetZoom: () -> Void
    let onResetPan: () -> Void
    let onSearchNext: () -> Void
    let onSearchPrevious: () -> Void
    
    func body(content: Content) -> some View {
        content
            .tabKeyboardShortcuts(tabs: $tabs, activeTabId: $activeTabId, onTabSelect: onTabSelect)
            .onKeyPress(.leftArrow) {
                guard !isEditingTextField else { return .ignored }
                onPrevious()
                return .handled
            }
            .onKeyPress(.rightArrow) {
                guard !isEditingTextField else { return .ignored }
                onNext()
                return .handled
            }
            .onKeyPress(.upArrow, modifiers: .command) {
                onResetToTop()
                return .handled
            }
            .onKeyPress("0", modifiers: .command) {
                onResetZoom()
                return .handled
            }
            .onKeyPress("r", modifiers: .command) {
                guard !isEditingTextField else { return .ignored }
                onResetPan()
                return .handled
            }
            .onKeyPress("g", modifiers: [.command]) {
                guard !isEditingTextField else { return .ignored }
                onSearchNext()
                return .handled
            }
            .onKeyPress("g", modifiers: [.command, .shift]) {
                guard !isEditingTextField else { return .ignored }
                onSearchPrevious()
                return .handled
            }
    }
}

