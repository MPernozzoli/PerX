import Foundation

// ============================================================================
// MARK: - MLX Vision Provider
// Interfaccia per modelli vision accelerati via MLX (Python bridge)
// ============================================================================

public actor MLXVisionProvider {
    
    private let pythonBridgeURL: String
    public let currentModel: String
    private let session: URLSession
    
    public init(
        bridgeURL: String = "http://localhost:8765",
        model: String = "mlx-community/Qwen2.5-VL-7B-Instruct-8bit"
    ) {
        self.pythonBridgeURL = bridgeURL
        self.currentModel = model
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180 // 3 minuti per analisi immagine
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Availability
    
    public var isAvailable: Bool {
        get async {
            guard let url = URL(string: "\(pythonBridgeURL)/health") else { return false }
            
            do {
                let (_, response) = try await session.data(from: url)
                if let httpResponse = response as? HTTPURLResponse {
                    return httpResponse.statusCode == 200
                }
                return false
            } catch {
                print("[MLXVisionProvider] ❌ Bridge non raggiungibile: \(error.localizedDescription)")
                return false
            }
        }
    }
    
    // MARK: - Analysis
    
    /// Analizza un'immagine con prompt
    public func analyze(
        imageData: Data,
        prompt: String
    ) async throws -> String {
        guard let url = URL(string: "\(pythonBridgeURL)/analyze") else {
            throw MLXVisionError.invalidURL
        }
        
        let base64Image = imageData.base64EncodedString()
        
        let requestBody: [String: Any] = [
            "model": currentModel,
            "image": base64Image,
            "prompt": prompt
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MLXVisionError.bridgeError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String else {
            throw MLXVisionError.invalidResponse
        }
        
        return result
    }
    
    /// Estrae testo da un documento
    public func extractText(imageData: Data) async throws -> String {
        return try await analyze(
            imageData: imageData,
            prompt: "Estrai tutto il testo visibile in questo documento. Mantieni la formattazione originale il più possibile."
        )
    }
    
    /// Analizza un documento peritale
    public func analyzeDocument(
        imageData: Data,
        documentType: DocumentType
    ) async throws -> DocumentAnalysis {
        let prompt: String
        
        switch documentType {
        case .invoice:
            prompt = """
            Analizza questa fattura ed estrai:
            - Numero fattura
            - Data
            - Fornitore
            - Importo totale
            - Voci principali
            
            Rispondi in formato JSON.
            """
        case .quote:
            prompt = """
            Analizza questo preventivo ed estrai:
            - Fornitore/Artigiano
            - Data
            - Importo totale
            - Voci di spesa principali
            
            Rispondi in formato JSON.
            """
        case .photo:
            prompt = """
            Descrivi cosa vedi in questa foto di danno:
            - Tipo di danno
            - Beni coinvolti
            - Gravità apparente
            - Dettagli rilevanti
            
            Rispondi in modo strutturato.
            """
        case .report:
            prompt = """
            Analizza questo documento e fornisci un riassunto:
            - Tipo di documento
            - Contenuto principale
            - Dati rilevanti
            
            Rispondi in modo strutturato.
            """
        case .unknown:
            prompt = "Descrivi il contenuto di questo documento."
        }
        
        let result = try await analyze(imageData: imageData, prompt: prompt)
        
        return DocumentAnalysis(
            documentType: documentType,
            rawText: result,
            extractedData: parseDocumentResult(result)
        )
    }
    
    private func parseDocumentResult(_ result: String) -> [String: String] {
        // Prova a parsare come JSON
        if let data = result.data(using: .utf8),
           let json = try? JSONDecoder().decode([String: String].self, from: data) {
            return json
        }
        
        // Altrimenti restituisci il testo grezzo
        return ["content": result]
    }
}

// MARK: - Types

public enum DocumentType: String, Codable, Sendable {
    case invoice = "fattura"
    case quote = "preventivo"
    case photo = "foto"
    case report = "verbale"
    case unknown = "altro"
}

public struct DocumentAnalysis: Codable, Sendable {
    public let documentType: DocumentType
    public let rawText: String
    public let extractedData: [String: String]
}

// MARK: - Errors

public enum MLXVisionError: Error, LocalizedError {
    case invalidURL
    case bridgeError
    case invalidResponse
    case modelNotLoaded
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL bridge MLX non valido"
        case .bridgeError:
            return "Errore nel bridge Python MLX"
        case .invalidResponse:
            return "Risposta MLX non valida"
        case .modelNotLoaded:
            return "Modello vision non caricato"
        }
    }
}
