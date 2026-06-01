import Foundation
import AppKit
import CoreML
import Vision

/// Servizio per gestire modelli vision multimodali usando MLX/Core ML su Apple Silicon
@MainActor
class MLXVisionService: ObservableObject {
    static let shared = MLXVisionService()
    
    @Published var isModelLoaded = false
    @Published var isLoading = false
    @Published var loadProgress: Double = 0.0
    @Published var loadError: String?
    
    private var modelPath: String?
    private var bridgeScriptPath: String?
    
    private var isAvailable: Bool {
        // Verifica che siamo su Apple Silicon
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
    
    private init() {
        // Trova il percorso dello script Python bridge
        if let scriptPath = Bundle.main.path(forResource: "mlx_vision_bridge", ofType: "py") {
            bridgeScriptPath = scriptPath
        } else {
            // Cerca nella directory del servizio
            let serviceDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
            let scriptURL = serviceDir.appendingPathComponent("mlx_vision_bridge.py")
            if FileManager.default.fileExists(atPath: scriptURL.path) {
                bridgeScriptPath = scriptURL.path
            }
        }
        
        // Verifica disponibilità all'avvio
        checkModelPath()
        
        // Carica automaticamente il modello se configurato (sul MainActor)
        if let path = modelPath, !isModelLoaded {
            print("[MLXVisionService] 🚀 Avvio caricamento automatico modello: \(path)")
            Task { @MainActor in
                let success = await loadModel(modelPath: path)
                print("[MLXVisionService] 📊 Caricamento automatico completato: \(success ? "✅ successo" : "❌ fallito")")
                if !success {
                    print("[MLXVisionService] ❌ Errore caricamento: \(loadError ?? "sconosciuto")")
                }
            }
        } else {
            if modelPath == nil {
                print("[MLXVisionService] ⚠️ Nessun percorso modello configurato, caricamento automatico saltato")
            } else if isModelLoaded {
                print("[MLXVisionService] ✅ Modello già caricato")
            }
        }
    }
    
    // MARK: - Public API
    
    /// Verifica se il servizio è disponibile
    var serviceAvailable: Bool {
        let available = isAvailable && isModelLoaded
        print("[MLXVisionService] 🔍 serviceAvailable: \(available) (isAvailable: \(isAvailable), isModelLoaded: \(isModelLoaded))")
        return available
    }
    
    /// Carica il modello vision
    func loadModel(modelPath: String) async -> Bool {
        guard isAvailable else {
            print("[MLXVisionService] ❌ Servizio non disponibile (non su Apple Silicon)")
            loadError = "MLX è disponibile solo su Apple Silicon (M-series)"
            return false
        }
        
        // Verifica se è un ID Hugging Face (contiene "/" e non è un path assoluto esistente)
        let isHuggingFaceID = modelPath.contains("/") && 
                              !modelPath.hasPrefix("/") && 
                              !FileManager.default.fileExists(atPath: modelPath)
        
        if !isHuggingFaceID {
            // Verifica che sia una directory (i modelli locali sono directory)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: modelPath, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                print("[MLXVisionService] ❌ Directory modello non trovata: \(modelPath)")
                loadError = "Directory modello non trovata"
                return false
            }
        } else {
            print("[MLXVisionService] 📥 Rilevato ID Hugging Face: \(modelPath)")
            print("[MLXVisionService] 📥 Il modello verrà scaricato automaticamente da Hugging Face")
        }
        
        isLoading = true
        loadProgress = 0.0
        loadError = nil
        
        defer {
            isLoading = false
        }
        
        do {
            print("[MLXVisionService] 📦 Caricamento modello Llama 3.1 8B Vision da: \(modelPath)")
            
            // Salva il percorso
            self.modelPath = modelPath
            UserDefaults.standard.set(modelPath, forKey: "ai_mlx_vision_model_path")
            
            loadProgress = 0.3
            
            // Verifica che la directory contenga i file necessari del modello (solo per modelli locali)
            if !isHuggingFaceID {
                let requiredFiles = ["config.json", "tokenizer.json"] // File minimi per un modello Hugging Face
                var foundFiles = 0
                for file in requiredFiles {
                    let filePath = (modelPath as NSString).appendingPathComponent(file)
                    if FileManager.default.fileExists(atPath: filePath) {
                        foundFiles += 1
                    }
                }
                
                if foundFiles == 0 {
                    print("[MLXVisionService] ⚠️ Directory modello non sembra contenere un modello Hugging Face valido")
                    // Non blocchiamo, potrebbe essere un formato diverso
                }
            }
            
            loadProgress = 0.6
            
            // Carica il modello usando il bridge Python
            guard let scriptPath = bridgeScriptPath else {
                loadError = "Script bridge Python non trovato"
                print("[MLXVisionService] ❌ Script bridge non trovato")
                return false
            }
            
            loadProgress = 0.7
            
            // Chiama il bridge Python per caricare il modello
            let loadResult = await executePythonBridge(
                command: "load",
                parameters: ["model_path": modelPath]
            )
            
            loadProgress = 0.9
            
            // Verifica successo (nuovo formato con "success" field)
            if let success = loadResult["success"] as? Bool {
                if success {
                    loadProgress = 1.0
                    isModelLoaded = true
                    print("[MLXVisionService] ✅ Modello caricato con successo via bridge Python")
                    return true
                } else {
                    // Errore nel formato nuovo
                    let error = loadResult["error"] as? String ?? "Caricamento fallito"
                    loadError = error
                    print("[MLXVisionService] ❌ Errore bridge Python: \(error)")
                    return false
                }
            } else {
                // Formato vecchio (backward compatibility)
                if let error = loadResult["error"] as? String {
                    loadError = error
                    print("[MLXVisionService] ❌ Errore bridge Python: \(error)")
                    return false
                }
                loadError = "Caricamento fallito senza errori specifici"
                return false
            }
        } catch {
            loadError = error.localizedDescription
            print("[MLXVisionService] ❌ Errore nel caricare modello: \(error)")
            return false
        }
    }
    
