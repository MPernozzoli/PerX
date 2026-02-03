import Foundation

/// Servizio per la classificazione automatica delle email
/// Analizza subject, sender, body e attachments per determinare la categoria
class EmailClassifier {
    static let shared = EmailClassifier()
    
    // MARK: - Configuration
    
    /// Domini email dello studio (noi)
    private let studioDomains = [
        "manivaperizie.it",
        "studioperizie.it"
        // Aggiungi altri domini se necessario
    ]
    
    /// Email della compagnia mandante
    private let companyEmails = [
        "info@actsrl.it"
    ]
    
    /// Domini agenzie
    private let agencyDomainPatterns = [
        "agenzia",
        "agency",
        "assicurazioni"
    ]
    
    /// Domini broker
    private let brokerDomainPatterns = [
        "broker",
        "intermediario",
        "intermediazione"
    ]
    
    /// Domini liquidatori
    private let liquidatorDomainPatterns = [
        "liquidazioni",
        "sinistri"
    ]
    
    private init() {}
    
    // MARK: - Classification
    
    /// Classifica un'email e restituisce il risultato
    /// - Parameters:
    ///   - email: L'email da classificare
    ///   - mailboxId: ID della mailbox (opzionale, usato per determinare se è nella mailbox SENT)
    func classify(_ email: Email, mailboxId: String? = nil) -> ClassifiedEmail {
        let subject = email.subject.lowercased()
        let body = (email.body ?? "").lowercased()
        let senderEmail = email.sender.email.lowercased()
        let hasAttachments = email.attachments?.isEmpty == false
        
        // Determina direzione (inbound/outbound)
        // Se l'email è nella mailbox SENT, è sempre outbound (anche se inviata da altro portale)
        let direction = determineDirection(senderEmail: senderEmail, mailboxId: mailboxId)
        
        // Determina tipo mittente
        let senderType = determineSenderType(senderEmail: senderEmail, subject: subject, body: body)
        
        // Classifica per categoria
        let (category, confidence, patterns) = classifyCategory(
            subject: subject,
            body: body,
            senderEmail: senderEmail,
            senderType: senderType,
            hasAttachments: hasAttachments,
            direction: direction,
            attachmentTypes: extractAttachmentTypes(from: email)
        )
        
        // Estrai riferimento sinistro
        let sinistroId = extractSinistroReference(subject: email.subject, body: email.body ?? "")
        
        return ClassifiedEmail(
            originalEmail: email,
            category: category,
            direction: direction,
            senderType: senderType,
            sinistroId: sinistroId,
            confidence: confidence,
            matchedPatterns: patterns
        )
    }
    
    // MARK: - Direction Detection
    
    private func determineDirection(senderEmail: String, mailboxId: String?) -> EmailDirection {
        // PRIORITÀ 1: Se l'email è nella mailbox SENT, è sempre outbound
        // (anche se inviata da un altro portale, vogliamo monitorarla)
        if let mailboxId = mailboxId, mailboxId.uppercased() == "SENT" {
            return .outbound
        }
        
        // PRIORITÀ 2: Se il mittente è uno dei nostri domini, è outbound
        for domain in studioDomains {
            if senderEmail.contains(domain) {
                return .outbound
            }
        }
        
        return .inbound
    }
    
    // MARK: - Sender Type Detection
    
    private func determineSenderType(senderEmail: String, subject: String, body: String) -> EmailSenderType {
        // Compagnia mandante
        if companyEmails.contains(senderEmail) {
            return .company
        }
        
        // Verifica pattern nel dominio
        let domain = senderEmail.components(separatedBy: "@").last ?? ""
        
        // Agenzia
        for pattern in agencyDomainPatterns {
            if domain.contains(pattern) {
                return .agency
            }
        }
        
        // Broker
        for pattern in brokerDomainPatterns {
            if domain.contains(pattern) {
                return .broker
            }
        }
        
        // Liquidatore
        for pattern in liquidatorDomainPatterns {
            if domain.contains(pattern) {
                return .liquidator
            }
        }
        
        // Studio (noi)
        for studioDomain in studioDomains {
            if domain.contains(studioDomain) {
                return .studio
            }
        }
        
        // Prova a determinare dal contenuto
        if subject.contains("agenzia") || body.contains("agenzia") {
            return .agency
        }
        
        if subject.contains("broker") || body.contains("broker") ||
           subject.contains("intermediario") || body.contains("intermediario") {
            return .broker
        }
        
        if subject.contains("liquidatore") || body.contains("liquidatore") ||
           subject.contains("liquidazione") {
            return .liquidator
        }
        
        // Default: assicurato
        return .insured
    }
    
