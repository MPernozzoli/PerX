import Foundation
import Combine

/// Repository centralizzato per la gestione delle email con deduplicazione basata su messageId
/// OTTIMIZZATO: liste pre-ordinate, batch saving con debounce, update UI aggregati
@MainActor
class EmailRepository: ObservableObject {
    static let shared = EmailRepository()
    
    // Indice unico per messageId (chiave primaria)
    private var emailIndex: [String: Email] = [:]
    
    // Indice per casella (mailboxId -> Set<messageId>)
    private var mailboxIndex: [String: Set<String>] = [:]
    
    // OTTIMIZZAZIONE: Liste pre-ordinate per evitare sorting ad ogni accesso
    private var sortedEmailsCache: [String: [Email]] = [:]
    private var sortedCacheInvalid: Set<String> = []
    
    // Cache service per persistenza
    private let cacheService = EmailCacheService.shared
    
    // Queue per operazioni thread-safe
    private let repositoryQueue = DispatchQueue(label: "EmailRepository", qos: .utility)
    
    // OTTIMIZZAZIONE: Debounce per update UI e salvataggio cache
    private var pendingUIUpdates: Set<String> = []
    private var uiUpdateDebounceTask: Task<Void, Never>?
    private var pendingSaveDebounceTask: Task<Void, Never>?
    private var pendingEmailsToSave: Set<String> = []
    
    // Configurazione debounce
    private let uiUpdateDebounceInterval: TimeInterval = 0.3 // 300ms per UI
    private let saveDebounceInterval: TimeInterval = 5.0 // 5s per salvataggio cache
    
    @Published var emailsByMailbox: [String: [Email]] = [:]
    
    private init() {
        // Carica indice dalla cache all'avvio con delay maggiore
        // per evitare modifiche @Published durante la costruzione della view
        Task.detached { [weak self] in
            // Delay maggiore per assicurarsi che tutte le view siano completamente renderizzate
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 secondo delay
            await self?.loadFromCache()
        }
    }
    
    // MARK: - Public Interface
    
    /// Aggiunge o aggiorna un'email con controllo duplicati
    /// Restituisce true se l'email è nuova, false se è un aggiornamento/completamento
    func addOrUpdateEmail(_ email: Email, forMailbox mailboxId: String) -> Bool {
        let existingEmail = emailIndex[email.id]
        let isNew = existingEmail == nil
        
        // Se l'email esiste già con corpo completo e la nuova ha anche il corpo,
        // non c'è nulla da aggiornare (evita log inutili)
        if let existing = existingEmail,
           existing.body != nil && email.body != nil,
           existing.isDownloaded == email.isDownloaded,
           existing.isRead == email.isRead {
            // Email già completa, nessun cambiamento reale
            return false
        }
        
        // Verifica se stiamo completando un'email (da metadato a corpo completo)
        let isCompleting = existingEmail != nil && 
                          existingEmail?.body == nil && 
                          email.body != nil
        
        // Aggiorna indice principale
        emailIndex[email.id] = email
        
        // Aggiorna indice casella
        if mailboxIndex[mailboxId] == nil {
            mailboxIndex[mailboxId] = Set<String>()
        }
        mailboxIndex[mailboxId]?.insert(email.id)
        
        // Invalida cache ordinata per questa mailbox
        sortedCacheInvalid.insert(mailboxId)
        
        // Schedula update UI con debounce (NON immediato)
        scheduleUIUpdate(forMailbox: mailboxId)
        
        // Schedula salvataggio cache con debounce
        scheduleCacheSave(forEmailId: email.id)
        
        // Log ridotti per performance
        if isNew {
            print("[EmailRepository] ✨ +1 email in \(mailboxId)")
        }
        
        return isNew
    }
    
    /// Recupera un'email per ID
    func getEmail(byId id: String) -> Email? {
        return emailIndex[id]
    }
    
    /// Recupera tutte le email per una casella (PRE-ORDINATE)
    func getEmails(forMailbox mailboxId: String) -> [Email] {
        // Se la cache è valida, ritorna direttamente
        if !sortedCacheInvalid.contains(mailboxId),
           let cached = sortedEmailsCache[mailboxId] {
            return cached
        }
        
        // Ricostruisci cache ordinata
        guard let messageIds = mailboxIndex[mailboxId] else {
            sortedEmailsCache[mailboxId] = []
            sortedCacheInvalid.remove(mailboxId)
            return []
        }
        
        let emails = messageIds.compactMap { emailIndex[$0] }
            .sorted { $0.date > $1.date }
        
        sortedEmailsCache[mailboxId] = emails
        sortedCacheInvalid.remove(mailboxId)
        
        return emails
    }
    
