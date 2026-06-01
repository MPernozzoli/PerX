import Foundation

/// Servizio per comunicare con modelli AI locali via API HTTP
class LocalModelService {
    static let shared = LocalModelService()
    
    var isAvailable: Bool {
        return isMultimodalAvailable || isTextAvailable
    }
    
    var isMultimodalAvailable: Bool {
        // Verifica che ci sia un modello configurato
        let model = UserDefaults.standard.string(forKey: "ai_local_multimodal_model") ?? ""
        let ggufPath = UserDefaults.standard.string(forKey: "ai_local_multimodal_gguf_path") ?? ""
        
        let available = !model.isEmpty || !ggufPath.isEmpty
        print("[LocalModelService] 🔍 isMultimodalAvailable: \(available) (model: \(!model.isEmpty), gguf: \(!ggufPath.isEmpty))")
        return available
    }
    
    var isTextAvailable: Bool {
        // Verifica che ci sia un modello configurato
        let model = UserDefaults.standard.string(forKey: "ai_local_text_model") ?? ""
        let ggufPath = UserDefaults.standard.string(forKey: "ai_local_text_gguf_path") ?? ""
        
        let available = !model.isEmpty || !ggufPath.isEmpty
        print("[LocalModelService] 🔍 isTextAvailable: \(available) (model: \(!model.isEmpty), gguf: \(!ggufPath.isEmpty))")
        return available
    }
    
    private var multimodalEndpoint: String {
        "PerX Local Agent"
    }
    
    private var textEndpoint: String {
        "PerX Local Agent"
    }
    
    private var multimodalModel: String {
        // Usa il nome del modello salvato (che dovrebbe essere il nome effettivo in Ollama)
        let value = UserDefaults.standard.string(forKey: "ai_local_multimodal_model") ?? ""
        if value.isEmpty {
            // Fallback: prova a trovare un modello che corrisponde al file .gguf
            let ggufPath = UserDefaults.standard.string(forKey: "ai_local_multimodal_gguf_path") ?? ""
            if !ggufPath.isEmpty {
                let fileName = (ggufPath as NSString).lastPathComponent
                return (fileName as NSString).deletingPathExtension
            }
        }
        return value
    }
    
