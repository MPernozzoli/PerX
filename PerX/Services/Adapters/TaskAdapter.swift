import Foundation
import Combine

private struct EmptyBody: Encodable {}

// ============================================================================
// MARK: - TaskAdapter
// Adapter per task con routing locale/Hub
// ============================================================================

@MainActor
final class TaskAdapter: ObservableObject {
    static let shared = TaskAdapter()
    
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    
    private let hubMode = HubModeService.shared
    private let hubClient = HubAPIAdapterClient.shared
    
    private init() {}
    
    // MARK: - Fetch Tasks
    
    /// Recupera task per utente (passare currentUsername da CurrentUserService)
    func getTasks(userId: String, userEmail: String? = nil) async throws -> [TaskListItem] {
        if hubClient.isCloudConfigured {
            return try await fetchFromCloud()
        } else if hubMode.shouldUseHub(for: .task) {
            return try await fetchFromHub(userId: userId, userEmail: userEmail)
        } else {
            return try await fetchFromLocal(userId: userId, userEmail: userEmail)
        }
    }
    
    /// Recupera task per sinistro
    func getTasks(sinistroRef: String) async throws -> [TaskListItem] {
        if hubClient.isCloudConfigured {
            return try await fetchFromCloud(sinistroRef: sinistroRef)
        } else if hubMode.shouldUseHub(for: .task) {
            return try await fetchFromHub(sinistroRef: sinistroRef)
        } else {
            return try await fetchFromLocal(sinistroRef: sinistroRef)
        }
    }
    
    // MARK: - Actions
    
    /// Crea nuovo task
    func createTask(
        title: String,
        description: String?,
        type: TaskType,
        priority: Double,
        sinistroRef: String?,
        dueDate: Date?,
        assignedTo: String?
    ) async throws -> TaskListItem {
        if hubClient.isCloudConfigured {
            return try await createOnCloud(
                title: title,
                description: description,
                type: type,
                priority: priority,
                sinistroRef: sinistroRef,
                dueDate: dueDate,
                assignedTo: assignedTo
            )
        } else if hubMode.shouldUseHub(for: .task) {
            return try await createOnHub(
                title: title,
                description: description,
                type: type,
                priority: priority,
                sinistroRef: sinistroRef,
                dueDate: dueDate,
                assignedTo: assignedTo
            )
        } else {
            return try await createLocally(
                title: title,
                description: description,
                type: type,
                priority: priority,
                sinistroRef: sinistroRef,
                dueDate: dueDate,
                assignedTo: assignedTo
            )
        }
    }
    
    /// Completa task
    func completeTask(id: String) async throws {
        if hubClient.isCloudConfigured {
            let _: TaskDTO = try await hubClient.cloudPost("/api/v1/tasks/\(id)/complete", body: EmptyBody())
        } else if hubMode.shouldUseHub(for: .task) {
            try await hubClient.completeTask(id: id)
        } else {
            // Logica locale esistente
            await TaskManager.shared.completeTaskForAdapter(id: id)
        }
    }
    
    /// Aggiorna task
    func updateTask(
        id: String,
        title: String?,
        description: String?,
        priority: Double?,
        dueDate: Date?,
        status: TaskStatus?
    ) async throws -> TaskListItem {
        if hubClient.isCloudConfigured {
            return try await updateOnCloud(
                id: id,
                title: title,
                description: description,
                priority: priority,
                dueDate: dueDate,
                status: status
            )
        } else if hubMode.shouldUseHub(for: .task) {
            return try await updateOnHub(
                id: id,
                title: title,
                description: description,
                priority: priority,
                dueDate: dueDate,
                status: status
            )
        } else {
            return try await updateLocally(
                id: id,
                title: title,
                description: description,
                priority: priority,
                dueDate: dueDate,
                status: status
            )
        }
    }
    
    // MARK: - Hub Implementation

