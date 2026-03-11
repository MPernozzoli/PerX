import Foundation
import Combine
import CoreData

/// Motore decisionale centralizzato per la gestione degli eventi sinistri
/// Si sottoscrive a UnifiedEventBus e determina le azioni da eseguire
@MainActor
class ClaimEngine: ObservableObject {
    static let shared = ClaimEngine()
    
    // MARK: - Dependencies
    
    private let eventBus = UnifiedEventBus.shared
    private let statoManager = StatoManager.shared
    private let ruleManager = RuleManager.shared
    private let taskManager = TaskManager.shared
    private let priorityCalculator = PriorityCalculator.shared
    private let workScheduleManager = WorkScheduleManager.shared
    
    // MARK: - State
    
    @Published var isProcessing = false
    @Published var lastProcessedEvent: (any ClaimEvent)?
    @Published var processedEventsCount: Int = 0
    @Published var lastError: String?
    
    /// Publisher per i risultati del processamento eventi
    let resultPublisher = PassthroughSubject<ClaimEngineResult, Never>()
    
    private var cancellables = Set<AnyCancellable>()
    private var processedEventIds = Set<String>() // Cache eventi già processati
    private let processedEventsCache = UserDefaults.standard
    private let processedEventsKey = "ClaimEngine.processedEvents"
    
    // MARK: - Initialization
    
    private init() {
        loadProcessedEvents()
        setupSubscriptions()
        print("[ClaimEngine] ✅ Inizializzato e sottoscritto a UnifiedEventBus")
    }
    
    /// Carica eventi già processati dalla cache
    private func loadProcessedEvents() {
        if let cached = processedEventsCache.array(forKey: processedEventsKey) as? [String] {
            processedEventIds = Set(cached)
            print("[ClaimEngine] 📦 Caricati \(processedEventIds.count) eventi già processati dalla cache")
        }
    }
    
    /// Salva eventi processati nella cache
    private func saveProcessedEvents() {
        let array = Array(processedEventIds)
        processedEventsCache.set(array, forKey: processedEventsKey)
        
        // Limita cache a 1000 eventi (rimuove i più vecchi)
        if array.count > 1000 {
            let trimmed = Array(array.suffix(1000))
            processedEventIds = Set(trimmed)
            processedEventsCache.set(trimmed, forKey: processedEventsKey)
        }
    }
    
    /// Genera un ID univoco per un evento
    private func eventId(for event: any ClaimEvent) -> String {
        // Usa emailId se disponibile (più affidabile)
        if let emailEvent = event as? EmailClaimEvent {
            return "\(type(of: event))-\(emailEvent.emailId)"
        }
        
        // Altrimenti usa sinistroId + timestamp
        let sinistroId = event.sinistroId ?? "unknown"
        let timestamp = event.timestamp
        return "\(type(of: event))-\(sinistroId)-\(Int(timestamp.timeIntervalSince1970))"
    }
    
    // MARK: - Subscriptions
    
