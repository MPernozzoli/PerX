import SwiftUI
import QuickLookThumbnailing
import PDFKit

// MARK: - Preview Panel View (Redesigned)

struct PreviewPanelView: View {
    let selectedFile: URL?
    let sinistro: Sinistro
    let onOpenFile: (URL) -> Void
    @Binding var isEditingTextField: Bool
    
    @StateObject private var fileTagManager = FileTagManager.shared
    @StateObject private var autoTaggingService = AutoTaggingService.shared
    @State private var thumbnail: NSImage?
    @State private var isLoadingThumbnail = false
    @State private var isDownloadingFromiCloud = false
    @State private var showTagPopover = false
    @State private var fileMetadata: FileMetadata?
    @State private var isHoveringPreview = false
    @State private var selectedSection: InspectorSection = .info
    @State private var isAutoTagging = false
    
    private let fileService = FileService.shared
    
    enum InspectorSection: String, CaseIterable {
        case info = "Info"
        case tags = "Tag"
        case actions = "Azioni"
    }
    
    struct FileMetadata {
        let name: String
        let size: String
        let sizeBytes: Int64
        let created: String
        let modified: String
        let kind: String
        let kindIcon: String
        let dimensions: String?
        let duration: String?
    }
    
    // MARK: - Computed Properties
    
    private var sinistroPath: String? {
        guard let ref = sinistro.riferimento,
              let file = selectedFile else { return nil }
        let components = file.pathComponents
        let prefixComponents = Array(components.prefix(while: { $0 != ref }))
        return prefixComponents.joined(separator: "/") + "/\(ref)"
    }
    
    private var isImage: Bool {
        guard let file = selectedFile else { return false }
        return isImageFile(file)
    }
    
    private var isPDF: Bool {
        guard let file = selectedFile else { return false }
        return file.pathExtension.lowercased() == "pdf"
    }
    
    private var isVideo: Bool {
        guard let file = selectedFile else { return false }
        let ext = file.pathExtension.lowercased()
        return ["mp4", "mov", "avi", "mkv", "m4v"].contains(ext)
    }
    
    private var isExcel: Bool {
        guard let file = selectedFile else { return false }
        let ext = file.pathExtension.lowercased()
        return ["xls", "xlsx", "xlsm"].contains(ext)
    }
    
    private var isWord: Bool {
        guard let file = selectedFile else { return false }
        let ext = file.pathExtension.lowercased()
        return ["doc", "docx"].contains(ext)
    }
    
    private var fileTags: Set<FileTagManager.FileTag> {
        guard let file = selectedFile else { return [] }
        return fileTagManager.getTagsForFile(at: file.path)
    }
    
