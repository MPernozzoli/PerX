import SwiftUI

struct GenerazioneAttiView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var templateManager = AttoTemplateManager.shared
    @ObservedObject private var cloudService = AttoTemplateCloudService.shared
    
    @State private var selectedTemplate: AttoTemplate?
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var templateToDelete: AttoTemplate?
    @State private var filterCompagnia: String = "Tutte"
    @State private var filterTipo: AttoTipo? = nil
    @State private var selectedTab = 0
    @State private var showUploadSheet = false
    @State private var preselectedPDF: AttoTemplateCloudService.AttoPDFInfo?
    
    private let compagnie = ["Tutte", "Zurich Italia", "Cattolica", "Generali", "Unipol", "HDI", "Allianz", "AXA"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Gestione Template Atti")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if selectedTab == 0 {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Nuovo Template", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        showUploadSheet = true
                    } label: {
                        Label("Carica PDF", systemImage: "arrow.up.doc.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            
            // Tab selector
            Picker("", selection: $selectedTab) {
                Text("Template").tag(0)
                Text("PDF Base").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            Divider()
            
            if selectedTab == 0 {
                // Tab Template
                templateTabContent
            } else {
                // Tab PDF Base
                pdfTabContent
            }
        }
    }
    
    // MARK: - Template Tab
    
    private var templateTabContent: some View {
        VStack(spacing: 0) {
            // Filtri
            HStack(spacing: 16) {
                Picker("Compagnia", selection: $filterCompagnia) {
                    ForEach(compagnie, id: \.self) { compagnia in
                        Text(compagnia).tag(compagnia)
                    }
                }
                .frame(width: 200)
                
                Picker("Tipo", selection: $filterTipo) {
                    Text("Tutti").tag(nil as AttoTipo?)
                    ForEach(AttoTipo.allCases, id: \.self) { tipo in
                        Text(tipo.displayName).tag(tipo as AttoTipo?)
                    }
                }
                .frame(width: 150)
                
                Spacer()
                
                Text("\(filteredTemplates.count) template")
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Lista template
            if filteredTemplates.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("Nessun template trovato")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Clicca su 'Nuovo Template' per crearne uno")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredTemplates) { template in
                        TemplateRowView(
                            template: template,
                            onEdit: {
                                print("[GenerazioneAttiView] Edit template: \(template.nome)")
                                print("[GenerazioneAttiView] Template ha \(template.pages.count) pagine")
                                print("[GenerazioneAttiView] Campi totali: \(template.pages.flatMap { $0.fields }.count)")
                                selectedTemplate = template
                                showingEditor = true
                            },
                            onDelete: {
                                templateToDelete = template
                                showingDeleteConfirmation = true
                            },
                            onDuplicate: {
                                duplicateTemplate(template)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }
    
    // MARK: - PDF Tab
    
    private var pdfTabContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(cloudService.availablePDFs.count) PDF disponibili")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    cloudService.loadAllPDFs()
                } label: {
                    Label("Ricarica", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            if cloudService.availablePDFs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("Nessun PDF disponibile")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Carica un PDF per usarlo come base per i template")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(cloudService.availablePDFs) { pdfInfo in
                        PDFInfoRowView(pdfInfo: pdfInfo, cloudService: cloudService) {
                            preselectedPDF = pdfInfo
                            showingEditor = true
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .sheet(isPresented: $showingEditor) {
            AttoTemplateEditorView(
                pdfs: cloudService.availablePDFs,
                selectedPDF: preselectedPDF?.fileName,
                existingTemplate: selectedTemplate
            )
            .onDisappear {
                preselectedPDF = nil
                selectedTemplate = nil
            }
        }
        .alert("Elimina Template", isPresented: $showingDeleteConfirmation) {
            Button("Annulla", role: .cancel) { }
            Button("Elimina", role: .destructive) {
                if let template = templateToDelete {
                    templateManager.deleteTemplate(id: template.id)
                }
            }
        } message: {
            if let template = templateToDelete {
                Text("Sei sicuro di voler eliminare il template '\(template.nome)'? Questa azione non può essere annullata.")
            }
        }
        .sheet(isPresented: $showUploadSheet) {
            PDFUploadSheet(cloudService: cloudService) {
                showUploadSheet = false
            }
        }
    }
    
    private var filteredTemplates: [AttoTemplate] {
        var templates = templateManager.templates
        
        if filterCompagnia != "Tutte" {
            templates = templates.filter { $0.compagnia == filterCompagnia }
        }
        
        if let tipo = filterTipo {
            templates = templates.filter { $0.tipo == tipo }
        }
        
        return templates.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    private func duplicateTemplate(_ template: AttoTemplate) {
        _ = templateManager.createNewVersion(of: template)
    }
}

// MARK: - Template Row View

struct TemplateRowView: View {
    let template: AttoTemplate
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Icona tipo
            Image(systemName: template.tipo == .liquidazione ? "checkmark.seal.fill" : "doc.text.fill")
                .font(.title2)
                .foregroundColor(template.tipo == .liquidazione ? .green : .blue)
                .frame(width: 40)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(template.nome)
                        .font(.headline)
                    
                    if !template.isActive {
                        Text("INATTIVO")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 12) {
                    Label(template.compagnia, systemImage: "building.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label(template.tipo.displayName, systemImage: "doc.badge.gearshape")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("v\(template.version)", systemImage: "number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Conteggio campi
            VStack(alignment: .trailing) {
                let fieldCount = template.pages.reduce(0) { $0 + $1.fields.count }
                Text("\(fieldCount) campi")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Aggiornato: \(template.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Azioni
            if isHovering {
                HStack(spacing: 8) {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help("Modifica")
                    
                    Button {
                        onDuplicate()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help("Duplica (nuova versione)")
                    
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash.circle")
                            .font(.title3)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Elimina")
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - PDF Info Row View

struct PDFInfoRowView: View {
    let pdfInfo: AttoTemplateCloudService.AttoPDFInfo
    @ObservedObject var cloudService: AttoTemplateCloudService
    let onCreateTemplate: () -> Void
    
    @State private var isHovering = false
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Icona PDF
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundColor(.red)
                .frame(width: 40)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(pdfInfo.displayName)
                        .font(.headline)
                    
                    if pdfInfo.isFromCloud {
                        Image(systemName: "icloud.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else if pdfInfo.uploadedBy == "Sistema" {
                        Text("SISTEMA")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    } else {
                        Text("LOCALE")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 12) {
                    Label(pdfInfo.fileName, systemImage: "doc.text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label(formatFileSize(pdfInfo.fileSize), systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Metadati
            VStack(alignment: .trailing) {
                Text("Caricato da: \(pdfInfo.uploadedBy)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(pdfInfo.uploadedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Azioni (solo per PDF non di sistema)
            if isHovering && pdfInfo.uploadedBy != "Sistema" {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash.circle")
                        .font(.title3)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Elimina")
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button {
                onCreateTemplate()
            } label: {
                Label("Crea Template", systemImage: "doc.badge.plus")
            }
            
            if pdfInfo.uploadedBy != "Sistema" {
                Divider()
                
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Elimina", systemImage: "trash")
                }
            }
        }
        .alert("Elimina PDF", isPresented: $showDeleteConfirmation) {
            Button("Annulla", role: .cancel) { }
            Button("Elimina", role: .destructive) {
                Task {
                    _ = await cloudService.deletePDF(pdfInfo)
                }
            }
        } message: {
            Text("Sei sicuro di voler eliminare '\(pdfInfo.displayName)'? Il file verrà rimosso da iCloud per tutti gli utenti.")
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        FileSizeFormatter.formatKBMB(bytes)
    }
}

// MARK: - PDF Upload Sheet

struct PDFUploadSheet: View {
    @ObservedObject var cloudService: AttoTemplateCloudService
    let onDismiss: () -> Void
    
    @State private var selectedFileURL: URL?
    @State private var displayName: String = ""
    @State private var isUploading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Carica PDF Template")
                .font(.headline)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("File PDF")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    if let url = selectedFileURL {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.red)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    } else {
                        Text("Nessun file selezionato")
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Sfoglia...") {
                        selectPDFFile()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Nome visualizzato")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField("Es: Atto Liquidazione Zurich", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }
            
            if isUploading {
                VStack(spacing: 8) {
                    ProgressView(value: cloudService.uploadProgress)
                    Text("Caricamento in corso...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack {
                Button("Annulla") {
                    onDismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Carica") {
                    uploadFile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFileURL == nil || displayName.isEmpty || isUploading)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
        .alert("Errore", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Caricamento completato", isPresented: $showSuccess) {
            Button("OK") {
                onDismiss()
            }
        } message: {
            Text("Il PDF è stato caricato ed è ora disponibile.")
        }
    }
    
    private func selectPDFFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                selectedFileURL = url
                if displayName.isEmpty {
                    displayName = url.deletingPathExtension().lastPathComponent
                }
            }
        }
    }
    
    private func uploadFile() {
        guard let url = selectedFileURL else { return }
        
        isUploading = true
        
        Task {
            let success = await cloudService.uploadPDF(from: url, displayName: displayName)
            
            await MainActor.run {
                isUploading = false
                
                if success {
                    showSuccess = true
                } else {
                    errorMessage = cloudService.errorMessage ?? "Errore durante il caricamento"
                    showError = true
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    GenerazioneAttiView()
}
