import Foundation
import CoreData

/// Handler per email di controllo perizia e revisione
class ControlHandler: BaseEmailHandler {
    
    private let taskManager = TaskManager.shared
    
    init() {
        super.init(
            handlerId: "control",
            supportedCategories: [.controlled, .revisionRequested]
        )
    }
    
    override func handle(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        switch email.category {
        case .controlled:
            return await handleControlled(email, context: context, isUnread: isUnread)
        case .revisionRequested:
            return await handleRevisionRequested(email, context: context, isUnread: isUnread)
        default:
            return nil
        }
    }
    
    // MARK: - Controlled (Perizia Controllata)
    
    private func handleControlled(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[ControlHandler] 📧 Perizia controllata: \(email.originalEmail.subject)")
        
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        let sinistroId = extractSinistroReference(from: email)
        
        if let sinistroId = sinistroId,
           let sinistro = findSinistro(riferimento: sinistroId, context: context) {
            
            // Estrai esito del controllo
            let outcome = extractControlOutcome(from: email.originalEmail.body ?? "")
            
            // Aggiungi sempre entry nel diario (anche se email letta)
            var diarioText = "Perizia controllata"
            if let outcome = outcome {
                diarioText += " - Esito: \(outcome)"
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
                        to: .controllata,
                        context: context
                    )
                } catch {
                    print("[ControlHandler] ⚠️ Impossibile aggiornare stato: \(error.localizedDescription)")
                }
                
                // Se esito positivo, crea task per chiusura
                if outcome?.lowercased().contains("approvata") == true || outcome == nil {
                    let task = DailyTask(
                        title: "Completare pratica controllata - \(sinistroId)",
                        description: "Perizia controllata, procedere con prossimi step",
                        type: .sinistroActivity,
                        sinistroID: sinistroId,
                        priority: 0.6,
                        deadline: Date().addingTimeInterval(48 * 60 * 60),
                        estimatedDuration: 900,
                        metadata: [
                            "emailId": AnyCodable(email.originalEmail.id),
                            "controlled": AnyCodable(true),
                            "outcome": AnyCodable(outcome ?? "")
                        ]
                )
                // Task creation delegata a ClaimEngine tramite evento
                // Task { @MainActor in
                //     taskManager.addTask(task)
                // }
            }
            }
            
