import SwiftUI
import QuickLook

// MARK: - Array Safe Subscript Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Cartella View

struct CartellaView: View {
    @ObservedObject var sinistro: Sinistro
    @StateObject private var fileTagManager = FileTagManager.shared
    @StateObject private var claimSync = ClaimSyncService.shared
    @StateObject private var directoryMonitor = DirectoryMonitor()
    @StateObject private var autoTaggingService = AutoTaggingService.shared
    @State private var selectedColumn = 0
    @State private var selectedItems: [String: URL] = [:]
    @State private var columns: [String] = []
    @State private var showingPreview = false
    @State private var showingTagSheet = false
    @State private var fileToTag: URL?
    @State private var previewURL: URL?
    @State private var quickLookURL: URL?
    @FocusState private var columnFocus: Int?
    @State private var columnWidths: [CGFloat] = []
    @State private var totalWidth: CGFloat = 0
    @State private var isDraggingDivider = false
    @State private var searchText = ""
    @State private var showingNewFolderSheet = false
    @State private var isRenaming = false
    @State private var itemToRename: FileService.FileItem?
    @State private var newName = ""
    @State private var isSearchActive = false
    @FocusState private var isSearchFieldFocused: Bool
    @EnvironmentObject private var appState: AppState
    @State private var refreshTrigger = UUID()
    @State private var showPreviewPanel = true
    @State private var isEditingTextField = false
    // Generazione file chiusura
    @State private var showingAttoSottotipoDialog = false
    @State private var isGeneratingClosure = false
    @State private var attoFileToUpdate: (filePath: String, tagId: String)?
    
    // Autotagging
    @State private var showingAutoTaggingProgress = false
    
    // Conferma eliminazione cartella
    @State private var showingDeleteFolderConfirmation = false
    @State private var isDeletingFolder = false
    
    // Esportazione cartella
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showingExportSuccess = false
    
    // Memorizza il path del sinistro per evitare chiamate filesystem in body
    @State private var rootPath: String? = nil
    
    // Memorizza lo status sync per evitare ricalcoli multipli per frame
    @State private var cachedSyncStatus: ClaimSyncStatus = .notDownloaded
    @State private var cachedIsSuspended: Bool = false
    
    // Gestione Drag and Drop condivisa tra le colonne
    @State private var draggedItem: FileService.FileItem? = nil
    @State private var draggedItems: [FileService.FileItem] = []
    
    private let fileService = FileService.shared
    private let closureService = ClosureFilesService.shared
    
    // File selezionato corrente per anteprima
    private var currentSelectedFile: URL? {
        guard let currentPath = columns[safe: selectedColumn],
              let url = selectedItems[currentPath],
              !fileService.isDirectory(url) else { return nil }
        return url
    }
    
