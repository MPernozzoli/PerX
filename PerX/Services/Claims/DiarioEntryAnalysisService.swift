import Foundation
import CoreData

/// Servizio per analizzare le entry del diario inserite manualmente dall'utente
/// e generare task automaticamente
@MainActor
class DiarioEntryAnalysisService {
    static let shared = DiarioEntryAnalysisService()
    
    private let taskManager = TaskManager.shared
    private let statoManager = StatoManager.shared
    private let aiService = AppleIntelligenceService.shared
    private let communicationAnalysisService = CommunicationAnalysisService.shared
    
    private init() {}
    
    /// Analizza una entry del diario e genera task/aggiorna stato se necessario
    func analyzeDiarioEntry(
        _ entry: DiarioEntry,
        sinistro: Sinistro,
        context: NSManagedObjectContext
    ) async {
        guard entry.tipo == .notaUtente else { return }
        
        let text = entry.contenutoCompleto ?? entry.riassunto ?? entry.testo
        let lowercased = text.lowercased()
        
        var aiHandledTask = false
        var aiHandledState = false
        
        // Analisi AI con threshold
        if let aiResult = await analyzeWithAI(entry: entry, sinistro: sinistro) {
            // Stato
            if let stateProposal = aiResult.stateProposal {
                if stateProposal.confidence >= 0.7 {
                    await updateSinistroState(
                        sinistro: sinistro,
                        newState: stateProposal.newState,
                        context: context
                    )
                    aiHandledState = true
                } else if stateProposal.confidence >= 0.4 {
                    notifyPendingProposal(entry: entry, sinistro: sinistro, stateProposal: stateProposal, taskProposals: aiResult.taskProposals)
                }
            }
            
            // Task
            let highTasks = aiResult.taskProposals.filter { $0.confidence >= 0.7 }
            if !highTasks.isEmpty {
                for task in highTasks {
                    await createTaskFromAIProposal(
                        entry: entry,
                        sinistro: sinistro,
                        proposal: task,
                        context: context
                    )
                }
                aiHandledTask = true
            }
            
            // Se ci sono solo task da confermare (0.4-0.7) e nessuno già notificato, notifica
            let confirmTasks = aiResult.taskProposals.filter { $0.confidence >= 0.4 && $0.confidence < 0.7 }
            if !confirmTasks.isEmpty && !aiHandledTask {
                notifyPendingProposal(entry: entry, sinistro: sinistro, stateProposal: aiResult.stateProposal?.confidence ?? 0.0 >= 0.4 ? aiResult.stateProposal : nil, taskProposals: confirmTasks)
            }
        }
        
        // 1. Estrai scadenze/deadline
        if let deadline = extractDeadline(from: text, referenceDate: entry.timestamp) {
            await createTaskFromEntry(
                entry: entry,
                sinistro: sinistro,
                text: text,
                deadline: deadline,
                context: context
            )
            aiHandledTask = true
        }
        
        // 2. Rileva azioni che richiedono task
        if !aiHandledTask, shouldCreateTask(from: lowercased) {
            await createTaskFromEntry(
                entry: entry,
                sinistro: sinistro,
                text: text,
                deadline: nil,
                context: context
            )
        }
        
        // 3. Rileva aggiornamenti di stato
        if !aiHandledState, let newState = extractStateUpdate(from: lowercased) {
            await updateSinistroState(
                sinistro: sinistro,
                newState: newState,
                context: context
            )
        }
    }
    
    // MARK: - Deadline Extraction
    
    /// Estrae una scadenza dal testo (es. "entro martedì", "entro il 15/01", "entro 3 giorni")
    private func extractDeadline(from text: String, referenceDate: Date) -> Date? {
        let calendar = Calendar.current
        let lowercased = text.lowercased()
        
        // Pattern per "entro [giorno della settimana]"
        let dayNames = [
            "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato", "domenica",
            "lunedi", "martedi", "mercoledi", "giovedi", "venerdi"
        ]
        
        for (index, dayName) in dayNames.enumerated() {
            let pattern = "entro\\s+\(dayName)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: lowercased, options: [], range: NSRange(location: 0, length: lowercased.utf16.count)) != nil {
                // Trova il prossimo giorno della settimana
                let weekday = (index % 7) + 1 // 1 = domenica, 2 = lunedì, etc.
                let todayWeekday = calendar.component(.weekday, from: referenceDate)
                var daysToAdd = (weekday - todayWeekday + 7) % 7
                if daysToAdd == 0 { daysToAdd = 7 } // Se è oggi, prendi la prossima settimana
                return calendar.date(byAdding: .day, value: daysToAdd, to: referenceDate)
            }
        }
        
