import Foundation
import Combine
import CoreData

/// Manager centrale per la gestione di tutte le task giornaliere
@MainActor
class TaskManager: ObservableObject {
    static let shared = TaskManager()
    
    @Published var tasks: [DailyTask] = []
    @Published var updateCounter: Int = 0
    
    private let durationService = TaskDurationService.shared
    private let workScheduleManager = WorkScheduleManager.shared
    private let statoManager = StatoManager.shared
    private let fileService = FileService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Hub integration
    private let hubMode = HubModeService.shared
    private let taskAdapter = TaskAdapter.shared
    
    private let tasksKey = "dailyTasks"
    private let suppressedTasksKey = "suppressedTasks"
    
    /// Task soppressi dall'utente (non devono essere rigenerati)
    /// Key: "\(sinistroID)_\(baseTaskType)" -> Data soppressione
    private var suppressedTasks: [String: Date] = [:]
    
    // Daily Scheduler properties
    private let lastDailyRunKey = "lastDailyTaskGenerationDate"
    private let lastEmailTriggeredRegenerationKey = "lastEmailTriggeredRegeneration"
    private let emailRegenerationCooldown: TimeInterval = 90
    
    private init() {
        loadTasks()
        loadSuppressedTasks()
        setupObservers()
        checkDailyTasksOnStartup()
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Ascolta cambi di stato sinistri
        NotificationCenter.default.publisher(for: .sinistroStatoChanged)
            .sink { [weak self] notification in
                Task { @MainActor in
                    if let userInfo = notification.userInfo,
                       let sinistroID = userInfo["sinistroID"] as? String,
                       let newState = userInfo["newState"] as? StatoManager.StatoSinistro {
                        
                        let oldState = (userInfo["oldState"] as? StatoManager.StatoSinistro) ?? newState
                        
                        // Log nel diario del cambio stato
                        if oldState != newState {
                            let context = PersistenceController.shared.container.viewContext
                            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
                            request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
                            if let sinistro = try? context.fetch(request).first {
                                sinistro.addDiarioEntry(DiarioEntry(
                                    testo: "Cambio stato: \(oldState.descrizione) → \(newState.descrizione)",
                                    tipo: .cambioStato
                                ))
                                try? context.save()
                            }
                        }
                        
                        // Verifica completamento task esistenti
                        self?.checkStateBasedCompletion(sinistroID: sinistroID, newState: newState)
                        
                        // Aggiorna task di base per questo sinistro
                        self?.updateBaseTaskForSinistro(sinistroID: sinistroID, newState: newState)
                        
                        // Valida e invalida task basate sulle nuove condizioni
                        self?.validateAndInvalidateTasks(for: sinistroID, newState: newState, eventType: nil)
                    }
                }
            }
            .store(in: &cancellables)
        
        // Ascolta eventi mail per auto-completamento goal
        NotificationCenter.default.publisher(for: .emailSent)
            .sink { [weak self] notification in
                Task { @MainActor in
                    if let userInfo = notification.userInfo,
                       let emailId = userInfo["emailId"] as? String,
                       let intentRaw = userInfo["intent"] as? String {
                        
                        // Determina il tipo di goal basato sull'intent
                        let goalType: TaskGoalType?
                        switch intentRaw {
                        case "reminderRequest", "documentationReminder":
                            goalType = .sendReminderEmail
                        case "actSent", "actRequest":
                            goalType = .sendActEmail
                        default:
                            goalType = .sendEmail
                        }
                        
                        if let goalType = goalType {
                            self?.checkGoalCompletion(
                                eventType: goalType,
                                targetValue: userInfo["sinistroID"] as? String,
                                eventDate: userInfo["sentDate"] as? Date ?? Date(),
                                eventId: emailId
                            )
                        }
                    }
                }
            }
            .store(in: &cancellables)
        
        // Ascolta eventi di documentazione ricevuta
        NotificationCenter.default.publisher(for: .documentationReceived)
            .sink { [weak self] notification in
                Task { @MainActor in
                    if let userInfo = notification.userInfo,
                       let sinistroID = userInfo["sinistroID"] as? String,
                       let eventDate = userInfo["eventDate"] as? Date,
                       let eventId = userInfo["eventId"] as? String {
                        
                        // Auto-completa task con goal receiveDocumentation
                        self?.checkGoalCompletion(
                            eventType: .receiveDocumentation,
                            targetValue: sinistroID,
                            eventDate: eventDate,
                            eventId: eventId
                        )
                        
                        // Invalida task di richiesta documentazione
                        if let currentState = self?.statoManager.getCurrentState(sinistroID: sinistroID) {
                            self?.validateAndInvalidateTasks(
                                for: sinistroID,
                                newState: currentState,
                                eventType: "documentationReceived"
                            )
                        }
                    }
                }
            }
            .store(in: &cancellables)
        
        // Ascolta modifiche orari di lavoro per riconfigurazione scheduler
        NotificationCenter.default.publisher(for: .workScheduleChanged)
            .sink { [weak self] _ in
                ScheduleManager.shared.setupDailyScheduler()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Task Management
    
    /// Aggiunge una nuova task
    func addTask(_ task: DailyTask) {
        tasks.append(task)
        saveTasks()
        updateCounter += 1
        
        // Se la task ha un obiettivo, avvisa lo scheduler
        if task.goal != nil {
            print("[TaskManager] 🎯 Aggiunta task con obiettivo: \(task.title)")
        }
    }
    
    /// Rimuove tutte le task pendenti associate a un sinistro
    func removeAllTasks(for sinistroID: String) {
        tasks.removeAll { $0.sinistroID == sinistroID && $0.status == .pending }
        saveTasks()
        updateCounter += 1
    }
    
    /// Genera task da comunicazione (email/WhatsApp)
    func generateTaskFromCommunication(
        email: Email? = nil,
        whatsappMessage: String? = nil,
        sinistroID: String? = nil,
        deadline: Date? = nil
    ) {
        // Verifica assegnazione se sinistroID è presente
        if let sinistroID = sinistroID {
            let context = PersistenceController.shared.container.viewContext
            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
            
            if let sinistro = try? context.fetch(request).first {
                let currentUserEmail = GoogleAuthService.shared.userEmail?.lowercased()
                let assignedEmail = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail ?? "").lowercased()
                
                // Se non assegnato a nessuno o assegnato a un altro, non generare task
                guard let currentEmail = currentUserEmail, !currentEmail.isEmpty, assignedEmail == currentEmail else {
                    return
                }
            }
        }
        
        let title: String
        let description: String
        let type: TaskType
        
        if let email = email {
            title = "Rispondere a: \(email.subject)"
            description = email.body.map { String($0.prefix(200)) } ?? "Rispondere all'email"
            type = .aiGenerated
            
            var metadata: [String: AnyCodable] = [
                "originalEmailId": AnyCodable(email.id),
                "emailSubject": AnyCodable(email.subject),
                "fromCommunication": AnyCodable(true)
            ]
            
            let task = DailyTask(
                title: title,
                description: description,
                type: type,
                sinistroID: sinistroID,
                priority: 0.5,
                deadline: deadline,
                estimatedDuration: durationService.getEstimatedDuration(for: type),
                metadata: metadata
            )
            
            addTask(task)
        } else if let message = whatsappMessage {
            title = "Rispondere a WhatsApp"
            description = String(message.prefix(200))
            type = .aiGenerated
            
            let task = DailyTask(
                title: title,
                description: String(description),
                type: type,
                sinistroID: sinistroID,
                priority: 0.5,
                deadline: deadline,
                estimatedDuration: durationService.getEstimatedDuration(for: type),
                metadata: ["fromCommunication": AnyCodable(true)]
            )
            
            addTask(task)
        }
    }
    
    // MARK: - Task specifiche
    
    func createAITriageTask(sinistro: Sinistro, title: String? = nil, description: String? = nil, priority: Double = 0.8, email: Email? = nil) {
        let finalTitle = title ?? "Triage AI: \(email?.subject ?? (sinistro.riferimento ?? ""))"
        let finalDescription = description ?? "Analizzare email per estrarre informazioni chiave"
        
        let task = DailyTask(
            title: finalTitle,
            description: finalDescription,
            type: .aiGenerated,
            sinistroID: sinistro.riferimento,
            priority: priority,
            estimatedDuration: 300,
            metadata: email != nil ? ["originalEmailId": AnyCodable(email!.id)] : [:],
            actionType: .verify
        )
        addTask(task)
    }
    
    func createDocumentationVerificationTask(sinistro: Sinistro, description: String? = nil) {
        let title = "Verificare documentazione: \(sinistro.riferimento ?? "")"
        let finalDescription = description ?? "Controllare la documentazione ricevuta"
        
        let task = DailyTask(
            title: title,
            description: finalDescription,
            type: .sinistroActivity,
            sinistroID: sinistro.riferimento,
            priority: 0.7,
            estimatedDuration: 900,
            actionType: .verify,
            goal: TaskGoal(type: .receiveDocumentation, targetValue: sinistro.riferimento),
            invalidationRules: TaskInvalidation(conditions: [.documentationReceived, .sinistroClosedOrRevoked])
        )
        addTask(task)
    }
    
    func handleFolderDownloaded(sinistroID: String) {
        print("[TaskManager] 📂 Cartella scaricata per \(sinistroID), gestione automatica...")
        if !tasks.contains(where: { $0.sinistroID == sinistroID && $0.actionType == .verify }) {
            let context = PersistenceController.shared.container.viewContext
            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
            if let sinistro = try? context.fetch(request).first {
                createDocumentationVerificationTask(sinistro: sinistro)
            }
        }
    }
    
    func createNewDocumentationTask(sinistroID: String) {
        let title = "Nuova documentazione: \(sinistroID)"
        let task = DailyTask(
            title: title,
            description: "È arrivata nuova documentazione da esaminare",
            type: .sinistroActivity,
            sinistroID: sinistroID,
            priority: 0.6,
            estimatedDuration: 600,
            actionType: .review
        )
        addTask(task)
    }
    
    func createManualDownloadFallbackTask(sinistroID: String) {
        let title = "Download manuale: \(sinistroID)"
        let task = DailyTask(
            title: title,
            description: "Il download automatico è fallito, procedere manualmente",
            type: .manual,
            sinistroID: sinistroID,
            priority: 0.9,
            estimatedDuration: 300,
            actionType: .request
        )
        addTask(task)
    }
    
    func getEstimatedDuration(for type: TaskType, sinistro: Sinistro? = nil) -> TimeInterval {
        return durationService.getEstimatedDuration(for: type)
    }
    
    func regenerateTaskTitles() {
        for index in tasks.indices {
            let task = tasks[index]
            if let _ = task.actionType {
                // Logica di rigenerazione titolo se necessaria
            }
        }
        updateCounter += 1
    }
    
    func cleanupExpiredTasks() {
        let now = Date()
        let calendar = Calendar.current
        tasks.removeAll { task in
            if task.status == .completed || task.status == .cancelled {
                if let date = task.completedAt, calendar.dateComponents([.day], from: date, to: now).day ?? 0 > 30 {
                    return true
                }
            }
            return false
        }
        saveTasks()
        updateCounter += 1
    }
    
    func updateTaskSchedule(taskID: UUID, scheduledDate: Date?, scheduledTime: Date?) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].scheduledDate = scheduledDate
        tasks[index].scheduledTime = scheduledTime
        saveTasks()
        updateCounter += 1
    }
    
    func checkEmailReplyCompletion(emailId: String, replyToEmailId: String) {
        for index in tasks.indices where tasks[index].status == .pending {
            if tasks[index].replyToEmailId == replyToEmailId {
                completeTaskWithEvent(taskID: tasks[index].id, eventDate: Date(), eventId: emailId)
            }
        }
    }
    
    // MARK: - Priorità
    
    func calculateBasePriority(for sinistro: Sinistro) -> Double {
        let monthlyGoal = workScheduleManager.getMonthlyTarget(for: Date())
        return PriorityCalculator.shared.calculateDynamicPriority(
            for: sinistro, 
            monthlyGoal: monthlyGoal, 
            currentClosures: 0, 
            needsAcceleration: false
        )
    }
    
    private func calculateBasePriorityForSinistro(sinistroID: String) -> Double {
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
        if let sinistro = try? PersistenceController.shared.container.viewContext.fetch(request).first {
            return calculateBasePriority(for: sinistro)
        }
        return 0.5
    }
    
    func updateTaskPriority(taskID: UUID, priority: Double) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        if abs(tasks[index].priority - priority) > 0.01 {
            tasks[index].priority = priority
            saveTasks()
            updateCounter += 1
        }
    }
    
    // MARK: - Query Task
    
    func getTasksForDate(_ date: Date) -> [DailyTask] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: date)
        
        return tasks.filter { task in
            guard task.status == .pending && !task.isIgnored else { return false }
            
            if task.hasExpired, let deadline = task.deadline {
                let daysSinceExpiry = calendar.dateComponents([.day], from: deadline, to: Date()).day ?? 0
                if daysSinceExpiry > 7 {
                    return false
                }
            }
            
            if let scheduledDate = task.scheduledDate {
                return calendar.isDate(scheduledDate, inSameDayAs: date)
            }
            
            if targetDate == today {
                return true
            }
            
            if targetDate > today {
                let daysSinceCreation = calendar.dateComponents([.day], from: task.createdAt, to: Date()).day ?? 0
                return daysSinceCreation <= 7
            }
            
            return false
        }
        .sorted { $0.priority > $1.priority }
    }
    
    func getTasksForToday() -> [DailyTask] {
        return getTasksForDate(Date())
    }
    
    func getBaseTasks(for sinistroID: String) -> [DailyTask] {
        return tasks.filter { task in
            task.sinistroID == sinistroID && 
            task.metadata["baseTaskType"] != nil &&
            task.status == .pending
        }
    }
    
    // MARK: - Completamento e Stati
    
    func startTask(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        
        if tasks[index].status == .pending {
            tasks[index].status = .inProgress
            tasks[index].startedAt = Date()
            saveTasks()
            updateCounter += 1
        }
    }
    
    func markTaskCompleted(taskID: UUID, manually: Bool = false) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let calendar = Calendar.current
        
        // Salva una copia del task prima di modificare l'array
        let task = tasks[index]
        let sinistroID = task.sinistroID
        
        tasks[index].status = .completed
        tasks[index].completedAt = Date()
        
        if let startedAt = task.startedAt {
            let actualDuration = Date().timeIntervalSince(startedAt)
            tasks[index].actualDuration = actualDuration
            tasks[index].estimatedDuration = actualDuration
            durationService.recordTaskDuration(taskType: task.type, actualDuration: actualDuration)
        }
        
        saveTasks()
        updateCounter += 1
        
        if let scheduledDate = task.scheduledDate {
            ScheduleManager.shared.rebalanceDayAfterCompletion(for: calendar.startOfDay(for: scheduledDate))
        }

        if let sinistroID = sinistroID {
            Task {
                await addTaskCompletionNoteToDiario(task: task, sinistroID: sinistroID)
            }
            Task {
                await ClaimSyncService.shared.finalizeAfterTasks(sinistroID: sinistroID)
            }
        }
    }
    
    private func addTaskCompletionNoteToDiario(task: DailyTask, sinistroID: String) async {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
        
        guard let sinistro = try? context.fetch(request).first else { return }
        
        let durationMinutes = Int(task.actualDuration ?? task.estimatedDuration) / 60
        let durationText = durationMinutes > 0 ? " (\(durationMinutes) min)" : ""
        
        // Gestione speciale per task "sollecita atto": registra sollecito inviato manualmente
        let baseTaskType = task.metadata["baseTaskType"]?.value as? String
        if baseTaskType == "sollecito_atto" {
            let sollicitoEntry = DiarioEntry(
                timestamp: Date(),
                tipo: .notaUtente,
                titolo: "Sollecito inviato manualmente",
                riassunto: "Sollecito atto inviato manualmente - in attesa di risposta",
                contenutoCompleto: "Sollecito atto inviato manualmente tramite task\(durationText). Il sinistro sarà in attesa per almeno 4 giorni lavorativi prima di poter essere nuovamente sollecitato."
            )
            
            await MainActor.run {
                // Aggiorna contatore e data solleciti inviati (consolidati sul modello)
                sinistro.registraSollecitoInviato()
                sinistro.addDiarioEntry(sollicitoEntry)
                try? context.save()
            }
            return
        }
        
        let noteText = "✅ Task completata: \(task.title)\(durationText)"
        
        let diarioEntry = DiarioEntry(
            timestamp: Date(),
            tipo: .notaUtente,
            titolo: "Task completata",
            riassunto: noteText,
            contenutoCompleto: noteText
        )
        
        await MainActor.run {
            sinistro.addDiarioEntry(diarioEntry)
            try? context.save()
        }
    }
    
    func markTaskIgnored(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = tasks[index]
        tasks[index].isIgnored = true
        
        // Aggiungi alla lista dei soppressi se è un baseTask
        suppressTaskIfNeeded(task)
        
        saveTasks()
        updateCounter += 1
    }
    
    func deleteTask(taskID: UUID) {
        // Prima di eliminare, salva nella lista soppressi se è un baseTask
        if let task = tasks.first(where: { $0.id == taskID }) {
            suppressTaskIfNeeded(task)
        }
        
        tasks.removeAll { $0.id == taskID }
        saveTasks()
        updateCounter += 1
    }
    
    /// Marca un task come cancellato (invece di eliminarlo)
    func cancelTask(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = tasks[index]
        tasks[index].status = .cancelled
        tasks[index].completedAt = Date()
        
        // Aggiungi alla lista dei soppressi se è un baseTask
        suppressTaskIfNeeded(task)
        
        saveTasks()
        updateCounter += 1
    }
    
    // MARK: - Task Suppression (Prevenzione Rigenerazione)
    
    /// Aggiunge un task alla lista dei soppressi se è un baseTask
    private func suppressTaskIfNeeded(_ task: DailyTask) {
        guard let sinistroID = task.sinistroID,
              let baseTaskType = task.metadata["baseTaskType"]?.value as? String else { return }
        
        let key = "\(sinistroID)_\(baseTaskType)"
        suppressedTasks[key] = Date()
        saveSuppressedTasks()
        print("[TaskManager] 🚫 Task soppresso: \(baseTaskType) per \(sinistroID)")
    }
    
    /// Verifica se un tipo di task è stato soppresso per un sinistro
    func isTaskSuppressed(sinistroID: String, baseTaskType: String) -> Bool {
        let key = "\(sinistroID)_\(baseTaskType)"
        return suppressedTasks[key] != nil
    }
    
    /// Riabilita un tipo di task per un sinistro (rimuove dalla lista soppressi)
    func unsuppressTask(sinistroID: String, baseTaskType: String) {
        let key = "\(sinistroID)_\(baseTaskType)"
        suppressedTasks.removeValue(forKey: key)
        saveSuppressedTasks()
        print("[TaskManager] ✅ Task riabilitato: \(baseTaskType) per \(sinistroID)")
    }
    
    /// Riabilita tutti i task per un sinistro
    func unsuppressAllTasks(for sinistroID: String) {
        let keysToRemove = suppressedTasks.keys.filter { $0.hasPrefix("\(sinistroID)_") }
        for key in keysToRemove {
            suppressedTasks.removeValue(forKey: key)
        }
        if !keysToRemove.isEmpty {
            saveSuppressedTasks()
            print("[TaskManager] ✅ Riabilitati \(keysToRemove.count) task per \(sinistroID)")
        }
    }
    
    /// Pulisce i task soppressi più vecchi di 60 giorni
    func cleanupOldSuppressedTasks() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let oldKeys = suppressedTasks.filter { $0.value < cutoffDate }.keys
        for key in oldKeys {
            suppressedTasks.removeValue(forKey: key)
        }
        if !oldKeys.isEmpty {
            saveSuppressedTasks()
            print("[TaskManager] 🧹 Rimossi \(oldKeys.count) task soppressi scaduti")
        }
    }
    
    /// Ottiene la lista dei tipi di task soppressi per un sinistro
    func getSuppressedTaskTypes(for sinistroID: String) -> [(type: String, suppressedAt: Date)] {
        let prefix = "\(sinistroID)_"
        return suppressedTasks
            .filter { $0.key.hasPrefix(prefix) }
            .compactMap { key, date -> (String, Date)? in
                let type = String(key.dropFirst(prefix.count))
                return (type, date)
            }
            .sorted { $0.1 > $1.1 } // Più recenti prima
    }
    
    /// Mappa dei nomi leggibili per i tipi di task
    static let taskTypeDisplayNames: [String: String] = [
        "documentazione": "Sollecitare documentazione",
        "perizia": "Eseguire perizia",
        "invio_atto": "Inviare atto",
        "sollecito_atto": "Sollecitare atto inviato",
        "sollecito_controllo": "Sollecitare controllo",
        "concordato_verbale": "Tentare concordato verbale",
        "chiusura": "Chiudere",
        "chiusura_non_concordato": "Chiudere non concordato",
        "polizza": "Richiedere polizza",
        "foto_ubicazione": "Richiedere foto ubicazione",
        "preventivo": "Richiedere preventivo",
        "iban": "Richiedere IBAN"
    ]
    
    private func loadSuppressedTasks() {
        if let data = UserDefaults.standard.data(forKey: suppressedTasksKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            suppressedTasks = decoded
            print("[TaskManager] 📂 Caricati \(suppressedTasks.count) task soppressi")
        }
    }
    
    private func saveSuppressedTasks() {
        if let encoded = try? JSONEncoder().encode(suppressedTasks) {
            UserDefaults.standard.set(encoded, forKey: suppressedTasksKey)
        }
    }
    
    private func checkStateBasedCompletion(sinistroID: String, newState: StatoManager.StatoSinistro) {
        for index in tasks.indices where tasks[index].sinistroID == sinistroID && tasks[index].status == .pending {
            let task = tasks[index]
            if task.title.lowercased().contains("chiudere") && newState == .chiusa {
                markTaskCompleted(taskID: task.id, manually: false)
            } else if task.title.lowercased().contains("verificare documentazione") {
                let postVerificationStates: Set<StatoManager.StatoSinistro> = [
                    .attoDaInviare, .esitoDaComunicare, .attoInviato, .esitoComunicato,
                    .attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa
                ]
                if postVerificationStates.contains(newState) {
                    markTaskCompleted(taskID: task.id, manually: false)
                }
            }
        }
    }
    
    func checkGoalCompletion(eventType: TaskGoalType, targetValue: String?, eventDate: Date, eventId: String) {
        for index in tasks.indices where tasks[index].status == .pending {
            guard let goal = tasks[index].goal else { continue }
            
            if goal.type == eventType {
                if let target = goal.targetValue, let provided = targetValue {
                    if target == provided {
                        completeTaskWithEvent(taskID: tasks[index].id, eventDate: eventDate, eventId: eventId)
                    }
                } else {
                    completeTaskWithEvent(taskID: tasks[index].id, eventDate: eventDate, eventId: eventId)
                }
            }
        }
    }
    
    private func completeTaskWithEvent(taskID: UUID, eventDate: Date, eventId: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        
        // Salva una copia del task prima di modificare l'array
        let task = tasks[index]
        let sinistroID = task.sinistroID
        
        tasks[index].status = .completed
        tasks[index].completedAt = eventDate
        tasks[index].completionEventId = eventId
        
        if let startedAt = task.startedAt {
            tasks[index].actualDuration = eventDate.timeIntervalSince(startedAt)
        }
        
        saveTasks()
        updateCounter += 1
        
        if let sinistroID = sinistroID {
            Task {
                await addTaskCompletionNoteToDiario(task: task, sinistroID: sinistroID)
            }
        }
    }
    
    func validateAndInvalidateTasks(for sinistroID: String, newState: StatoManager.StatoSinistro, eventType: String?) {
        let now = Date()
        var hasInvalidated = false
        
        // Stati post-atto: molte task non sono più rilevanti
        let statiPostAtto: Set<StatoManager.StatoSinistro> = [
            .attoRicevutoSottoscritto, .accettataVerbalmente
        ]
        let isPostAtto = statiPostAtto.contains(newState)
        
        for index in tasks.indices where tasks[index].sinistroID == sinistroID && tasks[index].status == .pending {
            if tasks[index].type == .manual { continue }
            
            var shouldInvalidate = false
            let task = tasks[index]
            let title = task.title.lowercased()
            
            // Invalidazione basata sul titolo per task senza invalidationRules
            if title.contains("sollecitare documentazione") || title.contains("sollecito documentazione") {
                let waitingStates: Set<StatoManager.StatoSinistro> = [
                    .inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia, .videoperiziaDaFissare
                ]
                if !waitingStates.contains(newState) {
                    shouldInvalidate = true
                }
            }
            
            // Quando l'atto viene ricevuto firmato, invalida TUTTE le task relative all'atto:
            // - Sollecitare atto inviato / sollecito atto
            // - Follow-up: Restiamo in attesa di atto
            // - Richiedere polizza (già avuta se abbiamo inviato l'atto)
            // - Richiedere IBAN (già nell'atto firmato)
            if isPostAtto {
                if title.contains("sollecit") && title.contains("atto") {
                    shouldInvalidate = true
                }
                if title.contains("follow-up") && title.contains("atto") {
                    shouldInvalidate = true
                }
                if title.contains("restiamo in attesa") && title.contains("atto") {
                    shouldInvalidate = true
                }
                if title.contains("richiedere polizza") || title.contains("polizza") && title.contains("richied") {
                    shouldInvalidate = true
                }
                if title.contains("richiedere iban") || title.contains("iban") {
                    shouldInvalidate = true
                }
            }
            
            if let invalidation = task.invalidationRules {
                for condition in invalidation.conditions {
                    switch condition {
                    case .sinistroClosedOrRevoked:
                        if newState == .chiusa || newState == .revocata || newState == .annullata {
                            shouldInvalidate = true
                        }
                    case .stateProgressed:
                        if let threshold = invalidation.stateThresholdEnum {
                            // Controllo se il nuovo stato è uguale o successivo alla threshold
                            if newState == threshold || newState.isAfter(threshold) {
                                shouldInvalidate = true
                            }
                        }
                    case .documentationReceived:
                        if eventType == "documentationReceived" { shouldInvalidate = true }
                    case .actReceived:
                        if newState == .attoRicevutoSottoscritto || newState == .accettataVerbalmente {
                            shouldInvalidate = true
                        }
                    case .reminderSent:
                        if eventType == "reminderSent" { shouldInvalidate = true }
                    case .emailReplied:
                        if eventType == "emailReplied" { shouldInvalidate = true }
                    case .policyReceived:
                        if eventType == "policyReceived" { shouldInvalidate = true }
                    }
                    if shouldInvalidate { break }
                }
            }
            
            if shouldInvalidate {
                tasks[index].status = .cancelled
                tasks[index].completedAt = now
                print("[TaskManager] 🚫 Task invalidata: \(tasks[index].title)")
                hasInvalidated = true
            }
        }
        
        if hasInvalidated {
            saveTasks()
            updateCounter += 1
        }
    }
    
    // MARK: - Generation and Scheduling
    
    func regenerateBaseTasks(triggeredByEmail: Bool = false) async {
        let now = Date()
        let defaults = UserDefaults.standard
        
        if triggeredByEmail {
            if let last = defaults.object(forKey: lastEmailTriggeredRegenerationKey) as? Date,
               now.timeIntervalSince(last) < emailRegenerationCooldown {
                return
            }
            defaults.set(now, forKey: lastEmailTriggeredRegenerationKey)
        }
        
        let lastRunKey = "lastGeneralRegenerationDate"
        if let last = defaults.object(forKey: lastRunKey) as? Date,
           now.timeIntervalSince(last) < 5 {
            return
        }
        defaults.set(now, forKey: lastRunKey)
        
        await validateAndCleanupExistingTasks()
        await BaseTaskGenerator.shared.generateDailyBaseTasks()
    }
    
    private func updateBaseTaskForSinistro(sinistroID: String, newState: StatoManager.StatoSinistro) {
        if newState == .chiusa || newState == .revocata || newState == .annullata {
            tasks.removeAll { task in
                guard task.sinistroID == sinistroID && task.status == .pending else { return false }
                if task.metadata["fromCommunication"]?.value as? Bool == true ||
                   task.metadata["manual"]?.value as? Bool == true {
                    return false
                }
                return true
            }
            
            // Pulisci anche i task soppressi per questo sinistro (chiuso)
            unsuppressAllTasks(for: sinistroID)
            
            saveTasks()
            updateCounter += 1
            return
        }
        
        // Riabilita task soppressi che non sono più rilevanti per lo stato attuale
        // (es: se era soppresso "sollecito_atto" ma ora siamo in "attoRicevutoSottoscritto")
        cleanupIrrelevantSuppressedTasks(for: sinistroID, newState: newState)
        
        Task {
            await BaseTaskGenerator.shared.updateOrCreateBaseTasksForSinistro(sinistroID: sinistroID)
        }
    }
    
    /// Rimuove i task soppressi che non sono più rilevanti per lo stato attuale
    private func cleanupIrrelevantSuppressedTasks(for sinistroID: String, newState: StatoManager.StatoSinistro) {
        // Mappa: tipo task -> stati in cui è rilevante
        let taskStateRelevance: [String: Set<StatoManager.StatoSinistro>] = [
            "documentazione": [.inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia],
            "perizia": [.inGestione, .inGestioneDocumentale],
            "invio_atto": [.attoDaInviare, .esitoDaComunicare, .esitoComunicato],
            "sollecito_atto": [.attoInviato],
            "sollecito_controllo": [.richiestaAutorizzazione, .supervisioneNonConcordata, .inControllo],
            "concordato_verbale": [.attoDaInviare, .esitoDaComunicare, .esitoComunicato, .attoInviato],
            "chiusura": [.attoRicevutoSottoscritto, .accettataVerbalmente],
            "chiusura_non_concordato": [.attoInviato]
        ]
        
        var tasksToUnsuppress: [String] = []
        
        for (taskType, relevantStates) in taskStateRelevance {
            let key = "\(sinistroID)_\(taskType)"
            if suppressedTasks[key] != nil && !relevantStates.contains(newState) {
                tasksToUnsuppress.append(taskType)
            }
        }
        
        for taskType in tasksToUnsuppress {
            unsuppressTask(sinistroID: sinistroID, baseTaskType: taskType)
        }
    }
    
    func validateAndCleanupExistingTasks() async {
        let context = PersistenceController.shared.container.viewContext
        let chiusaDesc = StatoManager.StatoSinistro.chiusa.descrizione
        let revocataDesc = StatoManager.StatoSinistro.revocata.descrizione
        let annullataDesc = StatoManager.StatoSinistro.annullata.descrizione
        let now = Date()
        let calendar = Calendar.current
        
        var tasksToRemove: [UUID] = []
        var tasksToComplete: [UUID] = []
        
        await MainActor.run {
            for task in tasks where task.status == .pending && !task.isIgnored {
                if task.metadata["fromCommunication"]?.value as? Bool == true ||
                   task.metadata["manual"]?.value as? Bool == true {
                    continue
                }
                
                if task.hasExpired, let deadline = task.deadline {
                    if (calendar.dateComponents([.day], from: deadline, to: now).day ?? 0) > 7 {
                        tasksToComplete.append(task.id)
                        continue
                    }
                }
                
                guard let sinistroID = task.sinistroID else { continue }
                let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
                request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
                
                guard let sinistro = try? context.fetch(request).first,
                      let stato = sinistro.stato else {
                    tasksToRemove.append(task.id)
                    continue
                }
                
                let isClosed = [chiusaDesc, revocataDesc, annullataDesc].contains(stato)
                if isClosed {
                    tasksToRemove.append(task.id)
                    continue
                }
                
                let title = task.title.lowercased()
                let statoEnum = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == stato })
                
                if title.contains("sollecitare documentazione") || title.contains("sollecito documentazione") {
                    let waitingStates: Set<StatoManager.StatoSinistro> = [
                        .inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia, .videoperiziaDaFissare
                    ]
                    if let s = statoEnum, !waitingStates.contains(s) {
                        tasksToRemove.append(task.id)
                    }
                } else if title.contains("verificare documentazione") {
                    let postVerificationStates: Set<StatoManager.StatoSinistro> = [
                        .attoDaInviare, .esitoDaComunicare, .attoInviato, .esitoComunicato,
                        .attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa
                    ]
                    if let s = statoEnum, postVerificationStates.contains(s) {
                        tasksToComplete.append(task.id)
                    }
                } else if title.contains("sollecita atto") || title.contains("sollecitare atto") {
                    if statoEnum != .attoInviato {
                        tasksToComplete.append(task.id)
                    }
                }
                
                // Invalida task non più rilevanti dopo ricezione atto firmato
                let statiPostAtto: Set<StatoManager.StatoSinistro> = [
                    .attoRicevutoSottoscritto, .accettataVerbalmente
                ]
                if let s = statoEnum, statiPostAtto.contains(s) {
                    // Follow-up atto, sollecito atto, polizza, IBAN - non più necessari
                    if title.contains("follow-up") && title.contains("atto") {
                        tasksToComplete.append(task.id)
                    } else if title.contains("restiamo in attesa") && title.contains("atto") {
                        tasksToComplete.append(task.id)
                    } else if title.contains("richiedere polizza") {
                        tasksToComplete.append(task.id)
                    } else if title.contains("richiedere iban") {
                        tasksToComplete.append(task.id)
                    }
                }
            }
            
            if !tasksToRemove.isEmpty {
                tasks.removeAll { tasksToRemove.contains($0.id) }
            }
            
            if !tasksToComplete.isEmpty {
                for taskId in tasksToComplete {
                    if let index = tasks.firstIndex(where: { $0.id == taskId }) {
                        tasks[index].status = .completed
                        tasks[index].completedAt = now
                    }
                }
            }
            
            if !tasksToRemove.isEmpty || !tasksToComplete.isEmpty {
                saveTasks()
                updateCounter += 1
            }
        }
    }
    
    func ensureBaseTasksAreScheduled() {
        var updated = false
        for index in tasks.indices where tasks[index].status == .pending && !tasks[index].isIgnored {
            if tasks[index].metadata["baseTask"]?.value as? Bool == true && tasks[index].scheduledDate == nil {
                let (date, time) = ScheduleManager.shared.scheduleTaskAutomatically(task: tasks[index])
                tasks[index].scheduledDate = date
                tasks[index].scheduledTime = time
                updated = true
            }
        }
        if updated {
            saveTasks()
            updateCounter += 1
        }
    }
    
    func distributeTasksInSchedule(for date: Date) -> [ScheduledTask] {
        return ScheduleManager.shared.distributeTasksInSchedule(for: date)
    }
    
    func reorganizeAllTasksBasedOnSchedule(userInitiated: Bool = false) {
        ScheduleManager.shared.reorganizeAllTasksBasedOnSchedule(userInitiated: userInitiated)
    }
    
    func rescheduleIncompleteTasks() {
        ScheduleManager.shared.rescheduleIncompleteTasks()
    }
    
    // MARK: - Daily Scheduler
    
    private func checkDailyTasksOnStartup() {
        if let lastRunString = UserDefaults.standard.string(forKey: lastDailyRunKey),
           let lastRun = ISO8601DateFormatter().date(from: lastRunString),
           Calendar.current.isDate(lastRun, inSameDayAs: Date()) {
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s: evita freeze navigazione (es. Sinistri) subito dopo avvio
            await ScheduleManager.shared.runDailyTasks()
        }
    }
    
    // MARK: - Persistence
    
    private func loadTasks() {
        // HUB MODE: carica da Hub se attivo
        if hubMode.shouldUseHub(for: .task) {
            Task {
                await loadTasksFromHub()
            }
            return
        }
        
        // Modalità locale
        if let data = UserDefaults.standard.data(forKey: tasksKey),
           let decoded = try? JSONDecoder().decode([DailyTask].self, from: data) {
            tasks = decoded
        }
    }
    
    /// Carica task dall'Hub
    private func loadTasksFromHub() async {
        do {
            guard let userId = CurrentUserService.shared.currentUsername ?? AppState.shared.googleAuthService.userEmail else { return }
            let hubTasks = try await taskAdapter.getTasks(userId: userId, userEmail: CurrentUserService.shared.currentEmail)
            
            // Converte TaskListItem in DailyTask
            var convertedTasks: [DailyTask] = []
            for item in hubTasks {
                let task = DailyTask(
                    title: item.title,
                    description: item.description ?? "",
                    type: item.type,
                    sinistroID: item.sinistroRef,
                    priority: item.priority,
                    deadline: item.dueDate
                )
                convertedTasks.append(task)
            }
            
            tasks = convertedTasks
            print("[TaskManager] ✅ Caricate \(tasks.count) task da Hub")
        } catch {
            print("[TaskManager] ❌ Errore caricamento Hub: \(error)")
            // Fallback a locale
            if let data = UserDefaults.standard.data(forKey: tasksKey),
               let decoded = try? JSONDecoder().decode([DailyTask].self, from: data) {
                tasks = decoded
            }
        }
    }
    
    func saveTasks() {
        // Salva sempre in locale come backup
        if let encoded = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(encoded, forKey: tasksKey)
        }
        
        // HUB MODE: sincronizza con Hub (async in background)
        if hubMode.shouldUseHub(for: .task) {
            Task {
                await syncTasksToHub()
            }
        }
    }
    
    /// Sincronizza task completate all'Hub
    private func syncTasksToHub() async {
        // Sincronizza solo task completate
        let completedTasks = tasks.filter { $0.completedAt != nil && $0.status == .completed }
        
        for task in completedTasks {
            do {
                try await taskAdapter.completeTask(id: task.id.uuidString)
            } catch {
                print("[TaskManager] ❌ Sync Hub fallito per task \(task.id): \(error)")
            }
        }
    }
    
    private func autoUpdateStateIfFolderPresent(_ sinistro: Sinistro) {
        guard let riferimento = sinistro.riferimento,
              let path = fileService.getSinistroPath(riferimento: riferimento, create: false) else { return }
        if fileService.hasAnyRegularFileRecursively(inDirectory: path) {
            if sinistro.stato == StatoManager.StatoSinistro.daScaricare.descrizione ||
                sinistro.stato == StatoManager.StatoSinistro.istruzione.descrizione {
                let newState = StatoManager.shared.operationalEntryState(for: sinistro)
                Task {
                    try? await StatoManager.shared.changeState(for: sinistro, to: newState, context: PersistenceController.shared.container.viewContext)
                }
            }
        }
    }
}
