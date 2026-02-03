import Foundation
import PerXCore
import Vapor

// ============================================================================
// MARK: - AIManager (Hub version)
// Gestisce i provider AI locali sull'Hub: Ollama, Apple Intelligence, MLX Vision
// ============================================================================

public actor HubAIManager {
    public static let shared = HubAIManager()
    
    // Providers
    private let ollamaProvider: OllamaProvider
    private let appleIntelligenceProvider: AppleIntelligenceProvider
    private let mlxVisionProvider: MLXVisionProvider
    
    // Config
    private var preferredTextProvider: AIProviderType = .ollama
    private var preferredVisionProvider: AIProviderType = .mlxVision
    
    private init() {
        ollamaProvider = OllamaProvider()
        appleIntelligenceProvider = AppleIntelligenceProvider()
        mlxVisionProvider = MLXVisionProvider()
        
        print("[HubAIManager] ✅ Inizializzato")
    }
    
    // MARK: - Public API
    
    /// Classifica un'email con AI quando il pattern matching fallisce
    public func classifyEmail(
        subject: String,
        body: String,
        senderEmail: String
    ) async throws -> AIEmailClassification {
        let prompt = buildEmailClassificationPrompt(
            subject: subject,
            body: body,
            senderEmail: senderEmail
        )
        
        // Usa provider text
        let response = try await generateText(prompt: prompt)
        
        // Parse risposta
        return parseEmailClassification(response)
    }
    
    /// Estrae informazioni da un'email di assegnazione
    public func extractAssignmentInfo(body: String) async throws -> [String: String] {
        let prompt = """
        Estrai le seguenti informazioni dall'email di assegnazione se presenti:
        - riferimento: il numero di riferimento del sinistro (7 cifre)
        - nome: il nome dell'assicurato/contraente
        - telefono: il numero di telefono
        - email: l'indirizzo email
        - indirizzo: l'indirizzo del rischio
        
        Rispondi SOLO in formato JSON, es: {"riferimento": "1234567", "nome": "Mario Rossi"}
        Se un campo non è presente, non includerlo.
        
        Testo email:
        \(body.prefix(2000))
        """
        
        let response = try await generateText(prompt: prompt)
        
        // Parse JSON
        if let data = response.data(using: .utf8),
           let json = try? JSONDecoder().decode([String: String].self, from: data) {
            return json
        }
        
        return [:]
    }
    
    /// Analizza email per determinare se parla di file caricati
    public func analyzeForFileNotification(body: String) async throws -> Bool {
        let prompt = """
        Analizza questa email e rispondi SOLO con SI o NO.
        La mail parla di file/documenti/foto caricati in una cartella o database (Jfish)?
        
        Testo: \(body.prefix(500))
        """
        
        let response = try await generateText(prompt: prompt)
        return response.lowercased().contains("si")
    }
    
    /// Analizza un documento/immagine
    public func analyzeDocument(
        imageData: Data,
        prompt: String? = nil
    ) async throws -> String {
        let analysisPrompt = prompt ?? "Analizza questo documento e descrivi il contenuto."
        
        // Usa MLX Vision se disponibile
        if await mlxVisionProvider.isAvailable {
            return try await mlxVisionProvider.analyze(imageData: imageData, prompt: analysisPrompt)
        }
        
        throw AIManagerError.providerUnavailable("Nessun provider vision disponibile")
    }
    
    /// Genera testo con il provider migliore disponibile
    public func generateText(prompt: String, maxTokens: Int = 1024) async throws -> String {
        // Catena di fallback
        let providers: [AIProviderType] = [.ollama, .appleIntelligence]
        
        for providerType in providers {
            do {
                switch providerType {
                case .ollama:
                    if await ollamaProvider.isAvailable {
                        return try await ollamaProvider.generate(prompt: prompt, maxTokens: maxTokens)
                    }
                case .appleIntelligence:
                    if await appleIntelligenceProvider.isAvailable {
                        return try await appleIntelligenceProvider.generate(prompt: prompt)
                    }
                case .mlxVision:
                    // Vision non è per text-only
                    continue
                }
            } catch {
                print("[HubAIManager] ⚠️ Provider \(providerType) fallito: \(error)")
                continue
            }
        }
        
        throw AIManagerError.allProvidersFailed
    }
    
    /// Verifica disponibilità dei provider
    public func getProvidersStatus() async -> [AIProviderStatus] {
        return [
            AIProviderStatus(
                provider: .ollama,
                available: await ollamaProvider.isAvailable,
                modelName: ollamaProvider.currentModel
            ),
            AIProviderStatus(
                provider: .appleIntelligence,
                available: await appleIntelligenceProvider.isAvailable,
                modelName: "Apple Foundation Models"
            ),
            AIProviderStatus(
                provider: .mlxVision,
                available: await mlxVisionProvider.isAvailable,
                modelName: mlxVisionProvider.currentModel
            )
        ]
    }
    
    // MARK: - Email Classification Helpers
    
    private func buildEmailClassificationPrompt(
        subject: String,
        body: String,
        senderEmail: String
    ) -> String {
        return """
        Classifica questa email in una delle seguenti categorie:
        - assignment: assegnazione nuovo incarico
        - revocation: revoca incarico
        - controlled: perizia controllata
        - revision_requested: richiesta revisione
        - documentation_request: richiesta documentazione
        - documentation_received: documentazione ricevuta
        - reminder_received: sollecito ricevuto
        - reminder_sent: sollecito inviato
        - survey_scheduled: sopralluogo fissato
        - survey_returned: sopralluogo restituito
        - videocall_scheduled: videoperizia fissata
        - act_sent: atto inviato
        - act_received: atto firmato ricevuto
        - clarification_request: richiesta chiarimenti
        - outcome_sent: esito comunicato
        - verbal_acceptance: accettazione verbale
        - generic: comunicazione generica
        
        Mittente: \(senderEmail)
        Oggetto: \(subject)
        Corpo (primi 500 caratteri): \(body.prefix(500))
        
        Rispondi SOLO con la categoria in formato: CATEGORY: nome_categoria
        """
    }
    
    private func parseEmailClassification(_ response: String) -> AIEmailClassification {
        let lowered = response.lowercased()
        
        // Cerca pattern "category: xxx"
        if let range = lowered.range(of: "category:") {
            let after = lowered[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let category = after.components(separatedBy: .whitespaces).first ?? "generic"
            
            if let emailCategory = EmailCategory(rawValue: category) {
                return AIEmailClassification(category: emailCategory, confidence: 0.8)
            }
        }
        
        // Fallback: cerca la categoria direttamente nel testo
        for category in EmailCategory.allCases {
            if lowered.contains(category.rawValue) {
                return AIEmailClassification(category: category, confidence: 0.6)
            }
        }
        
        return AIEmailClassification(category: .genericCommunication, confidence: 0.3)
    }
}

// MARK: - Types

public enum AIProviderType: String, Codable, Sendable {
    case ollama
    case appleIntelligence
    case mlxVision
}

public struct AIProviderStatus: Codable, Sendable, Content {
    public let provider: AIProviderType
    public let available: Bool
    public let modelName: String?
}

public struct AIEmailClassification: Codable, Sendable, Content {
    public let category: EmailCategory
    public let confidence: Double
}

public enum AIManagerError: Error, LocalizedError {
    case providerUnavailable(String)
    case allProvidersFailed
    case invalidResponse
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .providerUnavailable(let msg):
            return "Provider non disponibile: \(msg)"
        case .allProvidersFailed:
            return "Tutti i provider AI sono falliti"
        case .invalidResponse:
            return "Risposta AI non valida"
        case .timeout:
            return "Timeout nella risposta AI"
        }
    }
}
