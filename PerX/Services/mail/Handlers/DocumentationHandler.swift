import Foundation
import CoreData

/// Handler per email relative alla documentazione
/// Gestisce sia richieste che ricezione di documentazione
class DocumentationHandler: BaseEmailHandler {
    
    private let taskManager = TaskManager.shared
    
    init() {
        super.init(
            handlerId: "documentation",
            supportedCategories: [.documentationRequest, .documentationReceived]
        )
    }
    
    override func handle(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        switch email.category {
        case .documentationRequest:
            return await handleDocumentationRequest(email, context: context, isUnread: isUnread)
        case .documentationReceived:
            return await handleDocumentationReceived(email, context: context, isUnread: isUnread)
        default:
            return nil
        }
    }
    
    // MARK: - Documentation Request
    
    private func handleDocumentationRequest(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[DocHandler] 📧 Richiesta documentazione: \(email.originalEmail.subject)")
        
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        let sinistroId = extractSinistroReference(from: email)
        
        // Se abbiamo un sinistro
        if let sinistroId = sinistroId,
           let sinistro = findSinistro(riferimento: sinistroId, context: context) {
            
            // Aggiungi sempre entry nel diario (anche se email letta)
            sinistro.addDiarioEntry(DiarioEntry(
                testo: "Richiesta documentazione ricevuta",
                tipo: .email
            ))
            
            // Genera task/aggiornamenti stato solo se email è unread
            if isUnread {
                // Aggiorna stato se appropriato
                // "in attesa documentale" può essere impostato solo se è stata inviata mail "richiesta documentazione"
                // Qui gestiamo il caso inbound (richiesta ricevuta), per outbound (richiesta inviata) 
                // la validazione avviene quando viene inviata la mail
                if email.direction == .inbound {
                    // Richiesta dalla compagnia/assicurato - può andare in attesa documentale
                    updateSinistroStateIfNeeded(sinistro, newState: .inAttesaDocumentale, context: context)
                } else if email.direction == .outbound {
                    // Richiesta inviata da noi - può andare in attesa documentale
                    // (questa è la condizione richiesta: mail "richiesta documentazione" inviata)
                    updateSinistroStateIfNeeded(sinistro, newState: .inAttesaDocumentale, context: context)
                }
                
                // Crea task per rispondere
                createDocumentationTask(for: sinistroId, isRequest: true, email: email)
            }
        }
        
        // Determina tipo di documentazione richiesta
        let docType = extractDocumentationType(from: email.originalEmail.body ?? "")
        
        return EmailDocumentationRequested(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId,
            direction: email.direction,
            documentationType: docType,
            requestedBy: email.senderType
        )
    }
    
    // MARK: - Documentation Received
    
    private func handleDocumentationReceived(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[DocHandler] 📧 Documentazione ricevuta: \(email.originalEmail.subject)")
        
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        let sinistroId = extractSinistroReference(from: email)
        
        // Se abbiamo un sinistro
        if let sinistroId = sinistroId,
           let sinistro = findSinistro(riferimento: sinistroId, context: context) {
            // Aggiungi una entry completa (con emailMessageId) ed attiva i trigger
            // Serve per:
            // - far comparire correttamente l'email nel diario
            // - far scattare download allegati in "sinistro/da mail"
            if let createdEntry = await ensureEmailDiarioEntry(email: email.originalEmail, sinistro: sinistro, context: context) {
                await ActiveTriggerService.shared.processDiarioEntry(
                    createdEntry,
                    sinistro: sinistro,
                    email: email.originalEmail,
                    context: context
                )
            }
            
            // Aggiorna stato anche se l'email è già letta: la documentazione è un fatto "oggettivo"
            // (la validazione resta in StatoManager.canTransition).
            let currentStateDesc = sinistro.stato ?? ""
            let statoManager = StatoManager.shared
            
            // Verifica se lo stato attuale è in un gruppo di "attesa"
            let isWaiting = currentStateDesc.lowercased().contains("attesa")
            
            if isWaiting {
                updateSinistroStateIfNeeded(sinistro, newState: .periziaDaEseguireDocumentale, context: context)
            } else {
                print("[DocHandler] ℹ️ Documentazione ricevuta in stato non di attesa (\(currentStateDesc))")
            }
            
            // Task creation delegata a ClaimEngine tramite evento EmailDocumentationReceived
            // ClaimEngine processerà l'evento e creerà task "Verificare documentazione" se necessario
            
            // Salva
            saveContext(context)
        }
        
        return EmailDocumentationReceived(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId,
            attachmentCount: email.originalEmail.attachments?.count ?? 0,
            attachmentTypes: email.attachmentTypes,
            senderType: email.senderType
        )
    }
    
    // MARK: - Helpers
    
    private func updateSinistroStateIfNeeded(_ sinistro: Sinistro, newState: StatoManager.StatoSinistro, context: NSManagedObjectContext) {
        // Aggiorna stato con validazione
        Task {
            do {
                try await StatoManager.shared.changeState(
                    for: sinistro,
                    to: newState,
                    context: context
                )
                print("[DocHandler] 📊 Stato aggiornato a: \(newState.descrizione)")
            } catch {
                print("[DocHandler] ⚠️ Impossibile aggiornare stato: \(error.localizedDescription)")
            }
        }
    }
    
    private func extractDocumentationType(from body: String) -> String? {
        let patterns = [
            "fattur[ae]": "fatture",
            "foto": "foto",
            "preventiv[oi]": "preventivi",
            "contratto": "contratto",
            "polizza": "polizza",
            "denuncia": "denuncia",
            "perizia": "perizia",
            "document[io]": "documenti generici"
        ]
        
        let lowerBody = body.lowercased()
        
        for (pattern, docType) in patterns {
            if lowerBody.contains(pattern) {
                return docType
            }
        }
        
        return nil
    }
    
    private func createDocumentationTask(for sinistroId: String, isRequest: Bool, email: ClassifiedEmail) {
        let title = isRequest 
            ? "Rispondere a richiesta documentazione - \(sinistroId)"
            : "Verificare documentazione ricevuta - \(sinistroId)"
        
        // Task creation delegata a ClaimEngine tramite eventi
        // ClaimEngine processerà l'evento documentazione e creerà task se necessario
    }
    
    /// Crea (se serve) una entry completa nel diario per l'email e la restituisce.
    /// Se l'email è già presente nel diario (stesso emailMessageId), ritorna nil.
    private func ensureEmailDiarioEntry(email: Email, sinistro: Sinistro, context: NSManagedObjectContext) async -> DiarioEntry? {
        // Evita duplicati nel diario
        let alreadyInDiario = sinistro.diarioArray.contains { entry in
            entry.emailMessageId == email.id
        }
        guard !alreadyInDiario else { return nil }
        
        let body = email.body ?? ""
        let riassunto = body.isEmpty ? email.subject : String(body.prefix(200))
        
        let entry = DiarioEntry(
            timestamp: email.date ?? Date(),
            tipo: .email,
            titolo: email.subject,
            riassunto: riassunto,
            contenutoCompleto: body,
            emailMessageId: email.id,
            processedEmailDate: email.date
        )
        
        await MainActor.run {
            sinistro.addDiarioEntry(entry)
            try? context.save()
        }
        
        return entry
    }
}

