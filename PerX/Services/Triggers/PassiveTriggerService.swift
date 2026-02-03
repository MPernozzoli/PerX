import Foundation
import CoreData
import Combine

/// Tipo di trigger passivo
enum PassiveTriggerType: String, Codable {
    case attoInviato = "atto_inviato" // 7 giorni senza risposta
    case attoFollowUp = "atto_followup" // 7 giorni dopo follow-up
    case documentazioneRichiesta = "documentazione_richiesta" // 5 giorni
    case videoperiziaRichiesta = "videoperizia_richiesta" // 3 giorni
}

// MARK: - CoreData stub per TriggerState (se l'entità esiste nel modello, questa classe la rappresenta)
@objc(TriggerState)
class TriggerState: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var sinistroID: String?
    @NSManaged var triggerType: String?
    @NSManaged var startDate: Date?
    @NSManaged var isActive: Bool
    @NSManaged var lastCheckDate: Date?
    @NSManaged var timeoutDays: Int16
    @NSManaged var sinistro: Sinistro?
}

/// Servizio per gestire trigger passivi basati su timeout e scadenze
@MainActor
class PassiveTriggerService: ObservableObject {
    static let shared = PassiveTriggerService()
    
    @Published var isMonitoring = false
    
    private let taskManager = TaskManager.shared
    private let analysisService = CommunicationAnalysisService.shared
    private var monitoringTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private let context: NSManagedObjectContext
    
    private init() {
        self.context = PersistenceController.shared.container.viewContext
        // Ritarda startMonitoring per evitare (a) modifiche @Published durante build view,
        // (b) sovrapposizione con TaskManager init (validateAndCleanup, generateBaseTasks)
        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s delay
            await self?.startMonitoring()
        }
        
