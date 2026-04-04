import Foundation
import CoreData

/// Handler per email relative a comunicazioni interne dello studio
/// Gestisce: notizie dello studio, info interne, procedure, riunioni
class StudioCommunicationHandler: BaseEmailHandler {
    
    private let aiService = AppleIntelligenceService.shared
    
    init() {
        super.init(
            handlerId: "studio_communication",
            supportedCategories: [.studioNews, .internalInfo, .procedure, .meeting, .training, .administrative]
        )
    }
    
    override func handle(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[StudioHandler] 📧 Processamento email studio: \(email.originalEmail.subject) - categoria: \(email.category.displayName)")
        
        // Verifica se l'email ha un tag manuale e se è già processata
        let hasManualTag = await MainActor.run {
            EmailTagManager.shared.hasManualTag(emailId: email.originalEmail.id)
        }
        
        if hasManualTag {
            let status = await MainActor.run {
                EmailTagManager.shared.getProcessingStatus(forEmailId: email.originalEmail.id)
            }
            if status == .processata {
                print("[StudioHandler] ⏭️ Email \(email.originalEmail.id) ha tag manuale ed è già processata, skip")
                return nil
            }
        }
        
        // Applica tag automatico
        await applyEmailTag(for: email)
        
        // Verifica nuovamente dopo applyEmailTag (potrebbe aver marcato come processata)
        let hasManualTagAfter = await MainActor.run {
            EmailTagManager.shared.hasManualTag(emailId: email.originalEmail.id)
        }
        
        if hasManualTagAfter {
            let status = await MainActor.run {
                EmailTagManager.shared.getProcessingStatus(forEmailId: email.originalEmail.id)
            }
            if status == .processata {
                print("[StudioHandler] ⏭️ Email \(email.originalEmail.id) con tag manuale già processata dopo applyEmailTag, skip")
                return nil
            }
        }
        
        // Dispatch alla funzione specifica in base alla categoria
        switch email.category {
        case .studioNews, .internalInfo, .newsletter:
            return await handleStudioNews(email: email, context: context, isUnread: isUnread)
            
        case .meeting, .training:
            return await handleMeeting(email: email, context: context, isUnread: isUnread)
            
        case .procedure, .administrative:
            return await handleProcedure(email: email, context: context, isUnread: isUnread)
            
        default:
            return nil
        }
    }
    
    // MARK: - Studio News & Internal Info
    
    private func handleStudioNews(email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        guard isUnread else {
            print("[StudioHandler] ℹ️ Email già letta, skip creazione news")
            return nil
        }
        
        // Scarica corpo se mancante
        var emailToProcess = email.originalEmail
        if emailToProcess.body == nil {
            print("[StudioHandler] 📥 Download corpo email...")
            do {
                if let downloaded = try await MailManager.shared.fetchFullEmail(
                    emailId: emailToProcess.id,
                    context: context
                ) {
                    emailToProcess = downloaded
                }
            } catch {
                print("[StudioHandler] ⚠️ Errore download corpo email: \(error)")
            }
        }
        
        // Crea entry diario per analisi
        let summary = extractSummary(from: emailToProcess.body ?? emailToProcess.subject)
        let diarioEntry = DiarioEntry(
            timestamp: emailToProcess.date,
            tipo: .sistema,
            titolo: emailToProcess.subject,
            riassunto: summary,
            contenutoCompleto: emailToProcess.body ?? summary,
            emailMessageId: emailToProcess.id,
            processedEmailDate: emailToProcess.date
        )
        
        // Analizza il contenuto per determinare se creare una news
        let analysis = await analyzeContent(email: emailToProcess)
        
        // Passa al service che gestisce le news dello studio
        await MainActor.run {
            if let newsItem = StudioNewsService.shared.createNewsIfEligible(
                email: emailToProcess,
                entry: diarioEntry,
                analysis: analysis
            ) {
                print("[StudioHandler] ✅ News creata: \(newsItem.title)")
                
                // Se c'è una CTA, schedula la task
                if newsItem.cta != nil {
                    StudioNewsService.shared.scheduleCTA(for: newsItem)
                }
            } else {
                print("[StudioHandler] ℹ️ Email non idonea per news dashboard")
            }
        }
        
        // Le email studio non generano eventi sul bus sinistri
        return nil
    }
    
