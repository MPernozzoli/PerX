import Foundation

enum PendingOperationType: String, Codable {
    case create
    case update
    case complete
    case delete
}

/// Operazione task in attesa di sincronizzazione con il server.
/// Viene persistita in UserDefaults e riprovata quando il dispositivo
/// torna online.
struct PendingTaskOperation: Codable {
    let localId: UUID
    let type: PendingOperationType
    var cloudId: String?
    var retryCount: Int
    let enqueuedAt: Date

    // Payload — solo i campi rilevanti per il tipo di operazione vengono popolati
    var title: String?
    var taskDescription: String?
    var taskType: String?
    var priority: String?
    var sinistroRef: String?
    var dueDate: Date?
    var assignedTo: String?
    var status: String?

    static func create(task: DailyTask) -> PendingTaskOperation {
        PendingTaskOperation(
            localId: task.id,
            type: .create,
            cloudId: nil,
            retryCount: 0,
            enqueuedAt: Date(),
            title: task.title,
            taskDescription: task.description.isEmpty ? nil : task.description,
            taskType: task.type.rawValue,
            priority: TaskPriorityHelper.toString(task.priority),
            sinistroRef: task.sinistroID,
            dueDate: task.deadline,
            assignedTo: nil,
            status: nil
        )
    }

    static func update(
        localId: UUID,
        cloudId: String?,
        title: String?,
        description: String?,
        priority: Double?,
        dueDate: Date?,
        status: TaskStatus?
    ) -> PendingTaskOperation {
        PendingTaskOperation(
            localId: localId,
            type: .update,
            cloudId: cloudId,
            retryCount: 0,
            enqueuedAt: Date(),
            title: title,
            taskDescription: description,
            taskType: nil,
            priority: priority.map { TaskPriorityHelper.toString($0) },
            sinistroRef: nil,
            dueDate: dueDate,
            assignedTo: nil,
            status: status?.rawValue
        )
    }

    static func complete(localId: UUID, cloudId: String) -> PendingTaskOperation {
        PendingTaskOperation(
            localId: localId,
            type: .complete,
            cloudId: cloudId,
            retryCount: 0,
            enqueuedAt: Date()
        )
    }

    static func delete(localId: UUID, cloudId: String) -> PendingTaskOperation {
        PendingTaskOperation(
            localId: localId,
            type: .delete,
            cloudId: cloudId,
            retryCount: 0,
            enqueuedAt: Date()
        )
    }
}
