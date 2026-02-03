import SwiftUI
import CoreData

/// Vista per selezionare file dalla cartella del sinistro per allegare a WhatsApp
/// Supporta navigazione tra sinistri e suggerimenti file
struct WhatsAppFileSelectorView: View {
    let sinistro: Sinistro?
    let onFileSelected: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @StateObject private var fileTagManager = FileTagManager.shared
    private let fileService = FileService.shared
    
    @State private var selectedFile: URL?
    @State private var files: [FileService.FileItem] = []
    @State private var currentSinistro: Sinistro?
    @State private var showingSinistroSelector = false
    @State private var searchText = ""
    @State private var selectedTab: FileTab = .suggested
    @State private var isLoadingFiles = false
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Sinistro.riferimento, ascending: false)],
        predicate: NSPredicate(format: "stato != %@", "Chiuso"),
        animation: .default
    ) private var allSinistri: FetchedResults<Sinistro>
    
    enum FileTab: String, CaseIterable {
        case suggested = "Suggeriti"
        case all = "Tutti i file"
        case other = "Altro sinistro"
    }
    
    private var suggestedFiles: [FileService.FileItem] {
        // File suggeriti: quelli con tag specifici o recenti
        let relevantTags = ["Foto", "Documento", "Perizia", "Preventivo", "Fattura"]
        return files.filter { item in
            let itemTags = fileTagManager.getTagsForFile(at: item.url.path)
            return itemTags.contains { relevantTags.contains($0.name) }
        }
    }
    
    private var filteredFiles: [FileService.FileItem] {
        if searchText.isEmpty { return files }
        return files.filter { $0.url.lastPathComponent.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Sinistro attuale
            if let sinistro = currentSinistro {
                currentSinistroBar(sinistro: sinistro)
            }
            
            // Tab per tipo file
            tabSelector
            
            Divider()
            
            // Contenuto in base al tab
            fileContentView
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 550, height: 500)
        .onAppear {
            currentSinistro = sinistro
            loadFiles()
        }
        .sheet(isPresented: $showingSinistroSelector) {
            SinistroSelectorSheet(
                sinistri: Array(allSinistri),
                onSelect: { selected in
                    currentSinistro = selected
                    loadFiles()
                }
            )
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Seleziona File da Allegare")
                    .font(.headline)
                Text("Scegli dalla cartella del sinistro")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Pulsante sfoglia altre cartelle
            Button {
                openFilePicker()
            } label: {
                Label("Sfoglia...", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Sinistro Bar
    
    private func currentSinistroBar(sinistro: Sinistro) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(sinistro.riferimentoVisualizzato)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let nome = sinistro.nomeAssicurato, !nome.isEmpty {
                    Text(nome)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                showingSinistroSelector = true
            } label: {
                Label("Cambia", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(FileTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                        if tab == .other {
                            showingSinistroSelector = true
                        }
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedTab == tab ? .semibold : .medium)
                            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                        
                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: - File Content
    
    private var fileContentView: some View {
        VStack(spacing: 0) {
            // Barra ricerca
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Cerca file...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
            .padding()
            
            // Lista file
            if isLoadingFiles {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("Caricamento file...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                let displayFiles = selectedTab == .suggested ? suggestedFiles : filteredFiles
                
                if displayFiles.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: selectedTab == .suggested ? "star.slash" : "doc.text.magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text(selectedTab == .suggested ? "Nessun file suggerito" : "Nessun file trovato")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        if selectedTab == .suggested && !files.isEmpty {
                            Button("Mostra tutti i file") {
                                selectedTab = .all
                            }
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                    }
                } else {
                    List(displayFiles, id: \.url, selection: $selectedFile) { item in
                        WhatsAppFileItemRow(item: item, isSelected: selectedFile == item.url)
                            .tag(item.url)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            // Info file selezionato
            if let url = selectedFile {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.accentColor)
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                }
                .frame(maxWidth: 200, alignment: .leading)
            }
            
            Spacer()
            
            Button("Annulla") {
                dismiss()
            }
            .buttonStyle(.bordered)
            
            Button("Allega") {
                if let file = selectedFile {
                    onFileSelected(file)
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedFile == nil)
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func loadFiles() {
        guard let sinistro = currentSinistro,
              let sinistroPath = fileService.getSinistroPath(riferimento: sinistro.riferimento ?? "") else {
            files = []
            return
        }
        
        isLoadingFiles = true
        
        // Carica file in background
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedFiles = fileService.listContents(inDirectory: sinistroPath)
                .filter { !$0.isDirectory }
                .sorted { $0.modificationDate ?? Date.distantPast > $1.modificationDate ?? Date.distantPast }
            
            DispatchQueue.main.async {
                files = loadedFiles
                isLoadingFiles = false
            }
        }
    }
    
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .movie, .audio, .pdf, .data]
        
        if panel.runModal() == .OK, let url = panel.url {
            onFileSelected(url)
            dismiss()
        }
    }
}

// MARK: - WhatsApp File Item Row

private struct WhatsAppFileItemRow: View {
    let item: FileService.FileItem
    let isSelected: Bool
    @StateObject private var fileTagManager = FileTagManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconBackgroundColor)
                    .frame(width: 40, height: 40)
                
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 18))
                        .foregroundColor(iconColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.url.lastPathComponent)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    // Tag
                    let tags = fileTagManager.getTagsForFile(at: item.url.path)
                    if !tags.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(Array(tags.prefix(2)), id: \.id) { tag in
                                Text(tag.name)
                                    .font(.caption2)
                                    .foregroundColor(tag.tagColor)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(tag.tagColor.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            if tags.count > 2 {
                                Text("+\(tags.count - 2)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Data modifica
                    Text(item.modificationDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(item.formattedSize)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    private var iconName: String {
        let ext = item.url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.text.fill"
        case "jpg", "jpeg", "png", "heic", "gif": return "photo.fill"
        case "mp4", "mov", "m4v": return "video.fill"
        case "mp3", "m4a", "wav": return "waveform"
        case "doc", "docx": return "doc.richtext.fill"
        case "xls", "xlsx": return "tablecells.fill"
        default: return "doc.fill"
        }
    }
    
    private var iconColor: Color {
        let ext = item.url.pathExtension.lowercased()
        switch ext {
        case "pdf": return .red
        case "jpg", "jpeg", "png", "heic", "gif": return .blue
        case "mp4", "mov", "m4v": return .purple
        case "mp3", "m4a", "wav": return .orange
        case "doc", "docx": return .blue
        case "xls", "xlsx": return .green
        default: return .gray
        }
    }
    
    private var iconBackgroundColor: Color {
        iconColor.opacity(0.12)
    }
}

// MARK: - Sinistro Selector Sheet

private struct SinistroSelectorSheet: View {
    let sinistri: [Sinistro]
    let onSelect: (Sinistro) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private var filteredSinistri: [Sinistro] {
        if searchText.isEmpty { return sinistri }
        return sinistri.filter { sinistro in
            (sinistro.riferimento ?? "").localizedCaseInsensitiveContains(searchText) ||
            (sinistro.nomeAssicurato ?? "").localizedCaseInsensitiveContains(searchText) ||
            (sinistro.nomeContraente ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Seleziona Sinistro")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Ricerca
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Cerca sinistro...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
            .padding()
            
            // Lista
            List(filteredSinistri, id: \.objectID) { sinistro in
                Button {
                    onSelect(sinistro)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sinistro.riferimentoVisualizzato)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            if let nome = sinistro.nomeAssicurato, !nome.isEmpty {
                                Text(nome)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if let stato = sinistro.stato {
                            Text(stato)
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .cornerRadius(4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .frame(width: 450, height: 400)
    }
}

