import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AISettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @AppStorage("ai_mlx_vision_model_path") private var mlxVisionModelPath = ""
    @AppStorage("ai_local_text_endpoint") private var textEndpoint = "http://localhost:11434/api/generate"
    @AppStorage("ai_local_text_model") private var textModel = ""
    @AppStorage("ai_local_text_gguf_path") private var textGGUFPath = ""
    @AppStorage("ai_local_timeout") private var localTimeout = 60.0
    
    @AppStorage("ai_max_concurrent_tasks") private var maxConcurrentTasks = 5
    @AppStorage("ai_max_primary_tasks") private var maxPrimaryTasks = 3
    @AppStorage("ai_max_secondary_tasks") private var maxSecondaryTasks = 2
    
    @AppStorage("ai_enable_background_processing") private var enableBackgroundProcessing = true
    @AppStorage("ai_enable_local_multimodal") private var enableLocalMultimodal = true
    @AppStorage("ai_enable_local_text") private var enableLocalText = true
    @AppStorage("ai_enable_apple_intelligence") private var enableAppleIntelligence = true
    @AppStorage("ai_enable_cloud_fallback") private var enableCloudFallback = true
    
    @State private var loadingModel: ModelType?
    @State private var modelLoadStatus: String?
    @State private var loadingMLXModel = false
    @State private var mlxModelLoadStatus: String?
    
    @StateObject private var aiManager = AIManager.shared
    @StateObject private var resourceMonitor = ResourceMonitor.shared
    @StateObject private var mlxVisionService = MLXVisionService.shared
    @State private var isRefreshingKeys = false
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \AIKnowledgeDocument.ordine, ascending: true)],
        animation: .default
    ) private var knowledgeDocs: FetchedResults<AIKnowledgeDocument>
    @State private var showKnowledgeEditor = false
    @State private var editingDoc: AIKnowledgeDocument?
    @State private var knowledgeTitle = ""
    @State private var knowledgeContent = ""
    @State private var knowledgeCategory = "definizioni"
    @State private var knowledgeOrder: Int = 0
    @State private var knowledgeActive = true
    
    // RAG build (file -> kb.sqlite esterno)
    @State private var ragSelectedFiles: [URL] = []
    @StateObject private var ragBuildManager = RAGBuildManager.shared
    
    enum ModelType {
        case text
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Cloud AI — status (chiavi gestite da Supabase)
                GroupBox("AI Cloud (OpenAI + Claude)") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Le chiavi API vengono configurate dall'amministratore su Supabase e sincronizzate automaticamente.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        // OpenAI
                        HStack {
                            Label("OpenAI", systemImage: "cloud")
                                .font(.callout)
                            Spacer()
                            if TenantAIKeysService.shared.hasOpenAIKey {
                                Label(TenantAIKeysService.shared.openAIModel, systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Label("Non configurato", systemImage: "xmark.circle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Claude
                        HStack {
                            Label("Claude (Anthropic)", systemImage: "cloud")
                                .font(.callout)
                            Spacer()
                            if TenantAIKeysService.shared.hasAnthropicKey {
                                Label(TenantAIKeysService.shared.anthropicModel, systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Label("Non configurato", systemImage: "xmark.circle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        Toggle("Abilita fallback cloud", isOn: $enableCloudFallback)
                            .font(.callout)

                        HStack {
                            Spacer()
                            Button {
                                isRefreshingKeys = true
                                Task {
                                    await TenantAIKeysService.shared.forceRefresh()
                                    isRefreshingKeys = false
                                }
                            } label: {
                                if isRefreshingKeys {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Label("Sincronizza chiavi", systemImage: "arrow.clockwise")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRefreshingKeys)
                        }
                    }
                    .padding()
                }
                
                // Local Models Configuration
                GroupBox("Modelli Locali") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Abilita modelli locali", isOn: .constant(enableLocalMultimodal || enableLocalText))
                            .disabled(true)
                        
                        // Info modelli locali
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                Text("Modelli Locali")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("• Modello Multimodale: Llama 3.1 8B Vision con PyTorch/MPS su Apple Silicon")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("• Modello Testo: Usa Ollama (gestito automaticamente)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        
                        Divider()
                        
                        // Multimodale (Llama 3.1 8B Vision - MLX)
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Modello Multimodale (Llama 3.1 8B Vision - MLX)", isOn: $enableLocalMultimodal)
                            
                            if enableLocalMultimodal {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Modello MLX")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        if loadingMLXModel || mlxVisionService.isLoading {
                                            HStack {
                                                ProgressView()
                                                    .scaleEffect(0.7)
                                                Text(loadingMLXModel ? "Caricamento in corso..." : "Caricamento automatico...")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            if mlxVisionService.isLoading {
                                                ProgressView(value: mlxVisionService.loadProgress)
                                                    .progressViewStyle(.linear)
                                                Text("Progresso: \(Int(mlxVisionService.loadProgress * 100))%")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        if let status = mlxModelLoadStatus {
                                            Text(status)
                                                .font(.caption2)
                                                .foregroundColor(status.contains("✅") ? .green : .red)
                                        }
                                        
                                        if mlxVisionService.isModelLoaded {
                                            HStack {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                Text("Modello caricato e pronto")
                                                    .font(.caption)
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        
                                        if let error = mlxVisionService.loadError {
                                            HStack {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .foregroundColor(.orange)
                                                Text(error)
                                                    .font(.caption2)
                                                    .foregroundColor(.orange)
                                            }
                                        }
                                    }
                                    
                                    Text("Inserisci l'ID del modello Hugging Face (es. 'qresearch/llama-3.1-8B-vision-378') o seleziona una cartella locale. Il modello verrà scaricato automaticamente se non presente.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    TextField("qresearch/llama-3.1-8B-vision-378", text: $mlxVisionModelPath)
                                        .textFieldStyle(.roundedBorder)
                                        .onSubmit {
                                            if !mlxVisionModelPath.isEmpty {
                                                loadMLXModel(path: mlxVisionModelPath)
                                            }
                                        }
                                    
                                    HStack {
                                        Button("Usa ID Hugging Face") {
                                            mlxVisionModelPath = "qresearch/llama-3.1-8B-vision-378"
                                            loadMLXModel(path: mlxVisionModelPath)
                                        }
                                        .buttonStyle(.bordered)
                                        
                                        Button("Scegli Cartella Locale...") {
                                            selectMLXModel()
                                        }
                                        .buttonStyle(.bordered)
                                        
                                        if !mlxVisionModelPath.isEmpty && !mlxVisionService.isModelLoaded {
                                            Button("Ricarica Modello") {
                                                loadMLXModel(path: mlxVisionModelPath)
                                            }
                                            .buttonStyle(.bordered)
                                            .foregroundColor(.orange)
                                        }
                                    }
                                    
                                    #if !arch(arm64)
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text("⚠️ MLX è ottimizzato per Apple Silicon (M-series). Le prestazioni potrebbero essere ridotte su Intel.")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                    #endif
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        
                        Divider()
                        
                        // Testo (Microsoft Phi)
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Modello Testo (Microsoft Phi-3/4)", isOn: $enableLocalText)
                            
                            if enableLocalText {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("File Modello (.gguf)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(textGGUFPath.isEmpty ? "Nessun file selezionato" : (textGGUFPath as NSString).lastPathComponent)
                                                .foregroundColor(textGGUFPath.isEmpty ? .secondary : .primary)
                                            Spacer()
                                            if loadingModel == .text {
                                                ProgressView()
                                                    .scaleEffect(0.7)
                                            } else {
                                                Button("Scegli File...") {
                                                    selectGGUFFile(for: .text)
                                                }
                                                .buttonStyle(.bordered)
                                            }
                                        }
                                        
                                        if loadingModel == .text, let status = modelLoadStatus {
                                            Text(status)
                                                .font(.caption2)
                                                .foregroundColor(status.contains("✅") ? .green : .red)
                                        }
                                        
                                        if !textModel.isEmpty && !textGGUFPath.isEmpty {
                                            Text("Modello in Ollama: \(textModel)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Text("Seleziona il file .gguf del modello testo. Verrà caricato automaticamente in Ollama.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Timeout Modelli Locali (secondi)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Stepper(value: $localTimeout, in: 30...300, step: 10) {
                                Text("\(Int(localTimeout))s")
                            }
                        }
                    }
                    .padding()
                }
                
            // Motore RAG (caricamento file e generazione KB)
            GroupBox("Motore RAG") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Carica file di conoscenza (.txt, .md, .rtf) per generare il database vettoriale locale (kb.sqlite). Il processo avviene in background e continua anche se chiudi questa vista.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Button {
                            selectKnowledgeFiles()
                        } label: {
                            Label("Seleziona file", systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            openKnowledgeFolder()
                        } label: {
                            Label("Apri cartella KB", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            startRAGBuild()
                        } label: {
                            if ragBuildManager.isRunning {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label("Genera database RAG", systemImage: "gearshape.2")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(ragSelectedFiles.isEmpty || ragBuildManager.isRunning)
                    }
                    
                    if !ragSelectedFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("File selezionati (\(ragSelectedFiles.count))")
                                .font(.subheadline)
                            ForEach(ragSelectedFiles, id: \.self) { url in
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if ragBuildManager.isRunning {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: ragBuildManager.progress)
                            Text(ragBuildManager.status)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if let status = ragBuildManager.status.nonEmpty {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let error = ragBuildManager.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding()
            }
            
                // Apple Intelligence
                GroupBox("Apple Intelligence") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Abilita Apple Intelligence", isOn: $enableAppleIntelligence)
                        
                        if enableAppleIntelligence {
                            Text("Apple Intelligence è sempre disponibile e viene usato per:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Riassunti email", systemImage: "envelope")
                                Label("Guardrailing dei risultati", systemImage: "shield.checkered")
                                Label("Analisi testi base", systemImage: "text.alignleft")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
                
                // Resource Management
                GroupBox("Gestione Risorse") {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Task Simultanei Massimi")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Stepper(value: $maxConcurrentTasks, in: 1...10) {
                                Text("\(maxConcurrentTasks) task")
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Task Primari Massimi")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Stepper(value: $maxPrimaryTasks, in: 1...5) {
                                Text("\(maxPrimaryTasks) task")
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Task Secondari Massimi")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Stepper(value: $maxSecondaryTasks, in: 1...5) {
                                Text("\(maxSecondaryTasks) task")
                            }
                        }
                        
                        Divider()
                        
                        // Monitoraggio risorse in tempo reale
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Stato Risorse")
                                .font(.headline)
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("RAM Disponibile")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(formatBytes(resourceMonitor.availableRAM))
                                        .font(.title3)
                                        .bold()
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing) {
                                    Text("RAM Totale")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(formatBytes(resourceMonitor.totalRAM))
                                        .font(.title3)
                                }
                            }
                            
                            ProgressView(value: Double(resourceMonitor.totalRAM - resourceMonitor.availableRAM), total: Double(resourceMonitor.totalRAM)) {
                                Text("Uso RAM: \(Int(resourceMonitor.getUsedRAMPercentage() * 100))%")
                                    .font(.caption)
                            }
                            
                            HStack {
                                Text("CPU Usage: \(Int(resourceMonitor.cpuUsage * 100))%")
                                    .font(.caption)
                                Spacer()
                                Text("Pressione Memoria: \(resourceMonitor.memoryPressure.description)")
                                    .font(.caption)
                                    .foregroundColor(resourceMonitor.memoryPressure == .critical ? .red : .secondary)
                            }
                        }
                    }
                    .padding()
                }
                
                // Background Processing
                GroupBox("Elaborazione in Background") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Abilita elaborazione in background", isOn: $enableBackgroundProcessing)
                        
                        if enableBackgroundProcessing {
                            Text("Il sistema analizzerà automaticamente i documenti dei sinistri in background quando:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Il computer è collegato all'alimentazione", systemImage: "powerplug")
                                Label("Ci sono risorse disponibili", systemImage: "cpu")
                                Label("Non ci sono task primari in esecuzione", systemImage: "star.fill")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
                            HStack {
                                Text("Stato:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if resourceMonitor.isOnACPower() {
                                    Label("Collegato all'alimentazione", systemImage: "powerplug.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Label("Alimentazione batteria", systemImage: "battery.100")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                // Test Chat
                GroupBox("Test Modelli AI") {
                    AITestChatView()
                }
                
                // Statistics
                GroupBox("Statistiche e Feedback") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Task in Coda")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(aiManager.queueSize)")
                                    .font(.title2)
                                    .bold()
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text("Task Attivi")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(aiManager.activeTasks.count)")
                                    .font(.title2)
                                    .bold()
                            }
                        }
                        
                        if !aiManager.completedTasksHistory.isEmpty {
                            Divider()
                            
                            Text("Task Completate Oggi: \(aiManager.getCompletedTasksToday().count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Button("Esporta Feedback per Fine-Tuning") {
                            exportFeedback()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            }
            .padding()
        }
        .sheet(isPresented: $showKnowledgeEditor) {
            knowledgeEditor
                .frame(width: 600, height: 500)
        }
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func selectGGUFFile(for type: ModelType) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.data]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.title = "Seleziona Modello Testo (.gguf)"
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            let path = url.path
            
            // Verifica che sia un file .gguf
            guard path.lowercased().hasSuffix(".gguf") else {
                modelLoadStatus = "Errore: Il file deve avere estensione .gguf"
                return
            }
            
            // Salva il percorso del file .gguf (solo per modello testo)
            textGGUFPath = path
            
            // Carica il modello in Ollama (il nome effettivo verrà salvato dopo il caricamento)
            loadModelToOllama(path: path, type: type)
        }
    }
    
    private func selectMLXModel() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = false
        openPanel.title = "Seleziona cartella modello MLX"
        openPanel.prompt = "Seleziona"
        
        if openPanel.runModal() == .OK {
            if let selectedURL = openPanel.url {
                let path = selectedURL.path
                print("[AISettingsView] 📁 Percorso selezionato: \(path)")
                mlxVisionModelPath = path
                UserDefaults.standard.set(path, forKey: "ai_mlx_vision_model_path")
                print("[AISettingsView] 💾 Percorso salvato in UserDefaults: \(path)")
                
                // Verifica che il percorso sia stato salvato
                let verifyPath = UserDefaults.standard.string(forKey: "ai_mlx_vision_model_path") ?? ""
                print("[AISettingsView] ✅ Verifica percorso salvato: '\(verifyPath)'")
                
                // Carica il modello
                loadMLXModel(path: path)
            }
        }
    }
    
    // MARK: - RAG build helpers
    
    private func selectKnowledgeFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .plainText,
            UTType(filenameExtension: "md") ?? .plainText,
            .rtf
        ]
        panel.prompt = "Seleziona"
        if panel.runModal() == .OK {
            ragSelectedFiles = panel.urls
        }
    }
    
    private func startRAGBuild() {
        do {
            let workDir = try ensureKnowledgeWorkdir()
            let sourceFiles: [URL]
            if ragSelectedFiles.isEmpty {
                // Usa i file già presenti in cartella
                let existing = try FileManager.default.contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil)
                    .filter { ["txt", "md", "rtf"].contains($0.pathExtension.lowercased()) }
                guard !existing.isEmpty else {
                    ragBuildManager.errorMessage = "Nessun file di knowledge in cartella. Seleziona file o aggiungili in KnowledgeInput."
                    return
                }
                ragSelectedFiles = existing
                sourceFiles = existing
            } else {
                sourceFiles = try copyFilesToWorkdir(ragSelectedFiles, workdir: workDir)
            }
            ragBuildManager.startBuild(with: sourceFiles)
        } catch {
            ragBuildManager.errorMessage = error.localizedDescription
        }
    }
    
    private func loadMLXModel(path: String) {
        loadingMLXModel = true
        mlxModelLoadStatus = "Caricamento in corso..."
        
        Task { @MainActor in
            print("[AISettingsView] 🚀 Avvio caricamento modello: \(path)")
            let success = await mlxVisionService.loadModel(modelPath: path)
            
            loadingMLXModel = false
            if success {
                mlxModelLoadStatus = "✅ Modello caricato con successo"
                print("[AISettingsView] ✅ Modello caricato con successo")
            } else {
                let errorMsg = mlxVisionService.loadError ?? "Errore sconosciuto"
                mlxModelLoadStatus = "❌ Errore: \(errorMsg)"
                print("[AISettingsView] ❌ Errore nel caricare il modello: \(errorMsg)")
            }
        }
    }

    private func ensureKnowledgeWorkdir() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("PerX/KnowledgeInput", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: support.path) {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        return support
    }
    
    private func copyFilesToWorkdir(_ files: [URL], workdir: URL) throws -> [URL] {
        var result: [URL] = []
        for url in files {
            let dest = workdir.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            result.append(dest)
        }
        return result
    }
    
    private func openKnowledgeFolder() {
        if let url = try? ensureKnowledgeWorkdir() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    
    private func loadModelToOllama(path: String, type: ModelType) {
        loadingModel = type
        modelLoadStatus = "Caricamento in corso..."
        
        Task {
            // Estrai nome modello dal nome file (senza estensione)
            let modelName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            
            let result = await OllamaService.shared.loadModel(modelName: modelName, ggufPath: path)
            
            await MainActor.run {
                loadingModel = nil
                switch result {
                case .success(let name):
                    modelLoadStatus = "✅ Modello \(name) caricato con successo"
                    // Aggiorna il nome modello salvato (nome effettivo in Ollama)
                    textModel = name
                    print("[AISettingsView] 💾 Salvato nome modello testo: \(name)")
                case .failure(let error):
                    modelLoadStatus = "❌ Errore: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func exportFeedback() {
        guard let data = AIFeedbackService.shared.exportFeedbackForFineTuning(format: AIFeedbackService.ExportFormat.json) else {
            return
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "ai_feedback_\(Date().timeIntervalSince1970).json"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? data.write(to: url)
        }
    }
    
    // MARK: - Knowledge Base
    private var knowledgeEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editingDoc == nil ? "Nuovo Documento" : "Modifica Documento")
                    .font(.headline)
                Spacer()
                Button("Chiudi") { showKnowledgeEditor = false }
            }
            TextField("Titolo", text: $knowledgeTitle)
                .textFieldStyle(.roundedBorder)
            TextField("Categoria (definizioni, misure, diagnosi, garanzie)", text: $knowledgeCategory)
                .textFieldStyle(.roundedBorder)
            Stepper("Ordine: \(knowledgeOrder)", value: $knowledgeOrder, in: 0...999)
            Toggle("Attivo", isOn: $knowledgeActive)
            Text("Contenuto")
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: $knowledgeContent)
                .frame(minHeight: 240)
                .border(Color.secondary.opacity(0.3))
            HStack {
                Spacer()
                Button("Salva") {
                    saveKnowledgeDoc()
                    showKnowledgeEditor = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(knowledgeTitle.trimmingCharacters(in: .whitespaces).isEmpty || knowledgeContent.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }
    
    private func startKnowledgeEdit(doc: AIKnowledgeDocument?) {
        editingDoc = doc
        knowledgeTitle = doc?.titolo ?? ""
        knowledgeCategory = doc?.categoria ?? "definizioni"
        knowledgeOrder = Int(doc?.ordine ?? 0)
        knowledgeActive = doc?.attivo ?? true
        knowledgeContent = doc?.contenuto ?? ""
        showKnowledgeEditor = true
    }
    
    private func saveKnowledgeDoc() {
        let doc = editingDoc ?? AIKnowledgeDocument(context: viewContext)
        doc.id = editingDoc?.id ?? UUID()
        doc.titolo = knowledgeTitle
        doc.categoria = knowledgeCategory
        doc.ordine = Int16(knowledgeOrder)
        doc.attivo = knowledgeActive
        doc.contenuto = knowledgeContent
        try? viewContext.save()
    }
}


// MARK: - RAG build manager (background, indipendente dalla view)
final class RAGBuildManager: ObservableObject {
    static let shared = RAGBuildManager()
    
    @Published var isRunning: Bool = false
    @Published var progress: Double = 0
    @Published var status: String = ""
    @Published var errorMessage: String?
    
    private var currentTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "it.perx.ragbuild", qos: .utility)
    
    private init() {}
    
    func startBuild(with files: [URL]) {
        guard !files.isEmpty else { return }
        if isRunning {
            status = "Build già in corso"
            return
        }
        
        isRunning = true
        progress = 0
        errorMessage = nil
        status = "Preparazione file..."
        
        currentTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let scriptPath = try resolveScriptPath()
                let outputURL = try resolveOutputPath()
                let processResult = try await runBuildProcess(
                    scriptPath: scriptPath,
                    files: files,
                    outputURL: outputURL
                )
                await MainActor.run {
                    self.status = processResult
                    self.isRunning = false
                    self.progress = 1.0
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.status = "Errore durante la generazione"
                    self.isRunning = false
                }
            }
        }
    }
    
    private func resolveScriptPath() throws -> String {
        // 1) bundle resource
        if let path = Bundle.main.path(forResource: "build_kb", ofType: "py") {
            return path
        }
        // 2) accanto a questo file in /Services/Knowledge/tools
        let current = URL(fileURLWithPath: #file)
        let candidate = current
            .deletingLastPathComponent() // AISettingsView.swift
            .deletingLastPathComponent() // Settings
            .appendingPathComponent("Knowledge/tools/build_kb.py")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.path
        }
        throw NSError(domain: "RAGBuildManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "build_kb.py non trovato"])
    }
    
    private func resolveOutputPath() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("PerX", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: support.path) {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        
        return support.appendingPathComponent("kb.sqlite")
    }
    
    private func openAIEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Usa la chiave dal backend (Supabase); fallback a UserDefaults per retrocompatibilità
        let tenantKey = TenantAIKeysCache.snapshot().openAIKey
        if env["OPENAI_API_KEY"]?.isEmpty ?? true {
            let key = tenantKey.isEmpty
                ? (UserDefaults.standard.string(forKey: "ai_openai_api_key") ?? "")
                : tenantKey
            if !key.isEmpty { env["OPENAI_API_KEY"] = key }
        }
        if env["OPENAI_BASE_URL"]?.isEmpty ?? true {
            if let base = UserDefaults.standard.string(forKey: "ai_openai_base_url"), !base.isEmpty {
                env["OPENAI_BASE_URL"] = base
            }
        }
        if env["OPENAI_EMBEDDING_MODEL"]?.isEmpty ?? true {
            if let model = UserDefaults.standard.string(forKey: "ai_openai_embedding_model"), !model.isEmpty {
                env["OPENAI_EMBEDDING_MODEL"] = model
            }
        }
        return env
    }
    
    private func runBuildProcess(
        scriptPath: String,
        files: [URL],
        outputURL: URL
    ) async throws -> String {
        let pythonPath = "/usr/bin/python3"
        guard FileManager.default.fileExists(atPath: pythonPath) else {
            throw NSError(domain: "RAGBuildManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Python3 non trovato"])
        }
        
        let args = [scriptPath] + files.map { $0.path } + ["--output", outputURL.path, "--drop-existing"]
        
        return try await withCheckedThrowingContinuation { cont in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = args
            process.environment = openAIEnv()
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty else { return }
                Task { @MainActor in
                    self?.status = line.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty else { return }
                Task { @MainActor in
                    self?.errorMessage = line.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
            process.terminationHandler = { proc in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                let code = proc.terminationStatus
                if code == 0 {
                    cont.resume(returning: "Generazione completata: \(outputURL.lastPathComponent)")
                } else {
                    let err = NSError(domain: "RAGBuildManager", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "Processo terminato con codice \(code)"])
                    cont.resume(throwing: err)
                }
            }
            
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

extension ResourceMonitor.MemoryPressure {
    var description: String {
        switch self {
        case .normal:
            return "Normale"
        case .warning:
            return "Attenzione"
        case .critical:
            return "Critica"
        }
    }
}
