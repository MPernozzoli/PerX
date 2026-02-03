import SwiftUI
import AppKit

struct AITestChatView: View {
    @State private var selectedProvider: AIModelProvider = .localText
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isGenerating = false
    @State private var ollamaStatus: OllamaStatus = .checking
    @State private var selectedFiles: [URL] = []
    
    @StateObject private var mlxVisionService = MLXVisionService.shared
    
    enum OllamaStatus {
        case checking
        case running
        case notRunning
        case error(String)
    }
    
    struct ChatMessage: Identifiable {
        var id = UUID()
        var text: String
        let isUser: Bool
        let provider: AIModelProvider?
        let timestamp: Date
        let attachedFiles: [URL]?
        
        init(text: String, isUser: Bool, provider: AIModelProvider? = nil, attachedFiles: [URL]? = nil) {
            self.text = text
            self.isUser = isUser
            self.provider = provider
            self.timestamp = Date()
            self.attachedFiles = attachedFiles
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Selettore provider
            HStack {
                Text("Provider:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $selectedProvider) {
                    Text("Modello Testo (Phi)").tag(AIModelProvider.localText)
                    Text("Modello Multimodale (Llama)").tag(AIModelProvider.localMultimodal)
                    Text("Apple Intelligence").tag(AIModelProvider.appleIntelligence)
                    Text("OpenAI Cloud").tag(AIModelProvider.cloudOpenAI)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
                
                Spacer()
                
                // Status Ollama per modello testo locale
                if selectedProvider == .localText {
                    OllamaStatusView(status: $ollamaStatus)
                }
                
                // Status modello multimodale (MLX)
                if selectedProvider == .localMultimodal {
                    ModelStatusView(service: mlxVisionService)
                }
            }
            
            Divider()
            
            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if messages.isEmpty {
                            Text("Inizia a chattare per testare il modello selezionato")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(messages) { message in
                                ChatMessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .frame(height: 300)
                .background(Color(.textBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .onChange(of: messages.count) { _ in
                    // Scroll automatico all'ultimo messaggio
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: messages.last?.text) { _ in
                    // Scroll automatico quando il testo cambia (streaming)
                    if let lastMessage = messages.last, !lastMessage.isUser {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // File selezionati
            if !selectedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedFiles.indices, id: \.self) { index in
                            HStack(spacing: 4) {
                                Image(systemName: fileIcon(for: selectedFiles[index]))
                                Text(selectedFiles[index].lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)
                                
                                Button(action: {
                                    selectedFiles.remove(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(6)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 40)
            }
            
            // Input area
            HStack(spacing: 8) {
                // Pulsante per selezionare file (per modelli multimodali e OpenAI)
                if selectedProvider == .localMultimodal || selectedProvider == .cloudOpenAI {
                    Button(action: selectFiles) {
                        Image(systemName: "paperclip")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isGenerating)
                }
                
                TextField("Scrivi un messaggio...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .disabled(isGenerating)
                
                Button(action: sendMessage) {
                    if isGenerating {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled((messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedFiles.isEmpty) || isGenerating)
            }
        }
        .padding()
        .onAppear {
            checkOllamaStatus()
        }
        .onChange(of: selectedProvider) { _ in
            if selectedProvider == .localText {
                checkOllamaStatus()
            }
        }
    }
    
    // MARK: - Model Status View
    
    struct ModelStatusView: View {
        @ObservedObject var service: MLXVisionService
        
        var body: some View {
            HStack(spacing: 6) {
                if service.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Caricamento... \(Int(service.loadProgress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if service.isModelLoaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Modello pronto")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else if let error = service.loadError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Errore")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("Non caricato")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
        }
    }
    
    private func checkOllamaStatus() {
        ollamaStatus = .checking
        Task {
            let isRunning = await OllamaService.shared.isRunning()
            await MainActor.run {
                ollamaStatus = isRunning ? .running : .notRunning
            }
            
            // Se non è in esecuzione, prova ad avviarlo
            if !isRunning {
                let started = await OllamaService.shared.startOllama()
                await MainActor.run {
                    ollamaStatus = started ? .running : .error("Impossibile avviare Ollama")
                }
            }
        }
    }
    
    private func selectFiles() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowedContentTypes = [
            .image, .jpeg, .png, .gif, .bmp, .heic,
            .pdf, .text, .plainText, .rtf
        ]
        
        if openPanel.runModal() == .OK {
            selectedFiles = openPanel.urls
        }
    }
    
    private func fileIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "bmp", "heic", "heif"].contains(ext) {
            return "photo"
        } else if ext == "pdf" {
            return "doc.text"
        } else {
            return "doc"
        }
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasFiles = !selectedFiles.isEmpty
        
        guard !text.isEmpty || hasFiles else { return }
        
        // Aggiungi messaggio utente
        let userMessage = ChatMessage(
            text: text.isEmpty ? "Analizza i file allegati" : text,
            isUser: true,
            attachedFiles: hasFiles ? selectedFiles : nil
        )
        messages.append(userMessage)
        
        let filesToSend = selectedFiles
        messageText = ""
        selectedFiles = []
        isGenerating = true
        
        // Crea messaggio placeholder per la risposta
        var responseMessage = ChatMessage(text: "", isUser: false, provider: selectedProvider)
        messages.append(responseMessage)
        let responseIndex = messages.count - 1
        
        Task { @MainActor in
            // Determina se ci sono immagini tra i file allegati
            let imageFiles = filesToSend.filter { fileURL in
                let ext = fileURL.pathExtension.lowercased()
                return ["jpg", "jpeg", "png", "gif", "bmp", "heic", "heif"].contains(ext)
            }
            let hasImages = !imageFiles.isEmpty
            
            // Logica per determinare il tipo di task
            // Se ci sono immagini E il provider supporta immagini, usa imageAnalysis
            if hasImages && (selectedProvider == .localMultimodal || selectedProvider == .cloudOpenAI) {
                print("[AITestChatView] 🔍 Creazione task con immagini: tipo=imageAnalysis, provider=\(selectedProvider.rawValue), immagini=\(imageFiles.count), prompt='\(text)'")
                
                if selectedProvider == .localMultimodal {
                    print("[AITestChatView] • MLXVisionService.serviceAvailable: \(MLXVisionService.shared.serviceAvailable)")
                    print("[AITestChatView] • MLXVisionService.isModelLoaded: \(MLXVisionService.shared.isModelLoaded)")
                }
                
                // Analizza ogni immagine separatamente
                for imageURL in imageFiles {
                    let imagePath = imageURL.path
                    let prompt = text.isEmpty ? "Descrivi questa immagine in dettaglio" : text
                    
                    print("[AITestChatView] 📸 Analisi immagine: \(imageURL.lastPathComponent)")
                    print("[AITestChatView] • imagePath: \(imagePath)")
                    print("[AITestChatView] • File esiste: \(FileManager.default.fileExists(atPath: imagePath))")
                    
                    let task = AITask(
                        type: .imageAnalysis,
                        priority: .primary,
                        preferredProvider: selectedProvider, // Usa il provider selezionato (localMultimodal o cloudOpenAI)
                        parameters: [
                            "imagePath": AnyCodable(imagePath), // Supportato da entrambi i provider
                            "prompt": AnyCodable(prompt)
                        ]
                    )
                    
                    print("[AITestChatView] ➡️ Enqueue task: type=\(task.type), preferredProvider=\(task.preferredProvider?.rawValue ?? "nil"), parameters.keys=\(task.parameters.keys)")
                    
                    await AIManager.shared.enqueue(
                        task,
                        completion: { result in
                            print("[AITestChatView] 📥 Risultato ricevuto: success=\(result.success), provider=\(result.provider.rawValue)")
                            if !result.success {
                                print("[AITestChatView] ❌ Errore: \(result.error?.localizedDescription ?? "sconosciuto")")
                            }
                            if result.success, let response = result.result?.value as? String {
                                // Aggiungi la risposta per questa immagine
                                let fileName = imageURL.lastPathComponent
                                let imageResponse = "📎 \(fileName):\n\(response)"
                                
                                if responseIndex < messages.count {
                                    if messages[responseIndex].text.isEmpty {
                                        messages[responseIndex].text = imageResponse
                                    } else {
                                        messages[responseIndex].text += "\n\n\(imageResponse)"
                                    }
                                }
                            } else {
                                let errorMsg = result.error?.localizedDescription ?? "Errore sconosciuto"
                                let fileName = imageURL.lastPathComponent
                                let errorResponse = "📎 \(fileName): Errore - \(errorMsg)"
                                
                                if responseIndex < messages.count {
                                    if messages[responseIndex].text.isEmpty {
                                        messages[responseIndex].text = errorResponse
                                    } else {
                                        messages[responseIndex].text += "\n\n\(errorResponse)"
                                    }
                                }
                            }
                            
                            // Se è l'ultima immagine, termina
                            if imageURL == imageFiles.last {
                                isGenerating = false
                            }
                        }
                    )
                }
            } else if hasFiles && (selectedProvider == .localMultimodal || selectedProvider == .cloudOpenAI) {
                // File non-immagine con provider multimodale/OpenAI: usa documentAnalysis
                print("[AITestChatView] 📄 Creazione task: tipo=documentAnalysis, provider=\(selectedProvider.rawValue), file=\(filesToSend.count)")
                
                for fileURL in filesToSend {
                    let filePath = fileURL.path
                    let prompt = text.isEmpty ? "Analizza questo documento" : text
                    
                    let task = AITask(
                        type: .documentAnalysis,
                        priority: .primary,
                        preferredProvider: selectedProvider, // Usa il provider selezionato
                        parameters: [
                            "filePath": AnyCodable(filePath),
                            "prompt": AnyCodable(prompt)
                        ]
                    )
                    
                    await AIManager.shared.enqueue(
                        task,
                        completion: { result in
                            if result.success, let response = result.result?.value as? String {
                                let fileName = fileURL.lastPathComponent
                                let fileResponse = "📎 \(fileName):\n\(response)"
                                
                                if responseIndex < messages.count {
                                    if messages[responseIndex].text.isEmpty {
                                        messages[responseIndex].text = fileResponse
                                    } else {
                                        messages[responseIndex].text += "\n\n\(fileResponse)"
                                    }
                                }
                            } else {
                                let errorMsg = result.error?.localizedDescription ?? "Errore sconosciuto"
                                let fileName = fileURL.lastPathComponent
                                let errorResponse = "📎 \(fileName): Errore - \(errorMsg)"
                                
                                if responseIndex < messages.count {
                                    if messages[responseIndex].text.isEmpty {
                                        messages[responseIndex].text = errorResponse
                                    } else {
                                        messages[responseIndex].text += "\n\n\(errorResponse)"
                                    }
                                }
                            }
                            
                            if fileURL == filesToSend.last {
                                isGenerating = false
                            }
                        }
                    )
                }
            } else {
                // Chat normale (testo puro) con streaming
                print("[AITestChatView] 💬 Creazione task chat testuale: tipo=chat, provider=\(selectedProvider)")
                
                let task = AITask(
                    type: .chat,
                    priority: .primary,
                    preferredProvider: selectedProvider,
                    personality: selectedProvider == .appleIntelligence ? .elettra : nil,
                    parameters: [
                        "prompt": AnyCodable(text.isEmpty ? "Ciao" : text),
                        "stream": AnyCodable(true)
                    ],
                    requiresKnowledge: true,
                    knowledgeDomains: [.generico],
                    maxKnowledgeChunks: 6
                )
                
                AIManager.shared.enqueue(
                    task,
                    completion: { result in
                        isGenerating = false
                        
                        // Se il provider non streamma, completa il messaggio con il testo finale
                        if result.success,
                           responseIndex < messages.count,
                           messages[responseIndex].text.isEmpty,
                           let responseText = result.result?.value as? String {
                            messages[responseIndex].text = responseText
                        }
                        
                        if !result.success {
                            // Sostituisci il messaggio placeholder con l'errore
                            if responseIndex < messages.count {
                                let errorMsg = result.error?.localizedDescription ?? "Errore sconosciuto"
                                messages[responseIndex] = ChatMessage(text: "Errore: \(errorMsg)", isUser: false, provider: result.provider)
                            }
                        }
                    },
                    streamCallback: { token in
                        // Aggiorna il messaggio in tempo reale
                        if responseIndex < messages.count {
                            messages[responseIndex].text += token
                        }
                    }
                )
            }
        }
    }
}

struct ChatMessageRow: View {
    let message: AITestChatView.ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Mostra file allegati se presenti
                if let files = message.attachedFiles, !files.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(files, id: \.self) { fileURL in
                                VStack(spacing: 4) {
                                    if let nsImage = NSImage(contentsOf: fileURL) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 100, height: 100)
                                            .cornerRadius(4)
                                    } else {
                                        Image(systemName: fileIcon(for: fileURL))
                                            .font(.largeTitle)
                                            .foregroundColor(.secondary)
                                            .frame(width: 100, height: 100)
                                            .background(Color(.controlBackgroundColor))
                                            .cornerRadius(4)
                                    }
                                    
                                    Text(fileURL.lastPathComponent)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .frame(width: 100)
                                }
                            }
                        }
                        .padding(4)
                    }
                }
                
                if !message.text.isEmpty {
                    Text(message.text)
                        .padding(10)
                        .background(message.isUser ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                
                if let provider = message.provider {
                    Text(providerName(provider))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: 400, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser {
                Spacer()
            }
        }
    }
    
    private func fileIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "bmp", "heic", "heif"].contains(ext) {
            return "photo"
        } else if ext == "pdf" {
            return "doc.text"
        } else {
            return "doc"
        }
    }
    
    private func providerName(_ provider: AIModelProvider) -> String {
        switch provider {
        case .localText: return "Phi-3/4"
        case .localMultimodal: return "Llama 3.1 8B Vision"
        case .appleIntelligence: return "Apple Intelligence"
        case .cloudOpenAI: return "OpenAI"
        }
    }
}

struct OllamaStatusView: View {
    @Binding var status: AITestChatView.OllamaStatus
    
    var body: some View {
        HStack(spacing: 4) {
            switch status {
            case .checking:
                ProgressView()
                    .scaleEffect(0.6)
                Text("Verifica...")
                    .font(.caption2)
            case .running:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Ollama attivo")
                    .font(.caption2)
                    .foregroundColor(.green)
            case .notRunning:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.orange)
                Text("Ollama non attivo")
                    .font(.caption2)
                    .foregroundColor(.orange)
            case .error(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(msg)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }
}

