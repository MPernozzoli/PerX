import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import PDFKit

// MARK: - Batch Tag Mode

enum BatchTagMode {
    case files           // Tag su file selezionati
    case folderContents  // Tag su contenuto cartella
}

// MARK: - Column View

struct ColumnView: View {
    let path: String
    let isSelected: Bool
    let selectedItem: URL?
    let onItemSelected: (URL) -> Void
    let sinistro: Sinistro
    let refreshTrigger: UUID
    @Binding var draggedItem: FileService.FileItem?
    @Binding var draggedItems: [FileService.FileItem]
    let onFileMoved: () -> Void
    
    @StateObject private var fileTagManager = FileTagManager.shared
    @StateObject private var downloadTracker = FileDownloadTracker.shared
    @StateObject private var claimSync = ClaimSyncService.shared
    @StateObject private var newFilesTracker = NewFilesTracker.shared
    @State private var items: [FileService.FileItem] = []
    @State private var showingTagSheet = false
    @State private var fileToTag: URL?
    @State private var showingNewFolderSheet = false
    @State private var showingRenamePopover = false
    @State private var itemToRename: FileService.FileItem?
    @State private var previewURL: URL?
    @State private var quickLookURL: URL?
    @State private var showingVersionRecovery = false
    @State private var fileForVersionRecovery: URL?
    @State private var showingCompressionSheet = false
    @State private var filesToCompress: [FileService.FileItem] = []
    @State private var showingBatchTagSheet = false
    @State private var filesToTag: [URL] = []
    @State private var batchTagMode: BatchTagMode = .files
    @State private var isConvertingToPDF = false
    @EnvironmentObject private var appState: AppState
    private let fileService = FileService.shared
    private let closureService = ClosureFilesService.shared
    
    private let versioningService = FileVersioningService.shared
    private let editorService = MediaEditorService.shared
    @State private var selectedItems: Set<URL> = []
    @State private var lastSelectedIndex: Int?
    @State private var dropTarget: FileService.FileItem?
    @State private var isDropTargetForExternal = false
    @State private var marqueeSelection: CGRect? = nil
    @State private var marqueeStartPoint: CGPoint? = nil
    
    var filteredItems: [FileService.FileItem] {
        if appState.searchText.isEmpty {
            return items
        }
        return items.filter { item in
            item.url.lastPathComponent
                .localizedCaseInsensitiveContains(appState.searchText)
        }
    }
    