    private var hasPinnedTags: Bool {
        guard let file = selectedFile else { return false }
        return fileTags.contains { tag in
            fileTagManager.getDaAllegareInChiusura(forFile: file.path, tagId: tag.id)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            if let file = selectedFile {
                // Header compatto con anteprima
                previewHeader(file: file)
                
                // Tab selector
                tabSelector
                
                Divider()
                
                // Contenuto basato sulla tab selezionata
                ScrollView {
                    VStack(spacing: 0) {
                        switch selectedSection {
                        case .info:
                            infoSection(file: file)
                        case .tags:
                            tagsSection(file: file)
                        case .actions:
                            actionsSection(file: file)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .onChange(of: selectedFile) { newFile in
                    loadPreview(for: newFile)
                }
                .onAppear {
                    loadPreview(for: file)
                }
            } else {
                emptyState
            }
        }
        .background(inspectorBackground)
    }
    
    // MARK: - Background
    
    private var inspectorBackground: some View {
        ZStack {
            Color(NSColor.controlBackgroundColor)
            
            // Sottile pattern di texture
            LinearGradient(
                colors: [
                    Color(NSColor.separatorColor).opacity(0.03),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    // MARK: - Preview Header
    
    private func previewHeader(file: URL) -> some View {
        VStack(spacing: 12) {
            // Anteprima con overlay interattivo
            ZStack {
                if isDownloadingFromiCloud {
                    iCloudDownloadingView
                } else if isLoadingThumbnail {
                    loadingView
                } else if let thumbnail = thumbnail {
                    thumbnailView(thumbnail: thumbnail)
                } else {
                    iconFallback(file: file)
                }
                
                // Overlay con azioni rapide al hover
                if isHoveringPreview && thumbnail != nil {
                    previewOverlay(file: file)
                }
                
                // Badge stato
                statusBadges(file: file)
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.quaternaryLabelColor).opacity(0.1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHoveringPreview = hovering
                }
            }
            .onTapGesture(count: 2) {
                onOpenFile(file)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Nome file con tipo
            VStack(spacing: 4) {
                Text(file.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                if let metadata = fileMetadata {
                    HStack(spacing: 6) {
                        Image(systemName: metadata.kindIcon)
                            .font(.system(size: 10))
                        Text(metadata.kind)
                            .font(.system(size: 11))
                        Text("•")
                        Text(metadata.size)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - iCloud & Loading Views
    
    private var iCloudDownloadingView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 3)
                    .frame(width: 50, height: 50)
                
                ProgressView()
                    .scaleEffect(1.2)
            }
            
            Text("Download da iCloud...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Caricamento...")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private func thumbnailView(thumbnail: NSImage) -> some View {
        Image(nsImage: thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 260, maxHeight: 160)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
    }
    
    private func iconFallback(file: URL) -> some View {
        VStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                .resizable()
                .frame(width: 64, height: 64)
            
            if let metadata = fileMetadata {
                Text(metadata.kind)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Preview Overlay
    
    private func previewOverlay(file: URL) -> some View {
        ZStack {
            // Sfondo scuro semitrasparente
            Color.black.opacity(0.5)
            
            // Pulsante centrale
            Button {
                onOpenFile(file)
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.circle.fill")
                        .font(.system(size: 36))
                    Text("Apri")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .transition(.opacity)
    }
    
    // MARK: - Status Badges
    
    private func statusBadges(file: URL) -> some View {
        VStack {
            HStack {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    // Badge tag applicati
                    if !fileTags.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 9))
                            Text("\(fileTags.count)")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.accentColor)
                        )
                        .foregroundColor(.white)
                    }
                    
                    // Badge da allegare
                    if hasPinnedTags {
                        HStack(spacing: 4) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                            Text("Allegare")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.orange)
                        )
                        .foregroundColor(.white)
                    }
                }
            }
            
            Spacer()
        }
        .padding(8)
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(InspectorSection.allCases, id: \.self) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSection = section
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(section.rawValue)
                            .font(.system(size: 12, weight: selectedSection == section ? .semibold : .regular))
                            .foregroundColor(selectedSection == section ? .primary : .secondary)
                        
                        Rectangle()
                            .fill(selectedSection == section ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    // MARK: - Info Section
    
    private func infoSection(file: URL) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Metadati file
            if let metadata = fileMetadata {
                VStack(spacing: 0) {
                    MetadataCardRow(icon: "doc", label: "Tipo", value: metadata.kind)
                    Divider().padding(.leading, 40)
                    MetadataCardRow(icon: "externaldrive", label: "Dimensione", value: metadata.size)
                    Divider().padding(.leading, 40)
                    MetadataCardRow(icon: "calendar", label: "Creato", value: metadata.created)
                    Divider().padding(.leading, 40)
                    MetadataCardRow(icon: "clock", label: "Modificato", value: metadata.modified)
                    
                    if let dimensions = metadata.dimensions {
                        Divider().padding(.leading, 40)
                        MetadataCardRow(icon: "aspectratio", label: "Risoluzione", value: dimensions)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                )
            }
            
            // Descrizione AI (se presente)
            if let descrizione = fileTagManager.getAdditionalText(forFile: file.path, tagId: "descrizione_ai"), !descrizione.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                            .font(.system(size: 12))
                        Text("Descrizione IA")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    
                    Text(descrizione)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.purple.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            
            // Tag applicati (preview compatto)
            if !fileTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tag applicati")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button {
                            selectedSection = .tags
                        } label: {
                            Text("Modifica")
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    InspectorTagFlowLayout(spacing: 6) {
                        ForEach(Array(fileTags), id: \.id) { tag in
                            CompactTagBadge(tag: tag, filePath: file.path, fileTagManager: fileTagManager)
                        }
                    }
                }
            }
        }
        .padding(16)
    }
    
    // MARK: - Tags Section
    
    private func tagsSection(file: URL) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Quick tag per foto
            if isImage {
                PhotoTagSelectorView(
                    filePath: file.path,
                    sinistro: sinistro,
                    fileTagManager: fileTagManager,
                    isEditingTextField: $isEditingTextField
                )
            }
            
            // Tutti i tag applicati con gestione
            if !fileTags.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tag applicati")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(fileTags), id: \.id) { tag in
                        AppliedTagCard(
                            tag: tag,
                            filePath: file.path,
                            fileTagManager: fileTagManager
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            
            // Pulsante gestione tag completa
            Button {
                showTagPopover = true
            } label: {
                HStack {
                    Image(systemName: "tag.fill")
                    Text("Gestisci tutti i tag")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .popover(isPresented: $showTagPopover) {
                UnifiedTagView(context: .file(file), sinistroPath: sinistroPath)
            }
        }
        .padding(.top, 16)
    }
    
    // MARK: - Actions Section
    
    private func actionsSection(file: URL) -> some View {
        VStack(spacing: 12) {
            // Azioni principali
            VStack(spacing: 8) {
                ActionButton(
                    icon: "arrow.up.forward.square.fill",
                    title: "Apri file",
                    subtitle: "Apri con l'app predefinita",
                    color: .accentColor
                ) {
                    onOpenFile(file)
                }
                
                ActionButton(
                    icon: "eye.fill",
                    title: "Anteprima rapida",
                    subtitle: "QuickLook",
                    color: .blue
                ) {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
                
                ActionButton(
                    icon: "folder.fill",
                    title: "Mostra nel Finder",
                    subtitle: "Apri la cartella contenente",
                    color: .gray
                ) {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Azioni contestuali per immagini
            if isImage {
                VStack(spacing: 8) {
                    ActionButton(
                        icon: "wand.and.stars",
                        title: "Autotagga con IA",
                        subtitle: isAutoTagging ? "Analisi in corso..." : "Analizza e applica tag automatici",
                        color: .purple,
                        isLoading: isAutoTagging
                    ) {
                        Task {
                            isAutoTagging = true
                            await AutoCheckService.shared.autoTagPhotoFiles([file], for: sinistro)
                            isAutoTagging = false
                        }
                    }
                    
                    ActionButton(
                        icon: "arrow.down.circle.fill",
                        title: "Comprimi immagine",
                        subtitle: "Riduci dimensione file",
                        color: .orange
                    ) {
                        // Compressione
                        MediaEditorService.shared.compressImage(at: file, quality: 0.7) { _ in }
                    }
                }
            }
            
            // Azioni per PDF
            if isPDF {
                ActionButton(
                    icon: "arrow.down.circle.fill",
                    title: "Comprimi PDF",
                    subtitle: "Ottimizza per web",
                    color: .orange
                ) {
                    MediaEditorService.shared.compressPDF(at: file, quality: 0.7) { _ in }
                }
            }
            
            // Azioni per Excel elaborato
            if isExcel && file.lastPathComponent.starts(with: "Elaborato_Peritale_") {
                ActionButton(
                    icon: "arrow.clockwise",
                    title: "Sincronizza dati",
                    subtitle: "Aggiorna sinistro da Excel",
                    color: .green
                ) {
                    Task {
                        await AutoCheckService.shared.readAndUpdateExcel(excelURL: file, sinistro: sinistro)
                    }
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Azioni file
            VStack(spacing: 8) {
                ActionButton(
                    icon: "doc.on.doc.fill",
                    title: "Copia nome",
                    subtitle: file.lastPathComponent,
                    color: .secondary
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(file.lastPathComponent, forType: .string)
                }
                
                if !isPDF {
                    ActionButton(
                        icon: "doc.fill",
                        title: "Converti in PDF",
                        subtitle: "Crea versione PDF",
                        color: .red
                    ) {
                        ClosureFilesService.shared.convertFilesToPDF(fileURLs: [file]) { _, _ in }
                    }
                }
            }
        }
        .padding(16)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color(NSColor.quaternaryLabelColor).opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            
            VStack(spacing: 8) {
                Text("Nessun file selezionato")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Seleziona un file dalla lista\nper vedere i dettagli")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Load Preview
    
    private func loadPreview(for url: URL?) {
        guard let url = url else {
            thumbnail = nil
            fileMetadata = nil
            isDownloadingFromiCloud = false
            return
        }
        
        fileService.ensureFileDownloaded(url: url) { success in
            DispatchQueue.main.async {
                if !success {
                    thumbnail = nil
                    fileMetadata = nil
                    isDownloadingFromiCloud = false
                    return
                }
                
                isDownloadingFromiCloud = false
                isLoadingThumbnail = true
                
                loadMetadata(for: url)
                
                let size = CGSize(width: 560, height: 400)
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                
                let request = QLThumbnailGenerator.Request(
                    fileAt: url,
                    size: size,
                    scale: scale,
                    representationTypes: .thumbnail
                )
                
                QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, error in
                    DispatchQueue.main.async {
                        isLoadingThumbnail = false
                        if let rep = rep {
                            thumbnail = rep.nsImage
                        } else {
                            // Per Word ed Excel, riprova con più tempo
                            let ext = url.pathExtension.lowercased()
                            if ["doc", "docx", "xls", "xlsx", "xlsm"].contains(ext) {
                                loadOfficeThumbnail(for: url)
                            } else {
                                loadThumbnailManually(for: url)
                            }
                        }
                    }
                }
            }
        }
        
        if let resourceValues = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
           resourceValues.isUbiquitousItem == true,
           resourceValues.ubiquitousItemDownloadingStatus == .notDownloaded {
            isDownloadingFromiCloud = true
        }
    }
    
    private func loadThumbnailManually(for url: URL) {
        let ext = url.pathExtension.lowercased()
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
        
        if imageExtensions.contains(ext) {
            Task.detached(priority: .userInitiated) {
                // Usa SEMPRE security-scoped access per evitare errori sandbox
                let parentPath = url.deletingLastPathComponent().path
                let loadedImage: NSImage? = fileService.performWithSecurityScopedAccess(to: parentPath) {
                    // Prova prima con NSImage(contentsOf:) che è più efficiente
                    if let img = NSImage(contentsOf: url) {
                        return img
                    }
                    // Fallback: carica come Data e poi crea NSImage
                    if let data = try? Data(contentsOf: url) {
                        return NSImage(data: data)
                    }
                    return nil
                } ?? nil
                
                await MainActor.run {
                    thumbnail = loadedImage
                }
            }
        } else if ext == "pdf" {
            Task.detached(priority: .userInitiated) {
                // Usa SEMPRE security-scoped access per evitare errori sandbox
                let parentPath = url.deletingLastPathComponent().path
                let pdfThumb: NSImage? = fileService.performWithSecurityScopedAccess(to: parentPath) {
                    if let doc = PDFDocument(url: url), let page = doc.page(at: 0) {
                        return page.thumbnail(of: CGSize(width: 280, height: 400), for: .mediaBox)
                    }
                    return nil
                } ?? nil
                
                await MainActor.run {
                    thumbnail = pdfThumb
                }
            }
        }
    }
    
    private func loadOfficeThumbnail(for url: URL) {
        // Per Word ed Excel, usa QuickLook con più tempo e retry
        Task.detached(priority: .userInitiated) {
            let parentPath = url.deletingLastPathComponent().path
            let officeThumb: NSImage? = fileService.performWithSecurityScopedAccess(to: parentPath) {
                let size = CGSize(width: 560, height: 400)
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                
                let request = QLThumbnailGenerator.Request(
                    fileAt: url,
                    size: size,
                    scale: scale,
                    representationTypes: .thumbnail
                )
                
                var result: NSImage? = nil
                let semaphore = DispatchSemaphore(value: 0)
                
                QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, error in
                    if let rep = rep {
                        result = rep.nsImage
                    }
                    semaphore.signal()
                }
                
                // Attendi fino a 5 secondi per la generazione (Word/Excel richiedono più tempo)
                _ = semaphore.wait(timeout: .now() + 5.0)
                return result
            } ?? nil
            
            await MainActor.run {
                thumbnail = officeThumb
            }
        }
    }
    
    private func loadMetadata(for url: URL) {
        let fm = FileManager.default
        
        guard let attributes = try? fm.attributesOfItem(atPath: url.path) else {
            fileMetadata = nil
            return
        }
        
        let size = attributes[.size] as? Int64 ?? 0
        let created = attributes[.creationDate] as? Date ?? Date()
        let modified = attributes[.modificationDate] as? Date ?? Date()
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        let (kind, kindIcon) = getFileKindWithIcon(for: url)
        
        var dimensions: String? = nil
        let ext = url.pathExtension.lowercased()
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
        
        if imageExtensions.contains(ext) {
            // Usa security-scoped access per leggere metadata immagine
            let parentPath = url.deletingLastPathComponent().path
            let dims: String? = fileService.performWithSecurityScopedAccess(to: parentPath) {
                guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
                      let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight as String] as? Int else {
                    return nil
                }
                return "\(width) × \(height) px"
            } ?? nil
            dimensions = dims
        }
        
        fileMetadata = FileMetadata(
            name: url.lastPathComponent,
            size: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
            sizeBytes: size,
            created: dateFormatter.string(from: created),
            modified: dateFormatter.string(from: modified),
            kind: kind,
            kindIcon: kindIcon,
            dimensions: dimensions,
            duration: nil
        )
    }
    
    private func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"].contains(ext)
    }
    
    private func getFileKindWithIcon(for url: URL) -> (String, String) {
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "pdf": return ("PDF", "doc.fill")
        case "doc", "docx": return ("Word", "doc.text.fill")
        case "xls", "xlsx", "xlsm": return ("Excel", "tablecells.fill")
        case "ppt", "pptx": return ("PowerPoint", "rectangle.stack.fill")
        case "jpg", "jpeg": return ("JPEG", "photo.fill")
        case "png": return ("PNG", "photo.fill")
        case "gif": return ("GIF", "photo.stack.fill")
        case "heic": return ("HEIC", "photo.fill")
        case "webp": return ("WebP", "photo.fill")
        case "mp4": return ("MP4", "film.fill")
        case "mov": return ("QuickTime", "film.fill")
        case "avi": return ("AVI", "film.fill")
        case "mp3": return ("MP3", "waveform")
        case "wav": return ("WAV", "waveform")
        case "txt": return ("Testo", "doc.text")
        case "zip": return ("ZIP", "doc.zipper")
        case "rar": return ("RAR", "doc.zipper")
        default: return ("Documento", "doc")
        }
    }
}

// MARK: - Supporting Views

struct MetadataCardRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct CompactTagBadge: View {
    let tag: FileTagManager.FileTag
    let filePath: String
    @ObservedObject var fileTagManager: FileTagManager
    
    private var isPinned: Bool {
        fileTagManager.getDaAllegareInChiusura(forFile: filePath, tagId: tag.id)
    }
    
    private var additionalText: String? {
        fileTagManager.getAdditionalText(forFile: filePath, tagId: tag.id)
    }
    
    private var beneRiferimento: String? {
        fileTagManager.getBeneRiferimento(forFile: filePath, tagId: tag.id)
    }
    
    /// Costruisce il testo da mostrare con bene e/o componente
    private var displayDetails: String? {
        var parts: [String] = []
        
        // Per foto_bene, additionalText è il bene
        if tag.id == "foto_bene" {
            if let text = additionalText, !text.isEmpty {
                parts.append(text)
            }
        } else {
            // Per altri tag, beneRiferimento è il bene
            if let bene = beneRiferimento, !bene.isEmpty {
                parts.append(bene)
            }
            // additionalText è il componente/descrizione
            if let text = additionalText, !text.isEmpty {
                parts.append(text)
            }
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(tag.tagColor)
                    .frame(width: 6, height: 6)
                
                Text(tag.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                }
            }
            
            // Dettagli bene/componente
            if let details = displayDetails {
                Text(details)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tag.tagColor.opacity(0.12))
        .cornerRadius(10)
    }
}

struct AppliedTagCard: View {
    let tag: FileTagManager.FileTag
    let filePath: String
    @ObservedObject var fileTagManager: FileTagManager
    
    private var isPinned: Bool {
        fileTagManager.getDaAllegareInChiusura(forFile: filePath, tagId: tag.id)
    }
    
    private var additionalText: String? {
        fileTagManager.getAdditionalText(forFile: filePath, tagId: tag.id)
    }
    
    private var beneRiferimento: String? {
        fileTagManager.getBeneRiferimento(forFile: filePath, tagId: tag.id)
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tag.tagColor)
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(tag.name)
                    .font(.system(size: 12, weight: .medium))
                
                // Mostra bene
                if tag.id == "foto_bene" {
                    // Per foto_bene, additionalText è il bene
                    if let text = additionalText, !text.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "cube.fill")
                                .font(.system(size: 9))
                                .foregroundColor(tag.tagColor.opacity(0.7))
                            Text(text)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    // Per altri tag, mostra bene di riferimento se presente
                    if let bene = beneRiferimento, !bene.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "cube.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.blue.opacity(0.7))
                            Text(bene)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Mostra componente/descrizione
                    if let text = additionalText, !text.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.orange.opacity(0.7))
                            Text(text)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Toggle pin
            Button {
                fileTagManager.setDaAllegareInChiusura(!isPinned, forFile: filePath, tagId: tag.id)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundColor(isPinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Rimuovi dalla chiusura" : "Allega in chiusura")
            
            // Remove - usa removeCurrentTag per coerenza con regola "un solo tag per file"
            Button {
                fileTagManager.removeCurrentTag(fromFile: filePath)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tag.tagColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tag.tagColor.opacity(0.2), lineWidth: 1)
        )
    }
}

struct ActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    var isLoading: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundColor(color)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor).opacity(isHovered ? 0.5 : 0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Flow Layout per tag Inspector (mantenuto per compatibilità)

struct InspectorTagFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            
            size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

// MARK: - Metadata Row (legacy, kept for compatibility)

struct MetadataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Applied Tag View (legacy, kept for compatibility)

struct AppliedTagView: View {
    let tag: FileTagManager.FileTag
    let filePath: String
    @ObservedObject var fileTagManager: FileTagManager
    
    private var isDaAllegare: Bool {
        fileTagManager.getDaAllegareInChiusura(forFile: filePath, tagId: tag.id)
    }
    
    private var additionalText: String? {
        fileTagManager.getAdditionalText(forFile: filePath, tagId: tag.id)
    }
    
    private var beneRiferimento: String? {
        fileTagManager.getBeneRiferimento(forFile: filePath, tagId: tag.id)
    }
    
    /// Costruisce il testo dei dettagli con bene e componente
    private var detailsText: String? {
        var parts: [String] = []
        
        if tag.id == "foto_bene" {
            if let text = additionalText, !text.isEmpty {
                parts.append(text)
            }
        } else {
            if let bene = beneRiferimento, !bene.isEmpty {
                parts.append(bene)
            }
            if let text = additionalText, !text.isEmpty {
                parts.append(text)
            }
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tag.tagColor)
                    .frame(width: 8, height: 8)
                
                Text(tag.name)
                    .font(.caption)
                
                Button {
                    fileTagManager.setDaAllegareInChiusura(!isDaAllegare, forFile: filePath, tagId: tag.id)
                } label: {
                    Image(systemName: isDaAllegare ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundColor(isDaAllegare ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help(isDaAllegare ? "Rimuovi da allegare in chiusura" : "Allega in chiusura")
            }
            
            // Mostra dettagli bene/componente
            if let details = detailsText {
                Text(details)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tag.tagColor.opacity(0.1))
        .cornerRadius(12)
    }
}
