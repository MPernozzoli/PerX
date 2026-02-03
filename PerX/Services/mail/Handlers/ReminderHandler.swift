import Foundation
import CoreData

/// Handler per solleciti ricevuti e inviati
class ReminderHandler: BaseEmailHandler {
    
    private let taskManager = TaskManager.shared
    
    init() {
        super.init(
            handlerId: "reminder",
            supportedCategories: [.reminderReceived, .reminderSent]
        )
    }
    
    override func handle(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        switch email.category {
        case .reminderReceived:
            return await handleReminderReceived(email, context: context, isUnread: isUnread)
        case .reminderSent:
            return handleReminderSent(email, context: context, isUnread: isUnread)
        default:
            return nil
        }
    }
    
    // MARK: - Reminder Received
    
    private func handleReminderReceived(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[ReminderHandler] 📧 Sollecito ricevuto da \(email.senderType): \(email.originalEmail.subject)")
        
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        let sinistroId = extractSinistroReference(from: email)
        
        if let sinistroId = sinistroId,
           let sinistro = findSinistro(riferimento: sinistroId, context: context) {
            
            // Converti EmailSenderType in TipoMittenteSollecito
            let tipoMittente = convertToTipoMittenteSollecito(email.senderType)
            
            // Aggiorna contatore, data e tipo mittente solleciti ricevuti (consolidati sul modello)
            sinistro.registraSollecitoRicevuto(tipoMittente: tipoMittente)
            
            // Aggiungi sempre nota nel diario (anche se email letta)
            sinistro.addDiarioEntry(DiarioEntry(
                testo: "Sollecito ricevuto da \(senderTypeDescription(email.senderType))",
                tipo: .email
            ))
            
            // Task creation delegata a ClaimEngine tramite evento pubblicato sopra
            // ClaimEngine processerà l'evento e creerà la task se necessario
            
            saveContext(context)
        }
        
        return EmailReminderReceived(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId,
            senderType: email.senderType,
            subject: email.originalEmail.subject
        )
    }
    
    // MARK: - Reminder Sent
    
    private func handleReminderSent(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) -> (any EmailEvent)? {
        print("[ReminderHandler] 📤 Sollecito inviato: \(email.originalEmail.subject)")
        
        // Applica tag di categoria (async call from sync context)
        Task { @MainActor in
            EmailTagManager.shared.applyAutomaticTag(
                category: email.category,
                toEmailId: email.originalEmail.id,
                confidence: email.confidence,
                sinistroId: email.sinistroId
            )
        }
        
        let sinistroId = extractSinistroReference(from: email)
        
        if let sinistroId = sinistroId,
           let sinistro = findSinistro(riferimento: sinistroId, context: context) {
            
            // Aggiorna contatore e data solleciti inviati (consolidati sul modello)
            sinistro.registraSollecitoInviato()
            
            // Determina tipo di sollecito
            let reminderType = extractReminderType(from: email.originalEmail.subject)
            
            // Determina tipo di destinatario (agenzia o broker)
            let recipientType = determineRecipientType(from: email.originalEmail.recipients)
            let recipientDescription = recipientType != nil ? senderTypeDescription(recipientType!) : "destinatario"
            
            // Aggiungi sempre nota nel diario (anche se email letta)
            sinistro.addDiarioEntry(DiarioEntry(
                testo: "Sollecito \(reminderType) inviato a \(recipientDescription)",
                tipo: .email
            ))
            
            saveContext(context)
        }
        
        // Estrai destinatari
        let recipients = email.originalEmail.recipients.map { $0.email }
        
        // Determina tipo di destinatario
        let recipientType = determineRecipientType(from: email.originalEmail.recipients)
        
        return EmailReminderSent(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId,
            recipients: recipients,
            reminderType: extractReminderType(from: email.originalEmail.subject),
            recipientType: recipientType
        )
    }
    
    // MARK: - Helpers
    
    // createUrgentResponseTask RIMOSSO - task creation delegata a ClaimEngine
    // ClaimEngine riceve eventi tramite UnifiedEventBus e decide se/come creare task
    // con sistema goal/invalidation e standardizzazione titoli
    
    private func senderTypeDescription(_ type: EmailSenderType) -> String {
        switch type {
        case .insured: return "assicurato"
        case .agency: return "agenzia"
        case .company: return "compagnia"
        case .liquidator: return "liquidatore"
        case .broker: return "broker"
        case .studio: return "studio"
        default: return "mittente"
        }
    }
    
    private func extractReminderType(from subject: String) -> String {
        let lowerSubject = subject.lowercased()
        
        if lowerSubject.contains("documentazione") || lowerSubject.contains("documenti") {
            return "documentazione"
        }
        if lowerSubject.contains("atto") || lowerSubject.contains("firma") {
            return "atto"
        }
        if lowerSubject.contains("perizia") || lowerSubject.contains("relazione") {
            return "perizia"
        }
        if lowerSubject.contains("esito") || lowerSubject.contains("risposta") {
            return "risposta"
        }
        
        return "generico"
    }
    
    private func determineRecipientType(from recipients: [Contact]) -> EmailSenderType? {
        // Analizza i destinatari per determinare se è agenzia o broker
        for recipient in recipients {
            let email = recipient.email.lowercased()
            let domain = email.components(separatedBy: "@").last ?? ""
            
            // Pattern per agenzia
            let agencyPatterns = ["agenzia", "agency", "assicurazioni"]
            for pattern in agencyPatterns {
                if domain.contains(pattern) {
                    return .agency
                }
            }
            
            // Pattern per broker
            let brokerPatterns = ["broker", "intermediario", "intermediazione"]
            for pattern in brokerPatterns {
                if domain.contains(pattern) {
                    return .broker
                }
            }
        }
        
        // Se non trovato nel dominio, prova a cercare nel nome del destinatario
        for recipient in recipients {
            let name = recipient.name?.lowercased() ?? ""
            if name.contains("agenzia") || name.contains("agency") {
                return .agency
            }
            if name.contains("broker") || name.contains("intermediario") {
                return .broker
            }
        }
        
        return nil
    }
    
    /// Converte EmailSenderType in TipoMittenteSollecito per il calcolo priorità
    private func convertToTipoMittenteSollecito(_ senderType: EmailSenderType) -> TipoMittenteSollecito {
        switch senderType {
        case .company, .liquidator:
            return .liquidatoreCompagnia
        case .studio:
            return .studio
        case .agency, .broker:
            return .agenzia
        case .insured:
            return .assicurato
        default:
            return .unknown
        }
    }
}

