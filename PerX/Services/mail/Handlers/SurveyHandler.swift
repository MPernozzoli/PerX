import Foundation
import CoreData

/// Handler per email relative a sopralluoghi e videoperizie
class SurveyHandler: BaseEmailHandler {
    
    private let taskManager = TaskManager.shared
    
    init() {
        super.init(
            handlerId: "survey",
            supportedCategories: [.surveyScheduled, .surveyReturned, .videocallScheduled]
        )
    }
    
    override func handle(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        switch email.category {
        case .surveyScheduled:
            return await handleSurveyScheduled(email, context: context, isUnread: isUnread)
        case .surveyReturned:
            return await handleSurveyReturned(email, context: context, isUnread: isUnread)
        case .videocallScheduled:
            return await handleVideocallScheduled(email, context: context, isUnread: isUnread)
        default:
            return nil
        }
    }
    
    // MARK: - Survey Scheduled
    
    private func handleSurveyScheduled(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[SurveyHandler] 📧 Sopralluogo fissato: \(email.originalEmail.subject)")
        
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        let sinistroId = extractSinistroReference(from: email)
        
        if let sinistroId = sinistroId,
           let sinistro = findSinistro(riferimento: sinistroId, context: context) {
            
            // Estrai data/ora appuntamento
            let (scheduledDate, address) = extractAppointmentDetails(from: email)
            
            // Aggiungi sempre entry nel diario (anche se email letta)
            var diarioText = "Sopralluogo fissato"
            if let date = scheduledDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                formatter.locale = Locale(identifier: "it_IT")
                diarioText += " per il \(formatter.string(from: date))"
            }
            
            sinistro.addDiarioEntry(DiarioEntry(
                testo: diarioText,
                tipo: .email
            ))
            
            // Genera task/aggiornamenti stato solo se email è unread
            if isUnread {
                // Aggiorna stato con validazione
                do {
                    try await StatoManager.shared.changeState(
                        for: sinistro,
                        to: .sopralluogoFissato,
                        context: context
                    )
                } catch {
                    print("[SurveyHandler] ⚠️ Impossibile aggiornare stato: \(error.localizedDescription)")
                }
                sinistro.sopralluogo = true
                
                if let date = scheduledDate {
                    sinistro.dataSopralluogo = date
                }
                
                // Crea task per il sopralluogo
                if let date = scheduledDate {
                    createSurveyTask(for: sinistroId, date: date, isVideocall: false)
                }
            }
            
            return EmailSurveyScheduled(
                emailId: email.originalEmail.id,
                sinistroId: sinistroId,
                direction: email.direction,
                scheduledDate: scheduledDate,
                address: address
            )
        }
        