    private func isMediaViewerSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp", "pdf", "mp4", "mov", "avi", "mkv", "m4v"].contains(ext)
    }
    
    private func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"].contains(ext)
    }
    
    private func openFile(_ item: FileService.FileItem) {
        // Non aprire file in download o non ancora scaricati
        guard !item.isDownloading && !item.isNotDownloaded else {
            return
        }
        
        // Segna il file come letto se è nuovo
        markFileAsReadIfNew(item: item)
        
        // Verifica e scarica file iCloud se necessario prima di aprire
        fileService.ensureFileDownloaded(url: item.url) { success in
            guard success else { return }
            DispatchQueue.main.async {
                if isMediaViewerSupported(item.url) {
                    MediaViewerWindowManager.shared.openMediaViewer(for: item.url)
                } else {
                    fileService.openFile(item.url)
                }
            }
        }
    }
    
    /// Segna un file come letto se è nuovo o modificato
    private func markFileAsReadIfNew(item: FileService.FileItem) {
        guard let riferimento = sinistro.riferimento,
              let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) else { return }
        
        let relativePath = getRelativePath(from: sinistroPath, to: item.url.path)
        if newFilesTracker.isNew(riferimento: riferimento, relativePath: relativePath) ||
           newFilesTracker.isModified(riferimento: riferimento, relativePath: relativePath) {
            newFilesTracker.markAsRead(riferimento: riferimento, relativePath: relativePath)
        }
    }
    
    /// Verifica se un file è nuovo
    private func isFileNew(_ item: FileService.FileItem) -> Bool {
        guard let riferimento = sinistro.riferimento,
              let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) else { return false }
        
        let relativePath = getRelativePath(from: sinistroPath, to: item.url.path)
        return newFilesTracker.isNew(riferimento: riferimento, relativePath: relativePath)
    }
    
    /// Verifica se un file è modificato
    private func isFileModified(_ item: FileService.FileItem) -> Bool {
        guard let riferimento = sinistro.riferimento,
              let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) else { return false }
        
        let relativePath = getRelativePath(from: sinistroPath, to: item.url.path)
        return newFilesTracker.isModified(riferimento: riferimento, relativePath: relativePath)
    }
    
    /// Ottiene lo status di un file
    private func getFileStatus(_ item: FileService.FileItem) -> FileStatus? {
        guard let riferimento = sinistro.riferimento,
              let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) else { return nil }
        
        let relativePath = getRelativePath(from: sinistroPath, to: item.url.path)
        return newFilesTracker.getStatus(riferimento: riferimento, relativePath: relativePath)
    }
    
    /// Numero di elementi selezionati (escludendo l'item corrente se non selezionato)
    private var effectiveSelectedCount: Int {
        selectedItems.count
    }
    
    /// Verifica se ci sono più elementi selezionati
    private var hasMultipleSelection: Bool {
        selectedItems.count > 1
    }
    
    /// Ottiene i file selezionati (non cartelle)
    private var selectedFilesOnly: [URL] {
        filteredItems.filter { selectedItems.contains($0.url) && !$0.isDirectory }.map { $0.url }
    }
    
    /// Ottiene tutti i file in una cartella ricorsivamente (solo file, non cartelle)
    private func getFilesInFolder(_ folderURL: URL) -> [URL] {
        let allItems = fileService.listFilesRecursive(inDirectory: folderURL.path)
        // Filtra esplicitamente solo i file (non cartelle)
        return allItems.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
        }
    }
    
    /// Crea FileItem a partire da URL selezionati
    private func createFileItems(from urls: [URL]) -> [FileService.FileItem] {
        let workspace = NSWorkspace.shared
        return urls.compactMap { url in
            guard let resourceValues = try? url.resourceValues(forKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey
            ]),
            let isDirectory = resourceValues.isDirectory else { return nil }
            
            // Salta le directory
            guard !isDirectory else { return nil }
            
            let icon = workspace.icon(forFile: url.path)
            return FileService.FileItem(
                id: url.path,
                url: url,
                isDirectory: false,
                icon: icon,
                size: Int64(resourceValues.fileSize ?? 0),
                modificationDate: resourceValues.contentModificationDate ?? Date()
            )
        }
    }
    
    private func buildContextMenu(for item: FileService.FileItem) -> some View {
        Group {
            let itemTags = fileTagManager.getTagsForFile(at: item.url.path)
            let isIncarico = itemTags.contains(where: { $0.id == "incarico" })
            
            // === MENU PER SELEZIONE MULTIPLA ===
            if hasMultipleSelection && selectedItems.contains(item.url) {
                Text("\(selectedItems.count) elementi selezionati")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                // Tag multiplo
                Button {
                    filesToTag = selectedFilesOnly
                    batchTagMode = .files
                    showingBatchTagSheet = true
                } label: {
                    Label("Applica Tag a \(selectedFilesOnly.count) file", systemImage: "tag.fill")
                }
                .disabled(selectedFilesOnly.isEmpty)
                
                // Autotagga multiplo con IA
                let imageFilesCount = selectedFilesOnly.filter { isImageFile($0) }.count
                if imageFilesCount > 0 {
                    Button {
                        Task {
                            let imageFiles = selectedFilesOnly.filter { isImageFile($0) }
                            await AutoCheckService.shared.autoTagPhotoFiles(imageFiles, for: sinistro)
                            refreshItems()
                        }
                    } label: {
                        Label("Autotagga \(imageFilesCount) foto con IA", systemImage: "wand.and.stars")
                    }
                    .disabled(AutoTaggingService.shared.isProcessing)
                }
                
                Divider()
                
                // Comprimi multiplo
                Button {
                    filesToCompress = createFileItems(from: selectedFilesOnly)
                    showingCompressionSheet = true
                } label: {
                    Label("Comprimi \(selectedFilesOnly.count) file", systemImage: "arrow.down.circle")
                }
                .disabled(selectedFilesOnly.isEmpty)
                
                // Crea PDF multiplo
                Button {
                    convertSelectedFilesToPDF()
                } label: {
                    Label("Crea PDF da \(selectedFilesOnly.count) file", systemImage: "doc.fill")
                }
                .disabled(selectedFilesOnly.isEmpty || isConvertingToPDF)
                
                Divider()
                
                // Elimina multiplo
                Button(role: .destructive) {
                    deleteMultipleItems()
                } label: {
                    Label("Elimina \(selectedItems.count) elementi", systemImage: "trash")
                }
                
            // === MENU PER CARTELLA SINGOLA ===
            } else if item.isDirectory {
                Button {
                    onItemSelected(item.url)
                } label: {
                    Label("Apri", systemImage: "folder")
                }
                
                Divider()
                
                // Applica tag al contenuto della cartella
                Button {
                    let filesInFolder = getFilesInFolder(item.url)
                    filesToTag = filesInFolder
                    batchTagMode = .folderContents
                    showingBatchTagSheet = true
                } label: {
                    Label("Applica Tag al contenuto", systemImage: "tag.fill")
                }
                
                Divider()
                
                Button {
                    showingNewFolderSheet = true
                } label: {
                    Label("Nuova Cartella", systemImage: "folder.badge.plus")
                }
                
                Button {
                    itemToRename = item
                    showingRenamePopover = true
                } label: {
                    Label("Rinomina", systemImage: "pencil")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    moveFolderToTrash(item)
                } label: {
                    Label("Elimina", systemImage: "trash")
                }
                
            // === MENU PER FILE SINGOLO ===
            } else {
                Button {
                    openFile(item)
                } label: {
                    Label("Apri", systemImage: "doc.text")
                }
                
                Button {
                    quickLookURL = item.url
                } label: {
                    Label("Anteprima", systemImage: "eye")
                }
                .keyboardShortcut(.space, modifiers: [])
                
                Button {
                    NSWorkspace.shared.open(item.url)
                } label: {
                    Label("Apri con app esterna", systemImage: "arrow.up.forward.app")
                }
                
                Button {
                    NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: item.url.deletingLastPathComponent().path)
                } label: {
                    Label("Mostra nel Finder", systemImage: "folder")
                }
                
                if item.url.pathExtension.lowercased() == "xlsm" && item.url.lastPathComponent.starts(with: "Elaborato_Peritale_") {
                    Divider()
                    
                    Button {
                        Task {
                            await AutoCheckService.shared.readAndUpdateExcel(excelURL: item.url, sinistro: sinistro)
                        }
                    } label: {
                        Label("Aggiorna Sinistro da Excel", systemImage: "arrow.clockwise")
                    }
                }
                
                // Verifica manuale regolarità amministrativa (solo se file taggato "incarico")
                if isIncarico {
                    Divider()
                    
                    Button {
                        fileService.ensureFileDownloaded(url: item.url) { success in
                            guard success else { return }
                            Task {
                                await AutoCheckService.shared.verifyRegolaritaAmministrativaManually(fromIncaricoPDF: item.url, sinistro: sinistro)
                            }
                        }
                    } label: {
                        Label("Verifica regolarità amministrativa", systemImage: "checkmark.shield")
                    }
                }
                
                Divider()
                
                Button {
                    fileToTag = item.url
                    showingTagSheet = true
                } label: {
                    Label("Gestisci Tag", systemImage: "tag")
                }
                
                // Autotagga con IA
                if isImageFile(item.url) {
                    Button {
                        Task {
                            await AutoCheckService.shared.autoTagPhotoFiles([item.url], for: sinistro)
                            refreshItems()
                        }
                    } label: {
                        Label("Autotagga con IA", systemImage: "wand.and.stars")
                    }
                    .disabled(AutoTaggingService.shared.isProcessing)
                }
                
                Divider()
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.url.lastPathComponent, forType: .string)
                } label: {
                    Label("Copia Nome", systemImage: "doc.on.doc")
                }
                
                Button {
                    itemToRename = item
                    showingRenamePopover = true
                } label: {
                    Label("Rinomina", systemImage: "pencil")
                }
                
                Divider()
                
                Button {
                    duplicateFile(item)
                } label: {
                    Label("Duplica", systemImage: "doc.on.doc.fill")
                }
                .keyboardShortcut("d", modifiers: .command)
                
                Button {
                    filesToCompress = [item]
                    showingCompressionSheet = true
                } label: {
                    Label("Comprimi", systemImage: "arrow.down.circle")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                
                Button {
                    convertSingleFileToPDF(item.url)
                } label: {
                    Label("Crea PDF", systemImage: "doc.fill")
                }
                .disabled(isConvertingToPDF || item.url.pathExtension.lowercased() == "pdf")
                
                // Stampa annotazioni (solo per PDF con firme)
                if item.url.pathExtension.lowercased() == "pdf" && hasSignatureAnnotations(fileURL: item.url) {
                    Divider()
                    Button {
                        printSignatureAnnotations(fileURL: item.url)
                    } label: {
                        Label("Stampa Annotazioni", systemImage: "printer.fill")
                    }
                }
                
                Button {
                    fileForVersionRecovery = item.url
                    showingVersionRecovery = true
                } label: {
                    Label("Recupera Versione", systemImage: "clock.arrow.circlepath")
                }
                
                // Stampa annotazioni (solo per PDF con firme)
                if item.url.pathExtension.lowercased() == "pdf" && hasSignatureAnnotations(fileURL: item.url) {
                    Button {
                        printSignatureAnnotations(fileURL: item.url)
                    } label: {
                        Label("Stampa Annotazioni", systemImage: "printer.fill")
                    }
                }
                
                Divider()
                
                Button(role: .destructive) {
                    moveToTrash(item)
                } label: {
                    Label("Elimina", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
        }
    }
    
    /// Elimina più elementi selezionati
    private func deleteMultipleItems() {
        guard let sinistroPath = fileService.getSinistroPath(riferimento: sinistro.riferimento ?? "") else { return }
        
        let count = selectedItems.count
        let alert = NSAlert()
        alert.messageText = "Spostare \(count) elementi nel cestino?"
        alert.informativeText = "Gli elementi verranno spostati nel cestino del sinistro e potranno essere recuperati."
        alert.addButton(withTitle: "Sposta nel Cestino")
        alert.addButton(withTitle: "Annulla")
        alert.alertStyle = .informational
        
        if alert.runModal() == .alertFirstButtonReturn {
            for url in selectedItems {
                _ = versioningService.moveToTrash(url, in: sinistroPath)
            }
            selectedItems.removeAll()
            refreshItems()
        }
    }
    
    private func duplicateFile(_ item: FileService.FileItem) {
        let originalURL = item.url
        let directory = originalURL.deletingLastPathComponent()
        let fileName = originalURL.deletingPathExtension().lastPathComponent
        let fileExtension = originalURL.pathExtension
        var newFileName = "\(fileName) copia.\(fileExtension)"
        var counter = 1
        
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(newFileName).path) {
            counter += 1
            newFileName = "\(fileName) copia \(counter).\(fileExtension)"
        }
        
        let newURL = directory.appendingPathComponent(newFileName)
        
        do {
            try FileManager.default.copyItem(at: originalURL, to: newURL)
            refreshItems()
        } catch {
            print("Errore duplicazione file: \(error)")
        }
    }
    
    private func moveToTrash(_ item: FileService.FileItem) {
        guard let sinistroPath = fileService.getSinistroPath(riferimento: sinistro.riferimento ?? "") else {
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Spostare nel cestino?"
        alert.informativeText = "Il file verrà spostato nel cestino del sinistro e potrà essere recuperato."
        alert.addButton(withTitle: "Sposta nel Cestino")
        alert.addButton(withTitle: "Annulla")
        alert.alertStyle = .informational
        
        if alert.runModal() == .alertFirstButtonReturn {
            let success = versioningService.moveToTrash(item.url, in: sinistroPath)
            if success {
                refreshItems()
            }
        }
    }
    
    private func moveFolderToTrash(_ item: FileService.FileItem) {
        guard let sinistroPath = fileService.getSinistroPath(riferimento: sinistro.riferimento ?? "") else {
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Spostare la cartella nel cestino?"
        alert.informativeText = "La cartella e tutto il suo contenuto verranno spostati nel cestino del sinistro e potranno essere recuperati."
        alert.addButton(withTitle: "Sposta nel Cestino")
        alert.addButton(withTitle: "Annulla")
        alert.alertStyle = .informational
        
        if alert.runModal() == .alertFirstButtonReturn {
            let success = versioningService.moveToTrash(item.url, in: sinistroPath)
            if success {
                refreshItems()
            }
        }
    }
    
    /// Converte un singolo file in PDF
    private func convertSingleFileToPDF(_ fileURL: URL) {
        guard fileURL.pathExtension.lowercased() != "pdf" else {
            let alert = NSAlert()
            alert.messageText = "File già PDF"
            alert.informativeText = "Il file selezionato è già un PDF."
            alert.addButton(withTitle: "OK")
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        
        isConvertingToPDF = true
        
        let outputURL = fileURL.deletingPathExtension().appendingPathExtension("pdf")
        closureService.convertFilesToPDF(fileURLs: [fileURL]) { successCount, errors in
            DispatchQueue.main.async {
                self.isConvertingToPDF = false
                
                if successCount > 0 {
                    self.refreshItems()
                    
                    let alert = NSAlert()
                    alert.messageText = "Conversione completata"
                    alert.informativeText = "File convertito in PDF con successo."
                    alert.addButton(withTitle: "OK")
                    alert.alertStyle = .informational
                    alert.runModal()
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Errore conversione"
                    alert.informativeText = errors.isEmpty ? "Impossibile convertire il file." : errors.joined(separator: "\n")
                    alert.addButton(withTitle: "OK")
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    /// Converte i file selezionati in PDF
    private func convertSelectedFilesToPDF() {
        let filesToConvert = selectedFilesOnly
        guard !filesToConvert.isEmpty else { return }
        
        isConvertingToPDF = true
        
        // Se c'è un solo file, usa la conversione normale
        if filesToConvert.count == 1 {
            let file = filesToConvert[0]
            if file.pathExtension.lowercased() == "pdf" {
                let alert = NSAlert()
                alert.messageText = "File già PDF"
                alert.informativeText = "Il file selezionato è già un PDF."
                alert.addButton(withTitle: "OK")
                alert.alertStyle = .informational
                alert.runModal()
                isConvertingToPDF = false
                return
            }
            
            let outputURL = file.deletingPathExtension().appendingPathExtension("pdf")
            closureService.convertFilesToPDF(fileURLs: [file]) { successCount, errors in
                DispatchQueue.main.async {
                    self.isConvertingToPDF = false
                    
                    if successCount > 0 {
                        self.refreshItems()
                        
                        let alert = NSAlert()
                        alert.messageText = "Conversione completata"
                        alert.informativeText = "File convertito in PDF con successo."
                        alert.addButton(withTitle: "OK")
                        alert.alertStyle = .informational
                        alert.runModal()
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "Errore conversione"
                        alert.informativeText = errors.isEmpty ? "Impossibile convertire il file." : errors.joined(separator: "\n")
                        alert.addButton(withTitle: "OK")
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        } else {
            // Più file: crea un unico PDF
            let firstFile = filesToConvert[0]
            let directory = firstFile.deletingLastPathComponent()
            let outputURL = directory.appendingPathComponent("File_Unificati_\(UUID().uuidString.prefix(8)).pdf")
            
            closureService.mergeFilesToSinglePDF(fileURLs: filesToConvert, outputURL: outputURL) { success, errorMessage in
                DispatchQueue.main.async {
                    self.isConvertingToPDF = false
                    
                    if success {
                        self.refreshItems()
                        
                        let alert = NSAlert()
                        alert.messageText = "PDF creato"
                        alert.informativeText = "Creato un unico PDF con \(filesToConvert.count) file, un file per pagina."
                        alert.addButton(withTitle: "OK")
                        alert.alertStyle = .informational
                        alert.runModal()
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "Errore creazione PDF"
                        alert.informativeText = errorMessage ?? "Impossibile creare il PDF unificato."
                        alert.addButton(withTitle: "OK")
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    private func isItemSelected(_ item: FileService.FileItem) -> Bool {
        item.url == selectedItem || selectedItems.contains(item.url)
    }
    
    private func getTagsForItem(_ item: FileService.FileItem) -> Set<FileTagManager.FileTag> {
        fileTagManager.getTagsForFile(at: item.url.path)
    }
    
    @ViewBuilder
    private func fileItemRowView(for item: FileService.FileItem) -> some View {
        FileItemRow(
            item: item,
            isSelected: isItemSelected(item),
            tags: getTagsForItem(item),
            fileStatus: getFileStatus(item),
            onTagButtonTapped: {
                // Il popover è gestito direttamente nel FileItemRow
            }
        )
        .contentShape(Rectangle())
        .tag(item.url)
        .onTapGesture {
            handleSingleClick(item: item)
        }
        .onTapGesture(count: 2) {
            handleDoubleClick(item: item)
        }
        .onDrag {
            createDragProvider(for: item)
        }
        .onDrop(of: [.fileURL, .url], delegate: EnhancedFileDropDelegate(
            item: item,
            draggedItem: $draggedItem,
            draggedItems: $draggedItems,
            fileService: fileService,
            dropTarget: $dropTarget,
            currentPath: path,
            refreshTrigger: refreshTrigger,
            onDrop: { success in
                if success {
                    onFileMoved()
                    refreshItems()
                }
                draggedItem = nil
                draggedItems = []
                dropTarget = nil
            }
        ))
        .background(dropTarget?.id == item.id ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .contextMenu {
            buildContextMenu(for: item)
        }
    }
    
    private func handleDoubleClick(item: FileService.FileItem) {
        if item.isDirectory {
            onItemSelected(item.url)
        } else if !item.isDownloading && !item.isNotDownloaded {
            openFile(item)
        }
    }
    
    private func createDragProvider(for item: FileService.FileItem) -> NSItemProvider {
        // Se l'elemento fa parte di una selezione multipla, trascina tutti
        let urlsToDrag: [URL]
        if selectedItems.count > 1 && selectedItems.contains(item.url) {
            draggedItems = filteredItems.filter { selectedItems.contains($0.url) }
            draggedItem = item
            urlsToDrag = draggedItems.map { $0.url }
        } else {
            draggedItems = [item]
            draggedItem = item
            urlsToDrag = [item.url]
        }
        
        // Per file singolo: usa NSItemProvider standard
        if urlsToDrag.count == 1 {
            let provider = NSItemProvider()
            let fs = fileService // Cattura locale per closure
            provider.registerFileRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier,
                fileOptions: .openInPlace,
                visibility: .all
            ) { completion in
                let url = urlsToDrag[0]
                fs.ensureFileDownloaded(url: url) { ok in
                    if ok {
                        completion(url, false, nil)
                    } else {
                        completion(nil, false, NSError(domain: "PerX.FileDrag", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "File non disponibile"
                        ]))
                    }
                }
                return nil
            }
            return provider
        }
        
        // Per drag multiplo: copia i file in una cartella temporanea e trascina quella
        let provider = NSItemProvider()
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.folder.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            // Crea cartella temporanea per il drag
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("PerX_Drag_\(UUID().uuidString)")
            
            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                // Copia tutti i file nella cartella temporanea
                for url in urlsToDrag {
                    let destURL = tempDir.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.copyItem(at: url, to: destURL)
                }
                
                completion(tempDir, false, nil)
            } catch {
                completion(nil, false, error)
            }
            return nil
        }
        
        // Aggiungi anche i singoli file per Finder che li riconosce
        for url in urlsToDrag {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier,
                visibility: .all
            ) { completion in
                completion(url.dataRepresentation, nil)
                return nil
            }
        }
        
        provider.suggestedName = "\(urlsToDrag.count) elementi"
        
        return provider
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredItems, id: \.url) { item in
                        fileItemRowView(for: item)
                    }
                }
            }
            
            // Overlay per la marquee selection
            if let rect = marqueeSelection {
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .background(Color.accentColor.opacity(0.15))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    let event = NSApp.currentEvent
                    let isCmdPressed = event?.modifierFlags.contains(.command) ?? false
                    let isShiftPressed = event?.modifierFlags.contains(.shift) ?? false
                    
                    // Inizia la selezione marquee solo se non ci sono modificatori
                    if !isCmdPressed && !isShiftPressed {
                        if marqueeStartPoint == nil {
                            marqueeStartPoint = value.startLocation
                            selectedItems.removeAll()
                        }
                        
                        if let start = marqueeStartPoint {
                            let rect = CGRect(
                                x: min(start.x, value.location.x),
                                y: min(start.y, value.location.y),
                                width: abs(value.location.x - start.x),
                                height: abs(value.location.y - start.y)
                            )
                            marqueeSelection = rect
                            
                            let startY = min(start.y, value.location.y)
                            let endY = max(start.y, value.location.y)
                            let rowHeight: CGFloat = 35.0
                            let startIndex = max(0, Int(startY / rowHeight))
                            let endIndex = min(filteredItems.count - 1, Int(endY / rowHeight))
                            
                            if startIndex <= endIndex {
                                let selectedURLs = Set(filteredItems[startIndex...endIndex].map { $0.url })
                                selectedItems = selectedURLs
                                if let first = selectedURLs.first {
                                    onItemSelected(first)
                                }
                            }
                        }
                    }
                }
                .onEnded { _ in
                    marqueeStartPoint = nil
                    marqueeSelection = nil
                }
        )
        // Tasto Canc su macOS: forziamo lo spostamento nel cestino del sinistro (non nel cestino di sistema)
        .onDeleteCommand {
            handleDeleteCommand()
        }
        // Menu contestuale “di sistema” (tasto destro su area vuota / selezione):
        // lo sovrascriviamo per garantire che “Cancella” vada nel cestino interno.
        .contextMenu {
            if !selectedItems.isEmpty || selectedItem != nil {
                Button(role: .destructive) {
                    handleDeleteCommand()
                } label: {
                    let count = selectedItems.count > 0 ? selectedItems.count : 1
                    Label(count > 1 ? "Elimina \(count) elementi" : "Elimina", systemImage: "trash")
                }
            }
        }
        // Drop per file (interni ed esterni) sulla colonna intera (identifica colonna = path)
        .onDrop(of: [.fileURL, .url], delegate: ColumnDropDelegate(
            destinationPath: path,
            draggedItem: $draggedItem,
            draggedItems: $draggedItems,
            fileService: fileService,
            isTargeted: $isDropTargetForExternal
        ) { success in
            if success {
                onFileMoved()
                refreshItems()
            }
            // Pulisci lo stato del drag in ogni caso al termine
            draggedItem = nil
            draggedItems = []
        })
        .overlay {
            if isDropTargetForExternal {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .background(Color.accentColor.opacity(0.05))
                    .padding(4)
            }
        }
        .onChange(of: previewURL) { newURL in
            if let url = newURL {
                MediaViewerWindowManager.shared.openMediaViewer(for: url)
                previewURL = nil
            }
        }
        .quickLookPreview($quickLookURL)
        .popover(isPresented: $showingRenamePopover, attachmentAnchor: .point(.top), arrowEdge: .top) {
            if let item = itemToRename {
                RenamePopover(item: item, sinistro: sinistro) { newName in
                    if let sinistroPath = fileService.getSinistroPath(riferimento: sinistro.riferimento ?? "") {
                        _ = FileVersioningService.shared.createVersion(of: item.url, in: sinistroPath, description: "Rinomina file")
                    }
                    fileService.renameItem(item, to: newName)
                    refreshItems()
                    showingRenamePopover = false
                    itemToRename = nil
                }
            }
        }
        .onChange(of: showingRenamePopover) { isShowing in
            if !isShowing {
                itemToRename = nil
            }
        }
        .sheet(isPresented: $showingVersionRecovery) {
            if let fileURL = fileForVersionRecovery,
               let sinistroPath = fileService.getSinistroPath(riferimento: sinistro.riferimento ?? "") {
                VersionRecoveryView(fileURL: fileURL, sinistroPath: sinistroPath) {
                    refreshItems()
                }
            }
        }
        .sheet(isPresented: $showingCompressionSheet) {
            BatchCompressionSheet(files: filesToCompress)
        }
        .sheet(isPresented: $showingBatchTagSheet) {
            BatchTagSheet(
                files: filesToTag,
                mode: batchTagMode,
                sinistro: sinistro,
                onComplete: {
                    showingBatchTagSheet = false
                    refreshItems()
                }
            )
        }
        .sheet(isPresented: $showingNewFolderSheet) {
            NewFolderView(currentPath: path) { newFolderName in
                fileService.createFolder(at: path, named: newFolderName)
                refreshItems()
            }
        }
        .onAppear {
            // Carica gli elementi in background per non bloccare la UI
            let currentPath = path
            let currentSelectedItem = selectedItem
            Task.detached(priority: .userInitiated) {
                let items = fileService.listContents(inDirectory: currentPath)
                await MainActor.run {
                    self.items = items
                    if let selected = currentSelectedItem {
                        selectedItems = [selected]
                    }
                }
            }
        }
        .onChange(of: path) { _ in
            selectedItems.removeAll()
            // Segna tutti i file come letti quando si esce dalla cartella
            if let riferimento = sinistro.riferimento {
                newFilesTracker.markAllAsRead(riferimento: riferimento)
            }
            refreshItems()
        }
        .onChange(of: selectedItem) { newValue in
            // Sincronizza selectedItem esterno con selectedItems
            if let newValue = newValue {
                if !selectedItems.contains(newValue) {
                    selectedItems = [newValue]
                }
            } else if selectedItems.count == 1 {
                // Se selectedItem è nil e abbiamo solo un elemento selezionato, deseleziona
                selectedItems.removeAll()
            }
        }
        .onChange(of: refreshTrigger) { _ in
            refreshItems()
        }
        .onChange(of: downloadTracker.downloadingFiles) { _ in
            // Aggiorna lo stato di download quando cambia
            refreshItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newFilesDownloaded)) { notification in
            guard let riferimento = notification.userInfo?["riferimento"] as? String,
                  riferimento == sinistro.riferimento else { return }
            // Aggiorna la vista quando arrivano nuovi file
            refreshItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .claimFolderChanged)) { notification in
            guard let riferimento = notification.userInfo?["riferimento"] as? String,
                  riferimento == sinistro.riferimento else { return }
            // Aggiorna la vista quando cambia la cartella
            refreshItems()
        }
        .onChange(of: newFilesTracker.fileStatuses) { _ in
            // Aggiorna la vista quando cambia lo stato dei file nuovi/modificati
            refreshItems()
        }
    }

    private func handleDeleteCommand() {
        // Selezione multipla → stessa logica del menu contestuale (con conferma)
        if selectedItems.count > 1 {
            deleteMultipleItems()
            return
        }
        
        // Selezione singola → sposta nel cestino PerX (con conferma)
        if let selected = selectedItem ?? selectedItems.first,
           let item = filteredItems.first(where: { $0.url == selected }) {
            moveToTrash(item)
        }
    }
    
    private func handleSingleClick(item: FileService.FileItem) {
        // Segna il file come letto se è nuovo o modificato
        markFileAsReadIfNew(item: item)
        
        let event = NSApp.currentEvent
        let isShiftPressed = event?.modifierFlags.contains(.shift) ?? false
        let isCmdPressed = event?.modifierFlags.contains(.command) ?? false
        
        if isCmdPressed {
            // Selezione multipla con Cmd (toggle)
            if selectedItems.contains(item.url) {
                selectedItems.remove(item.url)
                // Se rimuoviamo l'item, notifica il parent con il primo rimanente (se esiste)
                if let first = selectedItems.first {
                    onItemSelected(first)
                }
            } else {
                selectedItems.insert(item.url)
                onItemSelected(item.url)
            }
            if let index = filteredItems.firstIndex(where: { $0.id == item.id }) {
                lastSelectedIndex = index
            }
        } else if isShiftPressed {
            // Selezione range con Shift
            if let lastIndex = lastSelectedIndex,
               let currentIndex = filteredItems.firstIndex(where: { $0.id == item.id }) {
                let startIndex = min(lastIndex, currentIndex)
                let endIndex = max(lastIndex, currentIndex)
                let range = filteredItems[startIndex...endIndex]
                selectedItems.formUnion(range.map { $0.url })
                if let first = range.first {
                    onItemSelected(first.url)
                }
            } else {
                // Se non c'è un indice precedente, seleziona solo questo
                selectedItems = [item.url]
                onItemSelected(item.url)
            }
            if let index = filteredItems.firstIndex(where: { $0.id == item.id }) {
                lastSelectedIndex = index
            }
        } else {
            // Selezione singola
            selectedItems = [item.url]
            lastSelectedIndex = filteredItems.firstIndex(where: { $0.id == item.id })
            onItemSelected(item.url)
        }
    }
    
    
    func refreshItems() {
        // Esegui il refresh in background per non bloccare la UI
        Task {
            let localItems = await Task.detached(priority: .userInitiated) {
                fileService.listContents(inDirectory: path)
            }.value
            
            // Ottieni i file dal manifest per includere quelli non ancora scaricati
            var allItems = localItems
            if let riferimento = sinistro.riferimento,
               let manifestFiles = await claimSync.getManifestFiles(for: riferimento),
               let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) {
                
                // Calcola il path relativo della directory corrente rispetto alla root del sinistro
                let currentRelativePath = getRelativePath(from: sinistroPath, to: path)
                
                // Calcola i path relativi dei file locali
                let localRelativePaths = Set(localItems.map { item in
                    getRelativePath(from: sinistroPath, to: item.url.path)
                })
                
                // Aggiungi i file dal manifest che non sono ancora locali E che appartengono a questa directory
                let workspace = NSWorkspace.shared
                for manifestFile in manifestFiles {
                    // Escludi file di sistema
                    if manifestFile.relativePath.contains("PerX-cache") || 
                       manifestFile.relativePath.contains(".DS_Store") {
                        continue
                    }
                    
                    // Calcola la directory del file nel manifest
                    let fileDir = (manifestFile.relativePath as NSString).deletingLastPathComponent
                    let fileName = (manifestFile.relativePath as NSString).lastPathComponent
                    
                    // Verifica se il file appartiene alla directory corrente
                    // Se currentRelativePath è vuoto (siamo nella root), mostra solo file nella root
                    // Altrimenti mostra solo file nella directory corrente (non nelle sottodirectory)
                    let belongsToCurrentDir: Bool
                    if currentRelativePath.isEmpty {
                        // Siamo nella root: mostra solo file direttamente nella root
                        belongsToCurrentDir = fileDir.isEmpty
                    } else {
                        // Siamo in una sottodirectory: mostra solo file direttamente in questa directory
                        belongsToCurrentDir = fileDir == currentRelativePath
                    }
                    
                    // Se il file non è già nella lista locale E appartiene a questa directory, aggiungilo
                    if !localRelativePaths.contains(manifestFile.relativePath) && belongsToCurrentDir {
                        let fullPath = (sinistroPath as NSString).appendingPathComponent(manifestFile.relativePath)
                        let url = URL(fileURLWithPath: fullPath)
                        let isDownloading = await downloadTracker.isDownloading(relativePath: manifestFile.relativePath)
                        
                        // Crea un FileItem per il file non ancora scaricato
                        let icon = workspace.icon(forFileType: url.pathExtension.isEmpty ? "public.folder" : url.pathExtension)
                        let item = FileService.FileItem(
                            id: fullPath,
                            url: url,
                            isDirectory: false,
                            icon: icon,
                            size: manifestFile.size,
                            modificationDate: manifestFile.modifiedAt ?? Date(),
                            isDownloading: isDownloading,
                            isNotDownloaded: true
                        )
                        allItems.append(item)
                    }
                }
            }
            
            // Aggiorna lo stato di download per i file locali
            await MainActor.run {
                self.items = allItems.map { item in
                    if !item.isNotDownloaded {
                        let relativePath = getRelativePath(from: fileService.getSinistroPath(riferimento: sinistro.riferimento ?? "") ?? path, to: item.url.path)
                        let isDownloading = downloadTracker.isDownloading(relativePath: relativePath)
                        if isDownloading != item.isDownloading {
                            return FileService.FileItem(
                                id: item.id,
                                url: item.url,
                                isDirectory: item.isDirectory,
                                icon: item.icon,
                                size: item.size,
                                modificationDate: item.modificationDate,
                                isDownloading: isDownloading,
                                isNotDownloaded: item.isNotDownloaded
                            )
                        }
                    }
                    return item
                }
            }
        }
    }
    
    /// Calcola il path relativo di un file rispetto alla root del sinistro
    private func getRelativePath(from sinistroPath: String, to fullPath: String) -> String {
        let sinistroURL = URL(fileURLWithPath: sinistroPath).standardizedFileURL
        let fullURL = URL(fileURLWithPath: fullPath).standardizedFileURL
        
        let sinistroPathNormalized = sinistroURL.path
        let fullPathNormalized = fullURL.path
        
        guard fullPathNormalized.hasPrefix(sinistroPathNormalized) else {
            return fullURL.lastPathComponent
        }
        
        let relativePath = String(fullPathNormalized.dropFirst(sinistroPathNormalized.count))
        return relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
    }
    
    private func getPreviousItem(from currentItem: FileService.FileItem) -> FileService.FileItem? {
        guard let currentIndex = filteredItems.firstIndex(where: { $0.id == currentItem.id }) else { return nil }
        return currentIndex > 0 ? filteredItems[currentIndex - 1] : nil
    }
    
    private func getNextItem(from currentItem: FileService.FileItem) -> FileService.FileItem? {
        guard let currentIndex = filteredItems.firstIndex(where: { $0.id == currentItem.id }) else { return nil }
        return currentIndex < filteredItems.count - 1 ? filteredItems[currentIndex + 1] : nil
    }
    
    private func getPreviousColumn() -> URL? {
        return nil
    }
    
    // MARK: - Signature Annotations
    
    private func hasSignatureAnnotations(fileURL: URL) -> Bool {
        guard let document = PDFDocument(url: fileURL) else {
            return false
        }
        
        for i in 0..<document.pageCount {
            if let page = document.page(at: i) {
                let annotations = page.annotations.filter { $0.userName == "PerX_Signature" }
                if !annotations.isEmpty {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func printSignatureAnnotations(fileURL: URL) {
        Task { @MainActor in
            if editorService.printAnnotationsToPDF(at: fileURL) {
                // Ricarica la vista
                refreshItems()
                NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
            }
        }
    }
}

// MARK: - Column Drop Delegate (handles both internal move to column space and external files)

private struct ColumnDropDelegate: DropDelegate {
    let destinationPath: String
    @Binding var draggedItem: FileService.FileItem?
    @Binding var draggedItems: [FileService.FileItem]
    let fileService: FileService
    @Binding var isTargeted: Bool
    let onDrop: (Bool) -> Void
    
    func validateDrop(info: DropInfo) -> Bool {
        // Accetta drag interno o file esterni
        return !draggedItems.isEmpty || draggedItem != nil || !info.itemProviders(for: [.fileURL]).isEmpty
    }
    
    func dropEntered(info: DropInfo) {
        isTargeted = true
    }
    
    func dropExited(info: DropInfo) {
        isTargeted = false
    }
    
    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        
        // 1. Gestione drag interno
        if !draggedItems.isEmpty {
            let sourcePath = draggedItems.first?.url.deletingLastPathComponent().path
            if sourcePath == destinationPath {
                return false
            }
            
            var allSuccess = true
            for dragged in draggedItems {
                if !fileService.moveItem(dragged, to: destinationPath) {
                    allSuccess = false
                }
            }
            onDrop(allSuccess)
            return allSuccess
        } else if let dragged = draggedItem {
            let sourcePath = dragged.url.deletingLastPathComponent().path
            if sourcePath == destinationPath {
                return false
            }
            
            let success = fileService.moveItem(dragged, to: destinationPath)
            onDrop(success)
            return success
        }
        
        // 2. Gestione file esterni
        let providers = info.itemProviders(for: [.fileURL])
        if !providers.isEmpty {
            ExternalFileDropHelpers.importFromProviders(providers, to: destinationPath) { success in
                onDrop(success)
            }
            return true
        }
        
        return false
    }
}
