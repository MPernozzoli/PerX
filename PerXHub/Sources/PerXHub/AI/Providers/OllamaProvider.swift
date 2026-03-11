import Foundation

// ============================================================================
// MARK: - Ollama Provider
// Interfaccia per modelli LLM locali via Ollama (Phi-3, Phi-4, Llama, etc.)
// ============================================================================

public actor OllamaProvider {
    
    private let baseURL: String
    public let currentModel: String
    private let session: URLSession
    
    public init(
        baseURL: String = "http://localhost:11434",
        model: String = "phi4"
    ) {
        self.baseURL = baseURL
        self.currentModel = model
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120 // 2 minuti per generazione
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Availability
    
    public var isAvailable: Bool {
        get async {
            // Verifica che Ollama sia raggiungibile
            guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
            
            do {
                let (_, response) = try await session.data(from: url)
                if let httpResponse = response as? HTTPURLResponse {
                    return httpResponse.statusCode == 200
                }
                return false
            } catch {
                print("[OllamaProvider] ❌ Non raggiungibile: \(error.localizedDescription)")
                return false
            }
        }
    }
    
    // MARK: - Generation
    
    public func generate(
        prompt: String,
        maxTokens: Int = 1024,
        temperature: Double = 0.7
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw OllamaError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "model": currentModel,
            "prompt": prompt,
            "stream": false,
            "options": [
                "num_predict": maxTokens,
                "temperature": temperature
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw OllamaError.httpError(httpResponse.statusCode)
        }
        
        // Parse risposta
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw OllamaError.invalidResponse
        }
        
        return responseText
    }
    
    // MARK: - Chat
    
    public func chat(
        messages: [[String: String]],
        maxTokens: Int = 1024
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw OllamaError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "model": currentModel,
            "messages": messages,
            "stream": false,
            "options": [
                "num_predict": maxTokens
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OllamaError.invalidResponse
        }
        
        return content
    }
    
    // MARK: - Models
    
    public func listModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw OllamaError.invalidURL
        }
        
        let (data, _) = try await session.data(from: url)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }
        
        return models.compactMap { $0["name"] as? String }
    }
}

// MARK: - Errors

public enum OllamaError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case modelNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL Ollama non valido"
        case .invalidResponse:
            return "Risposta Ollama non valida"
        case .httpError(let code):
            return "Errore HTTP Ollama: \(code)"
        case .modelNotFound(let model):
            return "Modello non trovato: \(model)"
        }
    }
}