    /// Esegue un task AI usando il modello vision
    func executeTask(_ task: AITask) async -> Result<AIResult, AIError> {
        print("[MLXVisionService] 🎯 Esecuzione task: tipo=\(task.type), id=\(task.id)")
        
        guard isModelLoaded else {
            print("[MLXVisionService] ❌ Modello non caricato")
            return .failure(.modelUnavailable)
        }
        
        let startTime = Date()
        
        do {
            switch task.type {
            case .imageAnalysis, .documentAnalysis:
                print("[MLXVisionService] 📸 Task di analisi immagine/documento")
                return await handleImageOrDocumentAnalysis(task: task, startTime: startTime)
            case .chat, .textGeneration:
                print("[MLXVisionService] 💬 Task di chat/generazione testo")
                // Il modello vision può anche fare chat/testo
                return await handleChat(task: task, startTime: startTime)
            default:
                print("[MLXVisionService] ❌ Tipo task non supportato: \(task.type)")
                return .failure(.invalidInput)
            }
        } catch {
            let processingTime = Date().timeIntervalSince(startTime)
            print("[MLXVisionService] ❌ Errore nell'esecuzione: \(error)")
            return .failure(.processingError(error.localizedDescription))
        }
    }
    
    private func handleImageOrDocumentAnalysis(task: AITask, startTime: Date) async -> Result<AIResult, AIError> {
        // Supporta sia "filePath" che "imagePath"
        let filePath = task.parameters["filePath"]?.value as? String ?? 
                       task.parameters["imagePath"]?.value as? String
        
        guard let filePath = filePath else {
            return .failure(.invalidInput)
        }
        
        // Prepara il prompt
        let customPrompt = task.parameters["prompt"]?.value as? String ?? "Analizza questo file"
        
        print("[MLXVisionService] 🔍 Analisi file: \(filePath)")
        print("[MLXVisionService] • Prompt: \(customPrompt)")
        
        let result = await analyzeImageOrDocument(imagePath: filePath, prompt: customPrompt)
        let processingTime = Date().timeIntervalSince(startTime)
        
        switch result {
        case .success(let response):
            return .success(AIResult.success(
                taskID: task.id,
                provider: .localMultimodal,
                result: response,
                metadata: ["model": "llama-3.1-8B-vision", "filePath": filePath],
                processingTime: processingTime
            ))
        case .failure(let error):
            return .failure(.processingError(error.localizedDescription))
        }
    }
    
