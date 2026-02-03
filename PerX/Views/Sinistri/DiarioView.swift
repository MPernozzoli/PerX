import SwiftUI
import CoreData
import Foundation
import WebKit

enum DiarioEntryType: String, Codable {
    case email = "Email"
    case whatsapp = "WhatsApp"
    case notaUtente = "Nota Utente"
    case cambioStato = "Cambio Stato"
    case sistema = "Sistema"
}

struct DiarioEntryViewModel: Identifiable {
    let id: UUID
    let timestamp: Date
    let tipo: DiarioEntryType
    let titolo: String
    let riassunto: String
    let contenutoCompleto: String
    let email: Email? // Opzionale, solo per entry di tipo email
    let emailMessageId: String? // ID email per associare task
    let whatsAppChatId: String? // ID chat WhatsApp per associare task
    let whatsAppMessageIds: [String]? // ID messaggi WhatsApp per associare task
    var isExpanded: Bool = false
    var pendingAIProposal: DiarioAIProposal?
    
    init(id: UUID = UUID(), timestamp: Date, tipo: DiarioEntryType, titolo: String, riassunto: String, contenutoCompleto: String, email: Email? = nil, emailMessageId: String? = nil, whatsAppChatId: String? = nil, whatsAppMessageIds: [String]? = nil, isExpanded: Bool = false, pendingAIProposal: DiarioAIProposal? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.tipo = tipo
        self.titolo = titolo
        self.riassunto = riassunto
        self.contenutoCompleto = contenutoCompleto
        self.email = email
        self.emailMessageId = emailMessageId ?? email?.id
        self.whatsAppChatId = whatsAppChatId
        self.whatsAppMessageIds = whatsAppMessageIds
        self.isExpanded = isExpanded
        self.pendingAIProposal = pendingAIProposal
    }
}

struct DiarioAIProposal {
    struct StateProposal {
        let stateId: String
        let confidence: Double
        let reason: String
    }
    
    struct TaskProposal: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let deadline: Date?
        let taskType: String?
        let confidence: Double
        let reason: String
    }
    
    let state: StateProposal?
    let tasks: [TaskProposal]
}

struct DiarioView: View {
    @ObservedObject var sinistro: Sinistro
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var principaleViewModel = PrincipaleViewModel.shared
    @StateObject private var diarioParser = DiarioParser.shared
    @State private var entries: [DiarioEntryViewModel] = []
    @State private var isLoading = false
    @State private var newNoteText = ""
    @State private var isGeneratingSummary = false
    @State private var isProcessingOldEmails = false
    @State private var unprocessedEmailsCount = 0
    @State private var aiProposals: [UUID: DiarioAIProposal] = [:]
    @State private var parsedTags: [ParsedTag] = []
    
    private let diarioService = DiarioService.shared
    
    // MARK: - Owner Check (per push CloudKit quando non-owner)
    
    /// Email utente corrente (lowercased)
    private var currentUserEmail: String? {
        GoogleAuthService.shared.userEmail?.lowercased()
    }
    
    /// Owner effettivo: assignedToUserEmail con fallback a ownerEmail
    private var ownerEmailEffettivo: String? {
        (sinistro.assignedToUserEmail ?? sinistro.ownerEmail)?.lowercased()
    }
    
