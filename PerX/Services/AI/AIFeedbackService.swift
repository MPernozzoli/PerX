import Foundation
import CoreData

/// Servizio per gestire i feedback degli utenti sui risultati AI
class AIFeedbackService {
    static let shared = AIFeedbackService()
    
    private var feedbackStorage: [AIFeedback] = []
    private let storageKey = "ai_feedback_storage"
    private let maxStoredFeedback = 10000  // Limite per evitare crescita eccessiva
    
    private init() {
        loadFeedback()
    }
    
    // MARK: - Public API
    
    /// Registra un feedback positivo
    func submitPositiveFeedback(
        for result: AIResult,
        task: AITask,
        additionalComments: String? = nil,
        userContext: [String: Any]? = nil
    ) {
        let feedback = createFeedback(
            result: result,
            task: task,
            feedbackType: .positive,
            additionalComments: additionalComments,
            userContext: userContext
        )
        
        saveFeedback(feedback)
    }
    
    /// Registra un feedback negativo
    func submitNegativeFeedback(
        for result: AIResult,
        task: AITask,
        additionalComments: String? = nil,
        specificIssues: [String]? = nil,
        suggestedImprovements: String? = nil,
        userContext: [String: Any]? = nil
    ) {
        let feedback = createFeedback(
            result: result,
            task: task,
            feedbackType: .negative,
            additionalComments: additionalComments,
            specificIssues: specificIssues,
            suggestedImprovements: suggestedImprovements,
            userContext: userContext
        )
        
        saveFeedback(feedback)
    }
    
    /// Feedback puntuale su un campo (es. bene/modello) con certezza
    func submitFieldFeedback(
        for result: AIResult,
        task: AITask,
        fieldName: String,
        fieldValue: String?,
        confidence: Double?,
        positive: Bool,
        additionalComments: String? = nil
    ) {
        let userContext: [String: Any] = [
            "field": fieldName,
            "value": fieldValue ?? "",
            "confidence": confidence ?? 0
        ]
        let feedback = createFeedback(
            result: result,
            task: task,
            feedbackType: positive ? .positive : .negative,
            additionalComments: additionalComments,
            userContext: userContext
        )
        saveFeedback(feedback)
    }
    
    /// Ottiene tutti i feedback
    func getAllFeedback() -> [AIFeedback] {
        return feedbackStorage
    }
    
    /// Ottiene feedback per un provider specifico
    func getFeedback(for provider: AIModelProvider) -> [AIFeedback] {
        return feedbackStorage.filter { $0.provider == provider }
    }
    
    /// Ottiene feedback per un tipo di task
    func getFeedback(for taskType: AITaskType) -> [AIFeedback] {
        return feedbackStorage.filter { $0.taskType == taskType }
    }
    
    /// Ottiene statistiche feedback
    func getFeedbackStats() -> AIFeedbackStats {
        let positiveCount = feedbackStorage.filter { $0.feedbackType == .positive }.count
        let negativeCount = feedbackStorage.filter { $0.feedbackType == .negative }.count
        let total = feedbackStorage.count
        
        let averageRating = total > 0 ? Double(positiveCount) / Double(total) : 0.0
        
        // Feedback per provider
        var feedbackByProvider: [String: Int] = [:]
        for feedback in feedbackStorage {
            let key = feedback.provider.rawValue
            feedbackByProvider[key, default: 0] += 1
        }
        
        // Feedback per tipo task
        var feedbackByTaskType: [String: Int] = [:]
        for feedback in feedbackStorage {
            let key = feedback.taskType.rawValue
            feedbackByTaskType[key, default: 0] += 1
        }
        
        // Feedback recenti (ultimi 50)
        let recentFeedback = Array(feedbackStorage.suffix(50))
        
        return AIFeedbackStats(
            totalFeedback: total,
            positiveCount: positiveCount,
            negativeCount: negativeCount,
            averageRating: averageRating,
            feedbackByProvider: feedbackByProvider,
            feedbackByTaskType: feedbackByTaskType,
            recentFeedback: recentFeedback
        )
    }
    
