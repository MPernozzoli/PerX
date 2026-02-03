import SwiftUI
import PDFKit
import AVKit
import Vision
import AppKit

struct MediaViewer: View {
    let initialURL: URL
    let initialPredefinedFiles: [URL]? // Lista predefinita di file (es. foto associate a un dato)
    @EnvironmentObject var windowManager: MediaViewerWindowManager
    @ObservedObject private var fileTagManager = FileTagManager.shared
    @State private var showTagPopover = false
    @State private var showQuickPhotoTagPanel = false
    @State private var isEditingQuickPhotoTagField = false
    @State private var currentPageIndex: Int = 0
    @State private var isEditingPDF = false
    @State private var showCompressionSheet = false
    @State private var isViewActive = true
    
    // Navigazione
    @State private var currentURL: URL
    @State private var predefinedFiles: [URL]?
    @State private var currentFileIndex: Int = 0
    @State private var navigableFiles: [URL] = []
    @State private var navigationScope: NavigationScope = .currentFolder
    @State private var typeFilter: TypeFilter = .all
    @State private var tagFilter: TagFilter = .all
    @State private var showNavigationSettings = false
    @FocusState private var isViewFocused: Bool
    
    private let fileService = FileService.shared
    
    init(url: URL, predefinedFiles: [URL]? = nil) {
        self.initialURL = url
        self.initialPredefinedFiles = predefinedFiles
        _currentURL = State(initialValue: url)
        _predefinedFiles = State(initialValue: predefinedFiles)
    }
    
    enum NavigationScope {
        case currentFolder
        case sinistroDirectory
    }
    
    enum TypeFilter {
        case all
        case pdf
        case media
    }
    
    enum TagFilter {
        case all
        case tagged
        case untagged
    }
    