            return EmailControlled(
                emailId: email.originalEmail.id,
                sinistroId: sinistroId,
                outcome: outcome
            )
        }
        
        return EmailControlled(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId,
            outcome: nil
        )
    }
    
    // MARK: - Revision Requested
    
    private func handleRevisionRequested(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[ControlHandler] 📧 Richiesta revisione: \(email.originalEmail.subject)")
        
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        let sinistroId = extractSinistroReference(from: email)
        
        guard let sinistroId = sinistroId,
              let sinistro = findSinistro(riferimento: sinistroId, context: context) else {
            return EmailRevisionRequested(
                emailId: email.originalEmail.id,
                sinistroId: sinistroId,
                reason: nil,
                priority: nil
            )
        }
        
        // Usa il corpo della mail di spiegazione se presente, altrimenti estrai motivo
        let reason = extractRevisionReason(from: email.originalEmail.body ?? "")
        
        // Aggiungi sempre entry nel diario (anche se email letta)
        var diarioText = "Richiesta revisione perizia"
        if let reason = reason, !reason.isEmpty {
            diarioText += ": \(reason)"
        }
        
        sinistro.addDiarioEntry(DiarioEntry(
            testo: diarioText,
            tipo: .email
        ))
        
        // Genera task/aggiornamenti stato solo se email è unread
        if isUnread {
            // Verifica se è il pattern prioritario "Perizia da revisionare"
            let isPriorityRevision = email.originalEmail.subject.lowercased().contains("perizia da revisionare")
            
            // Cerca email di spiegazione entro 5 minuti (solo per pattern prioritario)
            var explanationBody: String? = nil
            if isPriorityRevision {
                explanationBody = await findExplanationEmail(
                    for: sinistroId,
                    afterDate: email.originalEmail.date ?? Date(),
                    revisionEmailId: email.originalEmail.id,
                    context: context
                )
            }
            
            // Usa il corpo della mail di spiegazione se presente
            let finalReason: String?
            if let explanation = explanationBody, !explanation.isEmpty {
                finalReason = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                finalReason = reason
            }
            
            // Aggiorna stato con validazione (richiesta revisione è permessa anche da chiusa)
            do {
                try await StatoManager.shared.changeState(
                    for: sinistro,
                    to: .richiestaRevisione,
                    context: context
                )
            } catch {
                print("[ControlHandler] ⚠️ Impossibile aggiornare stato: \(error.localizedDescription)")
            }
            
            // Priorità alta per pattern prioritario (sinistri non chiusi correttamente)
            let priority = isPriorityRevision ? 0.95 : extractRevisionPriority(from: email)
            
            // Crea task urgente per revisione (in background)
            let task = DailyTask(
                title: "Revisione perizia - \(sinistroId)",
                description: finalReason ?? "Revisione richiesta dalla compagnia",
                type: .sinistroActivity,
                sinistroID: sinistroId,
                priority: priority,
                deadline: Date().addingTimeInterval(24 * 60 * 60), // 24 ore
                estimatedDuration: 3600, // 1 ora
                metadata: [
                    "emailId": AnyCodable(email.originalEmail.id),
                    "revision": AnyCodable(true),
                    "reason": AnyCodable(finalReason ?? ""),
                    "isPriorityRevision": AnyCodable(isPriorityRevision)
                ]
            )
            Task { @MainActor in
                taskManager.addTask(task)
            }
            
            return EmailRevisionRequested(
                emailId: email.originalEmail.id,
                sinistroId: sinistroId,
                reason: finalReason,
                priority: priority > 0.8 ? "alta" : "normale"
            )
        }
        
        return EmailRevisionRequested(
            emailId: email.originalEmail.id,
            sinistroId: sinistroId,
            reason: reason,
            priority: nil
        )
        
    }
    
    // MARK: - Explanation Email Finder
    
    /// Cerca email di spiegazione entro 5 minuti dalla richiesta di revisione
    /// che provengono dallo stesso dominio dello studio e riguardano lo stesso sinistro
    private func findExplanationEmail(
        for sinistroId: String,
        afterDate: Date,
        revisionEmailId: String,
        context: NSManagedObjectContext
    ) async -> String? {
        let repository = EmailRepository.shared
        let maxTimeWindow: TimeInterval = 5 * 60 // 5 minuti
        let endDate = afterDate.addingTimeInterval(maxTimeWindow)
        
        // Estrai dominio del tenant dalla mail di revisione
        // EmailRepository è @MainActor, quindi dobbiamo chiamarlo da MainActor
        let revisionEmail = await MainActor.run {
            EmailRepository.shared.getEmail(byId: revisionEmailId)
        }
        guard let revisionSender = revisionEmail?.sender.email else {
            return nil
        }
        
        let studioDomain = extractDomain(from: revisionSender)
        guard !studioDomain.isEmpty else {
            return nil
        }
        
        // Cerca in tutte le mailbox (tutto su MainActor)
        let (stats, allEmails) = await MainActor.run {
            let repo = EmailRepository.shared
            let stats = repo.getStats()
            var emails: [Email] = []
            for mailboxId in stats.emailsPerMailbox.keys {
                emails.append(contentsOf: repo.getEmails(forMailbox: mailboxId))
            }
            return (stats, emails)
        }
        
        var candidateEmails: [Email] = []
        
        for email in allEmails {
            // Filtra email entro la finestra temporale
            let emailDate = email.date
            guard emailDate >= afterDate,
                  emailDate <= endDate else {
                continue
            }
            
            // Escludi la mail di revisione stessa
            guard email.id != revisionEmailId else {
                continue
            }
            
            // Verifica dominio mittente (stesso dominio dello studio)
            let emailDomain = extractDomain(from: email.sender.email)
            guard emailDomain == studioDomain else {
                continue
            }
            
            // Verifica che riguardi lo stesso sinistro (controlla oggetto o corpo)
            if email.subject.contains(sinistroId) || 
               (email.body?.contains(sinistroId) ?? false) ||
               matchesSinistroPattern(subject: email.subject, sinistroId: sinistroId) {
                candidateEmails.append(email)
            }
        }
        
        // Ordina per data (più recente prima) e prendi la prima
        let sortedCandidates = candidateEmails.sorted { $0.date > $1.date }
        
        if let explanationEmail = sortedCandidates.first {
            // Se il corpo non è presente, prova a scaricarlo
            var body = explanationEmail.body
            
            if body == nil || body?.isEmpty == true {
                print("[ControlHandler] 📥 Download corpo email di spiegazione...")
                do {
                    if let downloaded = try await MailManager.shared.fetchFullEmail(
                        emailId: explanationEmail.id,
                        context: context
                    ) {
                        body = downloaded.body
                    }
                } catch {
                    print("[ControlHandler] ⚠️ Errore download corpo email: \(error)")
                }
            }
            
            if let finalBody = body, !finalBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("[ControlHandler] ✅ Trovata email di spiegazione: \(explanationEmail.subject)")
                return finalBody
            }
        }
        
        return nil
    }
    
    private func extractDomain(from email: String) -> String {
        guard let atIndex = email.lastIndex(of: "@") else {
            return ""
        }
        let domain = String(email[email.index(after: atIndex)...])
        return domain.lowercased()
    }
    
    private func matchesSinistroPattern(subject: String, sinistroId: String) -> Bool {
        // Pattern: "Sinistro n. [numero] - Assicurato [nome] - ns. rif. [riferimento]"
        let patterns = [
            "ns[.]?\\s*rif[.]?\\s+" + sinistroId,
            "rif[.]?\\s+" + sinistroId,
            "riferimento[:\\s]+" + sinistroId
        ]
        
        let subjectLower = subject.lowercased()
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(subjectLower.startIndex..<subjectLower.endIndex, in: subjectLower)
                if regex.firstMatch(in: subjectLower, options: [], range: range) != nil {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Helpers
    
    private func extractControlOutcome(from body: String) -> String? {
        let lowerBody = body.lowercased()
        
        if lowerBody.contains("approvata") || lowerBody.contains("ok") || lowerBody.contains("confermata") {
            return "Approvata"
        }
        if lowerBody.contains("modifiche") || lowerBody.contains("correzioni") {
            return "Richieste modifiche"
        }
        if lowerBody.contains("rifiutata") || lowerBody.contains("respinta") {
            return "Non approvata"
        }
        
        return nil
    }
    
    private func extractRevisionReason(from body: String) -> String? {
        let patterns = [
            "(?:motivo|causa|perch[eé])[:\\s]+(.+?)(?:\\n|\\.|$)",
            "(?:si richiede|richiediamo)[:\\s]+(.+?)(?:\\n|\\.|$)",
            "(?:necessario|occorre)[:\\s]+(.+?)(?:\\n|\\.|$)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(body.startIndex..<body.endIndex, in: body)
                if let match = regex.firstMatch(in: body, options: [], range: range),
                   let reasonRange = Range(match.range(at: 1), in: body) {
                    let reason = String(body[reasonRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if reason.count > 10 && reason.count < 200 {
                        return reason
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractRevisionPriority(from email: ClassifiedEmail) -> Double {
        let subject = email.originalEmail.subject.lowercased()
        let body = (email.originalEmail.body ?? "").lowercased()
        
        // Urgente
        if subject.contains("urgent") || body.contains("urgent") ||
           subject.contains("immediat") || body.contains("immediat") {
            return 0.95
        }
        
        // Alta priorità
        if subject.contains("priorit") || body.contains("sollecit") {
            return 0.85
        }
        
        return 0.75 // Default per revisioni
    }
}
