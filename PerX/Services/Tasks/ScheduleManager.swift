import Foundation
import Combine

/// Manager per la pianificazione delle task nelle working hours
/// Si occupa esclusivamente di scheduling e riorganizzazione in tempo reale
@MainActor
class ScheduleManager: ObservableObject {
    static let shared = ScheduleManager()

    private let taskManager = TaskManager.shared
    private let workScheduleManager = WorkScheduleManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var isReorganizing = false
    private var reorganizationTask: Task<Void, Never>?
    private var lastReorganizationTime: Date?
    /// Cooldown 30s tra riorganizzazioni automatiche; bypassato se userInitiated (es. tasto Aggiorna)
    private let schedulingCooldownInterval: TimeInterval = 30.0

    // Daily Scheduler properties
    private var dailySchedulerTimer: Timer?
    private let lastDailyRunKey = "lastDailyTaskGenerationDate"
    
    private init() {
        setupObservers()
        setupDailyScheduler()
    }

    // MARK: - Setup Observers

    private func setupObservers() {
        // Ascolta modifiche agli orari lavorativi tramite Combine
        workScheduleManager.$updateCounter
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.reorganizeAllTasksBasedOnSchedule()
                }
            }
            .store(in: &cancellables)

        // Ascolta modifiche agli orari lavorativi tramite NotificationCenter (backup più affidabile)
        NotificationCenter.default.publisher(for: .workScheduleChanged)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.reorganizeAllTasksBasedOnSchedule()
                    self?.setupDailyScheduler()
                }
            }
            .store(in: &cancellables)

        // Ascolta creazione nuove task
        NotificationCenter.default.publisher(for: .taskCreated)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.reorganizeAllTasksBasedOnSchedule()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Distribuzione e Scheduling

    /// Distribuisce task in base agli orari lavorativi
    func distributeTasksInSchedule(for date: Date) -> [ScheduledTask] {
        let calendar = Calendar.current
        let rawWorkingHours = workScheduleManager.getWorkingHours(for: date)
        guard !rawWorkingHours.isEmpty else { return [] }

        // Helper per combinare data e ora
        func combineDateTime(targetDate: Date, time: Date) -> Date {
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            dateComponents.second = timeComponents.second ?? 0
            return calendar.date(from: dateComponents) ?? targetDate
        }

        // Converti gli orari lavorativi alla data corretta
        let workingHours = rawWorkingHours.map { hours -> (start: Date, end: Date) in
            (start: combineDateTime(targetDate: date, time: hours.start),
             end: combineDateTime(targetDate: date, time: hours.end))
        }

        // Usa getTasksForDate per ottenere tutte le task per questa data (include anche quelle senza scheduledDate)
        var availableTasks = taskManager.getTasksForDate(date)

        // Aggiorna flag scadute e priorità (aggiorna nell'array originale)
        for task in availableTasks {
            if task.hasExpired {
                if let index = taskManager.tasks.firstIndex(where: { $0.id == task.id }) {
                    taskManager.tasks[index].isExpired = true
                    taskManager.tasks[index].priority = min(1.0, taskManager.tasks[index].priority * 2.0)
                }
            }
        }

        // Ricarica per avere le priorità aggiornate
        availableTasks = taskManager.getTasksForDate(date)

        // Ordina per priorità (scadute prima, poi per priorità)
        availableTasks.sort { task1, task2 in
            if task1.isExpired != task2.isExpired {
                return task1.isExpired
            }
            return task1.priority > task2.priority
        }

        // Distribuisci task negli slot temporali
        var scheduledTasks: [ScheduledTask] = []
        var currentTimeIndex = 0
        var currentSlotStart = workingHours.first?.start ?? date

        for task in availableTasks {
            // Task con scadenza specifica: schedulale rispettando orari lavorativi
            if let deadline = task.deadline {
                let deadlineDay = calendar.startOfDay(for: deadline)
                let taskDay = calendar.startOfDay(for: date)
                
                // Se il deadline è nello stesso giorno, trova lo slot appropriato
                if calendar.isDate(deadlineDay, inSameDayAs: taskDay) {
                    // Trova lo slot lavorativo che contiene il deadline
                    var foundSlot = false
                    for slot in workingHours {
                        if deadline >= slot.start && deadline <= slot.end {
                            // Il deadline è dentro questo slot
                            let startTime = max(slot.start, deadline.addingTimeInterval(-task.estimatedDuration))
                            // Se la durata non ci sta prima del deadline, inizia dall'inizio dello slot
                            let actualStart = startTime < slot.start ? slot.start : startTime
                            let actualEnd = actualStart.addingTimeInterval(task.estimatedDuration)
                            
                            // Se non ci sta nello slot, sposta al giorno precedente o all'inizio
                            if actualEnd > slot.end {
                                // Cerca il primo slot disponibile del giorno
                                if let firstSlot = workingHours.first {
                                    let fallbackStart = firstSlot.start
                                    let fallbackEnd = fallbackStart.addingTimeInterval(task.estimatedDuration)
                                    if fallbackEnd <= firstSlot.end {
                                        let scheduledTask = ScheduledTask(
                                            task: task,
                                            scheduledStartTime: fallbackStart,
                                            scheduledEndTime: fallbackEnd
                                        )
                                        scheduledTasks.append(scheduledTask)
                                        foundSlot = true
                                        break
                                    }
                                }
                            } else {
                                let scheduledTask = ScheduledTask(
                                    task: task,
                                    scheduledStartTime: actualStart,
                                    scheduledEndTime: actualEnd
                                )
                                scheduledTasks.append(scheduledTask)
                                foundSlot = true
                                break
                            }
                        }
                    }
                    
                    // Se non trovato, programma all'inizio del primo slot disponibile
                    if !foundSlot, let firstSlot = workingHours.first {
                        let startTime = firstSlot.start
                        let endTime = startTime.addingTimeInterval(task.estimatedDuration)
                        if endTime <= firstSlot.end {
                            let scheduledTask = ScheduledTask(
                                task: task,
                                scheduledStartTime: startTime,
                                scheduledEndTime: endTime
                            )
                            scheduledTasks.append(scheduledTask)
                            continue
                        }
                    }
                } else if deadlineDay < taskDay {
                    // Deadline è passato, programma all'inizio del primo slot
                    if let firstSlot = workingHours.first {
                        let startTime = firstSlot.start
                        let endTime = startTime.addingTimeInterval(task.estimatedDuration)
                        if endTime <= firstSlot.end {
                            let scheduledTask = ScheduledTask(
                                task: task,
                                scheduledStartTime: startTime,
                                scheduledEndTime: endTime
                            )
                            scheduledTasks.append(scheduledTask)
                            continue
                        }
                    }
                }
                // Se deadline è futuro, continua con la logica normale
            }

            // Trova slot disponibile
            while currentTimeIndex < workingHours.count {
                let currentSlot = workingHours[currentTimeIndex]
                let slotEnd = currentSlot.end

                if currentSlotStart.addingTimeInterval(task.estimatedDuration) <= slotEnd {
                    let scheduledTask = ScheduledTask(
                        task: task,
                        scheduledStartTime: currentSlotStart,
                        scheduledEndTime: currentSlotStart.addingTimeInterval(task.estimatedDuration)
                    )
                    scheduledTasks.append(scheduledTask)
                    currentSlotStart = scheduledTask.scheduledEndTime
                    break
                } else {
                    currentTimeIndex += 1
                    if currentTimeIndex < workingHours.count {
                        currentSlotStart = workingHours[currentTimeIndex].start
                    } else {
                        break
                    }
                }
            }
        }

        return scheduledTasks
    }

    /// Riorganizza tutte le task quando cambiano gli orari lavorativi.
    /// - Parameter userInitiated: se true (es. tasto Aggiorna in Dashboard), bypassa il cooldown di 30s
    func reorganizeAllTasksBasedOnSchedule(userInitiated: Bool = false) {
        guard !isReorganizing else { return }
        
        let now = Date()
        if !userInitiated, let lastTime = lastReorganizationTime,
           now.timeIntervalSince(lastTime) < schedulingCooldownInterval {
            return
        }
        
        // Verifica che taskManager sia accessibile (protezione contro deallocazione)
        // Cattura una copia locale delle task per evitare accessi concorrenti
        let tasks = taskManager.tasks
        
        isReorganizing = true
        lastReorganizationTime = now
        defer {
            isReorganizing = false
        }
        
        let calendar = Calendar.current
        let today = Date()

        // Helper per combinare la data target con l'ora degli orari lavorativi
        func combineDateTime(date: Date, time: Date) -> Date {
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            dateComponents.second = timeComponents.second ?? 0
            return calendar.date(from: dateComponents) ?? date
        }

        // Riorganizza per oggi e i prossimi 7 giorni
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let rawWorkingHours = workScheduleManager.getWorkingHours(for: date).sorted { $0.start < $1.start }
            guard !rawWorkingHours.isEmpty else { continue }

            // Converti gli orari lavorativi alla data corretta
            let workingHours = rawWorkingHours.map { hours -> (start: Date, end: Date) in
                (start: combineDateTime(date: date, time: hours.start),
                 end: combineDateTime(date: date, time: hours.end))
            }

            // Prima passata: assicura che tutte le task base senza scheduledDate vengano schedulate
            if dayOffset == 0 {
                for index in tasks.indices where tasks[index].status == .pending && !tasks[index].isIgnored {
                    let task = tasks[index]
                    if task.metadata["baseTask"]?.value as? Bool == true && task.scheduledDate == nil {
                        let (scheduledDate, scheduledTime) = scheduleTaskAutomatically(task: task)
                        taskManager.updateTaskSchedule(taskID: task.id, scheduledDate: scheduledDate, scheduledTime: scheduledTime)
                    }
                }
            }
            
            // Riorganizza tutte le task di questo giorno (pending, non ignorate)
            // Usa la copia locale per evitare accessi concorrenti
            let dayTasks = tasks.enumerated().compactMap { pair -> (Int, DailyTask)? in
                let task = pair.element
                guard task.status == .pending, !task.isIgnored else { return nil }
                
                // Escludi task scadute da più di 7 giorni
                if task.hasExpired, let deadline = task.deadline {
                    let daysSinceExpiry = calendar.dateComponents([.day], from: deadline, to: Date()).day ?? 0
                    if daysSinceExpiry > 7 {
                        return nil
                    }
                }

                // Include task di questo giorno o senza data (per oggi)
                if let scheduled = task.scheduledDate {
                    return calendar.isDate(scheduled, inSameDayAs: date) ? (pair.offset, task) : nil
                } else {
                    // Task senza data: assegna a oggi se è oggi, altrimenti salta
                    return dayOffset == 0 ? (pair.offset, task) : nil
                }
            }

            // Separa task in categorie per scheduling prioritario
            // 1. Task con orario FISSO (fixedDateTime) - slot riservato ESATTO
            // 2. Task con DEADLINE flessibile - da schedulare PRIMA della deadline con buffer
            // 3. Task flessibili (resto)
            let (fixedTimeTasks, deadlineTasks, flexibleTasks) = dayTasks.reduce(into: 
                ([(Int, DailyTask)](), [(Int, DailyTask)](), [(Int, DailyTask)]())
            ) { result, pair in
                let task = pair.1
                // Task con orario FISSO (ESATTO, non spostabile)
                if task.hasFixedDateTime || (task.isTimeSensitive && task.fixedDateTime != nil) {
                    result.0.append(pair)
                }
                // Task con DEADLINE flessibile (schedulabile prima con buffer)
                else if task.deadline != nil && task.fixedDateTime == nil {
                    result.1.append(pair)
                }
                // Task flessibili (senza vincoli temporali)
                else {
                    result.2.append(pair)
                }
            }
            
            // Separa task flessibili in 4 sottocategorie: manuali, bloccanti, essenziali, opzionali
            let (manualTasks, blockingTasks, essentialTasks, optionalTasks) = flexibleTasks.reduce(into:
                ([(Int, DailyTask)](), [(Int, DailyTask)](), [(Int, DailyTask)](), [(Int, DailyTask)]())
            ) { result, pair in
                let task = pair.1
                // Task manuali (create dall'utente)
                if task.type == .manual {
                    result.0.append(pair)
                }
                // Task bloccanti (es. polizza mancante)
                else if task.isBlocking {
                    result.1.append(pair)
                }
                // Task opzionali (bassa priorità)
                else if task.priorityLevel == .optional {
                    result.3.append(pair)
                }
                // Task essenziali (priorità normale)
                else {
                    result.2.append(pair)
                }
            }

            // Ordina task con orario FISSO per orario (ESATTE, non spostabili)
            let sortedFixedTasks = fixedTimeTasks.sorted { lhs, rhs in
                let t1 = lhs.1.fixedDateTime ?? lhs.1.scheduledTime ?? lhs.1.createdAt
                let t2 = rhs.1.fixedDateTime ?? rhs.1.scheduledTime ?? rhs.1.createdAt
                return t1 < t2
            }
            
            // Ordina task con DEADLINE e applica moltiplicatore urgenza
            let sortedDeadlineTasks = deadlineTasks.map { pair -> (Int, DailyTask, Double) in
                let urgency = calculateUrgencyMultiplier(deadline: pair.1.deadline!, now: now)
                return (pair.0, pair.1, urgency)
            }.sorted { lhs, rhs in
                // Ordina per urgenza * priorità (le più urgenti prima)
                (lhs.2 * lhs.1.priority) > (rhs.2 * rhs.1.priority)
            }
            
            // Ordina task manuali (rispetta priorità utente)
            let sortedManualTasks = manualTasks.sorted { lhs, rhs in
                // Priorità utente
                if lhs.1.priority != rhs.1.priority {
                    return lhs.1.priority > rhs.1.priority
                }
                return lhs.1.createdAt < rhs.1.createdAt
            }
            
            // Ordina task bloccanti (massima urgenza)
            let sortedBlockingTasks = blockingTasks.sorted { lhs, rhs in
                if lhs.1.priority != rhs.1.priority {
                    return lhs.1.priority > rhs.1.priority
                }
                return lhs.1.createdAt < rhs.1.createdAt
            }
            
            // Ordina task essenziali
            let sortedEssentialTasks = essentialTasks.sorted { lhs, rhs in
                if lhs.1.isExpired != rhs.1.isExpired {
                    return lhs.1.isExpired
                }
                if lhs.1.priority != rhs.1.priority {
                    return lhs.1.priority > rhs.1.priority
                }
                let t1 = lhs.1.scheduledTime ?? lhs.1.createdAt
                let t2 = rhs.1.scheduledTime ?? rhs.1.createdAt
                return t1 < t2
            }
            
            // Ordina task opzionali (bassa priorità)
            let sortedOptionalTasks = optionalTasks.sorted { lhs, rhs in
                if lhs.1.priority != rhs.1.priority {
                    return lhs.1.priority > rhs.1.priority
                }
                let t1 = lhs.1.scheduledTime ?? lhs.1.createdAt
                let t2 = rhs.1.scheduledTime ?? rhs.1.createdAt
                return t1 < t2
            }

            // Riorganizza le task con la nuova logica di scheduling usando durate reali
            var cursor = workingHours.first?.start ?? date
            var totalWorkTime: TimeInterval = 0
            let breakInterval: TimeInterval = 2 * 3600 // 2 ore
            let breakDuration: TimeInterval = 20 * 60 // 20 minuti
            var slotIndex = 0

            func advanceSlotIfNeeded() {
                while slotIndex < workingHours.count && cursor >= workingHours[slotIndex].end {
                    slotIndex += 1
                    if slotIndex < workingHours.count {
                        // Interruzione tra slot: spazio vuoto proporzionale
                        cursor = workingHours[slotIndex].start
                        totalWorkTime = 0 // Reset tra slot separati (interruzioni)
                    }
                }
            }

            advanceSlotIfNeeded()

            // PRIMA: Posiziona task con data/ora fissa (videoperizie, riunioni, etc.)
            var fixedTimeBlocks: [(start: Date, end: Date)] = []
            for (idx, task) in sortedFixedTasks {
                if let fixedTime = task.fixedDateTime {
                    let fixedDate = calendar.startOfDay(for: fixedTime)
                    // Solo se è dello stesso giorno
                    if calendar.isDate(fixedDate, inSameDayAs: date) {
                        let start = fixedTime
                        let end = start.addingTimeInterval(task.estimatedDuration)

                        // Verifica che la task esista ancora prima di aggiornarla
                        if tasks.contains(where: { $0.id == task.id }) {
                            taskManager.updateTaskSchedule(
                                taskID: task.id,
                                scheduledDate: fixedDate,
                                scheduledTime: start
                            )
                        }

                        fixedTimeBlocks.append((start: start, end: end))
                    }
                } else if task.isTimeSensitive, let scheduledTime = task.scheduledTime {
                    // Task time-sensitive già schedulata
                    let start = scheduledTime
                    let end = start.addingTimeInterval(task.estimatedDuration)
                    fixedTimeBlocks.append((start: start, end: end))
                }
            }

            // Ordina i blocchi fissi per orario
            fixedTimeBlocks.sort { $0.start < $1.start }

            // SECONDA: Riorganizza task flessibili compattandole per riempire tutti gli slot disponibili
            // Crea una lista di tutti i blocchi occupati (fissi + già schedulati)
            var occupiedBlocks = fixedTimeBlocks.sorted { $0.start < $1.start }
            
            // Funzione helper per trovare il primo slot disponibile per una task
            func findFirstAvailableSlot(for task: DailyTask) -> Date? {
                let duration = task.estimatedDuration
                
                // Se ha deadline, cerca prima intorno al deadline
                if let deadline = task.deadline {
                    let deadlineDay = calendar.startOfDay(for: deadline)
                    let taskDay = calendar.startOfDay(for: date)
                    
                    if calendar.isDate(deadlineDay, inSameDayAs: taskDay) {
                        // Cerca slot che contiene il deadline
                        for slot in workingHours {
                            if deadline >= slot.start && deadline <= slot.end {
                                let preferredStart = max(slot.start, deadline.addingTimeInterval(-duration))
                                let preferredEnd = preferredStart.addingTimeInterval(duration)
                                if preferredEnd <= slot.end {
                                    // Verifica che non si sovrapponga a blocchi occupati
                                    var canFit = true
                                    for block in occupiedBlocks {
                                        if preferredStart < block.end && preferredEnd > block.start {
                                            canFit = false
                                            break
                                        }
                                    }
                                    if canFit {
                                        return preferredStart
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Cerca il primo slot disponibile in ordine cronologico
                // Itera attraverso tutti gli slot lavorativi
                for slot in workingHours {
                    var candidateStart = slot.start
                    let slotEnd = slot.end
                    
                    // Calcola il tempo di lavoro totale già fatto in questo slot
                    var totalWorkInSlot: TimeInterval = 0
                    for block in occupiedBlocks {
                        if block.start >= slot.start && block.end <= slot.end {
                            totalWorkInSlot += block.end.timeIntervalSince(block.start)
                        } else if block.start < slot.end && block.end > slot.start {
                            // Blocco parzialmente sovrapposto
                            let overlapStart = max(block.start, slot.start)
                            let overlapEnd = min(block.end, slot.end)
                            totalWorkInSlot += overlapEnd.timeIntervalSince(overlapStart)
                        }
                    }
                    
                    // Cerca il primo punto disponibile nello slot
                    while candidateStart.addingTimeInterval(duration) <= slotEnd {
                        let candidateEnd = candidateStart.addingTimeInterval(duration)
                        
                        // Verifica sovrapposizioni con blocchi occupati
                        var overlaps = false
                        var nextStart = candidateStart
                        for block in occupiedBlocks {
                            if candidateStart < block.end && candidateEnd > block.start {
                                overlaps = true
                                nextStart = block.end
                                break
                            }
                        }
                        
                        if overlaps {
                            candidateStart = nextStart
                            continue
                        }
                        
                        // Calcola pause necessarie basate sul tempo di lavoro fino a questo punto
                        let workTimeAtPoint = candidateStart.timeIntervalSince(slot.start)
                        let breaksNeeded = Int(workTimeAtPoint / breakInterval)
                        let pauseTime = TimeInterval(breaksNeeded) * breakDuration
                        let adjustedStart = slot.start.addingTimeInterval(pauseTime)
                        
                        if candidateStart >= adjustedStart && candidateEnd <= slotEnd {
                            // Verifica vincoli temporali se presenti
                            if let constraints = task.timeConstraints {
                                if let constrainedStart = findStartTimeWithConstraints(
                                    for: task,
                                    on: date,
                                    workingHours: workingHours,
                                    fixedBlocks: occupiedBlocks,
                                    cursor: candidateStart,
                                    slotIndex: workingHours.firstIndex(where: { $0.start == slot.start }) ?? 0
                                ) {
                                    return constrainedStart
                                }
                            } else {
                                return candidateStart
                            }
                        }
                        
                        // Avanza di 5 minuti per cercare il prossimo punto disponibile
                        candidateStart = candidateStart.addingTimeInterval(5 * 60)
                    }
                }
                
                return nil
            }
            
            // ORDINE DI SCHEDULING:
            // 1B. Task con DEADLINE (prima della deadline con buffer 15 min, urgenza crescente)
            for (idx, task, urgency) in sortedDeadlineTasks {
                // Cerca slot PRIMA della deadline (con buffer 15 minuti)
                if let deadline = task.deadline {
                    let deadlineWithBuffer = deadline.addingTimeInterval(-15 * 60)
                    if let start = findSlotBeforeTime(for: task, before: deadlineWithBuffer, occupiedBlocks: occupiedBlocks) {
                        let taskEnd = start.addingTimeInterval(task.estimatedDuration)
                        occupiedBlocks.append((start: start, end: taskEnd))
                        occupiedBlocks.sort { $0.start < $1.start }
                        
                        if tasks.contains(where: { $0.id == task.id }) {
                            taskManager.updateTaskSchedule(
                                taskID: task.id,
                                scheduledDate: date,
                                scheduledTime: start
                            )
                        }
                    }
                }
            }
            
            // 2. Task manuali (create dall'utente - alta priorità)
            for (idx, task) in sortedManualTasks {
                if let start = findFirstAvailableSlot(for: task) {
                    let taskEnd = start.addingTimeInterval(task.estimatedDuration)
                    occupiedBlocks.append((start: start, end: taskEnd))
                    occupiedBlocks.sort { $0.start < $1.start }
                    
                    if tasks.contains(where: { $0.id == task.id }) {
                        taskManager.updateTaskSchedule(
                            taskID: task.id,
                            scheduledDate: date,
                            scheduledTime: start
                        )
                    }
                }
            }
            
            // 3. Task bloccanti (es. polizza mancante - URGENTE!)
            for (idx, task) in sortedBlockingTasks {
                if let start = findFirstAvailableSlot(for: task) {
                    let taskEnd = start.addingTimeInterval(task.estimatedDuration)
                    occupiedBlocks.append((start: start, end: taskEnd))
                    occupiedBlocks.sort { $0.start < $1.start }
                    
                    if tasks.contains(where: { $0.id == task.id }) {
                        taskManager.updateTaskSchedule(
                            taskID: task.id,
                            scheduledDate: date,
                            scheduledTime: start
                        )
                    }
                }
            }
            
            // 4. Task essenziali automatiche
            for (idx, task) in sortedEssentialTasks {
                if let start = findFirstAvailableSlot(for: task) {
                    let taskEnd = start.addingTimeInterval(task.estimatedDuration)
                    occupiedBlocks.append((start: start, end: taskEnd))
                    occupiedBlocks.sort { $0.start < $1.start }
                    
                    if tasks.contains(where: { $0.id == task.id }) {
                        taskManager.updateTaskSchedule(
                            taskID: task.id,
                            scheduledDate: date,
                            scheduledTime: start
                        )
                    }
                }
            }
            
            // 5. Task opzionali (solo se c'è spazio rimasto)
            for (idx, task) in sortedOptionalTasks {
                if let start = findFirstAvailableSlot(for: task) {
                    let taskEnd = start.addingTimeInterval(task.estimatedDuration)
                    occupiedBlocks.append((start: start, end: taskEnd))
                    occupiedBlocks.sort { $0.start < $1.start }
                    
                    if tasks.contains(where: { $0.id == task.id }) {
                        taskManager.updateTaskSchedule(
                            taskID: task.id,
                            scheduledDate: date,
                            scheduledTime: start
                        )
                    }
                } else {
                    // Nessuno slot disponibile per task opzionale - OK, viene saltata
                    print("[ScheduleManager] 🔵 Task opzionale non schedulata (nessuno spazio): \(task.title)")
                }
            }
        }

        taskManager.saveTasks()
        taskManager.updateCounter += 1
    }
    
    // MARK: - Scheduling Helpers
    
    /// Calcola moltiplicatore urgenza basato su vicinanza alla deadline
    /// Usato per task con deadline flessibile (non fixedDateTime)
    private func calculateUrgencyMultiplier(deadline: Date, now: Date) -> Double {
        let timeRemaining = deadline.timeIntervalSince(now)
        let hoursRemaining = timeRemaining / 3600
        
        if hoursRemaining <= 0 {
            return 3.0  // Scaduta: priorità massima
        } else if hoursRemaining <= 1 {
            return 2.0  // Entro 1 ora: priorità x2
        } else if hoursRemaining <= 3 {
            return 1.5  // Entro 3 ore: priorità x1.5
        } else if hoursRemaining <= 8 {
            return 1.2  // Entro 8 ore: priorità x1.2
        } else {
            return 1.0  // Oltre 8 ore: priorità normale
        }
    }
    
    /// Trova slot disponibile PRIMA di un certo orario (per deadline con buffer)
    private func findSlotBeforeTime(
        for task: DailyTask,
        before targetTime: Date,
        occupiedBlocks: [(start: Date, end: Date)]
    ) -> Date? {
        let calendar = Calendar.current
        let taskDate = task.scheduledDate ?? Date()
        let workingHours = workScheduleManager.getWorkingHours(for: taskDate)
        
        for hours in workingHours {
            let slotStart = calendar.startOfDay(for: taskDate) == calendar.startOfDay(for: hours.start)
                ? hours.start
                : combineDateTime(date: taskDate, time: hours.start)
            let slotEnd = min(hours.end, targetTime) // Non oltre il target time
            
            var candidateStart = slotStart
            
            // Cerca slot disponibile PRIMA del target time
            while candidateStart.addingTimeInterval(task.estimatedDuration) <= slotEnd {
                let candidateEnd = candidateStart.addingTimeInterval(task.estimatedDuration)
                
                // Verifica se lo slot è libero
                let isOccupied = occupiedBlocks.contains { block in
                    (candidateStart >= block.start && candidateStart < block.end) ||
                    (candidateEnd > block.start && candidateEnd <= block.end) ||
                    (candidateStart <= block.start && candidateEnd >= block.end)
                }
                
                if !isOccupied {
                    return candidateStart
                }
                
                // Avanza di 5 minuti
                candidateStart = candidateStart.addingTimeInterval(5 * 60)
            }
        }
        
        return nil // Nessuno slot disponibile prima del target time
    }
    
    /// Helper per combinare data e ora
    private func combineDateTime(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        dateComponents.second = timeComponents.second ?? 0
        return calendar.date(from: dateComponents) ?? date
    }

    /// Sposta un task alla prima giornata lavorativa successiva
    func rescheduleTaskToNextWorkingDay(taskID: UUID) {
        guard let index = taskManager.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let calendar = Calendar.current
        let today = Date()
        let task = taskManager.tasks[index]

        // Trova prossimo giorno lavorativo
        var nextDate = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        for _ in 0..<14 {
            if workScheduleManager.isWorkingDay(nextDate) {
                let workingHours = workScheduleManager.getWorkingHours(for: nextDate).sorted { $0.start < $1.start }
                if let firstSlot = workingHours.first {
                    // Combina la data corretta con l'ora dell'orario lavorativo
                    let timeComponents = calendar.dateComponents([.hour, .minute], from: firstSlot.start)
                    var dateComponents = calendar.dateComponents([.year, .month, .day], from: nextDate)
                    dateComponents.hour = timeComponents.hour
                    dateComponents.minute = timeComponents.minute
                    let scheduledTime = calendar.date(from: dateComponents) ?? nextDate

                    taskManager.updateTaskSchedule(
                        taskID: taskID,
                        scheduledDate: calendar.startOfDay(for: nextDate),
                        scheduledTime: scheduledTime
                    )
                    taskManager.tasks[index].isIgnored = false
                    taskManager.saveTasks()
                    taskManager.updateCounter += 1
                    return
                }
            }
            nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? nextDate
        }
    }
    
    /// Sposta task più tardi nella stessa giornata (decide automaticamente nel range 30m-2h)
    func rescheduleTaskLater(taskID: UUID) {
        guard let index = taskManager.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard let scheduledTime = taskManager.tasks[index].scheduledTime,
              let scheduledDate = taskManager.tasks[index].scheduledDate else { return }
        
        let calendar = Calendar.current
        let rawWorkingHours = workScheduleManager.getWorkingHours(for: scheduledDate).sorted { $0.start < $1.start }
        
        // Helper per combinare data e ora
        func combineDateTime(targetDate: Date, time: Date) -> Date {
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            dateComponents.second = timeComponents.second ?? 0
            return calendar.date(from: dateComponents) ?? targetDate
        }
        
        let workingHours = rawWorkingHours.map { hours -> (start: Date, end: Date) in
            (start: combineDateTime(targetDate: scheduledDate, time: hours.start),
             end: combineDateTime(targetDate: scheduledDate, time: hours.end))
        }
        
        let taskDuration = taskManager.tasks[index].estimatedDuration
        let minDelay: TimeInterval = 30 * 60 // 30 minuti minimo
        let maxDelay: TimeInterval = 2 * 3600 // 2 ore massimo
        
        // Prova a trovare uno slot disponibile nel range 30m-2h
        // Prova prima con 30m, poi 1h, poi 2h, o il primo slot disponibile nel range
        let delayOptions: [TimeInterval] = [30 * 60, 60 * 60, 2 * 3600]
        
        for delay in delayOptions {
            let newTime = scheduledTime.addingTimeInterval(delay)
            let taskEnd = newTime.addingTimeInterval(taskDuration)
            
            // Verifica che ci sia spazio negli orari lavorativi
            for slot in workingHours {
                if newTime >= slot.start && taskEnd <= slot.end && newTime >= scheduledTime.addingTimeInterval(minDelay) && newTime <= scheduledTime.addingTimeInterval(maxDelay) {
                    taskManager.updateTaskSchedule(
                        taskID: taskID,
                        scheduledDate: scheduledDate,
                        scheduledTime: newTime
                    )
                    taskManager.saveTasks()
                    taskManager.updateCounter += 1
                    reorganizeAllTasksBasedOnSchedule(userInitiated: true)
                    return
                }
            }
        }
        
        // Se non trova uno slot con i delay prefissati, cerca il primo slot disponibile nel range
        for slot in workingHours {
            if slot.start > scheduledTime {
                let candidateTime = max(slot.start, scheduledTime.addingTimeInterval(minDelay))
                let taskEnd = candidateTime.addingTimeInterval(taskDuration)
                
                if taskEnd <= slot.end && candidateTime <= scheduledTime.addingTimeInterval(maxDelay) {
                    taskManager.updateTaskSchedule(
                        taskID: taskID,
                        scheduledDate: scheduledDate,
                        scheduledTime: candidateTime
                    )
                    taskManager.saveTasks()
                    taskManager.updateCounter += 1
                    reorganizeAllTasksBasedOnSchedule(userInitiated: true)
                    return
                }
            }
        }
    }
    
    /// Sposta task al pomeriggio se è al mattino
    func rescheduleTaskToAfternoon(taskID: UUID) {
        guard let index = taskManager.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard let scheduledTime = taskManager.tasks[index].scheduledTime,
              let scheduledDate = taskManager.tasks[index].scheduledDate else { return }
        
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: scheduledTime)
        let now = Date()
        
        // Se è già pomeriggio, non fare nulla
        guard hour < 14 else { return }
        
        let rawWorkingHours = workScheduleManager.getWorkingHours(for: scheduledDate).sorted { $0.start < $1.start }
        
        // Helper per combinare data e ora
        func combineDateTime(targetDate: Date, time: Date) -> Date {
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            dateComponents.second = timeComponents.second ?? 0
            return calendar.date(from: dateComponents) ?? targetDate
        }
        
        let workingHours = rawWorkingHours.map { hours -> (start: Date, end: Date) in
            (start: combineDateTime(targetDate: scheduledDate, time: hours.start),
             end: combineDateTime(targetDate: scheduledDate, time: hours.end))
        }
        
        let taskDuration = taskManager.tasks[index].estimatedDuration
        
        // Trova slot pomeridiano disponibile
        for slot in workingHours {
            let slotHour = calendar.component(.hour, from: slot.start)
            if slotHour >= 14 {
                // Verifica che non sia già passato
                if slot.end <= now { continue }
                
                let taskEnd = slot.start.addingTimeInterval(taskDuration)
                if taskEnd <= slot.end {
                    taskManager.updateTaskSchedule(
                        taskID: taskID,
                        scheduledDate: scheduledDate,
                        scheduledTime: slot.start
                    )
                    taskManager.saveTasks()
                    taskManager.updateCounter += 1
                    reorganizeAllTasksBasedOnSchedule(userInitiated: true)
                    return
                }
            }
        }
    }
    
    /// Sposta task al mattino del giorno dopo
    func rescheduleTaskToNextMorning(taskID: UUID) {
        guard let index = taskManager.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard let scheduledDate = taskManager.tasks[index].scheduledDate else { return }
        
        let calendar = Calendar.current
        var nextDate = calendar.date(byAdding: .day, value: 1, to: scheduledDate) ?? scheduledDate
        
        // Helper per combinare data e ora
        func combineDateTime(targetDate: Date, time: Date) -> Date {
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            dateComponents.second = timeComponents.second ?? 0
            return calendar.date(from: dateComponents) ?? targetDate
        }
        
        // Trova prossimo giorno lavorativo
        for _ in 0..<7 {
            if workScheduleManager.isWorkingDay(nextDate) {
                let rawWorkingHours = workScheduleManager.getWorkingHours(for: nextDate).sorted { $0.start < $1.start }
                let workingHours = rawWorkingHours.map { hours -> (start: Date, end: Date) in
                    (start: combineDateTime(targetDate: nextDate, time: hours.start),
                     end: combineDateTime(targetDate: nextDate, time: hours.end))
                }
                let taskDuration = taskManager.tasks[index].estimatedDuration
                
                // Trova slot mattutino (prima delle 14)
                for slot in workingHours {
                    let slotHour = calendar.component(.hour, from: slot.start)
                    if slotHour < 14 {
                        let taskEnd = slot.start.addingTimeInterval(taskDuration)
                        if taskEnd <= slot.end {
                            taskManager.updateTaskSchedule(
                                taskID: taskID,
                                scheduledDate: calendar.startOfDay(for: nextDate),
                                scheduledTime: slot.start
                            )
                            taskManager.saveTasks()
                            taskManager.updateCounter += 1
                            reorganizeAllTasksBasedOnSchedule(userInitiated: true)
                            return
                        }
                    }
                }
            }
            nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? nextDate
        }
    }

    /// Riprogramma task non completate
    func rescheduleIncompleteTasks() {
        let calendar = Calendar.current
        let today = Date()

        for index in taskManager.tasks.indices where taskManager.tasks[index].status == .pending && !taskManager.tasks[index].isIgnored {
            let task = taskManager.tasks[index]

            // Se task è scaduta o non ha scheduledDate, riprogramma
            if task.hasExpired || task.scheduledDate == nil || (task.scheduledDate! < today && task.status != .completed) {
                // Trova prossimo giorno lavorativo
                var nextDate = today
                for _ in 0..<7 {
                    nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? nextDate
                    if workScheduleManager.isWorkingDay(nextDate) {
                        taskManager.updateTaskSchedule(
                            taskID: task.id,
                            scheduledDate: nextDate,
                            scheduledTime: nil
                        )
                        if task.hasExpired {
                            taskManager.tasks[index].priority = min(1.0, task.priority * 2.0)
                        }
                        break
                    }
                }
            }
        }

        taskManager.saveTasks()
        taskManager.updateCounter += 1
    }

    /// Ribilancia un giorno dopo il completamento di una task: accorcia la durata, compatta le successive e anticipa task future se c'è spazio.
    func rebalanceDayAfterCompletion(for date: Date) {
        let calendar = Calendar.current
        let rawWorkingHours = workScheduleManager.getWorkingHours(for: date).sorted { $0.start < $1.start }
        guard !rawWorkingHours.isEmpty else { return }

        // Helper per combinare data e ora
        func combineDateTime(targetDate: Date, time: Date) -> Date {
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            dateComponents.second = timeComponents.second ?? 0
            return calendar.date(from: dateComponents) ?? targetDate
        }

        // Converti gli orari lavorativi alla data corretta
        let workingHours = rawWorkingHours.map { hours -> (start: Date, end: Date) in
            (start: combineDateTime(targetDate: date, time: hours.start),
             end: combineDateTime(targetDate: date, time: hours.end))
        }

        // Task del giorno in ordine di orario previsto
        var dayTasks = taskManager.tasks.enumerated().compactMap { pair -> (Int, DailyTask)? in
            guard let scheduledDate = pair.element.scheduledDate,
                  calendar.isDate(scheduledDate, inSameDayAs: date),
                  !pair.element.isIgnored else { return nil }
            return (pair.offset, pair.element)
        }.sorted { lhs, rhs in
            let t1 = lhs.1.scheduledTime ?? lhs.1.createdAt
            let t2 = rhs.1.scheduledTime ?? rhs.1.createdAt
            return t1 < t2
        }

        var slotIndex = 0
        var cursor = workingHours.first?.start ?? date
        var totalWorkTime: TimeInterval = 0
        let breakInterval: TimeInterval = 2 * 3600 // 2 ore
        let breakDuration: TimeInterval = 20 * 60 // 20 minuti

        func advanceSlotIfNeeded() {
            while slotIndex < workingHours.count && cursor >= workingHours[slotIndex].end {
                slotIndex += 1
                if slotIndex < workingHours.count {
                    // Calcola automaticamente l'interruzione tra slot
                    // Se c'è un gap, il cursor va all'inizio del prossimo slot
                    // Lo spazio vuoto è proporzionale alla durata dell'interruzione
                    cursor = max(cursor, workingHours[slotIndex].start)
                    totalWorkTime = 0 // Reset tra slot separati (interruzioni)
                }
            }
        }

        advanceSlotIfNeeded()

        // Compatta le task del giorno usando durate reali
        for (idx, task) in dayTasks {
            advanceSlotIfNeeded()
            guard slotIndex < workingHours.count else { break }

            // Usa durata reale: se completata usa actualDuration, altrimenti estimatedDuration
            let duration: TimeInterval = {
                if task.status == .completed {
                    return task.actualDuration ?? task.estimatedDuration
                }
                return task.estimatedDuration
            }()

            // Posizione di partenza
            var start = max(cursor, workingHours[slotIndex].start)

            // Aggiungi pause se necessario (ogni 2 ore di lavoro)
            if totalWorkTime >= breakInterval {
                let breaks = Int(totalWorkTime / breakInterval)
                let pauseTime = TimeInterval(breaks) * breakDuration
                start = start.addingTimeInterval(pauseTime)
                totalWorkTime = totalWorkTime.truncatingRemainder(dividingBy: breakInterval)

                // Se la pausa va oltre lo slot, passa al prossimo
                if start >= workingHours[slotIndex].end {
                    slotIndex += 1
                    advanceSlotIfNeeded()
                    guard slotIndex < workingHours.count else { break }
                    start = workingHours[slotIndex].start
                    totalWorkTime = 0 // Reset tra slot
                }
            }

            // Verifica se la task ci entra con la sua durata reale
            let taskEnd = start.addingTimeInterval(duration)

            // Se non ci entra, passa al prossimo slot
            if taskEnd > workingHours[slotIndex].end {
                slotIndex += 1
                advanceSlotIfNeeded()
                guard slotIndex < workingHours.count else { break }
                start = workingHours[slotIndex].start
                totalWorkTime = 0 // Reset tra slot separati
            }

            taskManager.updateTaskSchedule(
                taskID: task.id,
                scheduledDate: date,
                scheduledTime: start
            )

            // Aggiorna cursor con durata reale
            cursor = start.addingTimeInterval(duration)
            totalWorkTime += duration

            // Se il cursor va oltre lo slot, passa al prossimo
            if cursor >= workingHours[slotIndex].end {
                slotIndex += 1
                advanceSlotIfNeeded()
                if slotIndex < workingHours.count {
                    cursor = workingHours[slotIndex].start
                    totalWorkTime = 0 // Reset tra slot
                }
            }
        }

        advanceSlotIfNeeded()

        // Se resta spazio nel giorno, prova ad anticipare task future (pending, non ignorate)
        if slotIndex < workingHours.count {
            let remainingSlotEnd = workingHours[slotIndex].end
            var availableCursor = cursor

            var futureTasks = taskManager.tasks.enumerated().compactMap { pair -> (Int, DailyTask)? in
                guard let scheduledDate = pair.element.scheduledDate,
                      scheduledDate > date,
                      pair.element.status == .pending,
                      !pair.element.isIgnored else { return nil }
                return (pair.offset, pair.element)
            }.sorted { lhs, rhs in
                let d1 = lhs.1.scheduledDate ?? Date.distantFuture
                let d2 = rhs.1.scheduledDate ?? Date.distantFuture
                if d1 == d2 {
                    let t1 = lhs.1.scheduledTime ?? lhs.1.createdAt
                    let t2 = rhs.1.scheduledTime ?? rhs.1.createdAt
                    return t1 < t2
                }
                return d1 < d2
            }

            var futureWorkTime = totalWorkTime
            for (idx, task) in futureTasks {
                let duration = task.estimatedDuration

                // Aggiungi pause se necessario
                var taskStart = availableCursor
                if futureWorkTime >= breakInterval {
                    let breaks = Int(futureWorkTime / breakInterval)
                    taskStart = taskStart.addingTimeInterval(TimeInterval(breaks) * breakDuration)
                    futureWorkTime = futureWorkTime.truncatingRemainder(dividingBy: breakInterval)
                }

                // Verifica se ci entra con la durata reale
                if taskStart.addingTimeInterval(duration) <= remainingSlotEnd {
                    taskManager.updateTaskSchedule(
                        taskID: task.id,
                        scheduledDate: date,
                        scheduledTime: taskStart
                    )
                    availableCursor = taskStart.addingTimeInterval(duration)
                    futureWorkTime += duration
                } else {
                    break
                }
            }
        }

        taskManager.saveTasks()
        taskManager.updateCounter += 1
    }

    /// Trova un orario di inizio rispettando i vincoli temporali
    private func findStartTimeWithConstraints(
        for task: DailyTask,
        on date: Date,
        workingHours: [(start: Date, end: Date)],
        fixedBlocks: [(start: Date, end: Date)],
        cursor: Date,
        slotIndex: Int
    ) -> Date? {
        guard let constraints = task.timeConstraints else { return nil }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)

        // Verifica giorno della settimana
        if let allowedWeekdays = constraints.allowedWeekdays, !allowedWeekdays.contains(weekday) {
            return nil // Questo giorno non è consentito
        }

        // Cerca un orario valido
        var candidateStart = max(cursor, workingHours[slotIndex].start)

        // Verifica periodi del giorno
        if let periods = constraints.allowedPeriods {
            let hour = calendar.component(.hour, from: candidateStart)
            var isValidPeriod = false

            for period in periods {
                switch period {
                case .morning:
                    if hour >= 9 && hour < 12 {
                        isValidPeriod = true
                    }
                case .afternoon:
                    if hour >= 14 && hour < 18 {
                        isValidPeriod = true
                    }
                case .specific:
                    if let specificTimes = constraints.specificTimes {
                        for specificTime in specificTimes {
                            if hour == specificTime.hour && calendar.component(.minute, from: candidateStart) == specificTime.minute {
                                isValidPeriod = true
                                break
                            }
                        }
                    }
                }
                if isValidPeriod { break }
            }

            if !isValidPeriod {
                // Trova il prossimo periodo valido
                for period in periods {
                    switch period {
                    case .morning:
                        if hour < 9 {
                            candidateStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? candidateStart
                            isValidPeriod = true
                        } else if hour >= 12 {
                            // Passa al pomeriggio se disponibile
                            if periods.contains(.afternoon) {
                                candidateStart = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: date) ?? candidateStart
                                isValidPeriod = true
                            }
                        }
                    case .afternoon:
                        if hour < 14 {
                            candidateStart = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: date) ?? candidateStart
                            isValidPeriod = true
                        }
                    case .specific:
                        if let specificTimes = constraints.specificTimes, let firstTime = specificTimes.first {
                            candidateStart = calendar.date(bySettingHour: firstTime.hour, minute: firstTime.minute, second: 0, of: date) ?? candidateStart
                            isValidPeriod = true
                        }
                    }
                    if isValidPeriod { break }
                }
            }
        }

        // Verifica orario limite (entro le X)
        if let deadlineTime = constraints.deadlineTime {
            let deadlineDate = calendar.date(bySettingHour: deadlineTime.hour, minute: deadlineTime.minute, second: 0, of: date) ?? date
            if candidateStart > deadlineDate {
                return nil // Non può essere completata entro l'orario limite
            }
        }

        // Verifica che non si sovrapponga ai blocchi fissi
        let taskEnd = candidateStart.addingTimeInterval(task.estimatedDuration)
        for fixedBlock in fixedBlocks {
            if candidateStart < fixedBlock.end && taskEnd > fixedBlock.start {
                // Si sovrappone, sposta dopo
                candidateStart = fixedBlock.end
            }
        }

        return candidateStart
    }

    /// Trova il prossimo slot disponibile rispettando gli orari lavorativi, durate reali, pause e interruzioni
    private func nextAvailableSlot(on date: Date, duration: TimeInterval) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        
        // Se la data è nel passato, usa oggi
        let targetDate = date < now ? now : date
        let dayStart = calendar.startOfDay(for: targetDate)

        let rawWorkingHours = workScheduleManager.getWorkingHours(for: targetDate).sorted { $0.start < $1.start }
        guard !rawWorkingHours.isEmpty else { return nil }

        // Helper per combinare data e ora
        func combineDateTime(targetDate: Date, time: Date) -> Date {
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            dateComponents.second = timeComponents.second ?? 0
            return calendar.date(from: dateComponents) ?? targetDate
        }

        // Converti gli orari lavorativi alla data corretta
        let workingHours = rawWorkingHours.map { hours -> (start: Date, end: Date) in
            (start: combineDateTime(targetDate: targetDate, time: hours.start),
             end: combineDateTime(targetDate: targetDate, time: hours.end))
        }

        // Task già programmati in quel giorno (solo pending/non ignorati)
        let sameDayTasks = taskManager.tasks
            .filter { $0.status == .pending && !$0.isIgnored && $0.scheduledDate.map { calendar.isDate($0, inSameDayAs: targetDate) } == true && $0.scheduledTime != nil }
            .sorted { ($0.scheduledTime ?? dayStart) < ($1.scheduledTime ?? dayStart) }

        // Calcola il tempo di lavoro accumulato e le pause necessarie
        // Assicura che il cursor non sia nel passato
        var cursor = max(workingHours.first?.start ?? targetDate, now)
        var totalWorkTime: TimeInterval = 0
        let breakInterval: TimeInterval = 2 * 3600 // 2 ore
        let breakDuration: TimeInterval = 20 * 60 // 20 minuti

        // Simula la programmazione esistente per calcolare pause e posizione
        for (slotIndex, slot) in workingHours.enumerated() {
            // Se il cursor è prima dello slot, spostalo all'inizio dello slot
            if cursor < slot.start {
                cursor = slot.start
                totalWorkTime = 0 // Reset tra slot separati (interruzioni)
            }

            // Se il cursor è dopo la fine dello slot, passa al prossimo
            if cursor >= slot.end {
                continue
            }

            // Processa task esistenti in questo slot
            for task in sameDayTasks {
                guard let start = task.scheduledTime else { continue }
                let taskEnd = start.addingTimeInterval(task.estimatedDuration)

                // Se il task è fuori dallo slot corrente, salta
                if taskEnd <= slot.start || start >= slot.end {
                    continue
                }

                // Se il task inizia dopo il cursor, verifica se c'è spazio prima
                if start > cursor {
                    // Calcola spazio disponibile considerando pause
                    var testCursor = cursor
                    var testWorkTime = totalWorkTime
                    var canFit = true

                    // Simula l'inserimento della nuova task con pause
                    while testCursor < start && canFit {
                        let remainingInSlot = min(start, slot.end).timeIntervalSince(testCursor)
                        let timeNeeded = duration

                        // Verifica se serve una pausa prima
                        if testWorkTime >= breakInterval {
                            let breaksNeeded = Int(testWorkTime / breakInterval)
                            testCursor = testCursor.addingTimeInterval(TimeInterval(breaksNeeded) * breakDuration)
                            testWorkTime = testWorkTime.truncatingRemainder(dividingBy: breakInterval)

                            // Se la pausa va oltre lo slot, non c'è spazio
                            if testCursor >= slot.end {
                                canFit = false
                                break
                            }
                        }

                        // Verifica se c'è spazio per la task
                        if testCursor.addingTimeInterval(timeNeeded) <= min(start, slot.end) {
                            // C'è spazio! Assicura che non sia nel passato
                            let finalCursor = max(cursor, now)
                            return finalCursor >= now ? finalCursor : nil
                        } else {
                            // Non c'è spazio, sposta il cursor dopo questo task
                            canFit = false
                        }
                    }
                }

                // Aggiorna cursor e tempo di lavoro
                cursor = max(cursor, taskEnd)
                totalWorkTime += task.estimatedDuration

                // Aggiungi pause ogni 2 ore
                if totalWorkTime >= breakInterval {
                    let breaks = Int(totalWorkTime / breakInterval)
                    totalWorkTime = totalWorkTime.truncatingRemainder(dividingBy: breakInterval)
                    cursor = cursor.addingTimeInterval(TimeInterval(breaks) * breakDuration)
                }

                // Se il cursor è dopo la fine dello slot, passa al prossimo
                if cursor >= slot.end {
                    break
                }
            }

            // Verifica se c'è spazio alla fine dello slot
            if cursor < slot.end {
                // Calcola spazio disponibile considerando pause
                var testCursor = cursor
                var testWorkTime = totalWorkTime
                var canFit = true

                while testCursor < slot.end && canFit {
                    let remainingInSlot = slot.end.timeIntervalSince(testCursor)
                    let timeNeeded = duration

                    // Verifica se serve una pausa prima
                    if testWorkTime >= breakInterval {
                        let breaksNeeded = Int(testWorkTime / breakInterval)
                        testCursor = testCursor.addingTimeInterval(TimeInterval(breaksNeeded) * breakDuration)
                        testWorkTime = testWorkTime.truncatingRemainder(dividingBy: breakInterval)

                        // Se la pausa va oltre lo slot, non c'è spazio
                        if testCursor >= slot.end {
                            canFit = false
                            break
                        }
                    }

                    // Verifica se c'è spazio per la task
                    if testCursor.addingTimeInterval(timeNeeded) <= slot.end {
                        // C'è spazio! Assicura che non sia nel passato
                        let finalCursor = max(cursor, now)
                        return finalCursor >= now ? finalCursor : nil
                    } else {
                        canFit = false
                    }
                }
            }

            // Se c'è un gap tra slot (interruzione), il cursor va all'inizio del prossimo slot
            // Le interruzioni vengono calcolate automaticamente in base agli slot configurati
            if slotIndex < workingHours.count - 1 {
                let nextSlot = workingHours[slotIndex + 1]
                if nextSlot.start > slot.end {
                    // C'è un'interruzione tra slot (calcolata automaticamente)
                    // Lo spazio vuoto è proporzionale alla durata dell'interruzione
                    cursor = nextSlot.start
                    totalWorkTime = 0 // Reset tempo di lavoro tra slot separati
                }
            }
        }

        return nil
    }

    /// Schedula automaticamente un task in base alla priorità/scadenza e orari lavorativi
    func scheduleTaskAutomatically(task: DailyTask) -> (Date, Date) {
        let calendar = Calendar.current
        let today = Date()
        let now = Date()

        // Base date scelta su scadenza/urgenza
        let baseDate: Date = {
            guard let deadline = task.deadline else {
                return today
            }
            let deadlineDay = calendar.startOfDay(for: deadline)
            let todayDay = calendar.startOfDay(for: today)
            if deadlineDay >= todayDay {
                let daysBefore = task.priority > 0.7 ? 0 : max(1, min(2, calendar.dateComponents([.day], from: todayDay, to: deadlineDay).day ?? 1))
                let calculatedDate = calendar.date(byAdding: .day, value: -daysBefore, to: deadlineDay) ?? today
                // Assicura che non sia nel passato
                return max(calculatedDate, today)
            }
            return today
        }()

        var candidateDate = max(baseDate, today)

        // Cerca il primo giorno lavorativo con slot disponibile (fino a 30 giorni avanti)
        for _ in 0..<30 {
            // Assicura che candidateDate non sia nel passato
            if candidateDate < today {
                candidateDate = today
            }
            
            if !workScheduleManager.isWorkingDay(candidateDate) {
                candidateDate = calendar.date(byAdding: .day, value: 1, to: candidateDate) ?? candidateDate
                continue
            }

            if let start = nextAvailableSlot(on: candidateDate, duration: task.estimatedDuration) {
                // Controllo finale: non permettere date nel passato
                if start >= now {
                    return (calendar.startOfDay(for: candidateDate), start)
                }
            }

            candidateDate = calendar.date(byAdding: .day, value: 1, to: candidateDate) ?? candidateDate
        }

        // Fallback: oggi o domani all'inizio giornata lavorativa
        let fallbackDate = today
        let rawWorkingHours = workScheduleManager.getWorkingHours(for: fallbackDate)
        let fallbackStart: Date
        if let firstSlot = rawWorkingHours.first {
            // Combina la data corretta con l'ora dell'orario lavorativo
            let timeComponents = calendar.dateComponents([.hour, .minute], from: firstSlot.start)
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: fallbackDate)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            let calculatedStart = calendar.date(from: dateComponents) ?? fallbackDate
            // Assicura che non sia nel passato
            fallbackStart = max(calculatedStart, now)
        } else {
            // Se non ci sono orari, usa domani alle 9:00
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: fallbackDate) ?? fallbackDate
            var components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
            components.hour = 9
            components.minute = 0
            fallbackStart = calendar.date(from: components) ?? tomorrow
        }
        
        let finalDate = calendar.startOfDay(for: fallbackStart >= now ? fallbackDate : calendar.date(byAdding: .day, value: 1, to: fallbackDate) ?? fallbackDate)
        return (finalDate, fallbackStart)
    }
    
    // MARK: - Daily Scheduler
    
    /// Configura lo scheduler giornaliero per eseguire le task giornaliere
    func setupDailyScheduler() {
        let calendar = Calendar.current
        let now = Date()
        
        // Trova il prossimo giorno lavorativo
        var candidateDate = now
        var scheduledDate: Date?
        var attempts = 0
        let maxAttempts = 30
        
        while scheduledDate == nil && attempts < maxAttempts {
            if workScheduleManager.isWorkingDay(candidateDate) {
                let workHours = workScheduleManager.getWorkingHours(for: candidateDate)
                guard let firstWorkHour = workHours.first else {
                    candidateDate = calendar.date(byAdding: .day, value: 1, to: candidateDate) ?? candidateDate
                    attempts += 1
                    continue
                }
                
                // Combina la data corretta con l'ora dell'orario lavorativo
                let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: firstWorkHour.start)
                var dateComponents = calendar.dateComponents([.year, .month, .day], from: candidateDate)
                dateComponents.hour = timeComponents.hour
                dateComponents.minute = timeComponents.minute
                dateComponents.second = timeComponents.second ?? 0
                
                guard let firstWorkHourStart = calendar.date(from: dateComponents) else {
                    candidateDate = calendar.date(byAdding: .day, value: 1, to: candidateDate) ?? candidateDate
                    attempts += 1
                    continue
                }
                
                // 15 minuti prima dell'inizio dell'orario lavorativo
                let targetTime = firstWorkHourStart.addingTimeInterval(-15 * 60)
                
                // Controlla che non sia nel passato
                if targetTime > now {
                    scheduledDate = targetTime
                } else {
                    // Se è passato, prova il giorno successivo
                    candidateDate = calendar.date(byAdding: .day, value: 1, to: candidateDate) ?? candidateDate
                    attempts += 1
                }
            } else {
                candidateDate = calendar.date(byAdding: .day, value: 1, to: candidateDate) ?? candidateDate
                attempts += 1
            }
        }
        
        // Fallback: se non trovato, usa domani alle 9:00
        guard let finalScheduledDate = scheduledDate else {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            var components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
            components.hour = 9
            components.minute = 0
            components.second = 0
            scheduledDate = calendar.date(from: components) ?? tomorrow
            return
        }
        
        let timeInterval = finalScheduledDate.timeIntervalSince(now)
        
        // Controllo finale: non permettere date nel passato
        guard timeInterval > 0 else {
            #if DEBUG
            print("[ScheduleManager] ⚠️ Tentativo di schedulare nel passato ignorato")
            #endif
            return
        }
        
        dailySchedulerTimer?.invalidate()
        dailySchedulerTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.runDailyTasks()
                self?.setupDailyScheduler()
            }
        }
        
        #if DEBUG
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        print("[ScheduleManager] ⏰ Daily scheduler configurato per: \(formatter.string(from: finalScheduledDate)) (tra \(Int(timeInterval/60)) minuti)")
        #endif
    }
    
    func runDailyTasks() async {
        let now = Date()
        let defaults = UserDefaults.standard
        
        // Controlla se è già stato eseguito oggi
        if let lastRunString = defaults.string(forKey: lastDailyRunKey),
           let lastRun = ISO8601DateFormatter().date(from: lastRunString),
           Calendar.current.isDate(lastRun, inSameDayAs: now) {
            return
        }
        
        #if DEBUG
        print("[ScheduleManager] 🌅 Esecuzione task giornaliere alle \(now)...")
        #endif
        
        // Pulisci task soppressi più vecchi di 60 giorni
        taskManager.cleanupOldSuppressedTasks()
        
        await taskManager.validateAndCleanupExistingTasks()
        await taskManager.regenerateBaseTasks()
        taskManager.rescheduleIncompleteTasks()
        
        defaults.set(ISO8601DateFormatter().string(from: now), forKey: lastDailyRunKey)
        
        #if DEBUG
        print("[ScheduleManager] ✅ Task giornaliere completate")
        #endif
    }
}
