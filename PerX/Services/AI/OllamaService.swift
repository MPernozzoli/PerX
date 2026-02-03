import Foundation
import AppKit

/// Servizio per gestire Ollama automaticamente
class OllamaService {
    static let shared = OllamaService()
    
    /// Verifica se Ollama è disponibile (non in sandbox)
    static var isAvailable: Bool {
        !NativeExcelReader.isRunningInSandbox
    }
    
    private let ollamaURL = URL(string: "http://localhost:11434")!
    private var ollamaProcess: Process?
    private var ollamaPath: String {
        // Cerca Ollama in posizioni comuni
        let possiblePaths = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "/usr/bin/ollama",
            "\(NSHomeDirectory())/.local/bin/ollama"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) && FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        // Se non trovato, prova a usare 'command -v ollama' (più robusto di which)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", "command -v ollama"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty,
                   FileManager.default.fileExists(atPath: path),
                   FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {
            print("[OllamaService] ⚠️ Errore ricerca Ollama nel PATH: \(error)")
        }
        
        return "ollama" // Fallback: prova a usare quello nel PATH
    }
    
    private init() {
        checkAndStartOllama()
    }
    
    // MARK: - Public API
    
    /// Verifica se Ollama è in esecuzione
    func isRunning() async -> Bool {
        do {
            var request = URLRequest(url: ollamaURL.appendingPathComponent("api/tags"))
            request.timeoutInterval = 2.0
            let (_, response) = try await URLSession.shared.data(for: request)
            let isRunning = (response as? HTTPURLResponse)?.statusCode == 200
            print("[OllamaService] 🔍 Verifica stato: \(isRunning ? "✅ In esecuzione" : "❌ Non in esecuzione")")
            return isRunning
        } catch {
            print("[OllamaService] ❌ Errore verifica: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Avvia Ollama se non è già in esecuzione
    func startOllama() async -> Bool {
        // In sandbox (TestFlight/App Store), Ollama non è disponibile
        guard OllamaService.isAvailable else {
            print("[OllamaService] 📦 Modalità sandbox rilevata - Ollama non disponibile")
            return false
        }
        
        if await isRunning() {
            return true
        }
        
        return await launchOllama()
    }
    
    /// Carica un modello .gguf in Ollama
    func loadModel(modelName: String, ggufPath: String) async -> Result<String, Error> {
        // Prima assicurati che Ollama sia in esecuzione
        guard await startOllama() else {
            return .failure(NSError(domain: "OllamaService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Impossibile avviare Ollama"]))
        }
        
        // Usa ollama import per caricare il modello
        return await importModel(modelName: modelName, ggufPath: ggufPath)
    }
    
    /// Verifica se un modello è già caricato e restituisce il nome effettivo
    func findModelName(_ modelName: String) async -> String? {
        guard await isRunning() else {
            print("[OllamaService] ⚠️ Ollama non in esecuzione, impossibile verificare modelli")
            return nil
        }
        
        do {
            var request = URLRequest(url: ollamaURL.appendingPathComponent("api/tags"))
            request.timeoutInterval = 5.0
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let modelNames = models.compactMap { $0["name"] as? String }
                print("[OllamaService] 📋 Modelli caricati in Ollama: \(modelNames.joined(separator: ", "))")
                print("[OllamaService] 🔍 Cercando modello: '\(modelName)'")
                
                // Cerca match esatto
                if let exactMatch = modelNames.first(where: { $0 == modelName || $0 == "\(modelName):latest" }) {
                    print("[OllamaService] ✅ Trovato match esatto: '\(exactMatch)'")
                    return exactMatch
                }
                
                // Estrai parti del nome per matching intelligente
                let baseName = modelName.components(separatedBy: ":").first ?? modelName
                let baseNameWithoutExt = (baseName as NSString).deletingPathExtension
                let lowercasedSearch = baseNameWithoutExt.lowercased()
                
                // Estrai parole chiave dal nome (es. "phi-4-Q4_K_M" -> ["phi", "4"])
                let keywords = lowercasedSearch.components(separatedBy: CharacterSet(charactersIn: "-_."))
                    .filter { !$0.isEmpty && $0.count > 1 }
                
                print("[OllamaService] 🔍 Keywords estratte: \(keywords)")
                
                // Cerca match parziale più intelligente
                if let partialMatch = modelNames.first(where: { name in
                    let nameBase = (name.components(separatedBy: ":").first ?? name).lowercased()
                    
                    // Match esatto del nome base
                    if nameBase == lowercasedSearch {
                        return true
                    }
                    
                    // Match per contenuto
                    if nameBase.contains(lowercasedSearch) || lowercasedSearch.contains(nameBase) {
                        return true
                    }
                    
                    // Match per keywords (almeno 2 keywords devono corrispondere)
                    let nameKeywords = nameBase.components(separatedBy: CharacterSet(charactersIn: "-_."))
                        .filter { !$0.isEmpty && $0.count > 1 }
                    
                    let matchingKeywords = keywords.filter { keyword in
                        nameKeywords.contains { $0.contains(keyword) || keyword.contains($0) }
                    }
                    
                    // Per modelli come "phi-4" cerca "phi4" o "phi-4" o "phi"
                    if keywords.count >= 1 {
                        let firstKeyword = keywords[0]
                        if nameBase.contains(firstKeyword) || nameKeywords.contains(where: { $0.contains(firstKeyword) || firstKeyword.contains($0) }) {
                            return true
                        }
                    }
                    
                    return matchingKeywords.count >= min(2, keywords.count)
                }) {
                    print("[OllamaService] ✅ Trovato match intelligente: '\(partialMatch)'")
                    return partialMatch
                }
                
                // Ultimo tentativo: se c'è solo un modello di quel tipo, usalo
                // (per quando l'utente ha solo un modello testo o solo un modello multimodale)
                if modelNames.count == 1 {
                    print("[OllamaService] ⚠️ Solo un modello disponibile, uso quello: '\(modelNames[0])'")
                    return modelNames[0]
                }
                
                print("[OllamaService] ❌ Modello '\(modelName)' non trovato")
                return nil
            } else {
                print("[OllamaService] ⚠️ Risposta non valida da Ollama")
            }
        } catch {
            print("[OllamaService] ❌ Errore nel verificare modelli: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Verifica se un modello è già caricato
    func isModelLoaded(_ modelName: String) async -> Bool {
        return await findModelName(modelName) != nil
    }
    
    /// Ottiene la lista dei modelli caricati
    func getLoadedModels() async -> [String] {
        guard await isRunning() else { return [] }
        
        do {
            var request = URLRequest(url: ollamaURL.appendingPathComponent("api/tags"))
            request.timeoutInterval = 5.0
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                return models.compactMap { $0["name"] as? String }
            }
        } catch {
            print("[OllamaService] Errore nel recuperare modelli: \(error)")
        }
        
        return []
    }
    
    // MARK: - Private Implementation
    
    private func checkAndStartOllama() {
        Task {
            let isCurrentlyRunning = await isRunning()
            if !isCurrentlyRunning {
                _ = await startOllama()
            }
        }
    }
    
    private func launchOllama() async -> Bool {
        // Verifica se Ollama è già in esecuzione
        let isCurrentlyRunning = await isRunning()
        if isCurrentlyRunning {
            return true
        }
        
        // Verifica che Ollama sia installato
        let ollamaInstalled = await DependencyManager.shared.isDependencyInstalled(.ollama)
        if !ollamaInstalled {
            print("[OllamaService] ⚠️ Ollama non trovato, avvio installazione...")
            let installed = await DependencyManager.shared.installDependency(.ollama)
            if !installed {
                print("[OllamaService] ❌ Impossibile installare Ollama")
                // Verifica di nuovo dopo l'installazione fallita
                let isInstalled = await DependencyManager.shared.isDependencyInstalled(.ollama)
                let stillMissing = !isInstalled
                if stillMissing {
                    print("[OllamaService] 💡 Ollama potrebbe richiedere installazione manuale")
                    if let url = URL(string: "https://ollama.com/download") {
                        await MainActor.run {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                return false
            }
            // Aggiorna il percorso dopo l'installazione
            // (il percorso verrà ricercato al prossimo accesso a ollamaPath)
        }
        
        // Verifica che il percorso di Ollama sia valido prima di avviarlo
        let path = ollamaPath
        if path == "ollama" {
            // Se è solo "ollama", verifica che sia nel PATH
            let testProcess = Process()
            testProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
            testProcess.arguments = ["-c", "command -v ollama"]
            let testPipe = Pipe()
            testProcess.standardOutput = testPipe
            testProcess.standardError = Pipe()
            
            do {
                try testProcess.run()
                testProcess.waitUntilExit()
                if testProcess.terminationStatus != 0 {
                    print("[OllamaService] ❌ Ollama non trovato nel PATH")
                    await DependencyManager.shared.handleServiceError(
                        NSError(domain: "OllamaService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ollama non trovato nel PATH"]),
                        for: .ollama
                    )
                    return false
                }
            } catch {
                print("[OllamaService] ❌ Errore verifica Ollama: \(error)")
                return false
            }
        } else if !FileManager.default.fileExists(atPath: path) {
            print("[OllamaService] ❌ Percorso Ollama non valido: \(path)")
            await DependencyManager.shared.handleServiceError(
                NSError(domain: "OllamaService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Percorso Ollama non valido: \(path)"]),
                for: .ollama
            )
            return false
        }
        
        // Avvia Ollama come processo in background
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["serve"]
        
        // Reindirizza output per evitare che appaia nella console
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            ollamaProcess = process
            
            // Aspetta che Ollama si avvii (max 10 secondi)
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 secondi
                if await isRunning() {
                    print("[OllamaService] ✅ Ollama avviato con successo")
                    return true
                }
                
                // Verifica se il processo è ancora in esecuzione
                if !process.isRunning {
                    // Leggi l'output di errore per capire cosa è successo
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorString = String(data: errorData, encoding: .utf8) ?? "Errore sconosciuto"
                    print("[OllamaService] ❌ Ollama si è chiuso durante l'avvio")
                    print("[OllamaService] Output errore: \(errorString)")
                    
                    // Se l'errore è dovuto a Ollama mancante, avvia installazione
                    await DependencyManager.shared.handleServiceError(
                        NSError(domain: "OllamaService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ollama si è chiuso durante l'avvio: \(errorString)"]),
                        for: .ollama
                    )
                    return false
                }
            }
            
            print("[OllamaService] ⚠️ Timeout nell'attesa dell'avvio di Ollama")
            return false
        } catch {
            print("[OllamaService] ❌ Errore nell'avviare Ollama: \(error)")
            // Se l'errore indica Ollama mancante, avvia installazione
            await DependencyManager.shared.handleServiceError(error, for: .ollama)
            return false
        }
    }
    
    private func importModel(modelName: String, ggufPath: String) async -> Result<String, Error> {
        // Estrai il nome base dal file (senza estensione)
        let fileName = (ggufPath as NSString).lastPathComponent
        let baseName = (fileName as NSString).deletingPathExtension
        
        // Crea un Modelfile temporaneo che punta al file .gguf
        let tempDir = FileManager.default.temporaryDirectory
        let modelfilePath = tempDir.appendingPathComponent("\(baseName)_Modelfile")
        
        // Crea il contenuto del Modelfile
        let modelfileContent = "FROM \(ggufPath)\n"
        
        do {
            try modelfileContent.write(to: modelfilePath, atomically: true, encoding: .utf8)
            
            // Usa ollama create con il Modelfile (usa il nome base del file)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ollamaPath)
            process.arguments = ["create", baseName, "-f", modelfilePath.path]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            // Rimuovi il Modelfile temporaneo
            try? FileManager.default.removeItem(at: modelfilePath)
            
            if process.terminationStatus == 0 {
                print("[OllamaService] ✅ Modello \(baseName) caricato con successo")
                
                // Verifica il nome effettivo in Ollama (potrebbe essere baseName:latest)
                let actualName = await findModelName(baseName) ?? baseName
                print("[OllamaService] • Nome effettivo in Ollama: \(actualName)")
                
                return .success(actualName)
            } else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? "Errore sconosciuto"
                print("[OllamaService] ❌ Errore nel caricare modello: \(errorString)")
                return .failure(NSError(domain: "OllamaService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorString]))
            }
        } catch {
            print("[OllamaService] ❌ Errore nell'eseguire ollama create: \(error)")
            try? FileManager.default.removeItem(at: modelfilePath)
            return .failure(error)
        }
    }
}

