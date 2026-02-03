import SwiftUI
import CoreData

struct PeriziaDetailView: View {
    @ObservedObject var sinistro: Sinistro
    @Binding var perizia: Perizia?
    @Environment(\.managedObjectContext) private var viewContext
    private let perxiaService = PerxiaService.shared
    
    // ViewModel per osservare lo stato persistente dell'analisi
    @StateObject private var analysisVM: PerxiaAnalysisViewModel
    
    @State private var fulminazione: Bool = false
    @State private var sopralluogo: Bool = false
    @State private var ubicazione: String = ""
    @State private var propensionePerito: String = "Imparziale"
    @State private var includeGiustificativi: Bool = true
    @State private var includeDenuncia: Bool = true
    @State private var fotoSelection: DocumentiSelectorView.FotoSelection = .tutte
    @State private var selectedFoto: Set<URL> = []
    @State private var analisiCorrente: PerxiaAnalisi?
    @State private var isInputExpanded = false
    
    // UI state
    @State private var selectedMisureReport: PerxiaService.ReportMisure? = nil
    @State private var showMisureReport = false
    
    private let propensioneOptions = ["Riconoscere il danno", "Imparziale", "Propensione a respingerlo"]
    
    init(sinistro: Sinistro, perizia: Binding<Perizia?>) {
        self.sinistro = sinistro
        self._perizia = perizia
        self._analysisVM = StateObject(wrappedValue: PerxiaAnalysisViewModel(
            sinistroRiferimento: sinistro.riferimento ?? ""
        ))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header con info sinistro
                headerSection
                
                // Sezione azioni principali (configurazione e avvio analisi)
                actionsSection
                
                // Sezione progresso analisi (usa viewModel)
                if analysisVM.isAnalyzing {
                    progressCard
                }
                
                // Sezione risultati beni (streaming da viewModel)
                if !analysisVM.beni.isEmpty {
                    beniStreamingCard
                } else if let analisi = analysisVM.analisiCompleta, !analisi.beni.isEmpty {
                    beniResultsCard(analisi: analisi)
                }
                
                // Sezione relazione (da viewModel)
                if !analysisVM.relazione.isEmpty {
                    relazioneCard
                }
            }
            .padding(20)
        }
        .task {
            loadInitialValues()
        }
        .sheet(isPresented: $showMisureReport) {
            if let report = selectedMisureReport {
                MisureReportSheet(report: report)
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            // Colonna sinistra: Nome assicurato, indirizzo, tipo
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(sinistro.nomeAssicurato ?? sinistro.nomeContraente ?? "N/A")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // Button configurazione
                    Button {
                        withAnimation {
                            isInputExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help("Configurazione analisi")
                }
                
                // Indirizzo con icona verifica ubicazione
                HStack(spacing: 6) {
                    if !ubicazione.isEmpty {
                        Text(ubicazione)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Icona verifica ubicazione
                    if let analisi = analysisVM.analisiCompleta, let verifica = analisi.verificaUbicazione {
                        Group {
                            switch verifica.corrispondenza {
                            case "confermata":
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            case "parziale", "non_verificabile":
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                            case "discrepanza":
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            default:
                                EmptyView()
                            }
                        }
                        .font(.subheadline)
                    }
                }
                
                // Tipo sinistro e fulminazione
                HStack(spacing: 12) {
                    if sopralluogo {
                        Label("Sopralluogo", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else {
                        Label("Documentale", systemImage: "doc.text.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if fulminazione {
                        Label("Fulminazione", systemImage: "bolt.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            // Colonna destra: Grado complessità e numero beni
            VStack(alignment: .trailing, spacing: 8) {
                if let analisi = analysisVM.analisiCompleta {
                    // Grado complessità
                    let livello = analisi.complessita.livello
                    if !livello.isEmpty {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Grado Complessità")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.heart.fill")
                                    .foregroundColor(.orange)
                                Text(livello.capitalized)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("(\(analisi.complessita.punteggio)/10)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                            )
                        }
                    }
                    
                    // Numero beni
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Beni Analizzati")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(analisi.beni.count)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    // MARK: - Actions Section
    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Configurazione espandibile
            if isInputExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Parametri sinistro
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Fulminazione", isOn: $fulminazione)
                        Toggle("Sopralluogo effettuato", isOn: $sopralluogo)
                        
                        HStack {
                            Text("Ubicazione:")
                                .frame(width: 120, alignment: .leading)
                            TextField("Indirizzo", text: $ubicazione)
                        }
                        
                        HStack {
                            Text("Propensione:")
                                .frame(width: 120, alignment: .leading)
                            Picker("", selection: $propensionePerito) {
                                ForEach(propensioneOptions, id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    
                    Divider()
                    
                    // Documenti
                    DocumentiSelectorView(
                        sinistro: sinistro,
                        includeGiustificativi: $includeGiustificativi,
                        includeDenuncia: $includeDenuncia,
                        fotoSelection: $fotoSelection,
                        selectedFoto: $selectedFoto
                    )
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Pulsante analisi (rimpicciolito)
            HStack {
                Button {
                    avviaAnalisiCompleta()
                } label: {
                    HStack(spacing: 6) {
                        if analysisVM.isAnalyzing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.7)
                            Text("Analisi in corso...")
                                .font(.subheadline)
                        } else {
                            Image(systemName: "sparkles")
                            Text("Avvia Analisi")
                                .font(.subheadline)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canAnalyze || analysisVM.isAnalyzing)
                
                if analysisVM.isAnalyzing {
                    ProgressView(value: analysisVM.progress, total: 1.0)
                        .frame(width: 100)
                        .padding(.leading, 8)
                }
                
                Spacer()
            }
            
            if !analysisVM.currentPhase.isEmpty {
                Text(analysisVM.currentPhase)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Progress Card
    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                Text("Progresso Analisi")
                    .font(.headline)
                Spacer()
                Text("\(Int(analysisVM.progress * 100))%")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Pulsante cancella
                Button {
                    analysisVM.cancelAnalysis()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Annulla analisi")
            }
            
            ProgressView(value: analysisVM.progress, total: 1.0)
                .progressViewStyle(.linear)
            
            if !analysisVM.currentPhase.isEmpty {
                Text(analysisVM.currentPhase)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let state = analysisVM.state, !state.streamOutput.isEmpty {
                ScrollView {
                    Text(state.streamOutput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.textBackgroundColor))
                        )
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    
    // MARK: - Beni Results Card
    private func beniResultsCard(analisi: PerxiaService.AnalisiSinistroCompleta) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "cube.box.fill")
                    .foregroundColor(.blue)
                Text("Beni Analizzati")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            
            if let error = analysisVM.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                )
            }
            
            // Card dei beni
            if !analisi.beni.isEmpty {
                VStack(spacing: 16) {
                    ForEach(Array(analisi.beni.enumerated()), id: \.offset) { index, bene in
                        BeneAnalysisCard(bene: bene)
                    }
                }
            } else {
                Text("Nessun bene analizzato")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Relazione Card
    private var relazioneCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.green)
                Text("Relazione")
                    .font(.headline)
                
                if analysisVM.isAnalyzing && analysisVM.currentPhase.contains("relazione") {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.leading, 4)
                }
                
                Spacer()
            }
            
            if analysisVM.relazione.isEmpty {
                Text("La relazione verrà generata automaticamente durante l'analisi.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                // Relazione in sola lettura durante lo streaming, editabile dopo
                ScrollView {
                    Text(analysisVM.relazione)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minHeight: 200, maxHeight: 400)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                
                if !analysisVM.isAnalyzing {
                    Button {
                        salvaRelazione()
                    } label: {
                        Label("Salva Relazione", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    // MARK: - Helper Functions
    private var canAnalyze: Bool { !ubicazione.isEmpty }
    
    @State private var hasLoadedInitialValues = false
    
    private func loadInitialValues() {
        guard !hasLoadedInitialValues else { return }
        hasLoadedInitialValues = true
        
        fulminazione = sinistro.fulminazione != nil && !sinistro.fulminazione!.isEmpty
        sopralluogo = sinistro.sopralluogo
        ubicazione = sinistro.indirizzoAssicurato ?? sinistro.indirizzoContraente ?? sinistro.indirizzoDanneggiato ?? sinistro.indirizzoAssicurato_legacy ?? ""
        propensionePerito = sinistro.propensionePerito ?? "Imparziale"
        
        // Carica ultima analisi completa se esiste
        if let perxiaSet = sinistro.perxiaAnalisi as? Set<PerxiaAnalisi>,
           let ultimaAnalisi = perxiaSet.sorted(by: { ($0.dataAnalisi ?? Date.distantPast) > ($1.dataAnalisi ?? Date.distantPast) }).first {
            analisiCorrente = ultimaAnalisi
        }
        
        // Carica analisi streaming salvata se disponibile (il viewModel lo fa automaticamente, ma forziamo il caricamento)
        if analysisVM.state == nil, let riferimento = sinistro.riferimento {
            // Forza il caricamento dello stato salvato
            _ = PerxiaAnalysisManager.shared.getState(for: riferimento)
        }
    }
    
    private func avviaAnalisiCompleta() {
        print("[PeriziaDetailView] 🚀 Avvio analisi via Manager per sinistro \(sinistro.riferimento ?? "N/A")")
        
        // Salva propensione
        sinistro.propensionePerito = propensionePerito
        try? viewContext.save()
        
        // Avvia analisi tramite il manager (persistente, continua in background)
        analysisVM.startAnalysis(
            sinistro: sinistro,
            fulminazione: fulminazione,
            sopralluogo: sopralluogo,
            ubicazione: ubicazione
        )
    }
    
    private func salvaRelazione() {
        let relazioneText = analysisVM.relazione
        guard !relazioneText.isEmpty else { return }
        
        if let analisi = analisiCorrente {
            analisi.relazioneComplessiva = relazioneText
            try? viewContext.save()
        } else {
            // Crea nuova analisi se non esiste
            let analisi = PerxiaAnalisi(context: viewContext)
            analisi.id = UUID()
            analisi.dataAnalisi = Date()
            analisi.sinistro = sinistro
            analisi.relazioneComplessiva = relazioneText
            analisiCorrente = analisi
            try? viewContext.save()
        }
    }
    
    // MARK: - Beni Streaming Card
    private var beniStreamingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "cube.box.fill")
                    .foregroundColor(.blue)
                Text("Beni Analizzati")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                
                if analysisVM.isAnalyzing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                
                Text("\(analysisVM.beni.count)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            if let error = analysisVM.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                )
            }
            
            // Card dei beni in streaming
            VStack(spacing: 16) {
                ForEach(analysisVM.beni) { bene in
                    BeneStreamingCard(
                        bene: bene,
                        onMisureTap: { report in
                            selectedMisureReport = report
                            showMisureReport = true
                        },
                        onAnalisiVisivaTap: {
                            // Gestito internamente con sheet
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .animation(.easeInOut, value: analysisVM.beni.count)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
}

// MARK: - Bene Streaming Card (con tracciabilità)
struct BeneStreamingCard: View {
    let bene: PerxiaService.BeneAnalysisStreaming
    let onMisureTap: (PerxiaService.ReportMisure) -> Void
    let onAnalisiVisivaTap: () -> Void
    
    @State private var showAnalisiVisiva = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: Nome bene
            HStack {
                Text(bene.nome)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Badge compatibilità FE
                Text(bene.compatibilitaFE.esito.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(compatibilitaColor.opacity(0.2))
                    )
                    .foregroundColor(compatibilitaColor)
            }
            
            // Dati con confidenza (sempre mostrati)
            HStack(spacing: 16) {
                // Marca
                if let marca = bene.marca, marca.daVisualizzare {
                    DatoConFonte(
                        label: "Marca",
                        valore: marca.valore,
                        confidenza: marca.livelloConfidenza,
                        fontiFoto: marca.fontiFoto
                    )
                } else {
                    DatoConFonte(
                        label: "Marca",
                        valore: "non determinabile",
                        confidenza: .nonDisponibile,
                        fontiFoto: []
                    )
                }
                
                // Modello
                if let modello = bene.modello, modello.daVisualizzare {
                    DatoConFonte(
                        label: "Modello",
                        valore: modello.valore,
                        confidenza: modello.livelloConfidenza,
                        fontiFoto: modello.fontiFoto
                    )
                } else {
                    DatoConFonte(
                        label: "Modello",
                        valore: "non determinabile",
                        confidenza: .nonDisponibile,
                        fontiFoto: []
                    )
                }
                
                // Anno
                if let anno = bene.anno, anno.daVisualizzare {
                    DatoConFonte(
                        label: bene.annoStimato ? "Anno (stima)" : "Anno",
                        valore: anno.valore,
                        confidenza: anno.livelloConfidenza,
                        fontiFoto: anno.fontiFoto
                    )
                } else {
                    DatoConFonte(
                        label: bene.annoStimato ? "Anno (stima)" : "Anno",
                        valore: "non determinabile",
                        confidenza: .nonDisponibile,
                        fontiFoto: []
                    )
                }
            }
            
            Divider()
            
            // Analisi visiva
            if bene.osservazioniVisive.daVisualizzare {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "eye.fill")
                            .foregroundColor(.blue)
                        Text("Analisi Visiva")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        ConfidenzaBadge(livello: bene.osservazioniVisive.livelloConfidenza)
                        
                        Spacer()
                        
                        Button {
                            showAnalisiVisiva = true
                        } label: {
                            Label("Dettagli", systemImage: "chevron.right")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                    }
                    
                    // Sintesi breve (prima frase o prime righe)
                    let sintesi = sintesiAnalisiVisiva(bene.osservazioniVisive.valore)
                    Text(sintesi)
                        .font(.body)
                        .lineLimit(3)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.05))
                )
                .sheet(isPresented: $showAnalisiVisiva) {
                    AnalisiVisivaSheet(bene: bene)
                }
            }
            
            // Test strumentali
            if let report = bene.reportMisure {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "gauge.high")
                            .foregroundColor(.purple)
                        Text("Test Strumentali")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Button {
                            onMisureTap(report)
                        } label: {
                            Label("Dettagli", systemImage: "chevron.right")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.purple)
                    }
                    
                    if report.testValidi {
                        Text(report.sintesiRisultati)
                            .font(.body)
                    } else {
                        Text("Test non validi")
                            .font(.body)
                            .foregroundColor(.orange)
                        if let motivo = report.testInvalidiMotivo {
                            Text(motivo)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.05))
                )
            }
            
            // Compatibilità FE
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(compatibilitaColor)
                    Text("Compatibilità FE")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    ConfidenzaBadge(livello: confidenzaLivello(bene.compatibilitaFE.confidenza))
                }
                
                Text(bene.compatibilitaFE.motivazione)
                    .font(.body)
                    .foregroundColor(.secondary)
                
                // Evidenze
                if !bene.compatibilitaFE.evidenzeAFavore.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A favore:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(bene.compatibilitaFE.evidenzeAFavore.prefix(3), id: \.descrizione) { ev in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption2)
                                Text(ev.descrizione)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                
                if !bene.compatibilitaFE.evidenzeContrarie.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Contrarie:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(bene.compatibilitaFE.evidenzeContrarie.prefix(3), id: \.descrizione) { ev in
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption2)
                                Text(ev.descrizione)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(compatibilitaColor.opacity(0.05))
            )
            
            // Stima economica
            if let stima = bene.stimaEconomica {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "eurosign.circle.fill")
                            .foregroundColor(.green)
                        Text("Stima Economica")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        if let importo = stima.importo, importo.daVisualizzare {
                            Text("€\(String(format: "%.2f", importo.valore))")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                    }
                    
                    Text(stima.descrizione)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.05))
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    private var compatibilitaColor: Color {
        switch bene.compatibilitaFE.esito {
        case "compatibile": return .green
        case "poco_probabile": return .orange
        case "non_compatibile": return .red
        default: return .gray
        }
    }
    
    private func confidenzaLivello(_ value: Double) -> PerxiaService.LivelloConfidenza {
        if value < 0.6 { return .nonDisponibile }
        if value < 0.76 { return .bassa }
        if value < 0.91 { return .media }
        return .alta
    }
    
    private func openPhotoViewer(foto: [String]) {
        guard !foto.isEmpty else { return }
        
        // Converti path in URL
        let photoURLs = foto.compactMap { path -> URL? in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }
        
        guard !photoURLs.isEmpty, let firstURL = photoURLs.first else { return }
        
        // Apri MediaViewer con tutte le foto associate
        MediaViewerWindowManager.shared.openMediaViewer(for: firstURL, files: photoURLs)
    }
    
    /// Estrae una sintesi breve dall'analisi visiva (prima frase o prime 150 caratteri)
    private func sintesiAnalisiVisiva(_ testo: String) -> String {
        let trimmed = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Prova a trovare la prima frase (terminata da punto, esclamazione o punto interrogativo)
        if let primoPunto = trimmed.firstIndex(where: { ".!?".contains($0) }) {
            let primaFrase = String(trimmed[...primoPunto])
            if primaFrase.count <= 200 {
                return primaFrase.trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Altrimenti taglia a 150 caratteri e aggiungi "..."
        if trimmed.count > 150 {
            let index = trimmed.index(trimmed.startIndex, offsetBy: 150)
            return String(trimmed[..<index]).trimmingCharacters(in: .whitespaces) + "..."
        }
        
        return trimmed
    }
}

// MARK: - Dato con Fonte
struct DatoConFonte: View {
    let label: String
    let valore: String
    let confidenza: PerxiaService.LivelloConfidenza
    let fontiFoto: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ConfidenzaBadge(livello: confidenza)
                
                // Icona foto (una sola icona per aprire MediaViewer con tutte le foto)
                if !fontiFoto.isEmpty {
                    Button {
                        openPhotoViewer(foto: fontiFoto)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "photo")
                                .font(.caption2)
                            if fontiFoto.count > 1 {
                                Text("(\(fontiFoto.count))")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    .help(fontiFoto.count > 1 ? "\(fontiFoto.count) foto" : "1 foto")
                }
            }
            
            Text(valore)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
    
    private func openPhotoViewer(foto: [String]) {
        guard !foto.isEmpty else { return }
        
        // Converti path in URL
        let photoURLs = foto.compactMap { path -> URL? in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }
        
        guard !photoURLs.isEmpty, let firstURL = photoURLs.first else { return }
        
        // Apri MediaViewer con tutte le foto associate
        MediaViewerWindowManager.shared.openMediaViewer(for: firstURL, files: photoURLs)
    }
}

// MARK: - Confidenza Badge
struct ConfidenzaBadge: View {
    let livello: PerxiaService.LivelloConfidenza
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: livello.icona)
                .font(.caption2)
            if livello != .alta {
                Text(livello.rawValue)
                    .font(.caption2)
            }
        }
        .foregroundColor(color)
    }
    
    private var color: Color {
        switch livello {
        case .nonDisponibile: return .gray
        case .bassa: return .orange
        case .media: return .yellow
        case .alta: return .green
        }
    }
}

// MARK: - Misure Report Sheet
struct MisureReportSheet: View {
    let report: PerxiaService.ReportMisure
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Report Misure Strumentali")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Chiudi") {
                    dismiss()
                }
            }
            
            Divider()
            
            if report.testValidi {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Almeno un test è stato eseguito correttamente")
                        .font(.subheadline)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.1))
                )
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading) {
                        Text("Nessun test valido")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if let motivo = report.testInvalidiMotivo {
                            Text(motivo)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                )
            }
            
            Text("Sintesi: \(report.sintesiRisultati)")
                .font(.body)
                .padding(.vertical, 8)
            
            Divider()
            
            Text("Dettaglio Misure")
                .font(.headline)
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(report.misureRilevate) { misura in
                        MisuraDetailCard(misura: misura)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 400)
    }
}