    /// true se l'utente corrente NON è l'owner
    private var isViewingAsNonOwner: Bool {
        guard let current = currentUserEmail,
              let owner = ownerEmailEffettivo,
              !owner.isEmpty else {
            return false
        }
        return current != owner
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "it_IT")
        return formatter
    }()
    
    private let relativeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "it_IT")
        return formatter
    }()
    
    @State private var loadTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar superiore (senza titolo)
            HStack {
                Spacer()
                
                // Pulsante "Compila Diario" se ci sono email non processate
                if unprocessedEmailsCount > 0 {
                    Button {
                        Task {
                            await processOldEmails()
                        }
                    } label: {
                        Label("Compila Diario (\(unprocessedEmailsCount))", systemImage: "book.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessingOldEmails || isLoading)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Chat view
            VStack(spacing: 0) {
                // Lista delle entry (stile chat)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if isLoading {
                                ProgressView()
                                    .padding()
                            } else if entries.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "message")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                    Text("Nessun messaggio")
                                        .foregroundColor(.secondary)
                                    Text("Le email associate al sinistro e le tue note appariranno qui")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.top, 60)
                            } else {
                                if isProcessingOldEmails {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Elaborazione email in corso...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                }
                                
                                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                    DiarioEntryRow(
                                        entry: entry,
                                        index: index,
                                        allEntries: entries,
                                        proposal: aiProposals[entry.id],
                                        onAcceptState: { proposal in
                                            Task { await acceptStateProposal(entry: entry, proposal: proposal) }
                                        },
                                        onRejectState: {
                                            aiProposals.removeValue(forKey: entry.id)
                                        },
                                        onAcceptTask: { task in
                                            Task { await acceptTaskProposal(entry: entry, task: task) }
                                        },
                                        onRejectTask: {
                                            aiProposals.removeValue(forKey: entry.id)
                                        },
                                        onToggleExpand: {
                                            toggleExpand(entry)
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: entries.count) { _, _ in
                        if let lastEntry = entries.last {
                            withAnimation {
                                proxy.scrollTo(lastEntry.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Barra di input (stile chat) con highlight tag
                VStack(alignment: .leading, spacing: 4) {
                    // Indicatore tag rilevati
                    if !parsedTags.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(parsedTags, id: \.body) { tag in
                                TagIndicator(tag: tag)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }
                    
                    HStack(spacing: 12) {
                        TextField("Scrivi una nota... (usa @task, @azione, @[riferimento])", text: $newNoteText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(20)
                            .lineLimit(1...5)
                            .onChange(of: newNoteText) { _, newValue in
                                // Parse in tempo reale per highlight
                                let result = diarioParser.parse(newValue)
                                parsedTags = result.tags
                            }
                            .onSubmit {
                                if !newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Task {
                                        await saveUserNote(newNoteText)
                                    }
                                }
                            }
                        
                        Button {
                            if !newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Task {
                                    await saveUserNote(newNoteText)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGeneratingSummary)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .onAppear {
            loadTask?.cancel()
            loadTask = Task {
                await loadEntries()
            }
            
            // Segna come "viste" tutte le entry per l'utente corrente (azzera contatore notifiche)
            if let email = currentUserEmail, let rif = sinistro.riferimento {
                DiarioUnreadService.shared.markSeen(sinistroRiferimento: rif, currentUserEmail: email)
            }
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiProposalForDiarioEntry)) { notification in
            guard let entryId = notification.userInfo?["entryId"] as? UUID else { return }
            
            let stateProposal: DiarioAIProposal.StateProposal? = {
                guard let raw = notification.userInfo?["stateProposal"] as? [String: Any],
                      let stateId = raw["stateId"] as? String,
                      let confidence = raw["confidence"] as? Double,
                      let reason = raw["reason"] as? String else { return nil }
                return DiarioAIProposal.StateProposal(stateId: stateId, confidence: confidence, reason: reason)
            }()
            
            let tasksRaw = notification.userInfo?["taskProposals"] as? [[String: Any]] ?? []
            let tasks: [DiarioAIProposal.TaskProposal] = tasksRaw.compactMap { raw in
                guard let title = raw["title"] as? String,
                      let description = raw["description"] as? String,
                      let confidence = raw["confidence"] as? Double,
                      let reason = raw["reason"] as? String else { return nil }
                let deadline: Date? = {
                    if let ts = raw["deadline"] as? TimeInterval {
                        return Date(timeIntervalSince1970: ts)
                    }
                    return nil
                }()
                let taskType = raw["taskType"] as? String
                return DiarioAIProposal.TaskProposal(
                    title: title,
                    description: description,
                    deadline: deadline,
                    taskType: taskType,
                    confidence: confidence,
                    reason: reason
                )
            }
            
            aiProposals[entryId] = DiarioAIProposal(state: stateProposal, tasks: tasks)
            if let idx = entries.firstIndex(where: { $0.id == entryId }) {
                entries[idx].pendingAIProposal = aiProposals[entryId]
            }
        }
    }
    
    private func toggleExpand(_ entry: DiarioEntryViewModel) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].isExpanded.toggle()
        }
    }
    
    // MARK: - AI Proposal Handlers
    private func acceptStateProposal(entry: DiarioEntryViewModel, proposal: DiarioAIProposal.StateProposal) async {
        guard let stato = StatoManager.StatoSinistro(rawValue: proposal.stateId) else { return }
        sinistro.stato = stato.descrizione
        sinistro.statoDetail = .none
        try? viewContext.save()
        NotificationCenter.default.post(
            name: .sinistroStatoChanged,
            object: nil,
            userInfo: [
                "sinistroID": sinistro.riferimento ?? "",
                "oldState": stato,
                "newState": stato
            ]
        )
        aiProposals.removeValue(forKey: entry.id)
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx].pendingAIProposal = nil
        }
    }
    
    private func acceptTaskProposal(entry: DiarioEntryViewModel, task: DiarioAIProposal.TaskProposal) async {
        let newTask = DailyTask(
            title: task.title,
            description: task.description,
            type: .aiGenerated,
            sinistroID: sinistro.riferimento,
            priority: TaskManager.shared.calculateBasePriority(for: sinistro),
            deadline: task.deadline,
            estimatedDuration: TaskManager.shared.getEstimatedDuration(for: TaskType.aiGenerated, sinistro: sinistro),
            metadata: [
                "ai_proposal": AnyCodable(true),
                "ai_confidence": AnyCodable(task.confidence),
                "sourceDiarioEntryId": AnyCodable(entry.id.uuidString),
                "taskType": AnyCodable(task.taskType ?? "")
            ],
            sourceDiarioEntryId: entry.id
        )
        TaskManager.shared.addTask(newTask)
        aiProposals.removeValue(forKey: entry.id)
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx].pendingAIProposal = nil
        }
    }
    
    private func loadEntries() async {
        isLoading = true
        
        // Carica PRIMA le entry salvate dal CoreData e mostra subito
        var savedEntries: [DiarioEntryViewModel] = []
        let savedDiarioEntries = sinistro.diarioArray
        
        print("[DiarioView] 📚 Caricate \(savedDiarioEntries.count) entry salvate")
        
        // Recupera il thread per poter caricare le email se necessario
        let threadRequest = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        threadRequest.predicate = NSPredicate(format: "sinistro == %@", sinistro)
        let thread = try? viewContext.fetch(threadRequest).first
        
        for savedEntry in savedDiarioEntries {
            var email: Email? = nil
            
            // Se è un'email, prova a recuperarla dal thread
            if savedEntry.tipo == .email, let emailId = savedEntry.emailMessageId, let thread = thread {
                let emails = principaleViewModel.emails(for: thread)
                email = emails.first { $0.id == emailId }
            }
            
            let viewModel = DiarioEntryViewModel(
                id: savedEntry.id,
                timestamp: savedEntry.timestamp,
                tipo: DiarioEntryType(rawValue: savedEntry.tipo.rawValue) ?? .sistema,
                titolo: savedEntry.titolo ?? "",
                riassunto: savedEntry.riassunto ?? savedEntry.testo,
                contenutoCompleto: savedEntry.contenutoCompleto ?? savedEntry.testo,
                email: email,
                emailMessageId: savedEntry.emailMessageId,
                whatsAppChatId: savedEntry.whatsAppChatId,
                whatsAppMessageIds: savedEntry.whatsAppMessageIds
            )
            savedEntries.append(viewModel)
        }
        
        // Mostra IMMEDIATAMENTE le entry salvate
        await MainActor.run {
            entries = savedEntries.sorted { $0.timestamp < $1.timestamp }
            isLoading = false
        }
        
        // Se non c'è thread, basta così
        guard let thread = thread else {
            await MainActor.run {
                unprocessedEmailsCount = 0
            }
            return
        }
        
        // Recupera tutte le email associate
        let allEmails = principaleViewModel.emails(for: thread)
            .sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
        
        // Crea un set delle email già processate (basato su messageId salvato)
        let processedEmailIds = Set(savedDiarioEntries.compactMap { $0.emailMessageId })
        
        print("[DiarioView] 📧 Trovate \(allEmails.count) email, già processate: \(processedEmailIds.count)")
        
        var newEntries: [DiarioEntryViewModel] = []
        var unprocessedCount = 0
        let activationDate = diarioService.activationDate ?? Date()
        
        // Processa solo le email NUOVE (non ancora nel diario)
        // Limita a 10 email per batch per evitare sovraccarico
        let emailsToProcess = allEmails.prefix(10)
        
        for email in emailsToProcess {
            // Controlla se il task è stato cancellato
            if Task.isCancelled {
                print("[DiarioView] ⚠️ Task cancellato, interruzione processamento")
                break
            }
            
            let emailDate = email.date ?? Date.distantPast
            let shouldProcessAuto = emailDate >= activationDate
            
            // Conta le email non ancora processate (quelle vecchie)
            if !shouldProcessAuto && !processedEmailIds.contains(email.id) {
                unprocessedCount += 1
                continue
            }
            
            // SALTA se già processata - questo è il punto chiave!
            if processedEmailIds.contains(email.id) {
                print("[DiarioView] ⏭️ Email \(email.id) già processata, saltata")
                continue
            }
            
            // Processa solo le email nuove che non sono ancora state salvate
            print("[DiarioView] ✨ Processando nuova email: \(email.id)")
            
            var currentEmail = email
            var emailBody = email.body
            
            if emailBody == nil {
                // Timeout per evitare loop infiniti
                let fetchTask = Task {
                    await MailViewModel.shared.fetchFullEmail(for: email.id)
                }
                
                var attempts = 0
                let maxAttempts = 5 // Ridotto da 10 a 5
                while attempts < maxAttempts && emailBody == nil {
                    // Controlla se il task è stato cancellato
                    if Task.isCancelled {
                        fetchTask.cancel()
                        break
                    }
                    
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if let cachedEmail = EmailCacheService.shared.loadFullEmail(forId: email.id) {
                        currentEmail = cachedEmail
                        emailBody = cachedEmail.body
                        break
                    }
                    attempts += 1
                }
                
                // Annulla il task se non è completato
                if emailBody == nil {
                    fetchTask.cancel()
                }
            }
            
            guard let body = emailBody, !body.isEmpty else { continue }
            
            // Genera riassunto usando AI
            let riassunto = await AppleIntelligenceService.shared.summarizeEmailBodyIgnoringSignature(
                subject: currentEmail.subject,
                body: body
            ) ?? currentEmail.subject
            
            // Crea entry e salvala
            let diarioEntry = DiarioEntry(
                timestamp: currentEmail.date ?? Date(),
                tipo: .email,
                titolo: currentEmail.subject,
                riassunto: riassunto,
                contenutoCompleto: body,
                emailMessageId: currentEmail.id,
                processedEmailDate: currentEmail.date
            )
            
            sinistro.addDiarioEntry(diarioEntry)
            
            // Attiva trigger intelligenti
            await ActiveTriggerService.shared.processDiarioEntry(
                diarioEntry,
                sinistro: sinistro,
                email: currentEmail,
                context: viewContext
            )
            
            let viewModel = DiarioEntryViewModel(
                timestamp: currentEmail.date ?? Date(),
                tipo: .email,
                titolo: currentEmail.subject,
                riassunto: riassunto,
                contenutoCompleto: body,
                email: currentEmail,
                emailMessageId: currentEmail.id
            )
            
            newEntries.append(viewModel)
        }
        
        // Salva le modifiche se ci sono nuove entry
        if !newEntries.isEmpty {
            try? viewContext.save()
            print("[DiarioView] 💾 Salvate \(newEntries.count) nuove entry")
        }
        
        // Combina entry salvate e nuove (solo se ci sono nuove)
        if !newEntries.isEmpty {
            var allEntries = savedEntries + newEntries
            allEntries.sort { $0.timestamp < $1.timestamp }
            
            await MainActor.run {
                entries = allEntries
            }
        }
        
        await MainActor.run {
            unprocessedEmailsCount = unprocessedCount
        }
    }
    
    private func processOldEmails() async {
        isProcessingOldEmails = true
        
        // Recupera il thread email per questo sinistro
        let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        request.predicate = NSPredicate(format: "sinistro == %@", sinistro)
        
        guard let thread = try? viewContext.fetch(request).first else {
            await MainActor.run {
                isProcessingOldEmails = false
            }
            return
        }
        
        // Recupera tutte le email associate
        let allEmails = principaleViewModel.emails(for: thread)
            .sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
        
        let activationDate = diarioService.activationDate ?? Date()
        var processedEntries: [DiarioEntryViewModel] = []
        
        // Processa solo le email vecchie (arrivate prima dell'attivazione)
        // Limita a 5 email per batch per evitare sovraccarico
        let oldEmailsToProcess = allEmails.filter { ($0.date ?? Date.distantPast) < activationDate }.prefix(5)
        
        for email in oldEmailsToProcess {
            // Controlla se il task è stato cancellato
            if Task.isCancelled {
                print("[DiarioView] ⚠️ Task cancellato, interruzione processamento email vecchie")
                break
            }
            
            let emailDate = email.date ?? Date.distantPast
            
            var currentEmail = email
            var emailBody = email.body
            
            // Assicurati che il corpo sia caricato
            if emailBody == nil {
                // Timeout per evitare loop infiniti
                let fetchTask = Task {
                    await MailViewModel.shared.fetchFullEmail(for: email.id)
                }
                
                // Attendi e recupera dalla cache
                var attempts = 0
                let maxAttempts = 5 // Ridotto da 10 a 5
                while attempts < maxAttempts && emailBody == nil {
                    // Controlla se il task è stato cancellato
                    if Task.isCancelled {
                        fetchTask.cancel()
                        break
                    }
                    
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if let cachedEmail = EmailCacheService.shared.loadFullEmail(forId: email.id) {
                        currentEmail = cachedEmail
                        emailBody = cachedEmail.body
                        break
                    }
                    attempts += 1
                }
                
                // Annulla il task se non è completato
                if emailBody == nil {
                    fetchTask.cancel()
                }
            }
            
            guard let body = emailBody, !body.isEmpty else { continue }
            
            // Genera riassunto usando AI
            let riassunto = await AppleIntelligenceService.shared.summarizeEmailBodyIgnoringSignature(
                subject: currentEmail.subject,
                body: body
            ) ?? currentEmail.subject
            
            // Mantieni il corpo HTML originale per la visualizzazione
            let entry = DiarioEntryViewModel(
                timestamp: currentEmail.date ?? Date(),
                tipo: .email,
                titolo: currentEmail.subject,
                riassunto: riassunto,
                contenutoCompleto: body, // Mantieni HTML
                email: currentEmail,
                emailMessageId: currentEmail.id
            )
            
            processedEntries.append(entry)
        }
        
        // Salva le entry processate e pubblica eventi per ClaimEngine
        let unifiedEventBus = UnifiedEventBus.shared
        
        for entry in processedEntries {
            if let email = entry.email {
                let diarioEntry = DiarioEntry(
                    timestamp: entry.timestamp,
                    tipo: .email,
                    titolo: entry.titolo,
                    riassunto: entry.riassunto,
                    contenutoCompleto: entry.contenutoCompleto,
                    emailMessageId: email.id,
                    processedEmailDate: email.date
                )
                sinistro.addDiarioEntry(diarioEntry)
                
                // Pubblica evento su UnifiedEventBus per attivare ClaimEngine
                // Determina direction confrontando sender con email utente
                let currentUserEmail = AppState.shared.googleAuthService.userEmail?.lowercased() ?? ""
                let senderEmail = email.sender.email.lowercased()
                let direction: ClaimEventDirection = senderEmail == currentUserEmail || senderEmail.contains("@actsrl.it") 
                    ? .outbound 
                    : .inbound
                
                // Determina senderType
                let senderType: ClaimEventSenderType = {
                    if senderEmail.contains("@actsrl.it") {
                        return .studio
                    } else if senderEmail.contains("agenzia") || senderEmail.contains("broker") {
                        return .agency
                    } else if senderEmail.contains("liquidatore") || senderEmail.contains("liquidazione") {
                        return .liquidator
                    } else if senderEmail.contains("compagnia") || senderEmail.contains("assicurazione") {
                        return .company
                    } else {
                        return .insured
                    }
                }()
                
                let emailEvent = EmailClaimEvent(
                    emailId: email.id,
                    sinistroId: sinistro.riferimento,
                    direction: direction,
                    intent: .documentation, // Default per email vecchie
                    senderType: senderType,
                    subject: email.subject,
                    hasAttachments: !(email.attachments?.isEmpty ?? true),
                    attachmentCount: email.attachments?.count ?? 0
                )
                unifiedEventBus.publish(emailEvent)
                
                // Attiva anche trigger intelligenti legacy
                await ActiveTriggerService.shared.processDiarioEntry(
                    diarioEntry,
                    sinistro: sinistro,
                    email: email,
                    context: viewContext
                )
            }
        }
        
        try? viewContext.save()
        
        // Aggiungi le nuove entry alle esistenti
        await MainActor.run {
            entries.append(contentsOf: processedEntries)
            entries.sort { $0.timestamp < $1.timestamp }
            unprocessedEmailsCount = 0
            isProcessingOldEmails = false
        }
    }
    
    
    private func saveUserNote(_ noteText: String) async {
        guard !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isGeneratingSummary = true
        
        // Parse nota per estrarre tag (@task, @azione, @[riferimento]) - solo per UI, non pubblica evento
        let parseResult = diarioParser.parse(noteText)
        
        // Genera riassunto della nota usando AI
        let riassunto = await AppleIntelligenceService.shared.summarizeEmailBodyIgnoringSignature(
            subject: "Nota utente",
            body: noteText
        ) ?? String(noteText.prefix(100))
        
        // Crea titolo basato sui tag trovati
        let titolo: String
        if let firstTask = parseResult.tags.first(where: { $0.type == .task }) {
            titolo = "📋 \(firstTask.body)"
        } else if let firstAction = parseResult.tags.first(where: { $0.type == .action }) {
            titolo = "⚡ Azione: \(firstAction.body)"
        } else if let firstRef = parseResult.tags.first(where: { $0.type == .reference }) {
            titolo = "🔗 Rif: \(firstRef.body)"
        } else {
            titolo = "Nota"
        }
        
        // Crea entry ID per tracking PRIMA di processare
        let entryId = UUID()
        let actorEmail = currentUserEmail
        
        // Crea e salva entry nel CoreData (con createdByEmail per tracciamento notifiche)
        let diarioEntry = DiarioEntry(
            id: entryId,
            timestamp: Date(),
            tipo: .notaUtente,
            titolo: titolo,
            riassunto: riassunto,
            contenutoCompleto: noteText,
            createdByEmail: actorEmail
        )
        
        sinistro.addDiarioEntry(diarioEntry)
        try? viewContext.save()
        
        // Se l'utente corrente non è l'owner, push immediato su CloudKit (best-effort)
        if isViewingAsNonOwner, let riferimento = sinistro.riferimento, let email = actorEmail {
            Task {
                await CloudKitSyncService.shared.pushDiarioEntry(diarioEntry, sinistroRiferimento: riferimento, actorEmail: email)
            }
        }
        
        // Ora processa la nota con il diarioEntryId per collegare le task
        if parseResult.hasTags {
            _ = diarioParser.processUserNote(
                noteText,
                sinistroId: sinistro.riferimento,
                diarioEntryId: entryId
            )
        } else {
            // Se non ci sono tag, usa l'analisi AI classica
            await DiarioEntryAnalysisService.shared.analyzeDiarioEntry(
                diarioEntry,
                sinistro: sinistro,
                context: viewContext
            )
        }
        
        // Crea view model
        let newEntry = DiarioEntryViewModel(
            id: entryId,
            timestamp: Date(),
            tipo: .notaUtente,
            titolo: titolo,
            riassunto: riassunto,
            contenutoCompleto: noteText
        )
        
        await MainActor.run {
            entries.append(newEntry)
            entries.sort { $0.timestamp < $1.timestamp }
            newNoteText = ""
            parsedTags = []
            isGeneratingSummary = false
        }
    }
}

