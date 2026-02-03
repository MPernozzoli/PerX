import Foundation
import CoreData

/// Handler per email di assegnazione nuove perizie
class AssignmentHandler: BaseEmailHandler {
    
    private let aiService = AppleIntelligenceService.shared
    
    init() {
        super.init(
            handlerId: "assignment",
            supportedCategories: [.assignment]
        )
    }
    
    override func handle(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[AssignmentHandler] 📧 Processamento email di assegnazione: \(email.originalEmail.subject)")
        
        // Verifica mittente (sempre info@actsrl.it) - PRIMA del tag
        guard email.originalEmail.sender.email.lowercased() == "info@actsrl.it" else {
            print("[AssignmentHandler] ⚠️ Mittente non valido: \(email.originalEmail.sender.email)")
            return nil
        }
        
        // Verifica oggetto - PRIMA del tag
        let subject = email.originalEmail.subject.lowercased()
        guard subject.contains("assegnazione") else {
            print("[AssignmentHandler] ⚠️ Oggetto non valido: \(email.originalEmail.subject)")
            return nil
        }
        
        // Per assegnazioni serve il corpo - scaricalo se mancante
        var emailWithBody = email.originalEmail
        var receivedDate: Date? = nil
        
        if emailWithBody.body == nil {
            print("[AssignmentHandler] 📥 Download corpo email per estrarre riferimento...")
            do {
                // Recupera il detail completo per ottenere internalDate (data di ricezione)
                let detail = try await GmailService.shared.fetchEmailDetails(messageId: emailWithBody.id)
                receivedDate = EmailDateParser.date(fromInternalDate: detail.internalDate)
                
                if let downloaded = try await MailManager.shared.fetchFullEmail(
                    emailId: emailWithBody.id,
                    context: context
                ) {
                    emailWithBody = downloaded
                } else {
                    print("[AssignmentHandler] ⚠️ Impossibile scaricare corpo email - riproveremo dopo")
                    // NON applica tag e NON marca come processata - ritenteremo
                    return nil
                }
            } catch {
                print("[AssignmentHandler] ⚠️ Errore download corpo email: \(error)")
                // NON applica tag e NON marca come processata - ritenteremo
                return nil
            }
        } else {
            // Se il body è già disponibile, recupera comunque la data di ricezione
            do {
                let detail = try await GmailService.shared.fetchEmailDetails(messageId: emailWithBody.id)
                receivedDate = EmailDateParser.date(fromInternalDate: detail.internalDate)
            } catch {
                print("[AssignmentHandler] ⚠️ Impossibile recuperare data di ricezione: \(error)")
            }
        }
        
        // Estrai riferimento dal corpo: "E' stato assegnato il perito [nome] per il sinistro [riferimento]."
        guard let body = emailWithBody.body else {
            print("[AssignmentHandler] ⚠️ Corpo email non disponibile - riproveremo dopo")
            return nil
        }
        
        // Pattern hardcoded per formato standard assegnazioni
        let pattern = #"per\s+il\s+sinistro\s+\[?([0-9]{7})\]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            print("[AssignmentHandler] ⚠️ Errore creazione regex")
            return nil
        }
        
        let range = NSRange(location: 0, length: body.utf16.count)
        guard let match = regex.firstMatch(in: body, range: range),
              match.range(at: 1).location != NSNotFound else {
            print("[AssignmentHandler] ⚠️ Riferimento sinistro non trovato nel corpo")
            return nil
        }
        
        let riferimento = (body as NSString).substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !riferimento.isEmpty, riferimento.count == 7 else {
            print("[AssignmentHandler] ⚠️ Riferimento non valido: \(riferimento)")
            return nil
        }
        
        // SUCCESSO: Applica tag di categoria ORA (dopo aver verificato tutto)
        await applyEmailTag(for: email)
        print("[AssignmentHandler] ✅ Tag assegnazione applicato, riferimento estratto: \(riferimento)")
        
        // Estrai dati aggiuntivi con AI (usa email con body)
        // Riclassifica l'email con il body completo
        // Ottieni mailboxId per riconoscere email nella mailbox SENT
        let mailboxId = await EmailRepository.shared.getMailbox(forEmailId: emailWithBody.id)
        let emailWithBodyClassified = EmailClassifier.shared.classify(emailWithBody, mailboxId: mailboxId)
        let extractedData = await extractDataWithAI(from: emailWithBodyClassified)

        // Determina assegnatario: chi riceve la mail (owner del sinistro)
        let currentUserEmail = await GoogleAuthService.shared.userEmail?.lowercased()
        let recipients = emailWithBody.recipients

        let recipientMatch: Contact? = {
            if let currentUserEmail,
               let match = recipients.first(where: { $0.email.lowercased() == currentUserEmail }) {
                return match
            }
            if let match = recipients.first(where: { $0.email.lowercased().hasSuffix("@actsrl.it") }) {
                return match
            }
            return recipients.first
        }()

        let assigneeEmail = recipientMatch?.email.lowercased() ?? currentUserEmail
        let assigneeName: String? = {
            if let name = recipientMatch?.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
            guard let assigneeEmail, let local = assigneeEmail.split(separator: "@").first else { return nil }
            let raw = String(local).replacingOccurrences(of: ".", with: " ")
            return raw.capitalized
        }()
        
        // Usa la data di ricezione (internalDate) invece della data di invio
        let assignmentDate = receivedDate ?? emailWithBody.date
        
        // Crea e restituisci evento (la creazione/gestione sinistro è delegata a ClaimEngine)
        return EmailAssignmentReceived(
            emailId: emailWithBody.id,
            riferimento: riferimento,
            assignmentDate: assignmentDate,
            assigneeEmail: assigneeEmail,
            assigneeName: assigneeName,
            extractedData: extractedData
        )
    }
    
    // MARK: - AI Data Extraction
    
    private func extractDataWithAI(from email: ClassifiedEmail) async -> [String: String] {
        var extractedData: [String: String] = [:]
        
        guard let body = email.originalEmail.body else {
            return extractedData
        }
        
        // Usa AI per estrazione
        let aiInfo = await aiService.extractEmailInfo(from: body)
        
        if let sinistroID = aiInfo.sinistroID {
            extractedData["sinistroID"] = sinistroID
        }
        
        // Estrazione manuale come fallback
        extractedData.merge(extractManualData(from: body)) { (current, _) in current }
        
        return extractedData
    }
    
    private func extractManualData(from body: String) -> [String: String] {
        var data: [String: String] = [:]
        
        // Pattern per telefono
        let phonePattern = "(?:tel|telefono|cell|cellulare)[:\\s]*([+]?[0-9\\s\\-]{8,15})"
        if let phone = extractFirst(pattern: phonePattern, from: body) {
            data["telefono"] = phone.replacingOccurrences(of: " ", with: "")
        }
        
        // Pattern per email
        let emailPattern = "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"
        if let email = extractFirst(pattern: emailPattern, from: body) {
            data["email"] = email
        }
        
        // Pattern per nome (dopo "assicurato:" o "contraente:")
        let namePattern = "(?:assicurato|contraente)[:\\s]*([A-Za-zÀ-ÿ\\s]+?)(?:\\n|,|\\.|tel|email)"
        if let name = extractFirst(pattern: namePattern, from: body) {
            data["nome"] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return data
    }
    
    private func extractFirst(pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range) {
            // Prendi il primo gruppo catturato
            let groupRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
            if let swiftRange = Range(groupRange, in: text) {
                return String(text[swiftRange])
            }
        }
        
        return nil
    }
}