    // MARK: - Meetings
    
    private func handleMeeting(email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        guard isUnread else {
            print("[StudioHandler] ℹ️ Email già letta, skip creazione task riunione")
            return nil
        }
        
        // Scarica corpo se mancante
        var emailToProcess = email.originalEmail
        if emailToProcess.body == nil {
            print("[StudioHandler] 📥 Download corpo email per riunione...")
            do {
                if let downloaded = try await MailManager.shared.fetchFullEmail(
                    emailId: emailToProcess.id,
                    context: context
                ) {
                    emailToProcess = downloaded
                }
            } catch {
                print("[StudioHandler] ⚠️ Errore download corpo email: \(error)")
            }
        }
        
        let body = emailToProcess.body ?? emailToProcess.subject
        
        // Estrai data/ora riunione dal testo
        let meetingDate = extractMeetingDate(from: body)
        let meetingTitle = extractMeetingTitle(from: emailToProcess.subject)
        
        // Task creation delegata a ClaimEngine tramite evento
        // TODO: Pubblicare SystemClaimEvent con tipo .meeting
        // ClaimEngine processerà l'evento e creerà la task con fixedDateTime
        // Per ora manteniamo creazione diretta per compatibilità con riunioni studio
        await MainActor.run {
            let estimatedDuration: TimeInterval = 60 * 60 // 1 ora di default
            
            let task = DailyTask(
                title: meetingTitle,
                description: extractSummary(from: body),
                type: .meeting, // Cambiato da aiGenerated a meeting
                sinistroID: nil, // Non associata a sinistri
                priority: 0.7, // Priorità medio-alta
                deadline: meetingDate,
                estimatedDuration: estimatedDuration,
                metadata: [
                    "meeting": AnyCodable(true),
                    "sourceEmailId": AnyCodable(emailToProcess.id),
                    "meetingType": AnyCodable("studio")
                ],
                isTimeSensitive: meetingDate != nil,
                fixedDateTime: meetingDate,
                actionType: .attend
            )
            
            TaskManager.shared.addTask(task)
            print("[StudioHandler] ✅ Task riunione creata: \(meetingTitle)")
        }
        
        // Crea anche una news per visibilità in dashboard
        await createMeetingNews(email: emailToProcess, meetingDate: meetingDate)
        
        return nil
    }
    
    // MARK: - Procedures
    
    private func handleProcedure(email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        guard isUnread else {
            print("[StudioHandler] ℹ️ Email già letta, skip notifica procedura")
            return nil
        }
        
        // Scarica corpo se mancante
        var emailToProcess = email.originalEmail
        if emailToProcess.body == nil {
            print("[StudioHandler] 📥 Download corpo email procedura...")
            do {
                if let downloaded = try await MailManager.shared.fetchFullEmail(
                    emailId: emailToProcess.id,
                    context: context
                ) {
                    emailToProcess = downloaded
                }
            } catch {
                print("[StudioHandler] ⚠️ Errore download corpo email: \(error)")
            }
        }
        
        let body = emailToProcess.body ?? emailToProcess.subject
        
        // Le procedure vengono trattate come news con icona specifica
        await MainActor.run {
            let newsItem = StudioNewsItem(
                title: cleanTitle(emailToProcess.subject),
                summary: extractSummary(from: body),
                createdAt: emailToProcess.date,
                eventDate: nil,
                icon: "list.bullet.rectangle.portrait.fill",
                sourceEmailId: emailToProcess.id,
                sourceBody: body,
                sender: emailToProcess.sender.displayName,
                cta: extractProcedureCTA(from: body)
            )
            
            // Aggiungi manualmente al servizio news
            addDirectNews(newsItem)
            print("[StudioHandler] ✅ Procedura aggiunta alle news: \(newsItem.title)")
        }
        
        // Task creation delegata a ClaimEngine tramite evento
        // TODO: Pubblicare SystemClaimEvent con tipo .procedure
        // Per ora task non creata - procedura visibile solo come news
        // if requiresAction(body: body) {
        //     // ClaimEngine processerà evento e creerà task se necessario
        // }
        
        return nil
    }
    
