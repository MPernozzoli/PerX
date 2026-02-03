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

/// Wrapper per permettere Codable con Any
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}

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
}

