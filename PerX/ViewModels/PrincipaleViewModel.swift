import Foundation
import CoreData
import Combine
import SwiftUI

@MainActor
class PrincipaleViewModel: ObservableObject {
    static let shared: PrincipaleViewModel = {
        return PrincipaleViewModel(mailViewModel: MailViewModel.shared)
    }()
    
    @Published var emailThreads: [SinistroEmailThread] = []
    @Published var subjectThreads: [SubjectThread] = []
    @Published var isLoading = false
    @Published var selectedThread: SinistroEmailThread?
    @Published var selectedEmail: Email?
    @Published var error: String?
    
    // Paginazione
    @Published var displayedThreads: [SinistroEmailThread] = []
    @Published var hasMoreThreads = false
    private let initialLoadCount = 30
    private let loadMoreCount = 20
    
    private let mailViewModel: MailViewModel
    private let tagManager = TagManager.shared
    private let context: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    private(set) var isPreloaded = false // Esposto per verificare se è già stato precaricato
    private var allThreads: [SinistroEmailThread] = []
    
    init(mailViewModel: MailViewModel, context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.mailViewModel = mailViewModel
        self.context = context
        
        // NON caricare qui - sarà fatto in modo asincrono quando necessario
        
        // OTTIMIZZAZIONE: Esegui il setup delle sottoscrizioni in modo asincrono 
        // per evitare crash all'avvio dovuti ad accessi prematuri a singleton in fase di init
        Task { @MainActor in
            setupSubscriptions()
        }
    }
    
    private func setupSubscriptions() {
        // OTTIMIZZAZIONE: Debounce aumentato a 1s per ridurre carico CPU
        // Osserva i cambiamenti in Core Data per i thread
        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextDidSave,
            object: context
        )
        .debounce(for: .seconds(1), scheduler: DispatchQueue.main) // Aumentato da 300ms a 1s
        .sink { [weak self] _ in
            // Ricarica i thread quando vengono salvati nuovi thread
            Task { @MainActor in
                await self?.loadExistingThreadsAsync()
            }
        }
        .store(in: &cancellables)
        