    private func fetchFromCloud() async throws -> [TaskListItem] {
        let response: [TaskDTO] = try await hubClient.cloudGet("/api/v1/tasks")
        return response.map { TaskListItem(from: $0) }
    }

    private func fetchFromCloud(sinistroRef: String) async throws -> [TaskListItem] {
        let encoded = sinistroRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sinistroRef
        let response: [TaskDTO] = try await hubClient.cloudGet("/api/v1/tasks?sinistroRef=\(encoded)")
        return response.map { TaskListItem(from: $0) }
    }

    private func createOnCloud(
        title: String,
        description: String?,
        type: TaskType,
        priority: Double,
        sinistroRef: String?,
        dueDate: Date?,
        assignedTo: String?
    ) async throws -> TaskListItem {
        let request = CreateTaskRequest(
            title: title,
            description: description,
            type: type.rawValue,
            priority: priorityToString(priority),
            sinistroRef: sinistroRef,
            dueDate: dueDate,
            assignedTo: assignedTo,
            createdBy: CurrentUserService.shared.currentEmail ?? "unknown",
            clientId: nil
        )

        let response: TaskDTO = try await hubClient.cloudPost("/api/v1/tasks", body: request)
        return TaskListItem(from: response)
    }

    private func updateOnCloud(
        id: String,
        title: String?,
        description: String?,
        priority: Double?,
        dueDate: Date?,
        status: TaskStatus?
    ) async throws -> TaskListItem {
        let request = UpdateTaskRequest(
            title: title,
            description: description,
            priority: priority.map { priorityToString($0) },
            dueDate: dueDate,
            status: status?.rawValue
        )

        let response: TaskDTO = try await hubClient.cloudPut("/api/v1/tasks/\(id)", body: request)
        return TaskListItem(from: response)
    }

    private func fetchFromHub(userId: String, userEmail: String? = nil) async throws -> [TaskListItem] {
        var path = "/tasks?user=\(userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId)"
        if let email = userEmail, !email.isEmpty {
            path += "&email=\(email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email)"
        }
        let response: [TaskDTO] = try await hubClient.get(path)
        return response.map { TaskListItem(from: $0) }
    }
    
    private func fetchFromHub(sinistroRef: String) async throws -> [TaskListItem] {
        let response: [TaskDTO] = try await hubClient.get("/tasks/sinistro/\(sinistroRef)")
        return response.map { TaskListItem(from: $0) }
    }
    
    private func createOnHub(
        title: String,
        description: String?,
        type: TaskType,
        priority: Double,
        sinistroRef: String?,
        dueDate: Date?,
        assignedTo: String?
    ) async throws -> TaskListItem {
        let priorityString = priorityToString(priority)
        let request = CreateTaskRequest(
            title: title,
            description: description,
            type: type.rawValue,
            priority: priorityString,
            sinistroRef: sinistroRef,
            dueDate: dueDate,
            assignedTo: assignedTo,
            createdBy: assignedTo ?? "unknown",
            clientId: nil
        )
        
        let response: TaskDTO = try await hubClient.post("/tasks", body: request)
        return TaskListItem(from: response)
    }
    
    private func updateOnHub(
        id: String,
        title: String?,
        description: String?,
        priority: Double?,
        dueDate: Date?,
        status: TaskStatus?
    ) async throws -> TaskListItem {
        let request = UpdateTaskRequest(
            title: title,
            description: description,
            priority: priority.map { priorityToString($0) },
            dueDate: dueDate,
            status: status?.rawValue
        )
        
        let response: TaskDTO = try await hubClient.put("/tasks/\(id)", body: request)
        return TaskListItem(from: response)
    }
    
    // MARK: - Local Implementation
    
    private func fetchFromLocal(userId: String, userEmail: String? = nil) async throws -> [TaskListItem] {
        let tasks = await TaskManager.shared.getTasksForAdapter(userId: userId, userEmail: userEmail)
        return tasks.map { TaskListItem(from: $0) }
    }
    