    /// Recupera la mailbox di un'email (restituisce la prima mailbox trovata)
    func getMailbox(forEmailId emailId: String) -> String? {
        for (mailboxId, messageIds) in mailboxIndex {
            if messageIds.contains(emailId) {
                return mailboxId
            }
        }
        return nil
    }
    
    /// Rimuove un'email da una casella specifica (non dall'indice principale)
    func removeEmail(byId id: String, fromMailbox mailboxId: String) {
        mailboxIndex[mailboxId]?.remove(id)
        sortedCacheInvalid.insert(mailboxId)
        scheduleUIUpdate(forMailbox: mailboxId)
    }
    
    /// Rimuove completamente un'email da tutte le caselle e dall'indice
    func removeEmailCompletely(byId id: String) {
        // Rimuovi da tutte le caselle
        for mailboxId in mailboxIndex.keys {
            mailboxIndex[mailboxId]?.remove(id)
            sortedCacheInvalid.insert(mailboxId)
        }
        
        // Rimuovi dall'indice principale
        emailIndex.removeValue(forKey: id)
        
        // Schedula update UI per tutte le mailbox modificate
        for mailboxId in mailboxIndex.keys {
            scheduleUIUpdate(forMailbox: mailboxId)
        }
    }
    
    /// Rimuove duplicati da una casella specifica
    func removeDuplicates(fromMailbox mailboxId: String) -> Int {
        guard let messageIds = mailboxIndex[mailboxId] else {
            return 0
        }
        
        var duplicatesRemoved = 0
        var seenIds = Set<String>()
        
        for messageId in messageIds {
            if seenIds.contains(messageId) {
                mailboxIndex[mailboxId]?.remove(messageId)
                duplicatesRemoved += 1
            } else {
                seenIds.insert(messageId)
            }
        }
        
        if duplicatesRemoved > 0 {
            sortedCacheInvalid.insert(mailboxId)
            scheduleUIUpdate(forMailbox: mailboxId)
            print("[EmailRepository] 🧹 Rimossi \(duplicatesRemoved) duplicati dalla casella \(mailboxId)")
        }
        
        return duplicatesRemoved
    }
    
    /// Aggiunge multiple email con deduplicazione automatica (BATCH OTTIMIZZATO)
    func addEmails(_ emails: [Email], forMailbox mailboxId: String) -> (added: Int, updated: Int) {
        var added = 0
        var updated = 0
        
        // Batch: aggiungi tutte senza trigger UI individuali
        for email in emails {
            let existingEmail = emailIndex[email.id]
            let isNew = existingEmail == nil
            
            // Skip se già completa e identica
            if let existing = existingEmail,
               existing.body != nil && email.body != nil,
               existing.isDownloaded == email.isDownloaded,
               existing.isRead == email.isRead {
                continue
            }
            
            emailIndex[email.id] = email
            
            if mailboxIndex[mailboxId] == nil {
                mailboxIndex[mailboxId] = Set<String>()
            }
            mailboxIndex[mailboxId]?.insert(email.id)
            
            // Schedula salvataggio (batch)
            pendingEmailsToSave.insert(email.id)
            
            if isNew {
                added += 1
            } else {
                updated += 1
            }
        }
        
        // Invalida cache e schedula UN SOLO update UI
        if added > 0 || updated > 0 {
            sortedCacheInvalid.insert(mailboxId)
            scheduleUIUpdate(forMailbox: mailboxId)
            scheduleBatchCacheSave()
            
            print("[EmailRepository] 📦 Batch: +\(added) nuove, ~\(updated) aggiornate in \(mailboxId)")
        }
        
        return (added: added, updated: updated)
    }
    
    /// Verifica se un'email esiste
    func emailExists(byId id: String) -> Bool {
        return emailIndex[id] != nil
    }
    
    /// Ottiene tutte le email (da tutte le caselle)
    func getAllEmails() -> [Email] {
        return Array(emailIndex.values)
    }
    
    /// Ottiene statistiche del repository
    func getStats() -> (totalEmails: Int, mailboxes: Int, emailsPerMailbox: [String: Int]) {
        var emailsPerMailbox: [String: Int] = [:]
        for (mailboxId, messageIds) in mailboxIndex {
            emailsPerMailbox[mailboxId] = messageIds.count
        }
        
        return (
            totalEmails: emailIndex.count,
            mailboxes: mailboxIndex.count,
            emailsPerMailbox: emailsPerMailbox
        )
    }
    