        // Pattern per "entro [numero] giorni"
        if let regex = try? NSRegularExpression(pattern: "entro\\s+(\\d+)\\s+giorni?", options: .caseInsensitive),
           let match = regex.firstMatch(in: lowercased, options: [], range: NSRange(location: 0, length: lowercased.utf16.count)),
           let daysRange = Range(match.range(at: 1), in: lowercased),
           let days = Int(lowercased[daysRange]) {
            return calendar.date(byAdding: .day, value: days, to: referenceDate)
        }
        
        // Pattern per "entro il [data]"
        let datePatterns = [
            "entro\\s+il\\s+(\\d{1,2})/(\\d{1,2})",
            "entro\\s+il\\s+(\\d{1,2})/(\\d{1,2})/(\\d{4})",
            "entro\\s+il\\s+(\\d{1,2})\\s+(gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre)",
            "entro\\s+il\\s+(\\d{1,2})\\s+(gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre)\\s+(\\d{4})"
        ]
        
        for pattern in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lowercased, options: [], range: NSRange(location: 0, length: lowercased.utf16.count)) {
                // Estrai e parsa la data
                if let date = parseDateFromMatch(match: match, text: lowercased, referenceDate: referenceDate) {
                    return date
                }
            }
        }
        
        return nil
    }
    
    private func parseDateFromMatch(match: NSTextCheckingResult, text: String, referenceDate: Date) -> Date? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: referenceDate)
        
        if match.numberOfRanges >= 3 {
            if let dayRange = Range(match.range(at: 1), in: text),
               let monthRange = Range(match.range(at: 2), in: text),
               let day = Int(text[dayRange]),
               let month = Int(text[monthRange]) {
                var components = DateComponents(year: year, month: month, day: day)
                if match.numberOfRanges >= 4,
                   let yearRange = Range(match.range(at: 3), in: text),
                   let parsedYear = Int(text[yearRange]) {
                    components.year = parsedYear
                }
                return calendar.date(from: components)
            }
        }
        
        // Pattern con nome mese
        let monthNames = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno",
                         "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
        
        if match.numberOfRanges >= 3,
           let dayRange = Range(match.range(at: 1), in: text),
           let monthNameRange = Range(match.range(at: 2), in: text),
           let day = Int(text[dayRange]) {
            let monthName = String(text[monthNameRange])
            if let monthIndex = monthNames.firstIndex(where: { $0.lowercased() == monthName.lowercased() }) {
                var components = DateComponents(year: year, month: monthIndex + 1, day: day)
                if match.numberOfRanges >= 4,
                   let yearRange = Range(match.range(at: 3), in: text),
                   let parsedYear = Int(text[yearRange]) {
                    components.year = parsedYear
                }
                return calendar.date(from: components)
            }
        }
        
        return nil
    }
    
    // MARK: - Task Detection
    
    /// Determina se il testo richiede la creazione di un task
    private func shouldCreateTask(from text: String) -> Bool {
        let taskKeywords = [
            "ricontattare", "chiamare", "telefonare", "scrivere", "inviare",
            "verificare", "controllare", "revisionare", "preparare", "completare",
            "chiudere", "gestire", "seguire", "monitorare", "sollecitare"
        ]
        
        return taskKeywords.contains { text.contains($0) }
    }
    
    // MARK: - State Update Detection
    
    /// Estrae aggiornamenti di stato dal testo
    private func extractStateUpdate(from text: String) -> StatoManager.StatoSinistro? {
        // Pattern per "comunico esito" -> esito comunicato
        if text.contains("comunico esito") || text.contains("comunicato esito") || text.contains("comunicazione esito") {
            return .esitoDaComunicare
        }
        
        // Pattern per "chiamo agenzia e comunico esito" -> esito comunicato
        if text.contains("chiamo agenzia") && text.contains("comunico esito") {
            return .esitoDaComunicare
        }
        
        // Pattern per "atto inviato" -> atto inviato
        if text.contains("atto inviato") || text.contains("inviato atto") {
            return .attoInviato
        }
        
        // Pattern per "atto restituito" -> atto restituito
        if text.contains("atto restituito") || text.contains("restituito atto") {
            return .attoRicevutoSottoscritto
        }
        
        // Pattern per "chiuso" -> chiusa
        if text.contains("chiuso") || text.contains("chiusura") {
            return .chiusa
        }
        
        return nil
    }
    
    // MARK: - Task Creation
    
    private func createTaskFromEntry(
        entry: DiarioEntry,
        sinistro: Sinistro,
        text: String,
        deadline: Date?,
        context: NSManagedObjectContext
    ) async {
        guard let riferimento = sinistro.riferimento else { return }
        
        // Genera titolo e descrizione dal testo
        let title = generateTaskTitle(from: text, riferimento: riferimento)
        let description = text
        
        // Calcola priorità
        let priority: Double
        if let deadline = deadline {
            let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
            if daysUntil <= 1 {
                priority = 0.9
            } else if daysUntil <= 3 {
                priority = 0.7
            } else {
                priority = 0.5
            }
        } else {
            priority = taskManager.calculateBasePriority(for: sinistro)
        }
        
        let task = DailyTask(
            title: title,
            description: description,
            type: .manual,
            sinistroID: riferimento,
            priority: priority,
            deadline: deadline,
            estimatedDuration: taskManager.getEstimatedDuration(for: .manual),
            metadata: [
                "sourceDiarioEntryId": AnyCodable(entry.id.uuidString),
                "sourceType": AnyCodable("diarioEntry")
            ],
            sourceDiarioEntryId: entry.id
        )
        
        taskManager.addTask(task)
        
        // Aggiorna l'entry con il task generato nel sinistro
        var entries = sinistro.diarioArray
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].generatedTaskId = task.id
            sinistro.diarioArray = entries
        }
        
        try? context.save()
        
        print("[DiarioEntryAnalysis] ✅ Task generata da entry diario: \(title)")
    }
    
    private func generateTaskTitle(from text: String, riferimento: String? = nil) -> String {
        let lowercased = text.lowercased()
        
        // Estrai azione principale senza riferimento sinistro (verrà aggiunto nella UI)
        if lowercased.contains("ricontattare") {
            return "Ricontattare cliente"
        } else if lowercased.contains("chiamare agenzia") {
            return "Chiamare agenzia"
        } else if lowercased.contains("verificare") {
            return "Verificare documentazione"
        } else if lowercased.contains("preparare atto") {
            return "Preparare atto"
        } else if lowercased.contains("chiudere") {
            return "Chiudere sinistro"
        } else {
            // Usa le prime parole del testo come titolo
            let words = text.components(separatedBy: .whitespacesAndNewlines).prefix(5)
            return words.joined(separator: " ")
        }
    }
    
    // MARK: - State Update
    
    private func updateSinistroState(
        sinistro: Sinistro,
        newState: StatoManager.StatoSinistro,
        context: NSManagedObjectContext
    ) async {
        guard let riferimento = sinistro.riferimento else { return }

        let oldStateId = statoManager.getStatoId(fromDescrizione: sinistro.stato ?? "")
        let oldStateEnum = oldStateId.flatMap { StatoManager.StatoSinistro(rawValue: $0) }
        
        sinistro.stato = newState.descrizione
        sinistro.statoDetail = .none
        
        do {
            try context.save()
            print("[DiarioEntryAnalysis] ✅ Stato sinistro \(riferimento) aggiornato a \(newState.descrizione)")
            
            NotificationCenter.default.post(
                name: .sinistroStatoChanged,
                object: nil,
                userInfo: [
                    "sinistroID": riferimento,
                    "oldState": oldStateEnum as Any,
                    "newState": newState
                ]
            )
        } catch {
            print("[DiarioEntryAnalysis] ❌ Errore aggiornamento stato: \(error)")
        }
    }

