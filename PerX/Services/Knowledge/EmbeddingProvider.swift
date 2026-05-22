import Foundation

/// Fornitore di embedding astratto (da implementare con modello reale)
protocol EmbeddingProvider {
    func embed(text: String) async throws -> [Float]
}

/// Implementazione stub in attesa del modello embedding reale
final class StubEmbeddingProvider: EmbeddingProvider {
    func embed(text: String) async throws -> [Float] {
        // TODO: sostituire con embedding reale (MLX/altro)
        return []
    }
}

// MARK: - OpenAI Embedding Provider

/// Usa la stessa configurazione OpenAI delle impostazioni AI
final class OpenAIEmbeddingProvider: EmbeddingProvider {
    static let shared = OpenAIEmbeddingProvider()
    
    private var apiKey: String {
        let tenantKey = TenantAIKeysService.shared.openAIKey
        if !tenantKey.isEmpty { return tenantKey }
        return UserDefaults.standard.string(forKey: "ai_openai_api_key") ?? ""
    }
    
    private var baseURL: String {
        UserDefaults.standard.string(forKey: "ai_openai_base_url") ?? "https://api.openai.com/v1"
    }
    
    /// Modello embedding dedicato; fallback su text-embedding-3-small
    private var model: String {
        UserDefaults.standard.string(forKey: "ai_openai_embedding_model") ?? "text-embedding-3-small"
    }
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        return URLSession(configuration: config)
    }()
    
    func embed(text: String) async throws -> [Float] {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "OpenAIEmbeddingProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "API key OpenAI mancante"])
        }
        guard let url = URL(string: "\(baseURL)/embeddings") else {
            throw NSError(domain: "OpenAIEmbeddingProvider", code: 400, userInfo: [NSLocalizedDescriptionKey: "Base URL OpenAI non valida"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let payload: [String: Any] = [
            "model": model,
            "input": text
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenAIEmbeddingProvider", code: 500, userInfo: [NSLocalizedDescriptionKey: "Risposta HTTP non valida"])
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OpenAIEmbeddingProvider", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Errore OpenAI \(http.statusCode): \(body)"])
        }
        
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataArr = json["data"] as? [[String: Any]],
            let first = dataArr.first,
            let embedding = first["embedding"] as? [Double]
        else {
            throw NSError(domain: "OpenAIEmbeddingProvider", code: 500, userInfo: [NSLocalizedDescriptionKey: "Formato embedding non valido"])
        }
        
        return embedding.map { Float($0) }
    }
}

