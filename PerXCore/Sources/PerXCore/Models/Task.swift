import Foundation

// ============================================================================
// MARK: - Task Models (condivisi tra Hub e Client)
// ============================================================================

/// Task centralizzato per Hub e Client
public struct HubTask: Codable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var description: String?
    public var type: TaskType
    public var priority: TaskPriority
    public var sinistroRef: String?
    public var dueDate: Date?
    public var reminderDate: Date?
    public var status: TaskStatus
    public var assignedTo: String?
    public var createdBy: String?
    public var createdAt: Date
    public var completedAt: Date?
    public var syncedToCK: Bool
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String? = nil,
        type: TaskType = .action,
        priority: TaskPriority = .normal,
        sinistroRef: String? = nil,
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        status: TaskStatus = .pending,
        assignedTo: String? = nil,
        createdBy: String? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        syncedToCK: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.type = type
        self.priority = priority
        self.sinistroRef = sinistroRef
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.status = status
        self.assignedTo = assignedTo
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.syncedToCK = syncedToCK
    }
    
    /// true se il task è in scadenza (entro 24 ore)
    public var isDueSoon: Bool {
        guard let dueDate = dueDate else { return false }
        return dueDate.timeIntervalSinceNow < 86400 && dueDate.timeIntervalSinceNow > 0
    }
    
    /// true se il task è scaduto
    public var isOverdue: Bool {
        guard let dueDate = dueDate else { return false }
        return dueDate < Date() && status != .completed && status != .cancelled
    }
}

// MARK: - Task Type

public enum TaskType: String, Codable, Sendable, CaseIterable {
    case generic        // Task generico
    case action         // Azione da compiere
    case reminder       // Promemoria
    case deadline       // Scadenza
    case followUp       // Follow-up
    case email          // Email da inviare
    case appointment    // Appuntamento
    case call           // Chiamata
    case document       // Documento da preparare
    case review         // Revisione
    
    public var displayName: String {
        switch self {
        case .generic: return "Generico"
        case .action: return "Azione"
        case .reminder: return "Promemoria"
        case .deadline: return "Scadenza"
        case .followUp: return "Follow-up"
        case .email: return "Email"
        case .appointment: return "Appuntamento"
        case .call: return "Chiamata"
        case .document: return "Documento"
        case .review: return "Revisione"
        }
    }
    
    public var iconName: String {
        switch self {
        case .generic: return "square.fill"
        case .action: return "checkmark.circle"
        case .reminder: return "bell"
        case .deadline: return "clock.badge.exclamationmark"
        case .followUp: return "arrow.turn.up.right"
        case .email: return "envelope"
        case .appointment: return "calendar"
        case .call: return "phone"
        case .document: return "doc"
        case .review: return "eye"
        }
    }
}

// MARK: - Task Priority

public enum TaskPriority: String, Codable, Sendable, CaseIterable {
    case low
    case normal
    case medium    // Alias per normal (retrocompatibilità)
    case high
    case urgent
    
    public var displayName: String {
        switch self {
        case .low: return "Bassa"
        case .normal, .medium: return "Normale"
        case .high: return "Alta"
        case .urgent: return "Urgente"
        }
    }
    
    public var sortOrder: Int {
        switch self {
        case .urgent: return 0
        case .high: return 1
        case .normal, .medium: return 2
        case .low: return 3
        }
    }
    
    public var colorHex: String {
        switch self {
        case .low: return "#808080"      // gray
        case .normal, .medium: return "#0000FF"   // blue
        case .high: return "#FFA500"     // orange
        case .urgent: return "#FF0000"   // red
        }
    }
}

// MARK: - Task Status

public enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case inProgress
    case completed
    case cancelled
    case deferred
    
    public var displayName: String {
        switch self {
        case .pending: return "Da fare"
        case .inProgress: return "In corso"
        case .completed: return "Completato"
        case .cancelled: return "Annullato"
        case .deferred: return "Posticipato"
        }
    }
    
    public var isActive: Bool {
        switch self {
        case .pending, .inProgress: return true
        default: return false
        }
    }
}

// MARK: - Task DTOs

/// DTO per creazione task via API
public struct CreateTaskRequest: Codable, Sendable {
    public let title: String
    public let description: String?
    public let type: TaskType
    public let priority: TaskPriority
    public let sinistroRef: String?
    public let dueDate: Date?
    public let reminderDate: Date?
    public let assignedTo: String?
    public let createdBy: String
    
    public init(
        title: String,
        description: String? = nil,
        type: TaskType = .action,
        priority: TaskPriority = .normal,
        sinistroRef: String? = nil,
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        assignedTo: String? = nil,
        createdBy: String
    ) {
        self.title = title
        self.description = description
        self.type = type
        self.priority = priority
        self.sinistroRef = sinistroRef
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.assignedTo = assignedTo
        self.createdBy = createdBy
    }
}

/// DTO per aggiornamento task
public struct UpdateTaskRequest: Codable, Sendable {
    public let id: String
    public let title: String?
    public let description: String?
    public let priority: TaskPriority?
    public let dueDate: Date?
    public let reminderDate: Date?
    public let status: TaskStatus?
    public let assignedTo: String?
    
    public init(
        id: String,
        title: String? = nil,
        description: String? = nil,
        priority: TaskPriority? = nil,
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        status: TaskStatus? = nil,
        assignedTo: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.priority = priority
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.status = status
        self.assignedTo = assignedTo
    }
}

/// DTO per lista task con filtri
public struct TaskListRequest: Codable, Sendable {
    public let userId: String?
    public let sinistroRef: String?
    public let status: [TaskStatus]?
    public let priority: [TaskPriority]?
    public let dueBefore: Date?
    public let dueAfter: Date?
    public let limit: Int?
    public let offset: Int?
    
    public init(
        userId: String? = nil,
        sinistroRef: String? = nil,
        status: [TaskStatus]? = nil,
        priority: [TaskPriority]? = nil,
        dueBefore: Date? = nil,
        dueAfter: Date? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) {
        self.userId = userId
        self.sinistroRef = sinistroRef
        self.status = status
        self.priority = priority
        self.dueBefore = dueBefore
        self.dueAfter = dueAfter
        self.limit = limit
        self.offset = offset
    }
}

/// Risposta lista task
public struct TaskListResponse: Codable, Sendable {
    public let tasks: [HubTask]
    public let total: Int
    public let hasMore: Bool
    
    public init(tasks: [HubTask], total: Int, hasMore: Bool = false) {
        self.tasks = tasks
        self.total = total
        self.hasMore = hasMore
    }
}
