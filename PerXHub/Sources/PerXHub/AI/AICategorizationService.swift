import Foundation
import PerXCore

/// Servizio AI per categorizzazione email quando il pattern matching fallisce
/// Placeholder per integrazione futura con modelli AI
public actor AICategorizationService {
    public static let shared = AICategorizationService()
    
    // Configurazione AI
    private var aiEndpoint: String?
    private var apiKey: String?
    private var isEnabled = false
    
    private init() {}
    
    // MARK: - Configuration
    
    public func configure(endpoint: String, apiKey: String) {
        self.aiEndpoint = endpoint
        self.apiKey = apiKey
        self.isEnabled = true
        print("[AI] Configured with endpoint: \(endpoint)")
    }
    
    public func disable() {
        self.isEnabled = false
    }
    
    // MARK: - Categorization
    
    /// Categorizza email usando AI (fallback quando pattern matching fallisce)
    public func categorizeEmail(subject: String?, body: String?) async throws -> AICategorizationResult {
        guard isEnabled else {
            return AICategorizationResult(category: nil, confidence: 0, fallbackUsed: true)
        }
        
        // Prepara prompt
        let text = "\(subject ?? "") \(body ?? "")"
        let truncated = String(text.prefix(2000))
        
        // TODO: Chiamata a endpoint AI (OpenAI, Claude, o modello locale)
        // Per ora ritorna nil con fallback
        
        print("[AI] Categorizing email with AI...")
        
        // Placeholder: simula chiamata AI
        let result = await simulateAICategorization(text: truncated)
        
        return result
    }
    
    /// Estrai sinistro ref usando AI
    public func extractSinistroRef(text: String) async throws -> AIExtractionResult {
        guard isEnabled else {
            return AIExtractionResult(sinistroRef: nil, confidence: 0)
        }
        
        // TODO: Chiamata a endpoint AI per NER
        print("[AI] Extracting sinistro ref with AI...")
        
        return AIExtractionResult(sinistroRef: nil, confidence: 0)
    }
    
    /// Suggerisci risposta a email
    public func suggestReply(to email: ClassifiedEmail) async throws -> AISuggestion? {
        guard isEnabled else { return nil }
        
        // TODO: Generazione risposta con AI
        print("[AI] Generating reply suggestion...")
        
        return nil
    }
    
    /// Analizza sentiment email
    public func analyzeSentiment(text: String) async throws -> SentimentResult {
        guard isEnabled else {
            return SentimentResult(sentiment: .neutral, confidence: 0)
        }
        
        // TODO: Analisi sentiment con AI
        return SentimentResult(sentiment: .neutral, confidence: 0)
    }
    
    // MARK: - Simulation (placeholder)
    
    private func simulateAICategorization(text: String) async -> AICategorizationResult {
        // Simulazione ritardo AI
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Regole euristiche come fallback (usando categorie da PerXCore)
        let lowered = text.lowercased()
        
        var category: EmailCategory? = nil
        var confidence: Double = 0.0
        
        if lowered.contains("urgente") || lowered.contains("sollecito") {
            category = .reminderReceived
            confidence = 0.7
        } else if lowered.contains("fattura") {
            category = .administrative
            confidence = 0.85
        } else if lowered.contains("documentazione") {
            category = .documentationReceived
            confidence = 0.75
        }
        
        return AICategorizationResult(
            category: category,
            confidence: confidence,
            fallbackUsed: true
        )
    }
}

// MARK: - Types

public struct AICategorizationResult: Codable, Sendable {
    public let category: EmailCategory?
    public let confidence: Double
    public let fallbackUsed: Bool
    
    public var isReliable: Bool {
        confidence >= 0.7
    }
}

public struct AIExtractionResult: Codable, Sendable {
    public let sinistroRef: String?
    public let confidence: Double
}

public struct AISuggestion: Codable, Sendable {
    public let text: String
    public let confidence: Double
    public let type: SuggestionType
}

public enum SuggestionType: String, Codable, Sendable {
    case reply
    case forward
    case archive
    case delegate
}

public struct SentimentResult: Codable, Sendable {
    public let sentiment: Sentiment
    public let confidence: Double
}

public enum Sentiment: String, Codable, Sendable {
    case positive
    case neutral
    case negative
    case urgent
}