struct MisuraDetailCard: View {
    let misura: PerxiaService.MisuraRilevata
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(misura.tipoMisura.capitalized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if misura.testValido {
                    Label("Valido", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("Non valido", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Strumento")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(misura.strumento)
                        .font(.body)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Valore")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 2) {
                        Text(misura.valore)
                            .font(.body)
                            .fontWeight(.medium)
                        if let unit = misura.unitaMisura {
                            Text(unit)
                                .font(.caption)
                        }
                    }
                }
            }
            
            if let dettagli = misura.dettagliTest, !dettagli.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dettagli test:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(dettagli)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            if !misura.interpretazione.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Interpretazione:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(misura.interpretazione)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            // Relazione test (sempre mostrata, sia per test validi che non validi)
            if let relazione = misura.relazioneTest, !relazione.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: misura.testValido ? "info.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(misura.testValido ? .blue : .orange)
                        Text(misura.testValido ? "Relazione test" : "Test non valido")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(misura.testValido ? .blue : .orange)
                    }
                    Text(relazione)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(misura.testValido ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                )
            } else if !misura.testValido, let motivo = misura.motivoInvalidita, !motivo.isEmpty {
                // Fallback al motivoInvalidita se relazioneTest non è disponibile
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Test non valido")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                    Text(motivo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.1))
                )
            }
            
            if let indicaDanno = misura.indicaDanno {
                HStack {
                    Image(systemName: indicaDanno ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(indicaDanno ? .orange : .green)
                    Text(indicaDanno ? "Indica possibile danno" : "Nessun danno rilevato")
                        .font(.caption)
                }
            }
            
            // Confidenze
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("Lettura:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(Int(misura.confidenzaLettura * 100))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                
                HStack(spacing: 4) {
                    Text("Interpretazione:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(Int(misura.confidenzaInterpretazione * 100))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
            }
            
            // Foto associata
            if !misura.fotoPath.isEmpty {
                HStack {
                    Text("Foto:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        openPhotoViewer(foto: [misura.fotoPath])
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.caption2)
                            Text(URL(fileURLWithPath: misura.fotoPath).lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.purple)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        )
    }
    
    private func openPhotoViewer(foto: [String]) {
        guard !foto.isEmpty else { return }
        
        let photoURLs = foto.compactMap { path -> URL? in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }
        
        guard !photoURLs.isEmpty, let firstURL = photoURLs.first else { return }
        MediaViewerWindowManager.shared.openMediaViewer(for: firstURL, files: photoURLs)
    }
}

// MARK: - Analisi Visiva Sheet
struct AnalisiVisivaSheet: View {
    let bene: PerxiaService.BeneAnalysisStreaming
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Analisi Visiva - \(bene.nome)")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Chiudi") {
                    dismiss()
                }
            }
            
            Divider()
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Sintesi
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sintesi")
                                .font(.headline)
                            
                            Text(bene.osservazioniVisive.valore)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Foto associate alla sintesi
                            if !bene.osservazioniVisive.fontiFoto.isEmpty {
                                HStack {
                                    Text("Foto:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(bene.osservazioniVisive.fontiFoto, id: \.self) { path in
                                                Button {
                                                    openPhotoViewer(foto: [path])
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "photo")
                                                            .font(.caption2)
                                                        Text(URL(fileURLWithPath: path).lastPathComponent)
                                                            .font(.caption)
                                                            .lineLimit(1)
                                                    }
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.blue.opacity(0.1))
                                                    .cornerRadius(6)
                                                }
                                                .buttonStyle(.plain)
                                                .foregroundColor(.blue)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    
                    // Segni danno elettrico
                    if !bene.segniDannoElettrico.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.orange)
                                Text("Segni di Danno Elettrico")
                                    .font(.headline)
                            }
                            
                            VStack(spacing: 12) {
                                ForEach(Array(bene.segniDannoElettrico.enumerated()), id: \.offset) { index, segno in
                                    SegnoDetailCard(segno: segno, tipo: .elettrico)
                                }
                            }
                        }
                    }
                    
                    // Segni danno non elettrico
                    if !bene.segniDannoNonElettrico.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("Segni di Danno Non Elettrico")
                                    .font(.headline)
                            }
                            
                            VStack(spacing: 12) {
                                ForEach(Array(bene.segniDannoNonElettrico.enumerated()), id: \.offset) { index, segno in
                                    SegnoDetailCard(segno: segno, tipo: .nonElettrico)
                                }
                            }
                        }
                    }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            // Verifica che i dati siano disponibili
            if bene.osservazioniVisive.valore.isEmpty {
                print("[AnalisiVisivaSheet] ⚠️ Analisi visiva vuota per bene: \(bene.nome)")
            }
        }
    }
    
    private func openPhotoViewer(foto: [String]) {
        guard !foto.isEmpty else { 
            print("[AnalisiVisivaSheet] ⚠️ Nessuna foto da aprire")
            return 
        }
        
        let photoURLs = foto.compactMap { path -> URL? in
            // Verifica esistenza file
            guard FileManager.default.fileExists(atPath: path) else {
                print("[AnalisiVisivaSheet] ⚠️ File non trovato: \(path)")
                return nil
            }
            return URL(fileURLWithPath: path)
        }
        
        guard !photoURLs.isEmpty, let firstURL = photoURLs.first else {
            print("[AnalisiVisivaSheet] ❌ Nessun URL valido per le foto: \(foto)")
            return
        }
        
        print("[AnalisiVisivaSheet] 📸 Apertura MediaViewer con \(photoURLs.count) foto")
        MediaViewerWindowManager.shared.openMediaViewer(for: firstURL, files: photoURLs)
    }
}

