import Foundation

/// Risultato di un task AI
struct AIResult: Codable {
    let taskID: UUID
    let success: Bool
    let provider: AIModelProvider
    let result: AnyCodable?
    let error: AIError?
    var metadata: [String: AnyCodable]
    let processingTime: TimeInterval
    let timestamp: Date
    
    // Fallback tracking
    let attemptedProviders: [AIModelProvider]
    let usedFallback: Bool
    
    init(
        taskID: UUID,
        success: Bool,
        provider: AIModelProvider,
        result: AnyCodable? = nil,
        error: AIError? = nil,
        metadata: [String: AnyCodable] = [:],
        processingTime: TimeInterval = 0,
        timestamp: Date = Date(),
        attemptedProviders: [AIModelProvider] = [],
        usedFallback: Bool = false
    ) {
        self.taskID = taskID
        self.success = success
        self.provider = provider
        self.result = result
        self.error = error
        self.metadata = metadata
        self.processingTime = processingTime
        self.timestamp = timestamp
        self.attemptedProviders = attemptedProviders.isEmpty ? [provider] : attemptedProviders
        self.usedFallback = usedFallback
    }
    
    static func success(
        taskID: UUID,
        provider: AIModelProvider,
        result: Any,
        metadata: [String: Any] = [:],
        processingTime: TimeInterval = 0,
        attemptedProviders: [AIModelProvider] = [],
        usedFallback: Bool = false
    ) -> AIResult {
        AIResult(
            taskID: taskID,
            success: true,
            provider: provider,
            result: AnyCodable(result),
            metadata: metadata.mapValues { AnyCodable($0) },
            processingTime: processingTime,
            attemptedProviders: attemptedProviders,
            usedFallback: usedFallback
        )
    }
    
    static func failure(
        taskID: UUID,
        provider: AIModelProvider,
        error: AIError,
        metadata: [String: Any] = [:],
        processingTime: TimeInterval = 0,
        attemptedProviders: [AIModelProvider] = [],
        usedFallback: Bool = false
    ) -> AIResult {
        AIResult(
            taskID: taskID,
            success: false,
            provider: provider,
            error: error,
            metadata: metadata.mapValues { AnyCodable($0) },
            processingTime: processingTime,
            attemptedProviders: attemptedProviders,
            usedFallback: usedFallback
        )
    }
}

/// Errori AI
enum AIError: Error, Codable {
    case modelUnavailable
    case timeout
    case rateLimitExceeded
    case invalidInput
    case resourceExhausted
    case networkError(String)
    case processingError(String)
    case unknown(String)
    
    var localizedDescription: String {
        switch self {
        case .modelUnavailable:
            return "Modello non disponibile"
        case .timeout:
            return "Timeout durante l'elaborazione"
        case .rateLimitExceeded:
            return "Limite di richieste superato"
        case .invalidInput:
            return "Input non valido"
        case .resourceExhausted:
            return "Risorse di sistema esaurite"
        case .networkError(let message):
            return "Errore di rete: \(message)"
        case .processingError(let message):
            return "Errore di elaborazione: \(message)"
        case .unknown(let message):
            return "Errore sconosciuto: \(message)"
        }
    }
}

/// Stato di un task nella queue
enum AITaskStatus: String, Codable {
    case pending = "pending"
    case running = "running"
    case completed = "completed"
    case failed = "failed"
    case suspended = "suspended"
    case cancelled = "cancelled"
}

/// Informazioni su un task in esecuzione
struct AITaskInfo: Identifiable {
    let id: UUID
    let task: AITask
    var status: AITaskStatus
    var startedAt: Date?
    var completedAt: Date?
    var result: AIResult?
    var progress: Double
    
    init(task: AITask) {
        self.id = task.id
        self.task = task
        self.status = .pending
        self.progress = 0.0
    }
}