        // OTTIMIZZAZIONE: Debounce aumentato a 1s per ridurre aggiornamenti UI
        // Evita ricaricamenti continui quando cambiano le email
        // dropFirst() evita il trigger iniziale che causa loop di pubblicazione
        mailViewModel.$emailsByMailbox
            .dropFirst() // Ignora il valore iniziale per evitare loop
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main) // Aumentato da 500ms a 1s
            .sink { [weak self] _ in
                // Aggiorna solo l'ordine dei thread esistenti (non ricarica tutto)
                self?.updateDisplayedThreads()
                // Aggiorna anche i thread per oggetto
                self?.updateSubjectThreads()
            }
            .store(in: &cancellables)
    }
    
    /// Carica i thread esistenti da Core Data in modo streaming (non blocca la UI, non occupa tutta la memoria)
    func loadExistingThreadsAsync() async {
        // Se ci sono già thread caricati (dal batch iniziale), continua da lì
        let existingCount = await MainActor.run {
            return allThreads.count
        }
        
        // Carica i thread in batch per non occupare tutta la memoria
        let batchSize = 50 // Processa 50 thread alla volta
        let threadCustomizationService = ThreadCustomizationService.shared
        
        // Fetch totale in background (non blocca)
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            // Conta prima quanti thread ci sono (query veloce)
            let totalCount = await MainActor.run {
                let countRequest = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
                return (try? self.context.count(for: countRequest)) ?? 0
            }
            
            // Se abbiamo già caricato tutto, esci
            if existingCount >= totalCount {
                await MainActor.run {
                    self.hasMoreThreads = false
                }
                return
            }
            
            print("[PrincipaleViewModel] 📊 Caricamento streaming: \(existingCount)/\(totalCount) thread già caricati")
            
            var allFilteredThreads = await MainActor.run {
                return self.allThreads // Parte dai thread già caricati
            }
            
            var offset = existingCount
            
            // Carica in batch per limitare l'uso di memoria
            while offset < totalCount {
                // Verifica cancellazione
                if Task.isCancelled {
                    break
                }
                
                let batch = await MainActor.run { [self] in
            let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
            // Ordinamento iniziale per dataUltimaModifica, poi verrà riordinato per data mail più recente
            request.sortDescriptors = [NSSortDescriptor(keyPath: \SinistroEmailThread.dataUltimaModifica, ascending: false)]
            request.fetchOffset = offset
            request.fetchLimit = batchSize
                    
                    do {
                        let fetchedThreads = try self.context.fetch(request)
                        
                        // Filtra thread con email escluse
                        var filteredBatch: [SinistroEmailThread] = []
                        
                        for thread in fetchedThreads {
                            let originalIds = thread.messageIds
                            let filteredIds = originalIds.filter { !threadCustomizationService.isEmailExcluded(emailId: $0) }
                            
                            if thread.sinistro != nil {
                                if !filteredIds.isEmpty || threadCustomizationService.isCustomThread(threadId: thread.wrappedId) {
                                    filteredBatch.append(thread)
                                }
                            } else {
                                if threadCustomizationService.isCustomThread(threadId: thread.wrappedId) {
                                    filteredBatch.append(thread)
                                } else if !filteredIds.isEmpty {
                                    filteredBatch.append(thread)
                                }
                            }
                        }
                        
                        return filteredBatch
                    } catch {
                        print("[PrincipaleViewModel] ⚠️ Errore nel caricamento batch: \(error)")
                        return [SinistroEmailThread]()
                    }
                }
                
                allFilteredThreads.append(contentsOf: batch)
                
                // Rimuovi duplicati prima di aggiornare
                var uniqueThreads: [SinistroEmailThread] = []
                var seenIds: Set<UUID> = []
                for thread in allFilteredThreads {
                    let threadId = thread.wrappedId
                    if !seenIds.contains(threadId) {
                        seenIds.insert(threadId)
                        uniqueThreads.append(thread)
                    }
                }
                
                // Aggiorna la UI in streaming (ogni batch) - aggiunge invece di sostituire
                await MainActor.run {
                    self.allThreads = uniqueThreads
                    self.emailThreads = uniqueThreads
                    self.hasMoreThreads = uniqueThreads.count < totalCount
                    
                    // Aggiorna i thread visualizzati se necessario
                    if self.displayedThreads.count < self.initialLoadCount && allFilteredThreads.count >= self.initialLoadCount {
                        self.loadInitialBatch()
                    }
                }
                
                offset += batchSize
                
                // Throttling: pausa tra batch per non saturare la CPU
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 secondi
            }
            
            // Rimuovi duplicati finali prima di completare
            var uniqueFinal: [SinistroEmailThread] = []
            var seenFinalIds: Set<UUID> = []
            for thread in allFilteredThreads {
                let threadId = thread.wrappedId
                if !seenFinalIds.contains(threadId) {
                    seenFinalIds.insert(threadId)
                    uniqueFinal.append(thread)
                }
            }
            
            // Caricamento completato
            await MainActor.run {
                self.allThreads = uniqueFinal
                self.emailThreads = uniqueFinal
                self.isLoading = false
                self.hasMoreThreads = false
                print("[PrincipaleViewModel] ✅ Caricamento streaming completato: \(uniqueFinal.count) thread totali (dopo deduplicazione)")
                
                // Aggiorna l'ordine dei thread visualizzati
                self.updateDisplayedThreads()
            }
        }
    }
    
    /// Ordina i thread in background senza bloccare la UI
    private func sortThreadsInBackground() async {
        // Ordina solo i primi 100 thread per non bloccare
        let threadsToSort = Array(allThreads.prefix(100))
        
        // Ottieni le date delle email sul main actor
        var dates: [UUID: Date] = [:]
        for thread in threadsToSort {
            let threadId = thread.wrappedId
            if let email = await latestEmail(for: thread) {
                dates[threadId] = email.date ?? Date.distantPast
            } else {
                dates[threadId] = Date.distantPast
            }
        }
        
        // Ordina usando le date già ottenute (non richiede main actor)
        let sorted = threadsToSort.sorted { thread1, thread2 in
            let date1 = dates[thread1.wrappedId] ?? Date.distantPast
            let date2 = dates[thread2.wrappedId] ?? Date.distantPast
            return date1 > date2
        }
        
        // Aggiorna solo se non ci sono stati cambiamenti
        await MainActor.run {
            let currentCount = self.allThreads.count
            let sortedCount = sorted.count
            if currentCount == sortedCount + (currentCount - 100) {
                // Sostituisci solo i primi 100 thread ordinati
                let rest = Array(self.allThreads.dropFirst(100))
                self.allThreads = sorted + rest
                self.emailThreads = self.allThreads
                self.updateDisplayedThreads()
            }
        }
    }
    
    /// Ordina i thread per data dell'email più recente (più recenti in alto)
    /// Usato solo per i thread visualizzati per non bloccare
    private func sortThreadsByLatestEmail(_ threads: [SinistroEmailThread]) -> [SinistroEmailThread] {
        // Limita a 50 thread per non bloccare
        let limited = Array(threads.prefix(50))
        return limited.sorted { thread1, thread2 in
            let date1 = self.latestEmail(for: thread1)?.date ?? Date.distantPast
            let date2 = self.latestEmail(for: thread2)?.date ?? Date.distantPast
            return date1 > date2
        } + Array(threads.dropFirst(50))
    }
    
    /// Carica il batch iniziale di thread
    private func loadInitialBatch() {
        let endIndex = min(initialLoadCount, allThreads.count)
        displayedThreads = Array(allThreads.prefix(endIndex))
        hasMoreThreads = allThreads.count > initialLoadCount
    }
    
    /// Carica più thread quando si scrolla
    func loadMoreThreads() {
        guard hasMoreThreads && !isLoading else { return }
        
        // Rimuovi duplicati da allThreads prima di procedere
        var uniqueThreads: [SinistroEmailThread] = []
        var seenIds: Set<UUID> = []
        for thread in allThreads {
            let threadId = thread.wrappedId
            if !seenIds.contains(threadId) {
                seenIds.insert(threadId)
                uniqueThreads.append(thread)
            }
        }
        allThreads = uniqueThreads
        
        let currentCount = displayedThreads.count
        let nextCount = min(currentCount + loadMoreCount, allThreads.count)
        
        // Rimuovi duplicati anche da displayedThreads
        var uniqueDisplayed: [SinistroEmailThread] = []
        var seenDisplayedIds: Set<UUID> = []
        for thread in Array(allThreads.prefix(nextCount)) {
            let threadId = thread.wrappedId
            if !seenDisplayedIds.contains(threadId) {
                seenDisplayedIds.insert(threadId)
                uniqueDisplayed.append(thread)
            }
        }
        displayedThreads = uniqueDisplayed
        hasMoreThreads = nextCount < allThreads.count
    }
    
    /// Cerca un thread specifico per sinistro e lo carica se necessario
    func loadThreadForSinistro(_ sinistro: Sinistro) {
        // Cerca se esiste già nei thread caricati
        if let existing = displayedThreads.first(where: { $0.sinistro?.riferimento == sinistro.riferimento }) {
            return
        }
        
        // Cerca in tutti i thread
        if let thread = allThreads.first(where: { $0.sinistro?.riferimento == sinistro.riferimento }) {
            // Aggiungi all'inizio se non è già presente
            let threadId = thread.wrappedId
            if !displayedThreads.contains(where: { $0.wrappedId == threadId }) {
                displayedThreads.insert(thread, at: 0)
            }
        }
    }
    
    /// Precarica i thread in background (chiamato all'avvio dell'app)
    /// Carica prima un batch piccolo per mostrare subito qualcosa, poi continua in streaming
    func preload() async {
        guard !isPreloaded else { return }
        isPreloaded = true
        
        // Carica prima un batch veloce (primi 30 thread) per mostrare subito la vista
        await loadInitialBatchFast()
        
        // Poi carica il resto in streaming in background
        Task.detached(priority: .utility) { [weak self] in
            await self?.loadExistingThreadsAsync()
        }
    }
    
    /// Carica velocemente i primi thread per mostrare subito la vista
    /// Tutte le operazioni Core Data vengono eseguite in background per non bloccare la UI
    private func loadInitialBatchFast() async {
        await MainActor.run {
            isLoading = true
        }
        
        // Esegui il fetch Core Data in background (non blocca la UI)
        // Usa un background context invece di viewContext (non thread-safe in Task.detached)
        let initialBatch = await Task.detached(priority: .userInitiated) { [self] in
            let context = PersistenceController.shared.container.newBackgroundContext()
            let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
            // Ordinamento iniziale per dataUltimaModifica, poi verrà riordinato per data mail più recente
            request.sortDescriptors = [NSSortDescriptor(keyPath: \SinistroEmailThread.dataUltimaModifica, ascending: false)]
            request.fetchLimit = initialLoadCount // Solo i primi 30
            
            var threadObjectIDs: [NSManagedObjectID] = []
            
            context.performAndWait {
                do {
                    let fetchedThreads = try context.fetch(request)
                    let threadCustomizationService = ThreadCustomizationService.shared
                    
                    // Estrai gli objectID dei thread (thread-safe)
                    threadObjectIDs = fetchedThreads.filter { thread in
                        let originalIds = thread.messageIds
                        let filteredIds = originalIds.filter { !threadCustomizationService.isEmailExcluded(emailId: $0) }
                        
                        if thread.sinistro != nil {
                            return !filteredIds.isEmpty || threadCustomizationService.isCustomThread(threadId: thread.wrappedId)
                        } else {
                            return threadCustomizationService.isCustomThread(threadId: thread.wrappedId) || !filteredIds.isEmpty
                        }
                    }.map { $0.objectID }
                } catch {
                    print("[PrincipaleViewModel] ⚠️ Errore nel caricamento batch iniziale: \(error)")
                }
            }
            
            // Recupera i thread dal viewContext sul main thread
            return await MainActor.run {
                let viewContext = PersistenceController.shared.container.viewContext
                return threadObjectIDs.compactMap { objectID in
                    try? viewContext.existingObject(with: objectID) as? SinistroEmailThread
                }
            }
        }.value
        
        // Aggiorna la UI sul main thread
        await MainActor.run {
            self.allThreads = initialBatch
            self.emailThreads = initialBatch
            self.displayedThreads = initialBatch
            self.hasMoreThreads = false // Verrà aggiornato quando carica il resto
            self.isLoading = false
            print("[PrincipaleViewModel] ✅ Caricati \(initialBatch.count) thread iniziali (vista reattiva)")
        }
    }
    
    /// Aggiorna i thread visualizzati quando cambiano le email
    private func updateDisplayedThreads() {
        // Rimuovi duplicati prima di ordinare
        var uniqueThreads: [SinistroEmailThread] = []
        var seenIds: Set<UUID> = []
        for thread in allThreads {
            let threadId = thread.wrappedId
            if !seenIds.contains(threadId) {
                seenIds.insert(threadId)
                uniqueThreads.append(thread)
            }
        }
        
        // Ordina allThreads per data della mail più recente (più recenti in alto)
        let sortedThreads = uniqueThreads.sorted { thread1, thread2 in
            let date1 = self.latestEmail(for: thread1)?.date ?? Date.distantPast
            let date2 = self.latestEmail(for: thread2)?.date ?? Date.distantPast
            return date1 > date2
        }
        allThreads = sortedThreads
        
        let currentCount = max(displayedThreads.count, initialLoadCount)
        displayedThreads = Array(sortedThreads.prefix(currentCount))
        hasMoreThreads = sortedThreads.count > currentCount
    }
    
    /// Ricarica completamente i thread (solo quando necessario, es. dopo import)
    func loadThreads() {
        Task {
            await loadExistingThreadsAsync()
        }
    }
    
    private func getAllEmails() -> [Email] {
        // Ottieni tutte le email da tutte le caselle usando EmailRepository, escluso SPAM e TRASH
        let emailRepository = EmailRepository.shared
        let stats = emailRepository.getStats()
        var allEmails: [Email] = []
        
        for mailboxId in stats.emailsPerMailbox.keys where !["SPAM", "TRASH"].contains(mailboxId) {
            allEmails.append(contentsOf: emailRepository.getEmails(forMailbox: mailboxId))
        }
        
        return allEmails
    }
    
    /// Metodo deprecato - non usare più, troppo lento con molti dati
    /// Usa invece loadExistingThreads() che carica da Core Data
    private func groupEmailsIntoThreads(emails: [Email]) async throws -> [SinistroEmailThread] {
        // Questo metodo è troppo lento con molti dati
        // I thread vengono creati da MailViewModel.indexEmailsForSinistro
        // e salvati in Core Data, quindi li carichiamo da lì
        return []
    }
    
    private func groupEmailsByTags(emails: [Email]) async throws -> [Tag: [Email]] {
        var emailsByTag: [Tag: [Email]] = [:]
        
        // Ottieni tutti i tag di tipo sinistro
        let sinistroTags = tagManager.getAllTags(ofType: .sinistro)
        
        for email in emails {
            // Ottieni i tag associati a questa email
            let tags = tagManager.getTags(forEmailWithMessageId: email.id)
            
            // Filtra solo i tag di tipo sinistro
            for tag in tags.filter({ sinistroTags.contains($0) }) {
                if emailsByTag[tag] == nil {
                    emailsByTag[tag] = []
                }
                emailsByTag[tag]?.append(email)
            }
        }
        
        return emailsByTag
    }
    
    /// Metodo deprecato - non usare più, troppo lento con molti dati
    private func autoGroupEmails(emails: [Email]) -> [SinistroEmailThread] {
        // Questo metodo è troppo lento con molti dati
        // I thread vengono creati da MailViewModel.indexEmailsForSinistro
        // e salvati in Core Data, quindi li carichiamo da lì
        return []
    }
    
    private func normalizeSubject(_ subject: String) -> String {
        // Rimuove prefissi comuni come "Re:", "Fwd:", "R:", "I:", etc.
        var normalized = subject
            .replacingOccurrences(of: "^(Re|R|Fwd|Fw|I|Vs|VS):\\s*", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Rimuove riferimenti interni dal subject per il raggruppamento
        normalized = normalized.replacingOccurrences(of: "\\b[0-9]{7}\\b", with: "", options: [.regularExpression])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Rimuove pattern comuni del formato standard
        normalized = normalized.replacingOccurrences(of: "^(.+?)\\s*-\\s*sinistro\\s*n\\..*$", with: "$1", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return normalized.isEmpty ? subject : normalized
    }
    
    /// Cerca un sinistro nel database usando il riferimento interno
    private func trovaSinistroPerRiferimento(_ riferimento: String) -> Sinistro? {
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        request.fetchLimit = 1
        
        do {
            let sinistri = try context.fetch(request)
            return sinistri.first
        } catch {
            print("Errore nella ricerca del sinistro per riferimento \(riferimento): \(error)")
            return nil
        }
    }
    
    /// Crea un SinistroEmailThread usando il context di Core Data
    private func createThread(id: String, emails: [Email], sinistro: Sinistro?) -> SinistroEmailThread {
        let thread = SinistroEmailThread(context: context)
        thread.id = UUID(uuidString: id) ?? UUID()
        thread.sinistro = sinistro
        thread.dataCreazione = Date()
        thread.dataUltimaModifica = Date()
        
        // Salva solo i messageIds delle email
        thread.messageIds = emails.map { $0.id }
        
        return thread
    }
    
    // MARK: - Azioni
    
    func selectThread(_ thread: SinistroEmailThread) {
        selectedThread = thread
        
        // Scarica le email del thread se non sono già caricate
        Task {
            await downloadThreadEmailsIfNeeded(thread)
            
            await MainActor.run {
                // Seleziona l'email più recente del thread
                selectedEmail = latestEmail(for: thread)
            }
        }
    }
    
    /// Scarica le email del thread solo se necessario (on-demand) con priorità
    func downloadThreadEmailsIfNeeded(_ thread: SinistroEmailThread, priority: _Concurrency.TaskPriority = .userInitiated) async {
        let messageIds = thread.messageIds
        
        // Controlla quali email sono già caricate
        var emailsToDownload: [String] = []
        
        let emailRepository = EmailRepository.shared
        
        for messageId in messageIds {
            // Controlla se l'email è già in EmailRepository
            let isInRepository = emailRepository.emailExists(byId: messageId)
                        
            if !isInRepository {
                emailsToDownload.append(messageId)
            }
        }
        
        if !emailsToDownload.isEmpty {
            // Scarica le email mancanti con priorità
            await withTaskGroup(of: Void.self) { group in
                for messageId in emailsToDownload {
                    group.addTask(priority: priority) {
                        await self.mailViewModel.fetchFullEmail(for: messageId)
                    }
                }
            }
        }
    }
    
    func selectEmail(_ email: Email) {
        selectedEmail = email
        
        // Segna l'email come letta
        if !email.isRead {
            Task {
                mailViewModel.markEmailAsRead(emailId: email.id)
            }
        }
        
        // Priorità massima per download se il contenuto non è già salvato in memoria locale
        let emailRepository = EmailRepository.shared
        if let cachedEmail = emailRepository.getEmail(byId: email.id) {
            // Se il body non è presente, prioritizza il download
            if cachedEmail.body == nil || cachedEmail.body?.isEmpty == true {
                Task {
                    await EmailQueueService.shared.prioritizeEmail(email.id)
                }
            }
        } else {
            // Email non in repository, prioritizza immediatamente
            Task {
                await EmailQueueService.shared.prioritizeEmail(email.id)
            }
        }
    }
    
    func associateThreadWithSinistro(_ thread: SinistroEmailThread, sinistro: Sinistro) {
        Task {
            do {
                // Crea o ottieni il tag per il sinistro
                let tag = try tagManager.createOrGetSinistroTag(for: sinistro)
                
                // Associa tutte le email del thread al tag
                for messageId in thread.messageIds {
                    try tagManager.addTag(tag, toEmailWithMessageId: messageId)
                }
                
                // Ricarica i thread per aggiornare la UI
                loadThreads()
            } catch {
                self.error = "Errore nell'associazione del thread: \(error.localizedDescription)"
            }
        }
    }
    
    func removeThreadAssociation(_ thread: SinistroEmailThread) {
        Task {
            do {
                // TODO: Recuperare il tag relativo al thread per rimuoverlo dalle email
                /*
                if let tag = ??? {
                    // Rimuovi il tag da tutte le email del thread
                    for email in thread.emails {
                        try tagManager.removeTag(tag, fromEmailWithMessageId: email.id)
                    }
                    
                    // Ricarica i thread per aggiornare la UI
                    loadThreads()
                }
                */
            } catch {
                self.error = "Errore nella rimozione dell'associazione: \(error.localizedDescription)"
            }
        }
    }

    // Correggo il sorting delle email - ora usa messageIds
    func sortedEmails(for thread: SinistroEmailThread) -> [Email] {
        let emails = self.emails(for: thread)
        return emails.sorted { (a: Email, b: Email) in
            (a.date ?? Date()) > (b.date ?? Date())
        }
    }

    // Correggo il loop sulle email - ora usa messageIds
    func processEmails(for thread: SinistroEmailThread) {
        let emails = self.emails(for: thread)
        for email in emails {
            // processa email
        }
    }

    // Rimosso il metodo processThread(_:) che non faceva nulla

    // Rimosso il sortComparator e ogni riferimento a sortOrder in quanto non presenti nel file

    // Correzione del FetchRequest
    private func fetchSinistri() {
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        // ... Logica di fetch ...
    }
    
    // Correzione del sorting
    func sortThreads() {
        emailThreads.sort { (thread1: SinistroEmailThread, thread2: SinistroEmailThread) -> Bool in
            let date1 = self.latestEmail(for: thread1)?.date ?? Date.distantPast
            let date2 = self.latestEmail(for: thread2)?.date ?? Date.distantPast
            return date1 > date2
        }
    }
    
    // Correzione dell'unwrapping dell'NSSet - ora usa messageIds
    func getSortedEmails(from thread: SinistroEmailThread) -> [Email] {
        let emails = self.emails(for: thread)
        return emails.sorted(by: { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) })
    }
    
    // Correzione del for-in loop - ora usa messageIds
    func processThreadEmails(for thread: SinistroEmailThread) {
        let emails = self.emails(for: thread)
        for email in emails {
            // ... la tua logica qui ...
            print(email.subject)
        }
    }
    
    // Rimozione del riferimento a `.tag`
    func handleThreadSelection(_ thread: SinistroEmailThread) {
        // La logica non userà più `thread.tag`
        if let sinistro = thread.sinistro {
            // ...
        }
    }
    
    // MARK: - Helper per le viste (ottimizzati)
    func unreadCount(for thread: SinistroEmailThread) -> Int {
        // Ottimizzazione: conta direttamente senza caricare tutte le email
        let messageIdSet = Set(thread.messageIds)
        var unread = 0
        var checkedIds = Set<String>()
        let emailRepository = EmailRepository.shared
        
        // Conta in tutte le caselle usando EmailRepository
        let stats = emailRepository.getStats()
        for mailboxId in stats.emailsPerMailbox.keys {
            let emails = emailRepository.getEmails(forMailbox: mailboxId)
            for email in emails {
                if messageIdSet.contains(email.id) && !checkedIds.contains(email.id) {
                    checkedIds.insert(email.id)
                    if !email.isRead {
                        unread += 1
                    }
                }
            }
        }
        
        return unread
    }
    
    func latestEmail(for thread: SinistroEmailThread) -> Email? {
        // Ottimizzazione: trova solo l'email più recente senza caricare tutte
        let messageIdSet = Set(thread.messageIds)
        var latest: Email? = nil
        var latestDate = Date.distantPast
        var checkedIds = Set<String>()
        let emailRepository = EmailRepository.shared
        
        // Cerca in tutte le caselle usando EmailRepository (solo quello già in memoria)
        let stats = emailRepository.getStats()
        for mailboxId in stats.emailsPerMailbox.keys {
            let emails = emailRepository.getEmails(forMailbox: mailboxId)
            for email in emails {
                if messageIdSet.contains(email.id) && !checkedIds.contains(email.id) {
                    checkedIds.insert(email.id)
                    let emailDate = email.date
                    if emailDate > latestDate {
                        latestDate = emailDate
                        latest = email
                    }
                }
            }
        }
        
        return latest
    }
    
    func emails(for thread: SinistroEmailThread) -> [Email] {
        // Ottimizzazione: crea un set di messageIds per ricerca più veloce
        let messageIdSet = Set(thread.messageIds)
        let threadCustomizationService = ThreadCustomizationService.shared
        
        // Cerca tutte le email in tutte le caselle (INBOX, SENT, ecc.) usando EmailRepository
        var foundEmails: [Email] = []
        var foundIds = Set<String>()
        let emailRepository = EmailRepository.shared
        
        // Cerca in tutte le caselle
        let stats = emailRepository.getStats()
        for mailboxId in stats.emailsPerMailbox.keys {
            let emails = emailRepository.getEmails(forMailbox: mailboxId)
            for email in emails {
                if messageIdSet.contains(email.id) && !foundIds.contains(email.id) {
                    // Filtra email escluse (a meno che non siano già nel thread)
                    if !threadCustomizationService.isEmailExcluded(emailId: email.id) || thread.messageIds.contains(email.id) {
                        foundEmails.append(email)
                        foundIds.insert(email.id)
                    }
                }
            }
        }
        
        // Se alcune email non sono ancora caricate, verranno scaricate on-demand
        
        // Ordina per data (più recenti in alto)
        return foundEmails.sorted { (a: Email, b: Email) in
            (a.date ?? Date.distantPast) > (b.date ?? Date.distantPast)
        }
    }
    
    // MARK: - Thread per Oggetto
    
    /// Aggiorna i thread raggruppati per oggetto normalizzato
    func updateSubjectThreads() {
        let allEmails = getAllEmails()
        let threadCustomizationService = ThreadCustomizationService.shared
        
        // Filtra email escluse
        let filteredEmails = allEmails.filter { email in
            !threadCustomizationService.isEmailExcluded(emailId: email.id)
        }
        
        // Raggruppa per oggetto normalizzato
        var threadsBySubject: [String: [Email]] = [:]
        
        for email in filteredEmails {
            let normalizedSubject = normalizeSubject(email.subject)
            if threadsBySubject[normalizedSubject] == nil {
                threadsBySubject[normalizedSubject] = []
            }
            threadsBySubject[normalizedSubject]?.append(email)
        }
        
        // Crea SubjectThread per ogni gruppo
        var subjectThreads: [SubjectThread] = []
        
        for (normalizedSubject, emails) in threadsBySubject {
            // Ordina email per data (più recente prima)
            let sortedEmails = emails.sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
            
            // Usa l'oggetto originale della prima email (più recente)
            let originalSubject = sortedEmails.first?.subject ?? normalizedSubject
            
            let thread = SubjectThread(
                id: UUID(),
                normalizedSubject: normalizedSubject,
                originalSubject: originalSubject,
                emails: sortedEmails
            )
            subjectThreads.append(thread)
        }
        
        // Ordina per data dell'email più recente
        subjectThreads.sort { thread1, thread2 in
            let date1 = thread1.emails.first?.date ?? Date.distantPast
            let date2 = thread2.emails.first?.date ?? Date.distantPast
            return date1 > date2
        }
        
        self.subjectThreads = subjectThreads
    }
    
    /// Ottiene le email per un thread per oggetto
    func emails(for subjectThread: SubjectThread) -> [Email] {
        return subjectThread.emails
    }
    
    /// Ottiene l'email più recente per un thread per oggetto
    func latestEmail(for subjectThread: SubjectThread) -> Email? {
        return subjectThread.emails.first
    }
    
    /// Conta le email non lette per un thread per oggetto
    func unreadCount(for subjectThread: SubjectThread) -> Int {
        return subjectThread.emails.filter { !$0.isRead }.count
    }
}

// MARK: - SubjectThread Model

struct SubjectThread: Identifiable, Hashable {
    let id: UUID
    let normalizedSubject: String
    let originalSubject: String
    let emails: [Email]
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SubjectThread, rhs: SubjectThread) -> Bool {
        lhs.id == rhs.id
    }
}