    private func setupSubscriptions() {
        // Sottoscrizione a tutti gli eventi
        eventBus.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    await self?.processEvent(event)
                }
            }
            .store(in: &cancellables)
        
        // Sottoscrizione specifica per assegnazioni (priorità alta)
        eventBus.assignmentPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    await self?.handleAssignment(event)
                }
            }
            .store(in: &cancellables)
        
        // Sottoscrizione specifica per revoche (azione immediata)
        eventBus.revocationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    await self?.handleRevocation(event)
                }
            }
            .store(in: &cancellables)
        
        // Sottoscrizione per note utente (parsing tag)
        eventBus.userNoteEventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    await self?.handleUserNote(event)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Event Processing
    
    /// Processa un evento generico
    private func processEvent(_ event: any ClaimEvent) async {
        // Verifica se già processato
        let eventId = eventId(for: event)
        if processedEventIds.contains(eventId) {
            print("[ClaimEngine] ⏭️ Evento già processato: \(eventId), skip")
            return
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let eventType = String(describing: type(of: event))
        print("[ClaimEngine] 🔄 Processando evento: \(eventType) [\(eventId)]")
        
        // Ottieni il sinistro se l'evento è associato a uno
        guard let sinistroId = event.sinistroId else {
            print("[ClaimEngine] ⚠️ Evento senza sinistroId, skip processing")
            logEventToDiary(event, decision: .noAction)
            return
        }
        
        guard let sinistro = fetchSinistro(riferimento: sinistroId) else {
            print("[ClaimEngine] ⚠️ Sinistro non trovato: \(sinistroId)")
            return
        }
        
        // Determina la decisione basata sul tipo di evento
        let decision = await determineDecision(for: event, sinistro: sinistro)
        
        // Esegui l'azione
        await executeDecision(decision, for: sinistro, event: event)
        
        // Marca come processato
        processedEventIds.insert(eventId)
        saveProcessedEvents()
        
        // Aggiorna contatori
        lastProcessedEvent = event
        processedEventsCount += 1
    }
    
    /// Determina la decisione per un evento
    private func determineDecision(for event: any ClaimEvent, sinistro: Sinistro) async -> ClaimEngineDecision {
        let currentStateDesc = sinistro.stato ?? ""
        let currentState = StatoManager.StatoSinistro.allCases.first { $0.descrizione == currentStateDesc }
            ?? .daScaricare
        
        switch event {
        case let emailEvent as EmailClaimEvent:
            return determineEmailDecision(emailEvent, sinistro: sinistro, currentState: currentState)
            
        case let waEvent as WhatsAppClaimEvent:
            return determineWhatsAppDecision(waEvent, sinistro: sinistro, currentState: currentState)
            
        case let noteEvent as UserNoteClaimEvent:
            return determineUserNoteDecision(noteEvent, sinistro: sinistro, currentState: currentState)
            
        case let systemEvent as SystemClaimEvent:
            return determineSystemDecision(systemEvent, sinistro: sinistro, currentState: currentState)
            
        default:
            return .noAction
        }
    }
    
    // MARK: - Decision Logic
    
    private func determineEmailDecision(
        _ event: EmailClaimEvent,
        sinistro: Sinistro,
        currentState: StatoManager.StatoSinistro
    ) -> ClaimEngineDecision {
        let recommendation = ruleManager.mapIntentToAction(
            intent: event.intent,
            sinistro: sinistro,
            currentState: currentState
        )
        
        switch recommendation.actionType {
        case .autoStateChange:
            if let targetState = recommendation.targetState {
                // Valida la transizione
                let validation = ruleManager.validateStateTransition(
                    from: currentState,
                    to: targetState,
                    sinistro: sinistro
                )
                
                if validation.isValid {
                    return ClaimEngineDecision(
                        actionType: .autoStateChange,
                        targetState: targetState,
                        taskTitle: recommendation.taskTitle,
                        taskDescription: recommendation.taskDescription,
                        priority: recommendation.priority,
                        reason: "Transizione automatica da \(currentState.descrizione) a \(targetState.descrizione)"
                    )
                } else {
                    return ClaimEngineDecision(
                        actionType: .createTask,
                        taskTitle: validation.taskDescription ?? "Azione manuale richiesta",
                        taskDescription: validation.reason,
                        priority: 0.8,
                        reason: validation.reason
                    )
                }
            }
            
        case .createTask:
            return ClaimEngineDecision(
                actionType: recommendation.createTask ? .createTask : .logToDiary,
                taskTitle: recommendation.taskTitle,
                taskDescription: recommendation.taskDescription,
                priority: recommendation.priority,
                reason: "Task generata da intent \(event.intent.rawValue)"
            )
            
        case .notify:
            return ClaimEngineDecision(
                actionType: .notifyUser,
                priority: recommendation.priority,
                reason: "Notifica utente richiesta"
            )
            
        case .noAction:
            return .noAction
        }
        
        return .noAction
    }
    
    private func determineWhatsAppDecision(
        _ event: WhatsAppClaimEvent,
        sinistro: Sinistro,
        currentState: StatoManager.StatoSinistro
    ) -> ClaimEngineDecision {
        // Logica simile a email ma adattata per WhatsApp
        let recommendation = ruleManager.mapIntentToAction(
            intent: event.intent,
            sinistro: sinistro,
            currentState: currentState
        )
        
        switch recommendation.actionType {
        case .createTask:
            return ClaimEngineDecision(
                actionType: .createTask,
                taskTitle: recommendation.taskTitle ?? "Rispondere a WhatsApp",
                taskDescription: "Messaggio WhatsApp richiede risposta",
                priority: recommendation.priority,
                reason: "Task da WhatsApp"
            )
            
        default:
            return ClaimEngineDecision(
                actionType: .logToDiary,
                reason: "Messaggio WhatsApp registrato"
            )
        }
    }
    
    private func determineUserNoteDecision(
        _ event: UserNoteClaimEvent,
        sinistro: Sinistro,
        currentState: StatoManager.StatoSinistro
    ) -> ClaimEngineDecision {
        // Processa i tag estratti dalla nota
        guard !event.parsedTags.isEmpty else {
            return ClaimEngineDecision(
                actionType: .logToDiary,
                reason: "Nota utente senza tag speciali"
            )
        }
        
        // Prendi il primo tag come azione principale
        guard let primaryTag = event.parsedTags.first else {
            return .noAction
        }
        
        switch primaryTag.type {
        case .task:
            var metadata: [String: Any] = [:]
            if let diarioEntryId = event.diarioEntryId {
                metadata["diarioEntryId"] = diarioEntryId
            }
            
            return ClaimEngineDecision(
                actionType: .createTask,
                taskTitle: primaryTag.body,
                taskDeadline: primaryTag.deadline,
                taskScheduledTime: primaryTag.scheduledTime,
                priority: ruleManager.calculatePriority(for: sinistro),
                reason: "Task da nota utente @task",
                additionalMetadata: metadata
            )
            
        case .action:
            // Per ora log solo, azioni future
            return ClaimEngineDecision(
                actionType: .logToDiary,
                reason: "Azione \(primaryTag.body) richiesta (non ancora implementata)",
                additionalMetadata: ["pendingAction": primaryTag.body]
            )
            
        case .reference:
            // Log del riferimento
            return ClaimEngineDecision(
                actionType: .logToDiary,
                reason: "Riferimento a \(primaryTag.body)",
                additionalMetadata: ["reference": primaryTag.body]
            )
        }
    }
    
    private func determineSystemDecision(
        _ event: SystemClaimEvent,
        sinistro: Sinistro,
        currentState: StatoManager.StatoSinistro
    ) -> ClaimEngineDecision {
        switch event.systemEventType {
        case .folderDownloaded:
            // Aggiorna stato se era "da scaricare"
            if currentState == .daScaricare {
                let nextState: StatoManager.StatoSinistro = sinistro.sopralluogo
                    ? .periziaDaEseguire
                    : .inAttesaDocumentale
                
                return ClaimEngineDecision(
                    actionType: .autoStateChange,
                    targetState: nextState,
                    reason: "Cartella scaricata, avanzamento automatico stato"
                )
            }
            
        case .deadlineApproaching:
            return ClaimEngineDecision(
                actionType: .createUrgentTask,
                taskTitle: "Scadenza imminente - \(sinistro.riferimento ?? "")",
                taskDescription: "La deadline per questo sinistro si avvicina",
                priority: 0.95,
                reason: "Deadline imminente"
            )
            
        case .taskCompleted:
            return ClaimEngineDecision(
                actionType: .logToDiary,
                reason: "Task completata"
            )
            
        default:
            return .noAction
        }
        
        return .noAction
    }
    
    // MARK: - Decision Execution
    
    private func executeDecision(
        _ decision: ClaimEngineDecision,
        for sinistro: Sinistro,
        event: any ClaimEvent
    ) async {
        guard let riferimento = sinistro.riferimento else { return }
        
        // Calcola priorità dinamica UNIFICATA per tutte le task
        let monthlyGoal = workScheduleManager.getMonthlyTarget(for: Date())
        let currentClosures = await getCurrentMonthClosuresCount()
        let needsAcceleration = await shouldAccelerateClosures()
        
        let dynamicPriority = priorityCalculator.calculateDynamicPriority(
            for: sinistro,
            monthlyGoal: monthlyGoal,
            currentClosures: currentClosures,
            needsAcceleration: needsAcceleration
        )
        
        switch decision.actionType {
        case .none:
            break
            
        case .autoStateChange:
            if let targetState = decision.targetState {
                await changeState(sinistro: sinistro, to: targetState, reason: decision.reason)
            }
            
            // Se c'è anche una task da creare
            if let taskTitle = decision.taskTitle {
                createTask(
                    sinistro: sinistro,
                    title: taskTitle,
                    description: decision.taskDescription,
                    deadline: decision.taskDeadline,
                    scheduledTime: decision.taskScheduledTime,
                    priority: dynamicPriority
                )
            }
            
        case .createTask:
            if let taskTitle = decision.taskTitle {
                // Estrai diarioEntryId da metadata se presente (per note utente)
                let diarioEntryId = decision.additionalMetadata["diarioEntryId"] as? UUID
                
                createTask(
                    sinistro: sinistro,
                    title: taskTitle,
                    description: decision.taskDescription,
                    deadline: decision.taskDeadline,
                    scheduledTime: decision.taskScheduledTime,
                    priority: dynamicPriority,
                    diarioEntryId: diarioEntryId
                )
            }
            
        case .createUrgentTask:
            if let taskTitle = decision.taskTitle {
                createTask(
                    sinistro: sinistro,
                    title: taskTitle,
                    description: decision.taskDescription,
                    deadline: decision.taskDeadline,
                    scheduledTime: decision.taskScheduledTime,
                    priority: min(1.0, dynamicPriority + 0.2), // Urgent: boost di 0.2
                    isUrgent: true
                )
            }
            
        case .downloadAttachment, .saveToFolder:
            // Gestito da ActiveTriggerService per ora
            break
            
        case .logToDiary:
            break
            
        case .notifyUser:
            sendNotification(
                sinistro: sinistro,
                title: decision.taskTitle ?? "Notifica",
                body: decision.taskDescription ?? decision.reason
            )
        }
        
        // Aggiorna date sinistro in base all'intent dell'evento
        await updateSinistroDatesFromEvent(event, sinistro: sinistro)
        
        // Log sempre nel diario
        logEventToDiary(event, decision: decision)
    }
    
    // MARK: - Automatic State Transitions & Date Updates
    
    /// Gestisce transizioni automatiche di stato e aggiornamento date basate sull'intent dell'evento
    /// 1. Tenta la transizione automatica di stato (che valorizza le date tramite StatoManager)
    /// 2. Se la transizione non avviene, valorizza comunque le date come fallback
    private func updateSinistroDatesFromEvent(_ event: any ClaimEvent, sinistro: Sinistro) async {
        let context = PersistenceController.shared.container.viewContext
        
        // Gestione eventi email
        guard let emailEvent = event as? EmailClaimEvent else { return }
        
        let eventDate = emailEvent.timestamp
        let currentStateDesc = sinistro.stato ?? ""
        let currentState = StatoManager.StatoSinistro.allCases.first { $0.descrizione == currentStateDesc }
        
        // Determina stato target e date da valorizzare in base all'intent
        var targetState: StatoManager.StatoSinistro?
        var dateUpdates: [(keyPath: ReferenceWritableKeyPath<Sinistro, Date?>, date: Date, name: String)] = []
        
        switch emailEvent.intent {
        case .actReceived:
            // Atto firmato ricevuto → transizione a .attoRicevutoSottoscritto
            targetState = .attoRicevutoSottoscritto
            dateUpdates = [
                (\.dataRitornoAtto, eventDate, "dataRitornoAtto"),
                (\.dataRicezioneAttoSottoscritto, eventDate, "dataRicezioneAttoSottoscritto")
            ]
            
        case .actSent:
            // Atto inviato → transizione a .attoInviato
            targetState = .attoInviato
            dateUpdates = [
                (\.dataInvioAtto, eventDate, "dataInvioAtto")
            ]
            
        case .outcomeSent:
            // Esito comunicato → transizione a .esitoComunicato
            targetState = .esitoComunicato
            dateUpdates = [
                (\.dataComunicazioneEsito, eventDate, "dataComunicazioneEsito"),
                (\.dataInvioAtto, eventDate, "dataInvioAtto") // Retrocompatibilità
            ]
            
        case .verbalAcceptance:
            // Accettazione verbale → transizione a .accettataVerbalmente
            targetState = .accettataVerbalmente
            dateUpdates = [
                (\.dataAccettazioneVerbale, eventDate, "dataAccettazioneVerbale")
            ]
            
        default:
            return
        }
        
        // Tenta la transizione automatica di stato
        var transitionSucceeded = false
        
        if let target = targetState, let current = currentState {
            // Verifica se la transizione è valida
            if current.validTransitions.contains(target) {
                do {
                    try await statoManager.changeState(
                        for: sinistro,
                        to: target,
                        context: context,
                        userEmail: nil,
                        skipValidation: false
                    )
                    transitionSucceeded = true
                    print("[ClaimEngine] ✅ Transizione automatica: \(current.descrizione) → \(target.descrizione)")
                } catch {
                    print("[ClaimEngine] ⚠️ Transizione automatica fallita: \(error.localizedDescription)")
                }
            } else {
                print("[ClaimEngine] ⚠️ Transizione \(current.descrizione) → \(target.descrizione) non valida, valorizzazione solo date")
            }
        }
        
        // Se la transizione non è avvenuta, valorizza comunque le date come fallback
        if !transitionSucceeded {
            var needsSave = false
            
            for update in dateUpdates {
                if sinistro[keyPath: update.keyPath] == nil {
                    sinistro[keyPath: update.keyPath] = update.date
                    needsSave = true
                    print("[ClaimEngine] 📅 Valorizzata \(update.name): \(update.date) (fallback)")
                }
            }
            
            if needsSave {
                do {
                    try context.save()
                    print("[ClaimEngine] ✅ Date sinistro aggiornate (fallback)")
                } catch {
                    print("[ClaimEngine] ❌ Errore aggiornamento date: \(error)")
                }
            }
        }
    }
    
    // MARK: - Specific Event Handlers
    
    private func handleAssignment(_ event: EmailAssignmentEvent) async {
        print("[ClaimEngine] 📥 Gestione nuova assegnazione: \(event.riferimento) - data: \(event.assignmentDate)")
        
        let context = PersistenceController.shared.container.viewContext
        let riferimento = event.riferimento
        let assignmentDate = event.assignmentDate

        // Owner/assegnatario: chi riceve la mail di assegnazione
        let newOwnerEmail = event.assigneeEmail?.lowercased()
        let newOwnerName = event.assigneeName
        
        // Verifica se l'email è letta
        let emailRepository = EmailRepository.shared
        let email = emailRepository.getEmail(byId: event.emailId)
        let isEmailRead = email?.isRead ?? false
        
        // Verifica se esiste già un sinistro con quel riferimento
        var isNewAssignment = false
        var isReassigned = false
        
        // Verifica limite importazione sinistri recenti (solo per nuovi sinistri)
        if !RiferimentoValidator.canImport(riferimento) {
            if let year = RiferimentoValidator.extractYear(from: riferimento) {
                print("[ClaimEngine] ⚠️ Sinistro \(riferimento) rifiutato: anno \(year) - troppo vecchio")
            } else {
                print("[ClaimEngine] ⚠️ Sinistro \(riferimento) rifiutato: troppo vecchio")
            }
            return
        }
        
        guard let existingSinistro = fetchSinistro(riferimento: riferimento) else {
            // Non esiste: crea nuova entity sempre (anche se email letta)
            print("[ClaimEngine] ✨ Creazione nuovo sinistro: \(riferimento)")
            isNewAssignment = true
            
            let sinistro = Sinistro(context: context)
            sinistro.riferimento = riferimento
            sinistro.setDataAssegnazione(assignmentDate)
            sinistro.dataAperturaGestione = assignmentDate
            sinistro.stato = StatoManager.StatoSinistro.daScaricare.descrizione
            if let newOwnerEmail {
                sinistro.ownerEmail = newOwnerEmail
                sinistro.assignedToUserEmail = newOwnerEmail
                sinistro.assignedToUserName = newOwnerName
            }
            // ... (rest of creation logic)
            print("[ClaimEngine] ✅ Data assegnazione impostata: \(assignmentDate) per sinistro \(riferimento)")
            
            // Popola dati estratti se disponibili
            let extractedData = event.extractedData
            if let nome = extractedData["nome"] {
                sinistro.nomeAssicurato = nome
                sinistro.nomeContraente = nome
            }
            if let telefono = extractedData["telefono"] {
                sinistro.telefonoAssicurato = telefono
            }
            if let emailAddr = extractedData["email"] {
                sinistro.emailAssicurato = emailAddr
            }
            if let indirizzo = extractedData["indirizzo"] {
                sinistro.indirizzoAssicurato = indirizzo
            }
            
            do {
                try context.save()
                print("[ClaimEngine] ✅ Sinistro \(riferimento) creato con stato 'da scaricare'")
                
                // Notifica push e avvio download per nuova assegnazione
                notifyAndDownload(riferimento: riferimento)
                
                // Notifica creazione sinistro per registrazione automatica nel Sync Agent
                NotificationCenter.default.post(
                    name: .sinistroCreated,
                    object: nil,
                    userInfo: ["riferimento": riferimento]
                )
                
                // Associa l'email al nuovo sinistro
                if let email {
                    await EmailAssociationService.shared.associateEmailToSinistri(email, sinistri: [sinistro], context: context)
                } else if let cachedEmail = EmailRepository.shared.getEmail(byId: event.emailId) {
                    // Fallback se email è nil ma presente nel repository
                    await EmailAssociationService.shared.associateEmailToSinistri(cachedEmail, sinistri: [sinistro], context: context)
                }
                
                // Segna in diario
                logEventToDiary(
                    event,
                    decision: ClaimEngineDecision(
                        actionType: .logToDiary,
                        reason: "Nuovo sinistro assegnato - riferimento: \(riferimento)"
                    )
                )
                
                // Pubblica risultato di successo
                let result = ClaimEngineResult(
                    eventId: event.eventId,
                    emailId: event.emailId,
                    resultType: .success,
                    actionType: .logToDiary,
                    message: "Data assegnazione impostata: \(assignmentDate)",
                    details: ["riferimento": riferimento, "dataAssegnazione": assignmentDate]
                )
                resultPublisher.send(result)
                print("[ClaimEngine] 📤 Risultato pubblicato: successo - data assegnazione impostata")
                
                // Associa l'email al nuovo sinistro
                if let email {
                    await EmailAssociationService.shared.associateEmailToSinistri(email, sinistri: [sinistro], context: context)
                } else if let cachedEmail = EmailRepository.shared.getEmail(byId: event.emailId) {
                    // Fallback se email è nil ma presente nel repository
                    await EmailAssociationService.shared.associateEmailToSinistri(cachedEmail, sinistri: [sinistro], context: context)
                }
                
                // Marca email come letta solo se non letta
                if !isEmailRead {
                    await markEmailAsRead(emailId: event.emailId)
                }
                
            } catch {
                print("[ClaimEngine] ❌ Errore creazione sinistro: \(error)")
                lastError = error.localizedDescription
                
                // Pubblica risultato di errore
                let result = ClaimEngineResult(
                    eventId: event.eventId,
                    emailId: event.emailId,
                    resultType: .error,
                    actionType: .none,
                    message: "Errore creazione sinistro: \(error.localizedDescription)",
                    details: ["error": error.localizedDescription, "riferimento": riferimento]
                )
                resultPublisher.send(result)
                print("[ClaimEngine] 📤 Risultato pubblicato: errore")
            }
            
            return
        }
        
        // Esiste già: verifica stato
        let wasRevoked = existingSinistro.stato == StatoManager.StatoSinistro.revocata.descrizione
        let revocationSubstateSnapshot = existingSinistro.substate
        
        if let newOwnerEmail {
            // Rileva se l'assegnatario è cambiato
            if existingSinistro.ownerEmail?.lowercased() != newOwnerEmail {
                print("[ClaimEngine] 🔄 Cambio assegnatario per \(riferimento): \(existingSinistro.ownerEmail ?? "nessuno") -> \(newOwnerEmail)")
                isReassigned = true
            }
            
            // Cambia owner SEMPRE: la mail di assegnazione è autoritativa
            existingSinistro.ownerEmail = newOwnerEmail
            existingSinistro.assignedToUserEmail = newOwnerEmail
            existingSinistro.assignedToUserName = newOwnerName
            existingSinistro.dataAssegnazione = assignmentDate
            if existingSinistro.dataAperturaGestione == nil {
                existingSinistro.dataAperturaGestione = assignmentDate
            }
            try? context.save()
            
            // Se l'assegnatario è cambiato, invia notifica e avvia download
            if isReassigned {
                notifyAndDownload(riferimento: riferimento)
            }
            
            // Associa l'email al sinistro esistente (se non già associata)
            if let email {
                await EmailAssociationService.shared.associateEmailToSinistri(email, sinistri: [existingSinistro], context: context)
            } else if let cachedEmail = EmailRepository.shared.getEmail(byId: event.emailId) {
                // Fallback se email è nil ma presente nel repository
                await EmailAssociationService.shared.associateEmailToSinistri(cachedEmail, sinistri: [existingSinistro], context: context)
            }
        }

        let currentStateDesc = existingSinistro.stato ?? ""
        let currentState = StatoManager.StatoSinistro.allCases.first { $0.descrizione == currentStateDesc }
            ?? .daScaricare
        
        if currentState == .revocata {
            // Se è revocato: aggiorna a "da scaricare" con dettaglio "reincaricato"
            print("[ClaimEngine] 🔄 Sinistro \(riferimento) reincaricato (era revocato)")
            
            // Per sinistri revocati, la transizione a daScaricare è sempre permessa (reincarico)
            existingSinistro.stato = StatoManager.StatoSinistro.daScaricare.descrizione
            existingSinistro.dataAssegnazione = assignmentDate
            existingSinistro.dataAperturaGestione = assignmentDate
            
            // Passaggio owner (multi-utente): revocato a X → riassegnato a Y
            if wasRevoked, let newOwnerEmail {
                let newOwnerDisplay: String = {
                    if let n = newOwnerName, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return n }
                    guard let local = newOwnerEmail.split(separator: "@").first else { return newOwnerEmail }
                    return String(local).replacingOccurrences(of: ".", with: " ").capitalized
                }()
                
                let revokedDisplay: String = {
                    guard let raw = revocationSubstateSnapshot,
                          raw.hasPrefix("revocationFrom=") else { return "perito" }
                    let payload = String(raw.dropFirst("revocationFrom=".count))
                    let parts = payload.components(separatedBy: "|")
                    let email = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let name = (parts.count > 1 ? parts[1] : "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { return name }
                    if !email.isEmpty { return email }
                    return "perito"
                }()
                
                existingSinistro.addDiarioEntry(
                    DiarioEntry(
                        testo: "Sinistro revocato a \(revokedDisplay) e riassegnato a \(newOwnerDisplay)",
                        tipo: .assegnazione
                    )
                )
            }
            
            // Pulizia metadati revoca (se presenti)
            if existingSinistro.substate?.hasPrefix("revocationFrom=") == true {
                existingSinistro.substate = nil
            }
            
            do {
                try context.save()
                print("[ClaimEngine] ✅ Sinistro \(riferimento) reincaricato")
                
                // Segna in diario
                logEventToDiary(
                    event,
                    decision: ClaimEngineDecision(
                        actionType: .logToDiary,
                        reason: "Sinistro reincaricato - riferimento: \(riferimento) (era revocato)"
                    )
                )
                
                // Associa l'email al sinistro esistente
                if let email {
                    await EmailAssociationService.shared.associateEmailToSinistri(email, sinistri: [existingSinistro], context: context)
                } else if let cachedEmail = EmailRepository.shared.getEmail(byId: event.emailId) {
                    await EmailAssociationService.shared.associateEmailToSinistri(cachedEmail, sinistri: [existingSinistro], context: context)
                }
                
                // Marca email come letta solo se non letta
                if !isEmailRead {
                    await markEmailAsRead(emailId: event.emailId)
                }
                
            } catch {
                print("[ClaimEngine] ❌ Errore aggiornamento sinistro reincaricato: \(error)")
                lastError = error.localizedDescription
            }
            
        } else if currentState == .chiusa {
            // Sinistro chiuso: inseriamo comunque l'assegnazione (dataAssegnazione, ownerEmail già aggiornati alle linee 558-568)
            print("[ClaimEngine] ⚠️ Sinistro \(riferimento) è chiuso, ma assegnazione comunque inserita")
            
            // Assicuriamoci che dataAssegnazione sia aggiornata (potrebbe non essere stata aggiornata se newOwnerEmail era nil)
            existingSinistro.dataAssegnazione = assignmentDate
            if existingSinistro.dataAperturaGestione == nil {
                existingSinistro.dataAperturaGestione = assignmentDate
            }
            
            do {
                try context.save()
                
                logEventToDiary(
                    event,
                    decision: ClaimEngineDecision(
                        actionType: .logToDiary,
                        reason: "Assegnazione inserita - sinistro chiuso: \(riferimento)"
                    )
                )
                
                // Pubblica risultato: successo (l'assegnazione è stata comunque inserita)
                let result = ClaimEngineResult(
                    eventId: event.eventId,
                    emailId: event.emailId,
                    resultType: .success,
                    actionType: .logToDiary,
                    message: "Assegnazione inserita - sinistro chiuso: \(riferimento)",
                    details: ["riferimento": riferimento, "stato": "chiusa", "dataAssegnazione": assignmentDate]
                )
                resultPublisher.send(result)
                print("[ClaimEngine] 📤 Risultato pubblicato: successo - assegnazione inserita (sinistro chiuso)")
                
                // Associa l'email al sinistro esistente
                if let email {
                    await EmailAssociationService.shared.associateEmailToSinistri(email, sinistri: [existingSinistro], context: context)
                } else if let cachedEmail = EmailRepository.shared.getEmail(byId: event.emailId) {
                    await EmailAssociationService.shared.associateEmailToSinistri(cachedEmail, sinistri: [existingSinistro], context: context)
                }
                
                // Marca email come letta solo se non letta
                if !isEmailRead {
                    await markEmailAsRead(emailId: event.emailId)
                }
                
            } catch {
                print("[ClaimEngine] ❌ Errore aggiornamento assegnazione sinistro chiuso: \(error)")
                lastError = error.localizedDescription
                
                // Pubblica risultato di errore
                let result = ClaimEngineResult(
                    eventId: event.eventId,
                    emailId: event.emailId,
                    resultType: .error,
                    actionType: .none,
                    message: "Errore aggiornamento assegnazione sinistro chiuso: \(error.localizedDescription)",
                    details: ["error": error.localizedDescription, "riferimento": riferimento]
                )
                resultPublisher.send(result)
                print("[ClaimEngine] 📤 Risultato pubblicato: errore")
            }
            
        } else {
            // Altro stato: verifica data incarico
            if let existingDate = existingSinistro.dataAssegnazione {
                let calendar = Calendar.current
                if calendar.isDate(existingDate, inSameDayAs: assignmentDate) {
                    // Stessa data: ignora (errore/duplicato)
                    print("[ClaimEngine] ⚠️ Sinistro \(riferimento) già assegnato nella stessa data, ignorato")
                    
                    logEventToDiary(
                        event,
                        decision: ClaimEngineDecision(
                            actionType: .logToDiary,
                            reason: "Assegnazione duplicata ignorata - riferimento: \(riferimento) (stessa data)"
                        )
                    )
                    
                    // Pubblica risultato: ignorato (duplicato) - ma è un successo perché la data è già corretta
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .none
                    let dataFormattata = formatter.string(from: existingDate)
                    
                    let result = ClaimEngineResult(
                        eventId: event.eventId,
                        emailId: event.emailId,
                        resultType: .ignored,
                        actionType: .logToDiary,
                        message: "Assegnazione duplicata - stessa data: \(dataFormattata)",
                        details: [
                            "riferimento": riferimento,
                            "dataEsistente": existingDate,
                            "stessaData": true
                        ]
                    )
                    resultPublisher.send(result)
                    print("[ClaimEngine] 📤 Risultato pubblicato: ignorato - duplicato")
                    
                    // Associa l'email al sinistro esistente
                    if let email {
                        await EmailAssociationService.shared.associateEmailToSinistri(email, sinistri: [existingSinistro], context: context)
                    } else if let cachedEmail = EmailRepository.shared.getEmail(byId: event.emailId) {
                        await EmailAssociationService.shared.associateEmailToSinistri(cachedEmail, sinistri: [existingSinistro], context: context)
                    }
                    
                    // Marca email come letta solo se non letta
                    if !isEmailRead {
                        await markEmailAsRead(emailId: event.emailId)
                    }
                    
                } else {
                // Data diversa: notifica utente (azione inattesa)
                print("[ClaimEngine] ⚠️ Sinistro \(riferimento) già assegnato in data diversa, notifica utente")
                
                sendNotification(
                    sinistro: existingSinistro,
                    title: "Sinistro già assegnato",
                    body: "Il sinistro \(riferimento) è stato assegnato ma risulta già incaricato. Verifica manualmente."
                )
                
                // Associa comunque l'email al sinistro esistente per visibilità
                if let email {
                    await EmailAssociationService.shared.associateEmailToSinistri(email, sinistri: [existingSinistro], context: context)
                } else if let cachedEmail = EmailRepository.shared.getEmail(byId: event.emailId) {
                    await EmailAssociationService.shared.associateEmailToSinistri(cachedEmail, sinistri: [existingSinistro], context: context)
                }
                
                logEventToDiary(
                        event,
                        decision: ClaimEngineDecision(
                            actionType: .logToDiary,
                            reason: "Assegnazione sinistro già incaricato - riferimento: \(riferimento) (data precedente: \(DateFormatter.short.string(from: existingDate)))"
                        )
                    )
                    
                    // Pubblica risultato: azione inattesa (non abbiamo aggiornato la data)
                    let result = ClaimEngineResult(
                        eventId: event.eventId,
                        emailId: event.emailId,
                        resultType: .unexpectedAction,
                        actionType: .logToDiary,
                        message: "Sinistro già assegnato in data diversa - data non aggiornata",
                        details: ["riferimento": riferimento, "dataEsistente": existingDate, "dataRichiesta": assignmentDate]
                    )
                    resultPublisher.send(result)
                    print("[ClaimEngine] 📤 Risultato pubblicato: azione inattesa")
                    
                    // Marca email come letta solo se non letta
                    if !isEmailRead {
                        await markEmailAsRead(emailId: event.emailId)
                    }
                }
            } else {
                // Nessuna data assegnazione: aggiorna SEMPRE (anche se email letta)
                print("[ClaimEngine] 🔄 Sinistro \(riferimento) senza data assegnazione, aggiornamento")
                
                existingSinistro.dataAssegnazione = assignmentDate
                if existingSinistro.dataAperturaGestione == nil {
                    existingSinistro.dataAperturaGestione = assignmentDate
                }
                print("[ClaimEngine] ✅ Data assegnazione aggiornata: \(assignmentDate) per sinistro \(riferimento)")
                
                do {
                    try context.save()
                    
                    logEventToDiary(
                        event,
                        decision: ClaimEngineDecision(
                            actionType: .logToDiary,
                            reason: "Data assegnazione aggiornata - riferimento: \(riferimento)"
                        )
                    )
                    
                    // Pubblica risultato di successo
                    let result = ClaimEngineResult(
                        eventId: event.eventId,
                        emailId: event.emailId,
                        resultType: .success,
                        actionType: .logToDiary,
                        message: "Data assegnazione aggiornata: \(assignmentDate)",
                        details: ["riferimento": riferimento, "dataAssegnazione": assignmentDate]
                    )
                    resultPublisher.send(result)
                    print("[ClaimEngine] 📤 Risultato pubblicato: successo - data assegnazione aggiornata")
                    
                    // Marca email come letta solo se non letta
                    if !isEmailRead {
                        await markEmailAsRead(emailId: event.emailId)
                    }
                    
                    // Associa l'email al sinistro esistente
                    if let email {
                        await EmailAssociationService.shared.associateEmailToSinistri(email, sinistri: [existingSinistro], context: context)
                    } else if let cachedEmail = EmailRepository.shared.getEmail(byId: event.emailId) {
                        await EmailAssociationService.shared.associateEmailToSinistri(cachedEmail, sinistri: [existingSinistro], context: context)
                    }
                    
                } catch {
                    print("[ClaimEngine] ❌ Errore aggiornamento data assegnazione: \(error)")
                    lastError = error.localizedDescription
                    
                    // Pubblica risultato di errore
                    let result = ClaimEngineResult(
                        eventId: event.eventId,
                        emailId: event.emailId,
                        resultType: .error,
                        actionType: .none,
                        message: "Errore aggiornamento data assegnazione: \(error.localizedDescription)",
                        details: ["error": error.localizedDescription, "riferimento": riferimento]
                    )
                    resultPublisher.send(result)
                    print("[ClaimEngine] 📤 Risultato pubblicato: errore")
                }
            }
        }
    }
    
    private func handleRevocation(_ event: EmailRevocationEvent) async {
        print("[ClaimEngine] 🚫 Gestione revoca: \(event.riferimento)")
        
        guard let sinistro = fetchSinistro(riferimento: event.riferimento) else {
            print("[ClaimEngine] ⚠️ Sinistro da revocare non trovato")
            return
        }
        
        // Cambia stato a revocata
        await changeState(sinistro: sinistro, to: .revocata, reason: event.reason ?? "Revoca ricevuta")
        
        // Rimuovi tutte le task
        taskManager.removeAllTasks(for: event.riferimento)
    }
    
    private func handleUserNote(_ event: UserNoteClaimEvent) async {
        print("[ClaimEngine] 📝 Gestione nota utente con \(event.parsedTags.count) tag")
        
        let parser = DiarioParser.shared
        
        // Estrai numeri di telefono dalla nota completa
        let phoneNumbers = parser.extractPhoneNumbers(from: event.noteText)
        
        // Processa ogni tag
        for tag in event.parsedTags {
            switch tag.type {
            case .task:
                guard let sinistroId = event.sinistroId,
                      let sinistro = fetchSinistro(riferimento: sinistroId) else { continue }
                
                // Pulisci il titolo dai riferimenti temporali
                let cleanTitle = parser.cleanTaskTitle(from: tag.body)
                
                // Prepara metadata con numeri di telefono
                var metadata: [String: AnyCodable] = [:]
                if let diarioEntryId = event.diarioEntryId {
                    metadata["diarioEntryId"] = AnyCodable(diarioEntryId.uuidString)
                }
                if !phoneNumbers.isEmpty {
                    metadata["phoneNumbers"] = AnyCodable(phoneNumbers)
                }
                
                createTask(
                    sinistro: sinistro,
                    title: cleanTitle,
                    description: "Task da nota utente",
                    deadline: tag.deadline,
                    scheduledTime: tag.scheduledTime,
                    priority: ruleManager.calculatePriority(for: sinistro),
                    diarioEntryId: event.diarioEntryId,
                    metadata: metadata
                )
                
            case .action:
                print("[ClaimEngine] ⚡ Azione richiesta: \(tag.body) (non ancora implementata)")
                
            case .reference:
                print("[ClaimEngine] 🔗 Riferimento: \(tag.body)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func fetchSinistro(riferimento: String) -> Sinistro? {
        let context = PersistenceController.shared.container.viewContext
        
        // PRIORITÀ 1: Cerca per riferimento
        let requestRif = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        requestRif.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        if let sinistro = try? context.fetch(requestRif).first {
            return sinistro
        }
        
        // PRIORITÀ 2: Se non trovato, cerca per numero sinistro agenzia
        let requestNum = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        requestNum.predicate = NSPredicate(format: "numeroSinistroCompagnia == %@", riferimento)
        return try? context.fetch(requestNum).first
    }
    
    private func changeState(
        sinistro: Sinistro,
        to newState: StatoManager.StatoSinistro,
        reason: String
    ) async {
        let context = PersistenceController.shared.container.viewContext
        let oldStateDesc = sinistro.stato ?? ""
        let oldState = StatoManager.StatoSinistro.allCases.first { $0.descrizione == oldStateDesc }
        
        sinistro.stato = newState.descrizione
        
        do {
            try context.save()
            print("[ClaimEngine] ✅ Stato cambiato: \(oldStateDesc) → \(newState.descrizione)")
            
            // Notifica cambio stato
            NotificationCenter.default.post(
                name: .sinistroStatoChanged,
                object: nil,
                userInfo: [
                    "sinistroID": sinistro.riferimento ?? "",
                    "oldState": oldState as Any,
                    "newState": newState
                ]
            )
        } catch {
            print("[ClaimEngine] ❌ Errore cambio stato: \(error)")
            lastError = error.localizedDescription
        }
    }
    
    // MARK: - Task Goal Mapping
    
    /// Determina obiettivo e regole di invalidazione per una task basati sull'intent dell'evento
    private func determineTaskGoal(
        for intent: ClaimEventIntent,
        event: EmailClaimEvent,
        sinistro: Sinistro
    ) -> (goal: TaskGoal?, invalidation: TaskInvalidation?) {
        guard let riferimento = sinistro.riferimento else { return (nil, nil) }
        
        switch intent {
        case .reminder:
            // Sollecitare documentazione
            return (
                goal: TaskGoal(
                    type: .sendReminderEmail,
                    targetValue: riferimento
                ),
                invalidation: TaskInvalidation(
                    conditions: [.sinistroClosedOrRevoked, .documentationReceived, .stateProgressed],
                    stateThreshold: .inGestione
                )
            )
            
        case .documentationRequest:
            // Richiedere documentazione
            return (
                goal: TaskGoal(
                    type: .requestDocumentation,
                    targetValue: riferimento
                ),
                invalidation: TaskInvalidation(
                    conditions: [.sinistroClosedOrRevoked, .documentationReceived, .stateProgressed],
                    stateThreshold: .periziaDaEseguire
                )
            )
            
        case .actSent:
            // Inviare atto
            return (
                goal: TaskGoal(
                    type: .sendActEmail,
                    targetValue: riferimento
                ),
                invalidation: TaskInvalidation(
                    conditions: [.sinistroClosedOrRevoked],
                    stateThreshold: nil
                )
            )
            
        case .actReceived:
            // Atto ricevuto - completa automaticamente task "sollecita atto"
            return (
                goal: TaskGoal(
                    type: .receiveActSigned,
                    targetValue: riferimento,
                    completionDate: event.timestamp,
                    completionSource: event.emailId
                ),
                invalidation: nil
            )
            
        case .documentation:
            // Documentazione ricevuta - completa automaticamente task "sollecita documentazione"
            return (
                goal: TaskGoal(
                    type: .receiveDocumentation,
                    targetValue: riferimento,
                    completionDate: event.timestamp,
                    completionSource: event.emailId
                ),
                invalidation: nil
            )
            
        case .clarification:
            // Rispondere a richiesta chiarimenti
            return (
                goal: TaskGoal(
                    type: .sendEmail,
                    targetValue: event.emailId
                ),
                invalidation: TaskInvalidation(
                    conditions: [.sinistroClosedOrRevoked, .emailReplied],
                    stateThreshold: nil
                )
            )
            
        case .control:
            // Sollecitare controllo
            return (
                goal: TaskGoal(
                    type: .sendReminderEmail,
                    targetValue: riferimento
                ),
                invalidation: TaskInvalidation(
                    conditions: [.sinistroClosedOrRevoked, .stateProgressed],
                    stateThreshold: .attoRicevutoSottoscritto
                )
            )
            
        case .surveyScheduled, .videocallScheduled:
            // Partecipare a sopralluogo/videoperizia
            return (
                goal: TaskGoal(
                    type: .attendMeeting,
                    targetValue: riferimento
                ),
                invalidation: TaskInvalidation(
                    conditions: [.sinistroClosedOrRevoked, .stateProgressed],
                    stateThreshold: .inGestione
                )
            )
            
        default:
            return (nil, nil)
        }
    }
    
    /// Mappa intent dell'evento a tipo di azione task
    private func mapIntentToActionType(_ intent: ClaimEventIntent) -> TaskActionType? {
        switch intent {
        case .reminder:
            return .remind
        case .documentationRequest:
            return .request
        case .clarification:
            return .reply
        case .actSent:
            return .send
        case .control:
            return .remind
        case .surveyScheduled, .videocallScheduled:
            return .attend
        case .outcomeSent:
            return .send
        default:
            return nil
        }
    }
    
    private func createTask(
        sinistro: Sinistro,
        title: String,
        description: String?,
        deadline: Date?,
        scheduledTime: Date? = nil,
        priority: Double,
        isUrgent: Bool = false,
        diarioEntryId: UUID? = nil,
        metadata: [String: AnyCodable]? = nil,
        actionType: TaskActionType? = nil,
        goal: TaskGoal? = nil,
        invalidationRules: TaskInvalidation? = nil,
        priorityLevel: TaskPriorityLevel = .essential
    ) {
        guard let riferimento = sinistro.riferimento else { return }
        
        // Standardizza titolo basato su actionType
        let standardizedTitle = standardizeTaskTitle(
            actionType: actionType,
            originalTitle: title,
            sinistro: sinistro
        )
        
        var finalMetadata: [String: AnyCodable] = [
            "fromClaimEngine": AnyCodable(true),
            "isUrgent": AnyCodable(isUrgent)
        ]
        
        // Merge con metadata aggiuntivi se forniti
        if let additionalMetadata = metadata {
            for (key, value) in additionalMetadata {
                finalMetadata[key] = value
            }
        }
        
        // Aggiungi info per tasti contestuali
        if let action = actionType {
            finalMetadata["actionType"] = AnyCodable(action.rawValue)
            
            // Aggiungi dati contestuali per tasti
            switch action {
            case .call:
                if let phone = sinistro.telefonoAssicurato, !phone.isEmpty {
                    finalMetadata["phoneNumber"] = AnyCodable(phone)
                }
            case .email, .reply:
                if let email = sinistro.emailAssicurato, !email.isEmpty {
                    finalMetadata["emailAddress"] = AnyCodable(email)
                }
            default:
                break
            }
        }
        
        let task = DailyTask(
            title: standardizedTitle,
            description: description ?? "",
            type: .sinistroActivity,
            sinistroID: riferimento,
            priority: priority,
            deadline: deadline,
            scheduledTime: scheduledTime,
            estimatedDuration: taskManager.getEstimatedDuration(for: .sinistroActivity, sinistro: sinistro),
            metadata: finalMetadata,
            sourceDiarioEntryId: diarioEntryId,
            phoneNumber: sinistro.telefonoAssicurato,
            email: sinistro.emailAssicurato,
            actionType: actionType,
            goal: goal,
            invalidationRules: invalidationRules,
            priorityLevel: priorityLevel
        )
        
        taskManager.addTask(task)
        print("[ClaimEngine] 📋 Task creata: \(standardizedTitle) [action: \(actionType?.rawValue ?? "none"), goal: \(goal != nil), invalidation: \(invalidationRules != nil)]")
    }
    
    /// Standardizza il titolo della task basandosi sul tipo di azione
    /// Es: "Rispondere a sollecito RIF123" → "Rispondere" (riferimento fuori dal titolo)
    private func standardizeTaskTitle(
        actionType: TaskActionType?,
        originalTitle: String,
        sinistro: Sinistro
    ) -> String {
        guard let action = actionType else { return originalTitle }
        
        // Estrai complemento oggetto dal titolo originale
        let complement = extractComplement(from: originalTitle)
        
        let verb = action.verb
        
        if let comp = complement, !comp.isEmpty {
            return "\(verb) \(comp)"
        } else {
            return verb
        }
    }
    
    /// Estrae il complemento oggetto da un titolo
    /// Es: "Sollecitare documentazione" -> "documentazione"
    /// Es: "Chiamare assicurato" -> "assicurato"
    private func extractComplement(from title: String) -> String? {
        let verbs = [
            "chiamare", "scrivere", "rispondere", "sollecitare",
            "verificare", "richiedere", "partecipare", "controllare",
            "chiudere", "inviare"
        ]
        
        let lower = title.lowercased()
        for verb in verbs {
            if lower.starts(with: verb) {
                let complement = String(title.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
                return complement.isEmpty ? nil : complement
            }
        }
        
        return nil
    }
    
    private func notifyAndDownload(riferimento: String) {
        NotificationService.shared.sendNotification(
            title: "assegnazione perito",
            body: "è stato assegnato il sinistro \(riferimento)"
        )
        Task {
            await ClaimSyncService.shared.downloadClaimFolder(riferimento: riferimento)
        }
    }
    
    private func logEventToDiary(_ event: any ClaimEvent, decision: ClaimEngineDecision) {
        // Per ora log solo su console
        // In futuro integreremo con DiarioService
        let eventType = String(describing: type(of: event))
        print("[ClaimEngine] 📔 Diario: \(eventType) → \(decision.actionType) | \(decision.reason)")
    }
    
    private func sendNotification(sinistro: Sinistro, title: String, body: String) {
        // Delega a NotificationService
        NotificationService.shared.sendNotification(
            title: title,
            body: body,
            userInfo: ["sinistroID": sinistro.riferimento ?? ""]
        )
    }
    
    /// Marca un'email come letta
    private func markEmailAsRead(emailId: String) async {
        // Usa MailViewModel per marcare come letta
        await MainActor.run {
            MailViewModel.shared.markEmailAsRead(emailId: emailId)
        }
    }
    
    // MARK: - Priority Calculation Helpers
    
    /// Conta sinistri chiusi nel mese corrente (solo utente loggato)
    private func getCurrentMonthClosuresCount() async -> Int {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return 0
        }
        
        // Filtra per utente loggato
        let currentUserEmail = GoogleAuthService.shared.userEmail?.lowercased()
        
        var predicates: [NSPredicate] = [
            NSPredicate(format: "stato == %@", StatoManager.StatoSinistro.chiusa.descrizione),
            NSPredicate(format: "dataChiusura >= %@ AND dataChiusura < %@", monthStart as NSDate, monthEnd as NSDate)
        ]
        
        if let userEmail = currentUserEmail {
            predicates.append(
                NSPredicate(format: "assignedToUserEmail ==[c] %@ OR ownerEmail ==[c] %@", userEmail, userEmail)
            )
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        return (try? context.count(for: request)) ?? 0
    }
    
    /// Determina se serve accelerare le chiusure (media gestione > 20 giorni, solo utente loggato)
    private func shouldAccelerateClosures() async -> Bool {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        
        let calendar = Calendar.current
        let now = Date()
        
        // Sinistri chiusi negli ultimi 3 mesi
        guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) else {
            return false
        }
        
        // Filtra per utente loggato
        let currentUserEmail = GoogleAuthService.shared.userEmail?.lowercased()
        
        var predicates: [NSPredicate] = [
            NSPredicate(format: "stato == %@", StatoManager.StatoSinistro.chiusa.descrizione),
            NSPredicate(format: "dataChiusura >= %@", threeMonthsAgo as NSDate)
        ]
        
        if let userEmail = currentUserEmail {
            predicates.append(
                NSPredicate(format: "assignedToUserEmail ==[c] %@ OR ownerEmail ==[c] %@", userEmail, userEmail)
            )
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        guard let recentlyClosed = try? context.fetch(request), !recentlyClosed.isEmpty else {
            return false
        }
        
        // Calcola media giorni di gestione
        var totalDays = 0
        var count = 0
        
        for sinistro in recentlyClosed {
            let startDate = sinistro.dataAssegnazione ?? sinistro.dataIncarico
            guard let start = startDate, let end = sinistro.dataChiusura else {
                continue
            }
            
            let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            totalDays += days
            count += 1
        }
        
        guard count > 0 else { return false }
        
        let averageDays = Double(totalDays) / Double(count)
        return averageDays > 20.0 // Obiettivo: 20 giorni
    }
}

