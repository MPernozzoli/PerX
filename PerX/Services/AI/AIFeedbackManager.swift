import Foundation

/// Manager per integrare il sistema di feedback nel flusso AI
class AIFeedbackManager {
    static let shared = AIFeedbackManager()
    
    private let feedbackService = AIFeedbackService.shared
    private let aiManager = AIManager.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// Registra un feedback per un risultato AI
    func submitFeedback(
        result: AIResult,
        task: AITask,
        feedbackType: AIFeedbackType,
        additionalInfo: FeedbackAdditionalInfo? = nil,
        userContext: [String: Any]? = nil
    ) {
        switch feedbackType {
        case .positive:
            feedbackService.submitPositiveFeedback(
                for: result,
                task: task,
                additionalComments: additionalInfo?.comments,
                userContext: userContext
            )
        case .negative:
            feedbackService.submitNegativeFeedback(
                for: result,
                task: task,
                additionalComments: additionalInfo?.comments,
                specificIssues: additionalInfo?.issues,
                suggestedImprovements: additionalInfo?.improvements,
                userContext: userContext
            )
        }
    }
    
    /// Ottiene statistiche feedback per un provider
    func getProviderStats(_ provider: AIModelProvider) -> ProviderFeedbackStats {
        let allFeedback = feedbackService.getAllFeedback()
        let providerFeedback = allFeedback.filter { $0.provider == provider }
        
        let positive = providerFeedback.filter { $0.feedbackType == .positive }.count
        let negative = providerFeedback.filter { $0.feedbackType == .negative }.count
        let total = providerFeedback.count
        
        return ProviderFeedbackStats(
            provider: provider,
            totalFeedback: total,
            positiveCount: positive,
            negativeCount: negative,
            positivePercentage: total > 0 ? Double(positive) / Double(total) * 100.0 : 0.0
        )
    }
    
    /// Verifica se un risultato ha già ricevuto feedback
    func hasFeedback(for taskID: UUID) -> Bool {
        let allFeedback = feedbackService.getAllFeedback()
        return allFeedback.contains { $0.taskID == taskID }
    }
}

/// Informazioni aggiuntive per feedback
struct FeedbackAdditionalInfo {
    var comments: String?
    var issues: [String]?
    var improvements: String?
}

/// Statistiche feedback per provider
struct ProviderFeedbackStats {
    let provider: AIModelProvider
    let totalFeedback: Int
    let positiveCount: Int
    let negativeCount: Int
    let positivePercentage: Double
}