// MARK: - Tag Indicator View

/// Indicatore visivo per i tag estratti dalla nota
struct TagIndicator: View {
    let tag: ParsedTag
    
    private var icon: String {
        switch tag.type {
        case .task: return "checkmark.circle"
        case .action: return "bolt.circle"
        case .reference: return "link.circle"
        }
    }
    
    private var color: Color {
        switch tag.type {
        case .task: return .blue
        case .action: return .orange
        case .reference: return .purple
        }
    }
    
    private var label: String {
        switch tag.type {
        case .task: return "Task"
        case .action: return "Azione"
        case .reference: return "Rif"
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text("\(label): \(tag.body.prefix(20))\(tag.body.count > 20 ? "..." : "")")
                .font(.caption2)
                .lineLimit(1)
            if let deadline = tag.deadline {
                Text("⏰ entro \(formatTime(deadline))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if let scheduledTime = tag.scheduledTime {
                Text("🕐 alle \(formatTime(scheduledTime))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(12)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: date)
    }
}

// Vista a bolle stile chat
struct ChatBubble: View {
    let entry: DiarioEntryViewModel
    let proposal: DiarioAIProposal?
    let onAcceptState: (DiarioAIProposal.StateProposal) -> Void
    let onRejectState: () -> Void
    let onAcceptTask: (DiarioAIProposal.TaskProposal) -> Void
    let onRejectTask: () -> Void
    let onToggleExpand: () -> Void
    @State private var dynamicHeight: CGFloat = 100
    @StateObject private var taskManager = TaskManager.shared
    
    init(
        entry: DiarioEntryViewModel,
        proposal: DiarioAIProposal?,
        onAcceptState: @escaping (DiarioAIProposal.StateProposal) -> Void,
        onRejectState: @escaping () -> Void,
        onAcceptTask: @escaping (DiarioAIProposal.TaskProposal) -> Void,
        onRejectTask: @escaping () -> Void,
        onToggleExpand: @escaping () -> Void
    ) {
        self.entry = entry
        self.proposal = proposal
        self.onAcceptState = onAcceptState
        self.onRejectState = onRejectState
        self.onAcceptTask = onAcceptTask
        self.onRejectTask = onRejectTask
        self.onToggleExpand = onToggleExpand
    }
    
    private var isUserNote: Bool {
        entry.tipo == .notaUtente
    }
    
    private var isSystemNote: Bool {
        entry.tipo == .sistema || entry.tipo == .cambioStato
    }
    
    private var isEmail: Bool {
        entry.tipo == .email
    }
    
    private var bubbleColor: Color {
        if isUserNote {
            return Color.blue.opacity(0.15) // Destra, blu per utente
        } else if isSystemNote {
            return Color.gray.opacity(0.25) // Sinistra, grigio scuro per sistema
        } else {
            return Color.gray.opacity(0.1) // Sinistra, grigio chiaro per email/altri utenti
        }
    }
    
    private var currentUserEmail: String? {
        AppState.shared.googleAuthService.userEmail
    }
    
    private var isCurrentUserEmail: Bool {
        guard isEmail, let email = entry.email, let currentEmail = currentUserEmail else {
            return false
        }
        return email.sender.email.lowercased() == currentEmail.lowercased()
    }
    
    private var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "it_IT")
        return formatter
    }()
    
    private var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "it_IT")
        return formatter
    }()
    
