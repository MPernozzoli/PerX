import Foundation
import Combine

/// Manager centrale per la gestione di tutti i task AI
@MainActor
class AIManager: ObservableObject {
    static let shared = AIManager()
    
    @Published var activeTasks: [AITaskInfo] = []
    @Published var queueSize: Int = 0
    @Published var isProcessing: Bool = false
    @Published var completedTasksHistory: [AITaskInfo] = []
    
    private var taskQueue: [AITask] = []
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var taskResults: [UUID: AIResult] = [:]
    private var taskCallbacks: [UUID: (AIResult) -> Void] = [:]
    private var streamCallbacks: [UUID: (String) -> Void] = [:]
    
    // Gestione rate limiting e cooldown per chiamate Cloud
    private var lastCloudCallTime: Date?
    private let cloudCooldown: TimeInterval = 2.0 // 2 secondi tra chiamate cloud per evitare burst
    private let maxConcurrentCloudTasks = 3
    
    private let resourceMonitor = ResourceMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    private let historyKey = "ai_completed_tasks_history"
    
    private var maxConcurrentTasks: Int {
        let value = UserDefaults.standard.integer(forKey: "ai_max_concurrent_tasks")
        return value > 0 ? value : 5
    }
    
    private var maxConcurrentPrimaryTasks: Int {
        let value = UserDefaults.standard.integer(forKey: "ai_max_primary_tasks")
        return value > 0 ? value : 3
    }
    
    private var maxConcurrentSecondaryTasks: Int {
        let value = UserDefaults.standard.integer(forKey: "ai_max_secondary_tasks")
        return value > 0 ? value : 2
    }
    
