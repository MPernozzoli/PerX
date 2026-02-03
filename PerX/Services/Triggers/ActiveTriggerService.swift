import Foundation
import CoreData

/// Servizio per gestire trigger attivi su comunicazioni in arrivo
@MainActor
class ActiveTriggerService {
    static let shared = ActiveTriggerService()
    
    private let analysisService = CommunicationAnalysisService.shared
    private let taskManager = TaskManager.shared
    private let statoManager = StatoManager.shared
    private let fileService = FileService.shared
    private let fileTagManager = FileTagManager.shared
    private let gmailService = GmailService.shared
    private let newsService = StudioNewsService.shared
    private let authService = GoogleAuthService.shared
    
    // Pattern per riconoscere loghi/immagini firme da escludere
    private let signatureLogoPatterns: [String] = [
        "logo", "firma", "signature", "banner", "icon", "brand",
        "footer", "header", "image00", "image01", "image02",
        "unnamed", "cid:", "inline"
    ]
    
    // Estensioni tipiche dei loghi firme
    private let signatureLogoExtensions: Set<String> = ["png", "gif", "bmp"]
    
    // Dimensione massima per considerare un file come logo firma (10KB)
    private let maxLogoSize: Int = 10 * 1024
    
    private init() {}
    
    /// Processa una nuova entry del diario e attiva i trigger se necessario
    func processDiarioEntry(
        _ entry: DiarioEntry,
        sinistro: Sinistro,
        email: Email? = nil,
        whatsAppMessages: [WhatsAppMessage]? = nil,
        context: NSManagedObjectContext
    ) async {
        // Estrai informazioni dalla comunicazione
        let subject = entry.titolo
        let body = entry.contenutoCompleto ?? entry.riassunto ?? entry.testo
        let senderEmail = email?.sender.email
        
        // Determina se ci sono allegati
        var hasAttachments = false
        var attachmentTypes: [String] = []
        
        if let email = email {
            hasAttachments = !(email.attachments?.isEmpty ?? true)
            attachmentTypes = email.attachments?.map { $0.filename } ?? []
        } else if let messages = whatsAppMessages {
            hasAttachments = messages.contains { $0.mediaUrl != nil }
            attachmentTypes = messages.filter { $0.type != .text }.map { $0.type.rawValue }
        }
        
        // Analizza la comunicazione
        let analysis = await analysisService.analyzeCommunication(
            subject: subject,
            body: body,
            senderEmail: senderEmail,
            hasAttachments: hasAttachments,
            attachmentTypes: attachmentTypes,
            sinistroID: sinistro.riferimento
        )
        
        // Genera eventuale notizia di studio (email informative interne con molti destinatari)
        if let email = email {
            if let newsItem = newsService.createNewsIfEligible(
                email: email,
                entry: entry,
                analysis: analysis
            ) {
                print("[ActiveTrigger] 📰 Notizia studio creata: \(newsItem.title)")
            }
        }
        
        // Heuristica rapida su oggetto/testo per aggiornare lo stato
        applyQuickStateTransitions(
            subject: subject ?? "",
            body: body,
            hasAttachments: hasAttachments,
            sinistro: sinistro,
            context: context,
            attachmentTypes: attachmentTypes
        )
        
        // Se non richiede azione, esci
        guard analysis.requiresAction else {
            print("[ActiveTrigger] ⏭️ Nessuna azione richiesta per entry \(entry.id)")
            return
        }
        
        print("[ActiveTrigger] ✅ Analisi completata: intent=\(analysis.intent.rawValue), azioni=\(analysis.suggestedActions.count)")
        
        // Esegui le azioni suggerite
        var generatedTaskId: UUID? = nil
        
        for action in analysis.suggestedActions {
            switch action.type {
            case .downloadAttachment:
                if let email = email {
                    await downloadAndTagAttachment(
                        email: email,
                        tag: action.metadata["tag"]?.value as? String,
                        sinistro: sinistro
                    )
                }
                
            case .updateState:
                if let newStateString = action.metadata["newState"]?.value as? String,
                   let newState = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == newStateString }) {
                    updateSinistroState(sinistro: sinistro, newState: newState, context: context)
                }
                
            case .createTask:
                let taskId = await createTaskFromAction(
                    action: action,
                    sinistro: sinistro,
                    entry: entry,
                    analysis: analysis
                )
                if generatedTaskId == nil {
                    generatedTaskId = taskId
                }
                
            case .saveFiles:
                await saveFilesToFolder(
                    action: action,
                    sinistro: sinistro,
                    email: email,
                    whatsAppMessages: whatsAppMessages
                )
                
            case .createFolder:
                if let folderName = action.metadata["folder"]?.value as? String {
                    createFolderIfNeeded(folderName: folderName, sinistro: sinistro)
                }
                
            case .tagFile:
                // Gestito insieme a downloadAttachment
                break
            }
        }
        
        // Aggiorna l'entry con il task generato se presente
        if let taskId = generatedTaskId {
            updateDiarioEntryWithTask(entry: entry, taskId: taskId, sinistro: sinistro, context: context)
        }
    }
    
    // MARK: - Action Handlers
    
    private func downloadAndTagAttachment(
        email: Email,
        tag: String?,
        sinistro: Sinistro
    ) async {
        // Scarica solo allegati da email in ENTRATA (non inviate da noi)
        if isEmailSentByUser(email: email) {
            print("[ActiveTrigger] ⏭️ Email in uscita, skip download allegati")
            return
        }
        
        guard let riferimento = sinistro.riferimento,
              let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) else {
            print("[ActiveTrigger] ❌ Percorso sinistro non trovato")
            return
        }
        
        // Scarica gli allegati
        guard let attachments = email.attachments, !attachments.isEmpty else {
            print("[ActiveTrigger] ⚠️ Nessun allegato trovato")
            return
        }
        
        // Crea cartella "da mail" se non esiste
        let mailFolderPath = (sinistroPath as NSString).appendingPathComponent("da mail")
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: mailFolderPath) {
            do {
                try fileManager.createDirectory(atPath: mailFolderPath, withIntermediateDirectories: true)
                print("[ActiveTrigger] ✅ Creata cartella 'da mail' in \(sinistroPath)")
            } catch {
                print("[ActiveTrigger] ❌ Errore creazione cartella 'da mail': \(error)")
                return
            }
        }
        
        do {
            let emailDetail = try await gmailService.fetchEmailDetails(messageId: email.id)
            
            // Decodifica e salva gli allegati (esclusi loghi firme)
            for attachment in attachments {
                // Salta loghi e immagini delle firme
                if isSignatureLogo(attachment: attachment) {
                    print("[ActiveTrigger] ⏭️ Logo firma ignorato: \(attachment.filename)")
                    continue
                }
                
                let attachmentId = attachment.attachmentId
                
                let attachmentData = try await downloadAttachment(
                    messageId: email.id,
                    attachmentId: attachmentId
                )
                
                // Verifica dimensione: se piccolo e immagine, probabilmente è un logo
                if isLikelySignatureLogo(data: attachmentData, filename: attachment.filename) {
                    print("[ActiveTrigger] ⏭️ Immagine piccola (logo firma?): \(attachment.filename)")
                    continue
                }
                
                // Salva il file nella cartella "da mail"
                let fileName = attachment.filename
                let filePath = (mailFolderPath as NSString).appendingPathComponent(fileName)
                
                try attachmentData.write(to: URL(fileURLWithPath: filePath))
                print("[ActiveTrigger] ✅ Allegato salvato: \(fileName)")
                
                // Applica tag se specificato
                if let tag = tag {
                    if let fileTag = FileTagManager.FileTag.availableTags.first(where: { $0.name.lowercased() == tag.lowercased() }) {
                        fileTagManager.addTag(fileTag, toFile: filePath)
                        print("[ActiveTrigger] ✅ Tag '\(tag)' applicato a \(fileName)")
                    } else {
                        // Crea tag personalizzato se non esiste
                        // Per ora usiamo un tag esistente simile
                        if let attoTag = FileTagManager.FileTag.availableTags.first(where: { $0.id == "atto_firmato" }) {
                            fileTagManager.addTag(attoTag, toFile: filePath)
                        }
                    }
                }
            }
        } catch {
            print("[ActiveTrigger] ❌ Errore download allegati: \(error)")
        }
    }
    
    /// Verifica se un'email è stata inviata dall'utente corrente
    private func isEmailSentByUser(email: Email) -> Bool {
        guard let userEmail = authService.userEmail?.lowercased() else {
            return false
        }
        return email.sender.email.lowercased() == userEmail
    }
    
    /// Verifica se un allegato è probabilmente un logo di firma basandosi sul nome
    private func isSignatureLogo(attachment: EmailAttachment) -> Bool {
        let filename = attachment.filename.lowercased()
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        
        // Controlla pattern nel nome file
        for pattern in signatureLogoPatterns {
            if filename.contains(pattern) {
                return true
            }
        }
        
        // Se è una piccola immagine con nome generico
        if signatureLogoExtensions.contains(fileExtension) {
            // Nomi generici tipici dei loghi inline
            let genericNames = ["image", "img", "pic", "photo", "untitled"]
            let nameWithoutExt = (filename as NSString).deletingPathExtension
            for generic in genericNames {
                if nameWithoutExt.hasPrefix(generic) || nameWithoutExt == generic {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Verifica se i dati scaricati sembrano essere un logo firma (immagine piccola)
    private func isLikelySignatureLogo(data: Data, filename: String) -> Bool {
        let fileExtension = (filename.lowercased() as NSString).pathExtension
        
        // Se è un'immagine tipica dei loghi e molto piccola, probabilmente è un logo
        if signatureLogoExtensions.contains(fileExtension) && data.count < maxLogoSize {
            return true
        }
        
        return false
    }
    
    private func downloadAttachment(messageId: String, attachmentId: String) async throws -> Data {
        guard let accessToken = try? await GoogleAuthService.shared.getAccessToken() else {
            throw NSError(domain: "ActiveTriggerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Token non disponibile"])
        }
        
        let url = URL(string: "https://www.googleapis.com/gmail/v1/users/me/messages/\(messageId)/attachments/\(attachmentId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let attachmentDataString = json["data"] as? String else {
            throw NSError(domain: "ActiveTriggerService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Errore parsing allegato"])
        }
        
        // Decodifica base64url
        let base64 = attachmentDataString
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        guard let attachmentData = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            throw NSError(domain: "ActiveTriggerService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Errore decodifica base64"])
        }
        
        return attachmentData
    }
    
    private func updateSinistroState(
        sinistro: Sinistro,
        newState: StatoManager.StatoSinistro,
        context: NSManagedObjectContext,
        detail: StatoDetailCategory? = nil
    ) {
        let oldStateId = statoManager.getStatoId(fromDescrizione: sinistro.stato ?? "")
        let oldStateEnum = oldStateId.flatMap { StatoManager.StatoSinistro(rawValue: $0) }
        
        // Verifica se il sinistro è chiuso - non permettere cambio stato automatico (tranne richiesta revisione)
        if let oldState = oldStateEnum, oldState == .chiusa && newState != .richiestaRevisione {
            print("[ActiveTrigger] ⚠️ Impossibile cambiare stato sinistro chiuso: \(oldState.descrizione) → \(newState.descrizione)")
            return
        }
        
        // Usa StatoManager.changeState per validare la transizione
        Task {
            do {
                try await statoManager.changeState(
                    for: sinistro,
                    to: newState,
                    context: context
                )
                
                if let detail = detail {
                    sinistro.statoDetail = detail
                    try context.save()
                }
                
                print("[ActiveTrigger] ✅ Stato aggiornato: \(newState.descrizione)")
            } catch {
                print("[ActiveTrigger] ⚠️ Impossibile aggiornare stato: \(error.localizedDescription)")
            }
        }
    }
    
    private func createTaskFromAction(
        action: SuggestedAction,
        sinistro: Sinistro,
        entry: DiarioEntry,
        analysis: CommunicationAnalysisResult
    ) async -> UUID? {
        let priority = calculateTaskPriority(
            basePriority: action.priority,
            urgency: analysis.urgency,
            sinistro: sinistro
        )
        
        var metadata: [String: AnyCodable] = [
            "sourceDiarioEntryId": AnyCodable(entry.id.uuidString),
            "intent": AnyCodable(analysis.intent.rawValue),
            "urgency": AnyCodable(analysis.urgency.rawValue)
        ]
        
        // Aggiungi metadata specifici dell'azione
        for (key, value) in action.metadata {
            metadata[key] = value
        }
        
        // Aggiungi link alla comunicazione
        if let emailId = entry.emailMessageId {
            metadata["originalEmailId"] = AnyCodable(emailId)
        }
        if let whatsAppChatId = entry.whatsAppChatId {
            metadata["whatsAppChatId"] = AnyCodable(whatsAppChatId)
        }
        
        let task = DailyTask(
            title: action.title,
            description: action.description,
            type: .aiGenerated,
            sinistroID: sinistro.riferimento,
            priority: priority,
            deadline: action.deadline,
            estimatedDuration: estimateTaskDuration(actionType: action.metadata["taskType"]?.value as? String ?? ""),
            metadata: metadata
        )
        
        taskManager.addTask(task)
        print("[ActiveTrigger] ✅ Task creato: \(action.title)")
        
        return task.id
    }
    
    private func saveFilesToFolder(
        action: SuggestedAction,
        sinistro: Sinistro,
        email: Email?,
        whatsAppMessages: [WhatsAppMessage]?
    ) async {
        guard let riferimento = sinistro.riferimento,
              let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) else {
            return
        }
        
        // Determina la cartella di destinazione in base al tipo di comunicazione
        // Email -> "da mail", WhatsApp -> "da WA"
        let folderName: String
        if email != nil {
            folderName = "da mail"
        } else if whatsAppMessages != nil {
            folderName = "da WA"  // WhatsApp già gestito da WhatsAppDiarioService, ma manteniamo coerenza
        } else {
            folderName = action.metadata["folder"]?.value as? String ?? "allegati"
        }
        
        // Crea cartella se necessario
        let folderPath = (sinistroPath as NSString).appendingPathComponent(folderName)
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: folderPath) {
            do {
                try fileManager.createDirectory(atPath: folderPath, withIntermediateDirectories: true)
                print("[ActiveTrigger] ✅ Cartella creata: \(folderName)")
            } catch {
                print("[ActiveTrigger] ❌ Errore creazione cartella: \(error)")
                return
            }
        }
        
        // Salva file da email (solo se in ENTRATA)
        if let email = email, let attachments = email.attachments {
            // Salta email in uscita
            if isEmailSentByUser(email: email) {
                print("[ActiveTrigger] ⏭️ Email in uscita, skip salvataggio file")
                return
            }
            
            for attachment in attachments {
                // Salta loghi e immagini delle firme
                if isSignatureLogo(attachment: attachment) {
                    print("[ActiveTrigger] ⏭️ Logo firma ignorato: \(attachment.filename)")
                    continue
                }
                
                let attachmentId = attachment.attachmentId
                
                do {
                    let data = try await downloadAttachment(
                        messageId: email.id,
                        attachmentId: attachmentId
                    )
                    
                    // Verifica se è un logo firma per dimensione
                    if isLikelySignatureLogo(data: data, filename: attachment.filename) {
                        print("[ActiveTrigger] ⏭️ Immagine piccola (logo firma?): \(attachment.filename)")
                        continue
                    }
                    
                    let filePath = (folderPath as NSString).appendingPathComponent(attachment.filename)
                    try data.write(to: URL(fileURLWithPath: filePath))
                    print("[ActiveTrigger] ✅ File salvato: \(attachment.filename)")
                } catch {
                    print("[ActiveTrigger] ❌ Errore salvataggio file: \(error)")
                }
            }
        }
        
        // File WhatsApp sono già gestiti da WhatsAppDiarioService
        // Non processiamo qui per evitare duplicati
    }
    
    private func createFolderIfNeeded(
        folderName: String,
        sinistro: Sinistro
    ) {
        guard let riferimento = sinistro.riferimento,
              let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) else {
            return
        }
        
        let folderPath = (sinistroPath as NSString).appendingPathComponent(folderName)
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: folderPath) {
            do {
                try fileManager.createDirectory(atPath: folderPath, withIntermediateDirectories: true)
                print("[ActiveTrigger] ✅ Cartella creata: \(folderName)")
            } catch {
                print("[ActiveTrigger] ❌ Errore creazione cartella: \(error)")
            }
        }
    }
    
    private func updateDiarioEntryWithTask(
        entry: DiarioEntry,
        taskId: UUID,
        sinistro: Sinistro,
        context: NSManagedObjectContext
    ) {
        // Aggiorna l'entry con riferimento al task
        var entries = sinistro.diarioArray
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            // DiarioEntry non è mutabile, dobbiamo ricrearla
            let updatedEntry = DiarioEntry(
                id: entry.id,
                timestamp: entry.timestamp,
                tipo: entry.tipo,
                titolo: entry.titolo,
                riassunto: entry.riassunto ?? entry.testo,
                contenutoCompleto: entry.contenutoCompleto ?? entry.testo,
                emailMessageId: entry.emailMessageId,
                processedEmailDate: entry.processedEmailDate,
                whatsAppChatId: entry.whatsAppChatId,
                whatsAppMessageIds: entry.whatsAppMessageIds,
                processedWhatsAppDate: entry.processedWhatsAppDate
            )
            
            entries[index] = updatedEntry
            sinistro.diarioArray = entries
            
            // Salva il riferimento al task nei metadata dell'entry (tramite metadata nel sinistro o altro meccanismo)
            // Per ora salviamo il taskId nel metadata del task stesso
        }
    }
    
    // MARK: - Helpers
    
    private func applyQuickStateTransitions(
        subject: String,
        body: String,
        hasAttachments: Bool,
        sinistro: Sinistro,
        context: NSManagedObjectContext,
        attachmentTypes: [String]
    ) {
        let lowerSubject = subject.lowercased()
        let lowerBody = body.lowercased()
        let riferimento = sinistro.riferimento ?? ""
        let hasFolder: Bool = {
            if let path = fileService.getSinistroPath(riferimento: riferimento) {
                return FileManager.default.fileExists(atPath: path)
            }
            return false
        }()
        let detailIfMissingFolder: StatoDetailCategory? = hasFolder ? nil : .daScaricare
        
        if lowerSubject.contains("richiesta documentazione") {
            updateSinistroState(sinistro: sinistro, newState: .inAttesaDocumentale, context: context, detail: detailIfMissingFolder)
            return
        }
        
        if hasAttachments && (lowerSubject.contains("documentaz") || lowerBody.contains("documentaz")) {
            updateSinistroState(sinistro: sinistro, newState: .periziaDaEseguireDocumentale, context: context, detail: detailIfMissingFolder)
            return
        }
        
        if lowerSubject.contains("perizia controllata") {
            updateSinistroState(sinistro: sinistro, newState: .controllata, context: context)
            return
        }
        
        if lowerSubject.contains("richiesta revisione") {
            updateSinistroState(sinistro: sinistro, newState: .richiestaRevisione, context: context, detail: detailIfMissingFolder)
            return
        }
        
        if lowerSubject.contains("sopralluogo fissato") {
            updateSinistroState(sinistro: sinistro, newState: .sopralluogoFissato, context: context, detail: detailIfMissingFolder)
            return
        }
        
        if lowerSubject.contains("sopralluogo restituito") {
            updateSinistroState(sinistro: sinistro, newState: .sopralluogoRestituito, context: context, detail: detailIfMissingFolder)
            return
        }
        
        if lowerSubject.contains("videoperizia") && (lowerSubject.contains("fissata") || lowerBody.contains("concordata")) {
            updateSinistroState(sinistro: sinistro, newState: .videoperiziaFissata, context: context, detail: detailIfMissingFolder)
            return
        }
        
        if lowerSubject.contains("invio atto") || lowerSubject.contains("atto da firmare") {
            updateSinistroState(sinistro: sinistro, newState: .attoInviato, context: context, detail: detailIfMissingFolder)
            return
        }
        
        // Rilevamento atto ricevuto sottoscritto: quando arriva atto allegato
        if hasAttachments && attachmentTypes.contains(where: { $0.lowercased().contains("atto") }) {
            updateSinistroState(sinistro: sinistro, newState: .attoRicevutoSottoscritto, context: context, detail: detailIfMissingFolder)
            return
        }
        
        // Rilevamento accettata verbalmente: quando si dice espressamente che si accetta l'importo
        let accettazionePatterns = [
            "accetto l'importo", "accettiamo l'importo", "accetto senza atto", "accettiamo senza atto",
            "accetto verbalmente", "accettiamo verbalmente", "accetto senza firmare", "accettiamo senza firmare",
            "accetto l'importo proposto", "accettiamo l'importo proposto", "accetto la liquidazione",
            "accettiamo la liquidazione", "accetto la stima", "accettiamo la stima"
        ]
        if accettazionePatterns.contains(where: { lowerBody.contains($0) || lowerSubject.contains($0) }) {
            // Verifica che non ci sia un atto allegato (altrimenti è atto ricevuto sottoscritto)
            if !hasAttachments || !attachmentTypes.contains(where: { $0.lowercased().contains("atto") }) {
                updateSinistroState(sinistro: sinistro, newState: .accettataVerbalmente, context: context, detail: detailIfMissingFolder)
                return
            }
        }
        
        if lowerSubject.contains("esito") && !hasAttachments {
            updateSinistroState(sinistro: sinistro, newState: .esitoComunicato, context: context, detail: detailIfMissingFolder)
            return
        }
    }
    
    private func calculateTaskPriority(
        basePriority: Double,
        urgency: UrgencyLevel,
        sinistro: Sinistro
    ) -> Double {
        var priority = basePriority
        
        // Aggiungi priorità base del sinistro
        let sinistroPriority = taskManager.calculateBasePriority(for: sinistro)
        priority = max(priority, sinistroPriority)
        
        // Aggiungi bonus urgenza
        switch urgency {
        case .urgent:
            priority = min(1.0, priority + 0.3)
        case .high:
            priority = min(1.0, priority + 0.2)
        case .normal:
            break
        case .low:
            priority = max(0.0, priority - 0.1)
        }
        
        return priority
    }
    
    private func estimateTaskDuration(actionType: String) -> TimeInterval {
        switch actionType {
        case "close_sinistro":
            return 1800 // 30 min
        case "verify_documentation":
            return 1200 // 20 min
        case "handle_contestation":
            return 3600 // 1 ora
        case "recontact":
            return 600 // 10 min
        case "execute_survey":
            return 7200 // 2 ore
        case "clarification":
            return 1800 // 30 min
        default:
            return 1800 // 30 min default
        }
    }
    
    // MARK: - Public API
}

