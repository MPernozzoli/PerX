import SwiftUI
import PDFKit
import CoreData

struct AttoView: View {
    @ObservedObject var sinistro: Sinistro
    @Binding var perizia: Perizia?
    @Environment(\.managedObjectContext) private var viewContext
    
    @StateObject private var templateManager = AttoTemplateManager.shared
    
    @State private var pdfData: Data?
    @State private var currentTemplate: AttoTemplate?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    @State private var isEditMode = false
    @State private var manualValues: [String: Any] = [:]
    @State private var validationErrors: [String: String] = [:]
    
    @State private var showGenerateConfirmation = false
    @State private var generateResult: AttoGeneratorService.GenerationResult?
    @State private var showResultAlert = false
    
    private let generatorService = AttoGeneratorService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
            
            Divider()
            
            // Content
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let data = pdfData {
                pdfPreview(data: data)
            } else {
                noTemplateView
            }
        }
        .onAppear {
            loadPreview()
        }
        .onChange(of: perizia?.objectID) { _ in
            if !isEditMode {
                loadPreview()
            }
        }
        .alert("Genera Atto", isPresented: $showGenerateConfirmation) {
            Button("Annulla", role: .cancel) { }
            Button("Genera") {
                generateAtto()
            }
        } message: {
            Text("Vuoi generare l'atto definitivo? Il file verrà salvato nella cartella del sinistro.")
        }
        .alert("Risultato", isPresented: $showResultAlert) {
            Button("OK") { }
            if let url = generateResult?.pdfURL {
                Button("Apri nel Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        } message: {
            if let result = generateResult {
                if result.success {
                    Text("Atto generato con successo!")
                } else {
                    Text(result.errorMessage ?? "Errore durante la generazione")
                }
            }
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbar: some View {
        HStack(spacing: 16) {
            // Info template
            if let template = currentTemplate {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.nome)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("\(template.compagnia) • \(template.tipo.displayName) • v\(template.version)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Nessun template disponibile")
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Modalità
            if isEditMode {
                Label("Modalità Modifica", systemImage: "pencil.circle.fill")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(8)
            }
            
            // Pulsanti azione
            if isEditMode {
                Button("Annulla") {
                    exitEditMode()
                }
                .buttonStyle(.bordered)
                
                Button("Genera Versione Manuale") {
                    showGenerateConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentTemplate == nil)
            } else {
                Button {
                    enterEditMode()
                } label: {
                    Label("Modifica", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .disabled(currentTemplate == nil)
                
                Button {
                    showGenerateConfirmation = true
                } label: {
                    Label("Genera", systemImage: "arrow.down.doc.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentTemplate == nil)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Content Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Caricamento anteprima...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Errore")
                .font(.headline)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Riprova") {
                loadPreview()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var noTemplateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("Nessun template disponibile")
                .font(.headline)
            
            Text("Non è stato trovato un template per la compagnia '\(sinistro.nomeCompagnia ?? "N/A")' e tipo '\(determineSottotipo().rawValue)'.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("Configura un template in Impostazioni → Gestione Sinistri → Generazione Atti")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private func pdfPreview(data: Data) -> some View {
        GeometryReader { geometry in
            ZStack {
                // PDF View
                PDFPreviewView(data: data)
                
                // Overlay per editing (se in modalità modifica)
                if isEditMode, let template = currentTemplate {
                    EditOverlayView(
                        template: template,
                        manualValues: $manualValues,
                        validationErrors: $validationErrors,
                        sinistro: sinistro,
                        perizia: perizia,
                        generatorService: generatorService
                    )
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadPreview() {
        isLoading = true
        errorMessage = nil
        
        // Determina compagnia e tipo
        let compagnia = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
        let sottotipo = determineSottotipo()
        let tipo: AttoTipo = sottotipo == .liquidazione ? .liquidazione : .accertamento
        
        // Cerca template
        guard let template = templateManager.getTemplate(forCompagnia: compagnia.rawValue, tipo: tipo) else {
            // Prova anche con il nome compagnia direttamente
            if let template = templateManager.getTemplate(forCompagnia: sinistro.nomeCompagnia ?? "", tipo: tipo) {
                currentTemplate = template
                generatePreview(template: template)
            } else {
                isLoading = false
                currentTemplate = nil
                pdfData = nil
            }
            return
        }
        
        currentTemplate = template
        generatePreview(template: template)
    }
    
    private func generatePreview(template: AttoTemplate) {
        let values = isEditMode ? manualValues : nil
        
        if let data = generatorService.generatePreview(
            sinistro: sinistro,
            perizia: perizia,
            template: template,
            manualValues: values
        ) {
            pdfData = data
            errorMessage = nil
        } else {
            errorMessage = "Impossibile generare l'anteprima"
            pdfData = nil
        }
        
        isLoading = false
    }
    
    private func enterEditMode() {
        // Inizializza manualValues con i valori attuali
        initializeManualValues()
        isEditMode = true
    }
    
    private func exitEditMode() {
        isEditMode = false
        manualValues = [:]
        validationErrors = [:]
        
        // Rigenera anteprima con valori automatici
        if let template = currentTemplate {
            generatePreview(template: template)
        }
    }
    
    private func initializeManualValues() {
        // Inizializza con i valori automatici
        guard let template = currentTemplate else { return }
        
        let sottotipo = determineSottotipo()
        let compagnia = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
        
        // Nome assicurato
        manualValues["nome_assicurato"] = sinistro.nomeAssicurato ?? ""
        manualValues["indirizzo_assicurato"] = sinistro.indirizzoAssicurato ?? ""
        
        // Tick tipo atto
        manualValues["tick_tipo_atto_liquidazione"] = sottotipo == .liquidazione
        manualValues["tick_tipo_atto_accertamento"] = sottotipo == .accertamento
        
        // Importo: sempre calcolato dalla stima del danno
        let importo = generatorService.calculateImporto(sinistro: sinistro, perizia: perizia, sottotipo: sottotipo)
        manualValues["importo_numero"] = importo
        manualValues["importo_lettere"] = TextFitter.numeroInLettere(Decimal(importo))
        
        // Tick riserva/osservazioni
        let hasRiserva = perizia?.hasRiserva ?? false
        manualValues["tick_riserva"] = hasRiserva
        manualValues["tick_osservazioni"] = !hasRiserva
        
        if hasRiserva {
            manualValues["note_riserva_osservazioni"] = perizia?.noteRiserva ?? ""
        } else {
            manualValues["note_riserva_osservazioni"] = perizia?.noteOsservazioni ?? ""
        }
        
        // Relazione
        manualValues["relazione_perizia"] = perizia?.relazionePerizia ?? ""
        manualValues["note_conclusive"] = perizia?.noteConclusive ?? ""
        manualValues["evento_causato_da"] = perizia?.eventoCausatoDa ?? ""
    }
    
    private func generateAtto() {
        guard let template = currentTemplate else { return }
        
        let values = isEditMode ? manualValues : nil
        
        let result = generatorService.generateAndSave(
            sinistro: sinistro,
            perizia: perizia,
            template: template,
            manualValues: values
        )
        
        generateResult = result
        showResultAlert = true
        
        if result.success {
            // Esci dalla modalità modifica se necessario
            if isEditMode {
                exitEditMode()
            }
            
            // Rigenera anteprima
            if let data = result.pdfData {
                pdfData = data
            }
        }
    }
    
    private func determineSottotipo() -> SottotipoAtto {
        return CompagniaService.shared.determinaSottotipoAtto(tipoChiusura: sinistro.definizione)
    }
}

// MARK: - PDF Preview View

struct PDFPreviewView: NSViewRepresentable {
    let data: Data
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor.windowBackgroundColor
        
        if let document = PDFDocument(data: data) {
            pdfView.document = document
        }
        
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        if let document = PDFDocument(data: data) {
            nsView.document = document
        }
    }
}

// MARK: - Edit Overlay View

struct EditOverlayView: View {
    let template: AttoTemplate
    @Binding var manualValues: [String: Any]
    @Binding var validationErrors: [String: String]
    let sinistro: Sinistro
    let perizia: Perizia?
    let generatorService: AttoGeneratorService
    
    var body: some View {
        // Overlay trasparente con campi editabili posizionati
        GeometryReader { geometry in
            ZStack {
                // Lista campi editabili in sidebar
                HStack {
                    Spacer()
                    
                    editPanel
                        .frame(width: 350)
                        .background(Color(NSColor.windowBackgroundColor))
                        .shadow(radius: 5)
                }
            }
        }
    }
    
    private var editPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Modifica Campi")
                .font(.headline)
                .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Checkbox Tipo Atto
                    GroupBox("Tipo Atto") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Liquidazione", isOn: bindingForBool("tick_tipo_atto_liquidazione"))
                                .onChange(of: manualValues["tick_tipo_atto_liquidazione"] as? Bool) { newValue in
                                    if newValue == true {
                                        manualValues["tick_tipo_atto_accertamento"] = false
                                        // Ricalcola importo quando cambia tipo
                                        updateImportoFromStima()
                                    }
                                }
                            
                            Toggle("Accertamento", isOn: bindingForBool("tick_tipo_atto_accertamento"))
                                .onChange(of: manualValues["tick_tipo_atto_accertamento"] as? Bool) { newValue in
                                    if newValue == true {
                                        manualValues["tick_tipo_atto_liquidazione"] = false
                                        // Ricalcola importo quando cambia tipo
                                        updateImportoFromStima()
                                    }
                                }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Checkbox Riserva/Osservazioni
                    GroupBox("Riserva/Osservazioni") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Riserva", isOn: bindingForBool("tick_riserva"))
                                .onChange(of: manualValues["tick_riserva"] as? Bool) { newValue in
                                    if newValue == true {
                                        manualValues["tick_osservazioni"] = false
                                    }
                                }
                            
                            Toggle("Osservazioni", isOn: bindingForBool("tick_osservazioni"))
                                .onChange(of: manualValues["tick_osservazioni"] as? Bool) { newValue in
                                    if newValue == true {
                                        manualValues["tick_riserva"] = false
                                    }
                                }
                            
                            TextField("Note", text: bindingForString("note_riserva_osservazioni"), axis: .vertical)
                                .lineLimit(3...6)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Campi testuali
                    GroupBox("Dati") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Nome Assicurato") {
                                TextField("", text: bindingForString("nome_assicurato"))
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            LabeledContent("Indirizzo") {
                                TextField("", text: bindingForString("indirizzo_assicurato"))
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            LabeledContent("Evento Causato Da") {
                                TextField("", text: bindingForString("evento_causato_da"))
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Importo (solo per atti di accertamento)
                    let isAccertamento = (manualValues["tick_tipo_atto_accertamento"] as? Bool) == true
                    if isAccertamento {
                        GroupBox("Importo") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    LabeledContent("Importo (€)") {
                                        TextField("0.00", text: bindingForImporto("importo_numero"))
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    
                                    Button("Atto a Zero") {
                                        manualValues["importo_numero"] = 0.0
                                        manualValues["importo_lettere"] = TextFitter.numeroInLettere(Decimal(0))
                                    }
                                    .buttonStyle(.bordered)
                                    .help("Imposta l'importo a € 0,00 (solo nell'atto, non nei calcoli)")
                                }
                                
                                Text("L'importo viene calcolato automaticamente dalla stima del danno. Usa 'Atto a Zero' per impostare € 0,00 solo nell'atto.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    // Relazione
                    GroupBox("Relazione") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Relazione Perizia")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: bindingForString("relazione_perizia"))
                                .frame(minHeight: 80)
                                .font(.system(size: 12))
                                .border(Color.gray.opacity(0.3))
                            
                            Text("Note Conclusive")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: bindingForString("note_conclusive"))
                                .frame(minHeight: 60)
                                .font(.system(size: 12))
                                .border(Color.gray.opacity(0.3))
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
        }
    }
    
    private func bindingForImporto(_ key: String) -> Binding<String> {
        Binding(
            get: {
                if let value = manualValues[key] as? Double {
                    return String(format: "%.2f", value)
                } else if let value = manualValues[key] as? NSNumber {
                    return String(format: "%.2f", value.doubleValue)
                }
                return ""
            },
            set: { newValue in
                if let doubleValue = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
                    manualValues[key] = doubleValue
                    // Aggiorna anche importo_lettere
                    manualValues["importo_lettere"] = TextFitter.numeroInLettere(Decimal(doubleValue))
                } else {
                    manualValues[key] = 0.0
                    manualValues["importo_lettere"] = TextFitter.numeroInLettere(Decimal(0))
                }
            }
        )
    }
    
    private func bindingForString(_ key: String) -> Binding<String> {
        Binding(
            get: { manualValues[key] as? String ?? "" },
            set: { manualValues[key] = $0 }
        )
    }
    
    private func bindingForBool(_ key: String) -> Binding<Bool> {
        Binding(
            get: { manualValues[key] as? Bool ?? false },
            set: { manualValues[key] = $0 }
        )
    }
    
    /// Aggiorna l'importo dalla stima del danno
    private func updateImportoFromStima() {
        let sottotipo: SottotipoAtto = (manualValues["tick_tipo_atto_accertamento"] as? Bool) == true ? .accertamento : .liquidazione
        let importo = generatorService.calculateImporto(sinistro: sinistro, perizia: perizia, sottotipo: sottotipo)
        manualValues["importo_numero"] = importo
        manualValues["importo_lettere"] = TextFitter.numeroInLettere(Decimal(importo))
    }
}