    /// Esporta feedback per fine-tuning
    func exportFeedbackForFineTuning(format: ExportFormat = .json) -> Data? {
        switch format {
        case .json:
            return exportAsJSON()
        case .csv:
            return exportAsCSV()
        }
    }
    
    /// Pulisce feedback vecchi (oltre il limite)
    func cleanupOldFeedback() {
        guard feedbackStorage.count > maxStoredFeedback else { return }
        
        // Mantieni i più recenti
        feedbackStorage = Array(feedbackStorage.suffix(maxStoredFeedback))
        saveFeedbackToStorage()
    }
    
    // MARK: - Private Implementation
    
    private func createFeedback(
        result: AIResult,
        task: AITask,
        feedbackType: AIFeedbackType,
        additionalComments: String? = nil,
        specificIssues: [String]? = nil,
        suggestedImprovements: String? = nil,
        userContext: [String: Any]? = nil
    ) -> AIFeedback {
        // Estrai prompt originale se disponibile
        let originalPrompt = task.parameters["prompt"]?.value as? String
        
        // Converti userContext
        let userContextCodable = userContext?.mapValues { AnyCodable($0) }
        
        return AIFeedback(
            taskID: task.id,
            taskType: task.type,
            provider: result.provider,
            personality: task.personality,
            feedbackType: feedbackType,
            originalPrompt: originalPrompt,
            originalParameters: task.parameters,
            originalResult: result.result,
            additionalComments: additionalComments,
            specificIssues: specificIssues,
            suggestedImprovements: suggestedImprovements,
            userContext: userContextCodable,
            modelVersion: extractModelVersion(from: result),
            processingTime: result.processingTime
        )
    }
    
    private func extractModelVersion(from result: AIResult) -> String? {
        return result.metadata["model"]?.value as? String
    }
    
    private func saveFeedback(_ feedback: AIFeedback) {
        feedbackStorage.append(feedback)
        
        // Cleanup periodico
        if feedbackStorage.count > maxStoredFeedback {
            cleanupOldFeedback()
        } else {
            saveFeedbackToStorage()
        }
        
        // Log per debug
        print("[AIFeedback] ✅ Feedback salvato: \(feedback.feedbackType.rawValue) per task \(feedback.taskID)")
    }
    
    private func saveFeedbackToStorage() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(feedbackStorage)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("[AIFeedback] ❌ Errore nel salvare feedback: \(error)")
        }
    }
    
    private func loadFeedback() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            feedbackStorage = try decoder.decode([AIFeedback].self, from: data)
            print("[AIFeedback] ✅ Caricati \(feedbackStorage.count) feedback")
        } catch {
            print("[AIFeedback] ❌ Errore nel caricare feedback: \(error)")
            feedbackStorage = []
        }
    }
    
    private func exportAsJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try? encoder.encode(feedbackStorage)
    }
    
    private func exportAsCSV() -> Data? {
        var csv = "ID,TaskID,TaskType,Provider,Personality,FeedbackType,Timestamp,HasComments,IssuesCount\n"
        
        for feedback in feedbackStorage {
            let line = [
                feedback.id.uuidString,
                feedback.taskID.uuidString,
                feedback.taskType.rawValue,
                feedback.provider.rawValue,
                feedback.personality?.rawValue ?? "",
                feedback.feedbackType.rawValue,
                ISO8601DateFormatter().string(from: feedback.timestamp),
                feedback.additionalComments != nil ? "Yes" : "No",
                String(feedback.specificIssues?.count ?? 0)
            ].joined(separator: ",")
            
            csv += line + "\n"
        }
        
        return csv.data(using: .utf8)
    }
    
    enum ExportFormat {
        case json
        case csv
    }
}

