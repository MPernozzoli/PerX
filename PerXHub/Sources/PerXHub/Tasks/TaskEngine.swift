import Foundation
import PerXCore
import SQLite

/// Engine centralizzato per gestione task
/// Migrato da TaskManager, ScheduleManager, BaseTaskGenerator del client
public actor TaskEngine {
    public static let shared = TaskEngine()
    
    private var scheduledTimers: [String: Task<Void, Never>] = [:]
    private var isRunning = false
    
    private init() {}
    
    // MARK: - Lifecycle
    
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        
        // Avvia scheduler
        Task {
            await runScheduler()
        }
        
        print("[TaskEngine] Started")
    }
    
    public func stop() {
        isRunning = false
        
        // Cancella tutti i timer
        for (_, timer) in scheduledTimers {
            timer.cancel()
        }
        scheduledTimers.removeAll()
        
        print("[TaskEngine] Stopped")
    }
    
    // MARK: - Scheduler Loop
    
    private func runScheduler() async {
        while isRunning {
            do {
                // Check task schedulati
                try await checkScheduledTasks()
                
                // Check scadenze
                try await checkDeadlines()
                
                // Check promemoria
                try await checkReminders()
                
            } catch {
                print("[TaskEngine] Scheduler error: \(error)")
            }
            
            // Pausa 60 secondi
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }
    
    // MARK: - Task Management
    
    /// Crea nuovo task
    public func createTask(_ task: HubTask) async throws -> HubTask {
        // TODO: Salvare nel database
        print("[TaskEngine] Created task: \(task.id) - \(task.title)")
        return task
    }
    
    /// Aggiorna task
    public func updateTask(_ task: HubTask) async throws -> HubTask {
        // TODO: Aggiornare nel database
        print("[TaskEngine] Updated task: \(task.id)")
        return task
    }
    
    /// Completa task
    public func completeTask(_ taskId: String) async throws {
        // TODO: Marcare come completato
        print("[TaskEngine] Completed task: \(taskId)")
    }
    
    /// Ottiene task per sinistro
    public func getTasks(sinistroRef: String) async throws -> [HubTask] {
        // TODO: Query dal database
        return []
    }
    
    /// Ottiene task in scadenza
    public func getUpcomingTasks(days: Int = 7) async throws -> [HubTask] {
        // TODO: Query dal database
        return []
    }
    
    // MARK: - Scheduling
    
    /// Schedula un task per esecuzione futura
    public func scheduleTask(_ taskId: String, at date: Date) async throws {
        // Cancella eventuale schedule esistente
        if let existing = scheduledTimers[taskId] {
            existing.cancel()
        }
        
        let delay = date.timeIntervalSinceNow
        guard delay > 0 else {
            // Esegui subito
            try await executeScheduledTask(taskId)
            return
        }
        
        // Crea timer
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !Task.isCancelled {
                try? await self.executeScheduledTask(taskId)
            }
        }
        
        scheduledTimers[taskId] = timer
        print("[TaskEngine] Scheduled task \(taskId) for \(date)")
    }
    
    /// Esegue task schedulato
    private func executeScheduledTask(_ taskId: String) async throws {
        print("[TaskEngine] Executing scheduled task: \(taskId)")
        
        // TODO: Recupera task e esegui azione
        // Potrebbe essere:
        // - Invio email programmata
        // - Creazione reminder
        // - Notifica scadenza
        
        scheduledTimers.removeValue(forKey: taskId)
    }
    
    // MARK: - Automated Checks
    
    /// Controlla task schedulati
    private func checkScheduledTasks() async throws {
        // TODO: Query task con execution_date <= now e status = pending
    }
    
    /// Controlla scadenze
    private func checkDeadlines() async throws {
        // TODO: Query task con deadline vicina
        // Crea notifiche per scadenze imminenti
    }
    
    /// Controlla promemoria
    private func checkReminders() async throws {
        // TODO: Query reminders attivi
    }
    
    // MARK: - Task Generation (from BaseTaskGenerator)
    
    /// Genera task automatici da template
    public func generateTasksFromTemplate(_ templateId: String, for sinistroRef: String) async throws -> [HubTask] {
        // TODO: Recupera template e genera task
        print("[TaskEngine] Generating tasks from template \(templateId) for \(sinistroRef)")
        return []
    }
    
    /// Genera task da email classificata
    public func generateTasksFromEmail(_ email: ClassifiedEmail) async throws -> [HubTask] {
        var tasks: [HubTask] = []
        
        // Genera task in base alla categoria email
        switch email.category {
        case .assignment:
            // Nuovo incarico: crea task accettazione
            let task = HubTask(
                id: UUID().uuidString,
                title: "Accettare incarico",
                description: "Confermare accettazione incarico: \(email.originalEmail.subject)",
                type: .action,
                priority: .high,
                sinistroRef: email.sinistroId,
                dueDate: Date().addingTimeInterval(86400), // +1 giorno
                status: .pending
            )
            tasks.append(task)
            
        case .actReceived:
            // Atto ricevuto: crea task urgente
            let task = HubTask(
                id: UUID().uuidString,
                title: "Gestire atto ricevuto",
                description: "Verificare e processare atto ricevuto",
                type: .action,
                priority: .urgent,
                sinistroRef: email.sinistroId,
                dueDate: Date().addingTimeInterval(43200), // +12 ore
                status: .pending
            )
            tasks.append(task)
            
        case .reminderReceived:
            // Sollecito ricevuto: crea task risposta
            let task = HubTask(
                id: UUID().uuidString,
                title: "Rispondere a sollecito",
                description: "Rispondere a: \(email.originalEmail.subject)",
                type: .action,
                priority: .high,
                sinistroRef: email.sinistroId,
                dueDate: Date().addingTimeInterval(86400),
                status: .pending
            )
            tasks.append(task)
            
        case .revocation:
            // Revoca incarico: crea task archiviazione
            let task = HubTask(
                id: UUID().uuidString,
                title: "Gestire revoca incarico",
                description: "Archiviare sinistro revocato",
                type: .action,
                priority: .high,
                sinistroRef: email.sinistroId,
                dueDate: Date().addingTimeInterval(86400),
                status: .pending
            )
            tasks.append(task)
            
        case .documentationReceived:
            // Documentazione ricevuta: crea task verifica
            let task = HubTask(
                id: UUID().uuidString,
                title: "Verificare documentazione",
                description: "Verificare documentazione ricevuta",
                type: .action,
                priority: .normal,
                sinistroRef: email.sinistroId,
                dueDate: Date().addingTimeInterval(172800), // +2 giorni
                status: .pending
            )
            tasks.append(task)
            
        case .revisionRequested:
            // Richiesta revisione: task urgente
            let task = HubTask(
                id: UUID().uuidString,
                title: "Revisionare perizia",
                description: "Effettuare revisione richiesta dalla compagnia",
                type: .action,
                priority: .urgent,
                sinistroRef: email.sinistroId,
                dueDate: Date().addingTimeInterval(86400),
                status: .pending
            )
            tasks.append(task)
            
        default:
            break
        }
        
        // Salva task generati
        for task in tasks {
            _ = try await createTask(task)
        }
        
        return tasks
    }
}

// MARK: - Task Types
// I modelli HubTask, TaskType, TaskPriority, TaskStatus sono ora definiti in PerXCore/Models/Task.swift
