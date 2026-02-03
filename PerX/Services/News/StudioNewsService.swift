import Foundation
import Combine

@MainActor
final class StudioNewsService: ObservableObject {
    static let shared = StudioNewsService()
    
    @Published private(set) var news: [StudioNewsItem] = []
    
    private let storageKey = "studioNewsItems"
    private let processedEmailsKey = "studioNewsProcessedEmails"
    private let processedBirthdaysKey = "studioNewsProcessedBirthdays"
    private let maxItems = 20
    private let taskManager = TaskManager.shared
    
    /// Set di email ID già processate (per evitare duplicati da handler multipli)
    private var processedEmailIds: Set<String> = []
    
    /// Set di compleanni già notificati oggi (email_YYYY-MM-DD)
    private var processedBirthdays: Set<String> = []
    
    private init() {
        // Ritarda load e purgeExpired per evitare modifiche @Published durante la costruzione della view
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms delay
            self?.load()
            self?.purgeExpired()
            
            // Check compleanni all'avvio
            await self?.checkBirthdays()
            
            // Purge periodico ogni 5 minuti e check compleanni
            self?.startPeriodicTasks()
        }
    }
    
    private func startPeriodicTasks() {
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minuti
                self?.purgeExpired()
                await self?.checkBirthdays()
            }
        }
    }
    
    // MARK: - Birthday Management
    
    /// Controlla se ci sono compleanni oggi e crea le news
    func checkBirthdays() async {
        let profileService = UserProfileService.shared
        
        // Assicurati che i profili siano caricati
        await profileService.refreshAllProfiles()
        
        let birthdaysToday = profileService.birthdaysToday()
        let today = birthdayKeyDate()
        
        for profile in birthdaysToday {
            let key = "\(profile.email)_\(today)"
            
            // Salta se già processato oggi
            guard !processedBirthdays.contains(key) else { continue }
            
            // Crea la news di compleanno
            let birthdayNews = StudioNewsItem.birthday(
                userName: profile.displayName,
                userEmail: profile.email
            )
            
            add(birthdayNews)
            processedBirthdays.insert(key)
            
            print("[StudioNewsService] 🎂 Compleanno aggiunto: \(profile.displayName)")
        }
        
        // Pulisci i compleanni vecchi (più di 2 giorni fa)
        cleanOldBirthdays()
        saveBirthdays()
    }
    
    private func birthdayKeyDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    private func cleanOldBirthdays() {
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        processedBirthdays = processedBirthdays.filter { key in
            guard let dateStr = key.components(separatedBy: "_").last,
                  let date = formatter.date(from: dateStr) else { return false }
            return Calendar.current.dateComponents([.day], from: date, to: today).day ?? 0 < 2
        }
    }
    
    private func saveBirthdays() {
        if let data = try? JSONEncoder().encode(processedBirthdays) {
            UserDefaults.standard.set(data, forKey: processedBirthdaysKey)
        }
    }
    
    private func loadBirthdays() {
        guard let data = UserDefaults.standard.data(forKey: processedBirthdaysKey),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) else { return }
        processedBirthdays = decoded
    }
    
    func newsForDashboard(limit: Int = 4) -> [StudioNewsItem] {
        // Non chiamare purgeExpired qui - causerebbe "Publishing changes from within view updates"
        // Il purge viene fatto in background dall'init e periodicamente
        let validNews = news.filter { !$0.isExpired }
        
        // I compleanni hanno priorità e vengono mostrati per primi
        let birthdays = validNews.filter { $0.isBirthday }
        let others = validNews.filter { !$0.isBirthday }
        
        return (birthdays + others).prefix(limit).map { $0 }
    }
    
    /// Ottiene i compleanni di oggi
    func birthdaysToday() -> [StudioNewsItem] {
        news.filter { $0.isBirthday && !$0.isExpired }
    }
    
    @discardableResult
    func createNewsIfEligible(
        email: Email,
        entry: DiarioEntry,
        analysis: CommunicationAnalysisResult
    ) -> StudioNewsItem? {
        // Check preventivo: email già processata da altro handler?
        if processedEmailIds.contains(email.id) {
            print("[StudioNewsService] ⚠️ Email già processata: \(email.id)")
            return nil
        }
        
        guard shouldGenerateNews(from: email, analysis: analysis) else {
            return nil
        }
        
        // Marca come processata
        processedEmailIds.insert(email.id)
        saveProcessedEmails()
        
        let summary = entry.riassunto ?? entry.contenutoCompleto ?? entry.titolo ?? "Comunicazione interna"
        let icon = icon(for: email, body: entry.contenutoCompleto ?? entry.riassunto ?? "")
        let eventDate = analysis.extractedData.dates.first(where: { $0 > Date().addingTimeInterval(-3600) })
        let cta = ctaIfNeeded(from: email, body: entry.contenutoCompleto ?? "", eventDate: eventDate)
        
        let item = StudioNewsItem(
            title: cleanedTitle(email.subject),
            summary: summary,
            createdAt: email.date,
            eventDate: eventDate,
            icon: icon,
            sourceEmailId: email.id,
            sourceBody: entry.contenutoCompleto ?? email.body,
            sender: email.sender.displayName,
            cta: cta
        )
        
        add(item)
        return item
    }
    
    func scheduleCTA(for news: StudioNewsItem) {
        guard let cta = news.cta else { return }
        
        let task = DailyTask(
            title: cta.title,
            description: news.summary,
            type: .aiGenerated,
            sinistroID: nil,
            priority: 0.6,
            deadline: cta.deadline ?? news.eventDate,
            estimatedDuration: 10 * 60,
            metadata: [
                "newsId": AnyCodable(news.id.uuidString),
                "sourceEmailId": AnyCodable(news.sourceEmailId ?? ""),
                "newsTitle": AnyCodable(news.title)
            ],
            isTimeSensitive: news.eventDate != nil,
            fixedDateTime: news.eventDate
        )
        
        taskManager.addTask(task)
    }
    
    // MARK: - Public
    
    /// Aggiunge una news direttamente (usato dagli handler email)
    func addNews(_ item: StudioNewsItem) {
        add(item)
    }
    
    // MARK: - Private
    
    private func add(_ item: StudioNewsItem) {
        // Deduplicazione per sourceEmailId (priorità) o per id
        if let emailId = item.sourceEmailId, !emailId.isEmpty {
            if news.contains(where: { $0.sourceEmailId == emailId }) {
                print("[StudioNewsService] ⚠️ Duplicato ignorato per email: \(emailId)")
                return
            }
        }
        
        // Deduplicazione per titolo + data (stessa news da fonti diverse)
        let isDuplicate = news.contains { existing in
            existing.title == item.title &&
            Calendar.current.isDate(existing.createdAt, inSameDayAs: item.createdAt)
        }
        if isDuplicate {
            print("[StudioNewsService] ⚠️ Duplicato ignorato per titolo: \(item.title)")
            return
        }
        
        news.removeAll { $0.id == item.id }
        news.insert(item, at: 0)
        if news.count > maxItems {
            news = Array(news.prefix(maxItems))
        }
        save()
        print("[StudioNewsService] ✅ News aggiunta: \(item.title)")
    }
    
    private func purgeExpired() {
        let before = news.count
        news.removeAll { $0.isExpired }
        if news.count != before {
            save()
        }
    }
    
    private func shouldGenerateNews(from email: Email, analysis: CommunicationAnalysisResult) -> Bool {
        let senderEmail = email.sender.email.lowercased()
        let isInternalSender = senderEmail.contains("@actsrl.it") ||
        senderEmail.contains("@allconsulting.org") ||
        [.companyGeneric, .partner, .teamLeader, .secretary, .colleague].contains(analysis.context.senderType)
        
        let recipientsCount = email.recipients.count + (email.cc?.count ?? 0)
        let hasSinistroRef = !(email.claimNumber?.isEmpty ?? true)
        
        let lowerSubject = email.subject.lowercased()
        let lowerBody = (email.body ?? "").lowercased()
        let keywords = [
            "newsletter", "aggiornamento", "avviso", "comunicazione interna",
            "cena", "evento", "riunione", "meeting", "formazione",
            "chiusura", "ferie", "auguri", "festa", "invito", "workshop"
        ]
        let matchesKeyword = keywords.contains { lowerSubject.contains($0) || lowerBody.contains($0) }
        let intentMatches = analysis.intent == .noAction || analysis.intent == .acknowledgment || analysis.intent == .genericAction
        
        return isInternalSender && recipientsCount >= 3 && !hasSinistroRef && matchesKeyword && intentMatches
    }
    
    private func icon(for email: Email, body: String) -> String {
        let text = (email.subject + " " + body).lowercased()
        if text.contains("cena") || text.contains("aperitivo") {
            return "fork.knife"
        }
        if text.contains("riunione") || text.contains("meeting") {
            return "person.2"
        }
        if text.contains("newsletter") {
            return "newspaper"
        }
        if text.contains("formazione") || text.contains("corso") {
            return "book"
        }
        if text.contains("chiusura") || text.contains("ferie") {
            return "calendar"
        }
        return "megaphone"
    }
    
    private func ctaIfNeeded(from email: Email, body: String, eventDate: Date?) -> StudioNewsCTA? {
        let text = (email.subject + " " + body).lowercased()
        
        if text.contains("conferma") && text.contains("presenza") {
            return StudioNewsCTA(
                title: "Confermare presenza",
                deadline: eventDate ?? Calendar.current.date(byAdding: .day, value: 2, to: Date()),
                taskType: "meeting"
            )
        }
        
        if text.contains("iscrizione") || text.contains("registrazione") {
            return StudioNewsCTA(
                title: "Registrarsi all'evento",
                deadline: eventDate ?? Calendar.current.date(byAdding: .day, value: 3, to: Date()),
                taskType: "meeting"
            )
        }
        
        if text.contains("richiesta") && text.contains("riscontro") {
            return StudioNewsCTA(
                title: "Rispondere alla comunicazione",
                deadline: eventDate ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                taskType: "generic"
            )
        }
        
        return nil
    }
    
    private func cleanedTitle(_ subject: String) -> String {
        let trimmed = subject.replacingOccurrences(of: "FW:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "FWD:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "RE:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Notizia dello studio" : trimmed
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(news) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([StudioNewsItem].self, from: data) else { return }
        news = decoded
        
        // Carica email e compleanni processati
        loadProcessedEmails()
        loadBirthdays()
    }
    
    private func loadProcessedEmails() {
        guard let data = UserDefaults.standard.data(forKey: processedEmailsKey),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) else { return }
        
        // Mantieni solo le ultime 500 per evitare crescita infinita
        if decoded.count > 500 {
            processedEmailIds = Set(decoded.suffix(500))
            saveProcessedEmails()
        } else {
            processedEmailIds = decoded
        }
    }
    
    private func saveProcessedEmails() {
        if let encoded = try? JSONEncoder().encode(processedEmailIds) {
            UserDefaults.standard.set(encoded, forKey: processedEmailsKey)
        }
    }
}

