import Foundation

// ============================================================================
// MARK: - MailManager Extensions for Adapters
// Fornisce l'interfaccia necessaria agli adapter per la modalità locale
// ============================================================================

extension MailManager {
    
    /// Ottiene email per un sinistro specifico
    func getEmailsForAdapter(sinistroRef: String) async -> [Email] {
        // Usa la cache esistente del MailManager
        // Filtra per sinistro se disponibile
        return []  // TODO: Implementare quando necessario
    }
    
    /// Ottiene le email più recenti
    func getRecentEmailsForAdapter(limit: Int) async -> [Email] {
        // TODO: Implementare quando necessario
        return []
    }
    
    /// Ottiene una singola email per ID
    func getEmailForAdapter(id: String) async -> Email? {
        // TODO: Implementare quando necessario
        return nil
    }
}

// ============================================================================
// MARK: - TaskManager Extensions for Adapters
// ============================================================================

extension TaskManager {
    
    /// Ottiene task per sinistro
    func getTasksForAdapter(sinistroRef: String) async -> [DailyTask] {
        // Filtra i task esistenti per sinistro
        return tasks.filter { $0.sinistroID == sinistroRef }
    }
    
    /// Ottiene task per utente (userId = username, userEmail opzionale per retrocompat)
    func getTasksForAdapter(userId: String, userEmail: String? = nil) async -> [DailyTask] {
        return tasks
    }
    
    /// Completa un task per ID (per adapter)
    func completeTaskForAdapter(id: String) async {
        guard let uuid = UUID(uuidString: id) else { return }
        await MainActor.run {
            if let index = tasks.firstIndex(where: { $0.id == uuid }) {
                var task = tasks[index]
                task.status = .completed
                task.completedAt = Date()
                tasks[index] = task
                saveTasks()
            }
        }
        // Sincronizza con il server (no-op se task mai sync'd)
        await TaskSyncQueue.shared.enqueueComplete(localId: uuid)
    }
    
    /// Crea un nuovo task (per adapter)
    func createTaskForAdapter(
        title: String,
        description: String?,
        type: TaskType,
        sinistroRef: String?,
        dueDate: Date?
    ) async -> DailyTask? {
        // Crea task con i parametri minimi necessari
        let task = DailyTask(
            title: title,
            description: description ?? "",
            type: type,
            sinistroID: sinistroRef,
            priority: 0.5,
            deadline: dueDate
        )
        
        await MainActor.run {
            addTask(task)
        }
        
        return task
    }
    
    /// Aggiorna un task esistente (per adapter)
    func updateTaskForAdapter(
        id: String,
        title: String?,
        description: String?,
        dueDate: Date?,
        status: TaskStatus?
    ) async -> DailyTask? {
        guard let uuid = UUID(uuidString: id),
              let index = tasks.firstIndex(where: { $0.id == uuid }) else {
            return nil
        }
        
        var task = tasks[index]
        
        if let title = title {
            task.title = title
        }
        if let description = description {
            task.description = description
        }
        if let dueDate = dueDate {
            task.deadline = dueDate
        }
        if let status = status {
            task.status = status
        }
        
        await MainActor.run {
            tasks[index] = task
            saveTasks()
        }
        
        return task
    }
}

// ============================================================================
// MARK: - DailyTask Sinistro Reference
// ============================================================================

extension DailyTask {
    /// Restituisce il riferimento sinistro (alias per sinistroID)
    var sinistroRef: String? {
        return sinistroID
    }
}
