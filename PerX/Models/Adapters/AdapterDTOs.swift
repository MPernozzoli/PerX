import Foundation

// ============================================================================
// MARK: - Adapter DTOs
// DTOs per le API client-hub (definiti localmente per evitare dipendenze SPM)
// ============================================================================

// MARK: - Type Aliases

/// Alias per StatoSinistro definito in StatoManager
typealias StatoSinistro = StatoManager.StatoSinistro

// MARK: - Email DTOs

struct EmailDTO: Codable, Identifiable {
    let id: String
    let subject: String
    let senderEmail: String
    let senderName: String?
    let date: Date
    let category: String
    let sinistroRef: String?
    let direction: String?
    let mailbox: String?
    let isRead: Bool?
}

struct MailboxDTO: Codable, Identifiable {
    let id: String
    let name: String
    let unreadCount: Int
    let totalCount: Int
}

struct EmailDetailDTO: Codable, Identifiable {
    let id: String
    let subject: String
    let senderEmail: String
    let senderName: String?
    let recipients: [String]
    let date: Date
    let bodyText: String?
    let bodyHtml: String?
    let category: String
    let sinistroRef: String?
    let direction: String?
}

struct ScheduledEmailDTO: Codable, Identifiable {
    let id: String
    let accountId: String
    let to: [String]
    let subject: String
    let scheduledFor: Date
    let status: String
}

// MARK: - Sinistro DTOs

struct SinistroDTO: Codable, Identifiable {
    let id: String
    let riferimento: String
    let numeroSinistro: String?
    let numeroSinistroCompagnia: String?
    let garanzia: String?
    let stato: String
    let substate: String?
    let assegnatario: String?
    let assignedToUserEmail: String?
    let compagnia: String?
    let nomeCompagnia: String?
    let agenzia: String?
    let nomeAssicurato: String?
    let dataSinistro: Date?
    let dataAssegnazione: Date?
    let dataChiusura: Date?
    let richiesta: Double?
    let liquidato: Double?
    let dannoAccertato: Double?
    let tipoDanno: String?
    let localita: String?
    let provincia: String?
}

// MARK: - State Change

struct StateChangeRequest: Codable {
    let newState: String
    let reason: String?
    let changedBy: String
}

struct StateChangeResponse: Codable {
    let success: Bool
    let newState: String
    let message: String?
}

// MARK: - Task DTOs

struct CreateTaskRequest: Codable {
    let title: String
    let description: String?
    let type: String
    let priority: String
    let sinistroRef: String?
    let dueDate: Date?
    let assignedTo: String?
    let createdBy: String
}

struct UpdateTaskRequest: Codable {
    let title: String?
    let description: String?
    let priority: String?
    let dueDate: Date?
    let status: String?
}

