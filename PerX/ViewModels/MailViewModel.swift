import Foundation
import Combine
import AppKit
import CoreData

// Struttura che combina i dati di un'etichetta con le sue personalizzazioni e stato
struct DisplayableMailbox: Identifiable, Hashable {
    let id: String
    var name: String
    var iconName: String
    var isVisible: Bool
    var unreadCount: Int
    var showUnreadCount: Bool
}

@MainActor
class MailViewModel: ObservableObject {
    static let shared = MailViewModel()
    
    // Repository centralizzato per gestione email con deduplicazione
    private let emailRepository = EmailRepository.shared
    
    // Computed property per backward compatibility - legge da EmailRepository
    @Published var emailsByMailbox: [String: [Email]] = [:] {
        didSet {
            // Sincronizza con EmailRepository quando viene modificato esternamente
            // (per backward compatibility durante la migrazione)
        }
    }
    
    @Published var displayableMailboxes: [DisplayableMailbox] = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Progress tracking per il download incrementale
    @Published var downloadProgress: Double = 0.0 // 0.0 - 1.0
    @Published var downloadStatus: String = ""
    @Published var isDownloading = false
    
    // Task per la sincronizzazione corrente
    private var syncTask: Task<Void, Never>?
    
    // Tracking per evitare download duplicati
    private var lastSyncDate: Date?
    private var isMonitoringActive = false

    private var labels: [GmailLabel] = []
    private var customizations: [String: MailboxCustomization] = [:]
    
    private let authService = GoogleAuthService.shared
    private let customizationService = MailboxCustomizationService.shared
    private let mailManager = MailManager.shared
    private let gmailService = GmailService.shared
    private let aiService = AppleIntelligenceService.shared
    
    // Hub integration
    private let hubMode = HubModeService.shared
    private let emailAdapter = EmailAdapter.shared
    
    // Cache per i riassunti email
    private var emailSummaries: [String: String] = [:]
    
    // Observer per sincronizzare emailsByMailbox con EmailRepository
    private var repositoryObserver: AnyCancellable?

    private init() {
        // Carica subito le personalizzazioni (non modifica @Published)
        self.customizations = customizationService.loadCustomizations()
        
        // IMPORTANTE: NON modificare @Published properties durante init() - causa loop infiniti
        // Ritarda tutte le operazioni che modificano @Published
        
        // Setup delle osservazioni in modo asincrono per evitare crash all'avvio
        Task { @MainActor in
            setupRepositoryObservation()
        }
        
        // Ritarda syncEmailsFromRepository e updateDisplayableMailboxes per evitare modifiche @Published durante init
        // Delay maggiore per assicurarsi che EmailRepository abbia finito di caricare
        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2 secondi delay (dopo EmailRepository)
            await MainActor.run {
                self?.syncEmailsFromRepository()
                self?.updateDisplayableMailboxes()
            }
        }
        