    // MARK: - Debounced UI Updates
    
    /// Schedula un update UI con debounce (300ms)
    private func scheduleUIUpdate(forMailbox mailboxId: String) {
        pendingUIUpdates.insert(mailboxId)
        
        // Cancella task precedente
        uiUpdateDebounceTask?.cancel()
        
        // Crea nuovo task con debounce
        uiUpdateDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.uiUpdateDebounceInterval ?? 0.3 * 1_000_000_000))
            guard !Task.isCancelled else { return }
            
            await self?.flushUIUpdates()
        }
    }
    
    /// Esegue tutti gli update UI pendenti
    /// IMPORTANTE: Raggruppa tutte le modifiche in una sola operazione per evitare loop infiniti
    private func flushUIUpdates() {
        guard !pendingUIUpdates.isEmpty else { return }
        
        let mailboxesToUpdate = pendingUIUpdates
        pendingUIUpdates.removeAll()
        
        // Raggruppa tutte le modifiche in una sola operazione invece di modificare @Published multiple volte
        var updatedMailboxes = emailsByMailbox
        for mailboxId in mailboxesToUpdate {
            updatedMailboxes[mailboxId] = getEmails(forMailbox: mailboxId)
        }
        // Aggiorna tutto in una volta - evita loop causati da multiple modifiche @Published
        emailsByMailbox = updatedMailboxes
    }
    
    // MARK: - Debounced Cache Saving
    
    /// Schedula salvataggio cache per una singola email
    private func scheduleCacheSave(forEmailId emailId: String) {
        pendingEmailsToSave.insert(emailId)
        scheduleBatchCacheSave()
    }
    
    /// Schedula salvataggio batch con debounce (5s)
    private func scheduleBatchCacheSave() {
        // Cancella task precedente
        pendingSaveDebounceTask?.cancel()
        
        // Crea nuovo task con debounce
        pendingSaveDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.saveDebounceInterval ?? 5.0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            
            await self?.flushCacheSave()
        }
    }
    
    /// Esegue salvataggio cache per tutte le email pendenti
    private func flushCacheSave() {
        guard !pendingEmailsToSave.isEmpty else { return }
        
        let emailsToSave = pendingEmailsToSave
        pendingEmailsToSave.removeAll()
        
        repositoryQueue.async { [weak self] in
            guard let self = self else { return }
            
            var savedCount = 0
            for emailId in emailsToSave {
                if let email = self.emailIndex[emailId] {
                    self.cacheService.saveFullEmail(email, forId: emailId)
                    savedCount += 1
                }
            }
            
            // Salva anche indice se abbiamo salvato molte email
            if savedCount > 10 {
                let index = self.emailIndex
                self.cacheService.saveEmailIndex(index)
            }
            
            if savedCount > 0 {
                print("[EmailRepository] 💾 Batch save: \(savedCount) email salvate")
            }
        }
    }
    
    // MARK: - Cache Management
    
    // OTTIMIZZAZIONE: Limite email da caricare all'avvio per ridurre memoria/CPU
    private let maxEmailsToLoadAtStartup = 500
    
    /// Carica l'indice dalla cache (LAZY LOADING: max 500 email recenti)
    private func loadFromCache() {
        repositoryQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Prova prima a caricare dall'indice completo (sistema nuovo)
            if let index = self.cacheService.loadEmailIndex() {
                Task { @MainActor in
                    var totalLoaded = 0
                    
                    // OTTIMIZZAZIONE: Ordina per data e carica solo le più recenti
                    let sortedEmails = index.values.sorted { $0.date > $1.date }
                    let emailsToLoad = sortedEmails.prefix(self.maxEmailsToLoadAtStartup)
                    
                    // Carica solo le email più recenti
                    for email in emailsToLoad {
                        self.emailIndex[email.id] = email
                        
                        // Determina la mailbox dall'email
                        let mailboxId = email.recipients.isEmpty ? "SENT" : "INBOX"
                        
                        if self.mailboxIndex[mailboxId] == nil {
                            self.mailboxIndex[mailboxId] = Set<String>()
                        }
                        self.mailboxIndex[mailboxId]?.insert(email.id)
                        totalLoaded += 1
                    }
                    
                    // Invalida tutte le cache ordinate
                    for mailboxId in self.mailboxIndex.keys {
                        self.sortedCacheInvalid.insert(mailboxId)
                    }
                    
                    // IMPORTANTE: Aggiorna emailsByMailbox in UN SOLO batch per evitare loop infiniti
                    // Raggruppa tutte le modifiche in una sola operazione
                    var updatedMailboxes: [String: [Email]] = [:]
                    for mailboxId in self.mailboxIndex.keys {
                        updatedMailboxes[mailboxId] = self.getEmails(forMailbox: mailboxId)
                    }
                    // Aggiorna tutto in una volta invece di modificare @Published multiple volte
                    self.emailsByMailbox = updatedMailboxes
                    
                    let skipped = index.count - totalLoaded
                    if skipped > 0 {
                        print("[EmailRepository] ✅ Caricati \(totalLoaded)/\(index.count) email (ultime \(self.maxEmailsToLoadAtStartup)) - \(skipped) caricate on-demand")
                    } else {
                        print("[EmailRepository] ✅ Caricati \(totalLoaded) email da cache")
                    }
                }
                return
            }
            
            // Fallback: carica dalla cache legacy
            let cachedMailboxes = self.cacheService.loadAllMailboxes() ?? [:]
            
            Task { @MainActor in
                var totalLoaded = 0
                
                for (mailboxId, emails) in cachedMailboxes {
                    // Deduplica prima di aggiungere
                    let deduplicated = self.deduplicateEmails(emails)
                    
                    for email in deduplicated {
                        self.emailIndex[email.id] = email
                        
                        if self.mailboxIndex[mailboxId] == nil {
                            self.mailboxIndex[mailboxId] = Set<String>()
                        }
                        self.mailboxIndex[mailboxId]?.insert(email.id)
                        
                        totalLoaded += 1
                    }
                }
                
                // Invalida cache
                for mailboxId in self.mailboxIndex.keys {
                    self.sortedCacheInvalid.insert(mailboxId)
                }
                
                // IMPORTANTE: Aggiorna emailsByMailbox in UN SOLO batch per evitare loop infiniti
                var updatedMailboxes: [String: [Email]] = [:]
                for mailboxId in self.mailboxIndex.keys {
                    updatedMailboxes[mailboxId] = self.getEmails(forMailbox: mailboxId)
                }
                // Aggiorna tutto in una volta invece di modificare @Published multiple volte
                self.emailsByMailbox = updatedMailboxes
                
                print("[EmailRepository] ✅ Caricati \(totalLoaded) email da cache legacy")
                
                // Migra a nuovo formato
                if !cachedMailboxes.isEmpty {
                    self.saveToCache()
                }
            }
        }
    }
    
    /// Salva l'indice completo nella cache (FORZA immediato, usare con parsimonia)
    func saveToCache() {
        // Flush pending saves first
        let emailsToSave = pendingEmailsToSave
        pendingEmailsToSave.removeAll()
        pendingSaveDebounceTask?.cancel()
        
        repositoryQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Salva ogni email pendente
            for emailId in emailsToSave {
                if let email = self.emailIndex[emailId] {
                    self.cacheService.saveFullEmail(email, forId: emailId)
                }
            }
            
            // Salva indice completo
            let index = self.emailIndex
            self.cacheService.saveEmailIndex(index)
            
            print("[EmailRepository] 💾 Salvato indice completo (\(self.emailIndex.count) email)")
        }
    }
    
    // MARK: - Private Helpers
    
    /// Deduplica un array di email mantenendo solo la versione più recente
    private func deduplicateEmails(_ emails: [Email]) -> [Email] {
        var seen = Set<String>()
        var deduplicated: [Email] = []
        
        // Ordina per data (più recente prima)
        let sorted = emails.sorted { $0.date > $1.date }
        
        for email in sorted {
            if !seen.contains(email.id) {
                seen.insert(email.id)
                deduplicated.append(email)
            }
        }
        
        return deduplicated
    }
    
    /// Pulisce il repository (utile per test o reset)
    func clear() {
        emailIndex.removeAll()
        mailboxIndex.removeAll()
        sortedEmailsCache.removeAll()
        sortedCacheInvalid.removeAll()
        emailsByMailbox.removeAll()
        pendingUIUpdates.removeAll()
        pendingEmailsToSave.removeAll()
        print("[EmailRepository] 🧹 Repository pulito")
    }
}