// MARK: - Segno Detail Card
struct SegnoDetailCard: View {
    let segno: PerxiaService.SegnoElettrico
    let tipo: TipoSegno
    
    enum TipoSegno {
        case elettrico, nonElettrico
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(segno.tipo.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if segno.confidenza < 0.76 {
                    Label("Confidenza bassa", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            // Descrizione con pillola per foto se presente
            if let fotoPath = segno.fotoPath, !fotoPath.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text(segno.descrizione)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Button {
                        openPhotoViewer(foto: [fotoPath])
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.caption2)
                            Text("Foto")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tipo == .elettrico ? Color.orange.opacity(0.1) : Color.red.opacity(0.1))
                        .foregroundColor(tipo == .elettrico ? .orange : .red)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(segno.descrizione)
                    .font(.body)
            }
            
            if let posizione = segno.posizione, !posizione.isEmpty {
                HStack {
                    Text("Posizione:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(posizione)
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tipo == .elettrico ? Color.orange.opacity(0.05) : Color.red.opacity(0.05))
        )
    }
    
    private func openPhotoViewer(foto: [String]) {
        guard !foto.isEmpty else { return }
        
        let photoURLs = foto.compactMap { path -> URL? in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }
        
        guard !photoURLs.isEmpty, let firstURL = photoURLs.first else { return }
        MediaViewerWindowManager.shared.openMediaViewer(for: firstURL, files: photoURLs)
    }
    
    // Init per SegnoElettrico
    init(segno: PerxiaService.SegnoElettrico, tipo: TipoSegno) {
        self.segno = segno
        self.tipo = tipo
    }
    
    // Init per supportare SegnoNonElettrico
    init(segno: PerxiaService.SegnoNonElettrico, tipo: TipoSegno) {
        self.segno = PerxiaService.SegnoElettrico(
            tipo: segno.tipo,
            descrizione: segno.descrizione,
            posizione: segno.posizione,
            confidenza: segno.confidenza,
            fotoPath: segno.fotoPath
        )
        self.tipo = tipo
    }
}

// MARK: - Bene Analysis Card
struct BeneAnalysisCard: View {
    let bene: PerxiaService.BeneAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: Tipo bene, marca, modello, anno
            VStack(alignment: .leading, spacing: 8) {
                Text(bene.nome)
                    .font(.headline)
                    .fontWeight(.bold)
                
                HStack(spacing: 16) {
                    if let marca = bene.marca, !marca.isEmpty {
                        Label(marca, systemImage: "tag.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let modello = bene.modello, !modello.isEmpty {
                        Label(modello, systemImage: "cube.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let anno = bene.anno, !anno.isEmpty {
                        HStack(spacing: 4) {
                            Label(anno, systemImage: "calendar")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if bene.annoStimato {
                                Text("(stimato)")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Analisi visiva del bene
            if !bene.osservazioniVisive.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "eye.fill")
                            .foregroundColor(.blue)
                        Text("Analisi Visiva")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    Text(bene.osservazioniVisive)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.05))
                )
            }
            
            // Test strumentali
            if !bene.testEseguiti.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "gauge.high")
                            .foregroundColor(.purple)
                        Text("Test Strumentali")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    Text(bene.testEseguiti)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.05))
                )
            }
            
            // Compatibilità FE
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(compatibilitaColor)
                    Text("Compatibilità Fenomeno Elettrico")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // Badge compatibilità
                    Text(bene.compatibilitaFE.esito.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(compatibilitaColor.opacity(0.2))
                        )
                        .foregroundColor(compatibilitaColor)
                }
                
                Text(bene.compatibilitaFE.motivazione)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !bene.compatibilitaFE.evidenzeAFavore.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Evidenze a favore:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(bene.compatibilitaFE.evidenzeAFavore, id: \.self) { evidenza in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption2)
                                Text(evidenza)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green.opacity(0.05))
                    )
                }
                
                if !bene.compatibilitaFE.evidenzeContrarie.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Evidenze contrarie:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(bene.compatibilitaFE.evidenzeContrarie, id: \.self) { evidenza in
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption2)
                                Text(evidenza)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.05))
                    )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(compatibilitaColor.opacity(0.05))
            )
            
            // Stima economica
            if let stima = bene.stimaEconomica {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "eurosign.circle.fill")
                            .foregroundColor(.green)
                        Text("Stima Economica")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        if let importo = stima.importo {
                            Text("€\(String(format: "%.2f", importo))")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                    }
                    
                    Text(stima.descrizione)
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    if !stima.baseStima.isEmpty {
                        Text("Base: \(stima.baseStima)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let note = stima.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.05))
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    private var compatibilitaColor: Color {
        switch bene.compatibilitaFE.esito {
        case "compatibile": return .green
        case "poco_probabile": return .orange
        case "non_compatibile": return .red
        default: return .gray
        }
    }
}

