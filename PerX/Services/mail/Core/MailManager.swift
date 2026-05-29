import Foundation
import CoreData
import Combine

// MARK: - Array Extension
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

/// Manager centralizzato per la gestione delle email
/// Legge le email una sola volta, le classifica e le instrada agli handler appropriati
@MainActor
class MailManager: ObservableObject {
    static let shared = MailManager()
    
    // MARK: - Dependencies
    
    private let gmailService = GmailService.shared
    private let classifier = EmailClassifier.shared
    @available(*, deprecated, message: "Usa unifiedEventBus invece")
    private let eventBus = EmailEventBus.shared
    private let unifiedEventBus = UnifiedEventBus.shared
    private let claimEngine = ClaimEngine.shared
    private let repository = EmailRepository.shared
    private let cacheService = EmailCacheService.shared
    private let authService = GoogleAuthService.shared
    
    // MARK: - Published State
    
    @Published var isProcessing = false
    @Published var lastProcessedDate: Date?
    @Published var processedCount: Int = 0
    @Published var errorMessage: String?
    
    /// Statistiche di classificazione
    @Published var classificationStats: ClassificationStats = ClassificationStats()
    
    struct ClassificationStats {
        var totalProcessed: Int = 0
        var byCategory: [EmailCategory: Int] = [:]
        var byDirection: [EmailDirection: Int] = [:]
        var lastReset: Date = Date()
    }
    
    // MARK: - Private State
    
    private var cancellables = Set<AnyCancellable>()
    private var isMonitoringActive = false
    private let processingQueue = DispatchQueue(label: "MailManager.processing", qos: .utility)
    private var activeProcessingTasks = 0
    private let maxConcurrentProcessing = 2 // Limite processi concurrent
    private var processingQueueEmails: [Email] = []
    
    // MARK: - Initialization
    
    private init() {
        // Registra tutti gli handler al primo avvio
        registerDefaultHandlers()
        print("[MailManager] Inizializzato")
    }
    
    // MARK: - Handler Registration
    
    private func registerDefaultHandlers() {
        let registry = EmailHandlerRegistry.shared
        
        // Registra tutti gli handler
        registry.register(DocumentationHandler())
        registry.register(ReminderHandler())
        registry.register(SurveyHandler())
        registry.register(ActHandler())
        registry.register(ClarificationHandler())
        registry.register(ControlHandler())
        registry.register(OutboundTracker())
        registry.register(StudioCommunicationHandler())
        registry.register(GenericCommunicationHandler())
        
        print("[MailManager] Registrati \(registry.getAllHandlers().count) handler")
    }
    
    // MARK: - Processed Email Tracking (Core Data)
    
    /// Verifica se un'email è già stata processata usando Core Data
    /// Non isolato al MainActor per permettere chiamate da contesti asincroni
    nonisolated private func isEmailProcessed(messageId: String, context: NSManagedObjectContext) -> Bool {
        // Valida contesto prima di procedere
        guard context.persistentStoreCoordinator != nil else {
            return false
        }
        
        // Usa performAndWait per garantire thread-safety
        var result = false
        context.performAndWait {
            let request = NSFetchRequest<ProcessedEmail>(entityName: "ProcessedEmail")
            request.predicate = NSPredicate(format: "messageId == %@", messageId)
            request.fetchLimit = 1
            
            do {
                let results = try context.fetch(request)
                result = !results.isEmpty
            } catch {
                print("[MailManager] ⚠️ Errore verifica email processata: \(error)")
                result = false
            }
        }
        return result
    }
    
