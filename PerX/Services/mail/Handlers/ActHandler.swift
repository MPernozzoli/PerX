import Foundation
import CoreData

/// Handler per email relative agli atti (da firmare e firmati)
class ActHandler: BaseEmailHandler {
    
    private let taskManager = TaskManager.shared
    private let fileTagManager = FileTagManager.shared
    
    init() {
        super.init(
            handlerId: "act",
            supportedCategories: [.actSent, .actReceived]
        )
    }
    
    override func handle(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        switch email.category {
        case .actSent:
            return await handleActSent(email, context: context, isUnread: isUnread)
        case .actReceived:
            return await handleActReceived(email, context: context, isUnread: isUnread)
        default:
            return nil
        }
    }
    
    // MARK: - Act Sent (Atto da firmare inviato)
    
    private func handleActSent(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[ActHandler] 📤 Atto inviato: \(email.originalEmail.subject)")
        
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        let sinistroId = extractSinistroReference(from: email)
        
        if let sinistroId = sinistroId,
           let sinistro = findSinistro(riferimento: sinistroId, context: context) {
            
            // Determina tipo atto
            let actType = extractActType(from: email.originalEmail.subject + " " + (email.originalEmail.body ?? ""))
            
            // Aggiungi sempre entry nel diario (anche se email letta)
            sinistro.addDiarioEntry(DiarioEntry(
                testo: "Atto \(actType ?? "di liquidazione") inviato per firma",
                tipo: .email
            ))
            
            // Genera task/aggiornamenti stato solo se email è unread
            if isUnread {
                // Verifica se è perizia senza atto (es. Zurich concordata senza divisione SI/VSU)
                let isPeriziaSenzaAtto = sinistro.isPeriziaSenzaAtto
                
                // Determina lo stato target: "esito comunicato" per perizie senza atto, "atto inviato" altrimenti
                let targetState: StatoManager.StatoSinistro = isPeriziaSenzaAtto ? .esitoComunicato : .attoInviato
                
                // Aggiorna stato con validazione
                // Nota: dataInvioAtto viene sempre aggiornata in changeState per attoInviato/esitoComunicato
                do {
                    try await StatoManager.shared.changeState(
                        for: sinistro,
                        to: targetState,
                        context: context
                    )
                    print("[ActHandler] ✅ Stato aggiornato a \(targetState.descrizione) per sinistro \(sinistroId)")
                } catch {
                    print("[ActHandler] ⚠️ Impossibile aggiornare stato: \(error.localizedDescription)")
                    // Continua comunque con il resto della logica
                }
                
                // Crea task per monitorare la restituzione (in background)
                let task = DailyTask(
                    title: "Sollecitare atto - \(sinistroId)",
                    description: "Verificare restituzione atto firmato",
                    type: .sinistroActivity,
                    sinistroID: sinistroId,
                    priority: 0.6,
                    deadline: Date().addingTimeInterval(7 * 24 * 60 * 60), // 7 giorni
                    estimatedDuration: 300,
                    metadata: [
                        "emailId": AnyCodable(email.originalEmail.id),
                        "actSent": AnyCodable(true),
                        "actType": AnyCodable(actType ?? "")
                    ]
                )
                // Task creation delegata a ClaimEngine tramite evento
                // Task { @MainActor in
                //     taskManager.addTask(task)
                // }
            }
            
            return EmailActToSignSent(
                emailId: email.originalEmail.id,
                sinistroId: sinistroId,
                actType: actType,
                recipients: email.originalEmail.recipients.map { $0.email }
            )
        }
        
        return EmailActToSignSent(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId,
            actType: nil,
            recipients: email.originalEmail.recipients.map { $0.email }
        )
    }
    
    // MARK: - Act Received (Atto firmato ricevuto)
    
    private func handleActReceived(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[ActHandler] 📥 Atto firmato ricevuto: \(email.originalEmail.subject)")
        
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        let sinistroId = extractSinistroReference(from: email)
        
        if let sinistroId = sinistroId,
           let sinistro = findSinistro(riferimento: sinistroId, context: context) {
            
            // Determina tipo atto
            let actType = extractActType(from: email.originalEmail.subject + " " + (email.originalEmail.body ?? ""))
            
            // Aggiungi sempre entry nel diario (anche se email letta)
            sinistro.addDiarioEntry(DiarioEntry(
                testo: "Atto \(actType ?? "di liquidazione") ricevuto firmato",
                tipo: .email
            ))
            
            // Aggiorna stato solo se email non letta
            if isUnread {
                // Aggiorna stato con validazione
                do {
                    try await StatoManager.shared.changeState(
                        for: sinistro,
                        to: .attoRicevutoSottoscritto,
                        context: context
                    )
                    sinistro.concordata = true
                    print("[ActHandler] ✅ Stato aggiornato a 'atto ricevuto sottoscritto' per sinistro \(sinistroId)")
                } catch {
                    print("[ActHandler] ⚠️ Impossibile aggiornare stato: \(error.localizedDescription)")
                    // Continua comunque con il resto della logica
                }
                
                // Crea task per chiusura pratica
                let task = DailyTask(
                    title: "Chiudere pratica - \(sinistroId)",
                    description: "Atto firmato ricevuto, procedere con chiusura",
                    type: .sinistroActivity,
                    sinistroID: sinistroId,
                    priority: 0.75,
                    deadline: Date().addingTimeInterval(24 * 60 * 60),
                    estimatedDuration: 900,
                    metadata: [
                        "emailId": AnyCodable(email.originalEmail.id),
                        "actReceived": AnyCodable(true),
                        "actType": AnyCodable(actType ?? "")
                    ]
                )
                // Task creation delegata a ClaimEngine tramite evento
                // Task { @MainActor in
                //     taskManager.addTask(task)
                // }
            }
            
            // Prepara lista URL allegati (placeholder, il download avverrà separatamente)
            let attachmentURLs: [URL] = []
            
            return EmailSignedActReceived(
                emailId: email.originalEmail.id,
                sinistroId: sinistroId,
                actType: actType,
                attachmentURLs: attachmentURLs
            )
        }
        
        return EmailSignedActReceived(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId,
            actType: nil,
            attachmentURLs: []
        )
    }
    
    // MARK: - Helpers
    
    private func extractActType(from text: String) -> String? {
        let lowerText = text.lowercased()
        
        if lowerText.contains("liquidazione") || lowerText.contains("quietanza") {
            return "liquidazione"
        }
        if lowerText.contains("accertamento") {
            return "accertamento"
        }
        if lowerText.contains("transazione") {
            return "transazione"
        }
        if lowerText.contains("rinuncia") {
            return "rinuncia"
        }
        
        return nil
    }
}

