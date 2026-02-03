import Foundation
import CoreData
import Combine

/// Servizio per la gestione di una coda persistente di email da processare
/// Caratteristiche:
/// - Coda persistente in Core Data (sopravvive al restart)
/// - Throttling aggressivo per non sovraccaricare CPU
/// - Prioritizzazione (assegnazioni > revoche > atti > resto)
/// - Retry con backoff esponenziale
/// - Rate limiting configurabile
/// - Processamento in background a bassa priorità
@MainActor
class EmailQueueService: ObservableObject {
    
    static let shared = EmailQueueService()
    
    // MARK: - Configuration
    
    /// Configurazione del processamento
    struct ProcessingConfig {
        /// Dimensione batch (email per ciclo)
        var batchSize: Int = 3
        
        /// Pausa tra batch (secondi)
        var batchDelay: TimeInterval = 2.0
        
        /// Pausa tra singole email nel batch (secondi)
        var emailDelay: TimeInterval = 0.5
        
        /// Pausa dopo errore (secondi)
        var errorDelay: TimeInterval = 5.0
        
        /// Max retry per email
        var maxRetries: Int = 3
        
        /// Backoff esponenziale base (secondi)
        var retryBackoffBase: TimeInterval = 60.0
        
        /// Max CPU usage target (0-1)
        var maxCPUUsage: Double = 0.3
        
        /// Intervallo check CPU (secondi)
        var cpuCheckInterval: TimeInterval = 1.0
        
        /// Abilita auto-throttle basato su CPU
        var enableCPUThrottling: Bool = true
    }
    
    // MARK: - Published State
    
    @Published private(set) var isProcessing = false
    @Published private(set) var isPaused = false
    @Published private(set) var queueStats = QueueStats()
    @Published private(set) var currentEmail: String?
    @Published private(set) var lastError: String?
    @Published private(set) var estimatedTimeRemaining: TimeInterval?
    
    struct QueueStats {
        var pending: Int = 0
        var processing: Int = 0
        var completed: Int = 0
        var failed: Int = 0
        var total: Int { pending + processing + completed + failed }
        var progress: Double { total > 0 ? Double(completed) / Double(total) : 0 }
        var processedPerMinute: Double = 0
        var averageProcessingTime: TimeInterval = 0
    }
    
    // MARK: - Priority Levels
    
    enum Priority: Int16, Comparable {
        case critical = 100    // Revoche
        case high = 80         // Assegnazioni
        case medium = 60       // Atti, documentazione
        case normal = 40       // Solleciti, sopralluoghi
        case low = 20          // Comunicazioni generiche
        
        static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
        static func from(category: EmailCategory?) -> Priority {
            guard let category = category else { return .normal }
            
            switch category {
            case .revocation:
                return .critical
            case .assignment:
                return .high
            case .actSent, .actReceived, .documentationReceived, .revisionRequested, .verbalAcceptance:
                return .medium
            case .reminderReceived, .reminderSent, .surveyScheduled, .surveyReturned,
                 .videocallScheduled, .documentationRequest, .clarificationRequest, .controlled,
                 .meeting, .training:
                return .normal
            case .outcomeSent, .genericCommunication, .studioNews, .internalInfo,
                 .procedure, .administrative, .newsletter, .spam:
                return .low
            }
        }
    }
    
    // MARK: - Status
    
    enum ItemStatus: String {
        case pending = "pending"
        case scheduled = "scheduled"     // Retry programmato
        case processing = "processing"
        case completed = "completed"
        case failed = "failed"
        case cancelled = "cancelled"
    }
    
    // MARK: - Private State
    
    private let context: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    private var config = ProcessingConfig()
    private var processingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // Metriche per calcolo tempo rimanente
    private var processingStartTime: Date?
    private var processedInSession: Int = 0
    private var processingTimes: [TimeInterval] = []
    private let maxProcessingTimeSamples = 50
    
    // MARK: - Initialization
    
    private init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
        
        // Crea background context per operazioni pesanti
        self.backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        self.backgroundContext.automaticallyMergesChangesFromParent = true
        self.backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Carica stats iniziali (senza auto-resume per evitare sovraccarico all'avvio)
        Task {
            await refreshStats()
            
            // DISABILITATO: Auto-resume causava CPU elevata all'avvio
            // Il processamento viene avviato esplicitamente da MailViewModel.startMonitoring()
            // tramite EmailQueueService.shared.startProcessing() dopo l'inizializzazione completa
            if queueStats.pending > 0 {
                print("[EmailQueue] 📬 Trovate \(queueStats.pending) email in coda (avvio manuale richiesto)")
            }
        }
    }
    
    // MARK: - Public API
    