    // Path del sinistro per UnifiedTagView
    private var sinistroPath: String? {
        rootPath
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if let rootPath = rootPath, !isDeletingFolder {
                    // Toolbar moderna
                    toolbarView(rootPath: rootPath)
                    
                    // Divider semplice (rimossa progress bar superiore)
                    Divider()
                    
                    // Vista a colonne con pannello anteprima
                    columnsView
                    
                } else {
                    emptyFolderView
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.easeInOut(duration: 0.4), value: isDeletingFolder)
            
            // Overlay animazione eliminazione
            if isDeletingFolder {
                deletingFolderOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isDeletingFolder)
        .onAppear {
            updateRootPath()
            setupView()
            
            // Sincronizza quando l'utente apre la cartella per assicurarsi di vedere tutto aggiornato
            Task {
                await claimSync.manualDownload(for: sinistro)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .claimFolderChanged)) { note in
            guard let rif = sinistro.riferimento else { return }
            guard (note.userInfo?["riferimento"] as? String) == rif else { return }
            
            // Se la cartella è appena comparsa (download iniziale), inizializza colonne/monitor.
            if columns.isEmpty {
                setupView()
            }
            
            // Aggiorna la UI (liste file/colonne) senza intervento utente.
            triggerRefresh()
        }
        .onChange(of: columns) { newColumns in
            directoryMonitor.startMonitoring(paths: newColumns)
            
            // Pulisci selectedItems per colonne che non esistono più
            let validPaths = Set(newColumns)
            selectedItems = selectedItems.filter { validPaths.contains($0.key) }
            
            // Assicura che selectedColumn sia valido
            if selectedColumn >= newColumns.count {
                selectedColumn = max(0, newColumns.count - 1)
            }
        }
        .onChange(of: claimSync.statuses) { _ in
            // Aggiorna cached status solo se effettivamente cambiato
            let newStatus = claimSync.status(for: sinistro)
            if newStatus != cachedSyncStatus {
                cachedSyncStatus = newStatus
            }
            let newSuspended = claimSync.isSyncSuspended(for: sinistro)
            if newSuspended != cachedIsSuspended {
                cachedIsSuspended = newSuspended
            }
        }
        .onAppear {
            // Inizializza cached status al primo render
            cachedSyncStatus = claimSync.status(for: sinistro)
            cachedIsSuspended = claimSync.isSyncSuspended(for: sinistro)
        }
        .onDisappear {
            directoryMonitor.stopMonitoring()
            
            // Sincronizza quando l'utente esce dalla cartella per caricare eventuali modifiche
            Task {
                // Verifica che il sinistro sia sincronizzato e non sospeso
                guard claimSync.status(for: sinistro) != .notDownloaded,
                      !claimSync.isSyncSuspended(for: sinistro) else {
                    return
                }
                
                // Carica solo le modifiche locali (upload)
                await claimSync.uploadChangedFiles(for: sinistro, isBackgroundSync: true)
            }
        }
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let url = previewURL {
                MediaViewer(url: url)
            }
        }
        .popover(isPresented: $showingTagSheet, attachmentAnchor: .point(.top), arrowEdge: .top) {
            if let url = fileToTag {
                UnifiedTagView(context: .file(url), sinistroPath: sinistroPath)
            }
        }
        .onKeyPress(.space) {
            guard !isEditingTextField && !isSearchFieldFocused else { return .ignored }
            
            if let currentPath = columns[safe: selectedColumn],
               let url = selectedItems[currentPath] {
                quickLookURL = url
                return .handled
            }
            return .ignored
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CartellaViewKeyPress"))) { notification in
            guard !isEditingTextField && !isSearchFieldFocused else { return }
            
            if let key = notification.userInfo?["key"] as? String {
                switch key {
                case "leftArrow":
                    if selectedColumn > 0 {
                        selectedColumn -= 1
                        columnFocus = selectedColumn
                    }
                case "rightArrow":
                    if selectedColumn < columns.count,
                       let path = columns[safe: selectedColumn],
                       let url = selectedItems[path],
                       fileService.isDirectory(url) {
                        selectedColumn += 1
                        columnFocus = selectedColumn
                    }
                case "upArrow":
                    navigateToPreviousItem()
                case "downArrow":
                    navigateToNextItem()
                default:
                    break
                }
            }
        }
        .onKeyPress(.leftArrow) {
            // Intercetta solo se non stiamo editando un campo di testo
            guard !isEditingTextField && !isSearchFieldFocused else {
                return .ignored
            }
            
            if selectedColumn > 0 {
                selectedColumn -= 1
                columnFocus = selectedColumn
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            // Intercetta solo se non stiamo editando un campo di testo
            guard !isEditingTextField && !isSearchFieldFocused else {
                return .ignored
            }
            
            guard selectedColumn < columns.count,
                  let path = columns[safe: selectedColumn],
                  let url = selectedItems[path],
                  fileService.isDirectory(url) else {
                return .ignored
            }
            selectedColumn += 1
            columnFocus = selectedColumn
            return .handled
        }
        .onKeyPress(.upArrow) {
            // Intercetta solo se non stiamo editando un campo di testo
            guard !isEditingTextField && !isSearchFieldFocused else {
                return .ignored
            }
            
            navigateToPreviousItem()
            return .handled
        }
        .onKeyPress(.downArrow) {
            // Intercetta solo se non stiamo editando un campo di testo
            guard !isEditingTextField && !isSearchFieldFocused else {
                return .ignored
            }
            
            navigateToNextItem()
            return .handled
        }
        .sheet(isPresented: $showingNewFolderSheet) {
            if let currentPath = columns[safe: selectedColumn] {
                NewFolderView(currentPath: currentPath) { newFolderName in
                    fileService.createFolder(at: currentPath, named: newFolderName)
                    triggerRefresh()
                }
            }
        }
        .sheet(item: $itemToRename) { item in
            RenameItemView(item: item, sinistro: sinistro) { newName in
                fileService.renameItem(item, to: newName)
                triggerRefresh()
            }
        }
        .sheet(isPresented: $showingAttoSottotipoDialog) {
            if let attoFile = attoFileToUpdate {
                AttoSottotipoDialog { sottotipo in
                    if let sottotipo = sottotipo {
                        let sottotipoStr = sottotipo == .liquidazione ? "liquidazione" : "accertamento"
                        fileTagManager.setAttoSottotipo(sottotipoStr, forFile: attoFile.filePath, tagId: attoFile.tagId)
                    }
                    attoFileToUpdate = nil
                    generateClosureFilesWithSottotipo(sottotipo)
                }
            }
        }
        .alert("Elimina cartella locale", isPresented: $showingDeleteFolderConfirmation) {
            Button("Annulla", role: .cancel) { }
            Button("Elimina", role: .destructive) {
                Task {
                    // Mostra animazione
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isDeletingFolder = true
                    }
                    
                    // Attendi un attimo per l'animazione
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    
                    // Prima sospendi la sync (rimuove dal monitoring senza eliminare sul server)
                    if let rif = sinistro.riferimento {
                        claimSync.suspendSync(for: rif)
                    }
                    
                    // Poi elimina solo la cartella locale
                    await claimSync.deleteLocalFolderOnly(for: sinistro)
                    
                    // Nascondi overlay
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isDeletingFolder = false
                    }
                }
            }
        } message: {
            Text("Vuoi eliminare l'intera cartella locale del sinistro?\n\nLa cartella sul server non verrà modificata.")
        }
        .onChange(of: sinistro.riferimento) { _ in
            updateRootPath()
        }
    }
    
    private func updateRootPath() {
        guard let riferimento = sinistro.riferimento else {
            rootPath = nil
            return
        }
        rootPath = FileService.shared.getSinistroPath(riferimento: riferimento, create: false)
    }
    
    // MARK: - Deleting Folder Overlay
    
    private var deletingFolderOverlay: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
            
            VStack(spacing: 20) {
                // Icona cartella animata
                ZStack {
                    // Cerchio di sfondo
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 120, height: 120)
                    
                    // Icona cartella che scompare
                    Image(systemName: "folder.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red.opacity(0.8))
                        .scaleEffect(isDeletingFolder ? 0.5 : 1.0)
                        .opacity(isDeletingFolder ? 0 : 1)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isDeletingFolder)
                    
                    // Icona cestino
                    Image(systemName: "trash.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.red)
                        .offset(x: 25, y: 25)
                }
                
                Text("Eliminazione in corso...")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }
    
    // MARK: - Toolbar View
    
    private func toolbarView(rootPath: String) -> some View {
        HStack(spacing: 16) {
            // Search field espandibile
            HStack {
                if isSearchActive {
                    SearchField(
                        text: $appState.searchText,
                        isActive: $isSearchActive,
                        isFocused: _isSearchFieldFocused,
                        placeholder: "Cerca file..."
                    )
                    .frame(width: 200)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                
                if !isSearchActive {
                    Button {
                        withAnimation {
                            isSearchActive = true
                            isSearchFieldFocused = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cerca (⌘F)")
                    .keyboardShortcut("f", modifiers: .command)
                }
            }
            
            Spacer()
            
            // Toolbar buttons
            HStack(spacing: 12) {
                // Toggle pannello anteprima
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPreviewPanel.toggle()
                    }
                } label: {
                    Image(systemName: showPreviewPanel ? "sidebar.right" : "sidebar.right")
                        .foregroundColor(showPreviewPanel ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(showPreviewPanel ? "Nascondi anteprima" : "Mostra anteprima")

                // AutoTagging IA
                if autoTaggingService.isProcessing {
                    Button {
                        autoTaggingService.cancel()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.circle.fill")
                                .foregroundColor(.red)
                            Text("\(autoTaggingService.processedCount)/\(autoTaggingService.totalCount)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Interrompi autotagging")
                } else {
                    Button {
                        Task {
                            showingAutoTaggingProgress = true
                            let count = await AutoCheckService.shared.runPhotoAutoTagging(for: sinistro, forceReanalyze: false)
                            showingAutoTaggingProgress = false
                            if count > 0 {
                                triggerRefresh()
                            }
                        }
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .buttonStyle(.plain)
                    .help("AutoTagging IA foto")
                }
                
                // Genera file di chiusura
                Button {
                    checkAndGenerateClosureFiles(rootPath: rootPath)
                } label: {
                    if isGeneratingClosure {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "doc.badge.plus")
                    }
                }
                .buttonStyle(.plain)
                .help("Genera file di chiusura")
                .disabled(isGeneratingClosure)
                
                Button {
                    showingNewFolderSheet = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .help("Nuova Cartella")
                
                Button {
                    exportFolder()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help("Esporta cartella")
                .disabled(isExporting)

                Button {
                    showingDeleteFolderConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Elimina cartella locale")
                
                Divider()
                    .frame(height: 16)
                
                // Indicatore sync interattivo (in fondo a destra)
                SyncIndicatorView(
                    sinistro: sinistro,
                    status: cachedSyncStatus,
                    isSuspended: cachedIsSuspended,
                    agentReachable: claimSync.agentReachable,
                    onForceSync: {
                        Task { await claimSync.manualDownload(for: sinistro) }
                    },
                    onSuspendSync: {
                        if let rif = sinistro.riferimento {
                            claimSync.suspendSync(for: rif)
                        }
                    },
                    onResumeSync: {
                        Task {
                            if let rif = sinistro.riferimento {
                                await claimSync.resumeSync(for: rif)
                            }
                        }
                    },
                    onStopAndRemove: {
                        Task {
                            if let rif = sinistro.riferimento {
                                await claimSync.stopSyncAndRemoveFolder(riferimento: rif)
                            }
                        }
                    }
                )
            }
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Empty Folder View
    
    private var emptyFolderView: some View {
        EmptyFolderView(
            sinistro: sinistro,
            status: claimSync.status(for: sinistro),
            agentReachable: claimSync.agentReachable,
            onDownload: {
                Task { await claimSync.manualDownload(for: sinistro) }
            },
            onStopSync: {
                Task {
                    if let riferimento = sinistro.riferimento {
                        await claimSync.stopSyncAndScheduleDeletion(riferimento: riferimento)
                    }
                }
            },
            onForceSync: {
                Task { await claimSync.manualDownload(for: sinistro) }
            },
            onFilesImported: {
                setupView()
                triggerRefresh()
            }
        )
    }
    
    // MARK: - Columns View
    
    private var columnsView: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Colonne di navigazione
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 0) {
                        ForEach(Array(columns.enumerated()), id: \.element) { index, path in
                            HStack(spacing: 0) {
                                ColumnView(
                                    path: path,
                                    isSelected: index == selectedColumn,
                                    selectedItem: selectedItems[path] ?? nil,
                                    onItemSelected: { url in
                                        handleItemSelection(at: index, url: url, totalWidth: geometry.size.width)
                                    },
                                    sinistro: sinistro,
                                    refreshTrigger: refreshTrigger,
                                    draggedItem: $draggedItem,
                                    draggedItems: $draggedItems,
                                    onFileMoved: {
                                        triggerRefresh()
                                    }
                                )
                                .frame(width: getColumnWidth(at: index, totalWidth: showPreviewPanel ? geometry.size.width - 320 : geometry.size.width))
                                .focused($columnFocus, equals: index)
                                
                                if index < columns.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: showPreviewPanel ? geometry.size.width - 320 : .infinity)
                .onDrop(of: [.fileURL, .url], isTargeted: nil) { providers in
                    // Gestisce drop sulla root o area vuota delle colonne
                    if let rootPath = columns.first {
                        // 1. Gestione drag interno
                        if !draggedItems.isEmpty {
                            var allSuccess = true
                            for dragged in draggedItems {
                                if !fileService.moveItem(dragged, to: rootPath) {
                                    allSuccess = false
                                }
                            }
                            if allSuccess {
                                triggerRefresh()
                            }
                            draggedItem = nil
                            draggedItems = []
                            return allSuccess
                        } else if let dragged = draggedItem {
                            let success = fileService.moveItem(dragged, to: rootPath)
                            if success {
                                triggerRefresh()
                            }
                            draggedItem = nil
                            draggedItems = []
                            return success
                        }
                        
                        // 2. Gestione file esterni
                        ExternalFileDropHelpers.importFromProviders(providers, to: rootPath) { success in
                            if success {
                                triggerRefresh()
                            }
                            // Pulisci lo stato del drag (caso improbabile qui ma per sicurezza)
                            DispatchQueue.main.async {
                                draggedItem = nil
                                draggedItems = []
                            }
                        }
                        return true
                    }
                    return false
                }
                
                // Pannello anteprima stile Finder
                if showPreviewPanel {
                    Divider()
                    
                    PreviewPanelView(
                        selectedFile: currentSelectedFile,
                        sinistro: sinistro,
                        onOpenFile: { url in
                            fileService.ensureFileDownloaded(url: url) { success in
                                guard success else { return }
                                DispatchQueue.main.async {
                                    if isMediaViewerSupported(url) {
                                        MediaViewerWindowManager.shared.openMediaViewer(for: url)
                                    } else {
                                        fileService.openFile(url)
                                    }
                                }
                            }
                        },
                        isEditingTextField: $isEditingTextField
                    )
                    .frame(width: 320)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private func isMediaViewerSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp", "pdf", "mp4", "mov", "avi", "mkv", "m4v"].contains(ext)
    }
    
    private func setupView() {
        if let rootPath = fileService.getSinistroPath(riferimento: sinistro.riferimento ?? "") {
            columns = [rootPath]
            columnWidths = [totalWidth]
            
            directoryMonitor.onChange = { [self] in
                triggerRefresh()
                scanNewFilesForAutoTags(inPath: rootPath)
            }
            directoryMonitor.startMonitoring(paths: [rootPath])
            
            scanNewFilesForAutoTags(inPath: rootPath)
        }
    }
    
    private func triggerRefresh() {
        refreshTrigger = UUID()
    }
    
    private func scanNewFilesForAutoTags(inPath path: String) {
        Task.detached(priority: .utility) {
            await AutoCheckService.shared.scanNewFilesForTags(inPath: path)
        }
    }
    
    private func navigateToPreviousItem() {
        if let currentPath = columns[safe: selectedColumn] {
            if let currentItem = selectedItems[currentPath],
               let previousItem = fileService.getPreviousItem(before: currentItem, in: currentPath) {
                handleItemSelection(at: selectedColumn, url: previousItem, totalWidth: 0)
            } else {
                let items = fileService.listContents(inDirectory: currentPath)
                if let lastItem = items.last {
                    handleItemSelection(at: selectedColumn, url: lastItem.url, totalWidth: 0)
                }
            }
        }
    }
    
    private func navigateToNextItem() {
        if let currentPath = columns[safe: selectedColumn] {
            if let currentItem = selectedItems[currentPath],
               let nextItem = fileService.getNextItem(after: currentItem, in: currentPath) {
                handleItemSelection(at: selectedColumn, url: nextItem, totalWidth: 0)
            } else {
                let items = fileService.listContents(inDirectory: currentPath)
                if let firstItem = items.first {
                    handleItemSelection(at: selectedColumn, url: firstItem.url, totalWidth: 0)
                }
            }
        }
    }
    
    // MARK: - Closure Files Generation
    
    private func checkAndGenerateClosureFiles(rootPath: String) {
        let attoInfo = findAttoInfoFromTags(inPath: rootPath)
        
        guard let info = attoInfo else {
            generateClosureFilesWithSottotipo(nil)
            return
        }
        
        if let sottotipo = info.sottotipo {
            generateClosureFilesWithSottotipo(sottotipo)
            return
        }
        
        attoFileToUpdate = (filePath: info.filePath, tagId: info.tagId)
        showingAttoSottotipoDialog = true
    }
    
    private struct AttoInfo {
        let filePath: String
        let tagId: String
        let sottotipo: SottotipoAtto?
    }
    
    private func findAttoInfoFromTags(inPath path: String) -> AttoInfo? {
        let allFiles = fileService.listFilesRecursive(inDirectory: path)
        
        var attiFirmati: [(filePath: String, tagId: String)] = []
        var attiDaFirmare: [(filePath: String, tagId: String)] = []
        
        // Raccogli tutti gli atti, separando firmati da da firmare
        for fileURL in allFiles {
            let filePath = fileURL.path
            let tags = fileTagManager.getTagsForFile(at: filePath)
            
            for tag in tags where FileTagManager.FileTag.attoTags.contains(tag.id) {
                guard fileTagManager.getDaAllegareInChiusura(forFile: filePath, tagId: tag.id) else {
                    continue
                }
                
                if tag.id == "atto_firmato" {
                    attiFirmati.append((filePath: filePath, tagId: tag.id))
                } else if tag.id == "atto_da_firmare" {
                    attiDaFirmare.append((filePath: filePath, tagId: tag.id))
                }
            }
        }
        
        // Priorità agli atti firmati
        let attiDaCercare = attiFirmati.isEmpty ? attiDaFirmare : attiFirmati
        
        for atto in attiDaCercare {
            // Cerca il sottotipo prima nel tag corrente, poi nell'altro tag possibile
            var sottotipoStr = fileTagManager.getAttoSottotipo(forFile: atto.filePath, tagId: atto.tagId)
            
            // Se non trovato, prova con l'altro tag atto
            if sottotipoStr == nil {
                let altroTagId = atto.tagId == "atto_firmato" ? "atto_da_firmare" : "atto_firmato"
                sottotipoStr = fileTagManager.getAttoSottotipo(forFile: atto.filePath, tagId: altroTagId)
            }
            
            let sottotipo: SottotipoAtto?
            if sottotipoStr == "liquidazione" {
                sottotipo = .liquidazione
            } else if sottotipoStr == "accertamento" {
                sottotipo = .accertamento
            } else {
                sottotipo = nil
            }
            
            return AttoInfo(filePath: atto.filePath, tagId: atto.tagId, sottotipo: sottotipo)
        }
        
        return nil
    }
    
    private func generateClosureFilesWithSottotipo(_ sottotipo: SottotipoAtto?) {
        showingAttoSottotipoDialog = false
        isGeneratingClosure = true
        
        Task { @MainActor in
            let missingFiles = await closureService.checkMissingEssentialFiles(for: sinistro)
            if !missingFiles.isEmpty {
                NotificationService.shared.sendMissingFilesNotification(sinistro: sinistro, missingFiles: missingFiles)
            }
            
            closureService.generateClosureFiles(for: sinistro, attoSottotipo: sottotipo) { result in
                DispatchQueue.main.async {
                    self.isGeneratingClosure = false
                    self.triggerRefresh()
                    
                    if !result.errors.isEmpty {
                        NotificationService.shared.sendClosureErrorNotification(sinistro: self.sinistro, errors: result.errors)
                    } else {
                        print("[CartellaView] ✅ File di chiusura generati: \(result.generatedFiles.count) file")
                    }
                }
            }
        }
    }
    
    private func getColumnWidth(at index: Int, totalWidth: CGFloat) -> CGFloat {
        let availableWidth = totalWidth
        if columns.count == 1 {
            return availableWidth
        } else if columns.count == 2 {
            return availableWidth / 2
        } else {
            return availableWidth / 3
        }
    }
    
    private func handleItemSelection(at column: Int, url: URL) {
        guard column < columns.count else { return }
        selectedColumn = column
        let path = columns[column]
        selectedItems[path] = url
        
        if fileService.isDirectory(url) {
            columns = Array(columns.prefix(column + 1))
            columns.append(url.path)
            previewURL = nil
        }
    }
    
    private func handleItemSelection(at column: Int, url: URL, totalWidth: CGFloat) {
        guard column < columns.count else { return }
        selectedColumn = column
        let path = columns[column]
        selectedItems[path] = url
        
        if fileService.isDirectory(url) {
            columns = Array(columns.prefix(column + 1))
            columns.append(url.path)
            self.totalWidth = totalWidth
            previewURL = nil
        }
    }
    
    /// Esporta la cartella del sinistro nella directory di esportazione
    private func exportFolder() {
        guard let riferimento = sinistro.riferimento else { return }
        
        isExporting = true
        exportError = nil
        
        // Ottieni directory di esportazione dalle impostazioni (o usa default)
        let exportDirectory = UserDefaults.standard.string(forKey: "exportDirectory")
        
        fileService.exportFolder(riferimento: riferimento, to: exportDirectory) { success, error in
            DispatchQueue.main.async {
                self.isExporting = false
                if success {
                    self.showingExportSuccess = true
                    // L'esportazione apre già la cartella nel Finder
                } else {
                    self.exportError = error ?? "Errore sconosciuto durante l'esportazione"
                }
            }
        }
    }
}
