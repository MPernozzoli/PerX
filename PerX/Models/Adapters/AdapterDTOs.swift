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
