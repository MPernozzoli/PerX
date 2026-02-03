import Foundation

/// Servizio per comunicare con OpenAI come fallback cloud
class CloudAIService {
    static let shared = CloudAIService()
    
    var isAvailable: Bool {
        return !apiKey.isEmpty
    }
    
    private var apiKey: String {
        // Usa Keychain per sicurezza in produzione
        if let key = UserDefaults.standard.string(forKey: "ai_openai_api_key"), !key.isEmpty {
            return key
        }
        return ""
    }
    
    private var baseURL: String {
        UserDefaults.standard.string(forKey: "ai_openai_base_url") ?? "https://api.openai.com/v1"
    }
    
    private var model: String {
        UserDefaults.standard.string(forKey: "ai_openai_model") ?? "gpt-4o"
    }
    
    private var timeout: TimeInterval {
        let value = UserDefaults.standard.double(forKey: "ai_openai_timeout")
        return value > 0 ? value : 30.0
    }
    
    private let session: URLSession
    private var requestCount: Int = 0
    private var lastRequestTime: Date?
    private let rateLimitDelay: TimeInterval = 1.0 // Minimo 1 secondo tra richieste
    
    private init() {
        let timeoutValue: TimeInterval = {
            let value = UserDefaults.standard.double(forKey: "ai_openai_timeout")
            return value > 0 ? value : 30.0
        }()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutValue
        config.timeoutIntervalForResource = timeoutValue * 2
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// Esegue un task usando OpenAI
    func executeTask(_ task: AITask) async -> Result<AIResult, AIError> {
        guard isAvailable else {
            return .failure(.modelUnavailable)
        }
        
        // Rate limiting
        if let lastTime = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastTime)
            if timeSinceLastRequest < rateLimitDelay {
                try? await Task.sleep(nanoseconds: UInt64((rateLimitDelay - timeSinceLastRequest) * 1_000_000_000))
            }
        }
        
        let startTime = Date()
        lastRequestTime = Date()
        requestCount += 1
        