    private var fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM yyyy 'alle' HH:mm"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter
    }()
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Allineamento a sinistra per email e sistema, a destra per note utente
            if !isUserNote {
                Spacer(minLength: 60)
            }
            
            // Bolla del messaggio
            VStack(alignment: isUserNote ? .trailing : .leading, spacing: 4) {
                // Header con informazioni - sempre visibile con data e ora
                HStack(spacing: 6) {
                    if entry.tipo == .email, let email = entry.email {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: isCurrentUserEmail ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(isCurrentUserEmail ? .blue : .green)
                                Text(email.sender.displayName)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }
                            
                            // Destinatari per email in uscita
                            if isCurrentUserEmail, !email.recipients.isEmpty {
                                Text("A: \(email.recipients.map { $0.displayName }.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: iconForEntryType(entry.tipo))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(entry.tipo.rawValue)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(formatTimestamp(entry.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(timeFormatter.string(from: entry.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                
                // Contenuto della bolla
                VStack(alignment: .leading, spacing: 8) {
                    // Titolo (solo per email)
                    if entry.tipo == .email && !entry.titolo.isEmpty {
                        Text(entry.titolo)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    
                    // Riassunto o contenuto
                    if entry.isExpanded {
                        if entry.tipo == .email {
                            // Mostra HTML per email
                            MailHTMLView(htmlString: entry.contenutoCompleto, dynamicHeight: $dynamicHeight)
                                .frame(height: max(dynamicHeight, 100))
                                .frame(maxWidth: 400)
                                .allowsHitTesting(false)
                        } else {
                            // Testo semplice per note
                            Text(entry.contenutoCompleto)
                                .font(.body)
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: 400, alignment: .leading)
                        }
                    } else {
                        Text(entry.riassunto)
                            .font(.body)
                            .foregroundColor(.primary)
                            .lineLimit(3)
                            .frame(maxWidth: 400, alignment: .leading)
                    }
                    
                    // Pulsante espandi/comprimi
                    if !entry.riassunto.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                onToggleExpand()
                            }
                        } label: {
                            Text(entry.isExpanded ? "Mostra meno" : "Mostra tutto")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Allegati email (se presenti)
                    if entry.tipo == .email, let email = entry.email, let attachments = email.attachments, !attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Divider()
                                .padding(.vertical, 4)
                            HStack(spacing: 4) {
                                Image(systemName: "paperclip")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("Allegati (\(attachments.count))")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                            }
                            ForEach(Array(attachments.enumerated()), id: \.element.attachmentId) { index, attachment in
                                HStack(spacing: 6) {
                                    Image(systemName: iconForFileType(attachment.filename))
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text(attachment.filename)
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if attachment.size > 0 {
                                        Text(formatFileSize(attachment.size))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Info WhatsApp (se presente)
                    if entry.tipo == .whatsapp {
                        HStack(spacing: 4) {
                            Image(systemName: "message.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("Messaggio WhatsApp")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    
                    // Task generate da questa entry (se presenti) - dentro la stessa bolla
                    let entryTasks = getTasksForEntry(entry)
                    if !entryTasks.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(entryTasks) { task in
                                TaskAttachmentView(
                                    task: task,
                                    onEdit: {
                                        // Mostra modal di modifica
                                        // TODO: Implementare modifica task
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(bubbleColor)
                )
                
                // Proposta AI (da confermare)
                if let proposal {
                    VStack(alignment: .leading, spacing: 8) {
                        if let state = proposal.state {
                            AIProposalRow(
                                title: "Cambiare stato in \(state.stateId)",
                                subtitle: state.reason,
                                confidence: state.confidence,
                                onAccept: { onAcceptState(state) },
                                onReject: onRejectState
                            )
                        }
                        
                        ForEach(proposal.tasks) { task in
                            AIProposalRow(
                                title: "Creare task \"\(task.title)\"",
                                subtitle: task.reason,
                                confidence: task.confidence,
                                onAccept: { onAcceptTask(task) },
                                onReject: onRejectTask
                            )
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.yellow.opacity(0.15))
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: isUserNote ? .trailing : .leading)
            
            if isUserNote {
                Spacer(minLength: 60)
            }
        }
    }
    
    private func getTasksForEntry(_ entry: DiarioEntryViewModel) -> [DailyTask] {
        // Cerca tutte le task associate a questa entry/comunicazione
        return taskManager.tasks.filter { task in
            // Task con sourceDiarioEntryId corrispondente
            if let sourceEntryId = task.sourceDiarioEntryId {
                return sourceEntryId == entry.id
            }
            
            // Task associate a email (tramite vari metadata)
            if let emailId = entry.emailMessageId ?? entry.email?.id {
                // Cerca per originalEmailId (task generate automaticamente da email)
                if let originalEmailId = task.metadata["originalEmailId"]?.value as? String,
                   originalEmailId == emailId {
                    return true
                }
                
                // Cerca per sourceEmailId (task create manualmente da email)
                if let sourceEmailId = task.metadata["sourceEmailId"]?.value as? String,
                   sourceEmailId == emailId {
                    return true
                }
            }
            
            // Task associate a WhatsApp
            if entry.tipo == .whatsapp {
                // Cerca per chat ID
                if let chatId = entry.whatsAppChatId {
                    if let taskChatId = task.metadata["whatsAppChatId"]?.value as? String,
                       taskChatId == chatId {
                        return true
                    }
                    if let sourceChatId = task.metadata["sourceWhatsAppChatId"]?.value as? String,
                       sourceChatId == chatId {
                        return true
                    }
                }
                
                // Cerca per message ID
                if let messageIds = entry.whatsAppMessageIds {
                    if let taskMessageId = task.metadata["sourceWhatsAppMessageId"]?.value as? String,
                       messageIds.contains(taskMessageId) {
                        return true
                    }
                }
            }
            
            return false
        }
    }
    
    private func iconForEntryType(_ type: DiarioEntryType) -> String {
        switch type {
        case .email: return "envelope.fill"
        case .whatsapp: return "message.fill"
        case .notaUtente: return "note.text"
        case .cambioStato: return "arrow.triangle.2.circlepath"
        case .sistema: return "gearshape.fill"
        }
    }
    
    private func iconForFileType(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "jpg", "jpeg", "png", "gif": return "photo.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        default: return "doc.fill"
        }
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        FileSizeFormatter.formatKBMB(bytes)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Oggi"
        } else if calendar.isDateInYesterday(date) {
            return "Ieri"
        } else {
            // Data completa
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            dateFormatter.locale = Locale(identifier: "it_IT")
            return dateFormatter.string(from: date)
        }
    }
    
    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "it_IT")
        
        if calendar.isDateInToday(date) {
            return "Oggi"
        } else if calendar.isDateInYesterday(date) {
            return "Ieri"
        } else {
            dateFormatter.dateFormat = "EEEE d MMMM yyyy"
            return dateFormatter.string(from: date).capitalized
        }
    }
}

struct TaskAttachmentView: View {
    let task: DailyTask
    let onEdit: (() -> Void)?
    
    @State private var isEditing = false
    
    init(task: DailyTask, onEdit: (() -> Void)? = nil) {
        self.task = task
        self.onEdit = onEdit
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(task.status == .completed ? .green : .blue)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .strikethrough(task.status == .completed)
                
                // Mostra deadline o scheduledTime
                if let deadline = task.deadline {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Scadenza: \(formatDate(deadline))")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                } else if let scheduledTime = task.scheduledTime {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text("Programmata: \(formatDate(scheduledTime))")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                if onEdit != nil && task.status != .completed {
                    Button {
                        onEdit?()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                
                if task.status == .completed {
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(task.status == .completed ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        DateUtils.formatRelativeWithTime(date)
    }
}

private struct AIProposalRow: View {
    let title: String
    let subtitle: String
    let confidence: Double
    let onAccept: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: "conf %.0f%%", confidence * 100))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
            
            HStack {
                Button("No") {
                    onReject()
                }
                .buttonStyle(.bordered)
                
                Button("Sì") {
                    onAccept()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct SelectableText: View {
    let text: String
    
    var body: some View {
        Text(text)
            .textSelection(.enabled)
    }
}

struct AddNoteSheet: View {
    @ObservedObject var sinistro: Sinistro
    @Binding var noteText: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Aggiungi Nota")
                .font(.headline)
            
            TextEditor(text: $noteText)
                .frame(height: 200)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .focused($isFocused)
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Salva") {
                    onSave(noteText)
                }
                .buttonStyle(.borderedProminent)
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 500, height: 350)
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - Helper Views

/// Riga di entry del diario con separatore di data
private struct DiarioEntryRow: View {
    let entry: DiarioEntryViewModel
    let index: Int
    let allEntries: [DiarioEntryViewModel]
    let proposal: DiarioAIProposal?
    let onAcceptState: (DiarioAIProposal.StateProposal) -> Void
    let onRejectState: () -> Void
    let onAcceptTask: (DiarioAIProposal.TaskProposal) -> Void
    let onRejectTask: () -> Void
    let onToggleExpand: () -> Void
    
    private var shouldShowSeparator: Bool {
        if index == 0 {
            // Mostra separatore per prima entry se non è di oggi
            return !Calendar.current.isDateInToday(entry.timestamp)
        } else {
            let previousEntry = allEntries[index - 1]
            return !Calendar.current.isDate(entry.timestamp, inSameDayAs: previousEntry.timestamp)
        }
    }
    
    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "it_IT")
        
        if calendar.isDateInToday(date) {
            return "Oggi"
        } else if calendar.isDateInYesterday(date) {
            return "Ieri"
        } else {
            dateFormatter.dateFormat = "EEEE d MMMM yyyy"
            return dateFormatter.string(from: date).capitalized
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if shouldShowSeparator {
                HStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                    Text(formatDateHeader(entry.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.vertical, 8)
            }
            
            ChatBubble(
                entry: entry,
                proposal: proposal,
                onAcceptState: onAcceptState,
                onRejectState: onRejectState,
                onAcceptTask: onAcceptTask,
                onRejectTask: onRejectTask,
                onToggleExpand: onToggleExpand
            )
            .id(entry.id)
        }
    }
}