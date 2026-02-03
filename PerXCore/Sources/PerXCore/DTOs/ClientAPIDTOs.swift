import Foundation

// ============================================================================
// MARK: - Client API DTOs
// DTOs per le API client-hub
// ============================================================================

// MARK: - Email DTOs

public struct EmailDTO: Codable, Sendable, Identifiable {
    public let id: String
    public let subject: String
    public let senderEmail: String
    public let senderName: String?
    public let date: Date
    public let category: String
    public let sinistroRef: String?
    public let direction: String?
    
    public init(
        id: String,
        subject: String,
        senderEmail: String,
        senderName: String?,
        date: Date,
        category: String,
        sinistroRef: String?,
        direction: String?
    ) {
        self.id = id
        self.subject = subject
        self.senderEmail = senderEmail
        self.senderName = senderName
        self.date = date
        self.category = category
        self.sinistroRef = sinistroRef
        self.direction = direction
    }
}

public struct EmailDetailDTO: Codable, Sendable, Identifiable {
    public let id: String
    public let subject: String
    public let senderEmail: String
    public let senderName: String?
    public let recipients: [String]
    public let date: Date
    public let bodyText: String?
    public let bodyHtml: String?
    public let category: String
    public let sinistroRef: String?
    public let direction: String?
    
    public init(
        id: String,
        subject: String,
        senderEmail: String,
        senderName: String?,
        recipients: [String],
        date: Date,
        bodyText: String?,
        bodyHtml: String?,
        category: String,
        sinistroRef: String?,
        direction: String?
    ) {
        self.id = id
        self.subject = subject
        self.senderEmail = senderEmail
        self.senderName = senderName
        self.recipients = recipients
        self.date = date
        self.bodyText = bodyText
        self.bodyHtml = bodyHtml
        self.category = category
        self.sinistroRef = sinistroRef
        self.direction = direction
    }
}

// MARK: - Task DTOs
// Nota: ScheduledEmailDTO, SinistroDTO, StateChangeRequest, StateChangeResponse,
// CreateTaskRequest, UpdateTaskRequest sono definiti in VaultDTOs.swift

public struct TaskDTO: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let description: String?
    public let type: String
    public let priority: String
    public let status: String
    public let sinistroRef: String?
    public let dueDate: Date?
    public let assignedTo: String?
    public let createdBy: String?
    public let createdAt: Date
    public let completedAt: Date?
    
    public init(from task: HubTask) {
        self.id = task.id
        self.title = task.title
        self.description = task.description
        self.type = task.type.rawValue
        self.priority = task.priority.rawValue
        self.status = task.status.rawValue
        self.sinistroRef = task.sinistroRef
        self.dueDate = task.dueDate
        self.assignedTo = task.assignedTo
        self.createdBy = task.createdBy
        self.createdAt = task.createdAt
        self.completedAt = task.completedAt
    }
    
    public init(
        id: String,
        title: String,
        description: String?,
        type: String,
        priority: String,
        status: String,
        sinistroRef: String?,
        dueDate: Date?,
        assignedTo: String?,
        createdBy: String?,
        createdAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.type = type
        self.priority = priority
        self.status = status
        self.sinistroRef = sinistroRef
        self.dueDate = dueDate
        self.assignedTo = assignedTo
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}
