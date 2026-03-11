import Foundation

/// Priorità di un task AI
enum AITaskPriority: Int, Comparable, Codable {
    case secondary = 0
    case primary = 1
    
    static func < (lhs: AITaskPriority, rhs: AITaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Tipo di task AI
enum AITaskType: String, Codable {
    case documentAnalysis = "document_analysis"
    case emailSummary = "email_summary"
    case textGeneration = "text_generation"
    case imageAnalysis = "image_analysis"
    case textAnalysis = "text_analysis"
    case documentExtraction = "document_extraction"
    case guardrailing = "guardrailing"
    case chat = "chat"
}

/// Provider del modello AI
enum AIModelProvider: String, Codable, CaseIterable {
    case localMultimodal = "local_multimodal"  // IBM Vulkan
    case localText = "local_text"              // Microsoft Phi-3/4
    case appleIntelligence = "apple_intelligence"
    case cloudOpenAI = "cloud_openai"
    
    /// Nome user-friendly del provider
    var displayName: String {
        switch self {
        case .localMultimodal: return "Modello Locale Vision"
        case .localText: return "Modello Locale Testo (Phi-4)"
        case .appleIntelligence: return "Apple Intelligence"
        case .cloudOpenAI: return "OpenAI Cloud"
        }
    }
}

/// Identità/personalità dell'IA
enum AIPersonality: String, Codable {
    case elettra = "elettra"  // Front desk
    case sparky = "sparky"    // Tecnico
}

/// Task AI da eseguire
struct AITask: Identifiable, Codable {
    let id: UUID
    let type: AITaskType
    let priority: AITaskPriority
    var preferredProvider: AIModelProvider?
    var personality: AIPersonality?
    var parameters: [String: AnyCodable]
    var context: [String: AnyCodable]?
    var createdAt: Date
    var retryCount: Int
    
    // Fallback configuration
    var fallbackProviders: [AIModelProvider]?  // Lista ordinata di provider fallback
    var allowFallback: Bool  // Se false, non usa fallback automatico
    var maxRetries: Int  // Max tentativi per singolo provider
    
    // Knowledge Bounded Prompting
    var requiresKnowledge: Bool
    var knowledgeDomains: [KnowledgeDomain]?
    var knowledgeQueryOverride: String?
    var maxKnowledgeChunks: Int?
    var knowledgeChunks: [KnowledgeChunk]
    
    init(
        id: UUID = UUID(),
        type: AITaskType,
        priority: AITaskPriority = .secondary,
        preferredProvider: AIModelProvider? = nil,
        fallbackProviders: [AIModelProvider]? = nil,
        allowFallback: Bool = true,
        maxRetries: Int = 1,
        personality: AIPersonality? = nil,
        parameters: [String: AnyCodable] = [:],
        context: [String: AnyCodable]? = nil,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        requiresKnowledge: Bool = false,
        knowledgeDomains: [KnowledgeDomain]? = nil,
        knowledgeQueryOverride: String? = nil,
        maxKnowledgeChunks: Int? = nil,
        knowledgeChunks: [KnowledgeChunk] = []
    ) {
        self.id = id
        self.type = type
        self.priority = priority
        self.preferredProvider = preferredProvider
        self.fallbackProviders = fallbackProviders
        self.allowFallback = allowFallback
        self.maxRetries = maxRetries
        self.personality = personality
        self.parameters = parameters
        self.context = context
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.requiresKnowledge = requiresKnowledge
        self.knowledgeDomains = knowledgeDomains
        self.knowledgeQueryOverride = knowledgeQueryOverride
        self.maxKnowledgeChunks = maxKnowledgeChunks
        self.knowledgeChunks = knowledgeChunks
    }
}

// AnyCodable è definito in Utils/AnyCodable.swift

/// Convenience extensions per creare task comuni
extension AITask {
    static func documentAnalysis(
        filePath: String,
        sinistroID: String? = nil,
        priority: AITaskPriority = .secondary,
        allowFallback: Bool = true
    ) -> AITask {
        AITask(
            type: .documentAnalysis,
            priority: priority,
            preferredProvider: .localMultimodal,
            fallbackProviders: [.cloudOpenAI],
            allowFallback: allowFallback,
            parameters: [
                "filePath": AnyCodable(filePath),
                "sinistroID": AnyCodable(sinistroID ?? "")
            ]
        )
    }
    
    static func emailSummary(
        subject: String,
        body: String,
        priority: AITaskPriority = .primary,
        allowFallback: Bool = true
    ) -> AITask {
        AITask(
            type: .emailSummary,
            priority: priority,
            preferredProvider: .appleIntelligence,
            fallbackProviders: [.localText, .cloudOpenAI],
            allowFallback: allowFallback,
            personality: .elettra,
            parameters: [
                "subject": AnyCodable(subject),
                "body": AnyCodable(body)
            ]
        )
    }
    
    static func imageAnalysis(
        imagePath: String,
        sinistroID: String? = nil,
        priority: AITaskPriority = .secondary,
        allowFallback: Bool = true
    ) -> AITask {
        AITask(
            type: .imageAnalysis,
            priority: priority,
            preferredProvider: .localMultimodal,
            fallbackProviders: [.cloudOpenAI],
            allowFallback: allowFallback,
            parameters: [
                "imagePath": AnyCodable(imagePath),
                "sinistroID": AnyCodable(sinistroID ?? "")
            ]
        )
    }
    
    static func textGeneration(
        prompt: String,
        personality: AIPersonality = .elettra,
        priority: AITaskPriority = .primary,
        allowFallback: Bool = true
    ) -> AITask {
        AITask(
            type: .textGeneration,
            priority: priority,
            preferredProvider: .localText,
            fallbackProviders: [.localMultimodal, .cloudOpenAI],
            allowFallback: allowFallback,
            personality: personality,
            parameters: [
                "prompt": AnyCodable(prompt)
            ]
        )
    }
    
    /// Riassunto giornaliero per la dashboard (Apple Intelligence preferito).
    static func dailyDashboardSummary(prompt: String) -> AITask {
        AITask(
            type: .textGeneration,
            priority: .secondary,
            preferredProvider: .appleIntelligence,
            fallbackProviders: [.localText, .cloudOpenAI],
            allowFallback: true,
            personality: .elettra,
            parameters: ["prompt": AnyCodable(prompt)]
        )
    }
}

