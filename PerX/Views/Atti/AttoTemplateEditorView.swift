import SwiftUI
import PDFKit
import AppKit

struct AttoTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Parametri passati
    let initialPDFs: [AttoTemplateCloudService.AttoPDFInfo]
    let initialSelectedPDF: String?
    let existingTemplate: AttoTemplate?
    
    // State
    @State private var templateId: String?
    @State private var selectedPDFName: String = ""
    @State private var selectedCompagnia: String = ""
    @State private var selectedTipo: AttoTipo = .liquidazione
    @State private var templateName: String = ""
    @State private var pdfDocument: PDFDocument?
    @State private var currentPageIndex: Int = 0
    @State private var fields: [[AttoFieldTemplate]] = []
    
    @State private var editingField: AttoFieldTemplate?
    @State private var showFieldEditor = false
    
    @State private var isDrawing = false
    @State private var drawStartPoint: CGPoint = .zero
    @State private var currentDrawRect: CGRect = .zero
    
    @State private var showSaveConfirmation = false
    @State private var saveMessage = ""
    
    // Per drag & resize
    @State private var selectedFieldId: String?
    @State private var isDraggingField = false
    @State private var isResizingField = false
    @State private var dragOffset: CGSize = .zero
    
    // Flag per caricare template esistente
    @State private var needsLoadExistingTemplate = false
    
    private let compagnie = ["Zurich Italia", "Cattolica", "Generali", "Unipol", "HDI", "Allianz", "AXA"]
    private let templateManager = AttoTemplateManager.shared
    
    var isEditMode: Bool { existingTemplate != nil }
    
    init(pdfs: [AttoTemplateCloudService.AttoPDFInfo], selectedPDF: String? = nil, existingTemplate: AttoTemplate? = nil) {
        self.initialPDFs = pdfs
        self.initialSelectedPDF = selectedPDF
        self.existingTemplate = existingTemplate
        
        // Inizializza @State con valori del template esistente
        if let template = existingTemplate {
            _templateId = State(initialValue: template.id)
            _templateName = State(initialValue: template.nome)
            _selectedCompagnia = State(initialValue: template.compagnia)
            _selectedTipo = State(initialValue: template.tipo)
            _selectedPDFName = State(initialValue: template.pdfFileName)
            _needsLoadExistingTemplate = State(initialValue: true)
            
            print("[AttoTemplateEditorView.init] Template esistente: \(template.nome)")
            print("[AttoTemplateEditorView.init] Pages: \(template.pages.count)")
            print("[AttoTemplateEditorView.init] Campi totali: \(template.pages.flatMap { $0.fields }.count)")
        } else if let preselected = selectedPDF {
            _selectedPDFName = State(initialValue: preselected)
        }
    }
    
    var body: some View {
        HSplitView {
            leftPanel
                .frame(minWidth: 280, maxWidth: 320)
            
            centerPanel
                .frame(minWidth: 500)
            
            rightPanel
                .frame(minWidth: 280, maxWidth: 350)
        }
        .frame(minWidth: 1200, minHeight: 700)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Salva Template") {
                    saveTemplate()
                }
                .disabled(selectedPDFName.isEmpty || selectedCompagnia.isEmpty || templateName.isEmpty)
            }
            
            ToolbarItem(placement: .automatic) {
                Button("Chiudi") {
                    dismiss()
                }
            }
        }
        .onAppear {
            if needsLoadExistingTemplate, let template = existingTemplate {
                // Carica PDF e campi del template esistente
                loadExistingTemplateFields(template)
                needsLoadExistingTemplate = false
            } else if !selectedPDFName.isEmpty && pdfDocument == nil {
                loadPDF()
            }
        }
        .alert("Template Salvato", isPresented: $showSaveConfirmation) {
            Button("OK") { dismiss() }
        } message: {
            Text(saveMessage)
        }
        .sheet(isPresented: $showFieldEditor) {
            if let field = editingField {
                FieldEditorSheet(
                    field: field,
                    onSave: { updatedField in
                        updateField(updatedField)
                        showFieldEditor = false
                    },
                    onCancel: {
                        showFieldEditor = false
                    }
                )
            }
        }
    }
    
    // MARK: - Left Panel
    
    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Configurazione Template")
                .font(.headline)
                .padding()
            
            Divider()
            
            Form {
                Section("PDF Base (\(initialPDFs.count) disponibili)") {
                    Picker("Seleziona PDF", selection: $selectedPDFName) {
                        Text("-- Seleziona --").tag("")
                        ForEach(initialPDFs, id: \.fileName) { pdf in
                            Text(pdf.displayName).tag(pdf.fileName)
                        }
                    }
                    .onChange(of: selectedPDFName) { newValue in
                        if !newValue.isEmpty {
                            loadPDF()
                        }
                    }
                }
                
                Section("Dati Template") {
                    TextField("Nome Template", text: $templateName)
                    
                    Picker("Compagnia", selection: $selectedCompagnia) {
                        Text("-- Seleziona --").tag("")
                        ForEach(compagnie, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                    
                    Picker("Tipo Atto", selection: $selectedTipo) {
                        ForEach(AttoTipo.allCases, id: \.self) { tipo in
                            Text(tipo.displayName).tag(tipo)
                        }
                    }
                }
                
                if let doc = pdfDocument, doc.pageCount > 1 {
                    Section("Navigazione Pagine") {
                        HStack {
                            Button(action: { currentPageIndex = max(0, currentPageIndex - 1) }) {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(currentPageIndex == 0)
                            
                            Spacer()
                            Text("Pagina \(currentPageIndex + 1) / \(doc.pageCount)")
                            Spacer()
                            
                            Button(action: { currentPageIndex = min(doc.pageCount - 1, currentPageIndex + 1) }) {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(currentPageIndex >= doc.pageCount - 1)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            
            Spacer()
            
            // Istruzioni
            GroupBox("Istruzioni") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Seleziona un PDF", systemImage: "1.circle")
                    Label("Clicca e trascina per creare box", systemImage: "2.circle")
                    Label("Doppio click per modificare", systemImage: "3.circle")
                    Label("Salva quando finito", systemImage: "4.circle")
                }
                .font(.caption)
            }
            .padding()
        }
    }
    
    // MARK: - Center Panel
    
    private var centerPanel: some View {
        Group {
            if pdfDocument != nil {
                PDFEditorView(
                    pdfDocument: $pdfDocument,
                    pageIndex: currentPageIndex,
                    fields: fieldsForCurrentPage,
                    isDrawing: $isDrawing,
                    drawStartPoint: $drawStartPoint,
                    currentDrawRect: $currentDrawRect,
                    onFieldCreated: { rect in
                        addField(at: rect)
                    },
                    onFieldSelected: { field in
                        editingField = field
                        showFieldEditor = true
                    },
                    onFieldDeleted: { field in
                        deleteField(field)
                    },
                    onFieldMoved: { field, newRect in
                        moveField(field, to: newRect)
                    },
                    onFieldResized: { field, newRect in
                        resizeField(field, to: newRect)
                    }
                )
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("Seleziona un PDF per iniziare")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    if initialPDFs.isEmpty {
                        Text("Nessun PDF disponibile. Carica un PDF dalla sezione PDF Base.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    }
    
    // MARK: - Right Panel
    
    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Campi Mappati")
                    .font(.headline)
                Spacer()
                Text("\(fieldsForCurrentPage.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            
            Divider()
            
            if fieldsForCurrentPage.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("Nessun campo")
                        .foregroundColor(.secondary)
                    
                    Text("Traccia un rettangolo sul PDF")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(fieldsForCurrentPage) { field in
                        FieldRowView(field: field) {
                            editingField = field
                            showFieldEditor = true
                        } onDelete: {
                            deleteField(field)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    // MARK: - Computed
    
    private var fieldsForCurrentPage: [AttoFieldTemplate] {
        guard currentPageIndex < fields.count else { return [] }
        return fields[currentPageIndex]
    }
    
    // MARK: - Actions
    
    private func loadPDF() {
        guard !selectedPDFName.isEmpty else { return }
        
        guard let url = AttoTemplateCloudService.shared.getPDFURL(forFileName: selectedPDFName) else {
            print("[AttoTemplateEditorView] PDF non trovato: \(selectedPDFName)")
            return
        }
        
        if let doc = PDFDocument(url: url) {
            pdfDocument = doc
            fields = (0..<doc.pageCount).map { _ in [] }
            currentPageIndex = 0
            print("[AttoTemplateEditorView] PDF caricato: \(selectedPDFName), \(doc.pageCount) pagine")
        }
    }
    
    private func addField(at rect: CGRect) {
        guard currentPageIndex < fields.count else { return }
        
        let newField = AttoFieldTemplate(
            id: UUID().uuidString,
            name: "campo_\(fields[currentPageIndex].count + 1)",
            rect: CodableRect(from: rect),
            type: .text,
            isRequired: false,
            alignment: .left,
            maxLines: 1,      // Default: 1 riga
            fontSize: 10      // Default: 10pt
        )
        
        fields[currentPageIndex].append(newField)
        editingField = newField
        showFieldEditor = true
    }
    
    private func updateField(_ updatedField: AttoFieldTemplate) {
        guard currentPageIndex < fields.count else { return }
        
        if let index = fields[currentPageIndex].firstIndex(where: { $0.id == updatedField.id }) {
            fields[currentPageIndex][index] = updatedField
        }
    }
    
    private func deleteField(_ field: AttoFieldTemplate) {
        guard currentPageIndex < fields.count else { return }
        fields[currentPageIndex].removeAll { $0.id == field.id }
    }
    
    private func moveField(_ field: AttoFieldTemplate, to newRect: CGRect) {
        guard currentPageIndex < fields.count else { return }
        
        if let index = fields[currentPageIndex].firstIndex(where: { $0.id == field.id }) {
            var updated = fields[currentPageIndex][index]
            updated.rect = CodableRect(from: newRect)
            fields[currentPageIndex][index] = updated
        }
    }
    
    private func resizeField(_ field: AttoFieldTemplate, to newRect: CGRect) {
        guard currentPageIndex < fields.count else { return }
        
        if let index = fields[currentPageIndex].firstIndex(where: { $0.id == field.id }) {
            var updated = fields[currentPageIndex][index]
            updated.rect = CodableRect(from: newRect)
            fields[currentPageIndex][index] = updated
        }
    }
    
    private func saveTemplate() {
        // Filtra solo pagine con campi
        let pages = fields.enumerated().compactMap { index, pageFields -> AttoPageTemplate? in
            guard !pageFields.isEmpty else { return nil }
            return AttoPageTemplate(
                id: UUID().uuidString,
                pageNumber: index,
                fields: pageFields
            )
        }
        
        let totalFields = pages.flatMap { $0.fields }.count
        print("[AttoTemplateEditorView] Salvataggio template con \(pages.count) pagine e \(totalFields) campi")
        
        if let existingId = templateId, let existing = existingTemplate {
            // Aggiorna template esistente
            let template = AttoTemplate(
                id: existingId,
                nome: templateName,
                compagnia: selectedCompagnia,
                tipo: selectedTipo,
                version: existing.version,
                pdfFileName: selectedPDFName,
                pages: pages,
                createdAt: existing.createdAt,
                updatedAt: Date(),
                isActive: true
            )
            templateManager.updateTemplate(template)
            saveMessage = "Template '\(templateName)' aggiornato!"
        } else {
            // Crea nuovo template
            let template = AttoTemplate(
                id: UUID().uuidString,
                nome: templateName,
                compagnia: selectedCompagnia,
                tipo: selectedTipo,
                version: 1,
                pdfFileName: selectedPDFName,
                pages: pages,
                createdAt: Date(),
                updatedAt: Date(),
                isActive: true
            )
            templateManager.addTemplate(template)
            saveMessage = "Template '\(templateName)' creato!"
        }
        showSaveConfirmation = true
    }
    
    private func loadExistingTemplateFields(_ template: AttoTemplate) {
        print("[AttoTemplateEditorView] Caricamento campi template: \(template.nome)")
        print("[AttoTemplateEditorView] Template ha \(template.pages.count) pagine")
        for page in template.pages {
            print("[AttoTemplateEditorView] Pagina \(page.pageNumber): \(page.fields.count) campi")
        }
        
        // Carica il PDF
        if let url = AttoTemplateCloudService.shared.getPDFURL(forFileName: template.pdfFileName),
           let doc = PDFDocument(url: url) {
            pdfDocument = doc
            print("[AttoTemplateEditorView] PDF caricato: \(doc.pageCount) pagine")
            
            // Carica i campi per ogni pagina
            // Inizializza array con pagine vuote per ogni pagina del PDF
            var loadedFields: [[AttoFieldTemplate]] = Array(repeating: [], count: doc.pageCount)
            
            // Popola con i campi del template
            for page in template.pages {
                if page.pageNumber < doc.pageCount {
                    loadedFields[page.pageNumber] = page.fields
                    print("[AttoTemplateEditorView] Caricati \(page.fields.count) campi per pagina \(page.pageNumber)")
                }
            }
            
            fields = loadedFields
            currentPageIndex = 0
            
            let totalFields = fields.flatMap { $0 }.count
            print("[AttoTemplateEditorView] Campi caricati: \(totalFields) totali")
        } else {
            print("[AttoTemplateEditorView] ERRORE: PDF non trovato per \(template.pdfFileName)")
        }
    }
}

// MARK: - Field Row View

struct FieldRowView: View {
    let field: AttoFieldTemplate
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text(field.type.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                    
                    if field.isRequired {
                        Text("Obbligatorio")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
            
            Button(action: onEdit) {
                Image(systemName: "pencil.circle")
            }
            .buttonStyle(.plain)
            
            Button(action: onDelete) {
                Image(systemName: "trash.circle")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Non-Interactive PDF View

class NonInteractivePDFView: PDFView {
    // Ignora tutti gli eventi del mouse per evitare selezione testo
    override func mouseDown(with event: NSEvent) { }
    override func mouseDragged(with event: NSEvent) { }
    override func mouseUp(with event: NSEvent) { }
    override func rightMouseDown(with event: NSEvent) { }
    override var acceptsFirstResponder: Bool { false }
}

// MARK: - PDF Editor View (con overlay SwiftUI)

struct PDFEditorView: View {
    @Binding var pdfDocument: PDFDocument?
    let pageIndex: Int
    let fields: [AttoFieldTemplate]
    @Binding var isDrawing: Bool
    @Binding var drawStartPoint: CGPoint
    @Binding var currentDrawRect: CGRect
    
    let onFieldCreated: (CGRect) -> Void
    let onFieldSelected: (AttoFieldTemplate) -> Void
    let onFieldDeleted: (AttoFieldTemplate) -> Void
    let onFieldMoved: (AttoFieldTemplate, CGRect) -> Void
    let onFieldResized: (AttoFieldTemplate, CGRect) -> Void
    
    @State private var zoomLevel: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var isPanning: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar zoom
            HStack {
                Button(action: { zoomLevel = max(0.5, zoomLevel - 0.25) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                
                Text("\(Int(zoomLevel * 100))%")
                    .frame(width: 50)
                
                Button(action: { zoomLevel = min(3.0, zoomLevel + 0.25) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                
                Button(action: { zoomLevel = 1.0; panOffset = .zero }) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .help("Reset zoom")
                
                Spacer()
                
                Toggle(isOn: $isPanning) {
                    Label("Pan", systemImage: "hand.draw")
                }
                .toggleStyle(.button)
                .help("Attiva modalità pan (trascina per spostare)")
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // PDF con overlay
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    ZStack {
                        // Contenitore zoomabile
                        PDFWithFieldsOverlay(
                            pdfDocument: pdfDocument,
                            pageIndex: pageIndex,
                            fields: fields,
                            isPanning: isPanning,
                            onFieldCreated: onFieldCreated,
                            onFieldSelected: onFieldSelected,
                            onFieldDeleted: onFieldDeleted,
                            onFieldMoved: onFieldMoved,
                            onFieldResized: onFieldResized
                        )
                        .frame(
                            width: geometry.size.width * zoomLevel,
                            height: geometry.size.height * zoomLevel
                        )
                    }
                }
            }
        }
    }
}

// MARK: - PDF With Fields Overlay (NSViewRepresentable combinato)

struct PDFWithFieldsOverlay: NSViewRepresentable {
    let pdfDocument: PDFDocument?
    let pageIndex: Int
    let fields: [AttoFieldTemplate]
    let isPanning: Bool
    
    let onFieldCreated: (CGRect) -> Void
    let onFieldSelected: (AttoFieldTemplate) -> Void
    let onFieldDeleted: (AttoFieldTemplate) -> Void
    let onFieldMoved: (AttoFieldTemplate, CGRect) -> Void
    let onFieldResized: (AttoFieldTemplate, CGRect) -> Void
    
    func makeNSView(context: Context) -> PDFEditorContainerView {
        let view = PDFEditorContainerView()
        view.coordinator = context.coordinator
        return view
    }
    
    func updateNSView(_ nsView: PDFEditorContainerView, context: Context) {
        nsView.pdfDocument = pdfDocument
        nsView.pageIndex = pageIndex
        nsView.fields = fields
        nsView.isPanning = isPanning
        nsView.coordinator = context.coordinator
        nsView.refresh()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator {
        var parent: PDFWithFieldsOverlay
        
        init(_ parent: PDFWithFieldsOverlay) {
            self.parent = parent
        }
        
        func fieldCreated(_ rect: CGRect) {
            parent.onFieldCreated(rect)
        }
        
        func fieldSelected(_ field: AttoFieldTemplate) {
            parent.onFieldSelected(field)
        }
        
        func fieldDeleted(_ field: AttoFieldTemplate) {
            parent.onFieldDeleted(field)
        }
        
        func fieldMoved(_ field: AttoFieldTemplate, to rect: CGRect) {
            parent.onFieldMoved(field, rect)
        }
        
        func fieldResized(_ field: AttoFieldTemplate, to rect: CGRect) {
            parent.onFieldResized(field, rect)
        }
    }
}

// MARK: - Container View che contiene PDF e Overlay

class PDFEditorContainerView: NSView {
    var pdfDocument: PDFDocument?
    var pageIndex: Int = 0
    var fields: [AttoFieldTemplate] = []
    var isPanning: Bool = false
    weak var coordinator: PDFWithFieldsOverlay.Coordinator?
    
    private var pdfView: PDFView!
    private var overlayView: DrawingOverlayView!
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        wantsLayer = true
        
        // PDF View (sotto) - solo visualizzazione
        pdfView = NonInteractivePDFView(frame: bounds)
        pdfView.autoresizingMask = [.width, .height]
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.backgroundColor = NSColor.windowBackgroundColor
        addSubview(pdfView)
        
        // Overlay View (sopra, per disegno)
        overlayView = DrawingOverlayView(frame: bounds)
        overlayView.autoresizingMask = [.width, .height]
        overlayView.containerView = self
        addSubview(overlayView)
    }
    
    override func layout() {
        super.layout()
        pdfView.frame = bounds
        overlayView.frame = bounds
    }
    
    func refresh() {
        pdfView.document = pdfDocument
        if let doc = pdfDocument, pageIndex < doc.pageCount, let page = doc.page(at: pageIndex) {
            pdfView.go(to: page)
        }
        overlayView.fields = fields
        overlayView.isPanning = isPanning
        overlayView.needsDisplay = true
    }
    
    func getPDFPageBounds() -> CGRect? {
        guard let page = pdfDocument?.page(at: pageIndex) else { return nil }
        return page.bounds(for: .mediaBox)
    }
    
    /// Ottiene la scala e l'offset correnti del PDFView per la conversione coordinate
    func getPDFTransform() -> (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat)? {
        guard let page = pdfDocument?.page(at: pageIndex) else { return nil }
        
        let pageBounds = page.bounds(for: .mediaBox)
        let scaleFactor = pdfView.scaleFactor
        
        // Il PDFView centra la pagina nella view
        let scaledWidth = pageBounds.width * scaleFactor
        let scaledHeight = pageBounds.height * scaleFactor
        
        let offsetX = (bounds.width - scaledWidth) / 2
        let offsetY = (bounds.height - scaledHeight) / 2
        
        return (scaleFactor, offsetX, offsetY)
    }
    
    func fieldCreated(_ rect: CGRect) {
        coordinator?.fieldCreated(rect)
    }
    
    func fieldSelected(_ field: AttoFieldTemplate) {
        coordinator?.fieldSelected(field)
    }
    
    func fieldDeleted(_ field: AttoFieldTemplate) {
        coordinator?.fieldDeleted(field)
    }
    
    func fieldMoved(_ field: AttoFieldTemplate, to rect: CGRect) {
        coordinator?.fieldMoved(field, to: rect)
    }
    
    func fieldResized(_ field: AttoFieldTemplate, to rect: CGRect) {
        coordinator?.fieldResized(field, to: rect)
    }
}

// MARK: - Drawing Overlay View

class DrawingOverlayView: NSView {
    weak var containerView: PDFEditorContainerView?
    var fields: [AttoFieldTemplate] = []
    var isPanning: Bool = false
    
    // Stato per disegno nuovi campi
    private var isDrawing = false
    private var drawStartPoint: CGPoint = .zero
    private var currentRect: CGRect = .zero
    
    // Stato per drag & resize
    private var selectedField: AttoFieldTemplate?
    private var isDragging = false
    private var isResizing = false
    private var resizeHandle: ResizeHandle = .none
    private var dragStartPoint: CGPoint = .zero
    private var originalFieldRect: CGRect = .zero
    
    private let handleSize: CGFloat = 8
    
    enum ResizeHandle {
        case none, topLeft, topRight, bottomLeft, bottomRight
    }
    
    override var isFlipped: Bool { true }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Sfondo trasparente
        NSColor.clear.setFill()
        bounds.fill()
        
        // Disegna i campi esistenti
        for field in fields {
            let rect = convertToViewCoordinates(field.rect.cgRect)
            let isSelected = selectedField?.id == field.id
            
            // Sfondo semitrasparente
            let fillColor = isSelected ? NSColor.systemOrange.withAlphaComponent(0.3) : NSColor.systemBlue.withAlphaComponent(0.2)
            context.setFillColor(fillColor.cgColor)
            context.fill(rect)
            
            // Bordo
            let strokeColor = isSelected ? NSColor.systemOrange : NSColor.systemBlue
            context.setStrokeColor(strokeColor.cgColor)
            context.setLineWidth(isSelected ? 3 : 2)
            context.stroke(rect)
            
            // Nome del campo con sfondo
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 10),
                .foregroundColor: NSColor.white
            ]
            let text = field.name as NSString
            let textSize = text.size(withAttributes: attrs)
            
            // Background del label
            let labelRect = CGRect(x: rect.minX, y: rect.minY, width: textSize.width + 8, height: textSize.height + 4)
            context.setFillColor(strokeColor.cgColor)
            context.fill(labelRect)
            
            // Testo
            text.draw(at: CGPoint(x: rect.minX + 4, y: rect.minY + 2), withAttributes: attrs)
            
            // Disegna maniglie di resize se selezionato
            if isSelected {
                let handles = getResizeHandles(for: rect)
                context.setFillColor(NSColor.white.cgColor)
                context.setStrokeColor(NSColor.systemOrange.cgColor)
                context.setLineWidth(1)
                
                for handle in handles {
                    context.fillEllipse(in: handle)
                    context.strokeEllipse(in: handle)
                }
            }
        }
        
        // Disegna rettangolo corrente durante il disegno
        if isDrawing && currentRect.width > 5 && currentRect.height > 5 {
            context.setFillColor(NSColor.systemGreen.withAlphaComponent(0.2).cgColor)
            context.fill(currentRect)
            
            context.setStrokeColor(NSColor.systemGreen.cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.stroke(currentRect)
        }
    }
    
    private func convertToViewCoordinates(_ pdfRect: CGRect) -> CGRect {
        guard let pageBounds = containerView?.getPDFPageBounds(),
              let transform = containerView?.getPDFTransform() else { return pdfRect }
        
        let scale = transform.scale
        let offsetX = transform.offsetX
        let offsetY = transform.offsetY
        
        // Coordinate flipped (PDF ha origine in basso, view in alto)
        let flippedY = pageBounds.height - pdfRect.maxY
        
        return CGRect(
            x: pdfRect.minX * scale + offsetX,
            y: flippedY * scale + offsetY,
            width: pdfRect.width * scale,
            height: pdfRect.height * scale
        )
    }
    
    private func convertToPDFCoordinates(_ viewPoint: CGPoint) -> CGPoint {
        guard let pageBounds = containerView?.getPDFPageBounds(),
              let transform = containerView?.getPDFTransform() else { return viewPoint }
        
        let scale = transform.scale
        let offsetX = transform.offsetX
        let offsetY = transform.offsetY
        
        let pdfX = (viewPoint.x - offsetX) / scale
        let pdfY = pageBounds.height - ((viewPoint.y - offsetY) / scale)
        
        return CGPoint(x: pdfX, y: pdfY)
    }
    
    private func getResizeHandles(for rect: CGRect) -> [CGRect] {
        let hs = handleSize
        return [
            CGRect(x: rect.minX - hs/2, y: rect.minY - hs/2, width: hs, height: hs), // topLeft
            CGRect(x: rect.maxX - hs/2, y: rect.minY - hs/2, width: hs, height: hs), // topRight
            CGRect(x: rect.minX - hs/2, y: rect.maxY - hs/2, width: hs, height: hs), // bottomLeft
            CGRect(x: rect.maxX - hs/2, y: rect.maxY - hs/2, width: hs, height: hs)  // bottomRight
        ]
    }
    
    private func hitTestResizeHandle(at point: CGPoint, for rect: CGRect) -> ResizeHandle {
        let handles = getResizeHandles(for: rect)
        if handles[0].contains(point) { return .topLeft }
        if handles[1].contains(point) { return .topRight }
        if handles[2].contains(point) { return .bottomLeft }
        if handles[3].contains(point) { return .bottomRight }
        return .none
    }
    
    override func mouseDown(with event: NSEvent) {
        if isPanning { return }
        
        let point = convert(event.locationInWindow, from: nil)
        
        // Prima controlla se clicchiamo su una maniglia di resize
        if let selected = selectedField {
            let rect = convertToViewCoordinates(selected.rect.cgRect)
            let handle = hitTestResizeHandle(at: point, for: rect)
            if handle != .none {
                isResizing = true
                resizeHandle = handle
                dragStartPoint = point
                originalFieldRect = rect
                return
            }
        }
        
        // Controlla se click su un campo esistente
        for field in fields {
            let rect = convertToViewCoordinates(field.rect.cgRect)
            if rect.contains(point) {
                if event.clickCount == 2 {
                    // Doppio click = modifica
                    containerView?.fieldSelected(field)
                } else {
                    // Click singolo = seleziona per drag
                    selectedField = field
                    isDragging = true
                    dragStartPoint = point
                    originalFieldRect = rect
                    needsDisplay = true
                }
                return
            }
        }
        
        // Click fuori dai campi = deseleziona e inizia a disegnare
        selectedField = nil
        isDrawing = true
        drawStartPoint = point
        currentRect = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        if isPanning { return }
        
        let point = convert(event.locationInWindow, from: nil)
        
        if isResizing, let field = selectedField {
            // Resize del campo
            let deltaX = point.x - dragStartPoint.x
            let deltaY = point.y - dragStartPoint.y
            
            var newRect = originalFieldRect
            
            switch resizeHandle {
            case .topLeft:
                newRect.origin.x += deltaX
                newRect.origin.y += deltaY
                newRect.size.width -= deltaX
                newRect.size.height -= deltaY
            case .topRight:
                newRect.origin.y += deltaY
                newRect.size.width += deltaX
                newRect.size.height -= deltaY
            case .bottomLeft:
                newRect.origin.x += deltaX
                newRect.size.width -= deltaX
                newRect.size.height += deltaY
            case .bottomRight:
                newRect.size.width += deltaX
                newRect.size.height += deltaY
            case .none:
                break
            }
            
            // Assicura dimensioni minime
            if newRect.width >= 20 && newRect.height >= 10 {
                currentRect = newRect
                needsDisplay = true
            }
            return
        }
        
        if isDragging {
            // Drag del campo
            let deltaX = point.x - dragStartPoint.x
            let deltaY = point.y - dragStartPoint.y
            
            currentRect = CGRect(
                x: originalFieldRect.origin.x + deltaX,
                y: originalFieldRect.origin.y + deltaY,
                width: originalFieldRect.width,
                height: originalFieldRect.height
            )
            needsDisplay = true
            return
        }
        
        if isDrawing {
            currentRect = CGRect(
                x: min(drawStartPoint.x, point.x),
                y: min(drawStartPoint.y, point.y),
                width: abs(point.x - drawStartPoint.x),
                height: abs(point.y - drawStartPoint.y)
            )
            needsDisplay = true
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if isPanning { return }
        
        if isResizing, let field = selectedField, currentRect.width >= 20 && currentRect.height >= 10 {
            // Converti in coordinate PDF e aggiorna
            let pdfStart = convertToPDFCoordinates(CGPoint(x: currentRect.minX, y: currentRect.minY))
            let pdfEnd = convertToPDFCoordinates(CGPoint(x: currentRect.maxX, y: currentRect.maxY))
            
            let pdfRect = CGRect(
                x: min(pdfStart.x, pdfEnd.x),
                y: min(pdfStart.y, pdfEnd.y),
                width: abs(pdfEnd.x - pdfStart.x),
                height: abs(pdfEnd.y - pdfStart.y)
            )
            
            containerView?.fieldResized(field, to: pdfRect)
            isResizing = false
            resizeHandle = .none
            currentRect = .zero
            needsDisplay = true
            return
        }
        
        if isDragging, let field = selectedField {
            // Converti in coordinate PDF e aggiorna
            let pdfStart = convertToPDFCoordinates(CGPoint(x: currentRect.minX, y: currentRect.minY))
            let pdfEnd = convertToPDFCoordinates(CGPoint(x: currentRect.maxX, y: currentRect.maxY))
            
            let pdfRect = CGRect(
                x: min(pdfStart.x, pdfEnd.x),
                y: min(pdfStart.y, pdfEnd.y),
                width: abs(pdfEnd.x - pdfStart.x),
                height: abs(pdfEnd.y - pdfStart.y)
            )
            
            containerView?.fieldMoved(field, to: pdfRect)
            isDragging = false
            currentRect = .zero
            needsDisplay = true
            return
        }
        
        if isDrawing {
            isDrawing = false
            
            if currentRect.width > 20 && currentRect.height > 10 {
                let pdfStart = convertToPDFCoordinates(CGPoint(x: currentRect.minX, y: currentRect.minY))
                let pdfEnd = convertToPDFCoordinates(CGPoint(x: currentRect.maxX, y: currentRect.maxY))
                
                let pdfRect = CGRect(
                    x: min(pdfStart.x, pdfEnd.x),
                    y: min(pdfStart.y, pdfEnd.y),
                    width: abs(pdfEnd.x - pdfStart.x),
                    height: abs(pdfEnd.y - pdfStart.y)
                )
                
                containerView?.fieldCreated(pdfRect)
            }
            
            currentRect = .zero
            needsDisplay = true
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        for field in fields {
            let rect = convertToViewCoordinates(field.rect.cgRect)
            if rect.contains(point) {
                let menu = NSMenu()
                
                let editItem = NSMenuItem(title: "Modifica", action: #selector(editFieldAction(_:)), keyEquivalent: "")
                editItem.representedObject = field
                editItem.target = self
                menu.addItem(editItem)
                
                menu.addItem(NSMenuItem.separator())
                
                let deleteItem = NSMenuItem(title: "Elimina", action: #selector(deleteFieldAction(_:)), keyEquivalent: "")
                deleteItem.representedObject = field
                deleteItem.target = self
                menu.addItem(deleteItem)
                
                NSMenu.popUpContextMenu(menu, with: event, for: self)
                return
            }
        }
    }
    
    @objc private func editFieldAction(_ sender: NSMenuItem) {
        if let field = sender.representedObject as? AttoFieldTemplate {
            containerView?.fieldSelected(field)
        }
    }
    
    @objc private func deleteFieldAction(_ sender: NSMenuItem) {
        if let field = sender.representedObject as? AttoFieldTemplate {
            containerView?.fieldDeleted(field)
        }
    }
    
    // Permetti all'evento di passare se in modalità pan
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isPanning {
            return nil // Passa l'evento alla scroll view
        }
        return super.hitTest(point)
    }
}

// MARK: - Field Editor Sheet

struct FieldEditorSheet: View {
    let field: AttoFieldTemplate
    let onSave: (AttoFieldTemplate) -> Void
    let onCancel: () -> Void
    
    @State private var name: String
    @State private var fieldType: AttoFieldType
    @State private var isRequired: Bool
    @State private var alignment: AttoTextAlignment
    @State private var maxLines: Int?
    @State private var fontSize: Double?
    
    /// Campi filtrati per il tipo selezionato
    private var filteredFieldNames: [AttoFieldName] {
        AttoFieldName.fieldsForType(fieldType)
    }
    
    init(field: AttoFieldTemplate, onSave: @escaping (AttoFieldTemplate) -> Void, onCancel: @escaping () -> Void) {
        self.field = field
        self.onSave = onSave
        self.onCancel = onCancel
        
        _name = State(initialValue: field.name)
        _fieldType = State(initialValue: field.type)
        _isRequired = State(initialValue: field.isRequired)
        _alignment = State(initialValue: field.alignment)
        // Default: maxLines = 1, fontSize = 10 per i testi
        _maxLines = State(initialValue: field.maxLines ?? 1)
        _fontSize = State(initialValue: field.fontSize.map { Double($0) } ?? 10.0)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Configura Campo")
                .font(.headline)
                .padding()
            
            Divider()
            
            Form {
                Section("Identificazione") {
                    TextField("Nome campo", text: $name)
                    
                    Picker("Tipo", selection: $fieldType) {
                        ForEach(AttoFieldType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    
                    Toggle("Obbligatorio", isOn: $isRequired)
                }
                
                if fieldType == .text {
                    Section("Formattazione Testo") {
                        Picker("Allineamento", selection: $alignment) {
                            Text("Sinistra").tag(AttoTextAlignment.left)
                            Text("Centro").tag(AttoTextAlignment.center)
                            Text("Destra").tag(AttoTextAlignment.right)
                        }
                        
                        HStack {
                            Text("Max righe")
                            Spacer()
                            TextField("", value: $maxLines, format: .number)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Text("Font size")
                            Spacer()
                            TextField("", value: $fontSize, format: .number)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                
                Section("Suggerimenti (\(filteredFieldNames.count) per \(fieldType.displayName))") {
                    if filteredFieldNames.isEmpty {
                        Text("Nessun campo suggerito per questo tipo")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                                ForEach(filteredFieldNames, id: \.self) { fieldName in
                                    Button(fieldName.displayName) {
                                        name = fieldName.rawValue
                                        // Imposta automaticamente il tipo corretto
                                        fieldType = fieldName.fieldType
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .frame(maxHeight: 120)
                    }
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            HStack {
                Button("Annulla") { onCancel() }
                    .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Salva") { saveField() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 420, height: 500)
    }
    
    private func saveField() {
        let updated = AttoFieldTemplate(
            id: field.id,
            name: name,
            rect: field.rect,
            type: fieldType,
            isRequired: isRequired,
            alignment: alignment,
            maxLines: maxLines,
            fontSize: fontSize.map { CGFloat($0) }
        )
        onSave(updated)
    }
}
