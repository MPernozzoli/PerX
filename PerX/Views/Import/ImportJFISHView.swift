import SwiftUI
import UniformTypeIdentifiers

struct ImportJFISHView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var importService = ImportService.shared
    
    @State private var currentStep: ImportStep = .selectFile
    @State private var selectedFileURL: URL?
    @State private var importData: ImportService.ImportData?
    @State private var columnMappings: [ImportService.ColumnMapping] = []
    @State private var stateMappings: [ImportService.StateMapping] = []
    @State private var uniqueStates: Set<String> = []
    @State private var importResult: ImportService.ImportResult?
    @State private var isProcessing = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var importProgress: Double = 0.0
    @State private var processedCount: Int = 0
    
    enum ImportStep {
        case selectFile
        case mapColumns
        case mapStates
        case previewChanges
        case confirm
        case result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Import da JFISH")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Annulla") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // Progress indicator
            ProgressView(value: progressValue, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
                .padding(.horizontal)
            
            HStack {
                ForEach(ImportStep.allCases, id: \.self) { step in
                    HStack {
                        Circle()
                            .fill(stepColor(step))
                            .frame(width: 12, height: 12)
                        Text(stepTitle(step))
                            .font(.caption)
                            .foregroundColor(stepColor(step))
                    }
                    if step != ImportStep.allCases.last {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 1)
                    }
                }
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                switch currentStep {
                case .selectFile:
                    FileSelectionView(
                        selectedFileURL: $selectedFileURL,
                        onFileSelected: loadFile
                    )
                    
                case .mapColumns:
                    if let data = importData {
                        ColumnMappingView(
                            importData: data,
                            columnMappings: $columnMappings,
                            onNext: { extractStatesAndProceed() }
                        )
                    }
                    
                case .mapStates:
                    StateMappingView(
                        uniqueStates: uniqueStates,
                        stateMappings: $stateMappings,
                        onNext: { currentStep = .previewChanges }
                    )
                    
                case .previewChanges:
                    if let data = importData {
                        ImportPreviewView(
                            importData: data,
                            columnMappings: columnMappings,
                            stateMappings: stateMappings,
                            onNext: { currentStep = .confirm }
                        )
                    }
                    
                case .confirm:
                    ConfirmImportView(
                        importData: importData,
                        columnMappings: columnMappings,
                        stateMappings: stateMappings,
                        onConfirm: { revokeMissing in
                            performImport(revokeMissing: revokeMissing)
                        },
                        progress: $importProgress,
                        processedCount: $processedCount
                    )
                    
                case .result:
                    if let result = importResult {
                        ImportResultView(result: result)
                    }
                }
            }
            
            Divider()
            
            // Footer con pulsanti
            HStack {
                if currentStep != .selectFile && currentStep != .result {
                    Button("Indietro") {
                        goBack()
                    }
                }
                
                Spacer()
                
                if currentStep == .result {
                    Button("Chiudi") {
                        dismiss()
                    }
                    .keyboardShortcut(.return)
                }
            }
            .padding()
        }
        .frame(width: 1000, height: 700)
        .alert("Errore", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Computed Properties
    
    private var progressValue: Double {
        switch currentStep {
        case .selectFile: return 0.0
        case .mapColumns: return 0.2
        case .mapStates: return 0.4
        case .previewChanges: return 0.6
        case .confirm: return 0.8
        case .result: return 1.0
        }
    }
    
    private func stepColor(_ step: ImportStep) -> Color {
        if ImportStep.allCases.firstIndex(of: step)! <= ImportStep.allCases.firstIndex(of: currentStep)! {
            return .blue
        } else {
            return .secondary
        }
    }
    
    private func stepTitle(_ step: ImportStep) -> String {
        switch step {
        case .selectFile: return "Selezione File"
        case .mapColumns: return "Mapping Colonne"
        case .mapStates: return "Mapping Stati"
        case .previewChanges: return "Anteprima"
        case .confirm: return "Conferma"
        case .result: return "Risultato"
        }
    }
    
    // MARK: - Actions
    
    private func loadFile() {
        guard let url = selectedFileURL else { return }
        
        Task {
            do {
                let data = try await importService.readFile(at: url)
                await MainActor.run {
                    importData = data
                    currentStep = .mapColumns
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    private func extractStatesAndProceed() {
        guard let data = importData,
              let statoMapping = columnMappings.first(where: { $0.targetField == .stato }) else {
            currentStep = .confirm
            return
        }
        
        // Estrai gli stati unici dalla colonna mappata
        guard let statoColumnIndex = data.headers.firstIndex(of: statoMapping.sourceColumn) else {
            currentStep = .confirm
            return
        }
        
        var states = Set<String>()
        for row in data.rows {
            if statoColumnIndex < row.count {
                let stato = row[statoColumnIndex].trimmingCharacters(in: .whitespaces)
                if !stato.isEmpty {
                    states.insert(stato)
                }
            }
        }
        
        uniqueStates = states
        
        if states.isEmpty {
            currentStep = .confirm
        } else {
            currentStep = .mapStates
        }
    }
    
    private func performImport(revokeMissing: Bool) {
        guard let data = importData else { return }
        
        isProcessing = true
        importProgress = 0.0
        processedCount = 0
        
        Task {
            do {
                let context = PersistenceController.shared.container.newBackgroundContext()
                let totalRows = data.rows.count
                
                // Processa in batch con aggiornamenti progressivi
                var processed = 0
                var updated = 0
                var created = 0
                var revoked = 0
                var errors: [String] = []
                var sinistroChanges: [ImportService.SinistroChange] = []
                
                let batchSize = 50
                
                for batchStart in stride(from: 0, to: totalRows, by: batchSize) {
                    let batchEnd = min(batchStart + batchSize, totalRows)
                    let batch = Array(data.rows[batchStart..<batchEnd])
                    
                    for (localIndex, row) in batch.enumerated() {
                        let globalIndex = batchStart + localIndex
                        do {
                            let change = try await importService.processRowInternal(
                                row: row,
                                headers: data.headers,
                                columnMappings: columnMappings,
                                stateMappings: stateMappings,
                                context: context
                            )
                            
                            processed += 1
                            if change.isNew {
                                created += 1
                            } else {
                                updated += 1
                            }
                            
                            // Limita i cambiamenti salvati
                            if sinistroChanges.count < 500 {
                                sinistroChanges.append(change)
                            }
                            
                        } catch {
                            errors.append("Riga \(globalIndex + 2): \(error.localizedDescription)")
                        }
                    }
                    
                    // Salva periodicamente
                    if context.hasChanges {
                        try context.save()
                    }
                    
                    // Aggiorna progresso
                    await MainActor.run {
                        processedCount = processed
                        importProgress = Double(processed) / Double(totalRows)
                    }
                    
                    // Yield per permettere aggiornamenti UI
                    await Task.yield()
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }
                
                // Gestione revoca sinistri mancanti
                if revokeMissing {
                    let allRiferimentiInFile = Set(data.rows.compactMap { row -> String? in
                        guard let riferimentoMapping = columnMappings.first(where: { $0.targetField == .riferimento }),
                              let riferimentoIndex = data.headers.firstIndex(of: riferimentoMapping.sourceColumn),
                              riferimentoIndex < row.count else {
                            return nil
                        }
                        let riferimento = row[riferimentoIndex].trimmingCharacters(in: .whitespaces)
                        return riferimento.isEmpty ? nil : riferimento
                    })
                    
                    let fetchRequest: NSFetchRequest<Sinistro> = Sinistro.fetchRequest
                    fetchRequest.predicate = NSPredicate(format: "NOT (riferimento IN %@) AND stato != %@", allRiferimentiInFile, "Revocata")
                    
                    let sinistriDaRevocare = try context.fetch(fetchRequest)
                    for sinistro in sinistriDaRevocare {
                        sinistro.stato = "Revocata"
                        sinistro.dataRevoca = Date()
                        revoked += 1
                    }
                    
                    if context.hasChanges {
                        try context.save()
                    }
                }
                
                let result = ImportService.ImportResult(
                    processed: processed,
                    updated: updated,
                    created: created,
                    revoked: revoked,
                    errors: errors,
                    sinistroChanges: sinistroChanges
                )
                
                await MainActor.run {
                    isProcessing = false
                    importResult = result
                    currentStep = .result
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    private func goBack() {
        switch currentStep {
        case .mapColumns:
            currentStep = .selectFile
        case .mapStates:
            currentStep = .mapColumns
        case .previewChanges:
            if uniqueStates.isEmpty {
                currentStep = .mapColumns
            } else {
                currentStep = .mapStates
            }
        case .confirm:
            currentStep = .previewChanges
        default:
            break
        }
    }
}

// MARK: - Extensions

extension ImportJFISHView.ImportStep: CaseIterable {
    static var allCases: [ImportJFISHView.ImportStep] {
        [.selectFile, .mapColumns, .mapStates, .previewChanges, .confirm, .result]
    }
} 