        setupStateChangeObserver()
    }
    
    /// Osserva i cambi di stato per disattivare trigger non più rilevanti
    private func setupStateChangeObserver() {
        NotificationCenter.default.publisher(for: .sinistroStatoChanged)
            .sink { [weak self] notification in
                Task { @MainActor in
                    guard let userInfo = notification.userInfo,
                          let sinistroID = userInfo["sinistroID"] as? String,
                          let newState = userInfo["newState"] as? StatoManager.StatoSinistro else { return }
                    
                    self?.handleStateChange(sinistroID: sinistroID, newState: newState)
                }
            }
            .store(in: &cancellables)
    }
    
    /// Gestisce i cambi di stato per disattivare trigger non più rilevanti
    private func handleStateChange(sinistroID: String, newState: StatoManager.StatoSinistro) {
        // Quando l'atto viene ricevuto firmato, disattiva tutti i trigger relativi all'atto
        let statiPostAtto: Set<StatoManager.StatoSinistro> = [
            .attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa
        ]
        
        if statiPostAtto.contains(newState) {
            deactivateTrigger(sinistroID: sinistroID, type: .attoInviato)
            deactivateTrigger(sinistroID: sinistroID, type: .attoFollowUp)
            print("[PassiveTrigger] 🔕 Trigger atto disattivati per \(sinistroID) (stato: \(newState.descrizione))")
        }
        
        // Se il sinistro passa a stato attivo di gestione, disattiva trigger documentazione
        let statiGestione: Set<StatoManager.StatoSinistro> = [
            .inGestione, .inGestioneDocumentale, .inGestioneVideoperizia,
            .attoDaInviare, .esitoDaComunicare
        ]
        
        if statiGestione.contains(newState) {
            deactivateTrigger(sinistroID: sinistroID, type: .documentazioneRichiesta)
        }
        
        // Se la videoperizia viene fissata, disattiva trigger videoperizia
        if newState == .videoperiziaFissata {
            deactivateTrigger(sinistroID: sinistroID, type: .videoperiziaRichiesta)
        }
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        
        Task {
            await CPUThrottler.shared.runWithThrottle { await checkAllTriggers() }
        }
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await CPUThrottler.shared.runWithThrottle { await self?.checkAllTriggers() }
            }
        }
        
        print("[PassiveTrigger] ✅ Monitoraggio avviato")
    }
    
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        isMonitoring = false
        print("[PassiveTrigger] ⏹️ Monitoraggio fermato")
    }
    
    // MARK: - Trigger Checks
    
    private func checkAllTriggers() async {
        print("[PassiveTrigger] 🔍 Controllo trigger passivi...")
        
        let sinistri = fetchActiveSinistri()
        
        for sinistro in sinistri {
            await checkSinistroTriggers(sinistro: sinistro)
        }
        
        print("[PassiveTrigger] ✅ Controllo completato")
    }
    
    private func checkSinistroTriggers(sinistro: Sinistro) async {
        guard let riferimento = sinistro.riferimento else { return }
        
        let entries = sinistro.diarioArray.sorted { $0.timestamp < $1.timestamp }
        
        // Verifica se ci sono contestazioni attive
        let hasActiveContestation = hasActiveContestation(in: entries)
        
        // 1. Controlla atto inviato (7 giorni senza risposta)
        await checkAttoInviatoTrigger(
            sinistro: sinistro,
            entries: entries,
            hasActiveContestation: hasActiveContestation
        )
        
        // 2. Controlla follow-up atto (7 giorni dopo follow-up)
        await checkAttoFollowUpTrigger(
            sinistro: sinistro,
            entries: entries,
            hasActiveContestation: hasActiveContestation
        )
        
        // 3. Controlla documentazione richiesta (5 giorni)
        await checkDocumentazioneRichiestaTrigger(
            sinistro: sinistro,
            entries: entries
        )
        
        // 4. Controlla videoperizia richiesta (3 giorni)
        await checkVideoperiziaRichiestaTrigger(
            sinistro: sinistro,
            entries: entries
        )
    }
    
    // MARK: - Specific Triggers
    
    private func checkAttoInviatoTrigger(
        sinistro: Sinistro,
        entries: [DiarioEntry],
        hasActiveContestation: Bool
    ) async {
        // Se lo stato è già "atto ricevuto sottoscritto" o successivi, non creare trigger
        let statiPostAtto: Set<StatoManager.StatoSinistro> = [
            .attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa, .revocata, .annullata
        ]
        if let statoDesc = sinistro.stato,
           let statoEnum = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == statoDesc }),
           statiPostAtto.contains(statoEnum) {
            return
        }
        
        // Cerca entry "atto inviato"
        guard let attoInviatoEntry = entries.last(where: { entry in
            let text = (entry.riassunto ?? entry.testo).lowercased()
            return text.contains("atto inviato") || text.contains("atto da inviare")
        }) else { return }
        
        // Verifica se è passato più di 7 giorni
        let daysSince = Calendar.current.dateComponents([.day], from: attoInviatoEntry.timestamp, to: Date()).day ?? 0
        
        guard daysSince >= 7 else { return }
        
        // Verifica se c'è già una risposta dopo l'atto inviato
        let hasResponse = entries.contains { entry in
            entry.timestamp > attoInviatoEntry.timestamp &&
            (entry.tipo == .email || entry.tipo == .whatsapp) &&
            !isOutgoingMessage(entry: entry)
        }
        
        guard !hasResponse else {
            // C'è stata risposta, disattiva trigger se attivo
            deactivateTrigger(sinistroID: sinistro.riferimento ?? "", type: .attoInviato)
            return
        }
        
        // Blocca se c'è contestazione attiva
        guard !hasActiveContestation else {
            print("[PassiveTrigger] ⏸️ Follow-up atto bloccato per contestazione attiva")
            return
        }
        
        // Verifica se il trigger è già stato attivato
        if let triggerState = getTriggerState(sinistroID: sinistro.riferimento ?? "", type: PassiveTriggerType.attoInviato),
           triggerState.isActive {
            // Già attivato, non fare nulla
            return
        }
        
        // Genera task follow-up
        await generateFollowUpTask(
            sinistro: sinistro,
            triggerType: .attoInviato,
            daysSince: daysSince,
            draftMessage: generateAttoFollowUpDraft(sinistro: sinistro)
        )
        
        // Salva stato trigger
        saveTriggerState(
            sinistroID: sinistro.riferimento ?? "",
            type: PassiveTriggerType.attoInviato,
            startDate: attoInviatoEntry.timestamp
        )
    }
    
    private func checkAttoFollowUpTrigger(
        sinistro: Sinistro,
        entries: [DiarioEntry],
        hasActiveContestation: Bool
    ) async {
        guard let riferimento = sinistro.riferimento else { return }
        
        // Se lo stato è già "atto ricevuto sottoscritto" o successivi, non creare trigger
        let statiPostAtto: Set<StatoManager.StatoSinistro> = [
            .attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa, .revocata, .annullata
        ]
        if let statoDesc = sinistro.stato,
           let statoEnum = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == statoDesc }),
           statiPostAtto.contains(statoEnum) {
            return
        }
        
        // Snapshot su MainActor per evitare EXC_BAD_ACCESS (iterazione durante modifiche concorrenti)
        let tasksSnapshot = taskManager.tasks
        
        let followUpTasks = tasksSnapshot.filter { task in
            task.sinistroID == riferimento &&
            task.title.contains("Restiamo in attesa") &&
            task.status == .completed
        }
        
        guard let lastFollowUpTask = followUpTasks.sorted(by: { $0.createdAt > $1.createdAt }).first else {
            return
        }
        
        // Verifica se è passato più di 7 giorni dal follow-up
        let daysSince = Calendar.current.dateComponents([.day], from: lastFollowUpTask.createdAt, to: Date()).day ?? 0
        
        guard daysSince >= 7 else { return }
        
        // Verifica se c'è stata risposta
        let hasResponse = entries.contains { entry in
            entry.timestamp > lastFollowUpTask.createdAt &&
            (entry.tipo == .email || entry.tipo == .whatsapp) &&
            !isOutgoingMessage(entry: entry)
        }
        
        guard !hasResponse else {
            return
        }
        
        // Blocca se c'è contestazione attiva
        guard !hasActiveContestation else {
            return
        }
        
        // Genera task chiusura non concordata
        await generateCloseNonConcordatoTask(sinistro: sinistro)
    }
    
    private func checkDocumentazioneRichiestaTrigger(
        sinistro: Sinistro,
        entries: [DiarioEntry]
    ) async {
        // Cerca entry richiesta documentazione
        guard let docRequestEntry = entries.last(where: { entry in
            let text = (entry.riassunto ?? entry.testo).lowercased()
            return (text.contains("documentazione") || text.contains("foto") || text.contains("allegat")) &&
                   (text.contains("richied") || text.contains("inviat") || text.contains("necessari"))
        }) else { return }
        
        // Verifica se è passato più di 5 giorni
        let daysSince = Calendar.current.dateComponents([.day], from: docRequestEntry.timestamp, to: Date()).day ?? 0
        
        guard daysSince >= 5 else { return }
        
        // Verifica se c'è già una risposta con documentazione
        let hasDocumentationResponse = entries.contains { entry in
            entry.timestamp > docRequestEntry.timestamp &&
            (entry.tipo == .email || entry.tipo == .whatsapp) &&
            entry.contenutoCompleto?.lowercased().contains("allegat") == true
        }
        
        guard !hasDocumentationResponse else { return }
        
        // Verifica se il trigger è già stato attivato
        if let triggerState = getTriggerState(sinistroID: sinistro.riferimento ?? "", type: PassiveTriggerType.documentazioneRichiesta),
           triggerState.isActive {
            return
        }
        
        // Genera task follow-up
        await generateFollowUpTask(
            sinistro: sinistro,
            triggerType: .documentazioneRichiesta,
            daysSince: daysSince,
            draftMessage: generateDocumentazioneFollowUpDraft(sinistro: sinistro)
        )
        
        saveTriggerState(
            sinistroID: sinistro.riferimento ?? "",
            type: PassiveTriggerType.documentazioneRichiesta,
            startDate: docRequestEntry.timestamp
        )
    }
    
    private func checkVideoperiziaRichiestaTrigger(
        sinistro: Sinistro,
        entries: [DiarioEntry]
    ) async {
        // Cerca entry richiesta videoperizia
        guard let videoRequestEntry = entries.last(where: { entry in
            let text = (entry.riassunto ?? entry.testo).lowercased()
            return text.contains("videoperizia") || text.contains("video perizia")
        }) else { return }
        
        // Verifica se è passato più di 3 giorni
        let daysSince = Calendar.current.dateComponents([.day], from: videoRequestEntry.timestamp, to: Date()).day ?? 0
        
        guard daysSince >= 3 else { return }
        
        // Verifica se c'è già una risposta
        let hasResponse = entries.contains { entry in
            entry.timestamp > videoRequestEntry.timestamp &&
            (entry.tipo == .email || entry.tipo == .whatsapp)
        }
        
        guard !hasResponse else { return }
        
        // Verifica se il trigger è già stato attivato
        if let triggerState = getTriggerState(sinistroID: sinistro.riferimento ?? "", type: PassiveTriggerType.videoperiziaRichiesta),
           triggerState.isActive {
            return
        }
        
        // Genera task follow-up
        await generateFollowUpTask(
            sinistro: sinistro,
            triggerType: .videoperiziaRichiesta,
            daysSince: daysSince,
            draftMessage: generateVideoperiziaFollowUpDraft(sinistro: sinistro)
        )
        
        saveTriggerState(
            sinistroID: sinistro.riferimento ?? "",
            type: .videoperiziaRichiesta,
            startDate: videoRequestEntry.timestamp
        )
    }
    
    // MARK: - Contestation Detection
    
    private func hasActiveContestation(in entries: [DiarioEntry]) -> Bool {
        // Cerca entry di contestazione
        let contestationEntries = entries.filter { entry in
            let text = (entry.riassunto ?? entry.testo).lowercased()
            return text.contains("contest") || text.contains("non concord") || text.contains("non accett")
        }
        
        guard !contestationEntries.isEmpty else { return false }
        
        // Verifica se c'è stata una risoluzione
        let lastContestation = contestationEntries.sorted { $0.timestamp > $1.timestamp }.first!
        
        let resolutionEntries = entries.filter { entry in
            entry.timestamp > lastContestation.timestamp &&
            (entry.riassunto ?? entry.testo).lowercased().contains("accordo") ||
            entry.riassunto?.lowercased().contains("risolto") == true ||
            entry.riassunto?.lowercased().contains("nuovo atto") == true
        }
        
        // Se non c'è risoluzione, la contestazione è attiva
        return resolutionEntries.isEmpty
    }
    
    // MARK: - Task Generation
    
    private func generateFollowUpTask(
        sinistro: Sinistro,
        triggerType: PassiveTriggerType,
        daysSince: Int,
        draftMessage: String
    ) async {
        let title: String
        let description: String
        
        switch triggerType {
        case .attoInviato:
            title = "Follow-up: Restiamo in attesa di atto"
            description = "Sono passati \(daysSince) giorni dall'invio dell'atto senza risposta"
        case .documentazioneRichiesta:
            title = "Follow-up: Richiesta documentazione"
            description = "Sono passati \(daysSince) giorni dalla richiesta di documentazione"
        case .videoperiziaRichiesta:
            title = "Follow-up: Richiesta videoperizia"
            description = "Sono passati \(daysSince) giorni dalla richiesta di videoperizia"
        default:
            title = "Follow-up"
            description = "Sono passati \(daysSince) giorni"
        }
        
        let priority = taskManager.calculateBasePriority(for: sinistro)
        
        var metadata: [String: AnyCodable] = [
            "triggerType": AnyCodable(triggerType.rawValue),
            "draftMessage": AnyCodable(draftMessage),
            "daysSince": AnyCodable(daysSince)
        ]
        
        let task = DailyTask(
            title: title,
            description: description,
            type: .aiGenerated,
            sinistroID: sinistro.riferimento,
            priority: priority,
            deadline: Date(),
            estimatedDuration: 1800, // 30 min
            metadata: metadata
        )
        
        taskManager.addTask(task)
        print("[PassiveTrigger] ✅ Task follow-up generato: \(title)")
    }
    
    private func generateCloseNonConcordatoTask(sinistro: Sinistro) async {
        let priority = taskManager.calculateBasePriority(for: sinistro)
        
        let task = DailyTask(
            title: "Chiudere sinistro non concordato",
            description: "Sono passati più di 14 giorni dall'invio dell'atto senza risposta",
            type: .aiGenerated,
            sinistroID: sinistro.riferimento,
            priority: priority,
            deadline: Date(),
            estimatedDuration: 1800,
            metadata: [
                "triggerType": AnyCodable(PassiveTriggerType.attoFollowUp.rawValue)
            ]
        )
        
        taskManager.addTask(task)
        print("[PassiveTrigger] ✅ Task chiusura non concordato generato")
    }
    
    // MARK: - Draft Messages
    
    private func generateAttoFollowUpDraft(sinistro: Sinistro) -> String {
        return """
        Gentile Cliente,
        
        in riferimento al sinistro \(sinistro.riferimento ?? ""), restiamo in attesa della restituzione dell'atto sottoscritto.
        
        Restiamo a disposizione per qualsiasi chiarimento.
        
        Cordiali saluti
        """
    }
    
    private func generateDocumentazioneFollowUpDraft(sinistro: Sinistro) -> String {
        return """
        Gentile Cliente,
        
        in riferimento al sinistro \(sinistro.riferimento ?? ""), restiamo in attesa della documentazione richiesta.
        
        Restiamo a disposizione per qualsiasi chiarimento.
        
        Cordiali saluti
        """
    }
    
    private func generateVideoperiziaFollowUpDraft(sinistro: Sinistro) -> String {
        return """
        Gentile Cliente,
        
        in riferimento al sinistro \(sinistro.riferimento ?? ""), restiamo in attesa di conferma per la videoperizia richiesta.
        
        Restiamo a disposizione per fissare un appuntamento.
        
        Cordiali saluti
        """
    }
    
    // MARK: - Helper Methods
    
    private func isOutgoingMessage(entry: DiarioEntry) -> Bool {
        // Determina se il messaggio è in uscita (da noi)
        // Per ora assumiamo che se non ha sender email o è di tipo sistema, è in uscita
        return entry.tipo == .sistema || entry.emailMessageId == nil
    }
    
    private func fetchActiveSinistri() -> [Sinistro] {
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "stato != %@", StatoManager.StatoSinistro.chiusa.descrizione)
        
        do {
            return try context.fetch(request)
        } catch {
            print("[PassiveTrigger] ❌ Errore fetch sinistri: \(error)")
            return []
        }
    }
    
    private func getTriggerState(sinistroID: String, type: PassiveTriggerType) -> TriggerState? {
        let request = NSFetchRequest<TriggerState>(entityName: "TriggerState")
        request.predicate = NSPredicate(format: "sinistroID == %@ AND triggerType == %@", sinistroID, type.rawValue)
        
        return try? context.fetch(request).first
    }
    
    private func saveTriggerState(
        sinistroID: String,
        type: PassiveTriggerType,
        startDate: Date
    ) {
        let triggerState: TriggerState
        
        if let existing = getTriggerState(sinistroID: sinistroID, type: type) {
            triggerState = existing
        } else {
            triggerState = TriggerState(context: context)
            triggerState.id = UUID()
            triggerState.sinistroID = sinistroID
            triggerState.triggerType = type.rawValue
            
            // Associa al sinistro
            let sinistroRequest = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            sinistroRequest.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
            if let sinistro = try? context.fetch(sinistroRequest).first {
                triggerState.sinistro = sinistro
            }
        }
        
        triggerState.startDate = startDate
        triggerState.isActive = true
        triggerState.lastCheckDate = Date()
        
        // Imposta timeout in base al tipo
        switch type {
        case .attoInviato, .attoFollowUp:
            triggerState.timeoutDays = 7
        case .documentazioneRichiesta:
            triggerState.timeoutDays = 5
        case .videoperiziaRichiesta:
            triggerState.timeoutDays = 3
        }
        
        try? context.save()
    }
    
    private func deactivateTrigger(sinistroID: String, type: PassiveTriggerType) {
        if let triggerState = getTriggerState(sinistroID: sinistroID, type: type) {
            triggerState.isActive = false
            try? context.save()
        }
    }
}