    private func handleChat(task: AITask, startTime: Date) async -> Result<AIResult, AIError> {
        guard let prompt = resolvePrompt(for: task) else {
            return .failure(.invalidInput)
        }
        
        // Verifica se ci sono immagini nel task
        if let imagesBase64 = task.parameters["images"]?.value as? [String], !imagesBase64.isEmpty {
            // Chat con immagini
            return await handleChatWithImages(task: task, prompt: prompt, imagesBase64: imagesBase64, startTime: startTime)
        }
        
        // Per chat senza immagini, usa solo testo
        guard let scriptPath = bridgeScriptPath, let modelPath = modelPath else {
            return .failure(.modelUnavailable)
        }
        
        let result = await executePythonBridge(
            command: "generate",
            parameters: [
                "model_path": modelPath,
                "prompt": prompt,
                "max_tokens": 512,
                "temperature": 0.7
            ]
        )
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        // Verifica formato nuovo (con "success" field)
        if let success = result["success"] as? Bool {
            if success {
                if let response = result["response"] as? String {
                    return .success(AIResult.success(
                        taskID: task.id,
                        provider: .localMultimodal,
                        result: response,
                        metadata: ["model": "llama-3.1-8B-vision"],
                        processingTime: processingTime
                    ))
                } else {
                    return .failure(.processingError("Risposta incompleta: success=true ma response mancante"))
                }
            } else {
                let error = result["error"] as? String ?? "Errore sconosciuto"
                return .failure(.processingError(error))
            }
        }
        
        // Backward compatibility: formato vecchio
        if let error = result["error"] as? String {
            return .failure(.processingError(error))
        }
        
        if let response = result["response"] as? String {
            return .success(AIResult.success(
                taskID: task.id,
                provider: .localMultimodal,
                result: response,
                metadata: ["model": "llama-3.1-8B-vision"],
                processingTime: processingTime
            ))
        }
        
        return .failure(.processingError("Risposta non valida dal bridge"))
    }
    
    private func handleChatWithImages(task: AITask, prompt: String, imagesBase64: [String], startTime: Date) async -> Result<AIResult, AIError> {
        // Salva temporaneamente le immagini e analizzale
        var analysisResults: [String] = []
        
        for (index, base64Image) in imagesBase64.enumerated() {
            guard let imageData = Data(base64Encoded: base64Image),
                  let tempURL = saveTemporaryImage(data: imageData, index: index) else {
                continue
            }
            
            let result = await analyzeImageOrDocument(imagePath: tempURL.path, prompt: prompt)
            switch result {
            case .success(let response):
                analysisResults.append(response)
            case .failure:
                break
            }
            
            // Pulisci file temporaneo
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let combinedResponse = analysisResults.isEmpty 
            ? "Impossibile analizzare le immagini fornite."
            : analysisResults.joined(separator: "\n\n")
        
        let processingTime = Date().timeIntervalSince(startTime)
        return .success(AIResult.success(
            taskID: task.id,
            provider: .localMultimodal,
            result: combinedResponse,
            metadata: ["model": "llama-3.1-8B-vision", "imagesCount": imagesBase64.count],
            processingTime: processingTime
        ))
    }
    
    private func saveTemporaryImage(data: Data, index: Int) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("mlx_vision_\(index)_\(UUID().uuidString).jpg")
        
        guard let _ = try? data.write(to: tempFile) else {
            return nil
        }
        
        return tempFile
    }
    
    /// Analizza un'immagine o documento
    private func analyzeImageOrDocument(imagePath: String, prompt: String) async -> Result<String, Error> {
        guard isModelLoaded else {
            return .failure(NSError(domain: "MLXVisionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Modello non caricato"]))
        }
        