    private func fetchFromLocal(sinistroRef: String) async throws -> [TaskListItem] {
        let tasks = await TaskManager.shared.getTasksForAdapter(sinistroRef: sinistroRef)
        return tasks.map { TaskListItem(from: $0) }
    }
    
    private func createLocally(
        title: String,
        description: String?,
        type: TaskType,
        priority: Double,
        sinistroRef: String?,
        dueDate: Date?,
        assignedTo: String?
    ) async throws -> TaskListItem {
        guard let task = await TaskManager.shared.createTaskForAdapter(
            title: title,
            description: description,
            type: type,
            sinistroRef: sinistroRef,
            dueDate: dueDate
        ) else {
            throw AdapterError.operationFailed("Impossibile creare il task")
        }
        return TaskListItem(from: task)
    }
    
    private func updateLocally(
        id: String,
        title: String?,
        description: String?,
        priority: Double?,
        dueDate: Date?,
        status: TaskStatus?
    ) async throws -> TaskListItem {
        guard let task = await TaskManager.shared.updateTaskForAdapter(
            id: id,
            title: title,
            description: description,
            dueDate: dueDate,
            status: status
        ) else {
            throw AdapterError.notFound("Task non trovato")
        }
        return TaskListItem(from: task)
    }
    
    // MARK: - Helpers
    
    /// Converte Double priority in stringa per Hub API
    private func priorityToString(_ value: Double) -> String {
        switch value {
        case 0..<0.3: return "low"
        case 0.3..<0.6: return "normal"
        case 0.6..<0.9: return "high"
        default: return "urgent"
        }
    }
}

// MARK: - Priority Conversion Helper

/// Helper per conversione priority string <-> Double
enum TaskPriorityHelper {
    static func fromString(_ value: String) -> Double {
        switch value.lowercased() {
        case "low": return 0.2
        case "normal", "medium": return 0.5
        case "high": return 0.8
        case "urgent": return 1.0
        default: return 0.5
        }
    }
    
    static func toString(_ value: Double) -> String {
        switch value {
        case 0..<0.3: return "low"
        case 0.3..<0.6: return "normal"
        case 0.6..<0.9: return "high"
        default: return "urgent"
        }
    }
}

// MARK: - View Models

struct TaskListItem: Identifiable {
    let id: String
    let title: String
    let description: String?
    let type: TaskType
    let priority: Double
    let status: TaskStatus
    let sinistroRef: String?
    let dueDate: Date?
    let assignedTo: String?
    let createdAt: Date
    
    init(from dto: TaskDTO) {
        self.id = dto.id
        self.title = dto.title
        self.description = dto.description
        self.type = TaskType(rawValue: dto.type) ?? .generic
        self.priority = TaskPriorityHelper.fromString(dto.priority)
        self.status = TaskStatus(rawValue: dto.status) ?? .pending
        self.sinistroRef = dto.sinistroRef
        self.dueDate = dto.dueDate
        self.assignedTo = dto.assignedTo
        self.createdAt = dto.createdAt
    }
    
    init(from task: HubTask) {
        self.id = task.id
        self.title = task.title
        self.description = task.description
        self.type = TaskType(rawValue: task.type) ?? .generic
        self.priority = task.priority
        self.status = TaskStatus(rawValue: task.status) ?? .pending
        self.sinistroRef = task.sinistroRef
        self.dueDate = task.dueDate
        self.assignedTo = task.assignedTo
        self.createdAt = task.createdAt
    }
    
    init(from task: DailyTask) {
        self.id = task.id.uuidString
        self.title = task.title
        self.description = task.description
        self.type = task.type
        self.priority = task.priority
        self.status = task.status
        self.sinistroRef = task.sinistroID
        self.dueDate = task.deadline
        self.assignedTo = nil
        self.createdAt = task.createdAt
    }
}