    private var textModel: String {
        // Usa il nome del modello salvato (che dovrebbe essere il nome effettivo in Ollama)
        let value = UserDefaults.standard.string(forKey: "ai_local_text_model") ?? ""
        if value.isEmpty {
            // Fallback: prova a trovare un modello che corrisponde al file .gguf
            let ggufPath = UserDefaults.standard.string(forKey: "ai_local_text_gguf_path") ?? ""
            if !ggufPath.isEmpty {
                let fileName = (ggufPath as NSString).lastPathComponent
                return (fileName as NSString).deletingPathExtension
            }
        }
        return value
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Esegue un task multimodale (IBM Vulkan)
    func executeMultimodalTask(_ task: AITask) async -> Result<AIResult, AIError> {
        print("[LocalModelService] 🔍 Esecuzione task multimodale")
        print("[LocalModelService] • isMultimodalAvailable: \(isMultimodalAvailable)")
        print("[LocalModelService] • multimodalEndpoint: \(multimodalEndpoint)")
        print("[LocalModelService] • multimodalModel: \(multimodalModel)")
        
        guard isMultimodalAvailable else {
            print("[LocalModelService] ❌ Modello multimodale non disponibile")
            return .failure(.modelUnavailable)
        }
        
        // Verifica che Ollama sia in esecuzione
        print("[LocalModelService] 🔍 Verifica Ollama...")
        let ollamaRunning = await OllamaService.shared.isRunning()
        print("[LocalModelService] • Ollama in esecuzione: \(ollamaRunning)")
        
        if !ollamaRunning {
            print("[LocalModelService] ⚠️ Ollama non in esecuzione, tentativo avvio...")
            // Prova ad avviarlo
            let started = await OllamaService.shared.startOllama()
            print("[LocalModelService] • Ollama avviato: \(started)")
            if !started {
                print("[LocalModelService] ❌ Impossibile avviare Ollama")
                return .failure(.modelUnavailable)
            }
        }
        
        // Verifica che il modello sia caricato e ottieni il nome effettivo
        var actualModelName = await OllamaService.shared.findModelName(multimodalModel)
        
        // Se non trovato, prova a cercare tra tutti i modelli disponibili
        if actualModelName == nil {
            print("[LocalModelService] ⚠️ Modello '\(multimodalModel)' non trovato, cerco tra i modelli disponibili...")
            let allModels = await OllamaService.shared.getLoadedModels()
            
            // Cerca modelli che potrebbero essere multimodali (granite, vision, etc.)
            if let multimodalCandidate = allModels.first(where: { name in
                let lower = name.lowercased()
                return lower.contains("granite") || lower.contains("vision") || lower.contains("multimodal")
            }) {
                actualModelName = multimodalCandidate
                print("[LocalModelService] ✅ Trovato modello multimodale candidato: '\(multimodalCandidate)'")
            } else if allModels.count == 1 {
                // Se c'è solo un modello, usalo
                actualModelName = allModels[0]
                print("[LocalModelService] ⚠️ Solo un modello disponibile, uso quello: '\(allModels[0])'")
            }
        }
        
        let finalModelName = actualModelName ?? multimodalModel
        print("[LocalModelService] • Modello richiesto: '\(multimodalModel)', nome effettivo: '\(finalModelName)'")
        
        let startTime = Date()
        
        do {
            switch task.type {
            case .documentAnalysis, .imageAnalysis:
                var actualModelName = await OllamaService.shared.findModelName(multimodalModel)
                if actualModelName == nil {
                    let allModels = await OllamaService.shared.getLoadedModels()
                    if let candidate = allModels.first(where: { $0.lowercased().contains("granite") || $0.lowercased().contains("vision") }) {
                        actualModelName = candidate
                    } else if allModels.count == 1 {
                        actualModelName = allModels[0]
                    }
                }
                return await analyzeImageOrDocument(task, model: actualModelName ?? multimodalModel, endpoint: multimodalEndpoint)
            case .documentExtraction:
                var actualModelName = await OllamaService.shared.findModelName(multimodalModel)
                if actualModelName == nil {
                    let allModels = await OllamaService.shared.getLoadedModels()
                    if let candidate = allModels.first(where: { $0.lowercased().contains("granite") || $0.lowercased().contains("vision") }) {
                        actualModelName = candidate
                    } else if allModels.count == 1 {
                        actualModelName = allModels[0]
                    }
                }
                return await extractFromDocument(task, model: actualModelName ?? multimodalModel, endpoint: multimodalEndpoint)
            case .chat, .textGeneration:
                // Anche i modelli multimodali possono fare chat/testo
                // Usa il nome effettivo del modello trovato in Ollama
                var actualModelName = await OllamaService.shared.findModelName(multimodalModel)
                if actualModelName == nil {
                    let allModels = await OllamaService.shared.getLoadedModels()
                    if let candidate = allModels.first(where: { $0.lowercased().contains("granite") || $0.lowercased().contains("vision") }) {
                        actualModelName = candidate
                    } else if allModels.count == 1 {
                        actualModelName = allModels[0]
                    }
                }
                return await generateText(task, model: actualModelName ?? multimodalModel, endpoint: multimodalEndpoint, provider: .localMultimodal)
            default:
                return .failure(.invalidInput)
            }
        } catch {
            let processingTime = Date().timeIntervalSince(startTime)
            return .failure(.processingError(error.localizedDescription))
        }
    }
    
    /// Esegue un task di testo (Microsoft Phi-3/4)
    func executeTextTask(_ task: AITask) async -> Result<AIResult, AIError> {
        print("[LocalModelService] 🔍 Esecuzione task testo")
        print("[LocalModelService] • isTextAvailable: \(isTextAvailable)")
        print("[LocalModelService] • textEndpoint: \(textEndpoint)")
        print("[LocalModelService] • textModel: \(textModel)")
        
        guard isTextAvailable else {
            print("[LocalModelService] ❌ Modello testo non disponibile")
            return .failure(.modelUnavailable)
        }
        
        // Verifica che Ollama sia in esecuzione
        print("[LocalModelService] 🔍 Verifica Ollama...")
        let ollamaRunning = await OllamaService.shared.isRunning()
        print("[LocalModelService] • Ollama in esecuzione: \(ollamaRunning)")
        
        if !ollamaRunning {
            print("[LocalModelService] ⚠️ Ollama non in esecuzione, tentativo avvio...")
            // Prova ad avviarlo
            let started = await OllamaService.shared.startOllama()
            print("[LocalModelService] • Ollama avviato: \(started)")
            if !started {
                print("[LocalModelService] ❌ Impossibile avviare Ollama")
                return .failure(.modelUnavailable)
            }
        }
        
        // Verifica che il modello sia caricato e ottieni il nome effettivo
        var actualModelName = await OllamaService.shared.findModelName(textModel)
        
        // Se non trovato, prova a cercare tra tutti i modelli disponibili
        if actualModelName == nil {
            print("[LocalModelService] ⚠️ Modello '\(textModel)' non trovato, cerco tra i modelli disponibili...")
            let allModels = await OllamaService.shared.getLoadedModels()
            
            // Cerca modelli che potrebbero essere di testo (phi, llama, mistral, etc.)
            if let textCandidate = allModels.first(where: { name in
                let lower = name.lowercased()
                return lower.contains("phi") || lower.contains("llama") || lower.contains("mistral") || 
                       lower.contains("qwen") || lower.contains("gemma") || (!lower.contains("vision") && !lower.contains("granite"))
            }) {
                actualModelName = textCandidate
                print("[LocalModelService] ✅ Trovato modello testo candidato: '\(textCandidate)'")
            } else if allModels.count == 1 {
                // Se c'è solo un modello, usalo
                actualModelName = allModels[0]
                print("[LocalModelService] ⚠️ Solo un modello disponibile, uso quello: '\(allModels[0])'")
            }
        }
        
        let finalModelName = actualModelName ?? textModel
        print("[LocalModelService] • Modello richiesto: '\(textModel)', nome effettivo: '\(finalModelName)'")
        
        let startTime = Date()
        
        do {
            switch task.type {
            case .textGeneration, .chat:
                // Usa il nome effettivo del modello trovato in Ollama
                var actualModelName = await OllamaService.shared.findModelName(textModel)
                if actualModelName == nil {
                    let allModels = await OllamaService.shared.getLoadedModels()
                    if let candidate = allModels.first(where: { $0.lowercased().contains("phi") || $0.lowercased().contains("llama") || (!$0.lowercased().contains("vision") && !$0.lowercased().contains("granite")) }) {
                        actualModelName = candidate
                    } else if allModels.count == 1 {
                        actualModelName = allModels[0]
                    }
                }
                return await generateText(task, model: actualModelName ?? textModel, endpoint: textEndpoint, provider: .localText)
            case .textAnalysis:
                var actualModelName = await OllamaService.shared.findModelName(textModel)
                if actualModelName == nil {
                    let allModels = await OllamaService.shared.getLoadedModels()
                    if let candidate = allModels.first(where: { $0.lowercased().contains("phi") || (!$0.lowercased().contains("vision") && !$0.lowercased().contains("granite")) }) {
                        actualModelName = candidate
                    } else if allModels.count == 1 {
                        actualModelName = allModels[0]
                    }
                }
                return await analyzeText(task, model: actualModelName ?? textModel, endpoint: textEndpoint)
            default:
                return .failure(.invalidInput)
            }
        } catch {
            let processingTime = Date().timeIntervalSince(startTime)
            return .failure(.processingError(error.localizedDescription))
        }
    }
    
    // MARK: - Private Implementation
    
    private func analyzeImageOrDocument(_ task: AITask, model: String, endpoint: String) async -> Result<AIResult, AIError> {
        // Supporta sia "filePath" che "imagePath"
        let filePath = task.parameters["filePath"]?.value as? String ?? 
                       task.parameters["imagePath"]?.value as? String
        
        guard let filePath = filePath else {
            return .failure(.invalidInput)
        }
        
        // Prepara il prompt (usa prompt personalizzato se presente, altrimenti usa quello predefinito)
        let customPrompt = task.parameters["prompt"]?.value as? String
        let sinistroID = task.parameters["sinistroID"]?.value as? String ?? ""
        let prompt: String
        if let custom = customPrompt, !custom.isEmpty {
            prompt = custom
        } else {
            prompt = buildDocumentAnalysisPrompt(sinistroID: sinistroID)
        }
        
        do {
            let responseText = try await LocalAIService.shared.analyzeImageWithLocalVision(
                imagePath: filePath,
                prompt: prompt
            )
            let result = AIResult.success(
                taskID: task.id,
                provider: .localMultimodal,
                result: responseText,
                metadata: ["model": model, "endpoint": endpoint]
            )
            return .success(result)
        } catch {
            if (error as NSError).code == NSURLErrorTimedOut {
                return .failure(.timeout)
            }
            return .failure(.networkError(error.localizedDescription))
        }
    }
    
    private func extractFromDocument(_ task: AITask, model: String, endpoint: String) async -> Result<AIResult, AIError> {
        // Simile ad analyzeImageOrDocument ma con prompt diverso
        return await analyzeImageOrDocument(task, model: model, endpoint: endpoint)
    }
    
    private func generateText(_ task: AITask, model: String, endpoint: String, provider: AIModelProvider = .localText) async -> Result<AIResult, AIError> {
        guard let prompt = resolvePrompt(for: task) else {
            print("[LocalModelService] ❌ Prompt mancante nel task")
            return .failure(.invalidInput)
        }
        
        // Controlla se lo streaming è richiesto
        let useStreaming = task.parameters["stream"]?.value as? Bool ?? false
        
        if useStreaming {
            return await generateTextStreaming(task: task, model: model, endpoint: endpoint, prompt: prompt, provider: provider)
        } else {
            return await generateTextNonStreaming(task, model: model, endpoint: endpoint, prompt: prompt, provider: provider)
        }
    }
    
    private func generateTextNonStreaming(_ task: AITask, model: String, endpoint: String, prompt: String, provider: AIModelProvider) async -> Result<AIResult, AIError> {
        print("[LocalModelService] 📤 Invio richiesta a Ollama (non-streaming)")
        print("[LocalModelService] • Endpoint: \(endpoint)")
        print("[LocalModelService] • Modello: \(model)")
        print("[LocalModelService] • Prompt: \(prompt.prefix(100))...")

        do {
            print("[LocalModelService] ⏳ Attesa risposta...")
            let responseText = try await LocalAIService.shared.generateLocalText(
                prompt: prompt,
                model: model
            )
            print("[LocalModelService] ✅ Risposta valida: \(responseText.prefix(100))...")
            let result = AIResult.success(
                taskID: task.id,
                provider: provider,
                result: responseText,
                metadata: ["model": model, "endpoint": endpoint]
            )
            return .success(result)
        } catch {
            print("[LocalModelService] ❌ Errore network: \(error.localizedDescription)")
            if (error as NSError).code == NSURLErrorTimedOut {
                return .failure(.timeout)
            }
            if (error as NSError).code == NSURLErrorCannotConnectToHost {
                return .failure(.networkError("Impossibile connettersi a Ollama. Verifica che sia in esecuzione."))
            }
            return .failure(.networkError(error.localizedDescription))
        }
    }
    
    private func generateTextStreaming(task: AITask, model: String, endpoint: String, prompt: String, provider: AIModelProvider) async -> Result<AIResult, AIError> {
        print("[LocalModelService] 📤 Invio richiesta a Ollama (streaming)")
        print("[LocalModelService] • Endpoint: \(endpoint)")
        print("[LocalModelService] • Modello: \(model)")
        print("[LocalModelService] • Prompt: \(prompt.prefix(100))...")
        
        // Ottieni il callback di streaming da AIManager
        let streamCallback = await MainActor.run {
            return AIManager.shared.getStreamCallback(for: task.id)
        }
        
        do {
            print("[LocalModelService] ⏳ Attesa risposta streaming...")
            print("[LocalModelService] • Lunghezza prompt: \(prompt.count) caratteri")
            let fullResponse = try await LocalAIService.shared.streamLocalText(
                prompt: prompt,
                model: model
            ) { token in
                Task { @MainActor in
                    streamCallback?(token)
                }
            }
            
            print("[LocalModelService] ✅ Risposta streaming completata: \(fullResponse.prefix(100))...")
            
            let result = AIResult.success(
                taskID: task.id,
                provider: provider,
                result: fullResponse,
                metadata: ["model": model, "endpoint": endpoint, "streamed": true]
            )
            return .success(result)
        } catch {
            print("[LocalModelService] ❌ Errore network streaming: \(error.localizedDescription)")
            if (error as NSError).code == NSURLErrorTimedOut {
                return .failure(.timeout)
            }
            if (error as NSError).code == NSURLErrorCannotConnectToHost {
                return .failure(.networkError("Impossibile connettersi a Ollama. Verifica che sia in esecuzione."))
            }
            return .failure(.networkError(error.localizedDescription))
        }
    }
    
    private func analyzeText(_ task: AITask, model: String, endpoint: String) async -> Result<AIResult, AIError> {
        // Usa generateText con prompt di analisi
        return await generateText(task, model: model, endpoint: endpoint, provider: .localText)
    }
    
    /// Risolve il prompt finale applicando il template RAG se richiesto
    private func resolvePrompt(for task: AITask) -> String? {
        if task.requiresKnowledge || !task.knowledgeChunks.isEmpty {
            return buildPerXPrompt(from: task)
        }
        
        if let prompt = task.parameters["prompt"]?.value as? String, !prompt.isEmpty {
            return prompt
        }
        
        if let input = task.parameters["inputText"]?.value as? String, !input.isEmpty {
            return input
        }
        
        if let text = task.parameters["text"]?.value as? String, !text.isEmpty {
            return text
        }
        
        return nil
    }
    
    // MARK: - Prompt Building
    
    private func buildDocumentAnalysisPrompt(sinistroID: String) -> String {
        var prompt = "Analizza questo documento peritale"
        if !sinistroID.isEmpty {
            prompt += " relativo al sinistro \(sinistroID)"
        }
        prompt += ". Estrai informazioni rilevanti come: tipo di danno, importi, date, descrizioni tecniche, e qualsiasi altra informazione utile per la gestione del sinistro."
        return prompt
    }
}
