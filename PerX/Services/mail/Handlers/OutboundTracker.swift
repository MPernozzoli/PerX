import Foundation
import CoreData

/// Handler specializzato per tracciare tutte le email in uscita
/// Registra nel diario e gestisce le email inviate (esiti, comunicazioni, ecc.)
class OutboundTracker: BaseEmailHandler {
    
    private let taskManager = TaskManager.shared
    
    init() {
        super.init(
            handlerId: "outbound_tracker",
            supportedCategories: [.outcomeSent, .genericCommunication]
        )
    }
    
    override func canHandle(_ email: ClassifiedEmail) -> Bool {
        // Gestisce solo email in uscita che non sono gestite da altri handler
        return email.direction == .outbound && 
               (email.category == .outcomeSent || email.category == .genericCommunication)
    }
    
    override func handle(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        switch email.category {
        case .outcomeSent:
            return await handleOutcomeSent(email, context: context, isUnread: isUnread)
        case .genericCommunication:
            return await handleGenericOutbound(email, context: context, isUnread: isUnread)
        default:
            return nil
        }
    }
    
    // MARK: - Outcome Sent
    
    private func handleOutcomeSent(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[OutboundTracker] 📤 Esito comunicato: \(email.originalEmail.subject)")
        
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        let sinistroId = extractSinistroReference(from: email)
        
        if let sinistroId = sinistroId,
           let sinistro = findSinistro(riferimento: sinistroId, context: context) {
            
            // Estrai tipo di esito
            let outcomeType = extractOutcomeType(from: email)
            
            // Aggiungi sempre entry nel diario (anche se email letta)
            var diarioText = "Esito comunicato"
            if let type = outcomeType {
                diarioText += " (\(type))"
            }
            
            sinistro.addDiarioEntry(DiarioEntry(
                testo: diarioText,
                tipo: .email
            ))
            
            // Aggiorna stato solo se email è unread
            if isUnread {
                do {
                    try await StatoManager.shared.changeState(
                        for: sinistro,
                        to: .esitoComunicato,
                        context: context
                    )
                } catch {
                    print("[OutboundTracker] ⚠️ Impossibile aggiornare stato: \(error.localizedDescription)")
                }
            }
            
            return EmailOutcomeSent(
                emailId: email.originalEmail.id,
                sinistroId: sinistroId,
                outcomeType: outcomeType,
                recipients: email.originalEmail.recipients.map { $0.email }
            )
        }
        
        return EmailOutcomeSent(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId,
            outcomeType: nil,
            recipients: email.originalEmail.recipients.map { $0.email }
        )
    }
    
    // MARK: - Generic Outbound
    
    private func handleGenericOutbound(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[OutboundTracker] 📤 Email inviata: \(email.originalEmail.subject)")
        
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        let sinistroId = extractSinistroReference(from: email)
        
        if let sinistroId = sinistroId,
           let sinistro = findSinistro(riferimento: sinistroId, context: context) {
            
            // Determina tipo di comunicazione per il diario
            let commType = categorizeOutboundCommunication(email)
            
            // Aggiungi entry nel diario
            sinistro.addDiarioEntry(DiarioEntry(
                testo: "Email inviata: \(commType)",
                tipo: .email
            ))
        }
        
        return EmailGenericCommunicationReceived(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId,
            direction: .outbound,
            subject: email.originalEmail.subject,
            sender: email.originalEmail.sender.email,
            hasAttachments: email.hasAttachments
        )
    }
    
    // MARK: - Helpers
    
    private func extractOutcomeType(from email: ClassifiedEmail) -> String? {
        let subject = email.originalEmail.subject.lowercased()
        let body = (email.originalEmail.body ?? "").lowercased()
        
        if subject.contains("liquidazione") || body.contains("liquidazione") {
            return "liquidazione"
        }
        if subject.contains("accertamento") || body.contains("accertamento") {
            return "accertamento"
        }
        if subject.contains("negativo") || body.contains("non indennizzabile") {
            return "esito negativo"
        }
        if subject.contains("parziale") {
            return "liquidazione parziale"
        }
        if subject.contains("totale") {
            return "liquidazione totale"
        }
        
        return nil
    }
    
    private func categorizeOutboundCommunication(_ email: ClassifiedEmail) -> String {
        let subject = email.originalEmail.subject.lowercased()
        
        if subject.contains("richiesta") {
            return "Richiesta informazioni"
        }
        if subject.contains("conferma") {
            return "Conferma"
        }
        if subject.contains("aggiornamento") {
            return "Aggiornamento stato"
        }
        if subject.contains("risposta") || subject.contains("re:") {
            return "Risposta"
        }
        if email.hasAttachments {
            return "Invio documentazione"
        }
        
        return "Comunicazione generica"
    }
}

// MARK: - Email Tracking Service

/// Servizio per tracciare statistiche email in uscita
@MainActor
class OutboundEmailStats: ObservableObject {
    static let shared = OutboundEmailStats()
    
    @Published private(set) var totalSent: Int = 0
    @Published private(set) var sentByType: [String: Int] = [:]
    @Published private(set) var sentBySinistro: [String: Int] = [:]
    @Published private(set) var lastSentDate: Date?
    
    private init() {}
    
    /// Registra un'email inviata
    func trackSent(type: String, sinistroId: String?) {
        totalSent += 1
        sentByType[type, default: 0] += 1
        
        if let id = sinistroId {
            sentBySinistro[id, default: 0] += 1
        }
        
        lastSentDate = Date()
    }
    
    /// Resetta le statistiche
    func reset() {
        totalSent = 0
        sentByType.removeAll()
        sentBySinistro.removeAll()
        lastSentDate = nil
    }
    
    /// Ottiene statistiche per un sinistro
    func getSentCount(for sinistroId: String) -> Int {
        return sentBySinistro[sinistroId] ?? 0
    }
}

