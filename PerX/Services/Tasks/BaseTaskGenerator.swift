import Foundation
import CoreData

/// Generatore di task di base per ogni sinistro basato sullo stato
/// Genera automaticamente task essenziali e opzionali in base allo stato del sinistro
@MainActor
class BaseTaskGenerator {
    static let shared = BaseTaskGenerator()
    
    private let taskManager = TaskManager.shared
    private let workScheduleManager = WorkScheduleManager.shared
    private let priorityCalculator = PriorityCalculator.shared
    private let validator = OptionalTaskValidator.shared
    private let cpuThrottler = CPUThrottler.shared
    
    private init() {}
    
    // MARK: - Main Generation Methods
    
    /// Genera task di base per tutti i sinistri attivi dell'utente loggato
    /// Chiamato giornalmente all'orario dinamico (inizio lavoro - 15 min) o all'avvio app
    func generateDailyBaseTasks() async {
        print("[BaseTaskGenerator] 🔄 Generazione task di base giornaliera...")
        
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        
        // Filtra sinistri non chiusi/revocati/annullati
        let excludedStates = [
            StatoManager.StatoSinistro.chiusa.descrizione,
            StatoManager.StatoSinistro.revocata.descrizione,
            StatoManager.StatoSinistro.annullata.descrizione
        ]
        
        // IMPORTANTE: Filtra SOLO sinistri dell'utente loggato
        let currentUserEmail = GoogleAuthService.shared.userEmail?.lowercased()
        
        var predicates: [NSPredicate] = [
            NSPredicate(format: "NOT (stato IN %@)", excludedStates)
        ]
        
        if let userEmail = currentUserEmail {
            // Sinistri assegnati all'utente corrente
            predicates.append(
                NSPredicate(format: "assignedToUserEmail ==[c] %@ OR ownerEmail ==[c] %@", userEmail, userEmail)
            )
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        guard let allSinistri = try? context.fetch(request) else { return }
        
        print("[BaseTaskGenerator] 📊 Trovati \(allSinistri.count) sinistri dell'utente")
        
        let monthlyGoal = workScheduleManager.getMonthlyTarget(for: Date())
        let currentMonthClosures = await getCurrentMonthClosuresCount()
        let needsAcceleration = await shouldAccelerateClosures()
        
        // FASE 1: Genera SOLO task essenziali (priorità alta)
        var essentialTasksCreated = 0
        let batchSize = 5 // Batch piccoli per ridurre carico CPU
        
        for batch in allSinistri.chunked(into: batchSize) {
            // Throttle CPU prima di ogni batch
            await cpuThrottler.throttleIfNeeded()
            
            for sinistro in batch {
                let tasks = await generateEssentialTasksOnly(
                    sinistro,
                    monthlyGoal: monthlyGoal,
                    currentClosures: currentMonthClosures,
                    needsAcceleration: needsAcceleration
                )
                essentialTasksCreated += tasks.count
            }
            
            // Pausa tra batch (riduce carico CPU al 30%)
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        }
        
        print("[BaseTaskGenerator] ✅ Generate \(essentialTasksCreated) task essenziali")
        
        // FASE 2: Genera task opzionali SOLO se task essenziali completate
        var optionalTasksCreated = 0
        
        for batch in allSinistri.chunked(into: batchSize) {
            // Throttle CPU prima di ogni batch
            await cpuThrottler.throttleIfNeeded()
            
            for sinistro in batch {
                let tasks = await generateOptionalTasksOnly(
                    sinistro,
                    monthlyGoal: monthlyGoal,
                    currentClosures: currentMonthClosures,
                    needsAcceleration: needsAcceleration
                )
                optionalTasksCreated += tasks.count
            }
            
            // Pausa tra batch
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        }
        
        print("[BaseTaskGenerator] ✅ Generate \(optionalTasksCreated) task opzionali")
        print("[BaseTaskGenerator] 🎯 Totale: \(essentialTasksCreated + optionalTasksCreated) task")
    }
    
    /// Verifica e aggiorna task esistenti, poi genera nuove se necessarie
    /// Chiamato dal tasto "Aggiorna" o da eventi che cambiano lo stato del sinistro
    func updateOrCreateBaseTasksForSinistro(sinistroID: String) async {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
        
        guard let sinistro = try? context.fetch(request).first,
              let riferimento = sinistro.riferimento else { return }
        
        let existingTasks = taskManager.getBaseTasks(for: riferimento)
        let currentState = StatoManager.shared.getCurrentState(sinistro: sinistro)
        
        // 1️⃣ Invalida task non più pertinenti per lo stato attuale
        for task in existingTasks where task.status == .pending {
            if !isTaskStillValidForState(task, state: currentState) {
                taskManager.validateAndInvalidateTasks(
                    for: riferimento,
                    newState: currentState,
                    eventType: "stateEvolution"
                )
            }
        }
        
        // 2️⃣ Aggiorna priorità task esistenti ancora valide (in base ai giorni passati)
        let monthlyGoal = workScheduleManager.getMonthlyTarget(for: Date())
        let currentClosures = await getCurrentMonthClosuresCount()
        let needsAcceleration = await shouldAccelerateClosures()
        
        for task in existingTasks where task.status == .pending {
            let newPriority = priorityCalculator.calculateDynamicPriority(
                for: sinistro,
                monthlyGoal: monthlyGoal,
                currentClosures: currentClosures,
                needsAcceleration: needsAcceleration
            )
            
            if abs(task.priority - newPriority) > 0.05 { // Solo se cambio significativo
                taskManager.updateTaskPriority(taskID: task.id, priority: newPriority)
            }
        }
        
        // 3️⃣ Crea nuove task di base se mancanti
        _ = await generateBaseTasksForSinistro(
            sinistro,
            monthlyGoal: monthlyGoal,
            currentClosures: currentClosures,
            needsAcceleration: needsAcceleration
        )
    }
    
    // MARK: - Task Generation Logic
    
    /// Genera SOLO task essenziali per un sinistro
    private func generateEssentialTasksOnly(
        _ sinistro: Sinistro,
        monthlyGoal: Int,
        currentClosures: Int,
        needsAcceleration: Bool
    ) async -> [DailyTask] {
        let allTasks = await generateBaseTasksForSinistro(
            sinistro,
            monthlyGoal: monthlyGoal,
            currentClosures: currentClosures,
            needsAcceleration: needsAcceleration
        )
        
        // Filtra solo essenziali (blocking)
        return allTasks.filter { $0.priorityLevel == .essential }
    }
    
    /// Genera SOLO task opzionali per un sinistro
    private func generateOptionalTasksOnly(
        _ sinistro: Sinistro,
        monthlyGoal: Int,
        currentClosures: Int,
        needsAcceleration: Bool
    ) async -> [DailyTask] {
        let allTasks = await generateBaseTasksForSinistro(
            sinistro,
            monthlyGoal: monthlyGoal,
            currentClosures: currentClosures,
            needsAcceleration: needsAcceleration
        )
        
        // Filtra solo opzionali
        return allTasks.filter { $0.priorityLevel == .optional }
    }
    
    /// Genera task di base per un singolo sinistro (crea solo quelle mancanti)
    private func generateBaseTasksForSinistro(
        _ sinistro: Sinistro,
        monthlyGoal: Int,
        currentClosures: Int,
        needsAcceleration: Bool
    ) async -> [DailyTask] {
        guard let riferimento = sinistro.riferimento,
              let statoDesc = sinistro.stato else { return [] }
        
        let statoEnum = StatoManager.StatoSinistro.allCases.first { $0.descrizione == statoDesc }
        guard let stato = statoEnum else { return [] }
        
        var tasks: [DailyTask] = []
        let now = Date()
        
        // Calcola priorità dinamica
        let priority = priorityCalculator.calculateDynamicPriority(
            for: sinistro,
            monthlyGoal: monthlyGoal,
            currentClosures: currentClosures,
            needsAcceleration: needsAcceleration
        )
        
        // Task basate sullo stato
        switch stato {
        case .inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia:
            // "Sollecitare documentazione"
            if canCreateTask(for: riferimento, type: "documentazione"),
               !hasExistingTaskWithSameTitle(sinistroID: riferimento, title: "Sollecitare documentazione") {
                tasks.append(createDocumentationTask(sinistro: sinistro, priority: priority))
            }
            
        case .inGestione, .inGestioneDocumentale:
            // "Eseguire perizia"
            if canCreateTask(for: riferimento, type: "perizia") {
                tasks.append(createPeriziaTask(sinistro: sinistro, priority: priority))
            }
            
        case .attoDaInviare, .esitoDaComunicare, .esitoComunicato:
            // "Inviare atto"
            if canCreateTask(for: riferimento, type: "invio_atto") {
                tasks.append(createSendActTask(sinistro: sinistro, priority: priority))
            }
            
            // "Tentare concordato verbale" (se condizioni soddisfatte)
            if await shouldAttemptVerbalAgreement(sinistro: sinistro, monthlyGoal: monthlyGoal, currentClosures: currentClosures) {
                if canCreateTask(for: riferimento, type: "concordato_verbale") {
                    tasks.append(createVerbalAgreementTask(sinistro: sinistro, priority: priority + 0.2))
                }
            }
            
        case .attoInviato:
            // Usa campi consolidati sul modello per solleciti inviati
            let sentReminderCount = Int(sinistro.sollecitiInviatiCount)
            let lastSentReminderDate = sinistro.dataUltimoSollecitoInviato
            
            // Dopo 3 solleciti inviati: proponi "Chiudere non concordato" invece di sollecitare
            if sinistro.hasSuperatoLimiteSollecitiInviati {
                if canCreateTask(for: riferimento, type: "chiusura_non_concordato"),
                   !hasExistingTaskWithSameTitle(sinistroID: riferimento, title: "Chiudere non concordato") {
                    tasks.append(createCloseNonAgreedTask(sinistro: sinistro, priority: priority + 0.3))
                }
            } else {
                // "Sollecitare atto inviato" (se >= 4 gg lavorativi dall'ultimo sollecito O prima volta)
                if let dataInvioAtto = sinistro.dataInvioAtto {
                    let workingDaysFromAct = workScheduleManager.countWorkingDays(from: dataInvioAtto, to: now)
                    
                    // Calcola giorni lavorativi dall'ultimo sollecito inviato (se esiste)
                    let workingDaysFromLastReminder: Int
                    if let lastReminder = lastSentReminderDate {
                        workingDaysFromLastReminder = workScheduleManager.countWorkingDays(from: lastReminder, to: now)
                    } else {
                        workingDaysFromLastReminder = Int.max // Mai sollecitato
                    }
                    
                    // Mostra task solo se:
                    // - Sono passati almeno 2 gg lavorativi dall'invio atto (primo sollecito)
                    // - E sono passati almeno 4 gg lavorativi dall'ultimo sollecito inviato (solleciti successivi)
                    let canRemindFirstTime = workingDaysFromAct >= 2 && sentReminderCount == 0
                    let canRemindAgain = sentReminderCount > 0 && workingDaysFromLastReminder >= 4
                    
                    if (canRemindFirstTime || canRemindAgain),
                       canCreateTask(for: riferimento, type: "sollecito_atto"),
                       !hasExistingTaskWithSameTitle(sinistroID: riferimento, title: "Sollecitare atto inviato"),
                       !hasExistingTaskWithSameTitle(sinistroID: riferimento, title: "Sollecito atto inviato"),
                       !hasExistingTaskWithSameTitle(sinistroID: riferimento, title: "Sollecita atto") {
                        tasks.append(createRemindActTask(sinistro: sinistro, priority: priority + 0.1))
                    }
                }
            }
            
            // "Tentare concordato verbale" (se condizioni soddisfatte)
            if await shouldAttemptVerbalAgreement(sinistro: sinistro, monthlyGoal: monthlyGoal, currentClosures: currentClosures) {
                if canCreateTask(for: riferimento, type: "concordato_verbale") {
                    tasks.append(createVerbalAgreementTask(sinistro: sinistro, priority: priority + 0.2))
                }
            }
            
        case .richiestaAutorizzazione, .supervisioneNonConcordata, .inControllo:
            // "Sollecitare controllo" (se >10 giorni lavorativi O <5 giorni da fine mese)
            if await shouldRemindControl(sinistro: sinistro) {
                if canCreateTask(for: riferimento, type: "sollecito_controllo") {
                    tasks.append(createRemindControlTask(sinistro: sinistro, priority: priority + 0.15))
                }
            }
            
        case .attoRicevutoSottoscritto, .accettataVerbalmente:
            // "Chiudere"
            if canCreateTask(for: riferimento, type: "chiusura") {
                tasks.append(createClosureTask(sinistro: sinistro, priority: priority + 0.3))
            }
            
        default:
            break
        }
        
        // TASK OPZIONALI E BLOCCANTI
        
        // Polizza (ESSENZIALE - BLOCCANTE se manca)
        // Verifica per stati operativi PRIMA dell'invio atto.
        // Se siamo in attoRicevutoSottoscritto/accettataVerbalmente, la polizza l'avevamo già sicuramente
        // (altrimenti non avremmo potuto inviare l'atto).
        let statiPostAtto: Set<StatoManager.StatoSinistro> = [
            .attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa, .revocata, .annullata
        ]
        if !statiPostAtto.contains(stato) {
            if validator.needsPolizza(sinistro: sinistro) {
                if canCreateTask(for: riferimento, type: "polizza") {
                    // Priorità ALTA: bloccante per gestione
                    tasks.append(createPolizzaTask(sinistro: sinistro, priority: min(priority + 0.3, 1.0)))
                }
            }
        }
        
        // Foto ubicazione (OPZIONALE - per sinistri in gestione)
        if [.inGestione, .inGestioneDocumentale, .periziaDaEseguire].contains(stato) {
            if validator.needsFotoUbicazione(sinistro: sinistro) {
                if canCreateTask(for: riferimento, type: "foto_ubicazione") {
                    tasks.append(createFotoUbicazioneTask(sinistro: sinistro, priority: priority * 0.5))
                }
            }
        }
        
        // Preventivo (OPZIONALE - solo per danneggiato non assicurato)
        if validator.needsPreventivo(sinistro: sinistro) {
            if canCreateTask(for: riferimento, type: "preventivo") {
                tasks.append(createPreventivoTask(sinistro: sinistro, priority: priority * 0.5))
            }
        }
        
        // IBAN (OPZIONALE - per sinistri prossimi alla chiusura)
        // Richiesto solo negli stati pre-ritorno atto. Una volta che l'atto è tornato firmato,
        // l'IBAN lo abbiamo già sicuramente (è nel documento firmato).
        if [.attoDaInviare, .esitoDaComunicare, .attoInviato, .esitoComunicato].contains(stato) {
            if validator.needsIBAN(sinistro: sinistro) {
                if canCreateTask(for: riferimento, type: "iban") {
                    tasks.append(createIBANTask(sinistro: sinistro, priority: priority * 0.5))
                }
            }
        }
        
        // Aggiungi task al TaskManager
        for task in tasks {
            taskManager.addTask(task)
        }
        
        return tasks
    }
    
    // MARK: - Task Creation Methods (Essenziali)
    
    private func createDocumentationTask(sinistro: Sinistro, priority: Double) -> DailyTask {
        DailyTask(
            title: "Sollecitare documentazione",
            description: "Richiedere documentazione mancante",
            type: .sinistroActivity,
            sinistroID: sinistro.riferimento,
            priority: priority,
            estimatedDuration: 5 * 60, // 5 minuti
            metadata: [
                "baseTask": AnyCodable(true),
                "baseTaskType": AnyCodable("documentazione")
            ],
            actionType: .remind,
            goal: TaskGoal(
                type: .receiveDocumentation,
                targetValue: sinistro.riferimento
            ),
            invalidationRules: TaskInvalidation(
                conditions: [.sinistroClosedOrRevoked, .documentationReceived, .stateProgressed],
                stateThreshold: .inGestione
            )
        )
    }
    
    private func createPeriziaTask(sinistro: Sinistro, priority: Double) -> DailyTask {
        DailyTask(
            title: "Eseguire perizia",
            description: "Completare perizia per il sinistro",
            type: .sinistroActivity,
            sinistroID: sinistro.riferimento,
            priority: priority,
            estimatedDuration: 30 * 60, // 30 minuti
            metadata: [
                "baseTask": AnyCodable(true),
                "baseTaskType": AnyCodable("perizia")
            ],
            actionType: .verify,
            invalidationRules: TaskInvalidation(
                conditions: [.sinistroClosedOrRevoked, .stateProgressed],
                stateThreshold: .attoDaInviare
            )
        )
    }
    
    private func createSendActTask(sinistro: Sinistro, priority: Double) -> DailyTask {
        DailyTask(
            title: "Inviare atto",
            description: "Predisporre e inviare atto",
            type: .sinistroActivity,
            sinistroID: sinistro.riferimento,
            priority: priority,
            estimatedDuration: 15 * 60, // 15 minuti
            metadata: [
                "baseTask": AnyCodable(true),
                "baseTaskType": AnyCodable("invio_atto")
            ],
            actionType: .send,
            goal: TaskGoal(
                type: .sendActEmail,
                targetValue: sinistro.riferimento
            ),
            invalidationRules: TaskInvalidation(
                conditions: [.sinistroClosedOrRevoked, .stateProgressed],
                stateThreshold: .attoInviato
            )
        )
    }
    
    private func createRemindActTask(sinistro: Sinistro, priority: Double) -> DailyTask {
        DailyTask(
            title: "Sollecitare atto inviato",
            description: "Sollecitare restituzione atto firmato",
            type: .sinistroActivity,
            sinistroID: sinistro.riferimento,
            priority: priority,
            estimatedDuration: 5 * 60, // 5 minuti
            metadata: [
                "baseTask": AnyCodable(true),
                "baseTaskType": AnyCodable("sollecito_atto")
            ],
            actionType: .remind,
            goal: TaskGoal(
                type: .receiveActSigned,
                targetValue: sinistro.riferimento
            ),
            invalidationRules: TaskInvalidation(
                conditions: [.sinistroClosedOrRevoked, .actReceived],
                stateThreshold: nil
            )
        )
    }
    
    /// Task per chiusura non concordato (dopo 3 solleciti senza risposta)
    private func createCloseNonAgreedTask(sinistro: Sinistro, priority: Double) -> DailyTask {
        DailyTask(
            title: "Chiudere non concordato",
            description: "Dopo 3 solleciti senza risposta, procedere con chiusura non concordata",
            type: .sinistroActivity,
            sinistroID: sinistro.riferimento,
            priority: priority,
            estimatedDuration: 15 * 60, // 15 minuti
            metadata: [
                "baseTask": AnyCodable(true),
                "baseTaskType": AnyCodable("chiusura_non_concordato")
            ],
            actionType: .close,
            goal: TaskGoal(
                type: .changeState,
                targetValue: StatoManager.StatoSinistro.chiusa.descrizione
            ),
            invalidationRules: TaskInvalidation(
                conditions: [.sinistroClosedOrRevoked, .actReceived],
                stateThreshold: nil
            )
        )
    }
    
    private func createRemindControlTask(sinistro: Sinistro, priority: Double) -> DailyTask {
        DailyTask(
            title: "Sollecitare controllo",
            description: "Sollecitare autorizzazione/controllo",
            type: .sinistroActivity,
            sinistroID: sinistro.riferimento,
            priority: priority,
            estimatedDuration: 5 * 60, // 5 minuti
            metadata: [
                "baseTask": AnyCodable(true),
                "baseTaskType": AnyCodable("sollecito_controllo")
            ],
            actionType: .remind,
            invalidationRules: TaskInvalidation(
                conditions: [.sinistroClosedOrRevoked, .stateProgressed],
                stateThreshold: .attoRicevutoSottoscritto
            )
        )
    }
    
    private func createVerbalAgreementTask(sinistro: Sinistro, priority: Double) -> DailyTask {
        DailyTask(
            title: "Tentare concordato verbale",
            description: "Contattare per concordato verbale (importo basso, fine mese)",
            type: .sinistroActivity,
            sinistroID: sinistro.riferimento,
            priority: priority,
            estimatedDuration: 10 * 60, // 10 minuti
            metadata: [
                "baseTask": AnyCodable(true),
                "baseTaskType": AnyCodable("concordato_verbale")
            ],
            phoneNumber: sinistro.telefonoAssicurato,
            actionType: .call,
            goal: TaskGoal(
                type: .changeState,
                targetValue: StatoManager.StatoSinistro.accettataVerbalmente.descrizione
            ),
            invalidationRules: TaskInvalidation(
                conditions: [.sinistroClosedOrRevoked, .stateProgressed],
                stateThreshold: .attoRicevutoSottoscritto
            )
        )
    }
    
    private func createClosureTask(sinistro: Sinistro, priority: Double) -> DailyTask {
        DailyTask(
            title: "Chiudere",
            description: "Completare chiusura sinistro",
            type: .sinistroActivity,
            sinistroID: sinistro.riferimento,
            priority: priority,
            estimatedDuration: 15 * 60, // 15 minuti
            metadata: [
                "baseTask": AnyCodable(true),
                "baseTaskType": AnyCodable("chiusura")
            ],
            actionType: .close,
            goal: TaskGoal(
                type: .changeState,
                targetValue: StatoManager.StatoSinistro.chiusa.descrizione
            )
        )
    }
    
    // MARK: - Task Opzionali Creation
    
    private func createFotoUbicazioneTask(sinistro: Sinistro, priority: Double) -> DailyTask {
        DailyTask(
            title: "Richiedere foto ubicazione",
            description: "Richiedere almeno 2 foto ubicazione del rischio",
            type: .sinistroActivity,
            sinistroID: sinistro.riferimento,
            priority: priority,
            estimatedDuration: 3 * 60, // 3 minuti
            metadata: [
                "baseTask": AnyCodable(true),
                "baseTaskType": AnyCodable("foto_ubicazione")
            ],
            actionType: .request,
            invalidationRules: TaskInvalidation(
                conditions: [.sinistroClosedOrRevoked, .stateProgressed],
                stateThreshold: .attoDaInviare
            ),
            priorityLevel: .optional
        )
    }
    
    private func createPolizzaTask(sinistro: Sinistro, priority: Double) -> DailyTask {
        DailyTask(
            title: "Richiedere polizza",
            description: "⚠️ URGENTE: Richiedere copia polizza assicurativa (bloccante per gestione)",
            type: .sinistroActivity,
            sinistroID: sinistro.riferimento,
            priority: priority,
            estimatedDuration: 5 * 60, // 5 minuti
            metadata: [
                "baseTask": AnyCodable(true),
                "baseTaskType": AnyCodable("polizza"),
                "isBlocking": AnyCodable(true) // Marca come bloccante
            ],
            actionType: .request,
            goal: TaskGoal(
                type: .receiveDocumentation,
                targetValue: "polizza"
            ),
            invalidationRules: TaskInvalidation(
                conditions: [.sinistroClosedOrRevoked, .policyReceived, .stateProgressed],
                stateThreshold: .attoRicevutoSottoscritto // Se atto ricevuto, polizza già avuta
            ),
            priorityLevel: .essential // ESSENZIALE (non opzionale!)
        )
    }
    
    private func createPreventivoTask(sinistro: Sinistro, priority: Double) -> DailyTask {
        DailyTask(
            title: "Richiedere preventivo",
            description: "Richiedere preventivo per danneggiato non assicurato",
            type: .sinistroActivity,
            sinistroID: sinistro.riferimento,
            priority: priority,
            estimatedDuration: 3 * 60,
            metadata: [
                "baseTask": AnyCodable(true),
                "baseTaskType": AnyCodable("preventivo")
            ],
            actionType: .request,
            invalidationRules: TaskInvalidation(
                conditions: [.sinistroClosedOrRevoked, .stateProgressed],
                stateThreshold: .attoDaInviare
            ),
            priorityLevel: .optional
        )
    }
    
    private func createIBANTask(sinistro: Sinistro, priority: Double) -> DailyTask {
        DailyTask(
            title: "Richiedere IBAN",
            description: "Richiedere coordinate bancarie per liquidazione",
            type: .sinistroActivity,
            sinistroID: sinistro.riferimento,
            priority: priority,
            estimatedDuration: 3 * 60,
            metadata: [
                "baseTask": AnyCodable(true),
                "baseTaskType": AnyCodable("iban")
            ],
            actionType: .request,
            invalidationRules: TaskInvalidation(
                conditions: [.sinistroClosedOrRevoked, .stateProgressed, .actReceived],
                stateThreshold: .attoRicevutoSottoscritto // IBAN già presente nell'atto firmato
            ),
            priorityLevel: .optional
        )
    }
    
    // MARK: - Validation & Helpers
    
    /// Verifica se una task è ancora valida per lo stato attuale del sinistro
    private func isTaskStillValidForState(_ task: DailyTask, state: StatoManager.StatoSinistro) -> Bool {
        guard let taskType = task.metadata["baseTaskType"]?.value as? String else {
            return true // Task non di base, mantieni
        }
        
        // Stati post-atto: polizza e IBAN non più necessari (già ottenuti)
        let statiPostAtto: Set<StatoManager.StatoSinistro> = [
            .attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa, .revocata, .annullata
        ]
        
        switch taskType {
        case "documentazione":
            return [.inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia].contains(state)
        case "perizia":
            return [.inGestione, .inGestioneDocumentale].contains(state)
        case "invio_atto":
            return [.attoDaInviare, .esitoDaComunicare, .esitoComunicato].contains(state)
        case "sollecito_atto":
            return state == .attoInviato
        case "sollecito_controllo":
            return [.richiestaAutorizzazione, .supervisioneNonConcordata, .inControllo].contains(state)
        case "chiusura":
            return [.attoRicevutoSottoscritto, .accettataVerbalmente].contains(state)
        case "polizza":
            // Polizza non serve più dopo che l'atto è stato ricevuto firmato
            return !statiPostAtto.contains(state)
        case "iban":
            // IBAN non serve più dopo che l'atto è stato ricevuto firmato (è nell'atto)
            return !statiPostAtto.contains(state)
        default:
            return true
        }
    }
    
    private func hasExistingBaseTask(for sinistroID: String, type: String) -> Bool {
        return taskManager.tasks.contains { task in
            guard task.sinistroID == sinistroID, task.status == .pending, !task.isIgnored else { return false }
            return task.metadata["baseTaskType"]?.value as? String == type
        }
    }
    
    /// Verifica se il task è stato soppresso dall'utente (cancellato/ignorato)
    private func isTaskSuppressed(for sinistroID: String, type: String) -> Bool {
        return taskManager.isTaskSuppressed(sinistroID: sinistroID, baseTaskType: type)
    }
    
    /// Verifica se un task può essere creato (non esiste già E non è soppresso)
    private func canCreateTask(for sinistroID: String, type: String) -> Bool {
        // Se esiste già un task pending, non crearlo
        if hasExistingBaseTask(for: sinistroID, type: type) {
            return false
        }
        
        // Se l'utente ha soppresso questo tipo di task, non rigenerarlo
        if isTaskSuppressed(for: sinistroID, type: type) {
            print("[BaseTaskGenerator] ⏭️ Task \(type) per \(sinistroID) soppresso dall'utente, skip")
            return false
        }
        
        return true
    }
    
    /// True se esiste già una pending con stesso titolo+sinistro (es. da ClaimEngine/manuale). Evita add→duplicata ignorata.
    private func hasExistingTaskWithSameTitle(sinistroID: String, title: String) -> Bool {
        return taskManager.tasks.contains { task in
            task.sinistroID == sinistroID &&
            task.title == title &&
            task.status == .pending &&
            !task.isIgnored
        }
    }
    
    private func getCurrentMonthClosuresCount() async -> Int {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        
        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        
        request.predicate = NSPredicate(
            format: "stato == %@ AND dataChiusura >= %@ AND dataChiusura < %@",
            StatoManager.StatoSinistro.chiusa.descrizione,
            monthStart as NSDate,
            monthEnd as NSDate
        )
        
        return (try? context.count(for: request)) ?? 0
    }
    
    /// Determina se serve accelerare le chiusure
    private func shouldAccelerateClosures() async -> Bool {
        // TODO: Leggere media tempi gestione da metriche ConsuntivoView
        // Se media > 20 giorni, restituire true
        return false
    }
    
    /// Verifica se sollecitare controllo
    private func shouldRemindControl(sinistro: Sinistro) async -> Bool {
        let now = Date()
        
        // Condizione 1: >10 giorni lavorativi da data ingresso in controllo
        // TODO: Aggiungere campo dataInControllo a Sinistro entity
        // if let dataControllo = sinistro.dataInControllo {
        //     let workingDays = workScheduleManager.countWorkingDays(from: dataControllo, to: now)
        //     if workingDays > 10 {
        //         return true
        //     }
        // }
        
        // Condizione 2: <5 giorni lavorativi da fine mese
        let daysToEndOfMonth = workScheduleManager.workingDaysUntilEndOfMonth(from: now)
        if daysToEndOfMonth <= 5 {
            return true
        }
        
        return false
    }
    
    /// Verifica se tentare concordato verbale
    private func shouldAttemptVerbalAgreement(
        sinistro: Sinistro,
        monthlyGoal: Int,
        currentClosures: Int
    ) async -> Bool {
        let now = Date()
        
        // Condizione 1: Importo ≤ 5k (idealmente ≤ 3k)
        let importo = sinistro.liquidato?.doubleValue ?? 0
        guard importo > 0 && importo <= 5000 else { return false }
        
        // Condizione 2: <7 giorni lavorativi da fine mese
        let daysToEndOfMonth = workScheduleManager.workingDaysUntilEndOfMonth(from: now)
        guard daysToEndOfMonth <= 7 else { return false }
        
        // Condizione 3: Obiettivo mese non ancora raggiunto
        guard currentClosures < monthlyGoal else { return false }
        
        return true
    }
}
