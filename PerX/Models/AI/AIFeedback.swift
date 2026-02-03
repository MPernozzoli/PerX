import Foundation

/// Tipo di feedback
enum AIFeedbackType: String, Codable {
    case positive = "positive"  // Pollice su
    case negative = "negative"  // Pollice giù
}

/// Feedback dell'utente su un risultato AI
struct AIFeedback: Identifiable, Codable {
    let id: UUID
    let taskID: UUID
    let taskType: AITaskType
    let provider: AIModelProvider
    let personality: AIPersonality?
    let feedbackType: AIFeedbackType
    let timestamp: Date
    
    // Dati del task originale
    let originalPrompt: String?
    let originalParameters: [String: AnyCodable]
    let originalResult: AnyCodable?
    
    // Feedback aggiuntivo
    var additionalComments: String?
    var specificIssues: [String]?  // Problemi specifici identificati
    var suggestedImprovements: String?
    
    // Metadati
    var userContext: [String: AnyCodable]?  // Contesto utente (es. sinistroID, etc.)
    var modelVersion: String?
    var processingTime: TimeInterval?
    
    init(
        id: UUID = UUID(),
        taskID: UUID,
        taskType: AITaskType,
        provider: AIModelProvider,
        personality: AIPersonality? = nil,
        feedbackType: AIFeedbackType,
        timestamp: Date = Date(),
        originalPrompt: String? = nil,
        originalParameters: [String: AnyCodable] = [:],
        originalResult: AnyCodable? = nil,
        additionalComments: String? = nil,
        specificIssues: [String]? = nil,
        suggestedImprovements: String? = nil,
        userContext: [String: AnyCodable]? = nil,
        modelVersion: String? = nil,
        processingTime: TimeInterval? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.taskType = taskType
        self.provider = provider
        self.personality = personality
        self.feedbackType = feedbackType
        self.timestamp = timestamp
        self.originalPrompt = originalPrompt
        self.originalParameters = originalParameters
        self.originalResult = originalResult
        self.additionalComments = additionalComments
        self.specificIssues = specificIssues
        self.suggestedImprovements = suggestedImprovements
        self.userContext = userContext
        self.modelVersion = modelVersion
        self.processingTime = processingTime
    }
}

/// Statistiche feedback per analisi
struct AIFeedbackStats: Codable {
    let totalFeedback: Int
    let positiveCount: Int
    let negativeCount: Int
    let averageRating: Double  // 0.0 - 1.0
    let feedbackByProvider: [String: Int]
    let feedbackByTaskType: [String: Int]
    let recentFeedback: [AIFeedback]
    
    var positivePercentage: Double {
        guard totalFeedback > 0 else { return 0.0 }
        return Double(positiveCount) / Double(totalFeedback) * 100.0
    }
}