// MARK: - AI Proposals

struct AIStateProposal {
    let newState: StatoManager.StatoSinistro
    let confidence: Double
    let reason: String
}

struct AITaskProposal {
    let title: String
    let description: String
    let deadline: Date?
    let taskType: String?
    let confidence: Double
    let reason: String
}

private struct AIProposalResult {
    let stateProposal: AIStateProposal?
    let taskProposals: [AITaskProposal]
}

private func analyzeWithAI(entry: DiarioEntry, sinistro: Sinistro) async -> AIProposalResult? {
    let text = entry.contenutoCompleto ?? entry.riassunto ?? entry.testo
    
    let analysis = await communicationAnalysisService.analyzeCommunication(
        subject: entry.titolo,
        body: text,
        senderEmail: nil,
        hasAttachments: false,
        attachmentTypes: [],
        sinistroID: sinistro.riferimento
    )
    
    guard analysis.requiresAction else { return nil }
    
    var stateProposal: AIStateProposal? = nil
    var taskProposals: [AITaskProposal] = []
    
    for action in analysis.suggestedActions {
        switch action.type {
        case .updateState:
            if let newStateString = action.metadata["newState"]?.value as? String,
               let newState = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == newStateString }) {
                stateProposal = AIStateProposal(
                    newState: newState,
                    confidence: 0.8,
                    reason: action.description
                )
            }
        case .createTask:
            let proposal = AITaskProposal(
                title: action.title,
                description: action.description,
                deadline: action.deadline,
                taskType: action.metadata["taskType"]?.value as? String,
                confidence: 0.7,
                reason: action.description
            )
            taskProposals.append(proposal)
        default:
            continue
        }
    }
    
    if stateProposal == nil && taskProposals.isEmpty {
        return nil
    }
    
    return AIProposalResult(stateProposal: stateProposal, taskProposals: taskProposals)
}