    private func fileTypeForURL(_ url: URL) -> FileType {
        let pathExtension = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"].contains(pathExtension) {
            return .image
        } else if pathExtension == "pdf" {
            return .pdf
        } else if ["mp4", "mov", "avi", "mkv", "m4v"].contains(pathExtension) {
            return .video
        }
        return .unknown
    }
    
    enum FileType {
        case image, pdf, video, unknown
    }
    
    var currentFile: URL {
        navigableFiles[safe: currentFileIndex] ?? currentURL
    }
    
    private var currentSinistroPath: String? {
        let components = currentFile.pathComponents
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
    
    private var isCurrentFileUntagged: Bool {
        fileTagManager.getTagsForFile(at: currentFile.path).isEmpty
    }
    
    private var shouldShowQuickPhotoTagPanel: Bool {
        fileTypeForURL(currentFile) == .image && (isCurrentFileUntagged || showQuickPhotoTagPanel)
    }
    
    private var windowIdentifier: String {
        let components = initialURL.pathComponents
        for component in components {
            if component.count == 7 && component.allSatisfy({ $0.isNumber }) {
                return "MediaViewer-\(component)"
            }
        }
        return "MediaViewer-Generic"
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Toolbar
                MediaViewerToolbar(
                    url: currentFile,
                    fileType: fileTypeForURL(currentFile),
                    showTagPopover: $showTagPopover,
                    showQuickPhotoTagPanel: $showQuickPhotoTagPanel,
                showCompressionSheet: $showCompressionSheet,
                showNavigationSettings: $showNavigationSettings,
                navigationScope: $navigationScope,
                typeFilter: $typeFilter,
                tagFilter: $tagFilter,
                currentIndex: currentFileIndex + 1,
                totalFiles: navigableFiles.count,
                windowIdentifier: windowIdentifier,
                onClose: { 
                    guard isViewActive else { return }
                    isViewActive = false
                    windowManager.closeMediaViewer(for: initialURL) 
                },
                    onRotate: handleRotate,
                    onCrop: handleCrop,
                    onRemovePage: fileTypeForURL(currentFile) == .pdf ? handleRemovePage : nil,
                    onHighlight: fileTypeForURL(currentFile) == .pdf ? handleHighlight : nil,
                    onOCR: handleOCR,
                    onSignature: handleSignature,
                    onPrevious: navigateToPrevious,
                    onNext: navigateToNext
                )
                
                Divider()
                
                // Content
                Group {
                    switch fileTypeForURL(currentFile) {
                    case .image:
                        ImageViewer(url: currentFile, showTagPopover: $showTagPopover)
                        .overlay {
                            if let overlay = signatureOverlay {
                                SignatureOverlayView(
                                    overlay: Binding(
                                        get: { overlay },
                                        set: { newOverlay in
                                            signatureOverlay = newOverlay
                                            saveSignaturePlacement()
                                        }
                                    ),
                                    onRemove: {
                                        removeSignaturePlacement()
                                    }
                                )
                            }
                        }
                    case .pdf:
                        PDFViewer(
                            url: currentFile,
                            currentPageIndex: $currentPageIndex,
                            showTagPopover: $showTagPopover
                        )
                        .overlay {
                            if let overlay = signatureOverlay,
                               let placement = placementService.getPlacement(for: currentFile.path),
                               placement.pageIndex == currentPageIndex {
                                SignatureOverlayView(
                                    overlay: Binding(
                                        get: { overlay },
                                        set: { newOverlay in
                                            signatureOverlay = newOverlay
                                            saveSignaturePlacement()
                                        }
                                    ),
                                    onRemove: {
                                        removeSignaturePlacement()
                                    }
                                )
                            }
                        }
                    case .video:
                        VideoViewer(url: currentFile)
                    case .unknown:
                        Text("Formato non supportato")
                            .foregroundColor(.secondary)
                    }
                }
                .id(currentFileIndex) // Forza ricreazione view quando cambia file
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    // Frecce di navigazione
                    HStack {
                        if currentFileIndex > 0 {
                            Button {
                                navigateToPrevious()
                            } label: {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 20)
                            .opacity(0.8)
                            .onHover { hovering in
                                // Feedback hover
                            }
                        } else {
                            Spacer()
                                .frame(width: 60)
                        }
                        
                        Spacer()
                        
                        if currentFileIndex < navigableFiles.count - 1 {
                            Button {
                                navigateToNext()
                            } label: {
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 20)
                            .opacity(0.8)
                            .onHover { hovering in
                                // Feedback hover
                            }
                        } else {
                            Spacer()
                                .frame(width: 60)
                        }
                    }
                )
                
                if shouldShowQuickPhotoTagPanel {
                    Divider()
                    ScrollView {
                        PhotoQuickTagPanelView(
                            filePath: currentFile.path,
                            sinistroPath: currentSinistroPath,
                            fileTagManager: fileTagManager,
                            isEditingTextField: $isEditingQuickPhotoTagField
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .frame(maxHeight: 320)
                    .background(Color(NSColor.windowBackgroundColor))
                }
            }
        }
        .onAppear {
            // Se abbiamo una lista predefinita, usala direttamente
            if let predefined = predefinedFiles, !predefined.isEmpty {
                navigableFiles = predefined.sorted { $0.lastPathComponent < $1.lastPathComponent }
                if let index = navigableFiles.firstIndex(of: currentURL) {
                    currentFileIndex = index
                } else if !navigableFiles.isEmpty {
                    currentFileIndex = 0
                    currentURL = navigableFiles[0]
                }
            } else {
                // Inizializza navigableFiles con il file corrente per evitare problemi di rendering
                if navigableFiles.isEmpty {
                    navigableFiles = [currentURL]
                    currentFileIndex = 0
                }
                loadNavigableFiles()
                // Assicurati che currentFileIndex punti al file corrente dopo il caricamento
                if let index = navigableFiles.firstIndex(of: currentURL) {
                    currentFileIndex = index
                }
            }
            // Carica posizione firma salvata
            loadSignaturePlacement()
            // Imposta il focus per abilitare la navigazione da tastiera
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isViewFocused = true
            }
        }
        .onChange(of: navigationScope) { _ in
            // Se abbiamo file predefiniti, non ricaricare
            guard predefinedFiles == nil else { return }
            loadNavigableFiles()
        }
        .onChange(of: typeFilter) { _ in
            // Se abbiamo file predefiniti, non ricaricare
            guard predefinedFiles == nil else { return }
            loadNavigableFiles()
        }
        .onChange(of: tagFilter) { _ in
            // Se abbiamo file predefiniti, non ricaricare
            guard predefinedFiles == nil else { return }
            loadNavigableFiles()
        }
        .onChange(of: currentURL) { _ in
            // Ricarica navigableFiles quando cambia l'URL corrente
            loadNavigableFiles()
        }
        .onChange(of: currentFileIndex) { _ in
            // Apri automaticamente la barra rapida quando si passa a una foto non taggata
            if fileTypeForURL(currentFile) == .image {
                showQuickPhotoTagPanel = isCurrentFileUntagged
            } else {
                showQuickPhotoTagPanel = false
            }
            // Carica posizione firma per il nuovo file
            loadSignaturePlacement()
        }
        .onChange(of: currentPageIndex) { _ in
            // Per PDF, carica la firma della pagina corrente
            if fileTypeForURL(currentFile) == .pdf {
                loadSignaturePlacement()
            }
        }
        .onChange(of: predefinedFiles) { _ in
            // Ricarica navigableFiles quando cambiano i file predefiniti
            loadNavigableFiles()
        }
        .popover(isPresented: $showTagPopover, attachmentAnchor: .point(.top), arrowEdge: .top) {
            if fileTypeForURL(currentFile) == .pdf {
                FileTagPopoverForPDFPage(
                    url: currentFile,
                    pageIndex: currentPageIndex
                )
            } else {
                FileTagPopover(url: currentFile)
            }
        }
        .sheet(isPresented: $showCompressionSheet) {
            CompressionSheet(url: currentFile, fileType: fileTypeForURL(currentFile))
        }
        .sheet(isPresented: $showCropSheet) {
            CropSheet(url: currentFile, fileType: fileTypeForURL(currentFile), currentPageIndex: currentPageIndex)
        }
        .sheet(isPresented: $showHighlightSheet) {
            HighlightSheet(url: currentFile, pageIndex: currentPageIndex)
        }
        .sheet(isPresented: $showOCRSheet) {
            OCRSheet(text: $ocrText)
        }
        .sheet(isPresented: $showSignatureSheet) {
            SignatureSheet(
                url: currentFile,
                fileType: fileTypeForURL(currentFile),
                pageIndex: currentPageIndex
            )
        }
        .popover(isPresented: $showSignaturePopover, attachmentAnchor: .point(.center)) {
            SignatureSelectionPopover(
                onSelect: { signatureType in
                    handleSignatureSelection(signatureType: signatureType)
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MediaViewerReloadFile"))) { _ in
            guard isViewActive else { return }
            // Ricarica il file
            windowManager.updateFile(currentFile, previousURL: initialURL)
        }
        .onDisappear {
            isViewActive = false
        }
        .popover(isPresented: $showNavigationSettings) {
            NavigationSettingsPopover(
                navigationScope: $navigationScope,
                typeFilter: $typeFilter,
                tagFilter: $tagFilter
            )
        }
        .focusable()
        .focused($isViewFocused)
        .onKeyPress(.leftArrow) {
            navigateToPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateToNext()
            return .handled
        }
    }
    
    private func loadNavigableFiles() {
        // Se abbiamo una lista predefinita di file (es. foto associate a un dato), usala direttamente
        if let predefined = predefinedFiles, !predefined.isEmpty {
            navigableFiles = predefined.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            // Trova l'indice del file corrente
            if let index = navigableFiles.firstIndex(of: currentURL) {
                currentFileIndex = index
            } else if !navigableFiles.isEmpty {
                // Se il file corrente non è nella lista, usa il primo
                currentFileIndex = 0
                // Aggiorna l'URL corrente
                if let firstFile = navigableFiles.first {
                    currentURL = firstFile
                    windowManager.updateFile(firstFile, previousURL: initialURL)
                }
            }
            return
        }
        
        // Altrimenti carica dalla cartella (comportamento normale)
        let directoryPath: String
        if navigationScope == .currentFolder {
            directoryPath = currentURL.deletingLastPathComponent().path
        } else {
            // Trova la directory principale del sinistro (cerca una cartella con nome numerico di 7 cifre)
            let pathComponents = currentURL.pathComponents
            var sinistroPath: String?
            
            // Cerca una cartella con nome numerico di 7 cifre (formato tipico riferimento sinistro)
            for (index, component) in pathComponents.enumerated() {
                if component.count == 7 && component.allSatisfy({ $0.isNumber }) {
                    let components = Array(pathComponents.prefix(index + 1))
                    sinistroPath = "/" + components.joined(separator: "/")
                    break
                }
            }
            
            if let sinistroPath = sinistroPath {
                directoryPath = sinistroPath
            } else {
                // Fallback: usa la directory corrente
                directoryPath = currentURL.deletingLastPathComponent().path
            }
        }
        
        // Ottieni tutti i file ricorsivamente se è tutto il sinistro
        var allFiles: [URL] = []
        if navigationScope == .sinistroDirectory {
            allFiles = getAllFilesRecursively(in: directoryPath)
        } else {
            let allItems = fileService.listContents(inDirectory: directoryPath)
            allFiles = allItems.filter { !$0.isDirectory }.map { $0.url }
        }
        
        var files = allFiles
        
        // Filtro per tipo
        switch typeFilter {
        case .pdf:
            files = files.filter { $0.pathExtension.lowercased() == "pdf" }
        case .media:
            let mediaExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp", "mp4", "mov", "avi", "mkv", "m4v"]
            files = files.filter { mediaExtensions.contains($0.pathExtension.lowercased()) }
        case .all:
            break
        }
        
        // Filtro per tag
        switch tagFilter {
        case .tagged:
            files = files.filter { !fileTagManager.getTagsForFile(at: $0.path).isEmpty }
        case .untagged:
            files = files.filter { fileTagManager.getTagsForFile(at: $0.path).isEmpty }
        case .all:
            break
        }
        
        navigableFiles = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        // Trova l'indice del file corrente
        if let index = navigableFiles.firstIndex(of: currentURL) {
            currentFileIndex = index
        } else if !navigableFiles.isEmpty {
            // Se il file corrente non è nella lista filtrata, vai al primo file disponibile
            currentFileIndex = 0
            currentURL = navigableFiles[0]
            windowManager.updateFile(currentURL, previousURL: initialURL)
        }
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
    
    private func navigateToPrevious() {
        guard isViewActive, currentFileIndex > 0 else { return }
        currentFileIndex -= 1
        currentPageIndex = 0 // Reset pagina quando si cambia file
        currentURL = currentFile
        windowManager.updateFile(currentFile, previousURL: initialURL)
    }
    
    private func navigateToNext() {
        guard isViewActive, currentFileIndex < navigableFiles.count - 1 else { return }
        currentFileIndex += 1
        currentPageIndex = 0 // Reset pagina quando si cambia file
        currentURL = currentFile
        windowManager.updateFile(currentFile, previousURL: initialURL)
    }
    
    @State private var showCropSheet = false
    @State private var showHighlightSheet = false
    @State private var showOCRSheet = false
    @State private var showSignatureSheet = false
    @State private var showSignaturePopover = false
    @State private var ocrText: String = ""
    @State private var signatureOverlay: SignatureOverlayData?
    
    private let editorService = MediaEditorService.shared
    @StateObject private var signatureService = SignatureService.shared
    @StateObject private var placementService = SignaturePlacementService.shared
    
    private func handleRotate() {
        let fileType = fileTypeForURL(currentFile)
        
        if fileType == .image {
            let success = editorService.rotateImage(at: currentFile, degrees: 90)
            if success {
                // Ricarica l'immagine
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
    
    private func handleCrop() {
        showCropSheet = true
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
                // Se la pagina rimossa era l'ultima, vai alla precedente
                if currentPageIndex > 0 {
                    currentPageIndex -= 1
                }
                NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
            }
        }
    }
    
    private func handleHighlight() {
        showHighlightSheet = true
    }
    
    private func handleOCR() {
        showOCRSheet = true
        ocrText = ""
        
        let fileType = fileTypeForURL(currentFile)
        
        if fileType == .image {
            editorService.performOCR(on: currentFile) { text in
                DispatchQueue.main.async {
                    self.ocrText = text ?? "Nessun testo riconosciuto"
                }
            }
        } else if fileType == .pdf {
            editorService.performOCROnPDFPage(at: currentFile, pageIndex: currentPageIndex) { text in
                DispatchQueue.main.async {
                    self.ocrText = text ?? "Nessun testo riconosciuto"
                }
            }
        }
    }
    
    private func handleSignature() {
        let availableSignatures = signatureService.getAvailableSignatures()
        
        if availableSignatures.isEmpty {
            // Nessuna firma disponibile
            return
        } else if availableSignatures.count == 1 {
            // Una sola firma: seleziona direttamente
            let signatureType = signatureService.individualSignature != nil ? "individual" : "studio"
            handleSignatureSelection(signatureType: signatureType)
        } else {
            // Più firme: mostra popover per scegliere
            showSignaturePopover = true
        }
    }
    
    private func handleSignatureSelection(signatureType: String) {
        showSignaturePopover = false
        
        // Per PDF, usa la pagina corrente; per immagini, usa nil
        let pageIndex = fileTypeForURL(currentFile) == .pdf ? currentPageIndex : nil
        
        // Carica posizione salvata per questa pagina/file o usa default
        let savedPlacement = placementService.getPlacement(for: currentFile.path)
        let useSaved = savedPlacement != nil && savedPlacement?.pageIndex == pageIndex
        
        let defaultPosition = useSaved ? savedPlacement!.position : CGPoint(x: 50, y: 50)
        let defaultSize = useSaved ? savedPlacement!.size : CGSize(width: 150, height: 60)
        
        // Crea overlay
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
        
        // Per PDF, aggiungi immediatamente l'annotazione
        if fileTypeForURL(currentFile) == .pdf {
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
                // Ricarica il PDF per mostrare l'annotazione
                NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
            }
        }
    }
    
    private func saveSignaturePlacement() {
        guard let overlay = signatureOverlay else { return }
        
        // Converti l'immagine in PNG data per la stampa
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
            pageIndex: fileTypeForURL(currentFile) == .pdf ? currentPageIndex : nil,
            signatureImageData: signatureImageData
        )
        
        placementService.setPlacement(placement)
        
        // Per PDF, aggiorna l'annotazione se la posizione è cambiata
        if fileTypeForURL(currentFile) == .pdf {
            // Rimuovi annotazioni esistenti per questa pagina
            Task { @MainActor in
                if let document = PDFDocument(url: currentFile),
                   let page = document.page(at: currentPageIndex) {
                    let existingAnnotations = page.annotations.filter { $0.userName == "PerX_Signature" }
                    for annotation in existingAnnotations {
                        page.removeAnnotation(annotation)
                    }
                    
                    // Aggiungi nuova annotazione con la posizione aggiornata
                    _ = editorService.addSignatureToPDF(
                        at: currentFile,
                        pageIndex: currentPageIndex,
                        signature: overlay.image,
                        position: overlay.position,
                        size: overlay.size,
                        createVersion: false,
                        asAnnotation: true
                    )
                    
                    NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
                }
            }
        }
    }
    
    private func removeSignaturePlacement() {
        signatureOverlay = nil
        placementService.removePlacement(for: currentFile.path)
    }
    
    private func loadSignaturePlacement() {
        let fileType = fileTypeForURL(currentFile)
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
}

// MARK: - Toolbar

struct MediaViewerToolbar: View {
    let url: URL
    let fileType: MediaViewer.FileType
    @Binding var showTagPopover: Bool
    @Binding var showQuickPhotoTagPanel: Bool
    @Binding var showCompressionSheet: Bool
    @Binding var showNavigationSettings: Bool
    @Binding var navigationScope: MediaViewer.NavigationScope
    @Binding var typeFilter: MediaViewer.TypeFilter
    @Binding var tagFilter: MediaViewer.TagFilter
    let currentIndex: Int
    let totalFiles: Int
    let windowIdentifier: String
    let onClose: () -> Void
    @EnvironmentObject var windowManager: MediaViewerWindowManager
    let onRotate: () -> Void
    let onCrop: () -> Void
    let onRemovePage: (() -> Void)?
    let onHighlight: (() -> Void)?
    let onOCR: () -> Void
    let onSignature: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    @ObservedObject private var fileTagManager = FileTagManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Navigazione
            HStack(spacing: 4) {
                Button {
                    onPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .disabled(currentIndex <= 1)
                .help("File Precedente (←)")
                
                Text("\(currentIndex) / \(totalFiles)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 60)
                
                Button {
                    onNext()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(currentIndex >= totalFiles)
                .help("File Successivo (→)")
            }
            
            Divider()
                .frame(height: 20)
            
            // Impostazioni navigazione
            Button {
                showNavigationSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .help("Impostazioni Navigazione (⌘N)")
            .keyboardShortcut("n", modifiers: .command)
            
            Divider()
                .frame(height: 20)
            
            // Tag button
            Button {
                showTagPopover = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                    Text("Tag")
                }
            }
            .buttonStyle(.bordered)
            .help("Gestisci Tag")
            
            if fileType == .image {
                Button {
                    showQuickPhotoTagPanel.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                        Text("Classifica")
                    }
                }
                .buttonStyle(.bordered)
                .help("Classifica foto (barra persistente)")
            }
            
            Divider()
                .frame(height: 20)
            
            // Editing buttons
            if fileType == .image || fileType == .pdf {
                Button {
                    onRotate()
                } label: {
                    Image(systemName: "rotate.right")
                }
                .buttonStyle(.plain)
                .help("Ruota")
                
                Button {
                    onCrop()
                } label: {
                    Image(systemName: "crop")
                }
                .buttonStyle(.plain)
                .help("Ritaglia")
            }
            
            if fileType == .pdf {
                if let onRemovePage = onRemovePage {
                    Button {
                        onRemovePage()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Rimuovi Pagina")
                }
                
                if let onHighlight = onHighlight {
                    Button {
                        onHighlight()
                    } label: {
                        Image(systemName: "highlighter")
                    }
                    .buttonStyle(.plain)
                    .help("Evidenzia")
                }
            }
            
            Divider()
                .frame(height: 20)
            
            Button {
                onOCR()
            } label: {
                Image(systemName: "text.viewfinder")
            }
            .buttonStyle(.plain)
            .help("OCR - Copia Testo")
            
            Button {
                onSignature()
            } label: {
                Image(systemName: "signature")
            }
            .buttonStyle(.plain)
            .help("Firma/Timbro")
            
            Spacer()
            
            Button {
                showCompressionSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                    Text("Comprimi")
                }
            }
            .buttonStyle(.bordered)
            .help("Riduci Peso File")
            
            // Always on top toggle
            Button {
                let newValue = !windowManager.isAlwaysOnTop
                windowManager.updateAlwaysOnTop(newValue)
                WindowManager.shared.updateAlwaysOnTop(identifier: windowIdentifier, value: newValue)
            } label: {
                Image(systemName: windowManager.isAlwaysOnTop ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .help(windowManager.isAlwaysOnTop ? "Disattiva Sempre in Primo Piano" : "Attiva Sempre in Primo Piano")
            
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Chiudi")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Image Viewer

struct ImageViewer: View {
    let url: URL
    @Binding var showTagPopover: Bool
    @State private var image: NSImage?
    @State private var scale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0 // Scala per adattare alla finestra
    @State private var offset: CGSize = .zero
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var loadTask: Task<Void, Never>?
    
    private let fileService = FileService.shared
    
    var body: some View {
        GeometryReader { geometry in
            if let image = image {
                let containerSize = geometry.size
                // Calcola la scala per adattare l'immagine alla finestra
                let imageSize = image.size
                let scaleToFit = min(
                    containerSize.width / imageSize.width,
                    containerSize.height / imageSize.height,
                    1.0 // Non ingrandire oltre la dimensione originale
                )
                let displayWidth = imageSize.width * scaleToFit * scale
                let displayHeight = imageSize.height * scaleToFit * scale
                
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: displayWidth, height: displayHeight)
                        .frame(minWidth: containerSize.width, minHeight: containerSize.height)
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            // Limita lo zoom tra 0.5x e 5x
                            scale = min(max(value, 0.5), 5.0)
                        }
                )
                .onTapGesture(count: 2) {
                    // Doppio click per reset zoom
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scale = 1.0
                    }
                }
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Caricamento...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Impossibile caricare l'immagine")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .onAppear {
            scale = 1.0 // Reset zoom quando appare
            loadImage()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .onChange(of: url) { _ in
            scale = 1.0 // Reset zoom quando cambia file
            loadImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MediaViewerReloadFile"))) { _ in
            loadImage()
        }
    }
    
    private func loadImage() {
        // Annulla il task precedente se esiste
        loadTask?.cancel()
        
        // Reset stato
        image = nil
        isLoading = true
        loadError = nil
        
        let fileURL = url
        let service = fileService
        
        // Carica l'immagine in modo asincrono
        loadTask = Task { @MainActor in
            // Usa un background thread per il caricamento
            let loadedImage = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                // Usa SEMPRE security-scoped access per evitare errori sandbox
                let filePath = fileURL.deletingLastPathComponent().path
                let result: NSImage? = service.performWithSecurityScopedAccess(to: filePath) {
                    // Prova prima con NSImage(contentsOf:) che è più efficiente
                    if let img = NSImage(contentsOf: fileURL) {
                        return img
                    }
                    // Fallback: carica come Data e poi crea NSImage
                    if let data = try? Data(contentsOf: fileURL), let img = NSImage(data: data) {
                        return img
                    }
                    return nil
                } ?? nil
                
                return result
            }.value
            
            // Verifica se il task è stato cancellato
            guard !Task.isCancelled else {
                return
            }
            
            if let loadedImage = loadedImage {
                self.image = loadedImage
                self.isLoading = false
                self.loadError = nil
            } else {
                self.image = nil
                self.isLoading = false
                self.loadError = "Il file potrebbe essere corrotto o in un formato non supportato"
            }
        }
    }
}

// MARK: - PDF Viewer

struct PDFViewer: NSViewRepresentable {
    let url: URL
    @Binding var currentPageIndex: Int
    @Binding var showTagPopover: Bool
    @ObservedObject private var fileTagManager = FileTagManager.shared
    
    private let fileService = FileService.shared
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor.windowBackgroundColor
        
        // Carica il documento con security-scoped access
        loadDocument(into: pdfView, context: context)
        
        // Ascolta le notifiche di ricaricamento
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.reloadDocument),
            name: NSNotification.Name("MediaViewerReloadFile"),
            object: nil
        )
        
        // Ascolta le notifiche di cambio pagina per aggiornare currentPageIndex
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        return pdfView
    }
    
    private func loadDocument(into pdfView: PDFView, context: Context) {
        // Prova caricamento diretto
        if let document = PDFDocument(url: url) {
            pdfView.document = document
            context.coordinator.pdfView = pdfView
            context.coordinator.document = document
            context.coordinator.url = url
            return
        }
        
        // Prova con Data
        if let data = try? Data(contentsOf: url), let document = PDFDocument(data: data) {
            pdfView.document = document
            context.coordinator.pdfView = pdfView
            context.coordinator.document = document
            context.coordinator.url = url
            return
        }
        
        // Prova con security-scoped access
        let filePath = url.deletingLastPathComponent().path
        fileService.performWithSecurityScopedAccess(to: filePath) {
            if let document = PDFDocument(url: url) {
                pdfView.document = document
                context.coordinator.pdfView = pdfView
                context.coordinator.document = document
                context.coordinator.url = url
            } else if let data = try? Data(contentsOf: url), let document = PDFDocument(data: data) {
                pdfView.document = document
                context.coordinator.pdfView = pdfView
                context.coordinator.document = document
                context.coordinator.url = url
            } else {
                print("[PDFViewer] ❌ Impossibile caricare PDF: \(url.lastPathComponent)")
            }
        }
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        // Aggiorna l'URL se è cambiato
        if context.coordinator.url != url {
            context.coordinator.url = url
            loadDocument(into: nsView, context: context)
        }
        
        if let document = nsView.document,
           currentPageIndex < document.pageCount,
           let page = document.page(at: currentPageIndex) {
            nsView.go(to: page)
        }
    }
    
    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        coordinator.invalidate()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(currentPageIndex: $currentPageIndex, showTagPopover: $showTagPopover, url: url, fileService: fileService)
    }
    
    class Coordinator: NSObject {
        weak var pdfView: PDFView?
        var document: PDFDocument?
        var url: URL
        let fileService: FileService
        @Binding var currentPageIndex: Int
        @Binding var showTagPopover: Bool
        private var isInvalidated = false
        
        init(currentPageIndex: Binding<Int>, showTagPopover: Binding<Bool>, url: URL, fileService: FileService) {
            _currentPageIndex = currentPageIndex
            _showTagPopover = showTagPopover
            self.url = url
            self.fileService = fileService
        }
        
        func invalidate() {
            isInvalidated = true
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func reloadDocument() {
            guard !isInvalidated, let pdfView = pdfView else { return }
            
            // Prova caricamento diretto
            if let newDocument = PDFDocument(url: url) {
                updatePDFView(pdfView, with: newDocument)
                return
            }
            
            // Prova con Data
            if let data = try? Data(contentsOf: url), let newDocument = PDFDocument(data: data) {
                updatePDFView(pdfView, with: newDocument)
                return
            }
            
            // Prova con security-scoped access
            let filePath = url.deletingLastPathComponent().path
            fileService.performWithSecurityScopedAccess(to: filePath) {
                if let newDocument = PDFDocument(url: url) {
                    updatePDFView(pdfView, with: newDocument)
                } else if let data = try? Data(contentsOf: url), let newDocument = PDFDocument(data: data) {
                    updatePDFView(pdfView, with: newDocument)
                }
            }
        }
        
        private func updatePDFView(_ pdfView: PDFView, with newDocument: PDFDocument) {
            pdfView.document = newDocument
            document = newDocument
            if currentPageIndex < newDocument.pageCount, let page = newDocument.page(at: currentPageIndex) {
                pdfView.go(to: page)
            } else if let firstPage = newDocument.page(at: 0) {
                pdfView.go(to: firstPage)
            }
        }
        
        @objc func pageChanged(_ notification: Notification) {
            guard !isInvalidated, let pdfView = pdfView else { return }
            
            // Ottieni la pagina corrente
            if let currentPage = pdfView.currentPage,
               let document = pdfView.document {
                let pageIndex = document.index(for: currentPage)
                // Aggiorna solo se diverso per evitare loop
                if currentPageIndex != pageIndex && pageIndex >= 0 && pageIndex < document.pageCount {
                    DispatchQueue.main.async {
                        self.currentPageIndex = pageIndex
                    }
                }
            }
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// MARK: - Video Viewer

struct VideoViewer: NSViewRepresentable {
    let url: URL
    
    private let fileService = FileService.shared
    
    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true
        
        // Crea l'AVPlayerView
        let playerView = AVPlayerView()
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true
        containerView.addSubview(playerView)
        
        // Constraints per riempire il container
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        context.coordinator.playerView = playerView
        context.coordinator.containerView = containerView
        
        // Carica il video
        loadVideo(into: playerView, context: context)
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            if let playerView = context.coordinator.playerView {
                loadVideo(into: playerView, context: context)
            }
        }
    }
    
    private func loadVideo(into playerView: AVPlayerView, context: Context) {
        // Ferma il player precedente
        context.coordinator.player?.pause()
        context.coordinator.stopSecurityAccess()
        
        // Ottieni security-scoped access e mantienilo attivo
        let directoryPath = url.deletingLastPathComponent().path
        context.coordinator.startSecurityAccess(for: directoryPath, fileService: fileService)
        
        // Crea il player con l'URL del file
        let player = AVPlayer(url: url)
        playerView.player = player
        context.coordinator.player = player
        context.coordinator.url = url
        
        // Avvia la riproduzione
        player.play()
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.cleanup()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }
    
    class Coordinator {
        var playerView: AVPlayerView?
        var containerView: NSView?
        var player: AVPlayer?
        var url: URL
        private var securityScopedURL: URL?
        
        init(url: URL) {
            self.url = url
        }
        
        func startSecurityAccess(for path: String, fileService: FileService) {
            // Per path interni (Application Support), non serve security access.
            // Per path esterni legacy, cerca nei bookmark salvati.
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
                            if !isStale && url.startAccessingSecurityScopedResource() {
                                securityScopedURL = url
                                return
                            }
                        } catch {
                            continue
                        }
                    }
                }
            }
            
            // Fallback: cerca nel vecchio bookmark di FileService
            if let bookmarkData = UserDefaults.standard.data(forKey: "MainDirectoryBookmark") {
                do {
                    var isStale = false
                    let url = try URL(resolvingBookmarkData: bookmarkData,
                                    options: .withSecurityScope,
                                    relativeTo: nil,
                                    bookmarkDataIsStale: &isStale)
                    if !isStale {
                        let bookmarkPath = url.path
                        if path.hasPrefix(bookmarkPath) && url.startAccessingSecurityScopedResource() {
                            securityScopedURL = url
                        }
                    }
                } catch {
                    // Ignora
                }
            }
        }
        
        func stopSecurityAccess() {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
        }
        
        func cleanup() {
            player?.pause()
            player = nil
            playerView?.player = nil
            stopSecurityAccess()
        }
        
        deinit {
            cleanup()
        }
    }
}