        // Il monitoring viene avviato esplicitamente tramite startMonitoring()
        // chiamato da PerXApp all'avvio dell'applicazione
        // Non stampiamo qui perché verrà stampato in startMonitoring()
    }
    
    private func setupRepositoryObservation() {
        // Osserva cambiamenti in EmailRepository per sincronizzare
        // IMPORTANTE: dropFirst() evita il trigger iniziale che causa loop di pubblicazione
        // debounce evita aggiornamenti troppo frequenti che causano freeze
        repositoryObserver = emailRepository.$emailsByMailbox
            .dropFirst() // Ignora il valore iniziale per evitare loop
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] newEmailsByMailbox in
                self?.emailsByMailbox = newEmailsByMailbox
            }
    }
    
    /// Sincronizza emailsByMailbox da EmailRepository
    private func syncEmailsFromRepository() {
        emailsByMailbox = emailRepository.emailsByMailbox
    }
    
    private func loadData() {
        self.customizations = customizationService.loadCustomizations()
        loadEmailsFromCache()
        
        Task {
            await fetchLabels()
        }
    }

    private func loadEmailsFromCache() {
        // EmailRepository carica automaticamente dalla cache all'inizializzazione
        // Qui sincronizziamo solo la struttura pubblicata
        syncEmailsFromRepository()
        updateDisplayableMailboxes() // Aggiorna la UI con i dati in cache
        
        // NON accodare automaticamente tutte le email non scaricate
        // Il download avverrà solo on-demand quando l'utente apre un'email
        // o quando vengono trovate nuove email recenti
        print("[ViewModel] ℹ️ Cache caricata - download automatico disabilitato (solo on-demand)")
    }

    func fetchLabels() async {
        guard let accessToken = try? await authService.getAccessToken() else {
            errorMessage = "Token di accesso non valido."
            return
        }
        
        let url = URL(string: "https://www.googleapis.com/gmail/v1/users/me/labels")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let maxRetries = 5
        var currentRetry = 0
        var delay: TimeInterval = 1.0

        while currentRetry < maxRetries {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    if statusCode >= 500 && currentRetry < maxRetries - 1 {
                        print("Errore server (\(statusCode)), ritento tra \(delay) secondi...")
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        delay *= 2 // Raddoppia il ritardo per il prossimo tentativo
                        currentRetry += 1
                        continue // Salta al prossimo tentativo
                    }
                 let body = String(data: data, encoding: .utf8)
                throw GmailAPIError.badServerResponse(statusCode: statusCode, responseBody: body)
            }
                
            let labelResponse = try JSONDecoder().decode(GmailLabelList.self, from: data)
            self.labels = labelResponse.labels
            
            // Successo! Esci dal ciclo.
            ensureCustomizationsExist()
            return // Esci dalla funzione
            
        } catch {
                if currentRetry >= maxRetries - 1 {
            errorMessage = "Errore durante il recupero delle etichette: \(error.localizedDescription)"
                    return
                }
            }
        }
    }

    /// Avvia il monitoring persistente delle email
    func startMonitoring() {
        guard !isMonitoringActive else {
            print("[ViewModel] ⚠️ Monitoring già attivo, ignoro la richiesta")
            return
        }
        
        isMonitoringActive = true
        print("[ViewModel] 🚀 Avvio monitoring email via Hub")
        
        // Task.detached con delay per evitare modifiche @Published durante il rendering delle view
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            // Delay iniziale per evitare loop di pubblicazione durante l'avvio
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Verifica connessione Hub
            await HubModeService.shared.checkHubConnection()
            
            let hubConnected = await MainActor.run { HubModeService.shared.hubConnected }
            guard hubConnected else {
                await MainActor.run {
                    self.errorMessage = "Hub non connesso - email non disponibili"
                }
                print("[ViewModel] ❌ Hub non connesso, monitoring non avviato")
                return
            }
            
            // Recupera email utente
            guard let userEmail = await MainActor.run(body: { self.authService.userEmail }) else {
                print("[ViewModel] ⚠️ Utente non autenticato")
                return
            }
            
            // Sync iniziale da Hub
            print("[ViewModel] 📥 Sincronizzazione iniziale email da Hub...")
            await self.fetchEmailsFromHub(prioritize: nil)
            
            // Avvia polling Hub (ogni 60 secondi)
            print("[ViewModel] 🔄 Avvio polling Hub (ogni 60s)...")
            await MainActor.run {
                self.emailAdapter.startPolling(userEmail: userEmail, interval: 60)
            }
            
            print("[ViewModel] ✅ Monitoring Hub completamente avviato")
        }
    }
    
    /// Ferma il monitoring (usato al logout)
    func stopMonitoring() {
        guard isMonitoringActive else { return }
        isMonitoringActive = false
        emailAdapter.stopPolling()
        print("[ViewModel] 🛑 Monitoring email fermato")
    }
    
    /// Controlla solo le nuove email degli ultimi 7 giorni senza scaricare tutto
    private func checkForNewEmailsOnly() async {
        guard let accessToken = try? await authService.getAccessToken() else {
            print("[ViewModel] ⚠️ Token non disponibile per controllo nuove email")
            return
        }
        
        guard !labels.isEmpty else {
            print("[ViewModel] ⚠️ Nessuna etichetta disponibile")
            return
        }
        
        // Cerca solo email degli ultimi 7 giorni
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let dateQuery = "after:\(dateFormatter.string(from: sevenDaysAgo))"
        
        var totalNew = 0
        
        for (index, label) in labels.enumerated() {
            do {
                // Ottieni solo i nuovi messaggi degli ultimi 7 giorni
                // Usa EmailRepository per verificare email esistenti con deduplicazione
                let existingEmails = emailRepository.getEmails(forMailbox: label.id)
                let existingIds = Set(existingEmails.map { $0.id })
                
                // Query per email degli ultimi 7 giorni
                let messages = try await fetchEmailList(for: label.id, accessToken: accessToken, query: dateQuery)
                
                // Filtra solo i nuovi (con controllo duplicati)
                let newMessages = messages.filter { !existingIds.contains($0.id) }
                
                if !newMessages.isEmpty {
                    totalNew += newMessages.count
                    print("[ViewModel] 📧 \(label.name): \(newMessages.count) nuove email (ultimi 7 giorni)")
                    
                    // Scarica solo i metadati delle nuove email
                    let newEmails = await fetchDetails(for: newMessages, accessToken: accessToken)
                    
                    // Aggiungi con deduplicazione automatica tramite EmailRepository
                    let result = emailRepository.addEmails(newEmails, forMailbox: label.id)
                    print("[ViewModel] 🔍 Deduplicazione: \(result.added) nuove, \(result.updated) aggiornate")
                    
                    await MainActor.run {
                        updateDisplayableMailboxes()
                        
                        // L'associazione automatica email-sinistro avviene automaticamente quando le email vengono processate da MailManager
                        // Non serve fare qui - MailManager.processEmails() chiama EmailAssociationService dopo il processamento
                    }
                } else if index == 0 || index == labels.count - 1 {
                    print("[ViewModel] ✓ \(label.name): nessuna nuova email")
                }
            } catch {
                print("[ViewModel] ❌ Errore nel controllo nuove email per \(label.name): \(error)")
            }
        }
        
        if totalNew > 0 {
            print("[ViewModel] ✅ Trovate \(totalNew) nuove email totali (ultimi 7 giorni), salvate in cache")
            emailRepository.saveToCache()
            
            // Processa le nuove email scaricate
            print("[ViewModel] 🔄 Processamento nuove email con handler...")
            let context = PersistenceController.shared.container.viewContext
            
            // Ottieni solo le email realmente nuove (non ancora processate)
            // MailManager controllerà internamente se sono già processate
            let emailsToProcess = labels.flatMap { label in
                emailRepository.getEmails(forMailbox: label.id)
            }.filter { email in
                // Prendi solo email degli ultimi 7 giorni per evitare di processare tutto
                let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
                return email.date >= sevenDaysAgo
            }
            
            if !emailsToProcess.isEmpty {
                await MailManager.shared.processEmails(emailsToProcess, context: context)
                // MailManager logga internamente quante email sono state effettivamente processate
            }
        } else {
            print("[ViewModel] ✓ Nessuna nuova email trovata (ultimi 7 giorni)")
        }
        
        lastSyncDate = Date()
    }
    
    /// Normalizza un numero rimuovendo caratteri non alfanumerici (trattini, slash, spazi)
    private func normalizeNumber(_ number: String) -> String {
        return number.replacingOccurrences(of: "[^0-9A-Za-z]", with: "", options: .regularExpression)
    }
    
    /// Crea query Gmail che cerca variazioni di un numero (ignorando trattini e slash)
    /// Gestisce formati come 005REE002025015575421 che possono essere scritti come:
    /// 005-REE-00-2025-015575421, 005/REE/00/2025/015575421, 005REE00/2025/015575421, etc.
    private func createFuzzyNumberQuery(_ number: String) -> String {
        let normalized = normalizeNumber(number)
        guard !normalized.isEmpty else { return "" }
        
        var queries: [String] = []
        
        // Query esatta con il numero normalizzato (senza separatori)
        queries.append("\"\(normalized)\"")
        
        let chars = Array(normalized)
        let charCount = chars.count
        
        // Genera varianti con separatori in posizioni comuni
        // Per numeri tipo 005REE002025015575421 (20 caratteri):
        // - Dopo 3 caratteri: 005-REE002025015575421
        // - Dopo 6 caratteri: 005REE-002025015575421
        // - Dopo 8 caratteri: 005REE00-2025015575421
        // - Dopo 12 caratteri: 005REE002025-015575421
        // - Combinazioni multiple
        
        // Posizioni comuni per inserire separatori (basate sul formato tipico)
        let separatorPositions = [3, 6, 8, 12]
        
        // Genera varianti con un solo separatore
        for pos in separatorPositions where pos < charCount {
            // Variante con trattino
            let variantDash = String(chars[0..<pos]) + "-" + String(chars[pos...])
            queries.append("\"\(variantDash)\"")
            
            // Variante con slash
            let variantSlash = String(chars[0..<pos]) + "/" + String(chars[pos...])
            queries.append("\"\(variantSlash)\"")
        }
        
        // Genera varianti con più separatori (pattern comune: 005-REE-00-2025-015575421)
        if charCount >= 12 {
            // Pattern: 3-3-2-4-resto
            if charCount >= 20 {
                let variant1 = String(chars[0..<3]) + "-" + 
                              String(chars[3..<6]) + "-" + 
                              String(chars[6..<8]) + "-" + 
                              String(chars[8..<12]) + "-" + 
                              String(chars[12...])
                queries.append("\"\(variant1)\"")
                
                let variant2 = String(chars[0..<3]) + "/" + 
                              String(chars[3..<6]) + "/" + 
                              String(chars[6..<8]) + "/" + 
                              String(chars[8..<12]) + "/" + 
                              String(chars[12...])
                queries.append("\"\(variant2)\"")
            }
            
            // Pattern: 3-3-2-4 (senza resto se il numero è più corto)
            if charCount >= 12 {
                var variant3 = String(chars[0..<3]) + "-" + 
                              String(chars[3..<6]) + "-" + 
                              String(chars[6..<8]) + "-" + 
                              String(chars[8..<12])
                if charCount > 12 {
                    variant3 += "-" + String(chars[12...])
                }
                queries.append("\"\(variant3)\"")
                
                var variant3Slash = String(chars[0..<3]) + "/" + 
                                   String(chars[3..<6]) + "/" + 
                                   String(chars[6..<8]) + "/" + 
                                   String(chars[8..<12])
                if charCount > 12 {
                    variant3Slash += "/" + String(chars[12...])
                }
                queries.append("\"\(variant3Slash)\"")
            }
            
            // Pattern alternativo: 6-2-4-resto (005REE-00-2025-015575421)
            if charCount >= 12 {
                var variant4 = String(chars[0..<6]) + "-" + 
                              String(chars[6..<8]) + "-" + 
                              String(chars[8..<12])
                if charCount > 12 {
                    variant4 += "-" + String(chars[12...])
                }
                queries.append("\"\(variant4)\"")
                
                var variant4Slash = String(chars[0..<6]) + "/" + 
                                   String(chars[6..<8]) + "/" + 
                                   String(chars[8..<12])
                if charCount > 12 {
                    variant4Slash += "/" + String(chars[12...])
                }
                queries.append("\"\(variant4Slash)\"")
            }
        }
        
        // Pattern: 8-4-resto (005REE00-2025-015575421)
        if charCount >= 12 {
            var variant5 = String(chars[0..<8]) + "-" + 
                          String(chars[8..<12])
            if charCount > 12 {
                variant5 += "-" + String(chars[12...])
            }
            queries.append("\"\(variant5)\"")
            
            var variant6 = String(chars[0..<8]) + "/" + 
                          String(chars[8..<12])
            if charCount > 12 {
                variant6 += "/" + String(chars[12...])
            }
            queries.append("\"\(variant6)\"")
        }
        
        // Rimuovi duplicati e unisci con OR
        let uniqueQueries = Array(Set(queries))
        return uniqueQueries.joined(separator: " OR ")
    }
    
    /// Cerca email associate a un sinistro usando Gmail API query con priorità a cascata
    /// 1. Riferimento
    /// 2. Numero agenzia intero (senza separatori)
    /// 3. Numero agenzia con varianti (con separatori)
    /// DEPRECATO: Questo metodo fa ricerche su Gmail che non dovrebbero essere fatte
    /// L'associazione email-sinistro avviene automaticamente quando le email vengono processate
    /// usando pattern matching su email già scaricate (EmailPatternMatcher + checkEmailAssociation)
    /// 4. Nome/Email assicurato
    /// NOTA: Cerca TUTTE le email, non solo quelle degli ultimi 7 giorni
    @available(*, deprecated, message: "Usa pattern matching su email già scaricate invece di ricerche su Gmail")
    func searchEmailsForSinistro(_ sinistro: Sinistro) async throws -> [String] {
        print("[ViewModel] ⚠️ DEPRECATO: searchEmailsForSinistro chiamato - usa pattern matching invece")
        return [] // Ritorna vuoto per evitare ricerche su Gmail
        guard let accessToken = try? await authService.getAccessToken() else {
            throw GmailAPIError.tokenError("Token di accesso non valido")
        }
        
        var foundMessageIds = Set<String>()
        
        // FASE 1: Cerca per riferimento (valore esatto, non frammentato)
        if let riferimento = sinistro.riferimento, !riferimento.isEmpty {
            let refQuery = "\"\(riferimento)\""
            print("[ViewModel] 🔍 Fase 1: Ricerca per riferimento: \(riferimento)")
            
            do {
                let ids = try await performSearch(query: refQuery, accessToken: accessToken)
                foundMessageIds.formUnion(ids)
                print("[ViewModel] ✅ Fase 1: Trovate \(ids.count) email per riferimento")
            } catch {
                print("[ViewModel] ⚠️ Fase 1 fallita: \(error)")
            }
        }
        
        // FASE 2: Cerca per numero agenzia intero (senza separatori)
        if let numeroAgenzia = sinistro.numeroSinistroCompagnia, !numeroAgenzia.isEmpty {
            let numQuery = "\"\(numeroAgenzia)\""
            print("[ViewModel] 🔍 Fase 2: Ricerca per numero agenzia intero: \(numeroAgenzia)")
            
            do {
                let ids = try await performSearch(query: numQuery, accessToken: accessToken)
                // Rimuovi quelli già trovati con il riferimento
                let newIds = ids.filter { !foundMessageIds.contains($0) }
                foundMessageIds.formUnion(newIds)
                print("[ViewModel] ✅ Fase 2: Trovate \(newIds.count) nuove email per numero agenzia intero")
            } catch {
                print("[ViewModel] ⚠️ Fase 2 fallita: \(error)")
            }
        }
        
        // FASE 3: Cerca per numero agenzia con varianti (con separatori)
        if let numeroAgenzia = sinistro.numeroSinistroCompagnia, !numeroAgenzia.isEmpty {
            let fuzzyQuery = createFuzzyNumberQuery(numeroAgenzia)
            if !fuzzyQuery.isEmpty {
                print("[ViewModel] 🔍 Fase 3: Ricerca per numero agenzia con varianti")
                
                do {
                    let ids = try await performSearch(query: fuzzyQuery, accessToken: accessToken)
                    // Rimuovi quelli già trovati
                    let newIds = ids.filter { !foundMessageIds.contains($0) }
                    foundMessageIds.formUnion(newIds)
                    print("[ViewModel] ✅ Fase 3: Trovate \(newIds.count) nuove email per numero agenzia con varianti")
                } catch {
                    print("[ViewModel] ⚠️ Fase 3 fallita: \(error)")
                }
            }
        }
        
        // FASE 4: Cerca per nome/email assicurato (solo se non abbiamo trovato abbastanza risultati)
        if foundMessageIds.count < 5, let nomeAssicurato = sinistro.nomeAssicurato, !nomeAssicurato.isEmpty {
            let nomeQuery = "\"\(nomeAssicurato)\""
            print("[ViewModel] 🔍 Fase 4: Ricerca per nome assicurato: \(nomeAssicurato)")
            
            do {
                let ids = try await performSearch(query: nomeQuery, accessToken: accessToken)
                let newIds = ids.filter { !foundMessageIds.contains($0) }
                foundMessageIds.formUnion(newIds)
                print("[ViewModel] ✅ Fase 4: Trovate \(newIds.count) nuove email per nome assicurato")
            } catch {
                print("[ViewModel] ⚠️ Fase 4 fallita: \(error)")
            }
        }
        
        // FASE 5: Cerca per email assicurato
        if let emailAssicuratoArray = sinistro.emailAssicuratoArray as? [String], !emailAssicuratoArray.isEmpty {
            for email in emailAssicuratoArray.prefix(3) { // Limita a 3 email per non fare troppe ricerche
                let emailQuery = "from:\(email) OR to:\(email) OR cc:\(email)"
                print("[ViewModel] 🔍 Fase 5: Ricerca per email assicurato: \(email)")
                
                do {
                    let ids = try await performSearch(query: emailQuery, accessToken: accessToken)
                    let newIds = ids.filter { !foundMessageIds.contains($0) }
                    foundMessageIds.formUnion(newIds)
                    print("[ViewModel] ✅ Fase 5: Trovate \(newIds.count) nuove email per email assicurato")
                } catch {
                    print("[ViewModel] ⚠️ Fase 5 fallita per \(email): \(error)")
                }
            }
        }
        
        let result = Array(foundMessageIds)
        print("[ViewModel] ✅ Totale email trovate per sinistro \(sinistro.riferimento ?? "N/A"): \(result.count)")
        return result
    }
    
    /// Esegue una ricerca email usando Gmail API
    /// Cerca in tutte le caselle (INBOX, SENT, ecc.) per trovare tutte le email
    private func performSearch(query: String, accessToken: String) async throws -> [String] {
        // Cerca sempre in modo globale (senza labelId) per trovare tutte le email
        // indipendentemente dalla casella in cui si trovano
        do {
            let messages = try await fetchEmailList(for: nil, accessToken: accessToken, query: query)
            let messageIds = messages.map { $0.id }
            print("[ViewModel] 🔍 Ricerca globale: trovate \(messageIds.count) email")
            return messageIds
        } catch {
            print("[ViewModel] ⚠️ Ricerca globale fallita, provo per caselle principali...")
            
            // Fallback: cerca nelle caselle principali (INBOX, SENT, DRAFT)
            var allMessageIds: Set<String> = []
            let mainLabels = ["INBOX", "SENT", "DRAFT", "IMPORTANT"]
            
            for labelId in mainLabels {
                do {
                    let messages = try await fetchEmailList(for: labelId, accessToken: accessToken, query: query)
                    allMessageIds.formUnion(messages.map { $0.id })
                } catch {
                    // Ignora errori per singole caselle
                }
            }
            
            print("[ViewModel] 🔍 Ricerca per caselle: trovate \(allMessageIds.count) email")
            return Array(allMessageIds)
        }
    }
    
    /// DEPRECATO: Questo metodo fa ricerche su Gmail che non dovrebbero essere fatte
    /// L'associazione email-sinistro avviene automaticamente quando le email vengono processate
    /// usando pattern matching su email già scaricate (EmailPatternMatcher + checkEmailAssociation)
    /// Crea o aggiorna un SinistroEmailThread con solo i messageIds (senza scaricare contenuto)
    /// Verifica se l'indexing è già stato fatto e aggiunge solo nuovi messageIds
    @available(*, deprecated, message: "L'associazione avviene automaticamente quando le email vengono processate")
    func indexEmailsForSinistro(_ sinistro: Sinistro, context: NSManagedObjectContext) async {
        print("[ViewModel] ⚠️ DEPRECATO: indexEmailsForSinistro chiamato - associazione automatica attiva")
        return // Non fare nulla - l'associazione avviene automaticamente
        // Verifica se esiste già un thread
        let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        request.predicate = NSPredicate(format: "sinistro == %@", sinistro)
        request.fetchLimit = 1
        
        let existingThreads = (try? context.fetch(request)) ?? []
        
        // Se esiste già un thread, aggiornalo comunque
        if let existingThread = existingThreads.first {
            print("[ViewModel] 🔄 Aggiornamento thread esistente per sinistro \(sinistro.riferimento ?? "N/A")")
        } else {
            print("[ViewModel] ✨ Creazione nuovo thread per sinistro \(sinistro.riferimento ?? "N/A")")
        }
        
        do {
            let messageIds = try await searchEmailsForSinistro(sinistro)
            
            guard !messageIds.isEmpty else {
                print("[ViewModel] ℹ️ Nessuna email trovata per sinistro \(sinistro.riferimento ?? "N/A")")
                return
            }
            
            await MainActor.run {
                let thread: SinistroEmailThread
                
                if let existing = existingThreads.first {
                    thread = existing
                    // Sostituisci tutti i messageIds con quelli trovati (ricerca completa)
                    // Questo assicura che tutte le email vengano incluse, anche quelle trovate in ricerche successive
                    let existingCount = thread.messageIds.count
                    thread.messageIds = messageIds
                    thread.dataUltimaModifica = Date()
                    
                    if messageIds.count > existingCount {
                        print("[ViewModel] 📝 Aggiornato thread esistente: \(existingCount) -> \(messageIds.count) email (+\(messageIds.count - existingCount) nuove)")
                    } else if messageIds.count < existingCount {
                        print("[ViewModel] 📝 Aggiornato thread esistente: \(existingCount) -> \(messageIds.count) email (ricerca più precisa)")
                    } else {
                        print("[ViewModel] ℹ️ Thread già aggiornato: \(messageIds.count) email")
                    }
                } else {
                    // Crea nuovo thread
                    thread = SinistroEmailThread(context: context)
                    thread.sinistro = sinistro
                    thread.messageIds = messageIds
                    thread.dataCreazione = Date()
                    thread.dataUltimaModifica = Date()
                    print("[ViewModel] ✨ Creato nuovo thread con \(messageIds.count) email")
                }
                
                do {
                    try context.save()
                    print("[ViewModel] ✅ Thread salvato per sinistro \(sinistro.riferimento ?? "N/A")")
                } catch {
                    print("[ViewModel] ❌ Errore salvataggio thread: \(error)")
                }
            }
        } catch {
            print("[ViewModel] ❌ Errore indicizzazione email per sinistro: \(error)")
        }
    }
    
    func fetchAllEmails(prioritize mailboxId: String? = nil) async {
        // Se c'è già una sincronizzazione in corso, non avviarne un'altra
        guard !isDownloading else { return }
        
        // TUTTO passa dall'Hub - nessun fallback locale
        await fetchEmailsFromHub(prioritize: mailboxId)
    }
    
    /// Interrompe la sincronizzazione in corso
    func stopSync() {
        if isDownloading {
            print("[ViewModel] 🛑 Richiesta interruzione sincronizzazione")
            syncTask?.cancel()
            syncTask = nil
            isDownloading = false
            isLoading = false
            downloadStatus = "Sincronizzazione interrotta"
        }
    }
    
    // MARK: - Hub Mode
    
    /// Recupera email dall'Hub centrale
    private func fetchEmailsFromHub(prioritize mailboxId: String?) async {
        isLoading = true
        isDownloading = true
        downloadProgress = 0.0
        downloadStatus = "Connessione all'Hub..."
        errorMessage = nil
        
        do {
            // Recupera email per l'utente corrente
            guard let userEmail = authService.userEmail else {
                throw NSError(domain: "MailViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Utente non autenticato"])
            }
            
            downloadStatus = "Scaricamento caselle da Hub..."
            downloadProgress = 0.2
            
            // Recupera mailbox disponibili dall'Hub
            let hubMailboxes = try await emailAdapter.getMailboxes(userEmail: userEmail)
            
            downloadStatus = "Scaricamento email da Hub..."
            downloadProgress = 0.4
            
            let emailItems = try await emailAdapter.getEmails(userEmail: userEmail, limit: 500)
            
            downloadStatus = "Elaborazione email..."
            downloadProgress = 0.7
            
            // Converte EmailListItem in Email e aggiorna la cache
            var newEmailsByMailbox: [String: [Email]] = [:]
            
            for item in emailItems {
                // Crea sender Contact
                let sender = Contact(name: item.senderName, email: item.senderEmail)
                
                let email = Email(
                    id: item.id,
                    isRead: item.isRead,
                    isDownloaded: true,
                    sender: sender,
                    recipients: [],
                    cc: nil,
                    subject: item.subject,
                    date: item.date,
                    body: nil,
                    attachments: nil,
                    claimNumber: item.sinistroRef,
                    insuredName: nil,
                    associationStatus: nil
                )
                
                // Raggruppa per mailbox (usa quella dall'Hub o default)
                let mailboxKey = item.mailbox ?? (item.direction == "OUT" ? "SENT" : "INBOX")
                if newEmailsByMailbox[mailboxKey] == nil {
                    newEmailsByMailbox[mailboxKey] = []
                }
                newEmailsByMailbox[mailboxKey]?.append(email)
            }
            
            // Aggiorna lo stato
            emailsByMailbox = newEmailsByMailbox
            
            // Aggiorna displayableMailboxes dalle mailbox Hub
            updateDisplayableMailboxesFromHub(hubMailboxes)
            
            downloadProgress = 1.0
            downloadStatus = "Sincronizzazione completata"
            lastSyncDate = Date()
            print("[MailViewModel] ✅ Caricate \(emailItems.count) email e \(hubMailboxes.count) caselle da Hub")
            
        } catch {
            print("[MailViewModel] ❌ Errore Hub: \(error)")
            errorMessage = "Errore Hub: \(error.localizedDescription)"
            downloadStatus = "Errore"
        }
        
        isLoading = false
        isDownloading = false
    }
    
    /// Aggiorna displayableMailboxes dalle mailbox ricevute dall'Hub
    private func updateDisplayableMailboxesFromHub(_ mailboxes: [MailboxDTO]) {
        var newDisplayable: [DisplayableMailbox] = []
        
        for mailbox in mailboxes {
            let custom = customizations[mailbox.id]
            let displayable = DisplayableMailbox(
                id: mailbox.id,
                name: custom?.customName ?? mailbox.name,
                iconName: custom?.iconName ?? iconForMailbox(mailbox.id),
                isVisible: custom?.isVisible ?? true,
                unreadCount: mailbox.unreadCount,
                showUnreadCount: custom?.showUnreadCount ?? true
            )
            newDisplayable.append(displayable)
        }
        
        // Ordina: INBOX prima, poi SENT, poi altri alfabeticamente
        newDisplayable.sort { a, b in
            if a.id == "INBOX" { return true }
            if b.id == "INBOX" { return false }
            if a.id == "SENT" { return true }
            if b.id == "SENT" { return false }
            return a.name < b.name
        }
        
        displayableMailboxes = newDisplayable
    }
    
    /// Icona default per mailbox
    private func iconForMailbox(_ mailboxId: String) -> String {
        switch mailboxId.uppercased() {
        case "INBOX": return "tray.fill"
        case "SENT": return "paperplane.fill"
        case "DRAFT", "DRAFTS": return "doc.text"
        case "TRASH": return "trash"
        case "SPAM": return "exclamationmark.triangle"
        case "STARRED": return "star.fill"
        case "IMPORTANT": return "bookmark.fill"
        default: return "folder"
        }
    }

    /// Scarica e processa i metadati delle email per tutte le etichette memorizzate.
    private func fetchAndProcessEmailsForLabels() async {
        guard let accessToken = try? await authService.getAccessToken() else {
            errorMessage = "Token di accesso non valido."
            return
        }

        let totalLabels = labels.count
        print("[ViewModel] Inizio processamento di \(totalLabels) etichette")
        
        var processedLabels = 0
        var totalProcessedMessages = 0
        
        for (index, label) in labels.enumerated() {
            print("[ViewModel] [\(index + 1)/\(totalLabels)] Processamento etichetta: \(label.name) (ID: \(label.id))")
            
            await MainActor.run {
                self.downloadStatus = "Scaricamento \(label.name)..."
            }
            
            do {
                print("[ViewModel] Scaricamento metadati per etichetta: \(label.name)")
                
                // Passando `nil` come query, scarichiamo tutti i messaggi per l'etichetta
                let messages = try await fetchEmailList(for: label.id, accessToken: accessToken, query: nil)
                print("[ViewModel] Trovati \(messages.count) messaggi per etichetta \(label.name)")
                
                // Scarica i metadati incrementali (aggiorna la UI man mano)
                let messagesCount = messages.count
                await fetchDetailsIncremental(
                    for: messages,
                    accessToken: accessToken,
                    labelId: label.id,
                    labelName: label.name,
                    totalLabels: totalLabels,
                    processedLabels: &processedLabels,
                    totalProcessedMessages: &totalProcessedMessages
                )
                
                // Pausa più lunga per evitare rate limiting e permettere all'app di respirare
                if messages.count > 100 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 secondo
                } else {
                    // Pausa minima anche per batch piccoli per limitare risorse
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                }

            } catch {
                print("[ViewModel] ❌ ERRORE nel caricare email per l'etichetta \(label.name): \(error)")
                print("[ViewModel] Tipo errore: \(type(of: error))")
                if let gmailError = error as? GmailAPIError {
                    print("[ViewModel] Gmail API Error: \(gmailError)")
                }
                
                // Continua con la prossima etichetta invece di fermarsi
                continue
            }
        }
        
        // Salva lo stato corrente nella cache dopo aver processato tutte le etichette
        print("[ViewModel] Salvataggio cache...")
        await MainActor.run {
            self.downloadStatus = "Salvataggio cache..."
            emailRepository.saveToCache()
        }
        
        let totalEmails = emailRepository.getStats().totalEmails
        print("[ViewModel] ✅ Completato download metadati. Totale email: \(totalEmails)")
        
        await MainActor.run {
            self.downloadStatus = "Completato: \(totalEmails) email"
            self.downloadProgress = 1.0
        }
        
        // Log dettagliato per casella
        let stats = emailRepository.getStats()
        for (labelId, count) in stats.emailsPerMailbox {
            if count > 0 {
                print("[ViewModel]   • \(labelId): \(count) email")
            }
        }
        
        // Avvia il processo di automazione se è abilitato
        if AutomationSettingsService.shared.isAutomationEnabled {
            let allEmails = emailRepository.getAllEmails()
            let context = PersistenceController.shared.container.viewContext
            let defaultStatus = AutomationSettingsService.shared.defaultStatus
            
            print("[ViewModel] Avvio automazione per \(allEmails.count) email totali")
            
            Task {
                // Usa il nuovo MailManager centralizzato
                await mailManager.processEmails(allEmails, context: context)
            }
        }
    }

    /// Versione incrementale che aggiorna la UI man mano che le email vengono scaricate
    private func fetchDetailsIncremental(
        for messages: [GmailMessageInfo],
        accessToken: String,
        labelId: String,
        labelName: String,
        totalLabels: Int,
        processedLabels: inout Int,
        totalProcessedMessages: inout Int
    ) async {
        let totalMessagesForLabel = messages.count
        print("[ViewModel] Inizio download dettagli per \(totalMessagesForLabel) messaggi (parallelizzato, incrementale)...")
        
        // Download con limitazione risorse: max 30% delle risorse disponibili
        // Ridotto batch size e limitata concorrenza per evitare di bloccare l'app
        let batchSize = 3 // Ridotto ulteriormente per limitare risorse
        let maxConcurrentTasks = 2 // Massimo 2 task paralleli (30% delle risorse)
        var allEmails: [Email] = []
        var processedInLabel = 0
        var rateLimitErrors = 0
        var lastCacheSave = 0
        var duplicatesDetected = 0
        
        for batchStart in stride(from: 0, to: totalMessagesForLabel, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, totalMessagesForLabel)
            let batch = Array(messages[batchStart..<batchEnd])
            
            // Scarica il batch con limitazione concorrenza per rispettare limite risorse
            await withTaskGroup(of: Email?.self) { group in
                var activeCount = 0
                
                for messageInfo in batch {
                    // Limita il numero di task paralleli
                    while activeCount >= maxConcurrentTasks {
                        // Attendi che un task finisca prima di aggiungerne altri
                        _ = await group.next()
                        activeCount -= 1
                        
                        // Pausa per permettere all'app di processare altre operazioni
                        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    }
                    
                    activeCount += 1
                    
                    group.addTask(priority: .utility) {
                        var retryCount = 0
                        let maxRetries = 3
                        
                        while retryCount <= maxRetries {
                            do {
                                // Pausa iniziale per distribuire il carico
                                if retryCount == 0 {
                                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                                }
                                
                                return try await self.fetchEmailDetails(messageId: messageInfo.id, accessToken: accessToken, metadataOnly: true)
                            } catch {
                                // Gestione errori rate limit (403)
                                if let gmailError = error as? GmailAPIError,
                                   case .badServerResponse(let statusCode, _) = gmailError,
                                   statusCode == 403 {
                                    rateLimitErrors += 1
                                    
                                    if retryCount < maxRetries {
                                        // Backoff esponenziale: 2s, 4s, 8s
                                        let delay = pow(2.0, Double(retryCount)) * 2.0
                                        print("[ViewModel] ⚠️ Rate limit raggiunto, attesa \(delay)s prima del retry...")
                                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                                        retryCount += 1
                                        continue
                                    } else {
                                        print("[ViewModel] ❌ Rate limit persistente per email \(messageInfo.id), skip")
                                        return nil
                                    }
                                } else {
                                    print("[ViewModel] ❌ Errore nel download email \(messageInfo.id): \(error)")
                                    return nil
                                }
                            }
                        }
                        return nil
                    }
                }
                
                // Raccogli tutti i risultati rimanenti
                for await _ in group {
                    activeCount -= 1
                }
                
                // Raccogli i risultati e aggiorna la UI incrementale con deduplicazione
                for await email in group {
                    if let email = email {
                        // Usa EmailRepository per aggiungere con deduplicazione automatica
                        let isNew = await MainActor.run {
                            let wasNew = self.emailRepository.addOrUpdateEmail(email, forMailbox: labelId)
                            if !wasNew {
                                duplicatesDetected += 1
                            }
                            self.updateDisplayableMailboxes()
                            
                            // Aggiorna il progresso basato sulle etichette processate
                            processedInLabel += 1
                            totalProcessedMessages += 1
                            let labelProgress = Double(processedLabels) / Double(totalLabels)
                            let currentLabelProgress = Double(processedInLabel) / Double(totalMessagesForLabel)
                            self.downloadProgress = labelProgress + (currentLabelProgress / Double(totalLabels))
                            self.downloadStatus = "\(labelName): \(processedInLabel)/\(totalMessagesForLabel) email"
                            
                            return wasNew
                        }
                        
                        if isNew {
                            allEmails.append(email)
                        }
                    }
                    
                    // Pausa periodica per permettere all'app di processare altre operazioni
                    if processedInLabel % 10 == 0 {
                        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms ogni 10 email
                    }
                }
            }
            
            // Salva cache ogni 50 email invece che ogni email (riduce I/O)
            if processedInLabel - lastCacheSave >= 50 {
                await MainActor.run {
                    emailRepository.saveToCache()
                    lastCacheSave = processedInLabel
                }
                
                // Pausa dopo il salvataggio cache per permettere I/O di altre operazioni
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            }
            
            // Pausa tra batch per limitare l'uso delle risorse
            if batchEnd < totalMessagesForLabel {
                try? await Task.sleep(nanoseconds: 150_000_000) // 150ms tra batch
            }
            
            // Log progresso
            if batchEnd % 100 == 0 || batchEnd == totalMessagesForLabel {
                print("[ViewModel] Progresso: \(batchEnd)/\(totalMessagesForLabel) (\(Int(Double(batchEnd)/Double(totalMessagesForLabel)*100))%)")
                if rateLimitErrors > 0 {
                    print("[ViewModel] ⚠️ Errori rate limit: \(rateLimitErrors)")
                }
            }
            
            // Pausa più lunga tra batch per rispettare rate limit (15000/min = ~250/sec)
            // Con batch di 5, facciamo ~10 batch/sec = 50 req/sec, ben sotto il limite
            if batchEnd < totalMessagesForLabel {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 secondi tra batch
            }
            
            // Se abbiamo avuto errori rate limit, pausa più lunga
            if rateLimitErrors > 0 {
                print("[ViewModel] ⏸️ Pausa estesa per recupero rate limit...")
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 secondi extra
                rateLimitErrors = 0 // Reset dopo la pausa
            }
        }
        
        processedLabels += 1
        await MainActor.run {
            self.downloadProgress = Double(processedLabels) / Double(totalLabels)
            
            // Salva finale nella cache (solo se non salvato recentemente)
            if processedInLabel - lastCacheSave > 0 {
                emailRepository.saveToCache()
            }
        }
        
        if duplicatesDetected > 0 {
            print("[ViewModel] ⚠️ Rilevati \(duplicatesDetected) duplicati durante il download per \(labelName)")
        }
        print("[ViewModel] ✅ Completato download dettagli: \(allEmails.count)/\(totalMessagesForLabel) email per \(labelName)")
    }
    
    private func fetchDetails(for messages: [GmailMessageInfo], accessToken: String) async -> [Email] {
        let totalMessages = messages.count
        print("[ViewModel] Inizio download dettagli per \(totalMessages) messaggi (parallelizzato, rate-limited)...")
        
        // Download parallelo con batch per evitare rate limiting
        let batchSize = 5 // Ridotto per rispettare rate limit
        var allEmails: [Email] = []
        var rateLimitErrors = 0
        
        for batchStart in stride(from: 0, to: totalMessages, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, totalMessages)
            let batch = Array(messages[batchStart..<batchEnd])
            
            // Scarica il batch in parallelo con gestione errori rate limit
            await withTaskGroup(of: Email?.self) { group in
                for messageInfo in batch {
                    group.addTask {
                        var retryCount = 0
                        let maxRetries = 3
                        
                        while retryCount <= maxRetries {
                            do {
                                return try await self.fetchEmailDetails(messageId: messageInfo.id, accessToken: accessToken, metadataOnly: true)
                            } catch {
                                // Gestione errori rate limit (403)
                                if let gmailError = error as? GmailAPIError,
                                   case .badServerResponse(let statusCode, _) = gmailError,
                                   statusCode == 403 {
                                    rateLimitErrors += 1
                                    
                                    if retryCount < maxRetries {
                                        // Backoff esponenziale: 2s, 4s, 8s
                                        let delay = pow(2.0, Double(retryCount)) * 2.0
                                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                                        retryCount += 1
                                        continue
                                    } else {
                                        return nil
                                    }
                                } else {
                                    return nil
                                }
                            }
                        }
                        return nil
                    }
                }
                
                // Raccogli i risultati
                for await email in group {
                    if let email = email {
                        allEmails.append(email)
                    }
                }
            }
            
            // Log progresso
            if batchEnd % 100 == 0 || batchEnd == totalMessages {
                print("[ViewModel] Progresso: \(batchEnd)/\(totalMessages) (\(Int(Double(batchEnd)/Double(totalMessages)*100))%)")
            }
            
            // Pausa tra batch per rispettare rate limit
            if batchEnd < totalMessages {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 secondi tra batch
            }
            
            // Se abbiamo avuto errori rate limit, pausa più lunga
            if rateLimitErrors > 0 {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 secondi extra
                rateLimitErrors = 0
            }
        }
        
        print("[ViewModel] ✅ Completato download dettagli: \(allEmails.count)/\(totalMessages) email")
        return allEmails.sorted(by: { $0.date > $1.date })
    }

    private func fetchEmailList(for labelId: String? = nil, accessToken: String, query: String? = nil) async throws -> [GmailMessageInfo] {
        var allMessages: [GmailMessageInfo] = []
        var nextPageToken: String?

        var urlComponents = URLComponents(string: "https://www.googleapis.com/gmail/v1/users/me/messages")!
        
        repeat {
            urlComponents.queryItems = []
            
            // Aggiungi labelId solo se specificato
            if let labelId = labelId {
                urlComponents.queryItems?.append(URLQueryItem(name: "labelIds", value: labelId))
            }
            
            if let q = query {
                urlComponents.queryItems?.append(URLQueryItem(name: "q", value: q))
            }
            if let token = nextPageToken {
                urlComponents.queryItems?.append(URLQueryItem(name: "pageToken", value: token))
            }

            guard let url = urlComponents.url else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8)
                throw GmailAPIError.badServerResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1, responseBody: body)
            }

            let result = try JSONDecoder().decode(GmailMessageList.self, from: data)
            if let messages = result.messages {
                // Convert GmailMessage to GmailMessageInfo
                let messageInfos = messages.compactMap { GmailMessageInfo(id: $0.id, threadId: "") }
                allMessages.append(contentsOf: messageInfos)
            }
            nextPageToken = result.nextPageToken

        } while nextPageToken != nil

        return allMessages
    }

    private func fetchEmailDetails(messageId: String, accessToken: String, metadataOnly: Bool = false) async throws -> Email {
        let format = metadataOnly ? "metadata" : "full"
        let url = URL(string: "https://www.googleapis.com/gmail/v1/users/me/messages/\(messageId)?format=\(format)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GmailAPIError.badServerResponse(statusCode: statusCode, responseBody: body)
        }

        let detail = try JSONDecoder().decode(GmailMessageDetail.self, from: data)
        
        let headers = detail.payload.headers
        
        let senderString = headers.first { $0.name == "From" }?.value ?? "Sconosciuto"
        let sender = EmailAddressParser.parse(addressString: senderString)
        
        let recipientString = headers.first { $0.name == "To" }?.value ?? ""
        let recipients = EmailAddressParser.parse(addressesString: recipientString)
        
        let ccString = headers.first { $0.name == "Cc" }?.value ?? ""
        let cc = ccString.isEmpty ? nil : EmailAddressParser.parse(addressesString: ccString)
        
        let subject = headers.first { $0.name == "Subject" }?.value ?? "Nessun Oggetto"
        
        let date: Date
        if let dateString = headers.first(where: { $0.name == "Date" })?.value,
           let parsedDate = EmailDateParser.date(from: dateString) {
            date = parsedDate
        } else if let internalDate = EmailDateParser.date(fromInternalDate: detail.internalDate) {
            date = internalDate
        } else {
            date = Date()
        }
        
        var body: String? = nil
        var attachments: [EmailAttachment] = []

        if !metadataOnly {
            let parsedResult = parse(payload: detail.payload)
            body = parsedResult.body
            attachments = parsedResult.attachments
        }

        let isRead = !detail.labelIds.contains("UNREAD")
        let isDownloaded = !metadataOnly && body != nil
        
        let email = Email(
            id: detail.id, 
            isRead: isRead, 
            isDownloaded: isDownloaded, 
            sender: sender, 
            recipients: recipients,
            cc: cc,
            subject: subject, 
            date: date, 
            body: body, 
            attachments: attachments,
            claimNumber: extractRiferimentoSinistro(from: subject, body: body) ?? "",
            insuredName: extractNomeAssicurato(from: subject)
        )
        return email
    }
    
    // MARK: - Nuova gestione download
    
    /// Chiamato dal DownloadManager quando un'email è stata scaricata
    func handleDownloadedEmail(emailDetail: GmailMessageDetail) {
        let email = self.convertDetailToEmail(detail: emailDetail)
                
        // Aggiorna sul main thread per sicurezza
        Task { @MainActor in
            // Trova la casella corretta per questa email
            let stats = emailRepository.getStats()
            let targetMailboxId = emailDetail.labelIds.first { labelId in
                // Verifica se la casella esiste in EmailRepository
                stats.emailsPerMailbox.keys.contains(labelId) || 
                emailRepository.getEmails(forMailbox: labelId).count > 0
            } ?? emailDetail.labelIds.first ?? "INBOX"
            
            // Usa EmailRepository per aggiungere/aggiornare con deduplicazione automatica
            let existingEmail = emailRepository.getEmail(byId: email.id)
            let isCompleting = existingEmail != nil && existingEmail?.body == nil && email.body != nil
            let isNew = emailRepository.addOrUpdateEmail(email, forMailbox: targetMailboxId)
            
            if isNew {
                print("[ViewModel] ✨ Aggiunta nuova email \(email.id) alla casella \(targetMailboxId)")
                // Notifica che è arrivata una nuova email
                NotificationCenter.default.post(name: .emailReceived, object: nil, userInfo: ["emailId": email.id])
            } else if isCompleting {
                print("[ViewModel] 📥 Completata email \(email.id) (corpo scaricato) nella casella \(targetMailboxId)")
                } else {
                // Aggiornamento reale (es. stato letto/non letto)
                print("[ViewModel] 🔄 Aggiornata email esistente \(email.id) nella casella \(targetMailboxId)")
            }

            // In ogni caso, aggiorna le caselle visualizzabili per rinfrescare la UI (es. contatori non letti)
            updateDisplayableMailboxes()
            
            // Verifica associazione automatica ora che abbiamo il corpo completo
            // Solo se l'email non è già associata a un thread
            guard !email.id.isEmpty, !email.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("[ViewModel] ⚠️ Email senza ID valido, salto verifica associazione")
                return
            }
            
            let context = PersistenceController.shared.container.viewContext
            // Non possiamo usare CONTAINS su campo Transformable, quindi carichiamo tutti i thread e filtriamo in memoria
            let threadRequest = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
            
            let allThreads: [SinistroEmailThread]
            do {
                allThreads = try context.fetch(threadRequest)
            } catch {
                print("[ViewModel] ❌ Errore fetch thread per email \(email.id): \(error)")
                return
            }
            
            // L'associazione automatica avviene già quando l'email viene processata da MailManager
            // Non serve fare qui - MailManager.processEmail() chiama EmailAssociationService dopo il processamento
            // Questo metodo viene chiamato solo quando l'email viene aggiornata, non durante il processamento iniziale
        }
    }

    /// Funzione di conversione da GmailMessageDetail al modello Email dell'app
    private func convertDetailToEmail(detail: GmailMessageDetail) -> Email {
        let headers = detail.payload.headers
        let senderString = headers.first { $0.name == "From" }?.value ?? "Sconosciuto"
        let sender = EmailAddressParser.parse(addressString: senderString)
        let recipientString = headers.first { $0.name == "To" }?.value ?? ""
        let recipients = EmailAddressParser.parse(addressesString: recipientString)
        let subject = headers.first { $0.name == "Subject" }?.value ?? "Nessun Oggetto"
        
        let date: Date
        if let dateString = headers.first(where: { $0.name == "Date" })?.value,
           let parsedDate = EmailDateParser.date(from: dateString) {
            date = parsedDate
        } else if let internalDate = EmailDateParser.date(fromInternalDate: detail.internalDate) {
            date = internalDate
        } else {
            date = Date()
        }
        
        let parsedResult = parse(payload: detail.payload)
        let body = parsedResult.body
        let attachments = parsedResult.attachments
        
        let isRead = !detail.labelIds.contains("UNREAD")
        
        return Email(
            id: detail.id, 
            isRead: isRead, 
            isDownloaded: true, 
            sender: sender, 
            recipients: recipients, 
            subject: subject, 
            date: date, 
            body: body, 
            attachments: attachments,
            claimNumber: extractRiferimentoSinistro(from: subject, body: body) ?? "",
            insuredName: extractNomeAssicurato(from: subject)
        )
    }
    
    // MARK: - Funzioni di Fetch (da aggiornare)
    
    // fetchLabels, fetchAllEmails etc. andrebbero modificate per usare il GmailService
    // Per ora ci concentriamo sulla logica di download

    // --- Funzione per caricare il corpo di una specifica email ---
    func fetchFullEmail(for emailId: String) async {
        // 1. Controlla se è già scaricata
        if isEmailDownloaded(emailId) { 
            print("[ViewModel] Email \(emailId) già scaricata")
            return 
        }
        
        // 2. Usa MailManager per scaricare e processare l'email
        // forceDownload=true perché l'utente vuole visualizzare l'email
        let context = PersistenceController.shared.container.viewContext
        do {
            if let email = try await mailManager.fetchFullEmail(emailId: emailId, context: context, forceDownload: true) {
                // 3. Aggiorna le caselle visualizzabili
                await MainActor.run {
                    updateDisplayableMailboxes()
                }
            }
        } catch {
            print("[MailViewModel] ⚠️ Errore download email \(emailId): \(error)")
        }
    }
    
    private func updateEmailInLists(with email: Email) {
        // Trova la casella dell'email
        let mailboxId = findMailboxForEmail(emailId: email.id) ?? "INBOX"
        emailRepository.addOrUpdateEmail(email, forMailbox: mailboxId)
    }
    
    private func parse(payload: MessagePayloadDetail) -> (body: String, attachments: [EmailAttachment]) {
        var attachments: [EmailAttachment] = []
        var htmlBody: String?
        var plainBody: String?

        func traverse(parts: [MessagePartDetail]) {
            for part in parts {
                if !part.filename.isEmpty, let attachmentId = part.body.attachmentId {
                    attachments.append(EmailAttachment(attachmentId: attachmentId, filename: part.filename, size: part.body.size))
                }
                
                if part.mimeType == "text/plain", let data = part.body.data {
                    plainBody = decode(base64url: data)
                }
                
                if part.mimeType == "text/html", let data = part.body.data {
                    htmlBody = decode(base64url: data)
                }

                if let subParts = part.parts {
                    traverse(parts: subParts)
                }
            }
        }
        
        if let parts = payload.parts {
            traverse(parts: parts)
        } else if let bodyData = payload.body?.data {
            plainBody = decode(base64url: bodyData)
        }
        
        var body = htmlBody ?? plainBody ?? "Corpo del messaggio non disponibile."
        
        if !attachments.isEmpty {
            let attachmentHTML = attachments.map { attachment in
                let formattedSize = ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file)
                return """
                <div style="border: 1px solid #e0e0e0; border-radius: 8px; padding: 10px; margin-top: 20px; display: inline-block;">
                    <strong>Allegato:</strong> \(attachment.filename) (\(formattedSize))
                </div>
                """
            }.joined(separator: "")
            
            body.append("<hr>\(attachmentHTML)")
        }
        
        return (body, attachments)
    }
    
    private func decode(base64url: String) -> String {
        let base64 = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: base64) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    // MARK: - Attachment Handling
    
    func downloadAndOpen(attachment: EmailAttachment, messageId: String) async throws {
        guard let accessToken = try? await authService.getAccessToken() else {
            throw URLError(.userAuthenticationRequired)
        }

        let url = URL(string: "https://www.googleapis.com/gmail/v1/users/me/messages/\(messageId)/attachments/\(attachment.attachmentId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let attachmentData = try JSONDecoder().decode(MessageAttachmentData.self, from: data)
        let fileData = Data(base64Encoded: attachmentData.data.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"))
        
        guard let fileData = fileData else {
            throw URLError(.cannotDecodeContentData)
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(attachment.filename)
        try fileData.write(to: tempURL)
        
        DispatchQueue.main.async {
            NSWorkspace.shared.open(tempURL)
        }
    }
    
    // MARK: - Email Actions

    func markEmailAsRead(emailId: String) {
        if let email = emailRepository.getEmail(byId: emailId), !email.isRead {
            // Trova la casella dell'email
            let mailboxId = findMailboxForEmail(emailId: emailId) ?? "INBOX"
            
            var updatedEmail = email
            updatedEmail.isRead = true
            emailRepository.addOrUpdateEmail(updatedEmail, forMailbox: mailboxId)
            
            Task {
                if email.body == nil {
                    await fetchFullEmail(for: emailId)
                }
                await modifyEmailLabels(messageId: emailId, labelsToRemove: ["UNREAD"])
            }
        }
    }
    
    /// Trova la casella per un'email
    private func findMailboxForEmail(emailId: String) -> String? {
        for mailboxId in emailRepository.emailsByMailbox.keys {
            if emailRepository.getEmails(forMailbox: mailboxId).contains(where: { $0.id == emailId }) {
                return mailboxId
            }
        }
        return nil
    }

    func toggleReadStatus(for emailId: String) {
        guard let email = emailRepository.getEmail(byId: emailId) else { return }
        
        let mailboxId = findMailboxForEmail(emailId: emailId) ?? "INBOX"
        
        var updatedEmail = email
        updatedEmail.isRead = !email.isRead
        emailRepository.addOrUpdateEmail(updatedEmail, forMailbox: mailboxId)

        Task {
            if updatedEmail.isRead {
                await modifyEmailLabels(messageId: emailId, labelsToRemove: ["UNREAD"])
            } else {
                await modifyEmailLabels(messageId: emailId, labelsToAdd: ["UNREAD"])
            }
        }
    }
    
    /// Trova un'email e la sua casella tramite ID
    private func findEmail(withId emailId: String) -> (mailboxId: String, index: Int)? {
        // Cerca in tutte le caselle usando EmailRepository
        let stats = emailRepository.getStats()
        for mailboxId in stats.emailsPerMailbox.keys {
            let emails = emailRepository.getEmails(forMailbox: mailboxId)
            if let index = emails.firstIndex(where: { $0.id == emailId }) {
                return (mailboxId, index)
            }
        }
        return nil
    }

    private func modifyEmailLabels(messageId: String, labelsToAdd: [String] = [], labelsToRemove: [String] = []) async {
        guard let accessToken = try? await authService.getAccessToken() else { return }

        let url = URL(string: "https://www.googleapis.com/gmail/v1/users/me/messages/\(messageId)/modify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "addLabelIds": labelsToAdd,
            "removeLabelIds": labelsToRemove
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                print("Errore nella modifica delle etichette per il messaggio \(messageId)")
                return
            }
            
            // Aggiorna la UI
            await MainActor.run {
                self.updateDisplayableMailboxes()
            }
            
        } catch {
            print("Errore nella modifica delle etichette: \(error.localizedDescription)")
        }
    }

    /// Si assicura che esista una personalizzazione per ogni etichetta scaricata.
    private func ensureCustomizationsExist() {
        var needsSave = false
        for label in labels {
            if customizations[label.id] == nil {
                customizations[label.id] = MailboxCustomization(
                    id: label.id,
                    iconName: MailboxCustomizationService.defaultIcon(for: label.id),
                    isVisible: !["SPAM", "TRASH"].contains(label.id), // Nascondi spam e cestino di default
                    showUnreadCount: true // Mostra il contatore di default
                )
                needsSave = true
            }
        }
        if needsSave {
            customizationService.saveCustomizations(customizations)
        }
    }
    
    /// Aggiorna l'array 'displayableMailboxes' che viene usato dalla UI.
    @MainActor
    private func updateDisplayableMailboxes() {
        var mailboxes: [DisplayableMailbox] = []
        
        // 1. Aggiungi la casella "Principale"
        mailboxes.append(DisplayableMailbox(
            id: "PRINCIPALE",
            name: "Principale",
            iconName: MailboxCustomizationService.defaultIcon(for: "PRINCIPALE"),
            isVisible: true,
            unreadCount: 0, // La logica dei thread verrà aggiunta in seguito
            showUnreadCount: true
        ))
        
        // 2. Aggiungi le etichette di Gmail
        for label in labels.sorted(by: { $0.name < $1.name }) {
            // Usa la personalizzazione salvata o crea una default al volo (non dovrebbe succedere)
            let custom = customizations[label.id] ?? MailboxCustomization(id: label.id, iconName: MailboxCustomizationService.defaultIcon(for: label.id), isVisible: true, showUnreadCount: true)
            
            let mailbox = DisplayableMailbox(
                id: label.id,
                name: label.name,
                iconName: custom.iconName,
                isVisible: custom.isVisible,
                unreadCount: unreadCount(for: label.id),
                showUnreadCount: custom.showUnreadCount
            )
            mailboxes.append(mailbox)
        }
        
        // Aggiorna sul main thread
        self.displayableMailboxes = mailboxes
        // Non stampiamo ogni volta per evitare spam nei log
    }

    /// Calcola il numero di email non lette per una data casella.
    private func unreadCount(for mailboxId: String) -> Int {
        return emailRepository.getEmails(forMailbox: mailboxId).filter { !$0.isRead }.count
    }

    /// Fa il merge di una nuova lista di messaggi con una lista esistente di email, preservando i corpi già scaricati.
    private func merge(newMessages: [GmailMessageInfo], with existingEmails: [Email], accessToken: String) async -> [Email] {
        let existingEmailsDict = Dictionary(uniqueKeysWithValues: existingEmails.map { ($0.id, $0) })
        
        // Scarica i metadati solo per i messaggi che non abbiamo già
        let messagesToFetch = newMessages.filter { existingEmailsDict[$0.id] == nil }

        var updatedEmails = existingEmails
        
        if !messagesToFetch.isEmpty {
            let newlyFetchedEmails = await fetchDetails(for: messagesToFetch, accessToken: accessToken)
            updatedEmails.append(contentsOf: newlyFetchedEmails)
        }
        
        // Qui si potrebbe aggiungere una logica per aggiornare lo stato (es. letto/non letto)
        // dei messaggi esistenti, se l'API fornisse questa informazione nella lista.
        
        return updatedEmails.sorted(by: { $0.date > $1.date })
    }

    /// Aggiorna una singola personalizzazione e salva tutto.
    func updateCustomization(for mailboxId: String, isVisible: Bool? = nil, iconName: String? = nil, showUnreadCount: Bool? = nil) {
        guard var custom = customizations[mailboxId] else { return }
        
        var needsUpdate = false
        if let isVisible = isVisible {
            custom.isVisible = isVisible
            needsUpdate = true
        }
        if let iconName = iconName, !iconName.isEmpty {
            custom.iconName = iconName
            needsUpdate = true
        }
        if let showUnreadCount = showUnreadCount {
            custom.showUnreadCount = showUnreadCount
            needsUpdate = true
        }
        
        if needsUpdate {
            customizations[mailboxId] = custom
            customizationService.saveCustomizations(customizations)
            self.updateDisplayableMailboxes()
        }
    }

    /// Verifica se una mail è già stata scaricata
    func isEmailDownloaded(_ emailId: String) -> Bool {
        // Controlla prima in EmailRepository
        if let email = emailRepository.getEmail(byId: emailId) {
            return email.isDownloaded ?? false
        }
        return false
    }

    // Aggiungo una funzione per convertire 'GmailMessageInfo' in 'GmailMessage'.
    private func convertToGmailMessage(info: GmailMessageInfo) -> GmailMessage {
        // Supponiamo che 'GmailMessage' richieda solo l'id e il payload, che possiamo impostare come nil o un valore predefinito.
        return GmailMessage(id: info.id, payload: nil)
    }

    private func extractRiferimentoSinistro(from testo: String, body: String? = nil) -> String? {
        let pattern = #"\b([0-9]{7})\b"# // 7 cifre consecutive, delimitato da word boundaries
        
        // Prima cerca nell'oggetto
        if let riferimento = trovaPattern(pattern, in: testo) {
            if isValidRiferimentoInterno(riferimento) {
                return riferimento
            }
        }
        
        // Se non trovato nell'oggetto e abbiamo il corpo, cerca nel corpo
        if let corpo = body, !corpo.isEmpty {
            if let riferimento = trovaPattern(pattern, in: corpo) {
                if isValidRiferimentoInterno(riferimento) {
                    return riferimento
                }
            }
        }
        
        return nil
    }
    
    private func extractNomeAssicurato(from subject: String) -> String? {
        // Cerca il nome assicurato nel formato standard: "Assicurato [nome]"
        let pattern = #"Assicurato\s+([A-Za-z\s]+?)(?:\s+-\s+|$)"#
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: subject.utf16.count)
            if let match = regex.firstMatch(in: subject, range: range) {
                let matchRange = match.range(at: 1)
                if matchRange.location != NSNotFound {
                    let nome = (subject as NSString).substring(with: matchRange)
                    return nome.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        return nil
    }
    
    /// Estrae il riferimento interno dello studio (7 cifre: 2 anno + 5 progressive)
    /// Cerca prima nell'oggetto, poi nel corpo se fornito
    private func estraiRiferimentoInterno(da testo: String, corpo: String? = nil) -> String? {
        let pattern = #"\b([0-9]{7})\b"# // 7 cifre consecutive, delimitato da word boundaries
        
        // Prima cerca nell'oggetto
        if let riferimento = trovaPattern(pattern, in: testo) {
            if isValidRiferimentoInterno(riferimento) {
                return riferimento
            }
        }
        
        // Se non trovato nell'oggetto e abbiamo il corpo, cerca nel corpo
        if let corpo = corpo, !corpo.isEmpty {
            if let riferimento = trovaPattern(pattern, in: corpo) {
                if isValidRiferimentoInterno(riferimento) {
                    return riferimento
                }
            }
        }
        
        return nil
    }
    
    /// Estrae TUTTI i riferimenti interni presenti nel testo (per gestire multi-tag)
    private func estraiTuttiRiferimentiInterni(da oggetto: String, corpo: String? = nil) -> [String] {
        var riferimenti: [String] = []
        let pattern = #"\b([0-9]{7})\b"#
        
        // Cerca nell'oggetto
        riferimenti.append(contentsOf: trovaTuttiPattern(pattern, in: oggetto).filter { isValidRiferimentoInterno($0) })
        
        // Cerca nel corpo se disponibile
        if let corpo = corpo, !corpo.isEmpty {
            riferimenti.append(contentsOf: trovaTuttiPattern(pattern, in: corpo).filter { isValidRiferimentoInterno($0) })
        }
        
        // Rimuovi duplicati mantenendo l'ordine
        return Array(NSOrderedSet(array: riferimenti)) as! [String]
    }
    
    /// Verifica se un numero di 7 cifre è un valido riferimento interno
    private func isValidRiferimentoInterno(_ riferimento: String) -> Bool {
        guard riferimento.count == 7, riferimento.allSatisfy({ $0.isNumber }) else {
            return false
        }
        
        // Estrae l'anno (prime 2 cifre)
        let annoString = String(riferimento.prefix(2))
        guard let anno = Int(annoString) else { return false }
        
        // Verifica che l'anno sia ragionevole (es. dal 2020 al 2030)
        // 20 = 2020, 21 = 2021, ..., 30 = 2030
        return anno >= 20 && anno <= 30
    }
    
    /// Trova il primo match di un pattern regex
    private func trovaPattern(_ pattern: String, in testo: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(location: 0, length: testo.utf16.count)
        if let match = regex.firstMatch(in: testo, range: range) {
            let matchRange = match.range(at: 1)
            if matchRange.location != NSNotFound {
                return (testo as NSString).substring(with: matchRange)
            }
        }
        
        return nil
    }
    
    /// Trova tutti i match di un pattern regex
    private func trovaTuttiPattern(_ pattern: String, in testo: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        
        let range = NSRange(location: 0, length: testo.utf16.count)
        let matches = regex.matches(in: testo, range: range)
        
        return matches.compactMap { match in
            let matchRange = match.range(at: 1)
            if matchRange.location != NSNotFound {
                return (testo as NSString).substring(with: matchRange)
            }
            return nil
        }
    }

    // MARK: - Funzioni per estrazione riferimenti (pubbliche per uso nei ViewModels)
    
    /// Estrae tutti i riferimenti interni presenti nell'email (per multi-tag)
    func extractAllRiferimenti(from email: Email) -> [String] {
        return estraiTuttiRiferimentiInterni(da: email.subject, corpo: email.body)
    }
    
    /// Estrae il primo riferimento interno dall'email
    func extractPrimaryRiferimento(from email: Email) -> String? {
        return extractRiferimentoSinistro(from: email.subject, body: email.body)
    }
    
    // MARK: - Funzioni private per estrazione

    // MARK: - Indicizzazione Periodica Sinistri
    
    /// Avvia l'indicizzazione periodica di tutti i sinistri (solo ID email, senza scaricare contenuto)
    /// DEPRECATO: Non più necessario - l'associazione avviene automaticamente quando le email vengono processate
    @available(*, deprecated, message: "L'associazione email-sinistro avviene automaticamente quando le email vengono processate")
    private func startPeriodicSinistroIndexing(interval: TimeInterval = 1800) { // 30 minuti
        print("[ViewModel] ⚠️ DEPRECATO: startPeriodicSinistroIndexing chiamato - non necessario")
        // Non fare nulla - l'associazione avviene automaticamente quando le email vengono processate
    }
    
    /// Indicizza le email per tutti i sinistri (solo ID, senza scaricare contenuto)
    /// Include tutti i sinistri, anche quelli chiusi
    /// Se forceRefresh è true, rigenera tutti i thread anche se esistono già
    func indexAllSinistri(forceRefresh: Bool = false) async {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        
        // Include tutti i sinistri, anche quelli chiusi
        // Nessun filtro per stato
        
        do {
            let sinistri = try context.fetch(request)
            print("[ViewModel] 📋 Indicizzazione di \(sinistri.count) sinistri (inclusi chiusi/revocati)...")
            
            // Processa tutti i sinistri (anche quelli con thread esistenti, per aggiornarli)
            var sinistriDaProcessare: [Sinistro] = []
            
            if forceRefresh {
                // Se forceRefresh è true, processa tutti i sinistri
                sinistriDaProcessare = sinistri
                print("[ViewModel] 🔄 Force refresh: rigenererò tutti i \(sinistri.count) sinistri")
            } else {
                // Comportamento normale: processa solo sinistri senza thread o con thread vecchi
                for sinistro in sinistri {
                    // Verifica se esiste già un thread per questo sinistro
                    let threadRequest = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
                    threadRequest.predicate = NSPredicate(format: "sinistro == %@", sinistro)
                    threadRequest.fetchLimit = 1
                    
                    let existingThreads = (try? context.fetch(threadRequest)) ?? []
                    
                    // Aggiungi alla lista se non esiste un thread o se il thread è vecchio (più di 24 ore)
                    if existingThreads.isEmpty {
                        sinistriDaProcessare.append(sinistro)
                    } else if let existingThread = existingThreads.first {
                        // Forza aggiornamento se il thread è più vecchio di 24 ore
                        let lastModification = existingThread.dataUltimaModifica ?? Date.distantPast
                        if Date().timeIntervalSince(lastModification) >= 24 * 60 * 60 {
                            sinistriDaProcessare.append(sinistro)
                        }
                    }
                }
            }
            
            print("[ViewModel] 📋 \(sinistriDaProcessare.count) sinistri necessitano indicizzazione (su \(sinistri.count) totali)")
            
            // DEPRECATO: Non più necessario fare ricerche su Gmail
            // L'associazione email-sinistro avviene automaticamente quando le email vengono processate
            // usando pattern matching su email già scaricate
            print("[ViewModel] ⚠️ Indicizzazione disabilitata - associazione automatica attiva")
            print("[ViewModel] ✅ Le email vengono associate automaticamente quando processate (pattern matching)")
        } catch {
            print("[ViewModel] ❌ Errore indicizzazione sinistri: \(error)")
        }
    }

    // MARK: - Nuovi metodi per il sistema di download intelligente
    
    /// Ottiene le email degli ultimi N giorni non ancora scaricate
    func getRecentUndownloadedEmails(since date: Date) -> [Email] {
        var recentEmails: [Email] = []
        
        for (_, emails) in emailsByMailbox {
            let filtered = emails.filter { email in
                email.date > date && !(email.isDownloaded ?? false)
            }
            recentEmails.append(contentsOf: filtered)
        }
        
        return recentEmails.sorted { $0.date > $1.date }
    }
    
    /// Controlla se ci sono nuove email dal server (chiamato periodicamente)
    func checkForNewEmails() async {
        guard let accessToken = try? await authService.getAccessToken() else {
            return // Non stampiamo errori per il periodic check
        }
        
        do {
            // Controlla solo la casella INBOX per nuove email
            let messages = try await fetchEmailList(for: "INBOX", accessToken: accessToken, query: nil)
            let existingEmails = emailRepository.getEmails(forMailbox: "INBOX")
            let existingIds = Set(existingEmails.map { $0.id })
            let newMessages = messages.filter { !existingIds.contains($0.id) }
            
            if !newMessages.isEmpty {
                print("[ViewModel] 📧 Controllo periodico: \(newMessages.count) nuove email in INBOX")
                
                // Scarica i metadati delle nuove email
                let newEmails = await fetchDetails(for: newMessages, accessToken: accessToken)
                
                // Aggiungile alla casella INBOX con deduplicazione automatica
                let result = await MainActor.run {
                    let result = emailRepository.addEmails(newEmails, forMailbox: "INBOX")
                    if result.added > 0 {
                        print("[ViewModel] 🔍 Deduplicazione periodica: \(result.added) nuove, \(result.updated) aggiornate")
                        // Notifica che sono arrivate nuove email
                        NotificationCenter.default.post(name: .emailReceived, object: nil, userInfo: ["count": result.added])
                    }
                    
                    // Aggiorna la UI
                    updateDisplayableMailboxes()
                    
                    // Salva nella cache
                    emailRepository.saveToCache()
                    
                    return result
                }
                
                // Processa le nuove email con gli handler (solo quelle aggiunte, non aggiornate)
                if result.added > 0 {
                    print("[ViewModel] 🔄 Processamento \(result.added) nuove email con handler...")
                    let context = PersistenceController.shared.container.viewContext
                    // Processa tutte le newEmails - MailManager salterà quelle già processate
                    await MailManager.shared.processEmails(newEmails, context: context)
                    print("[ViewModel] ✅ Processate nuove email")
                }
            }
            // Non stampiamo nulla se non ci sono nuove email per evitare spam nei log
        } catch {
            print("[ViewModel] ⚠️ Errore nel controllo periodico nuove email: \(error.localizedDescription)")
        }
    }
    
    /// Avvia il sistema di download automatico
    func startAutomaticDownload() {
        Task {
            await mailManager.startMonitoring()
        }
    }
    
    /// Ottieni statistiche del mail manager
    func getDownloadStats() async -> (requested: Int, completed: Int, failed: Int, rate: Double) {
        let stats = await MainActor.run {
            mailManager.classificationStats
        }
        return (
            requested: stats.totalProcessed,
            completed: stats.totalProcessed,
            failed: 0,
            rate: 1.0
        )
    }
    
    // MARK: - Associazione Email-Sinistro
    
    /// Struttura per il formato standard delle email
    private struct StandardEmailFormat {
        let tipo: String?
        let numeroAgenzia: String? // Senza separatori
        let nomeAssicurato: String?
        let riferimentoInterno: String?
    }
    
    /// Estrae il formato standard: [tipo] - sinistro n. [numero] - Assicurato [nome] - ns. rif. [rif]
    private func extractStandardFormat(from subject: String, body: String?) -> StandardEmailFormat? {
        let text = "\(subject) \(body ?? "")"
        
        // Pattern più flessibile per formato standard
        // Supporta varianti: [tipo opzionale] - sinistro n[°.] [numero] - Assicurato [nome] - ns[.] rif[.] [riferimento 7 cifre]
        let patterns = [
            // Con tipo: [tipo] - sinistro n. [numero] - Assicurato [nome] - ns. rif. [rif]
            #"([^-]+?)\s*-\s*sinistro\s+n[°.]?\s*([0-9A-Z]+)\s*-\s*[Aa]ssicurato\s+([^-]+?)\s*-\s*ns[.]?\s*rif[.]?\s*([0-9]{7})"#,
            // Senza tipo: sinistro n. [numero] - Assicurato [nome] - ns. rif. [rif]
            #"sinistro\s+n[°.]?\s*([0-9A-Z]+)\s*-\s*[Aa]ssicurato\s+([^-]+?)\s*-\s*ns[.]?\s*rif[.]?\s*([0-9]{7})"#
        ]
        
        for (index, pattern) in patterns.enumerated() {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: text.utf16.count)
                if let match = regex.firstMatch(in: text, range: range) {
                    let tipo: String?
                    let numero: String?
                    let nome: String?
                    let riferimento: String?
                    
                    if index == 0 {
                        // Pattern con tipo
                        tipo = match.range(at: 1).location != NSNotFound ? 
                            (text as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines) : nil
                        numero = match.range(at: 2).location != NSNotFound ? 
                            (text as NSString).substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines) : nil
                        nome = match.range(at: 3).location != NSNotFound ? 
                            (text as NSString).substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines) : nil
                        riferimento = match.range(at: 4).location != NSNotFound ? 
                            (text as NSString).substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespacesAndNewlines) : nil
                    } else {
                        // Pattern senza tipo
                        tipo = nil
                        numero = match.range(at: 1).location != NSNotFound ? 
                            (text as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines) : nil
                        nome = match.range(at: 2).location != NSNotFound ? 
                            (text as NSString).substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines) : nil
                        riferimento = match.range(at: 3).location != NSNotFound ? 
                            (text as NSString).substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines) : nil
                    }
                    
                    // Valida che almeno numero o riferimento siano presenti
                    if (numero != nil && !numero!.isEmpty) || (riferimento != nil && riferimento!.count == 7) {
                        return StandardEmailFormat(
                            tipo: tipo,
                            numeroAgenzia: numero,
                            nomeAssicurato: nome,
                            riferimentoInterno: riferimento
                        )
                    }
                }
            }
        }
        
        return nil
    }
    
    /// DEPRECATO: Usa EmailAssociationService.shared.checkEmailAssociation invece
    @available(*, deprecated, message: "Usa EmailAssociationService.shared.checkEmailAssociation")
    @MainActor
    func checkEmailAssociation(_ email: Email, context: NSManagedObjectContext) -> [Sinistro] {
        return EmailAssociationService.shared.checkEmailAssociation(email, context: context)
    }
    
    /// Genera suggerimenti per associazione manuale (match parziali, nome, email)
    /// Eseguito in background senza bloccare l'UI
    func generateAssociationSuggestions(
        for email: Email,
        context: NSManagedObjectContext
    ) async -> [Sinistro] {
        return await Task.detached(priority: .utility) { [email, weak self] in
            guard let self = self else { return [] }
            var suggestions: [(Sinistro, Double)] = []
            let disassociationService = EmailDisassociationService.shared
            
            // Estrai dati dall'email (chiamate MainActor)
            let nomeAssicurato = await MainActor.run { [weak self] in
                self?.extractNomeAssicurato(from: email.subject)
            }
            var emailsToCheck: [String] = [email.sender.email.lowercased()]
            emailsToCheck.append(contentsOf: email.recipients.map { $0.email.lowercased() })
            if let cc = email.cc {
                emailsToCheck.append(contentsOf: cc.map { $0.email.lowercased() })
            }
            
            // Fetch sinistri (con cancellazione se necessario)
            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            guard let allSinistri = try? context.fetch(request) else {
                return []
            }
            
            for (index, sinistro) in allSinistri.enumerated() {
                // Verifica cancellazione ogni 100 sinistri
                if index % 100 == 0 && Task.isCancelled {
                    break
                }
                
                // Salta disassociati
                let sinistroId = sinistro.objectID.uriRepresentation().absoluteString
                if disassociationService.isDisassociated(emailId: email.id, sinistroId: sinistroId) {
                    continue
                }
                
                var score = 0.0
                
                // Match per nome assicurato (match parziale)
                if let nome = nomeAssicurato, !nome.isEmpty {
                    let sinistroNome = (sinistro.nomeAssicurato ?? "").lowercased()
                    let emailNome = nome.lowercased()
                    if sinistroNome.contains(emailNome) || emailNome.contains(sinistroNome) {
                        score += 0.5
                    }
                }
                
                // Match per email assicurato
                var sinistroEmails: [String] = []
                if let emailAssicurato = sinistro.emailAssicurato?.lowercased(), !emailAssicurato.isEmpty {
                    sinistroEmails.append(emailAssicurato)
                }
                if let emailContraente = sinistro.emailContraente?.lowercased(), !emailContraente.isEmpty {
                    sinistroEmails.append(emailContraente)
                }
                if let emailDanneggiato = sinistro.emailDanneggiato?.lowercased(), !emailDanneggiato.isEmpty {
                    sinistroEmails.append(emailDanneggiato)
                }
                sinistroEmails.append(contentsOf: sinistro.emailAssicuratoArray.map { $0.lowercased() })
                
                for emailToCheck in emailsToCheck {
                    if sinistroEmails.contains(emailToCheck) {
                        score += 0.3
                        break
                    }
                }
                
                // Match parziale per numero compagnia (se presente ma non esatto)
                let patterns = await MainActor.run {
                    EmailPatternMatcher.shared.extractPatterns(subject: email.subject, body: email.body ?? "")
                }
                if let numero = patterns.numeroAgenzia,
                   let sinistroNumero = sinistro.numeroSinistroCompagnia,
                   !sinistroNumero.isEmpty {
                    let patternMatcher = EmailPatternMatcher.shared
                    let normalizedNumero = patternMatcher.normalizeNumber(numero)
                    let normalizedSinistroNumero = patternMatcher.normalizeNumber(sinistroNumero)
                    
                    // Match parziale (contiene)
                    if normalizedSinistroNumero.contains(normalizedNumero) || normalizedNumero.contains(normalizedSinistroNumero) {
                        score += 0.2
                    }
                }
                
                // Aggiungi se ha un punteggio minimo
                if score >= 0.3 {
                    suggestions.append((sinistro, score))
                }
                
                // Throttling ogni 100 sinistri per non bloccare
                if index % 100 == 0 && index > 0 {
                    try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
                }
            }
            
            // Ordina per score (decrescente) e restituisci solo i sinistri
            return suggestions.sorted { $0.1 > $1.1 }.map { $0.0 }
        }.value
    }
    
    /// DEPRECATO: Usa EmailAssociationService.shared.associateEmailToSinistri invece
    /// Associa un'email a uno o più sinistri
    @available(*, deprecated, message: "Usa EmailAssociationService.shared.associateEmailToSinistri")
    @MainActor
    func associateEmailToSinistri(_ email: Email, sinistri: [Sinistro], context: NSManagedObjectContext) async {
        await EmailAssociationService.shared.associateEmailToSinistri(email, sinistri: sinistri, context: context)
    }
    
    /// Riesegue l'associazione automatica su tutte le email esistenti
    /// Utile per correggere associazioni mancanti o errate
    @MainActor
    func recheckAllEmailAssociations(context: NSManagedObjectContext) async {
        print("[ViewModel] 🔍 Avvio riesame associazioni email...")
        
        let allEmails = emailRepository.getAllEmails()
        let threadCustomizationService = ThreadCustomizationService.shared
        var processed = 0
        var associated = 0
        var skipped = 0
        
        // Verifica quali email sono già associate
        let threadRequest = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        let allThreads = (try? context.fetch(threadRequest)) ?? []
        let associatedEmailIds = Set(allThreads.flatMap { $0.messageIds })
        
        for email in allEmails {
            // Salta email escluse
            if threadCustomizationService.isEmailExcluded(emailId: email.id) {
                skipped += 1
                continue
            }
            
            // Salta email già associate
            if associatedEmailIds.contains(email.id) {
                skipped += 1
                continue
            }
            
            // Verifica se può essere associata automaticamente
            let wasAssociated = await EmailAssociationService.shared.tryAutomaticAssociation(email, context: context)
            if wasAssociated {
                associated += 1
            }
            
            processed += 1
            
            // Log progresso ogni 100 email
            if processed % 100 == 0 {
                print("[ViewModel] Progresso: \(processed) email processate, \(associated) associate, \(skipped) saltate")
            }
            
            // Piccola pausa per non sovraccaricare
            if processed % 50 == 0 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 secondi
            }
        }
        
        print("[ViewModel] ✅ Riesame completato: \(processed) email processate, \(associated) associate automaticamente, \(skipped) saltate")
    }
    
    // MARK: - Apple Intelligence - Riassunti Email
    
    /// Genera un riassunto intelligente per un'email usando AIManager
    func generateEmailSummary(for email: Email) async -> String? {
        // Controlla la cache
        if let cachedSummary = emailSummaries[email.id] {
            return cachedSummary
        }
        
        guard let body = email.body, !body.isEmpty else {
            return nil
        }
        
        // Pulisci il body rimuovendo firme e disclaimer
        let (mainBody, _) = EmailHelpers.extractQuote(from: body)
        let cleanBody = EmailHelpers.cleanHTMLBody(mainBody)
        let bodyWithoutSignature = EmailHelpers.removeSignatureAndDisclaimer(from: cleanBody)
        
        // Usa AIManager con priorità primaria per email visibili
        let task = AITask.emailSummary(
            subject: email.subject,
            body: bodyWithoutSignature,
            priority: .primary
        )
        
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                AIManager.shared.enqueue(task) { (result: AIResult) in
                    if result.success, let summary = result.result?.value as? String {
                        self.emailSummaries[email.id] = summary
                        continuation.resume(returning: summary)
                    } else {
                        // Fallback al metodo diretto se il manager fallisce
                        Task {
                            let summary = await self.aiService.summarizeEmail(subject: email.subject, body: body)
                            if let summary = summary {
                                self.emailSummaries[email.id] = summary
                            }
                            continuation.resume(returning: summary)
                        }
                    }
                }
            }
        }
    }
    
    /// Estrae informazioni strutturate da un'email usando Apple Intelligence
    func extractEmailInfo(for email: Email) async -> EmailExtractedInfo? {
        guard let body = email.body, !body.isEmpty else {
            return nil
        }
        
        return await aiService.extractEmailInfo(from: body)
    }
    
    /// Genera un riassunto intelligente per una conversazione (thread) usando AIManager
    func generateThreadSummary(for emails: [Email]) async -> String? {
        guard !emails.isEmpty else {
            return nil
        }
        
        // Combina tutte le email in un'unica conversazione
        var conversationText = ""
        var subjects: Set<String> = []
        
        // Ordina le email per data (più vecchie prima)
        let sortedEmails = emails.sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
        
        for email in sortedEmails {
            if !subjects.contains(email.subject) {
                subjects.insert(email.subject)
            }
            
            // Escludi email di assegnazione dal riassunto (ma le mostriamo comunque nel thread)
            let isAssignmentEmail = email.sender.email.lowercased() == "info@actsrl.it" &&
                                   email.subject.lowercased().contains("assegnazione perito")
            
            if isAssignmentEmail {
                // Salta questa email dal riassunto
                continue
            }
            
            // Aggiungi header email
            conversationText += "\n\n--- Email da \(email.sender.displayName) ---\n"
            if !email.subject.isEmpty {
                conversationText += "Oggetto: \(email.subject)\n"
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            conversationText += "Data: \(formatter.string(from: email.date))\n"
            
            // Aggiungi body (pulito)
            if let body = email.body, !body.isEmpty {
                // Pulisci il body HTML
                var cleanBody = body
                // Rimuovi tag HTML
                cleanBody = cleanBody.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                cleanBody = cleanBody.replacingOccurrences(of: "&nbsp;", with: " ")
                cleanBody = cleanBody.replacingOccurrences(of: "&amp;", with: "&")
                cleanBody = cleanBody.replacingOccurrences(of: "&lt;", with: "<")
                cleanBody = cleanBody.replacingOccurrences(of: "&gt;", with: ">")
                cleanBody = cleanBody.replacingOccurrences(of: "&quot;", with: "\"")
                cleanBody = cleanBody.replacingOccurrences(of: "\r\n", with: " ")
                cleanBody = cleanBody.replacingOccurrences(of: "\n", with: " ")
                cleanBody = cleanBody.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                cleanBody = cleanBody.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Rimuovi firme e disclaimer prima di aggiungere al contesto
                let withoutSignature = EmailHelpers.removeSignatureAndDisclaimer(from: cleanBody)
                conversationText += withoutSignature
            }
        }
        
        // Usa l'oggetto più comune o il primo
        let mainSubject = subjects.first ?? "Conversazione"
        
        // Usa AIManager per generare il riassunto
        let task = AITask.emailSummary(
            subject: mainSubject,
            body: conversationText,
            priority: .secondary
        )
        
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                AIManager.shared.enqueue(task) { (result: AIResult) in
                    if result.success, let summary = result.result?.value as? String {
                        continuation.resume(returning: summary)
                    } else {
                        // Fallback: genera un riassunto semplice
                        let fallbackSummary = self.generateSimpleThreadSummary(from: sortedEmails)
                        continuation.resume(returning: fallbackSummary)
                    }
                }
            }
        }
    }
    
    /// Genera un riassunto semplice del thread senza AI
    private func generateSimpleThreadSummary(from emails: [Email]) -> String? {
        guard !emails.isEmpty else { return nil }
        
        let count = emails.count
        let senders = Set(emails.map { $0.sender.displayName })
        
        if count == 1 {
            return "1 email da \(senders.first ?? "sconosciuto")"
        } else {
            return "\(count) email tra \(senders.count) interlocutori"
        }
    }
    
    /// Genera riassunti per tutte le email di una casella
    func generateSummariesForMailbox(_ mailboxId: String) async {
        let emails = emailRepository.getEmails(forMailbox: mailboxId)
        guard !emails.isEmpty else { return }
        
        for email in emails {
            if emailSummaries[email.id] == nil, let body = email.body, !body.isEmpty {
                // Usa priorità secondaria per batch processing
                let task = AITask.emailSummary(
                    subject: email.subject,
                    body: body,
                    priority: .secondary
                )
                
                await withCheckedContinuation { continuation in
                    Task { @MainActor in
                        AIManager.shared.enqueue(task) { (result: AIResult) in
                            if result.success, let summary = result.result?.value as? String {
                                self.emailSummaries[email.id] = summary
                            }
                            continuation.resume(returning: ())
                        }
                    }
                }
            }
        }
    }
    
    /// Ottiene il riassunto di un'email (dalla cache o generandolo)
    func getEmailSummary(for email: Email) async -> String? {
        if let cached = emailSummaries[email.id] {
            return cached
        }
        
        return await generateEmailSummary(for: email)
    }
    
    // MARK: - Metodi esistenti ottimizzati
}

