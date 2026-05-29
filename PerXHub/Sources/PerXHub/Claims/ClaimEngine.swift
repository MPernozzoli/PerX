import Foundation
import PerXCore
import SQLite

// ============================================================================
// MARK: - ClaimEngine (Hub version)
// Motore decisionale centralizzato per la gestione degli eventi sinistri
// Processa eventi email/WA e determina le azioni da eseguire
// ============================================================================

public actor ClaimEngine {
    public static let shared = ClaimEngine()
    
    private let db = DatabaseManager.shared
    private var processedEventIds = Set<String>()
    
    private init() {
        print("[ClaimEngine] ✅ Inizializzato sull'Hub")
    }
    
    // MARK: - Event Processing
    
    /// Processa un evento email
    public func processEvent(_ event: HubEmailEvent) async throws -> ClaimEngineResult {
        let eventKey = "\(event.eventType.rawValue)-\(event.emailId)"
        
        // Verifica se già processato
        if processedEventIds.contains(eventKey) {
            print("[ClaimEngine] ⏭️ Evento già processato: \(eventKey)")
            return ClaimEngineResult(
                eventId: event.eventId.uuidString,
                success: false,
                action: .none,
                message: "Evento già processato"
            )
        }
        
        print("[ClaimEngine] 🔄 Processando evento: \(event.eventType.rawValue)")
        
        // Determina l'azione da compiere
        let decision = await determineDecision(for: event)
        
        // Esegui l'azione
        let result = try await executeDecision(decision, for: event)
        
        // Marca come processato
        processedEventIds.insert(eventKey)
        
        // Limita cache a 1000 eventi
        if processedEventIds.count > 1000 {
            let excess = processedEventIds.count - 1000
            for _ in 0..<excess {
                if let first = processedEventIds.first {
                    processedEventIds.remove(first)
                }
            }
        }
        
        return result
    }
    
    // MARK: - Decision Logic
    
    private func determineDecision(for event: HubEmailEvent) async -> ClaimEngineDecision {
        // Ottieni stato corrente del sinistro se presente
        let currentState = await getCurrentState(for: event.sinistroId)
        
        switch event.eventType {
        case .assignmentReceived:
            return await handleAssignmentDecision(event)
            
        case .revocationReceived:
            return ClaimEngineDecision(
                action: .changeState,
                targetState: .revocata,
                reason: event.reason ?? "Revoca ricevuta"
            )
            
        case .signedActReceived:
            return ClaimEngineDecision(
                action: .changeState,
                targetState: .attoRicevutoSottoscritto,
                createTask: true,
                taskTitle: "Verificare atto firmato",
                taskPriority: .urgent,
                reason: "Atto firmato ricevuto"
            )
            
        case .actToSignSent:
            return ClaimEngineDecision(
                action: .changeState,
                targetState: .attoInviato,
                reason: "Atto da firmare inviato"
            )
            
        case .reminderReceived:
            return ClaimEngineDecision(
                action: .createTask,
                createTask: true,
                taskTitle: "Rispondere a sollecito",
                taskPriority: .high,
                reason: "Sollecito ricevuto"
            )
            
        case .reminderSent:
            return ClaimEngineDecision(
                action: .logOnly,
                reason: "Sollecito inviato"
            )
            
        case .documentationReceived:
            // Se in attesa documentale, avanza a perizia da eseguire
            if currentState == .inAttesaDocumentale {
                return ClaimEngineDecision(
                    action: .changeState,
                    targetState: .periziaDaEseguireDocumentale,
                    createTask: true,
                    taskTitle: "Verificare documentazione",
                    taskPriority: .normal,
                    reason: "Documentazione ricevuta"
                )
            }
            return ClaimEngineDecision(
                action: .createTask,
                createTask: true,
                taskTitle: "Verificare documentazione",
                taskPriority: .normal,
                reason: "Documentazione ricevuta"
            )
            
        case .documentationRequested:
            return ClaimEngineDecision(
                action: .logOnly,
                reason: "Richiesta documentazione"
            )
            
        case .surveyScheduled:
            return ClaimEngineDecision(
                action: .changeState,
                targetState: .sopralluogoFissato,
                createTask: true,
                taskTitle: "Sopralluogo",
                taskPriority: .high,
                taskDueDate: event.scheduledDate,
                reason: "Sopralluogo fissato"
            )
            
        case .surveyReturned:
            return ClaimEngineDecision(
                action: .changeState,
                targetState: .sopralluogoRestituito,
                reason: "Sopralluogo restituito"
            )
            
        case .videocallScheduled:
            return ClaimEngineDecision(
                action: .changeState,
                targetState: .videoperiziaFissata,
                createTask: true,
                taskTitle: "Videoperizia",
                taskPriority: .high,
                taskDueDate: event.scheduledDate,
                reason: "Videoperizia fissata"
            )
            
        case .clarificationRequested:
            return ClaimEngineDecision(
                action: .createTask,
                createTask: true,
                taskTitle: "Rispondere a richiesta chiarimenti",
                taskPriority: .high,
                reason: "Richiesta chiarimenti ricevuta"
            )
            
        case .controlled:
            return ClaimEngineDecision(
                action: .changeState,
                targetState: .controllata,
                reason: "Perizia controllata"
            )
            
        case .revisionRequested:
            return ClaimEngineDecision(
                action: .changeState,
                targetState: .richiestaRevisione,
                createTask: true,
                taskTitle: "Revisionare perizia",
                taskPriority: .urgent,
                reason: "Richiesta revisione"
            )
            
        case .outcomeSent:
            return ClaimEngineDecision(
                action: .changeState,
                targetState: .esitoComunicato,
                reason: "Esito comunicato"
            )
            
        case .verbalAcceptance:
            return ClaimEngineDecision(
                action: .changeState,
                targetState: .accettataVerbalmente,
                reason: "Accettazione verbale ricevuta"
            )
            
        case .genericCommunication:
            return ClaimEngineDecision(
                action: .logOnly,
                reason: "Comunicazione generica"
            )
        }
    }
    
    private func handleAssignmentDecision(_ event: HubEmailEvent) async -> ClaimEngineDecision {
        guard let riferimento = event.riferimento else {
            return ClaimEngineDecision(
                action: .none,
                reason: "Riferimento mancante nell'evento di assegnazione"
            )
        }
        
        // Verifica se esiste già il sinistro
        let existingSinistro = await getSinistro(riferimento: riferimento)
        
        if existingSinistro == nil {
            // Nuovo sinistro: crea
            return ClaimEngineDecision(
                action: .createSinistro,
                targetState: .daScaricare,
                createTask: true,
                taskTitle: "Scaricare cartella",
                taskPriority: .high,
                reason: "Nuova assegnazione",
                metadata: [
                    "riferimento": riferimento,
                    "assigneeEmail": event.assigneeEmail ?? "",
                    "assigneeName": event.assigneeName ?? "",
                    "assignmentDate": event.assignmentDate?.iso8601String ?? ""
                ]
            )
        } else if let stato = existingSinistro?.stato, stato == StatoSinistro.revocata.descrizione {
            // Reincarico
            return ClaimEngineDecision(
                action: .changeState,
                targetState: .daScaricare,
                createTask: true,
                taskTitle: "Scaricare cartella (reincarico)",
                taskPriority: .high,
                reason: "Reincarico (era revocato)"
            )
        } else {
            // Già esistente: log solo
            return ClaimEngineDecision(
                action: .logOnly,
                reason: "Sinistro già assegnato"
            )
        }
    }
    
    // MARK: - Decision Execution
    
    private func executeDecision(_ decision: ClaimEngineDecision, for event: HubEmailEvent) async throws -> ClaimEngineResult {
        var result = ClaimEngineResult(
            eventId: event.eventId.uuidString,
            success: true,
            action: decision.action,
            message: decision.reason
        )
        
        switch decision.action {
        case .none:
            result.success = false
            
        case .logOnly:
            // Solo log
            print("[ClaimEngine] 📔 Log: \(decision.reason)")
            
        case .createSinistro:
            // Crea nuovo sinistro
            if let riferimento = decision.metadata?["riferimento"] as? String {
                try await createSinistro(
                    riferimento: riferimento,
                    assigneeEmail: decision.metadata?["assigneeEmail"] as? String,
                    assigneeName: decision.metadata?["assigneeName"] as? String,
                    assignmentDate: Date() // TODO: parse from metadata
                )
                result.details["sinistroCreated"] = riferimento
            }
            
        case .changeState:
            // Cambia stato
            if let sinistroId = event.sinistroId,
               let targetState = decision.targetState {
                try await changeState(
                    sinistroRef: sinistroId,
                    to: targetState,
                    reason: decision.reason
                )
                result.details["newState"] = targetState.descrizione
            }
            
        case .createTask:
            // Crea solo task
            break
            
        case .notify:
            // Invia notifica
            break
        }
        
        // Crea task se richiesto
        if decision.createTask, let taskTitle = decision.taskTitle {
            let task = try await createTask(
                title: taskTitle,
                sinistroRef: event.sinistroId,
                priority: decision.taskPriority ?? .normal,
                dueDate: decision.taskDueDate
            )
            result.details["taskCreated"] = task.id
        }
        
        return result
    }
    
    // MARK: - Database Operations
    
    private func getCurrentState(for sinistroRef: String?) async -> StatoSinistro? {
        guard let ref = sinistroRef else { return nil }
        
        let sinistro = await getSinistro(riferimento: ref)
        guard let statoDesc = sinistro?.stato else { return nil }
        return StatoSinistro.fromDescrizione(statoDesc)
    }
    
    private func getSinistro(riferimento: String) async -> SinistroRecord? {
        do {
            let conn = try await db.db()
            let query = DatabaseSchema.sinistri.filter(
                DatabaseSchema.SinistriColumns.riferimento == riferimento
            )
            
            guard let row = try conn.pluck(query) else { return nil }
            
            return SinistroRecord(
                riferimento: row[DatabaseSchema.SinistriColumns.riferimento],
                stato: row[DatabaseSchema.SinistriColumns.stato],
                ownerEmail: row[DatabaseSchema.SinistriColumns.assegnatario],
                dataAssegnazione: row[DatabaseSchema.SinistriColumns.dataAssegnazione].map { Date(timeIntervalSince1970: $0) }
            )
        } catch {
            print("[ClaimEngine] ❌ Errore query sinistro: \(error)")
            return nil
        }
    }
    
    private func createSinistro(
        riferimento: String,
        assigneeEmail: String?,
        assigneeName: String?,
        assignmentDate: Date
    ) async throws {
        let conn = try await db.db()
        let now = Date()
        
        // Inserisci in database
        try conn.run(DatabaseSchema.sinistri.insert(or: .replace,
            DatabaseSchema.SinistriColumns.riferimento <- riferimento,
            DatabaseSchema.SinistriColumns.stato <- StatoSinistro.daScaricare.descrizione,
            DatabaseSchema.SinistriColumns.assegnatario <- assigneeEmail,
            DatabaseSchema.SinistriColumns.dataAssegnazione <- assignmentDate.timeIntervalSince1970,
            DatabaseSchema.SinistriColumns.folderStatus <- "pending",
            DatabaseSchema.SinistriColumns.lastModifiedAt <- now.timeIntervalSince1970,
            DatabaseSchema.SinistriColumns.createdAt <- now.timeIntervalSince1970,
            DatabaseSchema.SinistriColumns.syncedToCK <- false
        ))
        
        // Crea struttura cartella nel Vault
        try await VaultManager.shared.createSinistroFolder(sinistroRef: riferimento)
        
        // Calcola legacy path
        let legacyPath = calculateLegacyPath(for: riferimento, assigneeEmail: assigneeEmail)
        
        // Aggiorna con legacy path
        try conn.run(
            DatabaseSchema.sinistri
                .filter(DatabaseSchema.SinistriColumns.riferimento == riferimento)
                .update(DatabaseSchema.SinistriColumns.legacyPath <- legacyPath)
        )
        
        // Crea job per import cartella
        _ = try await JobService.shared.createImportFolderJob(
            sinistroRef: riferimento,
            legacyPath: legacyPath,
            priority: 10
        )
        
        try await syncSinistroToBackend(riferimento: riferimento)
        
        print("[ClaimEngine] ✨ Creato sinistro: \(riferimento)")
    }
    
    private func changeState(
        sinistroRef: String,
        to newState: StatoSinistro,
        reason: String
    ) async throws {
        let conn = try await db.db()
        let now = Date()
        
        // Aggiorna stato
        try conn.run(
            DatabaseSchema.sinistri
                .filter(DatabaseSchema.SinistriColumns.riferimento == sinistroRef)
                .update(
                    DatabaseSchema.SinistriColumns.stato <- newState.descrizione,
                    DatabaseSchema.SinistriColumns.lastModifiedAt <- now.timeIntervalSince1970,
                    DatabaseSchema.SinistriColumns.syncedToCK <- false
                )
        )
        
        // Se chiuso, imposta data chiusura
        if newState == .chiusa || newState == .revocata || newState == .annullata {
            try conn.run(
                DatabaseSchema.sinistri
                    .filter(DatabaseSchema.SinistriColumns.riferimento == sinistroRef)
                    .update(DatabaseSchema.SinistriColumns.dataChiusura <- now.timeIntervalSince1970)
            )
        }
        
        try await syncSinistroToBackend(riferimento: sinistroRef)
        
        print("[ClaimEngine] 🔄 Stato cambiato: \(sinistroRef) → \(newState.descrizione)")
    }
    
    private func calculateLegacyPath(for riferimento: String, assigneeEmail: String?) -> String {
        // Base path (configurabile)
        let basePath = ProcessInfo.processInfo.environment["LEGACY_BASE_PATH"] ?? "W:\\Sinistri"
        return "\(basePath)\\\(riferimento)"
    }
    
    private func syncSinistroToBackend(riferimento: String) async throws {
        // Marca come sincronizzato dopo push al backend Supabase.
        do {
            try await BackendAPIClient.shared.syncSinistro(riferimento: riferimento)

            let conn = try await db.db()
            try conn.run(
                DatabaseSchema.sinistri
                    .filter(DatabaseSchema.SinistriColumns.riferimento == riferimento)
                    .update(DatabaseSchema.SinistriColumns.syncedToCK <- true)
            )
        } catch {
            print("[ClaimEngine] ⚠️ Sync backend fallito: \(error)")
        }
    }
    
    // MARK: - Public Query Methods
    
    public func getSinistroByRef(_ riferimento: String) async -> SinistroRecord? {
        return await getSinistro(riferimento: riferimento)
    }
    
    public func updateAssignment(
        riferimento: String,
        newAssignee: String,
        assignmentDate: Date
    ) async throws {
        let conn = try await db.db()
        
        try conn.run(
            DatabaseSchema.sinistri
                .filter(DatabaseSchema.SinistriColumns.riferimento == riferimento)
                .update(
                    DatabaseSchema.SinistriColumns.assegnatario <- newAssignee,
                    DatabaseSchema.SinistriColumns.dataAssegnazione <- assignmentDate.timeIntervalSince1970,
                    DatabaseSchema.SinistriColumns.lastModifiedAt <- Date().timeIntervalSince1970,
                    DatabaseSchema.SinistriColumns.syncedToCK <- false
                )
        )
        
        try await syncSinistroToBackend(riferimento: riferimento)
    }
    
    private func createTask(
        title: String,
        sinistroRef: String?,
        priority: TaskPriority,
        dueDate: Date?
    ) async throws -> HubTask {
        let task = HubTask(
            title: title,
            type: .action,
            priority: priority,
            sinistroRef: sinistroRef,
            dueDate: dueDate
        )
        
        _ = try await TaskEngine.shared.createTask(task)
        print("[ClaimEngine] 📋 Task creata: \(title)")
        
        return task
    }
}