// MARK: - PDF Page Tag Popover

struct FileTagPopoverForPDFPage: View {
    let url: URL
    let pageIndex: Int
    @ObservedObject private var fileTagManager = FileTagManager.shared
    @State private var expandedCategories: Set<FileTagManager.FileTag.TagCategory?> = [.foto]
    @State private var editingTagId: String?
    @State private var editingText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Tag - Pagina \(pageIndex + 1)")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // Lista tag organizzati per categoria
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // Tag senza categoria
                    if let noCategoryTags = FileTagManager.FileTag.tagsByCategory()[nil], !noCategoryTags.isEmpty {
                        PDFPageTagSection(
                            tags: noCategoryTags,
                            filePath: url.path,
                            pageIndex: pageIndex,
                            fileTagManager: fileTagManager,
                            editingTagId: $editingTagId,
                            editingText: $editingText,
                            isTextFieldFocused: _isTextFieldFocused
                        )
                    }
                    
                    // Categoria Foto
                    if let fotoTags = FileTagManager.FileTag.tagsByCategory()[.foto], !fotoTags.isEmpty {
                        PDFPageCategorySection(
                            category: .foto,
                            tags: fotoTags,
                            filePath: url.path,
                            pageIndex: pageIndex,
                            fileTagManager: fileTagManager,
                            expandedCategories: $expandedCategories,
                            editingTagId: $editingTagId,
                            editingText: $editingText,
                            isTextFieldFocused: _isTextFieldFocused
                        )
                    }
                }
            }
            .frame(maxHeight: 400)
        }
        .padding()
        .frame(width: 320)
    }
}