    /// Aggiunge email alla coda di processamento
    /// - Parameters:
    ///   - emails: Email da processare
    ///   - autoStart: Se avviare automaticamente il processamento
    func enqueue(_ emails: [Email], autoStart: Bool = true) async {
        guard !emails.isEmpty else { return }
        
        // Prefiltro sul MainActor: skip email lette associate a sinistri chiusi.
        // Non blocca: se l'indice non e' pronto, non skippa (verra' gestito comunque da MailManager in processing).
        var filtered: [Email] = []
        filtered.reserveCapacity(emails.count)
        var skippedEmails: [Email] = []
        
        for email in emails {
            let skipClosed = await ClosedSinistroEmailIndex.shared.shouldSkipProcessing(emailId: email.id, isRead: email.isRead)
            if skipClosed {
                skippedEmails.append(email)
                // Marca come saltata nel tag manager
                await MainActor.run {
                    EmailTagManager.shared.markAsSkipped(
                        emailId: email.id,
                        reason: "Email saltata (sinistro chiuso o troppo vecchia)"
                    )
                }
            } else {
                filtered.append(email)
            }
        }
        
        guard !filtered.isEmpty else {
            if !skippedEmails.isEmpty {
                print("[EmailQueue] ⏭️ \(skippedEmails.count) email saltate (sinistri chiusi)")
            }
            await refreshStats()
            return
        }
        
        await backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            var added = 0
            var skipped = 0
            
            for email in filtered {
                // Skip se già in coda o già processata
                if self.isInQueue(messageId: email.id, context: self.backgroundContext) {
                    skipped += 1
                    continue
                }
                
                if self.isAlreadyProcessed(messageId: email.id, context: self.backgroundContext) {
                    skipped += 1
                    continue
                }
                
                // Determina priorità basata su classificazione veloce
                // Le email non lette hanno priorità più alta
                var priority = self.quickClassifyPriority(for: email)
                
                // Boost priorità per email non lette (aumenta di 1 livello)
                if !email.isRead {
                    switch priority {
                    case .low:
                        priority = .normal
                    case .normal:
                        priority = .medium
                    case .medium:
                        priority = .high
                    case .high:
                        priority = .critical
                    case .critical:
                        break // Già massima priorità
                    }
                }
                
                // Crea item in coda
                let item = EmailQueueItem(context: self.backgroundContext)
                item.id = UUID()
                item.messageId = email.id
                item.priority = priority.rawValue
                item.status = ItemStatus.pending.rawValue
                item.retryCount = 0
                item.maxRetries = Int16(self.config.maxRetries)
                item.createdAt = Date()
                item.emailSubject = email.subject
                item.emailSender = email.sender.email
                item.emailDate = email.date
                
                added += 1
            }
            
            if added > 0 {
                do {
                    try self.backgroundContext.save()
                    print("[EmailQueue] ✅ Aggiunte \(added) email in coda, skipped \(skipped)")
                } catch {
                    print("[EmailQueue] ❌ Errore salvataggio coda: \(error)")
                }
            }
        }
        
        // Refresh stats e avvia se richiesto
        await refreshStats()
        
