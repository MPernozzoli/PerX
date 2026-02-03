import Foundation

/// Tipo di task
enum TaskType: String, Codable {
    case sinistroActivity = "sinistro_activity"
    case reminder = "reminder"
    case meeting = "meeting"
    case manual = "manual"
    case aiGenerated = "ai_generated"
    case generic = "generic"
}

/// Stato di una task
enum TaskStatus: String, Codable {
    case pending = "pending"
    case inProgress = "in_progress"
    case completed = "completed"
    case cancelled = "cancelled"
    case expired = "expired"
}

/// Tipo di sollecito per priorità dinamiche
enum ReminderType: String, Codable {
    case cliente = "cliente"
    case agenzia = "agenzia"
    case liquidatore = "liquidatore"
}

/// Vincoli temporali per task con orari multipli
struct TimeConstraints: Codable {
    /// Giorni della settimana (1 = domenica, 2 = lunedì, ..., 7 = sabato)
    var allowedWeekdays: Set<Int>?
    
    /// Periodi del giorno consentiti
    enum TimePeriod: String, Codable {
        case morning = "morning"      // Mattino (es. 09:00-12:00)
        case afternoon = "afternoon"  // Pomeriggio (es. 14:00-18:00)
        case specific = "specific"    // Orari specifici
    }
    
    var allowedPeriods: [TimePeriod]?
    
    /// Orari specifici (se TimePeriod.specific)
    struct SpecificTime: Codable {
        var hour: Int
        var minute: Int
    }
    var specificTimes: [SpecificTime]?
    
    /// Orario limite (es. "entro le 10:00")
    var deadlineTime: SpecificTime?
    
    /// Pattern complesso: "tutti i giorni entro le X" o "lunedì e mercoledì al mattino"
    var pattern: String? // Pattern testuale per riferimento
    
    init(
        allowedWeekdays: Set<Int>? = nil,
        allowedPeriods: [TimePeriod]? = nil,
        specificTimes: [SpecificTime]? = nil,
        deadlineTime: SpecificTime? = nil,
        pattern: String? = nil
    ) {
        self.allowedWeekdays = allowedWeekdays
        self.allowedPeriods = allowedPeriods
        self.specificTimes = specificTimes
        self.deadlineTime = deadlineTime
        self.pattern = pattern
    }
}