struct TaskDTO: Codable, Identifiable {
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

// MARK: - Cloud API DTOs

struct CloudAPILoginRequest: Codable {
    let username: String
    let password: String
}

struct CloudAPITokenResponse: Codable {
    let access_token: String
    let refresh_token: String
    let token_type: String
}

struct CloudAPIUserResponse: Codable {
    let id: String
    let email: String
    let full_name: String
    let is_active: Bool
    let tenant_id: String
    let is_platform_admin: Bool
}

struct CloudClaimListResponse: Codable {
    let items: [CloudClaimResponse]
    let total: Int
    let page: Int
    let page_size: Int
}

struct CloudClaimResponse: Codable {
    let id: String
    let external_ref: String?
    let numero_sinistro: String?
    let compagnia: String?
    let stato_corrente: String
    let garanzia: String?
    let agenzia: String?
    let nome_assicurato: String?
    let data_sinistro: Date?
    let numero_polizza: String?
    let tipo_polizza: String?
    let richiesta: Double?
    let liquidato: Double?
    let closed_at: Date?
    let created_at: Date
    let updated_at: Date
    let version: Int
}

// MARK: - Cloud Content DTOs

struct CloudDiaryEntryListResponse: Codable {
    let items: [CloudDiaryEntryResponse]
    let total: Int
}

struct CloudDiaryEntryResponse: Codable, Identifiable {
    let id: String
    let tenant_id: String
    let claim_id: String
    let entry_type: String
    let title: String?
    let body_text: String?
    let visibility: String
    let happened_at: Date
    let created_at: Date
    let created_by_user_id: String?
    let metadata_json: [String: String]?
}

struct CloudDiaryEntryCreateRequest: Codable {
    let entry_type: String
    let title: String?
    let body_text: String?
    let visibility: String
    let happened_at: Date?
    let metadata_json: [String: String]?
}

struct CloudEmailListResponse: Codable {
    let items: [CloudEmailResponse]
    let total: Int
}

struct CloudEmailResponse: Codable, Identifiable {
    let id: String
    let tenant_id: String
    let message_id: String
    let thread_id: String?
    let from_address: String
    let to_addresses: String?
    let cc_addresses: String?
    let subject: String?
    let body_text: String?
    let body_html: String?
    let received_at: Date
    let ingested_at: Date
    let status: String
    let raw_headers: String?
    let mailbox_id: String?
    let provider_id: String?
}

struct CloudFolderListResponse: Codable {
    let items: [CloudFolderResponse]
    let total: Int
}

struct CloudFolderResponse: Codable, Identifiable {
    let id: String
    let tenant_id: String
    let claim_id: String?
    let parent_id: String?
    let name: String
    let folder_type: String
    let path: String
    let source: String
    let external_ref: String?
    let created_at: Date
    let updated_at: Date
}

struct CloudFolderCreateRequest: Codable {
    let name: String
    let parent_id: String?
    let folder_type: String
    let path: String?
    let source: String
    let external_ref: String?
}

struct CloudDocumentListResponse: Codable {
    let items: [CloudDocumentResponse]
    let total: Int
}

struct CloudDocumentResponse: Codable, Identifiable {
    let id: String
    let tenant_id: String
    let claim_id: String?
    let folder_id: String?
    let attachment_id: String?
    let source_type: String
    let source_id: String?
    let file_name: String
    let original_file_name: String?
    let mime_type: String?
    let extension: String?
    let size_bytes: Int
    let storage_provider: String
    let storage_bucket: String?
    let storage_path: String
    let logical_path: String?
    let checksum_sha256: String?
    let checksum_md5: String?
    let version_no: Int
    let status: String
    let category: String?
    let tags_json: [String]?
    let uploaded_at: Date
    let uploaded_by_user_id: String?
}

struct CloudDocumentCreateRequest: Codable {
    let claim_id: String?
    let folder_id: String?
    let attachment_id: String?
    let source_type: String
    let source_id: String?
    let file_name: String
    let original_file_name: String?
    let mime_type: String?
    let `extension`: String?
    let size_bytes: Int
    let storage_provider: String
    let storage_bucket: String?
    let storage_path: String
    let logical_path: String?
    let checksum_sha256: String?
    let checksum_md5: String?
    let version_no: Int
    let status: String
    let category: String?
    let tags_json: [String]
}

struct CloudInternalChatThreadListResponse: Codable {
    let items: [CloudInternalChatThreadResponse]
    let total: Int
}

struct CloudInternalChatThreadResponse: Codable, Identifiable {
    let id: String
    let tenant_id: String
    let claim_id: String?
    let title: String
    let thread_type: String
    let created_at: Date
    let created_by_user_id: String?
}

struct CloudInternalChatThreadCreateRequest: Codable {
    let claim_id: String?
    let title: String
    let thread_type: String
    let member_user_ids: [String]
}

struct CloudInternalChatMessageListResponse: Codable {
    let items: [CloudInternalChatMessageResponse]
    let total: Int
}

struct CloudInternalChatMessageResponse: Codable, Identifiable {
    let id: String
    let tenant_id: String
    let thread_id: String
    let claim_id: String?
    let sender_user_id: String?
    let body_text: String?
    let message_type: String
    let attachment_document_id: String?
    let created_at: Date
}

struct CloudInternalChatMessageCreateRequest: Codable {
    let body_text: String?
    let message_type: String
    let attachment_document_id: String?
}

struct CloudAIChatSessionListResponse: Codable {
    let items: [CloudAIChatSessionResponse]
    let total: Int
}

struct CloudAIChatSessionResponse: Codable, Identifiable {
    let id: String
    let tenant_id: String
    let claim_id: String?
    let user_id: String
    let title: String
    let model: String?
    let status: String
    let created_at: Date
    let updated_at: Date
}

struct CloudAIChatSessionCreateRequest: Codable {
    let claim_id: String?
    let title: String
    let model: String?
}

struct CloudAIChatMessageListResponse: Codable {
    let items: [CloudAIChatMessageResponse]
    let total: Int
}

struct CloudAIChatMessageResponse: Codable, Identifiable {
    let id: String
    let tenant_id: String
    let session_id: String
    let role: String
    let body_text: String?
    let created_at: Date
}

struct CloudAIChatMessageCreateRequest: Codable {
    let role: String
    let body_text: String?
}

struct CloudCalendarEventListResponse: Codable {
    let items: [CloudCalendarEventResponse]
    let total: Int
}

struct CloudCalendarEventResponse: Codable, Identifiable {
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

struct CloudCalendarEventCreateRequest: Codable {
    let claim_id: String?
    let task_id: String?
    let owner_user_id: String?
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

struct CloudDashboardWidgetListResponse: Codable {
    let items: [CloudDashboardWidgetResponse]
    let total: Int
}

struct CloudDashboardWidgetResponse: Codable, Identifiable {
    let id: String
    let tenant_id: String
    let user_id: String
    let widget_key: String
    let position: Int
    let enabled: Bool
    let settings_json: [String: String]?
}

struct CloudDashboardWidgetUpsertRequest: Codable {
    let widget_key: String
    let position: Int
    let enabled: Bool
    let settings_json: [String: String]?
}

// MARK: - HubTask (per compatibilità)

struct HubTask: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let type: String          // Stringa per evitare dipendenze
    let priority: Double      // Usa Double come DailyTask
    let status: String        // Stringa per evitare dipendenze
    let sinistroRef: String?
    let dueDate: Date?
    let assignedTo: String?
    let createdBy: String?
    let createdAt: Date
    let completedAt: Date?
    
    /// Converte in TaskType
    var taskType: TaskType? {
        return TaskType(rawValue: type)
    }
    
    /// Converte in TaskStatus
    var taskStatus: TaskStatus? {
        return TaskStatus(rawValue: status)
    }
}

// MARK: - AdapterTaskPriority Helper (per adapter Hub)
// Nota: Usato solo per comunicazione con Hub, non confondere con Swift TaskPriority

enum AdapterTaskPriority: String, Codable {
    case low
    case normal
    case medium
    case high
    case urgent
    
    var asDouble: Double {
        switch self {
        case .low: return 0.2
        case .normal, .medium: return 0.5
        case .high: return 0.8
        case .urgent: return 1.0
        }
    }
    
    init(from double: Double) {
        switch double {
        case 0..<0.3: self = .low
        case 0.3..<0.6: self = .normal
        case 0.6..<0.9: self = .high
        default: self = .urgent
        }
    }
}