        if autoStart && !isProcessing {
            await startProcessing()
        }
    }
    
    /// Aggiunge una singola email con priorità specifica
    func enqueue(messageId: String, mailboxId: String?, priority: Priority = .normal) async {
        await backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            // Skip se già presente
            if self.isInQueue(messageId: messageId, context: self.backgroundContext) ||
               self.isAlreadyProcessed(messageId: messageId, context: self.backgroundContext) {
                return
            }
            
            let item = EmailQueueItem(context: self.backgroundContext)
            item.id = UUID()
            item.messageId = messageId
            item.mailboxId = mailboxId
            item.priority = priority.rawValue
            item.status = ItemStatus.pending.rawValue
            item.retryCount = 0
            item.maxRetries = Int16(self.config.maxRetries)
            item.createdAt = Date()
            
            do {
                try self.backgroundContext.save()
            } catch {
                print("[EmailQueue] ❌ Errore enqueue: \(error)")
            }
        }
        
        await refreshStats()
    }
    
    /// Avvia il processamento della coda
    func startProcessing() async {
        guard !isProcessing else {
            print("[EmailQueue] ⚠️ Processamento già in corso")
            return
        }
        
        isProcessing = true
        isPaused = false
        processingStartTime = Date()
        processedInSession = 0
        
        print("[EmailQueue] 🚀 Avvio processamento coda...")
        
        processingTask = Task.detached(priority: .utility) { [weak self] in
            await self?.processQueue()
        }
    }
    
    /// Mette in pausa il processamento
    func pauseProcessing() {
        isPaused = true
        print("[EmailQueue] ⏸️ Processamento in pausa")
    }
    
    /// Riprende il processamento
    func resumeProcessing() {
        isPaused = false
        print("[EmailQueue] ▶️ Processamento ripreso")
    }
    
    /// Ferma completamente il processamento
    func stopProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        isPaused = false
        currentEmail = nil
        print("[EmailQueue] ⏹️ Processamento fermato")
    }
    
    /// Aggiorna la configurazione
    func updateConfig(_ newConfig: ProcessingConfig) {
        config = newConfig
        print("[EmailQueue] ⚙️ Configurazione aggiornata")
    }
    
    /// Pulisce email completate più vecchie di X giorni
    func cleanupCompleted(olderThan days: Int = 7) async {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        await backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            let request = NSFetchRequest<EmailQueueItem>(entityName: "EmailQueueItem")
            request.predicate = NSPredicate(
                format: "status == %@ AND completedAt < %@",
                ItemStatus.completed.rawValue,
                cutoffDate as NSDate
            )
            
            do {
                let items = try self.backgroundContext.fetch(request)
                for item in items {
                    self.backgroundContext.delete(item)
                }
                try self.backgroundContext.save()
                print("[EmailQueue] 🧹 Rimosse \(items.count) email completate")
            } catch {
                print("[EmailQueue] ❌ Errore cleanup: \(error)")
            }
        }
        
        await refreshStats()
    }
    
    /// Riprova tutte le email fallite
    func retryAllFailed() async {
        await backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            let request = NSFetchRequest<EmailQueueItem>(entityName: "EmailQueueItem")
            request.predicate = NSPredicate(format: "status == %@", ItemStatus.failed.rawValue)
            
            do {
                let items = try self.backgroundContext.fetch(request)
                for item in items {
                    item.status = ItemStatus.pending.rawValue
                    item.retryCount = 0
                    item.lastError = nil
                    item.scheduledAt = nil
                }
                try self.backgroundContext.save()
                print("[EmailQueue] 🔄 Ripristinate \(items.count) email fallite")
            } catch {
                print("[EmailQueue] ❌ Errore retry: \(error)")
            }
        }
        
        await refreshStats()
    }
    
    /// Cancella tutta la coda
    func clearQueue() async {
        stopProcessing()
        
        await backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            let request = NSFetchRequest<EmailQueueItem>(entityName: "EmailQueueItem")
            
            do {
                let items = try self.backgroundContext.fetch(request)
                for item in items {
                    self.backgroundContext.delete(item)
                }
                try self.backgroundContext.save()
                print("[EmailQueue] 🗑️ Coda svuotata")
            } catch {
                print("[EmailQueue] ❌ Errore clear: \(error)")
            }
        }
        
        await refreshStats()
    }
    
    // MARK: - Queue Processing
    
    private func processQueue() async {
        // IMPORTANTE: Attendi che la sincronizzazione iniziale dei sinistri sia completata
        // Questo garantisce che i sinistri siano disponibili quando processiamo le email
        // (evita "Sinistro non trovato" per sinistri appena creati)
        let syncCompleted = await ClaimSyncService.shared.waitForInitialSync(timeout: 30)
        if syncCompleted {
            print("[EmailQueue] ✅ Sincronizzazione sinistri completata, avvio processamento email")
        } else {
            print("[EmailQueue] ⚠️ Timeout sincronizzazione, procedo comunque con il processamento")
        }
        
        while !Task.isCancelled {
            // Check pausa
            if await MainActor.run(body: { isPaused }) {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                continue
            }
            
            if config.enableCPUThrottling {
                await CPUThrottler.shared.throttleIfNeeded()
            }
            
            // Fetch prossimo batch
            let batch = await fetchNextBatch()
            
            if batch.isEmpty {
                // Coda vuota, termina
                await MainActor.run {
                    isProcessing = false
                    currentEmail = nil
                    print("[EmailQueue] ✅ Coda completata!")
                }
                break
            }
            
            // Processa batch
            for item in batch {
                if Task.isCancelled { break }
                
                // Check pausa tra email
                if await MainActor.run(body: { isPaused }) {
                    break
                }
                
                await processItem(item)
                
                // Pausa tra email
                try? await Task.sleep(nanoseconds: UInt64(config.emailDelay * 1_000_000_000))
            }
            
            // Pausa tra batch
            try? await Task.sleep(nanoseconds: UInt64(config.batchDelay * 1_000_000_000))
            
            // Refresh stats
            await refreshStats()
        }
    }
    
    private func fetchNextBatch() async -> [EmailQueueItem] {
        // 1. Recupera items dalla coda
        let items = await backgroundContext.perform { [weak self] () -> [EmailQueueItem] in
            guard let self = self else { return [] }
            
            let request = NSFetchRequest<EmailQueueItem>(entityName: "EmailQueueItem")
            
            // Pending o scheduled con data passata
            let now = Date()
            request.predicate = NSPredicate(
                format: "(status == %@) OR (status == %@ AND scheduledAt <= %@)",
                ItemStatus.pending.rawValue,
                ItemStatus.scheduled.rawValue,
                now as NSDate
            )
            
            // Ordina per priorità (desc) poi data creazione (asc)
            request.sortDescriptors = [
                NSSortDescriptor(key: "priority", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: true)
            ]
            
            // Recupera più item del necessario per poter filtrare per email non lette
            request.fetchLimit = self.config.batchSize * 2
            
            do {
                return try self.backgroundContext.fetch(request)
            } catch {
                print("[EmailQueue] ❌ Errore fetch batch: \(error)")
                return []
            }
        }
        
        guard !items.isEmpty else { return [] }
        
        // 2. Verifica stato isRead dal repository (sul MainActor)
        let emailRepository = await MainActor.run { EmailRepository.shared }
        let messageIds = items.compactMap { $0.messageId }
        let unreadMessageIds = await MainActor.run { () -> Set<String> in
            var unreadIds = Set<String>()
            for messageId in messageIds {
                if let email = emailRepository.getEmail(byId: messageId), !email.isRead {
                    unreadIds.insert(messageId)
                }
            }
            return unreadIds
        }
        
        // 3. Riordina: priorità base, poi email non lette, poi data creazione
        let sortedItems = items.sorted { item1, item2 in
            // Prima ordina per priorità
            if item1.priority != item2.priority {
                return item1.priority > item2.priority
            }
            
            // A parità di priorità, email non lette hanno priorità
            let isUnread1 = unreadMessageIds.contains(item1.messageId ?? "")
            let isUnread2 = unreadMessageIds.contains(item2.messageId ?? "")
            
            if isUnread1 != isUnread2 {
                return isUnread1 && !isUnread2
            }
            
            // Stesso stato, ordina per data creazione
            let date1 = item1.createdAt ?? Date.distantPast
            let date2 = item2.createdAt ?? Date.distantPast
            return date1 < date2
        }
        
        // 4. Prendi solo i primi N
        return Array(sortedItems.prefix(config.batchSize))
    }
    
    private func processItem(_ item: EmailQueueItem) async {
        let messageId = item.messageId ?? ""
        let startTime = Date()
        
        await MainActor.run {
            currentEmail = item.emailSubject ?? messageId
        }
        
        // Marca come in processing (nella coda)
        await backgroundContext.perform { [weak self] in
            item.status = ItemStatus.processing.rawValue
            item.startedAt = Date()
            try? self?.backgroundContext.save()
        }
        
        // Marca come in corso di processamento (nel tag manager)
        await MainActor.run {
            EmailTagManager.shared.markAsInProgress(emailId: messageId)
            print("[EmailQueue] 🔄 Email \(messageId) in corso di processamento")
        }
        
        // Processa l'email
        do {
            try await processEmail(messageId: messageId, mailboxId: item.mailboxId)
            
            // Verifica che l'email sia effettivamente processata prima di marcare come completato
            let context = await MainActor.run { PersistenceController.shared.container.viewContext }
            let isProcessed = await isEmailProcessedInCoreData(messageId: messageId, context: context)
            
            if isProcessed {
                // Successo - email processata
                await backgroundContext.perform { [weak self] in
                    item.status = ItemStatus.completed.rawValue
                    item.completedAt = Date()
                    try? self?.backgroundContext.save()
                }
                
                // Aggiorna metriche
                let processingTime = Date().timeIntervalSince(startTime)
                await updateProcessingMetrics(time: processingTime, success: true)
                
                // Aggiorna tag manager
                await MainActor.run {
                    EmailTagManager.shared.markAsProcessed(emailId: messageId)
                    
                    // Auto-marca come letta se abilitato per questa categoria
                    if let tag = EmailTagManager.shared.getTag(forEmailId: messageId),
                       EmailAutoReadSettings.shared.isCategoryEnabled(tag.category) {
                        MailViewModel.shared.markEmailAsRead(emailId: messageId)
                        print("[EmailQueue] 📌 Auto-marcatura come letta per email \(messageId) (categoria: \(tag.category.displayName))")
                    }
                }
            } else {
                // Email non processata (potrebbe essere perché manca body o handler non disponibile)
                // Marca come completato comunque per evitare loop infiniti
                print("[EmailQueue] ⚠️ Email \(messageId) non processata ma marcata come completata per evitare loop")
                await backgroundContext.perform { [weak self] in
                    item.status = ItemStatus.completed.rawValue
                    item.completedAt = Date()
                    item.lastError = "Email non processata (manca body o handler non disponibile)"
                    try? self?.backgroundContext.save()
                }
                
                // Aggiorna metriche
                let processingTime = Date().timeIntervalSince(startTime)
                await updateProcessingMetrics(time: processingTime, success: true)
            }
            
        } catch {
            // Errore - gestisci retry
            await handleProcessingError(item: item, error: error)
            await updateProcessingMetrics(time: 0, success: false)
        }
    }
    
    private func processEmail(messageId: String, mailboxId: String?) async throws {
        // Usa il MailManager esistente per processare
        let context = await MainActor.run { PersistenceController.shared.container.viewContext }
        
        // Verifica se già processata prima di scaricare (verifica diretta in Core Data)
        let wasAlreadyProcessed = await isEmailProcessedInCoreData(messageId: messageId, context: context)
        
        // Scarica email se necessario
        do {
            guard let email = try await MailManager.shared.fetchFullEmail(emailId: messageId, context: context) else {
                throw ProcessingError.emailNotFound(messageId)
            }
            
            // Verifica se è stata processata dopo il download
            let isNowProcessed = await isEmailProcessedInCoreData(messageId: messageId, context: context)
            
            if !wasAlreadyProcessed && !isNowProcessed {
                // L'email è stata scaricata ma non processata (es. manca body o handler non disponibile)
                // Processala manualmente
                print("[EmailQueue] 🔄 Email \(messageId) scaricata ma non processata, avvio processamento manuale")
                _ = await MailManager.shared.processEmail(email, context: context)
                
                // Verifica nuovamente se è stata processata
                let isProcessedAfterManual = await isEmailProcessedInCoreData(messageId: messageId, context: context)
                if !isProcessedAfterManual {
                    // Se ancora non processata, potrebbe essere perché manca il body
                    // In questo caso, marcala come processata comunque per evitare loop infiniti
                    if email.body == nil || email.body!.isEmpty {
                        print("[EmailQueue] ⚠️ Email \(messageId) senza body, marcata come processata per evitare loop")
                        await markEmailAsProcessedInCoreData(messageId: messageId, context: context)
                    } else {
                        throw ProcessingError.processingFailed("Email non processata dopo tentativo manuale")
                    }
                }
            }
        } catch let error as GmailAPIError where error.isAuthenticationError {
            // Propaga errori di autenticazione senza modifiche
            throw ProcessingError.authenticationRequired(error.errorDescription ?? "Token di autenticazione scaduto")
        } catch {
            // Rilancia altri errori
            throw error
        }
    }
    
    private func isEmailProcessedInCoreData(messageId: String, context: NSManagedObjectContext) async -> Bool {
        return await context.perform { () -> Bool in
            let request = NSFetchRequest<ProcessedEmail>(entityName: "ProcessedEmail")
            request.predicate = NSPredicate(format: "messageId == %@", messageId)
            request.fetchLimit = 1
            
            do {
                let results = try context.fetch(request)
                return !results.isEmpty
            } catch {
                print("[EmailQueue] ⚠️ Errore verifica email processata: \(error)")
                return false
            }
        }
    }
    
    private func markEmailAsProcessedInCoreData(messageId: String, context: NSManagedObjectContext) async {
        await context.perform {
            // Verifica se esiste già
            let request = NSFetchRequest<ProcessedEmail>(entityName: "ProcessedEmail")
            request.predicate = NSPredicate(format: "messageId == %@", messageId)
            request.fetchLimit = 1
            
            do {
                let results = try context.fetch(request)
                if let existing = results.first {
                    // Aggiorna data
                    existing.processedDate = Date()
                } else {
                    // Crea nuova entry
                    let processed = ProcessedEmail(context: context)
                    processed.messageId = messageId
                    processed.processedDate = Date()
                }
                
                // Verifica se ci sono modifiche prima di salvare
                guard context.hasChanges else {
                    return
                }
                
                try context.save()
            } catch {
                print("[EmailQueue] ⚠️ Errore marcatura email processata: \(error)")
            }
        }
    }
    
    private func removeFromProcessedInCoreData(messageId: String, context: NSManagedObjectContext) async {
        await context.perform {
            let request = NSFetchRequest<ProcessedEmail>(entityName: "ProcessedEmail")
            request.predicate = NSPredicate(format: "messageId == %@", messageId)
            
            do {
                let results = try context.fetch(request)
                for processed in results {
                    context.delete(processed)
                }
                
                if context.hasChanges {
                    try context.save()
                    print("[EmailQueue] 🗑️ Rimossa email \(messageId) dalla lista delle processate")
                }
            } catch {
                print("[EmailQueue] ⚠️ Errore rimozione email processata: \(error)")
            }
        }
    }
    
    private func handleProcessingError(item: EmailQueueItem, error: Error) async {
        await backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            // Verifica se è un errore di autenticazione (401)
            let isAuthError = (error as? GmailAPIError)?.isAuthenticationError ?? false
            
            if isAuthError {
                // Errore di autenticazione: prova a refreshare il token e riprova
                print("[EmailQueue] ⚠️ Email \(item.messageId ?? "") errore autenticazione, tentativo refresh token...")
                
                Task { [weak self] in
                    guard let self = self else { return }
                    
                    // Prova a refreshare il token
                    let refreshSuccess = await GoogleAuthService.shared.refreshTokenIfNeeded()
                    
                    if refreshSuccess {
                        // Token refreshato, riprova l'email (resetta retry count e riprogramma)
                        print("[EmailQueue] ✅ Token refreshato, riprogrammo email \(item.messageId ?? "")")
                        await self.backgroundContext.perform {
                            item.retryCount = 0
                            item.status = ItemStatus.pending.rawValue
                            item.scheduledAt = Date()
                            item.lastError = nil
                            
                            // Salva le modifiche
                            if self.backgroundContext.hasChanges {
                                try? self.backgroundContext.save()
                            }
                        }
                        
                        // Aggiorna stato UI
                        await MainActor.run {
                            if let messageId = item.messageId {
                                Task {
                                    await EmailTagManager.shared.updateProcessingStatus(
                                        forEmailId: messageId,
                                        status: .inCoda,
                                        result: "Riprocessamento dopo refresh token"
                                    )
                                }
                            }
                        }
                        
                        // Riavvia il processamento se non attivo
                        await self.startProcessing()
                    } else {
                        // Refresh fallito, marca come errore
                        await self.backgroundContext.perform {
                            item.status = ItemStatus.failed.rawValue
                            item.lastError = "Autenticazione richiesta. Riautenticazione necessaria."
                        }
                        
                        print("[EmailQueue] ❌ Refresh token fallito per email \(item.messageId ?? "")")
                        
                        // Aggiorna stato UI
                        await MainActor.run {
                            if let messageId = item.messageId {
                                Task {
                                    await EmailTagManager.shared.updateProcessingStatus(
                                        forEmailId: messageId,
                                        status: .errore,
                                        result: "Autenticazione richiesta"
                                    )
                                }
                            }
                        }
                    }
                }
                return
            }
            
            item.retryCount += 1
            item.lastError = error.localizedDescription
            
            if item.retryCount >= item.maxRetries {
                // Max retry raggiunto
                item.status = ItemStatus.failed.rawValue
                print("[EmailQueue] ❌ Email \(item.messageId ?? "") fallita dopo \(item.retryCount) tentativi")
            } else {
                // Programma retry con backoff esponenziale
                let backoff = self.config.retryBackoffBase * pow(2, Double(item.retryCount - 1))
                item.status = ItemStatus.scheduled.rawValue
                item.scheduledAt = Date().addingTimeInterval(backoff)
                print("[EmailQueue] 🔄 Retry \(item.retryCount)/\(item.maxRetries) per \(item.messageId ?? "") in \(Int(backoff))s")
            }
            
            try? self.backgroundContext.save()
        }
        
        // Pausa extra dopo errore
        try? await Task.sleep(nanoseconds: UInt64(config.errorDelay * 1_000_000_000))
    }
    
    // CPU throttling delegato a CPUThrottler.shared (mai dalla UI)

    // MARK: - Metrics
    
    private func updateProcessingMetrics(time: TimeInterval, success: Bool) async {
        if success {
            processedInSession += 1
            
            processingTimes.append(time)
            if processingTimes.count > maxProcessingTimeSamples {
                processingTimes.removeFirst()
            }
        }
        
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            
            // Calcola rate
            if let startTime = self.processingStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > 0 {
                    self.queueStats.processedPerMinute = Double(self.processedInSession) / (elapsed / 60.0)
                }
            }
            
            // Calcola tempo medio
            if !self.processingTimes.isEmpty {
                self.queueStats.averageProcessingTime = self.processingTimes.reduce(0, +) / Double(self.processingTimes.count)
            }
            
            // Stima tempo rimanente
            if self.queueStats.processedPerMinute > 0 && self.queueStats.pending > 0 {
                self.estimatedTimeRemaining = Double(self.queueStats.pending) / self.queueStats.processedPerMinute * 60
            }
        }
    }
    
    // MARK: - Stats
    
    func refreshStats() async {
        await backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            var stats = QueueStats()
            
            let statuses: [ItemStatus] = [.pending, .scheduled, .processing, .completed, .failed]
            
            for status in statuses {
                let request = NSFetchRequest<EmailQueueItem>(entityName: "EmailQueueItem")
                
                if status == .pending {
                    request.predicate = NSPredicate(
                        format: "status == %@ OR status == %@",
                        ItemStatus.pending.rawValue,
                        ItemStatus.scheduled.rawValue
                    )
                } else {
                    request.predicate = NSPredicate(format: "status == %@", status.rawValue)
                }
                
                do {
                    let count = try self.backgroundContext.count(for: request)
                    switch status {
                    case .pending, .scheduled:
                        stats.pending = count
                    case .processing:
                        stats.processing = count
                    case .completed:
                        stats.completed = count
                    case .failed:
                        stats.failed = count
                    case .cancelled:
                        break
                    }
                } catch {
                    print("[EmailQueue] ⚠️ Errore conteggio \(status): \(error)")
                }
            }
            
            // Mantieni metriche di sessione
            stats.processedPerMinute = self.queueStats.processedPerMinute
            stats.averageProcessingTime = self.queueStats.averageProcessingTime
            
            Task { @MainActor in
                self.queueStats = stats
            }
        }
    }
    
    // MARK: - Priority Download
    
    /// Prioritizza il download di un'email specifica (quando l'utente la apre)
    func prioritizeEmail(_ messageId: String) async {
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // 1. Controlla se l'email è già in coda (operazione Core Data sincrona)
        let isInQueue = await context.perform { () -> Bool in
            let request = NSFetchRequest<EmailQueueItem>(entityName: "EmailQueueItem")
            request.predicate = NSPredicate(
                format: "messageId == %@ AND (status == %@ OR status == %@ OR status == %@)",
                messageId,
                ItemStatus.pending.rawValue,
                ItemStatus.scheduled.rawValue,
                ItemStatus.processing.rawValue
            )
            request.fetchLimit = 1
            
            if let existingItem = try? context.fetch(request).first {
                // Aumenta la priorità e schedula subito
                existingItem.priority = Priority.critical.rawValue
                existingItem.scheduledAt = Date() // Schedula subito
                
                // Se è in scheduled, riporta a pending per processamento immediato
                if existingItem.status == ItemStatus.scheduled.rawValue {
                    existingItem.status = ItemStatus.pending.rawValue
                }
                
                // Se è in processing da più di 5 minuti, potrebbe essere bloccata - riporta a pending
                if existingItem.status == ItemStatus.processing.rawValue,
                   let startedAt = existingItem.startedAt,
                   Date().timeIntervalSince(startedAt) > 300 {
                    print("[EmailQueue] ⚠️ Email \(messageId) bloccata in processing da \(Int(Date().timeIntervalSince(startedAt)))s, riporto a pending")
                    existingItem.status = ItemStatus.pending.rawValue
                    existingItem.startedAt = nil
                }
                
                try? context.save()
                print("[EmailQueue] ⬆️ Priorità email \(messageId) aumentata a critica")
                return true
            }
            return false
        }
        
        // 2. Se è in coda, avvia il processamento se non è già in corso
        if isInQueue {
            print("[EmailQueue] 📋 Email \(messageId) già in coda, avvio processamento...")
            if !isProcessing {
                await startProcessing()
                print("[EmailQueue] 🚀 Processamento avviato per email \(messageId)")
            } else {
                print("[EmailQueue] ⏳ Processamento già in corso, email \(messageId) verrà processata a breve")
            }
            return
        }
        
        // 3. Controlla se l'email è già nel repository con body presente (operazione async)
        let emailRepository = await MainActor.run { EmailRepository.shared }
        let cachedEmail = await emailRepository.getEmail(byId: messageId)
        let mainContext = await MainActor.run { PersistenceController.shared.container.viewContext }
        
        if let cachedEmail = cachedEmail {
            // Se il body è già presente, verifica se è processata
            if cachedEmail.body != nil && !cachedEmail.body!.isEmpty {
                let isProcessed = await isEmailProcessedInCoreData(messageId: messageId, context: mainContext)
                
                if isProcessed {
                    // Email già processata - rimuovila dalla lista delle processate per riprocessarla
                    print("[EmailQueue] 🔄 Email \(messageId) già processata, rimozione per riprocessamento")
                    
                    // Rimuovi dalla lista delle processate
                    await removeFromProcessedInCoreData(messageId: messageId, context: mainContext)
                    
                    // Aggiorna stato nel tag manager a "in coda"
                    await MainActor.run {
                        EmailTagManager.shared.updateProcessingStatus(forEmailId: messageId, status: .inCoda)
                        print("[EmailQueue] 📋 Email \(messageId) stato aggiornato a 'in coda'")
                    }
                    
                    // Aggiungi alla coda con priorità critica per riprocessamento
                    await enqueue(messageId: messageId, mailboxId: nil, priority: .critical)
                    
                    // Avvia il processamento se non è già in corso
                    if !isProcessing {
                        await startProcessing()
                    }
                    return
                } else {
                    // Email scaricata ma non processata - processala immediatamente
                    print("[EmailQueue] 🔄 Email \(messageId) scaricata ma non processata, avvio processamento immediato")
                    
                    // Marca come in corso
                    await MainActor.run {
                        EmailTagManager.shared.markAsInProgress(emailId: messageId)
                    }
                    
                    do {
                        try await processEmail(messageId: messageId, mailboxId: nil)
                        
                        // Verifica che sia stata processata
                        let isProcessed = await isEmailProcessedInCoreData(messageId: messageId, context: mainContext)
                        if isProcessed {
                            print("[EmailQueue] ✅ Email \(messageId) processata con successo")
                            await MainActor.run {
                                EmailTagManager.shared.markAsProcessed(emailId: messageId)
                            }
                        } else {
                            print("[EmailQueue] ⚠️ Email \(messageId) non processata dopo tentativo")
                            await MainActor.run {
                                EmailTagManager.shared.markAsError(emailId: messageId, error: "Processamento non completato")
                            }
                        }
                    } catch {
                        print("[EmailQueue] ❌ Errore processamento email \(messageId): \(error)")
                        await MainActor.run {
                            EmailTagManager.shared.markAsError(emailId: messageId, error: error.localizedDescription)
                        }
                        // Se fallisce, aggiungi alla coda per retry
                        await enqueue(messageId: messageId, mailboxId: nil, priority: .critical)
                        if !isProcessing {
                            await startProcessing()
                        }
                    }
                    return
                }
            }
        }
        
        // 4. Se il body non è presente, aggiungi alla coda con priorità critica
        print("[EmailQueue] 📥 Aggiunta email \(messageId) alla coda con priorità critica")
        
        // Rimuovi dalla lista delle processate se presente (per permettere riprocessamento)
        await removeFromProcessedInCoreData(messageId: messageId, context: mainContext)
        
        // Aggiorna stato nel tag manager a "in coda"
        await MainActor.run {
            EmailTagManager.shared.updateProcessingStatus(forEmailId: messageId, status: .inCoda)
        }
        
        await enqueue(messageId: messageId, mailboxId: nil, priority: .critical)
        
        // 5. Avvia il processamento se non è già in corso
        if !isProcessing {
            await startProcessing()
        }
    }
    
    // MARK: - Helpers
    
    private func isInQueue(messageId: String, context: NSManagedObjectContext) -> Bool {
        let request = NSFetchRequest<EmailQueueItem>(entityName: "EmailQueueItem")
        request.predicate = NSPredicate(
            format: "messageId == %@ AND status != %@ AND status != %@",
            messageId,
            ItemStatus.completed.rawValue,
            ItemStatus.cancelled.rawValue
        )
        request.fetchLimit = 1
        
        return (try? context.count(for: request)) ?? 0 > 0
    }
    
    private func isAlreadyProcessed(messageId: String, context: NSManagedObjectContext) -> Bool {
        let request = NSFetchRequest<ProcessedEmail>(entityName: "ProcessedEmail")
        request.predicate = NSPredicate(format: "messageId == %@", messageId)
        request.fetchLimit = 1
        
        return (try? context.count(for: request)) ?? 0 > 0
    }
    
    private func quickClassifyPriority(for email: Email) -> Priority {
        let subject = email.subject.lowercased()
        let sender = email.sender.email.lowercased()
        
        // Revoche
        if subject.contains("revoca") {
            return .critical
        }
        
        // Assegnazioni (da ACT)
        if sender == "info@actsrl.it" && subject.contains("assegnazione") {
            return .high
        }
        
        // Atti
        if subject.contains("atto") || subject.contains("firma") || subject.contains("quietanza") {
            return .medium
        }
        
        // Solleciti
        if subject.contains("sollecito") || subject.contains("urgente") {
            return .normal
        }
        
        return .low
    }
    
    // MARK: - Errors
    
    enum ProcessingError: LocalizedError {
        case emailNotFound(String)
        case processingFailed(String)
        case authenticationRequired(String)
        
        var errorDescription: String? {
            switch self {
            case .emailNotFound(let id):
                return "Email \(id) non trovata"
            case .processingFailed(let reason):
                return "Processamento fallito: \(reason)"
            case .authenticationRequired(let message):
                return "Autenticazione richiesta: \(message)"
            }
        }
    }
}

// MARK: - EmailQueueItem Extension

extension EmailQueueItem {
    var statusEnum: EmailQueueService.ItemStatus {
        return EmailQueueService.ItemStatus(rawValue: status ?? "pending") ?? .pending
    }
    
    var priorityEnum: EmailQueueService.Priority {
        return EmailQueueService.Priority(rawValue: priority) ?? .normal
    }
}