        do {
            let prompt = await buildPrompt(for: task)
            let result = await callOpenAI(prompt: prompt, task: task)
            let processingTime = Date().timeIntervalSince(startTime)
            
            switch result {
            case .success(let text):
                let aiResult = AIResult.success(
                    taskID: task.id,
                    provider: .cloudOpenAI,
                    result: text,
                    metadata: [
                        "model": model,
                        "requestCount": requestCount,
                        "processingTime": processingTime
                    ],
                    processingTime: processingTime
                )
                return .success(aiResult)
            case .failure(let error):
                return .failure(error)
            }
        } catch {
            let processingTime = Date().timeIntervalSince(startTime)
            return .failure(.processingError(error.localizedDescription))
        }
    }
    
    /// Esegue un task in modalità streaming se possibile
    func executeTaskStreaming(
        _ task: AITask,
        streamCallback: @escaping (String) -> Void
    ) async -> Result<AIResult, AIError> {
        guard isAvailable else {
            return .failure(.modelUnavailable)
        }
        
        // Rate limiting
        if let lastTime = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastTime)
            if timeSinceLastRequest < rateLimitDelay {
                try? await Task.sleep(nanoseconds: UInt64((rateLimitDelay - timeSinceLastRequest) * 1_000_000_000))
            }
        }
        
        let startTime = Date()
        lastRequestTime = Date()
        requestCount += 1
        
        do {
            let prompt = await buildPrompt(for: task)
            let result = await callOpenAIStreaming(
                prompt: prompt,
                task: task,
                streamCallback: streamCallback
            )
            let processingTime = Date().timeIntervalSince(startTime)
            
            switch result {
            case .success(let text):
                let aiResult = AIResult.success(
                    taskID: task.id,
                    provider: .cloudOpenAI,
                    result: text,
                    metadata: [
                        "model": model,
                        "requestCount": requestCount,
                        "processingTime": processingTime,
                        "streamed": true
                    ],
                    processingTime: processingTime
                )
                return .success(aiResult)
            case .failure(let error):
                return .failure(error)
            }
        } catch {
            let processingTime = Date().timeIntervalSince(startTime)
            return .failure(.processingError(error.localizedDescription))
        }
    }
    
    // MARK: - Private Implementation
    
    private func buildPrompt(for task: AITask) async -> String {
        if task.requiresKnowledge || !task.knowledgeChunks.isEmpty {
            return buildPerXPrompt(from: task)
        }
        
        let personalityService = AIPersonalityService.shared
        let personality = task.personality ?? personalityService.selectPersonality(for: task.type)
        
        var basePrompt = ""
        
        switch task.type {
        case .emailSummary:
            if let subject = task.parameters["subject"]?.value as? String,
               let body = task.parameters["body"]?.value as? String {
                basePrompt = "Riassumi questa email:\nOggetto: \(subject)\nCorpo: \(body)"
            }
        case .documentAnalysis, .imageAnalysis:
            // Per documentAnalysis, usa SEMPRE il prompt dai parametri se presente
            // (può essere per autotagging o per analisi approfondita)
            if let prompt = task.parameters["prompt"]?.value as? String {
                basePrompt = prompt
            } else if let filePath = task.parameters["filePath"]?.value as? String ?? task.parameters["imagePath"]?.value as? String {
                // Fallback solo se c'è un filePath singolo e non c'è prompt esplicito
                basePrompt = "Analizza questa immagine in dettaglio"
            } else {
                // Se ci sono immagini in array ma nessun prompt, usa default
                basePrompt = "Analizza questa immagine in dettaglio"
            }
        case .textGeneration, .chat:
            if let prompt = task.parameters["prompt"]?.value as? String {
                basePrompt = prompt
            }
        default:
            basePrompt = "Esegui il task richiesto"
        }
        
        return personalityService.buildPrompt(
            basePrompt: basePrompt,
            personality: personality,
            context: nil,
            taskType: task.type
        )
    }
    
    /// Estrae i percorsi delle immagini dal task
    private func extractImagePaths(from task: AITask) -> [String] {
        var imagePaths: [String] = []
        
        // Supporta sia "imagePath" che "filePath" per singole immagini
        if let imagePath = task.parameters["imagePath"]?.value as? String {
            imagePaths.append(imagePath)
        } else if let filePath = task.parameters["filePath"]?.value as? String {
            imagePaths.append(filePath)
        }
        
        // Supporta anche array di immagini (per chat con multiple immagini)
        if let images = task.parameters["images"]?.value as? [String] {
            imagePaths.append(contentsOf: images)
        }
        
        return imagePaths
    }
    
    /// Converte un'immagine in base64 per OpenAI
    private func encodeImageToBase64(imagePath: String) -> String? {
        // Usa FileService per gestire correttamente i security scoped resources
        guard let imageData = FileService.shared.readFileData(at: imagePath) else {
            print("[CloudAIService] ⚠️ Impossibile leggere file con security scoped access: \(imagePath)")
            // Fallback: prova senza security scoped (per file nella directory principale)
            if let fallbackData = try? Data(contentsOf: URL(fileURLWithPath: imagePath)) {
                return fallbackData.base64EncodedString()
            }
            return nil
        }
        return imageData.base64EncodedString()
    }
    
    private func callOpenAI(prompt: String, task: AITask) async -> Result<String, AIError> {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            return .failure(.networkError("URL non valido"))
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Estrai immagini se presenti
        let imagePaths = extractImagePaths(from: task)
        let hasImages = !imagePaths.isEmpty
        
        // Costruisci il contenuto del messaggio utente
        var userContent: Any
        
        if hasImages {
            // Formato multimodale: array di contenuti (testo + immagini)
            var contentArray: [[String: Any]] = []
            
            // Aggiungi il testo se presente
            if !prompt.isEmpty {
                contentArray.append([
                    "type": "text",
                    "text": prompt
                ])
            }
            
            // Aggiungi le immagini
            for imagePath in imagePaths {
                print("[CloudAIService] 📸 Elaborazione immagine: \(imagePath)")
                guard let base64Image = encodeImageToBase64(imagePath: imagePath) else {
                    print("[CloudAIService] ⚠️ Impossibile codificare immagine: \(imagePath)")
                    continue
                }
                
                print("[CloudAIService] ✅ Immagine codificata in base64: \(base64Image.prefix(50))... (\(base64Image.count) caratteri)")
                
                // Determina il tipo MIME basato sull'estensione
                let ext = (imagePath as NSString).pathExtension.lowercased()
                let mimeType: String
                switch ext {
                case "jpg", "jpeg":
                    mimeType = "image/jpeg"
                case "png":
                    mimeType = "image/png"
                case "gif":
                    mimeType = "image/gif"
                case "webp":
                    mimeType = "image/webp"
                case "heic", "heif":
                    mimeType = "image/heic"
                default:
                    mimeType = "image/jpeg" // Default
                }
                
                print("[CloudAIService] 📎 Tipo MIME: \(mimeType)")
                
                contentArray.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:\(mimeType);base64,\(base64Image)"
                    ]
                ])
            }
            
            print("[CloudAIService] 📊 Contenuto array creato: \(contentArray.count) elementi (testo: \(!prompt.isEmpty ? 1 : 0), immagini: \(imagePaths.count))")
            
            userContent = contentArray
        } else {
            // Solo testo
            userContent = prompt
        }
        
        // Verifica che il modello supporti immagini (gpt-4o, gpt-4-vision, gpt-4-turbo supportano immagini)
        let modelSupportsImages = model.contains("gpt-4") || model.contains("vision")
        if hasImages && !modelSupportsImages {
            print("[CloudAIService] ⚠️ Il modello '\(model)' potrebbe non supportare immagini. Usa 'gpt-4o' o 'gpt-4-vision-preview'")
        }
        
        // Estrai parametri opzionali dal task
        let maxTokens = (task.parameters["max_tokens"]?.value as? Int) ?? (hasImages ? 4000 : 2000)
        let responseFormat = task.parameters["response_format"]?.value as? [String: String]
        
        // Usa systemPrompt dai parameters se presente, altrimenti usa il default
        let systemMessage: String
        if let customSystemPrompt = task.parameters["systemPrompt"]?.value as? String {
            systemMessage = customSystemPrompt
        } else if responseFormat?["type"] == "json_object" {
            systemMessage = "Sei un assistente AI per un'azienda di perizie assicurative in Italia. Rispondi sempre in italiano in formato JSON."
        } else {
            systemMessage = "Sei un assistente AI per un'azienda di perizie assicurative in Italia. Rispondi sempre in italiano."
        }
        
        var payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemMessage],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.7,
            "max_tokens": maxTokens
        ]
        
        // Aggiungi response_format se specificato
        if let responseFormat = responseFormat {
            payload["response_format"] = responseFormat
            print("[CloudAIService] 📋 Response format: \(responseFormat)")
        }
        
        print("[CloudAIService] 📤 Invio richiesta a OpenAI: model=\(model), hasImages=\(hasImages)")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            print("[CloudAIService] ✅ Payload JSON creato: \(payload.count) chiavi")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.networkError("Risposta non valida"))
            }
            
            if httpResponse.statusCode == 429 {
                return .failure(.rateLimitExceeded)
            }
            
            guard httpResponse.statusCode == 200 else {
                print("[CloudAIService] ❌ Status code non 200: \(httpResponse.statusCode)")
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("[CloudAIService] 📄 Error data: \(errorData)")
                    if let error = errorData["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        print("[CloudAIService] ❌ Errore OpenAI: \(message)")
                        return .failure(.networkError(message))
                    }
                }
                if let responseString = String(data: data, encoding: .utf8) {
                    print("[CloudAIService] 📄 Response body: \(responseString.prefix(500))")
                }
                return .failure(.networkError("Status code: \(httpResponse.statusCode)"))
            }
            
            print("[CloudAIService] ✅ Status code 200, parsing risposta...")
            
            // Parse risposta
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return .success(content)
            }
            
            return .failure(.processingError("Risposta non valida"))
        } catch {
            let nsError = error as NSError
            
            // Gestisci timeout
            if nsError.code == NSURLErrorTimedOut {
                print("[CloudAIService] ⏱️ Timeout durante la richiesta")
                return .failure(.timeout)
            }
            
            // Gestisci cancellazioni (non trattarle come errori permanenti)
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                print("[CloudAIService] ⚠️ Richiesta cancellata (probabilmente timeout o interruzione)")
                // Tratta le cancellazioni come timeout (possono essere ritentate)
                return .failure(.timeout)
            }
            
            // Altri errori di rete
            print("[CloudAIService] ❌ Errore di rete: \(error.localizedDescription) (code: \(nsError.code), domain: \(nsError.domain))")
            return .failure(.networkError(error.localizedDescription))
        }
    }
    
    /// Chiama OpenAI con streaming SSE
    func callOpenAIStreaming(
        prompt: String,
        task: AITask,
        systemPrompt: String? = nil,
        streamCallback: @escaping (String) -> Void
    ) async -> Result<String, AIError> {
        guard isAvailable else {
            return .failure(.modelUnavailable)
        }
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            return .failure(.networkError("URL non valido"))
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Estrai immagini se presenti
        let imagePaths = extractImagePaths(from: task)
        let hasImages = !imagePaths.isEmpty
        
        // Costruisci il contenuto del messaggio utente
        var userContent: Any
        
        if hasImages {
            var contentArray: [[String: Any]] = []
            
            if !prompt.isEmpty {
                contentArray.append([
                    "type": "text",
                    "text": prompt
                ])
            }
            
            for imagePath in imagePaths {
                guard let base64Image = encodeImageToBase64(imagePath: imagePath) else {
                    continue
                }
                
                let ext = (imagePath as NSString).pathExtension.lowercased()
                let mimeType: String
                switch ext {
                case "jpg", "jpeg":
                    mimeType = "image/jpeg"
                case "png":
                    mimeType = "image/png"
                case "gif":
                    mimeType = "image/gif"
                case "webp":
                    mimeType = "image/webp"
                case "heic", "heif":
                    mimeType = "image/heic"
                default:
                    mimeType = "image/jpeg"
                }
                
                contentArray.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:\(mimeType);base64,\(base64Image)"
                    ]
                ])
            }
            
            userContent = contentArray
        } else {
            userContent = prompt
        }
        
        // Estrai parametri opzionali dal task
        let maxTokens = (task.parameters["max_tokens"]?.value as? Int) ?? (hasImages ? 4000 : 2000)
        let responseFormat = task.parameters["response_format"]?.value as? [String: String]
        
        // Usa systemPrompt dai parameters se presente, altrimenti usa quello passato o default
        var systemContent: String
        if let customSystemPrompt = task.parameters["systemPrompt"]?.value as? String {
            systemContent = customSystemPrompt
        } else if let passedSystemPrompt = systemPrompt {
            systemContent = passedSystemPrompt
        } else {
            systemContent = "Sei un assistente AI per un'azienda di perizie assicurative in Italia. Rispondi sempre in italiano."
        }
        
        // Aggiungi JSON se richiesto e non già presente
        if responseFormat?["type"] == "json_object" && !systemContent.lowercased().contains("json") {
            systemContent += " Rispondi in formato JSON."
        }
        
        var payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemContent],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.7,
            "max_tokens": maxTokens,
            "stream": true
        ]
        
        // Aggiungi response_format se specificato (nota: streaming potrebbe non supportare json_object mode)
        if let responseFormat = responseFormat {
            payload["response_format"] = responseFormat
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            var fullResponse = ""
            
            let (asyncBytes, response) = try await session.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.networkError("Risposta non valida"))
            }
            
            if httpResponse.statusCode == 429 {
                return .failure(.rateLimitExceeded)
            }
            
            guard httpResponse.statusCode == 200 else {
                return .failure(.networkError("Status code: \(httpResponse.statusCode)"))
            }
            
            // Leggi lo stream SSE
            var lineBuffer = Data()
            for try await byte in asyncBytes {
                if byte == 10 { // \n
                    if let line = String(data: lineBuffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !line.isEmpty {
                        // Parse formato SSE: "data: {...}"
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            
                            if jsonString == "[DONE]" {
                                break
                            }
                            
                            if let jsonData = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let firstChoice = choices.first,
                               let delta = firstChoice["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                fullResponse += content
                                streamCallback(content)
                            }
                        }
                    }
                    lineBuffer = Data()
                } else if byte != 13 { // Ignora \r
                    lineBuffer.append(byte)
                }
            }
            
            return .success(fullResponse)
        } catch {
            let nsError = error as NSError
            
            // Gestisci timeout
            if nsError.code == NSURLErrorTimedOut {
                print("[CloudAIService] ⏱️ Timeout durante la richiesta")
                return .failure(.timeout)
            }
            
            // Gestisci cancellazioni (non trattarle come errori permanenti)
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                print("[CloudAIService] ⚠️ Richiesta cancellata (probabilmente timeout o interruzione)")
                // Tratta le cancellazioni come timeout (possono essere ritentate)
                return .failure(.timeout)
            }
            
            // Altri errori di rete
            print("[CloudAIService] ❌ Errore di rete: \(error.localizedDescription) (code: \(nsError.code), domain: \(nsError.domain))")
            return .failure(.networkError(error.localizedDescription))
        }
    }
}