    /// Marca un'email come processata in Core Data
    /// Non isolato al MainActor per permettere chiamate da contesti asincroni
    /// IMPORTANTE: Usa context.perform per garantire thread-safety
    nonisolated private func markEmailAsProcessed(messageId: String, context: NSManagedObjectContext) {
        // Valida contesto prima di procedere
        guard context.persistentStoreCoordinator != nil else {
            print("[MailManager] ⚠️ Contesto Core Data non valido per marcatura email \(messageId)")
            return
        }
        
        // Usa perform per garantire thread-safety
        context.performAndWait {
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
                print("[MailManager] ⚠️ Errore marcatura email processata: \(error)")
                // Recovery: prova a rollback per evitare stato inconsistente
                if context.hasChanges {
                    context.rollback()
                }
            }
        }
    }
    
    // MARK: - Main Processing Pipeline
    
    /// Processa tutte le email nuove con throttling e deduplicazione
    /// - Parameters:
    ///   - emails: Array di email da processare
    ///   - context: Contesto Core Data
    func processEmails(_ emails: [Email], context: NSManagedObjectContext) async {
        guard !isProcessing else {
            print("[MailManager] ⚠️ Processamento già in corso")
            return
        }
        
        isProcessing = true
        errorMessage = nil
        
        let startTime = Date()
        
        // Filtra solo email non ancora processate
        let unprocessedEmails = emails.filter { !isEmailProcessed(messageId: $0.id, context: context) }
        
        guard !unprocessedEmails.isEmpty else {
            print("[MailManager] ✅ Tutte le \(emails.count) email già processate, skip")
            isProcessing = false
            return
        }
        
        print("[MailManager] 🚀 Processamento di \(unprocessedEmails.count)/\(emails.count) email nuove")
        
        var processedEmails = 0
        var skippedEmails = 0
        var eventCount = 0
        
        // Processa in batch con throttling (batch più piccoli per non sovraccaricare)
        let batchSize = 5 // Ridotto da 10 a 5 per ridurre carico CPU
        for batch in unprocessedEmails.chunked(into: batchSize) {
            // Limita processi concurrent
            while activeProcessingTasks >= maxConcurrentProcessing {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s (aumentato)
            }
            
            // Processa batch (in background tramite processBatch che usa TaskGroup)
            await processBatch(batch, context: context) { processed, events in
                processedEmails += processed
                eventCount += events
            }
            
            // Throttling tra batch (aumentato per dare respiro al sistema e ridurre CPU)
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s tra batch per ridurre carico CPU
        }
        
        skippedEmails = emails.count - unprocessedEmails.count
        
        // Aggiorna stato
        processedCount = processedEmails
        lastProcessedDate = Date()
        isProcessing = false
        
        let duration = Date().timeIntervalSince(startTime)
        print("[MailManager] ✅ Processate \(processedEmails) email, saltate \(skippedEmails) già processate in \(String(format: "%.2f", duration))s")
        print("[MailManager] 📬 Pubblicati \(eventCount) eventi")
    }
    
    /// Processa un batch di email con controllo concurrent
    private func processBatch(
        _ emails: [Email],
        context: NSManagedObjectContext,
        completion: @escaping (Int, Int) -> Void
    ) async {
        await withTaskGroup(of: (Int, Int).self) { group in
            for email in emails {
                group.addTask { [weak self] in
                    guard let self = self else { return (0, 0) }
                    
                    // Verifica doppia (race condition protection)
                    if self.isEmailProcessed(messageId: email.id, context: context) {
                        return (0, 0)
                    }
                    
                    return await self.processSingleEmail(email, context: context, isReprocessing: false)
                }
            }
            
            var totalProcessed = 0
            var totalEvents = 0
            
            for await (processed, events) in group {
                totalProcessed += processed
                totalEvents += events
            }
            
            completion(totalProcessed, totalEvents)
        }
    }
    
    /// Processa una singola email
    private func processSingleEmail(_ email: Email, context: NSManagedObjectContext, isReprocessing: Bool = false) async -> (Int, Int) {
        activeProcessingTasks += 1
        defer { activeProcessingTasks -= 1 }
        
        do {
            // SKIP: email letta associata a sinistro chiuso (evita elaborare storico)
            if await ClosedSinistroEmailIndex.shared.shouldSkipProcessing(emailId: email.id, isRead: email.isRead) {
                markEmailAsProcessed(messageId: email.id, context: context)
                // Marca come saltata invece di processata
                await updateProcessingStatus(
                    forEmailId: email.id,
                    status: .saltata,
                    result: "Email saltata (sinistro chiuso o troppo vecchia)"
                )
                return (1, 0)
            }
            
            // Marca come in corso di processamento
            await updateProcessingStatus(forEmailId: email.id, status: .inCorso)
            
            // 1. Ottieni mailboxId per determinare se è nella mailbox SENT
            let mailboxId = repository.getMailbox(forEmailId: email.id)
            
            // 2. Verifica se email è unread (ha label UNREAD)
            // isRead == false significa che ha label UNREAD (non letta)
            let isUnread = !email.isRead
            
            // 3. Classifica l'email (passa mailboxId per riconoscere email nella mailbox SENT)
            let classified = classifier.classify(email, mailboxId: mailboxId)
            
            // 4. Aggiorna statistiche
            updateStats(for: classified)
            
            // 5. Trova handler appropriato
            guard let handler = EmailHandlerRegistry.shared.findHandler(for: classified) else {
                print("[MailManager] ⚠️ Nessun handler per categoria: \(classified.category)")
                markEmailAsProcessed(messageId: email.id, context: context)
                return (1, 0)
            }
            
            // 6. Processa con handler (passa isUnread)
            // Se email è letta (isUnread == false), handler non genererà task/aggiornamenti
            // ma aggiungerà comunque al diario
            if let event = await handler.handle(classified, context: context, isUnread: isUnread) {
                // 7. Pubblica evento su entrambi i bus (legacy + unified)
                // Assegnazioni vengono sempre pubblicate (per creare/verificare sinistro)
                // Atti e documentazione solo se email non letta (per aggiornare stato)
                let shouldPublish = isUnread || classified.category == .assignment
                
                if shouldPublish {
                    eventBus.publish(event)
                    publishToUnifiedBus(event, classified: classified)
                    
                    // Aspetta conferma da ClaimEngine prima di marcare come processata
                    let processingResult = await waitForClaimEngineConfirmation(
                        emailId: email.id,
                        expectedAction: getExpectedAction(for: classified.category),
                        timeout: 10.0 // 10 secondi timeout
                    )
                    
                    // Aggiorna stato in base al risultato
                    // NOTA: updateProcessingStatusBasedOnResult marca come processata in Core Data
                    // quando il ClaimEngine risponde con successo, garantendo che la mail
                    // non venga riprocessata ad ogni avvio
                    await updateProcessingStatusBasedOnResult(
                        emailId: email.id,
                        result: processingResult,
                        expectedAction: getExpectedAction(for: classified.category)
                    )
                    
                    // Marca come processata se ignorato con stessa data (per assegnazioni)
                    // Il caso di successo è già gestito in updateProcessingStatusBasedOnResult
                    let isIgnoredSameDate = processingResult?.resultType == .ignored &&
                        processingResult?.details["stessaData"] as? Bool == true
                    let shouldMarkAsProcessed = isIgnoredSameDate && classified.category == .assignment
                    
                    if shouldMarkAsProcessed {
                        markEmailAsProcessed(messageId: email.id, context: context)
                        
                        // Auto-marca come letta se abilitato per questa categoria
                        if EmailAutoReadSettings.shared.isCategoryEnabled(classified.category) {
                            await markEmailAsReadIfNeeded(emailId: email.id)
                        }
                    } else if processingResult?.resultType == .success {
                        // Auto-marca come letta se abilitato per questa categoria (già marcata come processata in updateProcessingStatusBasedOnResult)
                        if EmailAutoReadSettings.shared.isCategoryEnabled(classified.category) {
                            await markEmailAsReadIfNeeded(emailId: email.id)
                        }
                    }
                } else {
                    // Non pubblicato, marca come processata comunque
                    markEmailAsProcessed(messageId: email.id, context: context)
                    await updateProcessingStatus(
                        forEmailId: email.id,
                        status: .processata,
                        result: getProcessingResultDescription(for: event, category: classified.category)
                    )
                    
                    // Auto-marca come letta se abilitato per questa categoria
                    if EmailAutoReadSettings.shared.isCategoryEnabled(classified.category) {
                        await markEmailAsReadIfNeeded(emailId: email.id)
                    }
                }
                
                // 7a. Prova associazione automatica email-sinistro (dopo processamento handler)
                // Usa forceReassociation solo se è un riprocessamento esplicito
                await EmailAssociationService.shared.tryAutomaticAssociation(email, context: context, forceReassociation: isReprocessing)
                
                return (1, shouldPublish ? 1 : 0)
            }
            
            // 7b. Se handler non ha generato eventi, prova associazione automatica e poi aggiungi al diario
            // Usa forceReassociation solo se è un riprocessamento esplicito
            await EmailAssociationService.shared.tryAutomaticAssociation(email, context: context, forceReassociation: isReprocessing)
            await ensureEmailInDiario(email: email, context: context)
            
            // Marca come processata solo se il body è disponibile
            if email.body != nil {
                markEmailAsProcessed(messageId: email.id, context: context)
                // Handler non ha prodotto evento ma ha comunque processato
                await updateProcessingStatus(
                    forEmailId: email.id,
                    status: .processata,
                    result: "Aggiunta al diario"
                )
                
                // Auto-marca come letta se abilitato per questa categoria
                if EmailAutoReadSettings.shared.isCategoryEnabled(classified.category) {
                    await markEmailAsReadIfNeeded(emailId: email.id)
                }
            } else {
                print("[MailManager] ⏸️ Email \(email.id) senza body, non marcata come processata")
            }
            return (1, 0)
            
        } catch {
            print("[MailManager] ❌ Errore processamento email \(email.id): \(error)")
            // Aggiorna stato processamento come errore
            await updateProcessingStatus(
                forEmailId: email.id,
                status: .errore,
                error: error.localizedDescription
            )
            return (0, 0)
        }
    }
    
    /// Processa una singola email (con controllo se già processata)
    func processEmail(_ email: Email, context: NSManagedObjectContext, isReprocessing: Bool = false) async -> (any EmailEvent)? {
        // Verifica se già processata (solo se non è un riprocessamento)
        if !isReprocessing && isEmailProcessed(messageId: email.id, context: context) {
            print("[MailManager] ⏭️ Email \(email.id) già processata, skip")
            return nil
        }
        
        // SKIP: email letta associata a sinistro chiuso
        if await ClosedSinistroEmailIndex.shared.shouldSkipProcessing(emailId: email.id, isRead: email.isRead) {
            markEmailAsProcessed(messageId: email.id, context: context)
            // Marca come saltata invece di processata
            await updateProcessingStatus(
                forEmailId: email.id,
                status: .saltata,
                result: "Email saltata (sinistro chiuso o troppo vecchia)"
            )
            return nil
        }
        
        // Marca come in corso di processamento
        await updateProcessingStatus(forEmailId: email.id, status: .inCorso)
        
        // Ottieni mailboxId per determinare se è nella mailbox SENT
        let mailboxId = repository.getMailbox(forEmailId: email.id)
        
        // Verifica se email è unread (ha label UNREAD)
        let isUnread = !email.isRead
        
        let classified = classifier.classify(email, mailboxId: mailboxId)
        updateStats(for: classified)
        
        guard let handler = EmailHandlerRegistry.shared.findHandler(for: classified) else {
            print("[MailManager] ⚠️ Nessun handler per categoria: \(classified.category)")
            markEmailAsProcessed(messageId: email.id, context: context)
            return nil
        }
        
        if let event = await handler.handle(classified, context: context, isUnread: isUnread) {
            // Pubblica su legacy bus e unified bus
            // Assegnazioni vengono sempre pubblicate (per creare/verificare sinistro)
            // Atti e documentazione solo se email non letta (per aggiornare stato)
            let shouldPublish = isUnread || classified.category == .assignment
            
            if shouldPublish {
                eventBus.publish(event)
                publishToUnifiedBus(event, classified: classified)
                
                // Aspetta conferma da ClaimEngine prima di marcare come processata
                let processingResult = await waitForClaimEngineConfirmation(
                    emailId: email.id,
                    expectedAction: getExpectedAction(for: classified.category),
                    timeout: 10.0 // 10 secondi timeout
                )
                
                // Aggiorna stato in base al risultato
                // NOTA: updateProcessingStatusBasedOnResult marca come processata in Core Data
                // quando il ClaimEngine risponde con successo, garantendo che la mail
                // non venga riprocessata ad ogni avvio
                await updateProcessingStatusBasedOnResult(
                    emailId: email.id,
                    result: processingResult,
                    expectedAction: getExpectedAction(for: classified.category)
                )
            } else {
                // Non pubblicato, marca come processata comunque
                markEmailAsProcessed(messageId: email.id, context: context)
            }
            
            // Prova associazione automatica email-sinistro (dopo processamento handler)
            // Usa forceReassociation solo se è un riprocessamento esplicito
            await EmailAssociationService.shared.tryAutomaticAssociation(email, context: context, forceReassociation: isReprocessing)
            
            return shouldPublish ? event : nil
        }
        
        // Se handler non ha generato eventi, prova associazione automatica e poi aggiungi al diario
        await EmailAssociationService.shared.tryAutomaticAssociation(email, context: context)
        await ensureEmailInDiario(email: email, context: context)
        
        // Marca come processata solo se il body è disponibile
        // Altrimenti riprocesseremo quando avremo il body (es. assegnazioni)
        if email.body != nil {
            markEmailAsProcessed(messageId: email.id, context: context)
        } else {
            print("[MailManager] ⏸️ Email \(email.id) senza body, non marcata come processata per riprocessazione futura")
        }
        return nil
    }
    
    // MARK: - Sync & Fetch
    
    /// Sincronizza email da Gmail per una casella specifica
    func syncMailbox(_ mailboxId: String, context: NSManagedObjectContext) async {
        // Esegui in background per non bloccare la UI
        await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            guard let accessToken = try? await self.authService.getAccessToken() else {
                await MainActor.run {
                    self.errorMessage = "Token di accesso non valido"
                }
                return
            }
            
            // Verifica se è un errore 401 e riautentica
            do {
                // Fetch lista messaggi con limit ragionevole (max 100 per evitare troppe richieste)
                let messageIds = try await self.fetchEmailList(mailboxId: mailboxId, accessToken: accessToken, maxResults: 100)
                
                // Filtra solo nuovi (deve essere fatto sul MainActor perché repository è isolato)
                let existingIds = await MainActor.run {
                    Set(self.repository.getEmails(forMailbox: mailboxId).map { $0.id })
                }
                let newIds = messageIds.filter { !existingIds.contains($0) }
                
                guard !newIds.isEmpty else {
                    print("[MailManager] ✓ \(mailboxId): nessuna nuova email")
                    return
                }
                
                print("[MailManager] 📥 \(mailboxId): \(newIds.count) nuove email da scaricare")
                
                // Limita a 30 nuove email per volta per evitare rate limiting e ridurre CPU
                let limitedNewIds = Array(newIds.prefix(30))
                
                // Scarica dettagli sequenzialmente con throttling per rispettare rate limit Gmail
                // (non in parallelo per evitare troppe richieste simultanee)
                var newEmails: [Email] = []
                
                for (index, messageId) in limitedNewIds.enumerated() {
                    // Throttling tra richieste (almeno 300ms per rispettare rate limit Gmail)
                    if index > 0 {
                        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms tra richieste
                    }
                    
                    do {
                        let detail = try await self.gmailService.fetchEmailDetails(messageId: messageId)
                        let email = self.convertToEmail(detail, mailboxId: mailboxId)
                        newEmails.append(email)
                        
                        // Salva in repository (deve essere fatto sul MainActor perché repository è isolato)
                        await MainActor.run {
                            _ = self.repository.addOrUpdateEmail(email, forMailbox: mailboxId)
                        }
                    } catch {
                        // Gestisci errori 401 (riautenticazione) - prova a refreshare
                        if let gmailError = error as? GmailAPIError,
                           case .badServerResponse(let statusCode, _) = gmailError,
                           statusCode == 401 {
                            print("[MailManager] ⚠️ Token scaduto per \(mailboxId), tentativo refresh...")
                            
                            // Prova a refreshare il token
                            let refreshSuccess = await self.authService.refreshTokenIfNeeded()
                            
                            if refreshSuccess {
                                // Token refreshato, riprova questa email
                                print("[MailManager] ✅ Token refreshato, riprovo email \(messageId)...")
                                do {
                                    let detail = try await self.gmailService.fetchEmailDetails(messageId: messageId)
                                    let email = self.convertToEmail(detail, mailboxId: mailboxId)
                                    newEmails.append(email)
                                    
                                    await MainActor.run {
                                        _ = self.repository.addOrUpdateEmail(email, forMailbox: mailboxId)
                                    }
                                } catch {
                                    print("[MailManager] ❌ Errore scaricamento \(messageId) dopo refresh: \(error)")
                                    // Se anche dopo refresh fallisce, potrebbe essere un problema diverso
                                    // Continua con le prossime email
                                }
                            } else {
                                // Refresh fallito, richiedi riautenticazione
                                print("[MailManager] ❌ Refresh token fallito, richiesta riautenticazione...")
                                await MainActor.run {
                                    self.errorMessage = "Token di autenticazione scaduto. Riautenticazione richiesta."
                                }
                                // Ferma il download per questa casella
                                break
                            }
                        } else {
                            print("[MailManager] ❌ Errore scaricamento \(messageId): \(error)")
                            // Continua con le prossime email anche in caso di errore
                        }
                    }
                }
                
                // Aggiungi email alla queue per processamento (non blocca)
                if !newEmails.isEmpty {
                    print("[MailManager] ✅ \(mailboxId): scaricate \(newEmails.count) email, aggiunte in coda...")
                    await EmailQueueService.shared.enqueue(newEmails, autoStart: true)
                }
                
            } catch {
                // Gestisci errori 401 (riautenticazione) - prova a refreshare
                if let gmailError = error as? GmailAPIError,
                   case .badServerResponse(let statusCode, _) = gmailError,
                   statusCode == 401 {
                    print("[MailManager] ⚠️ Token scaduto per \(mailboxId), tentativo refresh...")
                    
                    // Prova a refreshare il token
                    let refreshSuccess = await self.authService.refreshTokenIfNeeded()
                    
                    if refreshSuccess {
                        // Token refreshato, riprova la sync
                        print("[MailManager] ✅ Token refreshato, riprovo sync \(mailboxId)...")
                        // Richiama syncMailbox per riprovare
                        await self.syncMailbox(mailboxId, context: context)
                    } else {
                        // Refresh fallito, richiedi riautenticazione
                        print("[MailManager] ❌ Refresh token fallito, richiesta riautenticazione...")
                        await MainActor.run {
                            self.errorMessage = "Token di autenticazione scaduto. Riautenticazione richiesta."
                            self.isProcessing = false
                        }
                        // Ferma il monitoring per evitare loop di errori
                        await MainActor.run {
                            self.stopMonitoring()
                        }
                    }
                } else {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                    }
                    print("[MailManager] ❌ Errore sync \(mailboxId): \(error)")
                }
            }
        }
    }
    
    /// Sincronizza tutte le caselle con throttling per evitare rate limiting (sequenziale per rispettare rate limit)
    func syncAllMailboxes(context: NSManagedObjectContext) async {
        _ = context
        print("[MailManager] Sync locale Gmail disabilitato: email gestite dal backend Resend")
    }

    /// Sincronizza tutte le email di assegnazione NON LETTE ("Assegnazione perito") presenti nell'account.
    /// - Nota: usa query Gmail + paginazione completa, poi salva l'email in TUTTE le labelIds del messaggio,
    ///   così appare correttamente anche nella casella/etichetta "Assegnate".
    private func syncUnreadAssignmentEmails(context: NSManagedObjectContext) async {
        _ = context
        return
    }
    
    // MARK: - Bulk Metadata Fetch (spostato da MailViewModel)
    
    /// Scarica e indicizza i metadati delle email per una lista di label Gmail.
    /// Questo è il percorso "pesante" e deve stare nei servizi, non nelle view/view model.
    /// - Parameters:
    ///   - labels: etichette Gmail da processare
    ///   - prioritizeMailboxId: ID dell'etichetta da processare per prima (opzionale)
    ///   - progress: callback UI (status, 0...1)
    func fetchAndProcessEmailsForLabels(
        labels: [GmailLabel],
        prioritizeMailboxId: String? = nil,
        progress: ((String, Double) -> Void)? = nil
    ) async {
        guard let accessToken = try? await authService.getAccessToken() else {
            errorMessage = "Token di accesso non valido"
            return
        }
        
        let totalLabels = labels.count
        guard totalLabels > 0 else { return }
        
        // Ordina le etichette per processare prima quella prioritaria
        var sortedLabels = labels
        if let prioritizeId = prioritizeMailboxId {
            if let index = sortedLabels.firstIndex(where: { $0.id == prioritizeId }) {
                let priorityLabel = sortedLabels.remove(at: index)
                sortedLabels.insert(priorityLabel, at: 0)
                print("[MailManager] 🚀 Prioritizzazione etichetta: \(priorityLabel.name) (\(prioritizeId))")
            }
        }
        
        print("[MailManager] Inizio processamento di \(totalLabels) etichette")
        progress?("Inizializzazione...", 0.0)
        
        var processedLabels = 0
        var totalMessagesAcrossLabels = 0
        var processedMessagesAcrossLabels = 0
        
        for (index, label) in sortedLabels.enumerated() {
            if Task.isCancelled { break }
            
            let labelPrefix = "[\(index + 1)/\(totalLabels)]"
            print("[MailManager] \(labelPrefix) Processamento etichetta: \(label.name) (ID: \(label.id))")
            progress?("Scaricamento \(label.name)...", Double(processedLabels) / Double(totalLabels))
            
            do {
                let messageIds = try await fetchMessageIds(labelId: label.id, accessToken: accessToken)
                totalMessagesAcrossLabels += messageIds.count
                
                if messageIds.isEmpty {
                    processedLabels += 1
                    continue
                }
                
                await fetchMetadataIncremental(
                    messageIds: messageIds,
                    accessToken: accessToken,
                    mailboxId: label.id,
                    labelName: label.name,
                    totalLabels: totalLabels,
                    processedLabels: &processedLabels,
                    totalMessagesAcrossLabels: totalMessagesAcrossLabels,
                    processedMessagesAcrossLabels: &processedMessagesAcrossLabels,
                    progress: progress
                )
                
                processedLabels += 1
                
                // Pausa leggera tra label per respirare/rate limit
                try? await Task.sleep(nanoseconds: messageIds.count > 100 ? 1_000_000_000 : 300_000_000)
                
            } catch {
                print("[MailManager] ❌ ERRORE nel caricare email per l'etichetta \(label.name): \(error)")
                continue
            }
        }
        
        // Salva cache (repository gestisce persistenza)
        progress?("Salvataggio cache...", 0.98)
        repository.saveToCache()
        
        let totalEmails = repository.getStats().totalEmails
        print("[MailManager] ✅ Completato download metadati. Totale email: \(totalEmails)")
        progress?("Completato: \(totalEmails) email", 1.0)
        
        // Avvia automazione se abilitata - usa queue per non bloccare
        if AutomationSettingsService.shared.isAutomationEnabled {
            let allEmails = repository.getAllEmails()
            print("[MailManager] Aggiunta di \(allEmails.count) email alla coda di processamento...")
            await EmailQueueService.shared.enqueue(allEmails, autoStart: true)
        }
    }
    
    /// Scarica metadati in batch e aggiorna repository incrementalmente.
    private func fetchMetadataIncremental(
        messageIds: [String],
        accessToken: String,
        mailboxId: String,
        labelName: String,
        totalLabels: Int,
        processedLabels: inout Int,
        totalMessagesAcrossLabels: Int,
        processedMessagesAcrossLabels: inout Int,
        progress: ((String, Double) -> Void)?
    ) async {
        let totalMessagesForLabel = messageIds.count
        print("[MailManager] Inizio download metadati per \(labelName): \(totalMessagesForLabel) messaggi")
        
        // Limita risorse
        let batchSize = 3
        let maxConcurrentTasks = 2
        var processedInLabel = 0
        
        for batchStart in stride(from: 0, to: totalMessagesForLabel, by: batchSize) {
            if Task.isCancelled { break }
            
            let batchEnd = min(batchStart + batchSize, totalMessagesForLabel)
            let batch = Array(messageIds[batchStart..<batchEnd])
            
            await withTaskGroup(of: Email?.self) { group in
                var activeCount = 0
                
                for messageId in batch {
                    while activeCount >= maxConcurrentTasks {
                        _ = await group.next()
                        activeCount -= 1
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                    
                    activeCount += 1
                    group.addTask(priority: .utility) { [weak self] in
                        guard let self else { return nil }
                        do {
                            let detail = try await self.fetchGmailMessageDetail(
                                messageId: messageId,
                                accessToken: accessToken,
                                format: "metadata"
                            )
                            return self.convertToEmail(detail, mailboxId: mailboxId)
                        } catch {
                            return nil
                        }
                    }
                }
                
                for await email in group {
                    if let email {
                        _ = repository.addOrUpdateEmail(email, forMailbox: mailboxId)
                        processedInLabel += 1
                        processedMessagesAcrossLabels += 1
                    }
                }
            }
            
            // Progress UI
            let labelProgress = totalMessagesForLabel > 0 ? Double(processedInLabel) / Double(totalMessagesForLabel) : 1.0
            let overall = totalMessagesAcrossLabels > 0 ? Double(processedMessagesAcrossLabels) / Double(totalMessagesAcrossLabels) : 0.0
            let status = "Scaricamento \(labelName)... \(Int(labelProgress * 100))%"
            progress?(status, min(0.97, overall))
            
            // Pausa tra batch
            if batchEnd < totalMessagesForLabel {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        
        print("[MailManager] ✅ Completato \(labelName): \(processedInLabel)/\(totalMessagesForLabel)")
    }
    
    /// Lista messageIds con paginazione (labelId opzionale, query opzionale).
    private func fetchMessageIds(labelId: String? = nil, accessToken: String, query: String? = nil) async throws -> [String] {
        throw GmailAPIError.tokenError("MailManager Gmail disabilitato: usare backend/Resend.")
    }
    
    private func fetchGmailMessageDetail(messageId: String, accessToken: String, format: String) async throws -> GmailMessageDetail {
        throw GmailAPIError.tokenError("MailManager Gmail disabilitato: usare backend/Resend.")
    }
    
    // MARK: - Monitoring
    
    /// Avvia il monitoring periodico delle email (in background per non bloccare la UI)
    func startMonitoring(interval: TimeInterval = 600) { // Aumentato da 300s a 600s (10 minuti)
        guard !isMonitoringActive else {
            print("[MailManager] ⚠️ Monitoring già attivo")
            return
        }
        print("[MailManager] Monitoring locale Gmail disabilitato: email gestite dal backend Resend")
    }
    
    /// Ferma il monitoring
    func stopMonitoring() {
        isMonitoringActive = false
        print("[MailManager] ⏹️ Monitoring fermato")
    }
    
    // MARK: - Manual Processing
    
    /// Riprocessa email esistenti (utile dopo aggiornamenti handler)
    func reprocessEmails(forMailbox mailboxId: String, context: NSManagedObjectContext) async {
        let emails = repository.getEmails(forMailbox: mailboxId)
        await processEmails(emails, context: context)
    }
    
    /// Classifica email senza processarla (utile per preview)
    /// - Parameters:
    ///   - email: L'email da classificare
    ///   - mailboxId: ID della mailbox (opzionale, usato per riconoscere email nella mailbox SENT)
    func classifyOnly(_ email: Email, mailboxId: String? = nil) -> ClassifiedEmail {
        // Se mailboxId non fornito, prova a recuperarlo dal repository
        let finalMailboxId = mailboxId ?? repository.getMailbox(forEmailId: email.id)
        return classifier.classify(email, mailboxId: finalMailboxId)
    }
    
    // MARK: - On-Demand Email Download
    
    /// Verifica se un'email deve essere mantenuta in cache
    /// Mantiene in cache se: ha meno di 7 giorni O è associata a un sinistro attivo (non chiuso)
    private func shouldKeepEmailInCache(emailId: String, emailDate: Date?, context: NSManagedObjectContext) -> Bool {
        // Controlla se ha meno di 7 giorni
        if let emailDate = emailDate {
            let daysSinceEmail = Calendar.current.dateComponents([.day], from: emailDate, to: Date()).day ?? 0
            if daysSinceEmail < 7 {
                return true
            }
        }
        
        // Controlla se è associata a un sinistro attivo (non chiuso)
        // Non possiamo usare CONTAINS su campi Transformable, quindi facciamo fetch e filtriamo in memoria
        var result = false
        context.performAndWait {
            let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
            
            guard let threads = try? context.fetch(request) else {
                return
            }
            
            // Filtra in memoria usando messageIds (proprietà calcolata)
            let matchingThread = threads.first { thread in
                thread.messageIds.contains(emailId)
            }
            
            guard let thread = matchingThread,
                  let sinistro = thread.sinistro,
                  let stato = sinistro.stato else {
                return
            }
            
            // Sinistro attivo se stato != "Chiusa" (SV090)
            result = stato != StatoManager.StatoSinistro.chiusa.rawValue && stato != "Chiusa"
        }
        
        return result
    }
    
    /// Scarica il corpo completo di un'email se non presente in locale
    /// - Parameters:
    ///   - emailId: ID dell'email da scaricare
    ///   - context: Contesto Core Data per processare l'email dopo il download
    ///   - forceDownload: Se true, scarica anche se già processata (per visualizzazione utente)
    /// - Returns: Email completa con body, o nil se errore
    func fetchFullEmail(emailId: String, context: NSManagedObjectContext, forceDownload: Bool = false) async throws -> Email? {
        // 1. Controlla se è già in cache
        if let cached = cacheService.loadFullEmail(forId: emailId), cached.body != nil {
            // Verifica se deve essere rimossa dalla cache (vecchia o sinistro chiuso)
            let shouldKeep = shouldKeepEmailInCache(emailId: emailId, emailDate: cached.date, context: context)
            if !shouldKeep {
                // Rimuovi dalla cache ma mantieni nel repository per permettere download on-demand
                cacheService.removeEmail(forId: emailId)
                print("[MailManager] 🗑️ Email \(emailId) rimossa dalla cache (vecchia o sinistro chiuso)")
            } else {
                print("[MailManager] ✅ Email \(emailId) già in cache")
                // Verifica se già processata, altrimenti processa
                if !isEmailProcessed(messageId: emailId, context: context) {
                    await processEmail(cached, context: context)
                }
                return cached
            }
        }
        
        // 2. Controlla se è nel repository ma senza body
        if let existing = repository.getEmail(byId: emailId), existing.body != nil {
            print("[MailManager] ✅ Email \(emailId) già scaricata nel repository")
            // Verifica se già processata, altrimenti processa
            if !isEmailProcessed(messageId: emailId, context: context) {
                await processEmail(existing, context: context)
            }
            return existing
        }
        
        // 3. Se già processata ma forceDownload è false, non scaricare (solo se non richiesto dall'utente)
        if !forceDownload && isEmailProcessed(messageId: emailId, context: context) {
            print("[MailManager] ⏭️ Email \(emailId) già processata, skip download (usa forceDownload=true per forzare)")
            return nil
        }
        
        // 4. Scarica da Gmail
        print("[MailManager] 📥 Download email \(emailId) da Gmail...")
        
        do {
            let detail = try await gmailService.fetchEmailDetails(messageId: emailId)
            
            // 5. Determina la mailbox dall'email
            let mailboxId = detail.labelIds.first { labelId in
                let stats = repository.getStats()
                return stats.emailsPerMailbox.keys.contains(labelId)
            } ?? detail.labelIds.first ?? "INBOX"
            
            // 6. Converti in Email
            let email = convertToEmail(detail, mailboxId: mailboxId)
            
            // 7. Salva in cache solo se deve essere mantenuta
            let shouldKeep = shouldKeepEmailInCache(emailId: emailId, emailDate: email.date, context: context)
            if shouldKeep {
                cacheService.saveFullEmail(email, forId: email.id)
            } else {
                print("[MailManager] ℹ️ Email \(emailId) non salvata in cache (vecchia o sinistro chiuso)")
            }
            
            // 8. Aggiungi/aggiorna nel repository (sempre, per permettere download on-demand)
            repository.addOrUpdateEmail(email, forMailbox: mailboxId)
            
            // 9. Processa l'email SOLO se non già processata
            if !isEmailProcessed(messageId: email.id, context: context) {
                await processEmail(email, context: context)
            }
            
            print("[MailManager] ✅ Email \(emailId) scaricata e processata")
            return email
            
        } catch {
            // Gestisci errori 401 (autenticazione scaduta) - prova a refreshare il token
            if let gmailError = error as? GmailAPIError,
               case .badServerResponse(let statusCode, _) = gmailError,
               statusCode == 401 {
                print("[MailManager] ⚠️ Token di autenticazione scaduto per email \(emailId), tentativo refresh...")
                
                // Prova a refreshare il token
                let refreshSuccess = await authService.refreshTokenIfNeeded()
                
                if refreshSuccess {
                    // Token refreshato, riprova il download
                    print("[MailManager] 🔄 Token refreshato, riprovo download email \(emailId)...")
                    do {
                        let detail = try await gmailService.fetchEmailDetails(messageId: emailId)
                        
                        // Determina la mailbox dall'email
                        let mailboxId = detail.labelIds.first { labelId in
                            let stats = repository.getStats()
                            return stats.emailsPerMailbox.keys.contains(labelId)
                        } ?? detail.labelIds.first ?? "INBOX"
                        
                        // Converti in Email
                        let email = convertToEmail(detail, mailboxId: mailboxId)
                        
                        // Salva in cache solo se deve essere mantenuta
                        let shouldKeep = shouldKeepEmailInCache(emailId: emailId, emailDate: email.date, context: context)
                        if shouldKeep {
                            cacheService.saveFullEmail(email, forId: email.id)
                        }
                        
                        // Aggiungi/aggiorna nel repository
                        repository.addOrUpdateEmail(email, forMailbox: mailboxId)
                        
                        // Processa l'email SOLO se non già processata
                        if !isEmailProcessed(messageId: email.id, context: context) {
                            await processEmail(email, context: context)
                        }
                        
                        print("[MailManager] ✅ Email \(emailId) scaricata dopo refresh token")
                        return email
                    } catch {
                        print("[MailManager] ❌ Errore download email \(emailId) dopo refresh: \(error)")
                        return nil
                    }
                } else {
                    // Refresh fallito, richiedi riautenticazione
                    print("[MailManager] ❌ Refresh token fallito, richiesta riautenticazione")
                    await MainActor.run {
                        self.errorMessage = "Token di autenticazione scaduto. Riautenticazione richiesta."
                    }
                    throw GmailAPIError.authenticationRequired("Token di autenticazione scaduto e refresh fallito")
                }
            }
            print("[MailManager] ❌ Errore download email \(emailId): \(error)")
            return nil
        }
    }
    
    // MARK: - Auto-Read Helpers
    
    /// Marca un'email come letta se necessario (solo se non già letta)
    private func markEmailAsReadIfNeeded(emailId: String) async {
        guard let email = repository.getEmail(byId: emailId), !email.isRead else {
            return
        }
        
        print("[MailManager] 📌 Auto-marcatura come letta per email \(emailId)")
        await MainActor.run {
            MailViewModel.shared.markEmailAsRead(emailId: emailId)
        }
    }
    
    // MARK: - Private Helpers
    
    private func updateStats(for classified: ClassifiedEmail) {
        classificationStats.totalProcessed += 1
        classificationStats.byCategory[classified.category, default: 0] += 1
        classificationStats.byDirection[classified.direction, default: 0] += 1
    }
    
    private func fetchEmailList(mailboxId: String, accessToken: String, maxResults: Int = 100) async throws -> [String] {
        throw GmailAPIError.tokenError("MailManager Gmail disabilitato: usare backend/Resend.")
    }
    
    nonisolated private func convertToEmail(_ detail: GmailMessageDetail, mailboxId: String) -> Email {
        let headers = detail.payload.headers
        
        let subject = headers.first { $0.name.lowercased() == "subject" }?.value ?? "(Nessun oggetto)"
        let from = headers.first { $0.name.lowercased() == "from" }?.value ?? ""
        let to = headers.first { $0.name.lowercased() == "to" }?.value ?? ""
        let dateHeader = headers.first { $0.name.lowercased() == "date" }?.value
        
        // Parse date
        let date: Date
        if let dateHeader = dateHeader, let parsed = EmailDateParser.date(from: dateHeader) {
            date = parsed
        } else if let internalDate = EmailDateParser.date(fromInternalDate: detail.internalDate) {
            date = internalDate
        } else {
            date = Date()
        }
        
        // Parse sender
        let sender = parseSender(from: from)
        
        // Decode body
        let body = decodeEmailBody(detail.payload)
        
        // Parse attachments
        let attachments = parseAttachments(from: detail.payload)
        
        // Determina isRead basandosi sulla presenza di label "UNREAD"
        // Se "UNREAD" è presente in labelIds, l'email è non letta (isRead = false)
        let isRead = !detail.labelIds.contains("UNREAD")
        
        return Email(
            id: detail.id,
            isRead: isRead,
            isDownloaded: body != nil,
            sender: sender,
            recipients: parseRecipients(from: to),
            subject: subject,
            date: date,
            body: body,
            attachments: attachments
        )
    }
    
    nonisolated private func parseSender(from: String) -> Contact {
        // Parse "Nome <email@example.com>" format
        let pattern = "^(.+?)\\s*<([^>]+)>$"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: from, range: NSRange(from.startIndex..., in: from)) {
            
            if let nameRange = Range(match.range(at: 1), in: from),
               let emailRange = Range(match.range(at: 2), in: from) {
                let name = String(from[nameRange]).trimmingCharacters(in: .whitespaces)
                let email = String(from[emailRange]).trimmingCharacters(in: .whitespaces)
                return Contact(name: name, email: email)
            }
        }
        
        // Fallback: use as email
        return Contact(name: nil, email: from.trimmingCharacters(in: .whitespaces))
    }
    
    nonisolated private func parseRecipients(from: String) -> [Contact] {
        return from.components(separatedBy: ",").map { parseSender(from: $0) }
    }
    
    nonisolated private func decodeEmailBody(_ payload: MessagePayloadDetail) -> String? {
        // Try parts first
        if let parts = payload.parts {
            for part in parts {
                if part.mimeType == "text/plain" || part.mimeType == "text/html",
                   let data = part.body.data,
                   let decoded = decodeBase64(data) {
                    return decoded
                }
            }
        }
        
        // Try direct body
        if let data = payload.body?.data,
           let decoded = decodeBase64(data) {
            return decoded
        }
        
        return nil
    }
    
    nonisolated private func decodeBase64(_ base64: String) -> String? {
        let cleaned = base64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        guard let data = Data(base64Encoded: cleaned) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    nonisolated private func parseAttachments(from payload: MessagePayloadDetail) -> [EmailAttachment]? {
        guard let parts = payload.parts else { return nil }
        
        let attachments = parts.compactMap { part -> EmailAttachment? in
            // filename è String, non optional - controlla solo se vuoto
            guard !part.filename.isEmpty else { return nil }
            
            return EmailAttachment(
                attachmentId: part.body.attachmentId ?? "",
                filename: part.filename,
                size: part.body.size ?? 0
            )
        }
        
        return attachments.isEmpty ? nil : attachments
    }
    
    // MARK: - Reset Stats
    
    func resetStats() {
        classificationStats = ClassificationStats()
        print("[MailManager] Statistiche resettate")
    }
    
    // MARK: - Unified Event Bus Integration
    
    /// Pubblica un evento legacy su UnifiedEventBus convertendolo in ClaimEvent
    private func publishToUnifiedBus(_ event: any EmailEvent, classified: ClassifiedEmail) {
        let intent = mapCategoryToIntent(classified.category)
        let senderType = mapSenderType(classified.originalEmail.sender.email)
        
        // Crea ClaimEvent appropriato in base al tipo di evento legacy
        switch event {
        case let assignmentEvent as EmailAssignmentReceived:
            let claimEvent = EmailAssignmentEvent(
                emailId: assignmentEvent.emailId,
                riferimento: assignmentEvent.riferimento,
                assignmentDate: assignmentEvent.assignmentDate,
                assigneeEmail: assignmentEvent.assigneeEmail,
                assigneeName: assignmentEvent.assigneeName,
                extractedData: assignmentEvent.extractedData
            )
            print("[MailManager] 📤 Pubblicazione evento assegnazione: \(assignmentEvent.riferimento) - data: \(assignmentEvent.assignmentDate) - emailId: \(assignmentEvent.emailId)")
            unifiedEventBus.publishAssignment(claimEvent)
            print("[MailManager] ✅ Evento assegnazione pubblicato su UnifiedEventBus (emailId: \(assignmentEvent.emailId))")
            
        case let revocationEvent as EmailRevocationReceived:
            let claimEvent = EmailRevocationEvent(
                emailId: revocationEvent.emailId,
                riferimento: revocationEvent.riferimento,
                reason: revocationEvent.reason
            )
            unifiedEventBus.publishRevocation(claimEvent)
            
        default:
            // Per altri tipi, crea un EmailClaimEvent generico
            let claimEvent = EmailClaimEvent(
                emailId: event.emailId,
                sinistroId: event.sinistroId,
                direction: event.direction == .inbound ? .inbound : .outbound,
                intent: intent,
                senderType: senderType,
                subject: classified.originalEmail.subject,
                hasAttachments: classified.hasAttachments,
                attachmentCount: classified.originalEmail.attachments?.count ?? 0,
                metadata: event.metadata
            )
            unifiedEventBus.publishEmail(claimEvent)
        }
    }
    
    /// Determina l'azione attesa per una categoria email
    private func getExpectedAction(for category: EmailCategory) -> ClaimEngineDecision.ActionType {
        switch category {
        case .assignment:
            return .logToDiary // Per assegnazioni, ci aspettiamo che venga aggiornata la data
        case .revocation:
            return .autoStateChange // Per revoche, ci aspettiamo cambio stato
        case .actSent, .actReceived:
            return .logToDiary
        case .documentationReceived, .documentationRequest:
            return .logToDiary
        default:
            return .logToDiary
        }
    }
    
    /// Aspetta la conferma da ClaimEngine per un'email
    private func waitForClaimEngineConfirmation(
        emailId: String,
        expectedAction: ClaimEngineDecision.ActionType,
        timeout: TimeInterval
    ) async -> ClaimEngineResult? {
        print("[MailManager] ⏳ In attesa conferma ClaimEngine per email \(emailId)...")
        
        return await withTaskGroup(of: ClaimEngineResult?.self) { group in
            // Task 1: Aspetta il risultato da ClaimEngine
            group.addTask {
                await withCheckedContinuation { continuation in
                    var cancellable: AnyCancellable?
                    cancellable = self.claimEngine.resultPublisher
                        .filter { $0.emailId == emailId }
                        .first()
                        .sink { result in
                            continuation.resume(returning: result)
                            cancellable?.cancel()
                        }
                }
            }
            
            // Task 2: Timeout
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return ClaimEngineResult(
                    eventId: UUID(),
                    emailId: emailId,
                    resultType: .timeout,
                    actionType: .none,
                    message: "Timeout in attesa risposta ClaimEngine",
                    details: ["timeout": timeout]
                )
            }
            
            // Prendi il primo risultato (risultato o timeout)
            if let result = await group.next() {
                group.cancelAll()
                
                if let result = result {
                    if result.resultType == .timeout {
                        print("[MailManager] ⏱️ Timeout in attesa conferma ClaimEngine per email \(emailId)")
                    } else {
                        print("[MailManager] ✅ Ricevuta conferma ClaimEngine per email \(emailId): \(result.resultType)")
                    }
                    return result
                }
            }
            
            return nil
        }
    }
    
    /// Aggiorna lo stato di processamento in base al risultato di ClaimEngine
    private func updateProcessingStatusBasedOnResult(
        emailId: String,
        result: ClaimEngineResult?,
        expectedAction: ClaimEngineDecision.ActionType
    ) async {
        guard let result = result else {
            // Nessun risultato = timeout o errore
            await updateProcessingStatus(
                forEmailId: emailId,
                status: .errore,
                error: "Nessuna risposta da ClaimEngine"
            )
            return
        }
        
        switch result.resultType {
        case .success:
            // Verifica che l'azione corrisponda a quella attesa
            if result.matchesExpectedAction(expectedAction) {
                await updateProcessingStatus(
                    forEmailId: emailId,
                    status: .processata,
                    result: result.message
                )
                
                // IMPORTANTE: Marca come processata in Core Data in modo permanente
                // Questo garantisce che la mail non venga riprocessata ad ogni avvio
                let context = await MainActor.run { PersistenceController.shared.container.viewContext }
                markEmailAsProcessed(messageId: emailId, context: context)
                print("[MailManager] ✅ Email \(emailId) marcata come processata permanentemente dopo successo ClaimEngine")
            } else {
                // Azione diversa da quella attesa
                await updateProcessingStatus(
                    forEmailId: emailId,
                    status: .errore,
                    error: "Azione inattesa: \(result.message)"
                )
            }
            
        case .error:
            await updateProcessingStatus(
                forEmailId: emailId,
                status: .errore,
                error: result.message
            )
            
        case .unexpectedAction:
            await updateProcessingStatus(
                forEmailId: emailId,
                status: .errore,
                error: "Azione inattesa: \(result.message)"
            )
            
        case .ignored:
            // Ignorato (es. duplicato) - per assegnazioni con stessa data, trattalo come successo
            let isSameDate = result.details["stessaData"] as? Bool == true
            if expectedAction == .logToDiary && isSameDate {
                // Per assegnazioni: se il sinistro ha già la stessa data, è un successo
                let riferimento = result.details["riferimento"] as? String ?? "N/A"
                let dataEsistente = result.details["dataEsistente"] as? Date
                
                var message = "Sinistro \(riferimento) ha già la data di assegnazione"
                if let data = dataEsistente {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .none
                    message += " \(formatter.string(from: data))"
                }
                message += " correttamente impostata"
                
                await updateProcessingStatus(
                    forEmailId: emailId,
                    status: .processata,
                    result: message
                )
                
                // Marca come processata anche in Core Data
                let context = await MainActor.run { PersistenceController.shared.container.viewContext }
                markEmailAsProcessed(messageId: emailId, context: context)
                
                // Auto-marca come letta se abilitato per assegnazioni
                if EmailAutoReadSettings.shared.isCategoryEnabled(.assignment) {
                    await markEmailAsReadIfNeeded(emailId: emailId)
                }
            } else {
                // Altri casi di ignored = errore
                await updateProcessingStatus(
                    forEmailId: emailId,
                    status: .errore,
                    error: "Evento ignorato: \(result.message)"
                )
            }
            
        case .timeout:
            await updateProcessingStatus(
                forEmailId: emailId,
                status: .errore,
                error: "Timeout in attesa risposta ClaimEngine"
            )
            
        case .partialSuccess:
            // Successo parziale - potrebbe essere ok o errore
            await updateProcessingStatus(
                forEmailId: emailId,
                status: .errore,
                error: "Successo parziale: \(result.message)"
            )
        }
    }
    
    /// Mappa categoria email a intent ClaimEvent
    private func mapCategoryToIntent(_ category: EmailCategory) -> ClaimEventIntent {
        switch category {
        case .assignment:
            return .assignment
        case .revocation:
            return .revocation
        case .actSent:
            return .actSent
        case .actReceived:
            return .actReceived
        case .documentationRequest:
            return .documentationRequest
        case .documentationReceived:
            return .documentation
        case .reminderReceived, .reminderSent:
            return .reminder
        case .surveyScheduled:
            return .surveyScheduled
        case .surveyReturned:
            return .surveyReturned
        case .videocallScheduled:
            return .videocallScheduled
        case .clarificationRequest:
            return .clarification
        case .controlled:
            return .control
        case .revisionRequested:
            return .revision
        case .outcomeSent:
            return .outcomeSent
        case .verbalAcceptance:
            return .verbalAcceptance
        case .genericCommunication, .studioNews, .internalInfo, .procedure, 
             .meeting, .training, .administrative, .newsletter, .spam:
            return .generic
        }
    }
    
    /// Assicura che l'email sia aggiunta al diario del sinistro associato (se presente)
    /// Chiamato dopo il processamento per email che non hanno generato eventi o sono lette
    private func ensureEmailInDiario(email: Email, context: NSManagedObjectContext) async {
        // Cerca thread che contengono questa email
        // Non possiamo usare CONTAINS su campi Transformable, quindi filtriamo in memoria
        let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        request.fetchLimit = 100 // Limita per performance
        
        guard let allThreads = try? context.fetch(request) else {
            return
        }
        
        // Filtra in memoria usando messageIds
        let threads = allThreads.filter { $0.messageIds.contains(email.id) }
        
        guard !threads.isEmpty else {
            // Email non associata, non aggiungere al diario
            return
        }
        
        // Per ogni sinistro associato, verifica se l'email è già nel diario
        for thread in threads {
            guard let sinistro = thread.sinistro else { continue }
            
            // Verifica se l'email è già nel diario
            let diarioArray = sinistro.diarioArray
            let emailAlreadyInDiario = diarioArray.contains { entry in
                entry.emailMessageId == email.id
            }
            
            if !emailAlreadyInDiario {
                // Aggiungi email al diario
                let body = email.body ?? ""
                let riassunto = body.isEmpty ? email.subject : String(body.prefix(200))
                
                let diarioEntry = DiarioEntry(
                    timestamp: email.date,
                    tipo: .email,
                    titolo: email.subject,
                    riassunto: riassunto,
                    contenutoCompleto: body,
                    emailMessageId: email.id,
                    processedEmailDate: email.date
                )
                
                await MainActor.run {
                    sinistro.addDiarioEntry(diarioEntry)
                    try? context.save()
                    print("[MailManager] 📝 Email \(email.id) aggiunta al diario del sinistro \(sinistro.riferimento ?? "N/A")")
                }
            }
        }
    }
    
    /// Mappa email sender a sender type
    private func mapSenderType(_ email: String) -> ClaimEventSenderType {
        let lowercased = email.lowercased()
        
        if lowercased.contains("@cattolica.it") || 
           lowercased.contains("@generali.it") ||
           lowercased.contains("@zurich.it") ||
           lowercased.contains("@unipolsai.it") {
            return .company
        }

        if TenantMailSettingsService.shared.isInternalEmail(lowercased) {
            return .studio
        }
        
        if lowercased.contains("agenzia") || lowercased.contains("agent") {
            return .agency
        }
        
        if lowercased.contains("liquidator") || lowercased.contains("liquidazione") {
            return .liquidator
        }
        
        // Se è il nostro studio
        if lowercased.contains("@studioperitale") || lowercased.contains("@mperx") {
            return .studio
        }
        
        return .insured
    }
    
    // MARK: - Processing Status Helpers
    
    /// Aggiorna lo stato di processamento di un'email nel tag manager
    private func updateProcessingStatus(
        forEmailId emailId: String,
        status: EmailProcessingStatus,
        result: String? = nil,
        error: String? = nil
    ) async {
        await MainActor.run {
            if status == .errore {
                EmailTagManager.shared.markAsError(emailId: emailId, error: error ?? "Errore sconosciuto")
            } else {
                EmailTagManager.shared.markAsProcessed(emailId: emailId, result: result)
            }
        }
    }
    
    /// Genera una descrizione del risultato del processamento in base all'evento
    private func getProcessingResultDescription(for event: any EmailEvent, category: EmailCategory) -> String {
        switch category {
        case .assignment:
            return "Sinistro creato/aggiornato"
        case .revocation:
            return "Sinistro revocato"
        case .controlled:
            return "Perizia controllata registrata"
        case .revisionRequested:
            return "Richiesta revisione registrata"
        case .documentationReceived:
            return "Documentazione registrata"
        case .documentationRequest:
            return "Richiesta documentazione inviata"
        case .actSent:
            return "Atto inviato registrato"
        case .actReceived:
            return "Atto firmato registrato"
        case .reminderReceived:
            return "Sollecito ricevuto registrato"
        case .reminderSent:
            return "Sollecito inviato registrato"
        case .surveyScheduled:
            return "Sopralluogo fissato"
        case .surveyReturned:
            return "Sopralluogo restituito"
        case .videocallScheduled:
            return "Videoperizia fissata"
        case .clarificationRequest:
            return "Richiesta chiarimenti registrata"
        case .outcomeSent:
            return "Esito comunicato"
        case .verbalAcceptance:
            return "Accettazione verbale registrata"
        case .studioNews:
            return "News studio creata"
        case .internalInfo:
            return "Info interna registrata"
        case .procedure:
            return "Procedura registrata"
        case .meeting:
            return "Riunione registrata"
        case .training:
            return "Formazione registrata"
        case .administrative:
            return "Elemento amministrativo registrato"
        case .newsletter:
            return "Newsletter registrata"
        case .spam:
            return "Spam identificato"
        case .genericCommunication:
            return "Comunicazione registrata"
        }
    }
}

// MARK: - Generic Communication Handler

/// Handler per comunicazioni generiche non classificate
class GenericCommunicationHandler: BaseEmailHandler {
    init() {
        super.init(
            handlerId: "generic_communication",
            supportedCategories: [.genericCommunication]
        )
    }
    
    override func handle(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        let sinistroId = extractSinistroReference(from: email)
        
        // Se abbiamo un sinistro, aggiungi sempre al diario (anche se email letta)
        if let sinistroId = sinistroId,
           let sinistro = findSinistro(riferimento: sinistroId, context: context) {
            sinistro.addDiarioEntry(DiarioEntry(
                testo: "Email ricevuta: \(email.originalEmail.subject)",
                tipo: .email
            ))
        }
        
        return EmailGenericCommunicationReceived(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId,
            direction: email.direction,
            subject: email.originalEmail.subject,
            sender: email.originalEmail.sender.email,
            hasAttachments: email.hasAttachments
        )
    }
}
