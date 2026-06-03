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

// MARK: - Emails

struct EmailDTO: Decodable, Identifiable, Hashable {
    let id: String
    let from_address: String
    let to_addresses: String?
    let subject: String?
    let body_text: String?
    let received_at: Date
    let status: String
}

struct EmailListDTO: Decodable {
    let items: [EmailDTO]
    let total: Int
}

// MARK: - Internal chat

struct ChatThreadDTO: Decodable, Identifiable, Hashable {
    let id: String
    let claim_id: String?
    let title: String
    let thread_type: String
    let created_at: Date
}

struct ChatThreadListDTO: Decodable {
    let items: [ChatThreadDTO]
    let total: Int
}

struct ChatMessageDTO: Decodable, Identifiable, Hashable {
    let id: String
    let thread_id: String
    let sender_user_id: String?
    let body_text: String?
    let message_type: String
    let created_at: Date
}

struct ChatMessageListDTO: Decodable {
    let items: [ChatMessageDTO]
    let total: Int
}

struct ChatMessageCreateDTO: Encodable {
    let body_text: String
    let message_type: String
}

// MARK: - Outbound call

struct CommunicationStartRequestDTO: Encodable {
    struct Destination: Encodable {
        let destination_type: String  // "internal_user" | "external_phone"
        let transport: String         // "livekit" | "telecom_provider"
        let target_id: String?
        let raw_value: String
        let display_name: String?
    }
    struct Context: Encodable {
        let claim_id: String?
    }
    let destination: Destination
    let context: Context
}

struct CommunicationStartResponseDTO: Decodable {
    let session_id: String
    let call_id: String
    let state: String
}

struct LiveKitTokenDTO: Decodable {
    let token: String
    let livekit_url: String
    let room_name: String
    let identity: String
    let session_id: String
    let call_id: String?
    let display_name: String?
}

struct CallSessionAction: Encodable {
    let action_type: String  // "answer" | "answer_and_open_claim" | "end" | "send_to_voicemail_ai_triage" | "open_claim_only"
}

struct CallHistoryDTO: Decodable, Identifiable, Hashable {
    let id: String
    let display_name: String?
    let state: String
    let destination_type: String
    let transport: String
    let direction: String?
    let from_value: String?
    let to_value: String?
    let claim_id: String?
    let created_at: Date
    let ended_at: Date?
}

struct CallHistoryListDTO: Decodable {
    let items: [CallHistoryDTO]
    let total: Int
}

// MARK: - Profilo utente corrente

struct MeProfileDTO: Decodable, Hashable {
    let id: String
    let email: String
    let first_name: String?
    let last_name: String?
    let extension_number: String?
    let extension_enabled: Bool?
    let extension_display_name: String?
}