        // Usa FileService per gestire correttamente i security scoped resources
        guard let imageData = FileService.shared.readFileData(at: imagePath) ?? (try? Data(contentsOf: URL(fileURLWithPath: imagePath))),
              let image = NSImage(data: imageData) else {
            return .failure(NSError(domain: "MLXVisionService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Impossibile caricare l'immagine: \(imagePath)"]))
        }
        
        print("[MLXVisionService] 🔍 Analisi immagine: \(imagePath)")
        print("[MLXVisionService] • Prompt: \(prompt)")
        print("[MLXVisionService] • File esiste: \(FileManager.default.fileExists(atPath: imagePath))")
        
        // Chiama il bridge Python per analizzare l'immagine
        guard let scriptPath = bridgeScriptPath else {
            print("[MLXVisionService] ❌ bridgeScriptPath non configurato")
            return .failure(NSError(domain: "MLXVisionService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Bridge Python script non trovato"]))
        }
        
        guard let modelPath = modelPath else {
            print("[MLXVisionService] ❌ modelPath non configurato")
            return .failure(NSError(domain: "MLXVisionService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Percorso modello non configurato"]))
        }
        
        print("[MLXVisionService] 📤 Invio richiesta al bridge Python...")
        print("[MLXVisionService] • Comando: analyze")
        print("[MLXVisionService] • model_path: \(modelPath)")
        print("[MLXVisionService] • image_path: \(imagePath)")
        print("[MLXVisionService] • prompt: \(prompt)")
        
        let result = await executePythonBridge(
            command: "analyze",
            parameters: [
                "model_path": modelPath,
                "image_path": imagePath,
                "prompt": prompt,
                "max_tokens": 512
            ]
        )
        
        print("[MLXVisionService] 📥 Risposta ricevuta dal bridge: \(result)")
        
        // Verifica formato nuovo (con "success" field)
        if let success = result["success"] as? Bool {
            if success {
                if let response = result["response"] as? String {
                    print("[MLXVisionService] ✅ Risposta valida ricevuta (\(response.count) caratteri)")
                    return .success(response)
                } else {
                    print("[MLXVisionService] ❌ Success=true ma response mancante")
                    return .failure(NSError(domain: "MLXVisionService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Risposta incompleta: success=true ma response mancante"]))
                }
            } else {
                // Errore nel formato nuovo
                let error = result["error"] as? String ?? "Errore sconosciuto"
                print("[MLXVisionService] ❌ Errore dal bridge: \(error)")
                return .failure(NSError(domain: "MLXVisionService", code: 4, userInfo: [NSLocalizedDescriptionKey: error]))
            }
        }
        
        // Backward compatibility: formato vecchio
        if let error = result["error"] as? String {
            print("[MLXVisionService] ❌ Errore dal bridge (formato vecchio): \(error)")
            return .failure(NSError(domain: "MLXVisionService", code: 4, userInfo: [NSLocalizedDescriptionKey: error]))
        }
        
        if let response = result["response"] as? String {
            print("[MLXVisionService] ✅ Risposta valida ricevuta (formato vecchio) (\(response.count) caratteri)")
            return .success(response)
        }
        
        print("[MLXVisionService] ❌ Risposta non valida dal bridge: \(result)")
        return .failure(NSError(domain: "MLXVisionService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Risposta non valida dal bridge: \(result)"]))
    }
    
    // MARK: - Private Implementation
    
    /// Risolve il prompt applicando eventualmente il template RAG
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
        
        return nil
    }
    
    private func checkModelPath() {
        // Verifica se c'è un percorso modello salvato
        let savedPath = UserDefaults.standard.string(forKey: "ai_mlx_vision_model_path") ?? ""
        print("[MLXVisionService] 🔍 Verifica percorso modello salvato: '\(savedPath)'")
        
        if !savedPath.isEmpty {
            let exists = FileManager.default.fileExists(atPath: savedPath)
            var isDirectory: ObjCBool = false
            let isDir = FileManager.default.fileExists(atPath: savedPath, isDirectory: &isDirectory) && isDirectory.boolValue
            
            print("[MLXVisionService] • File esiste: \(exists)")
            print("[MLXVisionService] • È una directory: \(isDir)")
            
            if exists {
                modelPath = savedPath
                print("[MLXVisionService] ✅ Percorso modello impostato: \(savedPath)")
            } else {
                print("[MLXVisionService] ⚠️ Percorso salvato non esiste: \(savedPath)")
            }
        } else {
            print("[MLXVisionService] ⚠️ Nessun percorso modello salvato in UserDefaults")
        }
    }
    
    // MARK: - Python Bridge
    
    /// Esegue un comando tramite il bridge Python
    private func executePythonBridge(command: String, parameters: [String: Any]) async -> [String: Any] {
        print("[MLXVisionService] 🔧 Esecuzione bridge Python - Comando: \(command)")
        
        guard let scriptPath = bridgeScriptPath else {
            print("[MLXVisionService] ❌ Script bridge non trovato")
            return ["error": "Script bridge non trovato"]
        }
        
        // Prepara input JSON
        var inputDict = parameters
        if let modelPath = modelPath {
            inputDict["model_path"] = modelPath
        }
        
        guard let inputJSON = try? JSONSerialization.data(withJSONObject: inputDict) else {
            return ["error": "Errore nella serializzazione input"]
        }

        do {
            let result = try await PerXLocalAgent.shared.runPythonScript(
                scriptPath: scriptPath,
                arguments: [command],
                environment: [:],
                standardInput: inputJSON,
                timeout: 60
            )
            guard result.exitCode == 0 else {
                return ["error": result.combinedOutput]
            }
            guard let outputData = result.output.data(using: .utf8),
                  let outputJSON = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
                return ["error": "Output non valido dal bridge Python"]
            }
            return outputJSON
        } catch {
            print("[MLXVisionService] ❌ Errore esecuzione bridge: \(error)")
            return ["error": "Errore esecuzione bridge: \(error.localizedDescription)"]
        }
    }
}
