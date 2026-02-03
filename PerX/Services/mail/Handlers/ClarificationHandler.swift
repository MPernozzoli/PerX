import Foundation
import CoreData

/// Handler per richieste di chiarimenti
class ClarificationHandler: BaseEmailHandler {
    
    private let taskManager = TaskManager.shared
    
    init() {
        super.init(
            handlerId: "clarification",
            supportedCategories: [.clarificationRequest]
        )
    }
    
    override func handle(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[ClarificationHandler] 📧 Richiesta chiarimenti: \(email.originalEmail.subject)")
        
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        let sinistroId = extractSinistroReference(from: email)
        
        if let sinistroId = sinistroId,
           let sinistro = findSinistro(riferimento: sinistroId, context: context) {
            
            // Estrai argomento dei chiarimenti
            let topic = extractClarificationTopic(from: email)
            
            // Aggiungi sempre entry nel diario (anche se email letta)
            let direction = email.direction == .inbound ? "ricevuta" : "inviata"
            var diarioText = "Richiesta chiarimenti \(direction)"
            if let topic = topic {
                diarioText += " su \(topic)"
            }
            
            sinistro.addDiarioEntry(DiarioEntry(
                testo: diarioText,
                tipo: .email
            ))
            
            // Genera task solo se email è unread e è una richiesta ricevuta
            if isUnread && email.direction == .inbound {
                let priority = calculatePriority(senderType: email.senderType)
                
                let task = DailyTask(
                    title: "Rispondere a chiarimenti - \(sinistroId)",
                    description: "Chiarimenti richiesti da \(senderDescription(email.senderType))" + (topic.map { " su \($0)" } ?? ""),
                    type: .sinistroActivity,
                    sinistroID: sinistroId,
                    priority: priority,
                    deadline: Date().addingTimeInterval(calculateDueTime(senderType: email.senderType)),
                    estimatedDuration: 1200,
                    metadata: [
                        "emailId": AnyCodable(email.originalEmail.id),
                        "clarification": AnyCodable(true),
                        "topic": AnyCodable(topic ?? ""),
                        "senderType": AnyCodable(email.senderType.rawValue)
                    ]
                )
                // Task creation delegata a ClaimEngine tramite evento
                // Task { @MainActor in
                //     taskManager.addTask(task)
                // }
            }
            
            saveContext(context)
            
            return EmailClarificationRequested(
                emailId: email.originalEmail.id,
                sinistroId: sinistroId,
                direction: email.direction,
                requestedBy: email.senderType,
                topic: topic
            )
        }
        
        return EmailClarificationRequested(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId,
            direction: email.direction,
            requestedBy: email.senderType,
            topic: nil
        )
    }
    
    // MARK: - Helpers
    
    private func extractClarificationTopic(from email: ClassifiedEmail) -> String? {
        let body = email.originalEmail.body ?? ""
        let subject = email.originalEmail.subject
        let text = "\(subject) \(body)".lowercased()
        
        // Pattern per argomenti comuni
        let topics = [
            ("importo", "importo/valutazione"),
            ("danno", "natura del danno"),
            ("copertura", "copertura assicurativa"),
            ("polizza", "condizioni di polizza"),
            ("perizia", "dettagli perizia"),
            ("foto", "documentazione fotografica"),
            ("preventivo", "preventivo/offerta"),
            ("riparazione", "riparazione/sostituzione"),
            ("franchigia", "franchigia"),
            ("indennizzo", "calcolo indennizzo")
        ]
        
        for (keyword, topic) in topics {
            if text.contains(keyword) {
                return topic
            }
        }
        
        return nil
    }
    
    private func calculatePriority(senderType: EmailSenderType) -> Double {
        switch senderType {
        case .company, .liquidator:
            return 0.85  // Alta priorità per compagnia/liquidatore
        case .agency:
            return 0.75
        case .insured:
            return 0.65
        default:
            return 0.6
        }
    }
    
    private func calculateDueTime(senderType: EmailSenderType) -> TimeInterval {
        switch senderType {
        case .company, .liquidator:
            return 4 * 60 * 60  // 4 ore
        case .agency:
            return 8 * 60 * 60  // 8 ore
        default:
            return 24 * 60 * 60 // 24 ore
        }
    }
    
    private func senderDescription(_ type: EmailSenderType) -> String {
        switch type {
        case .company: return "compagnia"
        case .liquidator: return "liquidatore"
        case .agency: return "agenzia"
        case .insured: return "assicurato"
        case .broker: return "broker"
        case .studio: return "studio"
        default: return "mittente"
        }
    }
}