    // MARK: - Category Classification
    
    private func classifyCategory(
        subject: String,
        body: String,
        senderEmail: String,
        senderType: EmailSenderType,
        hasAttachments: Bool,
        direction: EmailDirection,
        attachmentTypes: [String]
    ) -> (EmailCategory, Double, [String]) {
        
        var matchedPatterns: [String] = []
        
        // MARK: - Inbound from Company (alta priorità)
        
        if senderType == .company || companyEmails.contains(senderEmail) || senderEmail.lowercased() == "info@actsrl.it" {
            // Assegnazione perito (due varianti)
            let subjectLower = subject.lowercased()
            if subjectLower.contains("assegnazione perito") || 
               (subjectLower.contains("assegnazione") && subjectLower.hasSuffix(":")) {
                matchedPatterns.append("assegnazione")
                return (.assignment, 0.95, matchedPatterns)
            }
            
            // Revoca (tre varianti)
            // Variante 1: "Revoca incarico videoperizia per sinistro..."
            // Variante 2: "Revoca incarico per sinistro..."
            // Variante 3: "...REVOCA INCARICO"
            if subjectLower.contains("revoca incarico") || 
               subjectLower.contains("revoca videoperizia") ||
               subjectLower.contains("revoca incarico") ||
               (subjectLower.contains("sinistro") && subjectLower.contains("revoca incarico")) {
                matchedPatterns.append("revoca incarico")
                return (.revocation, 0.95, matchedPatterns)
            }
            
            // Perizia controllata
            // Pattern: "perizia controllata: [riferimento] - [nome assicurato]" (no body needed)
            if subject.contains("perizia controllata") {
                // Verifica pattern specifico con riferimento e nome assicurato
                let subjectLower = subject.lowercased()
                if subjectLower.contains("perizia controllata:") || 
                   (subjectLower.contains("perizia controllata") && subjectLower.contains("-")) {
                    matchedPatterns.append("perizia controllata")
                    return (.controlled, 0.95, matchedPatterns)
                }
                // Pattern generico
                matchedPatterns.append("perizia controllata")
                return (.controlled, 0.9, matchedPatterns)
            }
            
            // Richiesta revisione - pattern specifico prioritario
            if subject.contains("perizia da revisionare") {
                matchedPatterns.append("perizia da revisionare")
                return (.revisionRequested, 0.98, matchedPatterns) // Alta confidenza per pattern specifico
            }
            
            // Richiesta revisione (pattern generico)
            if subject.contains("richiesta revisione") || subject.contains("revisione perizia") {
                matchedPatterns.append("richiesta revisione")
                return (.revisionRequested, 0.9, matchedPatterns)
            }
        }
        
        // MARK: - Acts (Atti)
        
        // Atto da firmare inviato (SOLO outbound - siamo noi a inviarlo)
        if direction == .outbound {
            let attoOutPatterns = ["atto da firmare", "invio atto", "atto in allegato", "atto di liquidazione", "atto per la firma"]
            for pattern in attoOutPatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append(pattern)
                    return (.actSent, 0.9, matchedPatterns)
                }
            }
        }
        
        // Atto ricevuto (può essere da qualsiasi mittente, anche interno allo studio)
        // IMPORTANTE: spesso mantengono l'oggetto "atto da firmare" anche quando restituiscono l'atto,
        // quindi dobbiamo analizzare il CONTENUTO per distinguere i vari casi
        
        // 1. Atto firmato restituito (analizza body per confermare - priorità al body)
        let attoFirmatoPatterns = [
            "atto firmato", "atto sottoscritto", "firmato in allegato", "quietanza firmata",
            "restituisco l'atto", "restituiamo l'atto", "atto firmato e restituito",
            "inviato firmato", "firmato e inviato", "atto compilato e firmato",
            "ho firmato", "abbiamo firmato", "firmato come richiesto"
        ]
        for pattern in attoFirmatoPatterns {
            // Priorità al body (più affidabile dell'oggetto)
            if body.contains(pattern) {
                matchedPatterns.append(pattern)
                return (.actReceived, 0.95, matchedPatterns) // Alta confidenza se nel body
            }
            if subject.contains(pattern) {
                matchedPatterns.append(pattern)
                return (.actReceived, 0.85, matchedPatterns) // Media confidenza se solo nel subject
            }
        }
        
        // 2. Contestazione importo (analizza body per parole chiave)
        let contestazionePatterns = [
            "non sono d'accordo", "non condivido", "contestazione", "importo non corretto",
            "importo errato", "non accetto", "ritengo che", "non corrisponde",
            "disconforme", "non conforme", "importo diverso", "liquidazione errata"
        ]
        for pattern in contestazionePatterns {
            if body.contains(pattern) {
                matchedPatterns.append("contestazione: \(pattern)")
                // Se c'è un allegato (atto firmato), è più probabile che sia atto ricevuto con contestazione
                if hasAttachments {
                    return (.actReceived, 0.8, matchedPatterns)
                }
            }
        }
        
        // 3. Richiesta spiegazioni (analizza body)
        let spiegazioniPatterns = [
            "spiegazioni", "chiarimenti", "motivazione", "perché", "come mai",
            "non capisco", "vorrei sapere", "potete spiegare", "desidero capire"
        ]
        for pattern in spiegazioniPatterns {
            if body.contains(pattern) && subject.lowercased().contains("atto") {
                matchedPatterns.append("richiesta spiegazioni: \(pattern)")
                // Se c'è un allegato, potrebbe essere atto ricevuto con richiesta
                if hasAttachments {
                    return (.actReceived, 0.75, matchedPatterns)
                }
                // Altrimenti è più probabile una richiesta di chiarimenti
                return (.clarificationRequest, 0.8, matchedPatterns)
            }
        }
        
        // 4. Documentazione aggiuntiva (fattura, foto, ecc. dopo invio atto)
        let docAggiuntivaPatterns = [
            "fattura", "fatturazione", "ricevuta", "scontrino", "foto aggiuntive",
            "documentazione aggiuntiva", "ulteriore documentazione", "altri documenti",
            "allego anche", "in allegato anche", "documenti integrativi"
        ]
        for pattern in docAggiuntivaPatterns {
            if body.contains(pattern) && hasAttachments {
                matchedPatterns.append("documentazione aggiuntiva: \(pattern)")
                // Se l'oggetto contiene "atto", potrebbe essere documentazione aggiuntiva dopo invio atto
                if subject.lowercased().contains("atto") {
                    return (.documentationReceived, 0.85, matchedPatterns)
                }
            }
        }
        
        // 5. Check nome file allegato per atto firmato (fallback)
        if hasAttachments && attachmentTypes.contains(where: { 
            $0.contains("atto") && ($0.contains("firmato") || $0.contains("sottoscritto") || $0.contains("compilato"))
        }) {
            matchedPatterns.append("allegato atto firmato")
            return (.actReceived, 0.85, matchedPatterns)
        }
        
        // 6. Se l'oggetto contiene "atto da firmare" ma è inbound e non abbiamo trovato pattern specifici,
        // potrebbe essere una risposta che mantiene l'oggetto originale - analizza meglio il body
        if subject.lowercased().contains("atto da firmare") || subject.lowercased().contains("atto") {
            // Se il body è molto corto o contiene solo "in allegato", potrebbe essere atto firmato restituito
            if body.count < 100 || body.lowercased().contains("in allegato") || body.lowercased().contains("allego") {
                if hasAttachments {
                    matchedPatterns.append("atto restituito (oggetto mantenuto)")
                    return (.actReceived, 0.7, matchedPatterns) // Bassa confidenza ma probabile
                }
            }
        }
        
        // MARK: - Documentation
        
        // Richiesta documentazione
        let docRequestPatterns = ["richiesta documentazione", "inviare documentazione", "documentazione mancante", "documenti mancanti"]
        for pattern in docRequestPatterns {
            if subject.contains(pattern) || body.contains(pattern) {
                matchedPatterns.append(pattern)
                let dir = direction == .outbound ? EmailDirection.outbound : .inbound
                return (.documentationRequest, 0.85, matchedPatterns)
            }
        }
        
        // Documentazione ricevuta (con allegati)
        if hasAttachments && direction == .inbound {
            let docReceivedPatterns = ["documentazione", "documenti", "in allegato", "allego", "invio documentazione"]
            for pattern in docReceivedPatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append(pattern)
                    return (.documentationReceived, 0.8, matchedPatterns)
                }
            }
        }
        
        // MARK: - Reminders (Solleciti)
        
        let reminderPatterns = ["sollecit", "urgente", "mancata risposta", "ancora in attesa", "scadenza"]
        for pattern in reminderPatterns {
            if subject.contains(pattern) || body.contains(pattern) {
                matchedPatterns.append(pattern)
                if direction == .outbound {
                    return (.reminderSent, 0.85, matchedPatterns)
                } else {
                    return (.reminderReceived, 0.85, matchedPatterns)
                }
            }
        }
        
        // MARK: - Survey (Sopralluoghi)
        
        // Sopralluogo fissato
        let surveyScheduledPatterns = ["sopralluogo fissato", "appuntamento fissato", "confermo sopralluogo", "sopralluogo confermato"]
        for pattern in surveyScheduledPatterns {
            if subject.contains(pattern) || body.contains(pattern) {
                matchedPatterns.append(pattern)
                return (.surveyScheduled, 0.9, matchedPatterns)
            }
        }
        
        // Sopralluogo restituito
        let surveyReturnedPatterns = ["sopralluogo restituito", "restituito sopralluogo", "impossibile effettuare", "non eseguibile"]
        for pattern in surveyReturnedPatterns {
            if subject.contains(pattern) || body.contains(pattern) {
                matchedPatterns.append(pattern)
                return (.surveyReturned, 0.9, matchedPatterns)
            }
        }
        
        // MARK: - Videocall (Videoperizia)
        
        let videocallPatterns = ["videoperizia fissata", "videoperizia confermata", "collegamento video", "videochiamata", "meet", "teams", "zoom"]
        for pattern in videocallPatterns {
            if subject.contains(pattern) || body.contains(pattern) {
                matchedPatterns.append(pattern)
                return (.videocallScheduled, 0.85, matchedPatterns)
            }
        }
        
        // MARK: - Clarification (Chiarimenti)
        
        let clarificationPatterns = ["chiariment", "spiegazione", "domanda", "delucidazione", "precisazione"]
        for pattern in clarificationPatterns {
            if subject.contains(pattern) || body.contains(pattern) {
                matchedPatterns.append(pattern)
                return (.clarificationRequest, 0.8, matchedPatterns)
            }
        }
        
        // MARK: - Outcome (Esito)
        
        if direction == .outbound {
            let outcomePatterns = ["esito perizia", "comunicazione esito", "esito sinistro", "resoconto perizia"]
            for pattern in outcomePatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append(pattern)
                    return (.outcomeSent, 0.85, matchedPatterns)
                }
            }
        }
        
        // MARK: - Verbal Acceptance
        
        // Accettazione verbale da parte dell'assicurato (inbound)
        if direction == .inbound {
            let verbalAcceptancePatterns = [
                "accettazione verbale", "accetto verbalmente", "accettiamo verbalmente",
                "accetto senza firmare", "accettiamo senza firmare", "accetto senza atto",
                "accettiamo senza atto", "va bene così", "accetto la proposta",
                "accettiamo la proposta", "confermo accettazione", "confermiamo accettazione",
                "accetto l'importo", "accettiamo l'importo", "d'accordo con l'importo",
                "proceda pure", "procedete pure", "ok per la liquidazione"
            ]
            for pattern in verbalAcceptancePatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append(pattern)
                    return (.verbalAcceptance, 0.9, matchedPatterns)
                }
            }
        }
        
        // MARK: - Studio Internal Communications
        
        // Solo per mittenti interni (domini studio o email note dello studio)
        let isStudioSender = isFromStudio(senderEmail: senderEmail)
        
        if isStudioSender {
            // Riunioni
            let meetingPatterns = ["riunione", "meeting", "convocazione", "incontro", "call", "collegamento", "partecipazione"]
            for pattern in meetingPatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append("riunione: \(pattern)")
                    return (.meeting, 0.85, matchedPatterns)
                }
            }
            
            // Procedure
            let procedurePatterns = ["procedura", "protocollo", "linee guida", "normativa", "regolamento", "istruzioni operative"]
            for pattern in procedurePatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append("procedura: \(pattern)")
                    return (.procedure, 0.85, matchedPatterns)
                }
            }
            
            // Notizie dello studio (newsletter, comunicazioni generiche interne)
            let studioNewsPatterns = ["newsletter", "aggiornamento", "avviso", "notizia", "comunicazione interna", "novità"]
            for pattern in studioNewsPatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append("notizia studio: \(pattern)")
                    return (.studioNews, 0.8, matchedPatterns)
                }
            }
            
            // Info interne (ferie, ufficio, organizzazione)
            let internalInfoPatterns = ["ferie", "assenza", "chiusura ufficio", "orario", "turni", "organizzazione", "presenze", "permesso", "malattia"]
            for pattern in internalInfoPatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append("info interna: \(pattern)")
                    return (.internalInfo, 0.85, matchedPatterns)
                }
            }
            
            // Eventi sociali (cena, aperitivo, festa, auguri)
            let socialPatterns = ["cena", "aperitivo", "festa", "auguri", "compleanno", "natale", "pasqua", "evento", "invito"]
            for pattern in socialPatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append("evento studio: \(pattern)")
                    return (.studioNews, 0.75, matchedPatterns)
                }
            }
            
            // Formazione (corsi, webinar, workshop)
            let trainingPatterns = ["formazione", "corso", "webinar", "workshop", "training", "aggiornamento professionale", "seminario"]
            for pattern in trainingPatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append("formazione: \(pattern)")
                    return (.training, 0.8, matchedPatterns) // Formazione
                }
            }
        }
        
        // MARK: - Default: Generic Communication
        
        return (.genericCommunication, 0.5, matchedPatterns)
    }
    
    // MARK: - Studio Domain Check
    
    /// Verifica se l'email proviene da un dominio interno dello studio o email associata
    private func isFromStudio(senderEmail: String) -> Bool {
        let senderLower = senderEmail.lowercased()
        
        // Verifica domini studio
        for domain in studioDomains {
            if senderLower.contains(domain) {
                return true
            }
        }
        
        // Verifica domini partner noti
        let partnerDomains = [
            "actsrl.it",
            "allconsulting.org"
        ]
        
        for domain in partnerDomains {
            if senderLower.contains(domain) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Reference Extraction
    
    private func extractSinistroReference(subject: String, body: String) -> String? {
        let text = "\(subject) \(body)"
        
        let patterns = [
            "per il sinistro \\[([^\\]]+)\\]",
            "per il sinistro\\s+([A-Z0-9\\-/]+)",
            "sinistro n[°.]?\\s*([A-Z0-9\\-/]+)",
            "pratica[\\s:]+([A-Z0-9\\-/]+)",
            "riferimento[\\s:]+([A-Z0-9\\-/]+)",
            "\\bsinistro[\\s:]+([A-Z0-9\\-/]+)",
            "\\[([A-Z0-9\\-/]{5,})\\]"  // Codice tra parentesi quadre (min 5 caratteri)
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   let idRange = Range(match.range(at: 1), in: text) {
                    let foundID = String(text[idRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !foundID.isEmpty && foundID.count > 2 {
                        return foundID
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Attachment Analysis
    
    private func extractAttachmentTypes(from email: Email) -> [String] {
        guard let attachments = email.attachments else { return [] }
        
        return attachments.compactMap { attachment in
            // Estrai dal filename
            let filename = attachment.filename.lowercased()
            let ext = (filename as NSString).pathExtension
            // Restituisci anche il nome file per pattern matching
            return "\(ext):\(filename)"
        }
    }
    
    // MARK: - Batch Classification
    
    /// Classifica un batch di email
    func classify(_ emails: [Email]) -> [ClassifiedEmail] {
        return emails.map { classify($0) }
    }
    
    /// Filtra email già classificate per categoria
    func filter(_ classifiedEmails: [ClassifiedEmail], by categories: [EmailCategory]) -> [ClassifiedEmail] {
        return classifiedEmails.filter { categories.contains($0.category) }
    }
    
    /// Raggruppa email classificate per categoria
    func group(_ classifiedEmails: [ClassifiedEmail]) -> [EmailCategory: [ClassifiedEmail]] {
        return Dictionary(grouping: classifiedEmails, by: { $0.category })
    }
}