struct PDFPageTagSection: View {
    let tags: [FileTagManager.FileTag]
    let filePath: String
    let pageIndex: Int
    @ObservedObject var fileTagManager: FileTagManager
    @Binding var editingTagId: String?
    @Binding var editingText: String
    @FocusState var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(tags) { tag in
                PDFPageTagRow(
                    tag: tag,
                    filePath: filePath,
                    pageIndex: pageIndex,
                    fileTagManager: fileTagManager,
                    editingTagId: $editingTagId,
                    editingText: $editingText,
                    isTextFieldFocused: _isTextFieldFocused
                )
            }
        }
    }
}

struct PDFPageCategorySection: View {
    let category: FileTagManager.FileTag.TagCategory
    let tags: [FileTagManager.FileTag]
    let filePath: String
    let pageIndex: Int
    @ObservedObject var fileTagManager: FileTagManager
    @Binding var expandedCategories: Set<FileTagManager.FileTag.TagCategory?>
    @Binding var editingTagId: String?
    @Binding var editingText: String
    @FocusState var isTextFieldFocused: Bool
    
    var isExpanded: Bool {
        expandedCategories.contains(category)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation {
                    if isExpanded {
                        expandedCategories.remove(category)
                    } else {
                        expandedCategories.insert(category)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    
                    Text(category.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                PDFPageTagSection(
                    tags: tags,
                    filePath: filePath,
                    pageIndex: pageIndex,
                    fileTagManager: fileTagManager,
                    editingTagId: $editingTagId,
                    editingText: $editingText,
                    isTextFieldFocused: _isTextFieldFocused
                )
                .padding(.leading, 20)
            }
        }
    }
}

struct PDFPageTagRow: View {
    let tag: FileTagManager.FileTag
    let filePath: String
    let pageIndex: Int
    @ObservedObject var fileTagManager: FileTagManager
    @Binding var editingTagId: String?
    @Binding var editingText: String
    @FocusState var isTextFieldFocused: Bool
    
