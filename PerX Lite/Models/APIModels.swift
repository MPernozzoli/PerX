import Foundation

// MARK: - Tasks

struct TaskDTO: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let type: String
    let priority: String
    let status: String
    let sinistroRef: String?
    let dueDate: Date?
    let assignedTo: String?
    let createdBy: String?
    let createdAt: Date
    let completedAt: Date?
}

// MARK: - Calendar / Planning

struct CalendarEventDTO: Decodable, Identifiable, Hashable {
    let id: String
    let tenant_id: String
    let claim_id: String?
    let task_id: String?
    let owner_user_id: String
    let title: String
    let description: String?
    let event_type: String
    let starts_at: Date
    let ends_at: Date
    let all_day: Bool
    let location: String?
    let status: String
    let visibility: String
    let source: String
}

struct CalendarEventListDTO: Decodable {
    let items: [CalendarEventDTO]
    let total: Int
}

struct WorkScheduleDTO: Decodable, Identifiable, Hashable {
    let id: String
    let tenant_id: String
    let user_id: String
    let weekday: Int          // 0=Mon ... 6=Sun (backend convention)
    let start_time: String    // "HH:mm:ss"
    let end_time: String
    let location: String?
    let slot_type: String
    let effective_from: String?
    let effective_to: String?
    let created_at: Date
}

struct WorkScheduleListDTO: Decodable {
    let items: [WorkScheduleDTO]
    let total: Int
}

struct WorkScheduleCreateDTO: Encodable {
    let weekday: Int
    let start_time: String
    let end_time: String
    let location: String?
    let slot_type: String
    let effective_from: String?
    let effective_to: String?
}

// MARK: - Communications

struct IncomingCallDTO: Decodable, Identifiable, Hashable {
    var id: String { session_id }
    let session_id: String
    let call_id: String?
    let display_name: String?
    let state: String
    let destination_type: String
    let transport: String
    let livekit_room_name: String?
    let claim_id: String?
    let created_at: Date
}

struct IncomingCallListDTO: Decodable {
    let items: [IncomingCallDTO]
}