// MARK: - Decision Types

/// Decisione del ClaimEngine
public struct ClaimEngineDecision {
    public let action: ClaimEngineAction
    public let targetState: StatoSinistro?
    public let createTask: Bool
    public let taskTitle: String?
    public let taskPriority: TaskPriority?
    public let taskDueDate: Date?
    public let reason: String
    public let metadata: [String: Any]?
    
    public init(
        action: ClaimEngineAction,
        targetState: StatoSinistro? = nil,
        createTask: Bool = false,
        taskTitle: String? = nil,
        taskPriority: TaskPriority? = nil,
        taskDueDate: Date? = nil,
        reason: String,
        metadata: [String: Any]? = nil
    ) {
        self.action = action
        self.targetState = targetState
        self.createTask = createTask
        self.taskTitle = taskTitle
        self.taskPriority = taskPriority
        self.taskDueDate = taskDueDate
        self.reason = reason
        self.metadata = metadata
    }
}

/// Azioni possibili del ClaimEngine
public enum ClaimEngineAction: String, Codable, Sendable {
    case none
    case logOnly
    case createSinistro
    case changeState
    case createTask
    case notify
}

/// Risultato del processing
public struct ClaimEngineResult: Codable, Sendable {
    public let eventId: String
    public var success: Bool
    public let action: ClaimEngineAction
    public var message: String
    public var details: [String: String]
    
    public init(
        eventId: String,
        success: Bool,
        action: ClaimEngineAction,
        message: String,
        details: [String: String] = [:]
    ) {
        self.eventId = eventId
        self.success = success
        self.action = action
        self.message = message
        self.details = details
    }
}

// MARK: - Internal Types

/// Record sinistro dal database
public struct SinistroRecord {
    public let riferimento: String
    public let stato: String
    public let ownerEmail: String?
    public let dataAssegnazione: Date?
}

// MARK: - Date Extension

extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}