    // MARK: - Helpers
    
    private func analyzeContent(email: Email) async -> CommunicationAnalysisResult {
        // Analisi semplificata per email interne
        let body = email.body ?? ""
        let dates = extractDates(from: body)
        
        return CommunicationAnalysisResult(
            intent: .noAction,
            urgency: .normal,
            context: CommunicationContext(
                senderType: determineSenderType(email: email),
                originalSender: nil,
                isForwarded: false,
                domain: email.sender.email.components(separatedBy: "@").last
            ),
            extractedData: ExtractedData(
                iban: nil,
                phoneNumbers: [],
                relevantPhoneNumber: nil,
                amounts: [],
                dates: dates,
                attachmentTypes: [],
                hasAttachments: email.attachments?.isEmpty == false
            ),
            requiresAction: false,
            suggestedActions: [],
            confidence: 0.8
        )
    }
    
    private func determineSenderType(email: Email) -> SenderType {
        let senderEmail = email.sender.email.lowercased()
        
        if TenantMailSettingsService.shared.isInternalEmail(senderEmail) {
            return .colleague
        }
        
        return .unknown
    }
    
    private func extractDates(from text: String) -> [Date] {
        var dates: [Date] = []
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        
        detector?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let date = match?.date, date > Date() {
                dates.append(date)
            }
        }
        
        return dates
    }
    
    private func extractMeetingDate(from text: String) -> Date? {
        let dates = extractDates(from: text)
        return dates.first
    }
    
    private func extractMeetingTitle(from subject: String) -> String {
        var title = subject
        
        // Rimuovi prefissi comuni
        let prefixes = ["FW:", "FWD:", "RE:", "I:", "R:"]
        for prefix in prefixes {
            if title.uppercased().hasPrefix(prefix) {
                title = String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Se contiene "riunione" o "meeting", usa il subject pulito
        if title.lowercased().contains("riunione") || title.lowercased().contains("meeting") {
            return title
        }
        
        return "Riunione: \(title)"
    }
    
    private func extractSummary(from text: String) -> String {
        // Prendi le prime 200 caratteri puliti
        let cleaned = text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleaned.count <= 200 {
            return cleaned
        }
        
        return String(cleaned.prefix(200)) + "..."
    }
    
    private func cleanTitle(_ subject: String) -> String {
        var title = subject
        
        let prefixes = ["FW:", "FWD:", "RE:", "I:", "R:"]
        for prefix in prefixes {
            while title.uppercased().hasPrefix(prefix) {
                title = String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        
        return title.isEmpty ? "Comunicazione interna" : title
    }
    
    private func extractProcedureCTA(from text: String) -> StudioNewsCTA? {
        let lower = text.lowercased()
        
        if lower.contains("scadenza") || lower.contains("entro") {
            let dates = extractDates(from: text)
            return StudioNewsCTA(
                title: "Adeguarsi alla nuova procedura",
                deadline: dates.first ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()),
                taskType: "procedure"
            )
        }
        
        return nil
    }
    
    private func requiresAction(body: String) -> Bool {
        let lower = body.lowercased()
        let actionKeywords = ["obbligatorio", "scadenza", "entro", "necessario", "richiesto", "da completare"]
        return actionKeywords.contains { lower.contains($0) }
    }
    
    private func createMeetingNews(email: Email, meetingDate: Date?) async {
        await MainActor.run {
            let newsItem = StudioNewsItem(
                title: cleanTitle(email.subject),
                summary: extractSummary(from: email.body ?? email.subject),
                createdAt: email.date,
                eventDate: meetingDate,
                icon: "calendar.badge.person.fill",
                sourceEmailId: email.id,
                sourceBody: email.body,
                sender: email.sender.displayName,
                cta: StudioNewsCTA(
                    title: "Confermare presenza",
                    deadline: meetingDate,
                    taskType: "meeting"
                )
            )
            
            addDirectNews(newsItem)
        }
    }
    
    /// Aggiunge una news direttamente al service
    @MainActor
    private func addDirectNews(_ item: StudioNewsItem) {
        StudioNewsService.shared.addNews(item)
    }
}