        return EmailSurveyScheduled(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId,
            direction: email.direction,
            scheduledDate: nil,
            address: nil
        )
    }
    
    // MARK: - Survey Returned
    
    private func handleSurveyReturned(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[SurveyHandler] 📧 Sopralluogo restituito: \(email.originalEmail.subject)")
        
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        let sinistroId = extractSinistroReference(from: email)
        
        if let sinistroId = sinistroId,
           let sinistro = findSinistro(riferimento: sinistroId, context: context) {
            
            // Aggiungi sempre entry nel diario (anche se email letta)
            sinistro.addDiarioEntry(DiarioEntry(
                testo: "Sopralluogo restituito - necessario riprogrammare",
                tipo: .email
            ))
            
            // Genera task/aggiornamenti stato solo se email è unread
            if isUnread {
                // Aggiorna stato con validazione
                do {
                    try await StatoManager.shared.changeState(
                        for: sinistro,
                        to: .sopralluogoRestituito,
                        context: context
                    )
                } catch {
                    print("[SurveyHandler] ⚠️ Impossibile aggiornare stato: \(error.localizedDescription)")
                }
                
                // Crea task per riprogrammare (in background)
                let task = DailyTask(
                    title: "Riprogrammare sopralluogo - \(sinistroId)",
                    description: "Sopralluogo restituito, contattare assicurato",
                    type: .sinistroActivity,
                    sinistroID: sinistroId,
                    priority: 0.8,
                    deadline: Date().addingTimeInterval(24 * 60 * 60),
                    estimatedDuration: 600,
                    metadata: [
                        "emailId": AnyCodable(email.originalEmail.id),
                        "surveyReturned": AnyCodable(true)
                    ]
                )
                Task { @MainActor in
                    taskManager.addTask(task)
                }
            }
        }
        
        return EmailSurveyReturned(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId
        )
    }
    
    // MARK: - Videocall Scheduled
    
    private func handleVideocallScheduled(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[SurveyHandler] 📧 Videoperizia fissata: \(email.originalEmail.subject)")
        
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        let sinistroId = extractSinistroReference(from: email)
        
        if let sinistroId = sinistroId,
           let sinistro = findSinistro(riferimento: sinistroId, context: context) {
            
            // Estrai dettagli
            let (scheduledDate, _) = extractAppointmentDetails(from: email)
            let meetingLink = extractMeetingLink(from: email.originalEmail.body ?? "")
            
            // Aggiungi sempre entry nel diario (anche se email letta)
            var diarioText = "Videoperizia fissata"
            if let date = scheduledDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                formatter.locale = Locale(identifier: "it_IT")
                diarioText += " per il \(formatter.string(from: date))"
            }
            
            sinistro.addDiarioEntry(DiarioEntry(
                testo: diarioText,
                tipo: .email
            ))
            
            // Genera task/aggiornamenti stato solo se email è unread
            if isUnread {
                // Aggiorna stato con validazione
                do {
                    try await StatoManager.shared.changeState(
                        for: sinistro,
                        to: .videoperiziaFissata,
                        context: context
                    )
                } catch {
                    print("[SurveyHandler] ⚠️ Impossibile aggiornare stato: \(error.localizedDescription)")
                }
                sinistro.sopralluogo = false // È una videoperizia, non sopralluogo fisico
                
                if let date = scheduledDate {
                    sinistro.dataSopralluogo = date
                }
                
                // Crea task per la videoperizia
                if let date = scheduledDate {
                    createSurveyTask(for: sinistroId, date: date, isVideocall: true, meetingLink: meetingLink)
                }
            }
            
            return EmailVideocallScheduled(
                emailId: email.originalEmail.id,
                sinistroId: sinistroId,
                direction: email.direction,
                scheduledDate: scheduledDate,
                meetingLink: meetingLink
            )
        }
        
        return EmailVideocallScheduled(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId,
            direction: email.direction,
            scheduledDate: nil,
            meetingLink: nil
        )
    }
    
    // MARK: - Helpers
    
    private func extractAppointmentDetails(from email: ClassifiedEmail) -> (Date?, String?) {
        let body = email.originalEmail.body ?? ""
        let subject = email.originalEmail.subject
        let text = "\(subject) \(body)"
        
        var date: Date?
        var address: String?
        
        // Pattern per data/ora
        let datePatterns = [
            "(?:il|per il|giorno)\\s+(\\d{1,2})[/\\-](\\d{1,2})[/\\-](\\d{2,4})\\s+(?:ore|alle)?\\s*(\\d{1,2})[:\\.](\\d{2})",
            "(\\d{1,2})[/\\-](\\d{1,2})[/\\-](\\d{2,4})\\s+(?:ore|alle)?\\s*(\\d{1,2})[:\\.](\\d{2})"
        ]
        
        for pattern in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    // Estrai componenti
                    let components = (1...5).compactMap { i -> String? in
                        guard let range = Range(match.range(at: i), in: text) else { return nil }
                        return String(text[range])
                    }
                    
                    if components.count >= 5 {
                        var calendar = Calendar.current
                        calendar.locale = Locale(identifier: "it_IT")
                        
                        var year = Int(components[2]) ?? 2024
                        if year < 100 { year += 2000 }
                        
                        var dateComponents = DateComponents()
                        dateComponents.day = Int(components[0])
                        dateComponents.month = Int(components[1])
                        dateComponents.year = year
                        dateComponents.hour = Int(components[3])
                        dateComponents.minute = Int(components[4])
                        
                        date = calendar.date(from: dateComponents)
                        break
                    }
                }
            }
        }
        
        // Pattern per indirizzo
        let addressPattern = "(?:indirizzo|presso|via|piazza)[:\\s]+(.+?)(?:\\n|,\\s*(?:ore|il)|$)"
        if let regex = try? NSRegularExpression(pattern: addressPattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let addrRange = Range(match.range(at: 1), in: text) {
                address = String(text[addrRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return (date, address)
    }
    
    private func extractMeetingLink(from body: String) -> String? {
        let patterns = [
            "(https?://[a-zA-Z0-9.-]+\\.zoom\\.us/[^\\s]+)",
            "(https?://teams\\.microsoft\\.com/[^\\s]+)",
            "(https?://meet\\.google\\.com/[^\\s]+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(body.startIndex..<body.endIndex, in: body)
                if let match = regex.firstMatch(in: body, options: [], range: range),
                   let linkRange = Range(match.range(at: 1), in: body) {
                    return String(body[linkRange])
                }
            }
        }
        
        return nil
    }
    
    private func createSurveyTask(for sinistroId: String, date: Date, isVideocall: Bool, meetingLink: String? = nil) {
        let typeText = isVideocall ? "Videoperizia" : "Sopralluogo"
        
        var metadata: [String: AnyCodable] = [
            "survey": AnyCodable(true),
            "isVideocall": AnyCodable(isVideocall)
        ]
        
        if let link = meetingLink {
            metadata["meetingLink"] = AnyCodable(link)
        }
        
        let task = DailyTask(
            title: "\(typeText) - \(sinistroId)",
            description: "Eseguire \(typeText.lowercased()) programmato",
            type: .sinistroActivity,
            sinistroID: sinistroId,
            priority: 0.85,
            deadline: date,
            estimatedDuration: isVideocall ? 1800 : 3600, // 30 min video, 1h sopralluogo
            metadata: metadata
        )
        
        // Task creation delegata a ClaimEngine tramite evento
        // Task { @MainActor in
        //     taskManager.addTask(task)
        // }
    }
}