/// Task giornaliera per la dashboard
struct DailyTask: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String
    var type: TaskType
    var sinistroID: String?
    var priority: Double // Priorità calcolata dinamicamente
    var deadline: Date? // Scadenza opzionale
    var status: TaskStatus
    var createdAt: Date
    var scheduledDate: Date? // Data programmata
    var scheduledTime: Date? // Orario programmato (se specifico)
    var startedAt: Date? // Tempo di inizio task (per calcolo durata effettiva)
    var completedAt: Date?
    var isExpired: Bool
    var isIgnored: Bool
    var estimatedDuration: TimeInterval // Durata stimata in secondi
    var actualDuration: TimeInterval? // Durata effettiva (registrata al completamento)
    var metadata: [String: AnyCodable] // Metadata per tracking (originalEmailId, etc.)
    var sourceDiarioEntryId: UUID? // ID dell'entry del diario che ha generato questo task
    var draftMessage: String? // Bozza messaggio per task di follow-up
    
    // Campi per azioni di comunicazione
    var phoneNumber: String? // Numero di telefono per chiamate
    var email: String? // Indirizzo email per scrivere mail
    var replyToEmailId: String? // ID email a cui rispondere (messageId Gmail)
    
    // Time-sensitive properties
    var isTimeSensitive: Bool // Se true, è un evento con data/ora fissa o scadenza critica
    var fixedDateTime: Date? // Data/ora fissa per eventi come videoperizie, riunioni
    var timeConstraints: TimeConstraints? // Vincoli temporali per orari multipli
    
    // Nuovi campi per sistema goal e invalidazione
    var actionType: TaskActionType?           // Tipo azione standardizzata
    var goal: TaskGoal?                       // Obiettivo task per auto-completamento
    var invalidationRules: TaskInvalidation?  // Condizioni di invalidazione automatica
    var completionEventId: String?            // ID evento che ha completato la task
    var priorityLevel: TaskPriorityLevel      // Livello priorità (essenziale/opzionale)
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        type: TaskType,
        sinistroID: String? = nil,
        priority: Double = 0.0,
        deadline: Date? = nil,
        status: TaskStatus = .pending,
        createdAt: Date = Date(),
        scheduledDate: Date? = nil,
        scheduledTime: Date? = nil,
        estimatedDuration: TimeInterval = 1800, // Default 30 minuti
        metadata: [String: AnyCodable] = [:],
        sourceDiarioEntryId: UUID? = nil,
        draftMessage: String? = nil,
        phoneNumber: String? = nil,
        email: String? = nil,
        replyToEmailId: String? = nil,
        isTimeSensitive: Bool = false,
        fixedDateTime: Date? = nil,
        timeConstraints: TimeConstraints? = nil,
        actionType: TaskActionType? = nil,
        goal: TaskGoal? = nil,
        invalidationRules: TaskInvalidation? = nil,
        completionEventId: String? = nil,
        priorityLevel: TaskPriorityLevel = .essential
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.type = type
        self.sinistroID = sinistroID
        self.priority = priority
        self.deadline = deadline
        self.status = status
        self.createdAt = createdAt
        self.scheduledDate = scheduledDate
        self.scheduledTime = scheduledTime
        self.startedAt = nil
        self.isExpired = false
        self.isIgnored = false
        self.estimatedDuration = estimatedDuration
        self.actualDuration = nil
        self.metadata = metadata
        self.sourceDiarioEntryId = sourceDiarioEntryId
        self.draftMessage = draftMessage
        self.phoneNumber = phoneNumber
        self.email = email
        self.replyToEmailId = replyToEmailId
        self.isTimeSensitive = isTimeSensitive
        self.fixedDateTime = fixedDateTime
        self.timeConstraints = timeConstraints
        self.actionType = actionType
        self.goal = goal
        self.invalidationRules = invalidationRules
        self.completionEventId = completionEventId
        self.priorityLevel = priorityLevel
    }
    
    /// Crea copia mutabile della task per aggiornamenti
    func with(
        title: String? = nil,
        description: String? = nil,
        priority: Double? = nil,
        status: TaskStatus? = nil,
        scheduledDate: Date? = nil,
        scheduledTime: Date? = nil,
        completedAt: Date? = nil,
        completionEventId: String? = nil,
        goal: TaskGoal? = nil
    ) -> DailyTask {
        return DailyTask(
            id: self.id,
            title: title ?? self.title,
            description: description ?? self.description,
            type: self.type,
            sinistroID: self.sinistroID,
            priority: priority ?? self.priority,
            deadline: self.deadline,
            status: status ?? self.status,
            createdAt: self.createdAt,
            scheduledDate: scheduledDate ?? self.scheduledDate,
            scheduledTime: scheduledTime ?? self.scheduledTime,
            estimatedDuration: self.estimatedDuration,
            metadata: self.metadata,
            sourceDiarioEntryId: self.sourceDiarioEntryId,
            draftMessage: self.draftMessage,
            phoneNumber: self.phoneNumber,
            email: self.email,
            replyToEmailId: self.replyToEmailId,
            isTimeSensitive: self.isTimeSensitive,
            fixedDateTime: self.fixedDateTime,
            timeConstraints: self.timeConstraints,
            actionType: self.actionType,
            goal: goal ?? self.goal,
            invalidationRules: self.invalidationRules,
            completionEventId: completionEventId ?? self.completionEventId,
            priorityLevel: self.priorityLevel
        )
    }
    
    /// Verifica se la task è scaduta
    var hasExpired: Bool {
        guard let deadline = deadline else { return false }
        return deadline < Date() && status != .completed
    }
    
    /// Verifica se la task ha una scadenza imminente (< 1 ora)
    var isDeadlineImminent: Bool {
        guard let deadline = deadline else { return false }
        let timeUntilDeadline = deadline.timeIntervalSinceNow
        return timeUntilDeadline > 0 && timeUntilDeadline < 3600 // Meno di 1 ora
    }
    
    /// Verifica se la task ha una data/ora fissa
    var hasFixedDateTime: Bool {
        return fixedDateTime != nil
    }
    
    /// Verifica se la task è scaduta e non può essere completata in tempo
    var isOverdue: Bool {
        guard isTimeSensitive else { return hasExpired }
        
        // Se ha data/ora fissa e è passata
        if let fixed = fixedDateTime, fixed < Date() {
            return status != .completed
        }
        
        // Se ha scadenza e non può essere completata
        if let deadline = deadline, deadline < Date() {
            return status != .completed
        }
        
        return false
    }
    
    /// Titolo con prefisso "SCADUTO" se necessario
    var displayTitle: String {
        if isOverdue && !title.hasPrefix("SCADUTO") {
            let riferimento = sinistroID.map { " \($0)" } ?? ""
            return "SCADUTO - \(title)\(riferimento)"
        }
        return title
    }
    
    /// Verifica se la task è manuale (creata dall'utente)
    var isManual: Bool {
        return type == .manual
    }
    
    /// Verifica se la task è bloccante per il sinistro
    var isBlocking: Bool {
        return metadata["isBlocking"]?.value as? Bool ?? false
    }
}

/// Task programmata con orario specifico
struct ScheduledTask: Identifiable {
    let task: DailyTask
    let scheduledStartTime: Date
    let scheduledEndTime: Date
    
    var id: UUID { task.id }
}