    private init() {
        // Ritarda l'avvio per evitare modifiche @Published durante la costruzione della view
        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms delay
            await self?.startProcessing()
            await self?.loadHistory()
        }
    }
    
    // MARK: - Provider Status
    
    /// Stato di un provider AI
    struct ProviderStatus {
        let provider: AIModelProvider
        let available: Bool
        let reason: String?
    }
    
    /// Restituisce lo stato di tutti i provider disponibili
    func getProvidersStatus() -> [ProviderStatus] {
        return AIModelProvider.allCases.map { provider in
            let (available, reason) = getProviderAvailability(provider)
            return ProviderStatus(provider: provider, available: available, reason: reason)
        }
    }
    
    /// Verifica se un provider è disponibile (API pubblica)
    func checkProviderAvailable(_ provider: AIModelProvider) -> Bool {
        return isProviderAvailable(provider)
    }
    
    /// Restituisce i provider disponibili
    func getAvailableProviders() -> [AIModelProvider] {
        return AIModelProvider.allCases.filter { isProviderAvailable($0) }
    }
    
    /// Suggerisce il miglior provider per un tipo di task
    func requestProvider(for taskType: AITaskType, preferred: AIModelProvider? = nil) -> AIModelProvider? {
        // Se il preferito è disponibile e può gestire il task, usalo
        if let preferred = preferred,
           isProviderAvailable(preferred),
           canProviderHandleTaskType(preferred, taskType: taskType) {
            return preferred
        }
        
        // Altrimenti restituisce il primo disponibile dalla catena di fallback
        let fallbacks = getDefaultFallbacks(for: taskType)
        return fallbacks.first { isProviderAvailable($0) && canProviderHandleTaskType($0, taskType: taskType) }
    }
    
    // MARK: - Public API
    
    /// Aggiunge un task alla queue
    func enqueue(_ task: AITask, completion: ((AIResult) -> Void)? = nil, streamCallback: ((String) -> Void)? = nil) -> UUID {
        if let completion = completion {
            taskCallbacks[task.id] = completion
        }
        if let streamCallback = streamCallback {
            streamCallbacks[task.id] = streamCallback
        }
        
        taskQueue.append(task)
        taskQueue.sort { $0.priority.rawValue > $1.priority.rawValue }
        
        updateQueueSize()
        processQueue()
        
        return task.id
    }
    
    /// Ottiene il risultato di un task
    func getResult(for taskID: UUID) -> AIResult? {
        return taskResults[taskID]
    }
    
    // MARK: - Daily Dashboard Summary
    
    /// Genera un breve riassunto testuale per la dashboard (cosa è previsto oggi, notizie studio, messaggio contestuale).
    /// Preferisce Apple Intelligence. completion su main thread.
    func generateDailySummary(
        contextHint: String,
        sinistriInGestione: Int,
        assegnazioniRecenti: Int,
        taskTitles: [String],
        studioNewsTitles: [String],
        completion: @escaping (Result<String, AIError>) -> Void
    ) {
        var prompt = """
        Sei l'assistente di uno studio peritale. Scrivi un breve messaggio (2-4 frasi, tono professionale ma cordiale) per il riquadro \"In sintesi\" della dashboard dell'app. \
        Contesto: \(contextHint). \
        Dati di oggi: \(sinistriInGestione) sinistri in gestione, \(assegnazioniRecenti) nuove assegnazioni dall'ultimo accesso. \
        Task in programma: \(taskTitles.isEmpty ? "nessuna" : taskTitles.prefix(8).joined(separator: "; ")). \
        Notizie studio: \(studioNewsTitles.isEmpty ? "nessuna" : studioNewsTitles.prefix(5).joined(separator: "; ")).
        """
        prompt += " Rispondi SOLO con il testo del messaggio, senza titoli o prefissi."
        
        let task = AITask.dailyDashboardSummary(prompt: prompt)
        enqueue(task) { aiResult in
            Task { @MainActor in
                if aiResult.success {
                    let raw = (aiResult.result?.value as? String) ?? ""
                    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        completion(.success(text))
                    } else {
                        completion(.failure(aiResult.error ?? .modelUnavailable))
                    }
                } else {
                    completion(.failure(aiResult.error ?? .modelUnavailable))
                }
            }
        }
    }
    
    /// Cancella un task
    func cancelTask(_ taskID: UUID) {
        // Rimuovi dalla queue se non ancora eseguito
        taskQueue.removeAll { $0.id == taskID }
        
        // Cancella se in esecuzione
        runningTasks[taskID]?.cancel()
        runningTasks.removeValue(forKey: taskID)
        
        // Aggiorna stato
        if let index = activeTasks.firstIndex(where: { $0.id == taskID }) {
            activeTasks[index].status = .cancelled
            activeTasks.remove(at: index)
        }
        
        taskCallbacks.removeValue(forKey: taskID)
        updateQueueSize()
    }
    
    /// Sospende tutti i task secondari
    func suspendSecondaryTasks() {
        for (index, taskInfo) in activeTasks.enumerated() where taskInfo.task.priority == .secondary {
            if taskInfo.status == .running {
                runningTasks[taskInfo.id]?.cancel()
                activeTasks[index].status = .suspended
            }
        }
    }
    
    /// Riprende i task secondari sospesi
    func resumeSecondaryTasks() {
        for taskInfo in activeTasks where taskInfo.status == .suspended {
            if taskInfo.task.priority == .secondary {
                processTask(taskInfo.task)
            }
        }
    }
    
    // MARK: - Queue Processing
    
    private func startProcessing() {
        // Monitora risorse e adatta il processing
        resourceMonitor.$isLowOnResources
            .sink { [weak self] isLow in
                Task { @MainActor in
                    if isLow {
                        self?.suspendSecondaryTasks()
                    } else {
                        self?.resumeSecondaryTasks()
                    }
                }
            }
            .store(in: &cancellables)
        
        // Processa la queue periodicamente
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.processQueue()
                }
            }
            .store(in: &cancellables)
    }
    
    private func processQueue() {
        // Conta i task effettivamente in esecuzione
        let runningCloudTasks = activeTasks.filter { $0.status == .running && $0.task.preferredProvider == .cloudOpenAI }.count
        let totalRunning = runningTasks.count
        
        // Controlla limiti globali
        guard totalRunning < maxConcurrentTasks else {
            return
        }
        
        guard !taskQueue.isEmpty else { return }
        
        // Rate limiting Cloud: cooldown
        if let lastCall = lastCloudCallTime {
            let elapsed = Date().timeIntervalSince(lastCall)
            if elapsed < cloudCooldown {
                return
            }
        }
        
        // Trova il prossimo task da eseguire
        if let nextTask = taskQueue.first {
            // Se è un task cloud, verifica il limite di 3 simultanei
            if nextTask.preferredProvider == .cloudOpenAI {
                if runningCloudTasks >= maxConcurrentCloudTasks {
                    // Se abbiamo già 3 task cloud, prova a vedere se c'è un task locale in coda da far passare avanti
                    if let localTask = taskQueue.first(where: { $0.preferredProvider != .cloudOpenAI }) {
                        processTask(localTask)
                    }
                    return
                }
                lastCloudCallTime = Date()
            }
            
            processTask(nextTask)
        }
    }
    
    private func processTask(_ task: AITask) {
        // Rimuovi dalla queue
        taskQueue.removeAll { $0.id == task.id }
        updateQueueSize()
        
        // Aggiungi ai task attivi
        var taskInfo = AITaskInfo(task: task)
        taskInfo.status = .running
        taskInfo.startedAt = Date()
        activeTasks.append(taskInfo)
        
        isProcessing = true
        
        // Esegui il task
        let taskExecution = Task {
            let startTime = Date()
            
            // Prepara knowledge (se richiesto) prima di selezionare il provider
            let preparedTask = await prepareTaskWithKnowledge(task)
            
            await MainActor.run {
                if let idx = activeTasks.firstIndex(where: { $0.id == task.id }) {
                    var updatedInfo = AITaskInfo(task: preparedTask)
                    updatedInfo.status = activeTasks[idx].status
                    updatedInfo.startedAt = activeTasks[idx].startedAt
                    updatedInfo.progress = activeTasks[idx].progress
                    activeTasks[idx] = updatedInfo
                }
            }
            
            // Esegui con fallback automatico
            let result = await executeTaskWithFallback(preparedTask)
            let processingTime = Date().timeIntervalSince(startTime)
            
            await MainActor.run {
                // Aggiorna risultato con processing time
                var updatedResult = result
                let finalProvider: AIModelProvider
                
                switch result {
                case .success(let successResult):
                    finalProvider = successResult.provider
                    var metadata = successResult.metadata
                    metadata["processingTime"] = AnyCodable(processingTime)
                    updatedResult = .success(AIResult(
                        taskID: task.id,
                        success: true,
                        provider: successResult.provider,
                        result: successResult.result,
                        metadata: metadata,
                        processingTime: processingTime,
                        attemptedProviders: successResult.attemptedProviders,
                        usedFallback: successResult.usedFallback
                    ))
                case .failure:
                    finalProvider = task.preferredProvider ?? .cloudOpenAI
                }
                
                handleTaskCompletion(taskID: task.id, result: updatedResult, selectedProvider: finalProvider)
            }
        }
        
        runningTasks[task.id] = taskExecution
    }
    
    private func handleTaskCompletion(taskID: UUID, result: Result<AIResult, AIError>, selectedProvider: AIModelProvider) {
        let aiResult: AIResult
        
        switch result {
        case .success(let result):
            aiResult = result
        case .failure(let error):
            // Usa il provider effettivamente selezionato dal routing
            aiResult = AIResult.failure(
                taskID: taskID,
                provider: selectedProvider,
                error: error
            )
        }
        
        // Salva risultato
        taskResults[taskID] = aiResult
        
        // Trova il task originale per tracciare feedback
        let originalTask = activeTasks.first { $0.id == taskID }?.task
        
        // Aggiorna task info
        if let index = activeTasks.firstIndex(where: { $0.id == taskID }) {
            activeTasks[index].status = aiResult.success ? .completed : .failed
            activeTasks[index].completedAt = Date()
            activeTasks[index].result = aiResult
            activeTasks[index].progress = 1.0
        }
        
        // Chiama callback
        if let callback = taskCallbacks[taskID] {
            callback(aiResult)
            taskCallbacks.removeValue(forKey: taskID)
        }
        
        // Rimuovi stream callback
        streamCallbacks.removeValue(forKey: taskID)
        
        // Salva task per feedback e history (solo se successo)
        if aiResult.success, let task = originalTask {
            // Il task viene salvato per permettere feedback successivo
            // La view che mostra il risultato può accedere al task tramite taskID
            
            // Aggiungi alla history delle task completate
            if let taskInfo = activeTasks.first(where: { $0.id == taskID }) {
                completedTasksHistory.append(taskInfo)
                
                // Mantieni solo le ultime 100 task completate
                if completedTasksHistory.count > 100 {
                    completedTasksHistory.removeFirst(completedTasksHistory.count - 100)
                }
                persistHistory()
            }
        }
        
        // Rimuovi dai task in esecuzione
        runningTasks.removeValue(forKey: taskID)
        
        // Rimuovi dai task attivi dopo un po'
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 secondi
            await MainActor.run {
                activeTasks.removeAll { $0.id == taskID && $0.status != .running }
            }
        }
        
        isProcessing = false
        updateQueueSize()
        processQueue()
    }
    
    /// Ottiene il task originale per un risultato (per feedback)
    func getTask(for result: AIResult) -> AITask? {
        return activeTasks.first { $0.id == result.taskID }?.task
    }
    
    /// Ottiene il callback di streaming per un task
    func getStreamCallback(for taskID: UUID) -> ((String) -> Void)? {
        return streamCallbacks[taskID]
    }
    
    // MARK: - Task Execution
    
    /// Costruisce la query per la KB, genera embedding e applica i chunk al task
    private func prepareTaskWithKnowledge(_ task: AITask) async -> AITask {
        guard task.requiresKnowledge else { return task }
        
        var updatedTask = task
        
        let queryText = buildKnowledgeQuery(for: task)
        guard let query = queryText, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return updatedTask
        }
        
        do {
            print("[AIManager] 🧭 RAG: preparo knowledge per task \(task.id) type=\(task.type)")
            print("[AIManager] • Query: \(query.prefix(200))")
            try KnowledgeBaseService.shared.loadKnowledgeIfNeeded()
            let embedding = try await KnowledgeBaseService.shared.embeddingProvider.embed(text: query)
            guard !embedding.isEmpty else { return updatedTask }
            
            let domains = updatedTask.knowledgeDomains ?? KnowledgeDomain.allCases
            let maxResults = updatedTask.maxKnowledgeChunks ?? 6
            let chunks = KnowledgeBaseService.shared.search(
                queryEmbedding: embedding,
                domains: domains,
                maxResults: maxResults
            )
            updatedTask.knowledgeChunks = chunks
            if chunks.isEmpty {
                print("[AIManager] ⚠️ RAG: nessun chunk trovato (domains=\(domains.map { $0.rawValue }))")
            } else {
                print("[AIManager] ✅ RAG: trovati \(chunks.count) chunk (max=\(maxResults), domains=\(domains.map { $0.rawValue }))")
            }
        } catch {
            print("[AIManager] ⚠️ Impossibile preparare knowledge: \(error.localizedDescription)")
        }
        
        return updatedTask
    }
    
    /// Deriva una query testuale per la KB in base al tipo di task e ai parametri
    private func buildKnowledgeQuery(for task: AITask) -> String? {
        if let override = task.knowledgeQueryOverride, !override.isEmpty {
            return override
        }
        
        switch task.type {
        case .emailSummary:
            let subject = task.parameters["subject"]?.value as? String ?? ""
            let body = task.parameters["body"]?.value as? String ?? ""
            return [subject, body]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .textAnalysis:
            return task.parameters["text"]?.value as? String
        case .textGeneration, .chat:
            if let input = task.parameters["inputText"]?.value as? String {
                return input
            }
            return task.parameters["prompt"]?.value as? String
        case .documentAnalysis, .documentExtraction, .imageAnalysis:
            if let customPrompt = task.parameters["prompt"]?.value as? String, !customPrompt.isEmpty {
                return customPrompt
            }
            if let sinistro = task.parameters["sinistroID"]?.value as? String, !sinistro.isEmpty {
                return "Analisi sinistro \(sinistro)"
            }
            return nil
        case .guardrailing:
            return task.parameters["content"]?.value as? String
        }
    }
    
    private func executeTask(_ task: AITask) async -> Result<AIResult, AIError> {
        return await executeTaskWithFallback(task)
    }
    
    /// Esegue un task con fallback automatico su provider alternativi
    private func executeTaskWithFallback(_ task: AITask) async -> Result<AIResult, AIError> {
        var providersToTry: [AIModelProvider] = []
        
        // 1. Provider preferito (se specificato)
        if let preferred = task.preferredProvider {
            providersToTry.append(preferred)
        }
        
        // 2. Fallback specificati dal task
        if task.allowFallback, let fallbacks = task.fallbackProviders {
            providersToTry.append(contentsOf: fallbacks.filter { !providersToTry.contains($0) })
        }
        
        // 3. Fallback standard basato sul tipo di task
        if task.allowFallback {
            providersToTry.append(contentsOf: getDefaultFallbacks(for: task.type)
                .filter { !providersToTry.contains($0) })
        }
        
        // Se non abbiamo provider, usa quelli di default per il tipo
        if providersToTry.isEmpty {
            providersToTry = getDefaultFallbacks(for: task.type)
        }
        
        var attemptedProviders: [AIModelProvider] = []
        var lastError: AIError?
        
        print("[AIManager] 🔄 Fallback chain per task \(task.type): \(providersToTry.map { $0.rawValue })")
        
        for provider in providersToTry {
            // Verifica disponibilità
            guard isProviderAvailable(provider) else {
                print("[AIManager] ⏭️ Provider \(provider.rawValue) non disponibile, salto")
                continue
            }
            
            // Verifica compatibilità con tipo di task
            guard canProviderHandleTaskType(provider, taskType: task.type) else {
                print("[AIManager] ⏭️ Provider \(provider.rawValue) non può gestire \(task.type.rawValue), salto")
                continue
            }
            
            attemptedProviders.append(provider)
            print("[AIManager] 🎯 Tento provider: \(provider.rawValue)")
            
            // Esegui con questo provider
            let result = await executeTaskWithProvider(task, provider: provider)
            
            switch result {
            case .success(var aiResult):
                let usedFallback = attemptedProviders.count > 1
                if usedFallback {
                    print("[AIManager] ✅ Fallback riuscito con \(provider.rawValue) dopo aver provato: \(attemptedProviders.dropLast().map { $0.rawValue })")
                } else {
                    print("[AIManager] ✅ Provider primario \(provider.rawValue) OK")
                }
                
                // Crea nuovo risultato con info fallback
                let finalResult = AIResult(
                    taskID: aiResult.taskID,
                    success: aiResult.success,
                    provider: provider,
                    result: aiResult.result,
                    error: aiResult.error,
                    metadata: aiResult.metadata,
                    processingTime: aiResult.processingTime,
                    timestamp: aiResult.timestamp,
                    attemptedProviders: attemptedProviders,
                    usedFallback: usedFallback
                )
                return .success(finalResult)
                
            case .failure(let error):
                lastError = error
                print("[AIManager] ❌ Provider \(provider.rawValue) fallito: \(error.localizedDescription)")
                
                // Se allowFallback è false, non continuare
                if !task.allowFallback {
                    print("[AIManager] ⛔ Fallback disabilitato, non provo altri provider")
                    break
                }
            }
        }
        
        // Nessun provider è riuscito
        let finalError = lastError ?? .modelUnavailable
        print("[AIManager] ❌ Tutti i provider falliti. Ultimo errore: \(finalError.localizedDescription)")
        return .failure(finalError)
    }
    
    /// Restituisce la catena di fallback standard per un tipo di task
    private func getDefaultFallbacks(for taskType: AITaskType) -> [AIModelProvider] {
        switch taskType {
        case .textGeneration, .chat:
            return [.localText, .localMultimodal, .cloudOpenAI]
        case .documentAnalysis, .imageAnalysis:
            return [.localMultimodal, .cloudOpenAI]
        case .emailSummary, .textAnalysis:
            return [.appleIntelligence, .localText, .cloudOpenAI]
        case .documentExtraction:
            return [.localMultimodal, .cloudOpenAI]
        case .guardrailing:
            return [.appleIntelligence, .cloudOpenAI]
        }
    }
    
    private func executeTaskWithProvider(_ task: AITask, provider: AIModelProvider) async -> Result<AIResult, AIError> {
        // Esegui con il provider appropriato e assicurati che il risultato abbia il provider corretto
        let result: Result<AIResult, AIError>
        
        let wantsStreaming = (task.parameters["stream"]?.value as? Bool) ?? false
        
        switch provider {
        case .localMultimodal:
            result = await MLXVisionService.shared.executeTask(task)
        case .localText:
            result = await LocalModelService.shared.executeTextTask(task)
        case .appleIntelligence:
            result = await AppleAIService.shared.executeTask(task)
        case .cloudOpenAI:
            if wantsStreaming, let streamCb = streamCallbacks[task.id] {
                result = await CloudAIService.shared.executeTaskStreaming(task, streamCallback: streamCb)
            } else {
                result = await CloudAIService.shared.executeTask(task)
            }
        }
        
        // Assicurati che il provider nel risultato corrisponda a quello usato
        switch result {
        case .success(let aiResult):
            // Se il provider nel risultato è diverso, crea un nuovo risultato con il provider corretto
            if aiResult.provider != provider {
                let correctedResult = AIResult(
                    taskID: aiResult.taskID,
                    success: aiResult.success,
                    provider: provider,
                    result: aiResult.result,
                    error: aiResult.error,
                    metadata: aiResult.metadata,
                    processingTime: aiResult.processingTime,
                    timestamp: aiResult.timestamp
                )
                return .success(correctedResult)
            }
            return .success(aiResult)
        case .failure:
            return result
        }
    }
    
    private func selectProvider(for task: AITask) -> AIModelProvider {
        print("[AIManager] 🎯 selectProvider per task: type=\(task.type), preferred=\(task.preferredProvider?.rawValue ?? "nil")")
        
        // Se c'è un provider preferito, verifica se può gestire il tipo di task
        if let preferred = task.preferredProvider {
            let available = isProviderAvailable(preferred)
            let canHandle = canProviderHandleTaskType(preferred, taskType: task.type)
            print("[AIManager] • Provider preferito: \(preferred.rawValue), disponibile: \(available), può gestire: \(canHandle)")
            
            // Per task dalla chat di test (priority .primary e preferredProvider esplicito),
            // usa SEMPRE il provider preferito anche se non disponibile (così l'utente vede l'errore)
            let isTestChatTask = task.priority == .primary && task.preferredProvider != nil
            
            if canHandle {
                if available {
                    print("[AIManager] ✅ Usando provider preferito: \(preferred.rawValue)")
                    return preferred
                } else if isTestChatTask {
                    // Forza l'uso del provider preferito anche se non disponibile (per mostrare errore chiaro)
                    print("[AIManager] ⚠️ Provider preferito non disponibile, ma forzato per test chat: \(preferred.rawValue)")
                    return preferred
                }
            } else if isTestChatTask {
                // Anche se non può gestire il tipo, forziamo per mostrare errore chiaro
                print("[AIManager] ⚠️ Provider preferito non può gestire questo tipo, ma forzato per test chat: \(preferred.rawValue)")
                return preferred
            }
        }
        
        // Routing intelligente basato sul tipo di task
        switch task.type {
        case .documentAnalysis, .imageAnalysis:
            print("[AIManager] 📸 Task di analisi immagine/documento")
            if isProviderAvailable(.localMultimodal) {
                print("[AIManager] ✅ Usando .localMultimodal per analisi")
                return .localMultimodal
            }
            print("[AIManager] ⚠️ .localMultimodal non disponibile, usando .cloudOpenAI")
            return .cloudOpenAI
            
        case .emailSummary, .textAnalysis:
            if isProviderAvailable(.appleIntelligence) {
                return .appleIntelligence
            }
            if isProviderAvailable(.localText) {
                return .localText
            }
            return .cloudOpenAI
            
        case .textGeneration, .chat:
            // Per chat, rispetta il preferredProvider se disponibile
            if let preferred = task.preferredProvider, isProviderAvailable(preferred) {
                return preferred
            }
            // Altrimenti usa routing intelligente
            if isProviderAvailable(.localText) {
                return .localText
            }
            if isProviderAvailable(.localMultimodal) {
                return .localMultimodal
            }
            return .cloudOpenAI
            
        case .guardrailing:
            return .appleIntelligence
            
        case .documentExtraction:
            if isProviderAvailable(.localMultimodal) {
                return .localMultimodal
            }
            return .cloudOpenAI
        }
    }
    
    private func isProviderAvailable(_ provider: AIModelProvider) -> Bool {
        return getProviderAvailability(provider).available
    }
    
    /// Restituisce disponibilità e motivo per un provider
    private func getProviderAvailability(_ provider: AIModelProvider) -> (available: Bool, reason: String?) {
        switch provider {
        case .localMultimodal:
            let serviceAvailable = MLXVisionService.shared.serviceAvailable
            let modelLoaded = MLXVisionService.shared.isModelLoaded
            if serviceAvailable && modelLoaded {
                return (true, nil)
            } else if !serviceAvailable {
                return (false, "Servizio MLX Vision non disponibile")
            } else {
                return (false, "Modello vision non caricato")
            }
            
        case .localText:
            let available = LocalModelService.shared.isTextAvailable
            if available {
                return (true, nil)
            } else {
                return (false, "Modello Phi-4 non caricato o non disponibile")
            }
            
        case .appleIntelligence:
            let available = AppleAIService.shared.isAvailable
            if available {
                return (true, nil)
            } else {
                return (false, "Apple Intelligence non disponibile su questo dispositivo")
            }
            
        case .cloudOpenAI:
            let apiAvailable = CloudAIService.shared.isAvailable
            let canWorkInBackground = resourceMonitor.canWorkInBackground()
            if apiAvailable && canWorkInBackground {
                return (true, nil)
            } else if !apiAvailable {
                return (false, "API key OpenAI non configurata")
            } else {
                return (false, "Risorse di sistema insufficienti per operazioni cloud")
            }
        }
    }
    
    private func canProviderHandleTaskType(_ provider: AIModelProvider, taskType: AITaskType) -> Bool {
        switch (provider, taskType) {
        case (.appleIntelligence, .chat), (.appleIntelligence, .textGeneration):
            // Apple Intelligence supporta chat (limitato)
            return true
        case (.localMultimodal, .chat), (.localMultimodal, .textGeneration):
            // Modelli multimodali possono fare chat
            return true
        case (.localText, .chat), (.localText, .textGeneration):
            return true
        case (.cloudOpenAI, _):
            return true
        case (.appleIntelligence, .emailSummary), (.appleIntelligence, .textAnalysis), (.appleIntelligence, .guardrailing):
            return true
        case (.localMultimodal, .documentAnalysis), (.localMultimodal, .imageAnalysis), (.localMultimodal, .documentExtraction):
            return true
        case (.localText, .textAnalysis):
            return true
        default:
            return false
        }
    }
    
    private func updateQueueSize() {
        queueSize = taskQueue.count
    }
    
    /// Ottiene il task per un taskID (per feedback)
    func getTaskByID(_ taskID: UUID) -> AITask? {
        return activeTasks.first { $0.id == taskID }?.task ?? taskQueue.first { $0.id == taskID }
    }
    
    // MARK: - Reminder Analysis
    
    /// Analizza un'email per determinare se è un sollecito e di che tipo
    func analyzeReminderType(email: Email) -> (type: ReminderType, isUrgent: Bool)? {
        guard let body = email.body?.lowercased() else { return nil }
        
        let subject = email.subject.lowercased()
        let fullText = "\(subject) \(body)"
        
        // Rileva urgenza
        let urgentKeywords = ["urgente", "immediato", "asap", "subito", "priorità", "importante", "critico", "tempestivo"]
        let isUrgent = urgentKeywords.contains { fullText.contains($0) }
        
        // Determina tipo di sollecito basandosi sul mittente e contenuto
        let senderEmail = email.sender.email.lowercased()
        
        // Sollecito da liquidatore
        let liquidatoreKeywords = ["liquidatore", "liquidazione", "stima", "perizia"]
        if liquidatoreKeywords.contains(where: { fullText.contains($0) }) ||
           senderEmail.contains("liquidatore") || senderEmail.contains("perito") {
            return (.liquidatore, isUrgent)
        }
        
        // Sollecito da agenzia
        let agenziaKeywords = ["agenzia", "agente", "intermediario", "broker"]
        if agenziaKeywords.contains(where: { fullText.contains($0) }) ||
           senderEmail.contains("agenzia") || senderEmail.contains("agente") {
            return (.agenzia, isUrgent)
        }
        
        // Sollecito da cliente (default se contiene parole chiave di sollecito)
        let reminderKeywords = ["sollecito", "richiesta", "chiediamo", "sarebbe", "gradiremmo", "attendo", "aspetto"]
        if reminderKeywords.contains(where: { fullText.contains($0) }) {
            return (.cliente, isUrgent)
        }
        
        return nil
    }
    
    /// Ottiene le task completate oggi
    func getCompletedTasksToday() -> [AITaskInfo] {
        let calendar = Calendar.current
        let today = Date()
        
        return completedTasksHistory.filter { taskInfo in
            guard let completedAt = taskInfo.completedAt else { return false }
            return calendar.isDate(completedAt, inSameDayAs: today)
        }
    }
    
    /// Task completate negli ultimi `days` (default 3)
    func getCompletedTasks(lastDays: Int = 3) -> [AITaskInfo] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -lastDays, to: Date()) else {
            return completedTasksHistory
        }
        return completedTasksHistory.filter { info in
            guard let date = info.completedAt else { return false }
            return date >= start
        }
    }
    
    // MARK: - Persistence ultimo 3 giorni
    
    private struct HistoryItem: Codable {
        let task: AITask
        let status: AITaskStatus
        let startedAt: Date?
        let completedAt: Date?
        let result: AIResult?
    }
    
    private func persistHistory() {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -3, to: Date()) else { return }
        
        completedTasksHistory = completedTasksHistory.filter { info in
            guard let date = info.completedAt else { return false }
            return date >= cutoff
        }
        
        let items = completedTasksHistory.map { info in
            HistoryItem(
                task: info.task,
                status: info.status,
                startedAt: info.startedAt,
                completedAt: info.completedAt,
                result: info.result
            )
        }
        
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let items = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            return
        }
        
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -3, to: Date()) ?? Date.distantPast
        
        let filtered = items.filter { item in
            guard let date = item.completedAt else { return false }
            return date >= cutoff
        }
        
        completedTasksHistory = filtered.map { item in
            var info = AITaskInfo(task: item.task)
            info.status = item.status
            info.startedAt = item.startedAt
            info.completedAt = item.completedAt
            info.result = item.result
            info.progress = 1.0
            return info
        }
        
        persistHistory() // aggiorna storage con pruning
    }
    
}