private func notifyPendingProposal(entry: DiarioEntry, sinistro: Sinistro, stateProposal: AIStateProposal?, taskProposals: [AITaskProposal]) {
    NotificationCenter.default.post(
        name: .aiProposalForDiarioEntry,
        object: nil,
        userInfo: [
            "entryId": entry.id,
            "sinistroId": sinistro.riferimento ?? "",
            "stateProposal": stateProposal.map {
                [
                    "stateId": $0.newState.rawValue,
                    "confidence": $0.confidence,
                    "reason": $0.reason
                ]
            } as Any,
            "taskProposals": taskProposals.map {
                [
                    "title": $0.title,
                    "description": $0.description,
                    "deadline": $0.deadline?.timeIntervalSince1970 as Any,
                    "taskType": $0.taskType as Any,
                    "confidence": $0.confidence,
                    "reason": $0.reason
                ]
            }
        ]
    )
}

private func createTaskFromAIProposal(
    entry: DiarioEntry,
    sinistro: Sinistro,
    proposal: AITaskProposal,
    context: NSManagedObjectContext
) async {
    guard let riferimento = sinistro.riferimento else { return }
    
    let task = DailyTask(
        title: proposal.title,
        description: proposal.description,
        type: .aiGenerated,
        sinistroID: riferimento,
        priority: taskManager.calculateBasePriority(for: sinistro),
        deadline: proposal.deadline,
        estimatedDuration: taskManager.getEstimatedDuration(for: .aiGenerated, sinistro: sinistro),
        metadata: [
            "ai_proposal": AnyCodable(true),
            "ai_confidence": AnyCodable(proposal.confidence),
            "sourceDiarioEntryId": AnyCodable(entry.id.uuidString),
            "taskType": AnyCodable(proposal.taskType ?? "")
        ],
        sourceDiarioEntryId: entry.id
    )
    
    taskManager.addTask(task)
}
}

// MARK: - Notifications
extension Notification.Name {
    static let aiProposalForDiarioEntry = Notification.Name("aiProposalForDiarioEntry")
}