    var isSelected: Bool {
        fileTagManager.getTagsForPDFPage(at: filePath, pageIndex: pageIndex).contains(tag)
    }
    
    var currentAdditionalText: String {
        fileTagManager.getAdditionalTextForPDFPage(forFile: filePath, pageIndex: pageIndex, tagId: tag.id) ?? ""
    }
    
    var isDaAllegare: Bool {
        fileTagManager.getDaAllegareForPDFPage(forFile: filePath, pageIndex: pageIndex, tagId: tag.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    toggleTag()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? tag.tagColor : .secondary)
                            .font(.system(size: 14))
                        
                        Text(tag.name)
                            .font(.system(size: 13))
                            .foregroundColor(isSelected ? tag.tagColor : .primary)
                    }
                }
                .buttonStyle(.plain)
                
                if isSelected {
                    Toggle(isOn: Binding(
                        get: { isDaAllegare },
                        set: { fileTagManager.setDaAllegareForPDFPage($0, forFile: filePath, pageIndex: pageIndex, tagId: tag.id) }
                    )) {
                        HStack(spacing: 2) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                            Text("Chiusura")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(isDaAllegare ? tag.tagColor : .secondary)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                }
                
                Spacer()
            }
            
            if isSelected && tag.requiresAdditionalText {
                if editingTagId == tag.id {
                    HStack(spacing: 6) {
                        TextField(placeholderForTag(tag), text: $editingText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(6)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                            .focused($isTextFieldFocused)
                            .onSubmit {
                                saveAdditionalText()
                            }
                        
                        Button {
                            saveAdditionalText()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            cancelEditing()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 20)
                } else {
                    HStack(spacing: 6) {
                        if !currentAdditionalText.isEmpty {
                            Text(currentAdditionalText)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(tag.tagColor.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        Button {
                            startEditing()
                        } label: {
                            Image(systemName: currentAdditionalText.isEmpty ? "plus.circle" : "pencil.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 20)
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    private func toggleTag() {
        if isSelected {
            fileTagManager.removeTag(tag, fromPDFPage: filePath, pageIndex: pageIndex)
        } else {
            fileTagManager.addTag(tag, toPDFPage: filePath, pageIndex: pageIndex)
            if tag.requiresAdditionalText {
                startEditing()
            }
        }
    }
    
    private func startEditing() {
        editingTagId = tag.id
        editingText = currentAdditionalText
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextFieldFocused = true
        }
    }
    
    private func saveAdditionalText() {
        fileTagManager.setAdditionalTextForPDFPage(editingText, forFile: filePath, pageIndex: pageIndex, tagId: tag.id)
        editingTagId = nil
    }
    
    private func cancelEditing() {
        editingTagId = nil
        editingText = ""
    }
    
    private func placeholderForTag(_ tag: FileTagManager.FileTag) -> String {
        switch tag.id {
        case "foto_bene":
            return "Es: caldaia, televisore..."
        case "foto_componente":
            return "Es: scheda, circolatore, encoder..."
        case "foto_ripristino":
            return "Es: caldaia, televisore..."
        default:
            return "Inserisci testo..."
        }
    }
}

// MARK: - Navigation Settings Popover

struct NavigationSettingsPopover: View {
    @Binding var navigationScope: MediaViewer.NavigationScope
    @Binding var typeFilter: MediaViewer.TypeFilter
    @Binding var tagFilter: MediaViewer.TagFilter
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Impostazioni Navigazione")
                .font(.headline)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Scope Navigazione")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Picker("Scope", selection: $navigationScope) {
                    Text("Cartella Corrente").tag(MediaViewer.NavigationScope.currentFolder)
                    Text("Tutto il Sinistro").tag(MediaViewer.NavigationScope.sinistroDirectory)
                }
                .pickerStyle(.segmented)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Filtro Tipo")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Picker("Tipo", selection: $typeFilter) {
                    Text("Tutto").tag(MediaViewer.TypeFilter.all)
                    Text("PDF").tag(MediaViewer.TypeFilter.pdf)
                    Text("Media").tag(MediaViewer.TypeFilter.media)
                }
                .pickerStyle(.segmented)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Filtro Tag")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Picker("Tag", selection: $tagFilter) {
                    Text("Tutti").tag(MediaViewer.TagFilter.all)
                    Text("Solo Taggati").tag(MediaViewer.TagFilter.tagged)
                    Text("Solo Non Taggati").tag(MediaViewer.TagFilter.untagged)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Compression Sheet

struct CompressionSheet: View {
    let url: URL
    let fileType: MediaViewer.FileType
    @Environment(\.dismiss) private var dismiss
    @State private var compressionQuality: Double = 0.7
    @State private var isCompressing = false
    @State private var compressionMessage: String = ""
    
    private let editorService = MediaEditorService.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Riduci Peso File")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Qualità: \(Int(compressionQuality * 100))%")
                    .font(.subheadline)
                
                Slider(value: $compressionQuality, in: 0.1...1.0)
                
                Text("Qualità più bassa = file più piccolo")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !compressionMessage.isEmpty {
                    Text(compressionMessage)
                        .font(.caption)
                        .foregroundColor(compressionMessage.contains("successo") ? .green : .red)
                }
            }
            
            if isCompressing {
                ProgressView()
                    .padding()
            }
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                .disabled(isCompressing)
                
                Button("Comprimi") {
                    compressFile()
                }
                .disabled(isCompressing)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    private func compressFile() {
        isCompressing = true
        compressionMessage = ""
        
        let quality = CGFloat(compressionQuality)
        
        if fileType == .image {
            editorService.compressImage(at: url, quality: quality) { success in
                DispatchQueue.main.async {
                    isCompressing = false
                    if success {
                        compressionMessage = "Compressione completata con successo"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                            NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
                        }
                    } else {
                        compressionMessage = "Errore durante la compressione"
                    }
                }
            }
        } else if fileType == .pdf {
            editorService.compressPDF(at: url, quality: quality) { success in
                DispatchQueue.main.async {
                    isCompressing = false
                    if success {
                        compressionMessage = "Compressione completata con successo"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                            NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
                        }
                    } else {
                        compressionMessage = "Errore durante la compressione"
                    }
                }
            }
        } else {
            isCompressing = false
            compressionMessage = "Formato non supportato per la compressione"
        }
    }
}

// MARK: - Crop Sheet

struct CropSheet: View {
    let url: URL
    let fileType: MediaViewer.FileType
    let currentPageIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var cropRect: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    @State private var isCropping = false
    
    private let editorService = MediaEditorService.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Ritaglia \(fileType == .pdf ? "Pagina PDF" : "Immagine")")
                .font(.headline)
            
            Text("Seleziona l'area da ritagliare")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // TODO: Implementare interfaccia di selezione area
            Text("Interfaccia di ritaglio da implementare")
                .foregroundColor(.secondary)
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                .disabled(isCropping)
                
                Button("Ritaglia") {
                    performCrop()
                }
                .disabled(isCropping)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
    
    private func performCrop() {
        isCropping = true
        
        if fileType == .image {
            let success = editorService.cropImage(at: url, rect: cropRect)
            if success {
                NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
                dismiss()
            }
        } else if fileType == .pdf {
            let success = editorService.cropPDFPage(at: url, pageIndex: currentPageIndex, rect: cropRect)
            if success {
                NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
                dismiss()
            }
        }
        
        isCropping = false
    }
}

// MARK: - Highlight Sheet

struct HighlightSheet: View {
    let url: URL
    let pageIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var highlightRect: CGRect = CGRect(x: 0, y: 0, width: 100, height: 20)
    @State private var highlightColor: NSColor = .yellow
    @State private var isHighlighting = false
    
    private let editorService = MediaEditorService.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Evidenzia Testo")
                .font(.headline)
            
            Text("Seleziona l'area da evidenziare nella pagina \(pageIndex + 1)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // TODO: Implementare interfaccia di selezione area
            Text("Interfaccia di evidenziazione da implementare")
                .foregroundColor(.secondary)
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                .disabled(isHighlighting)
                
                Button("Evidenzia") {
                    performHighlight()
                }
                .disabled(isHighlighting)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
    
    private func performHighlight() {
        isHighlighting = true
        let success = editorService.addHighlightToPDFPage(at: url, pageIndex: pageIndex, rect: highlightRect, color: highlightColor)
        if success {
            NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
            dismiss()
        }
        isHighlighting = false
    }
}

// MARK: - OCR Sheet

struct OCRSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = true
    
    var body: some View {
        VStack(spacing: 20) {
            Text("OCR - Testo Riconosciuto")
                .font(.headline)
            
            if isProcessing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Elaborazione in corso...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                ScrollView {
                    Text(text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(minHeight: 200)
            }
            
            HStack {
                Button("Copia") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .disabled(isProcessing || text.isEmpty)
                
                Spacer()
                
                Button("Chiudi") {
                    dismiss()
                }
            }
        }
        .padding()
        .frame(width: 600, height: 400)
        .onAppear {
            // Simula il processing per mostrare il progresso
            if text.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isProcessing = false
                }
            } else {
                isProcessing = false
            }
        }
    }
}

