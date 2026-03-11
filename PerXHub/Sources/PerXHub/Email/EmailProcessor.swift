import Foundation
import PerXCore
import SQLite

// ============================================================================
// MARK: - EmailProcessor
// Copia fedele della logica di EmailClassifier da PerX/Services/mail/Core/EmailClassifier.swift
// ============================================================================

/// Processore email centralizzato sull'Hub
/// Replica esattamente la logica di classificazione del client MailManager/EmailClassifier
public actor EmailProcessor {
    
    private let db: DatabaseManager
    private let vaultManager: VaultManager
    
    // MARK: - Configuration (identico a EmailClassifier client)
    
    /// Domini email dello studio (noi)
    private let studioDomains = [
        "manivaperizie.it",
        "studioperizie.it"
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
    
    // MARK: - Init
    
    init(db: DatabaseManager, vaultManager: VaultManager) {
        self.db = db
        self.vaultManager = vaultManager
    }
    
    // MARK: - Processing
    
    /// Processa una email ricevuta dal worker Python
    /// - Parameters:
    ///   - email: Email da processare (struttura identica al client)
    ///   - accountId: ID account email
    ///   - mailboxId: ID mailbox (es. "INBOX", "SENT")
    /// - Returns: Email classificata
    func processEmail(_ email: Email, accountId: String, mailboxId: String?) async throws -> ClassifiedEmail {
        // Classifica email (usa stessa logica del client)
        let classified = classify(email, mailboxId: mailboxId)
        
        // Salva nel DB
        try await saveEmailToDatabase(email: email, classified: classified, accountId: accountId)
        
        print("[EmailProcessor] ✅ Email processata: \(email.id) -> \(classified.category.rawValue)")
        
        return classified
    }
    
    /// Processa un batch di email
    func processEmails(_ emails: [Email], accountId: String, mailboxId: String?) async throws -> [ClassifiedEmail] {
        var results: [ClassifiedEmail] = []
        
        for email in emails {
            do {
                let classified = try await processEmail(email, accountId: accountId, mailboxId: mailboxId)
                results.append(classified)
            } catch {
                print("[EmailProcessor] ⚠️ Errore processing email \(email.id): \(error)")
            }
        }
        
        return results
    }
    
    // MARK: - Classification (copia esatta da EmailClassifier client)
    
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
            // Assegnazione perito
            let subjectLower = subject.lowercased()
            if subjectLower.contains("assegnazione perito") || 
               (subjectLower.contains("assegnazione") && subjectLower.hasSuffix(":")) {
                matchedPatterns.append("assegnazione")
                return (.assignment, 0.95, matchedPatterns)
            }
            
            // Revoca
            if subjectLower.contains("revoca incarico") || 
               subjectLower.contains("revoca videoperizia") ||
               (subjectLower.contains("sinistro") && subjectLower.contains("revoca incarico")) {
                matchedPatterns.append("revoca incarico")
                return (.revocation, 0.95, matchedPatterns)
            }
            
            // Perizia controllata
            if subject.contains("perizia controllata") {
                let subjectLower = subject.lowercased()
                if subjectLower.contains("perizia controllata:") || 
                   (subjectLower.contains("perizia controllata") && subjectLower.contains("-")) {
                    matchedPatterns.append("perizia controllata")
                    return (.controlled, 0.95, matchedPatterns)
                }
                matchedPatterns.append("perizia controllata")
                return (.controlled, 0.9, matchedPatterns)
            }
            
            // Richiesta revisione - pattern specifico prioritario
            if subject.contains("perizia da revisionare") {
                matchedPatterns.append("perizia da revisionare")
                return (.revisionRequested, 0.98, matchedPatterns)
            }
            
            // Richiesta revisione (pattern generico)
            if subject.contains("richiesta revisione") || subject.contains("revisione perizia") {
                matchedPatterns.append("richiesta revisione")
                return (.revisionRequested, 0.9, matchedPatterns)
            }
        }
        
        // MARK: - Acts (Atti)
        
        // Atto da firmare inviato (SOLO outbound)
        if direction == .outbound {
            let attoOutPatterns = ["atto da firmare", "invio atto", "atto in allegato", "atto di liquidazione", "atto per la firma"]
            for pattern in attoOutPatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append(pattern)
                    return (.actSent, 0.9, matchedPatterns)
                }
            }
        }
        
        // Atto firmato restituito - SOLO per email in entrata (ci restituiscono l'atto firmato)
        if direction == .inbound {
            let attoFirmatoPatterns = [
                "atto firmato", "atto sottoscritto", "firmato in allegato", "quietanza firmata",
                "restituisco l'atto", "restituiamo l'atto", "atto firmato e restituito",
                "inviato firmato", "firmato e inviato", "atto compilato e firmato",
                "ho firmato", "abbiamo firmato", "firmato come richiesto"
            ]
            for pattern in attoFirmatoPatterns {
                if body.contains(pattern) {
                    matchedPatterns.append(pattern)
                    return (.actReceived, 0.95, matchedPatterns)
                }
                if subject.contains(pattern) {
                    matchedPatterns.append(pattern)
                    return (.actReceived, 0.85, matchedPatterns)
                }
            }
            
            // Contestazione importo (in entrata)
            let contestazionePatterns = [
                "non sono d'accordo", "non condivido", "contestazione", "importo non corretto",
                "importo errato", "non accetto", "ritengo che", "non corrisponde",
                "disconforme", "non conforme", "importo diverso", "liquidazione errata"
            ]
            for pattern in contestazionePatterns {
                if body.contains(pattern) {
                    matchedPatterns.append("contestazione: \(pattern)")
                    if hasAttachments {
                        return (.actReceived, 0.8, matchedPatterns)
                    }
                }
            }
            
            // Richiesta spiegazioni (in entrata)
            let spiegazioniPatterns = [
                "spiegazioni", "chiarimenti", "motivazione", "perché", "come mai",
                "non capisco", "vorrei sapere", "potete spiegare", "desidero capire"
            ]
            for pattern in spiegazioniPatterns {
                if body.contains(pattern) && subject.lowercased().contains("atto") {
                    matchedPatterns.append("richiesta spiegazioni: \(pattern)")
                    if hasAttachments {
                        return (.actReceived, 0.75, matchedPatterns)
                    }
                    return (.clarificationRequest, 0.8, matchedPatterns)
                }
            }
            
            // Documentazione aggiuntiva (in entrata con allegati)
            let docAggiuntivaPatterns = [
                "fattura", "fatturazione", "ricevuta", "scontrino", "foto aggiuntive",
                "documentazione aggiuntiva", "ulteriore documentazione", "altri documenti",
                "allego anche", "in allegato anche", "documenti integrativi"
            ]
            for pattern in docAggiuntivaPatterns {
                if body.contains(pattern) && hasAttachments {
                    matchedPatterns.append("documentazione aggiuntiva: \(pattern)")
                    if subject.lowercased().contains("atto") {
                        return (.documentationReceived, 0.85, matchedPatterns)
                    }
                }
            }
            
            // Check nome file allegato per atto firmato
            if hasAttachments && attachmentTypes.contains(where: { 
                $0.contains("atto") && ($0.contains("firmato") || $0.contains("sottoscritto") || $0.contains("compilato"))
            }) {
                matchedPatterns.append("allegato atto firmato")
                return (.actReceived, 0.85, matchedPatterns)
            }
            
            // Atto restituito con oggetto mantenuto (risposta a nostra email)
            if subject.lowercased().contains("atto da firmare") || subject.lowercased().contains("re:") && subject.lowercased().contains("atto") {
                if body.count < 100 || body.lowercased().contains("in allegato") || body.lowercased().contains("allego") {
                    if hasAttachments {
                        matchedPatterns.append("atto restituito (oggetto mantenuto)")
                        return (.actReceived, 0.7, matchedPatterns)
                    }
                }
            }
        }
        
        // MARK: - Documentation
        
        // Richiesta documentazione - SOLO per email in uscita (noi che chiediamo)
        if direction == .outbound {
            let docRequestPatterns = ["richiesta documentazione", "inviare documentazione", "documentazione mancante", "documenti mancanti"]
            for pattern in docRequestPatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append(pattern)
                    return (.documentationRequest, 0.85, matchedPatterns)
                }
            }
        }
        
        // Email in entrata: gestisci risposte a richieste documentazione
        if direction == .inbound {
            // Risposte a richieste di documentazione (Re: Richiesta documentazione...)
            let isReplyToDocRequest = subject.contains("re:") && 
                (subject.contains("richiesta documentazione") || 
                 subject.contains("documentazione mancante") ||
                 subject.contains("documenti mancanti") ||
                 subject.contains("inviare documentazione"))
            
            if isReplyToDocRequest {
                if hasAttachments {
                    // Hanno allegati = documentazione ricevuta
                    matchedPatterns.append("risposta a richiesta documentazione con allegati")
                    return (.documentationReceived, 0.9, matchedPatterns)
                } else {
                    // Senza allegati = comunicazione generica (dicono che manderanno, etc.)
                    matchedPatterns.append("risposta a richiesta documentazione senza allegati")
                    return (.genericCommunication, 0.7, matchedPatterns)
                }
            }
            
            // Altri pattern documentazione ricevuta
            let docReceivedPatterns = ["documentazione", "documenti", "in allegato", "allego", "invio documentazione"]
            for pattern in docReceivedPatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    if hasAttachments {
                        matchedPatterns.append(pattern)
                        return (.documentationReceived, 0.8, matchedPatterns)
                    }
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
        
        let surveyScheduledPatterns = ["sopralluogo fissato", "appuntamento fissato", "confermo sopralluogo", "sopralluogo confermato"]
        for pattern in surveyScheduledPatterns {
            if subject.contains(pattern) || body.contains(pattern) {
                matchedPatterns.append(pattern)
                return (.surveyScheduled, 0.9, matchedPatterns)
            }
        }
        
        let surveyReturnedPatterns = ["sopralluogo restituito", "restituito sopralluogo", "impossibile effettuare", "non eseguibile"]
        for pattern in surveyReturnedPatterns {
            if subject.contains(pattern) || body.contains(pattern) {
                matchedPatterns.append(pattern)
                return (.surveyReturned, 0.9, matchedPatterns)
            }
        }
        
        // MARK: - Videocall
        
        let videocallPatterns = ["videoperizia fissata", "videoperizia confermata", "collegamento video", "videochiamata", "meet", "teams", "zoom"]
        for pattern in videocallPatterns {
            if subject.contains(pattern) || body.contains(pattern) {
                matchedPatterns.append(pattern)
                return (.videocallScheduled, 0.85, matchedPatterns)
            }
        }
        
        // MARK: - Clarification
        
        let clarificationPatterns = ["chiariment", "spiegazione", "domanda", "delucidazione", "precisazione"]
        for pattern in clarificationPatterns {
            if subject.contains(pattern) || body.contains(pattern) {
                matchedPatterns.append(pattern)
                return (.clarificationRequest, 0.8, matchedPatterns)
            }
        }
        
        // MARK: - Outcome
        
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
            
            // Notizie dello studio
            let studioNewsPatterns = ["newsletter", "aggiornamento", "avviso", "notizia", "comunicazione interna", "novità"]
            for pattern in studioNewsPatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append("notizia studio: \(pattern)")
                    return (.studioNews, 0.8, matchedPatterns)
                }
            }
            
            // Info interne
            let internalInfoPatterns = ["ferie", "assenza", "chiusura ufficio", "orario", "turni", "organizzazione", "presenze", "permesso", "malattia"]
            for pattern in internalInfoPatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append("info interna: \(pattern)")
                    return (.internalInfo, 0.85, matchedPatterns)
                }
            }
            
            // Eventi sociali
            let socialPatterns = ["cena", "aperitivo", "festa", "auguri", "compleanno", "natale", "pasqua", "evento", "invito"]
            for pattern in socialPatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append("evento studio: \(pattern)")
                    return (.studioNews, 0.75, matchedPatterns)
                }
            }
            
            // Formazione
            let trainingPatterns = ["formazione", "corso", "webinar", "workshop", "training", "aggiornamento professionale", "seminario"]
            for pattern in trainingPatterns {
                if subject.contains(pattern) || body.contains(pattern) {
                    matchedPatterns.append("formazione: \(pattern)")
                    return (.training, 0.8, matchedPatterns)
                }
            }
        }
        
        // MARK: - File Notification Check (mail interne di notifica nuovi file)
        
        // Solo se mittente interno (stesso dominio) e nessun altro handler ha matchato
        if isInternalSender(senderEmail: senderEmail) {
            // Pattern comuni per mail di notifica file
            let fileNotificationPatterns = [
                "caricato", "caricati", "inserito", "inseriti",
                "foto in cartella", "documenti in", "file in",
                "aggiornato la cartella", "jfish", "gestionale"
            ]
            
            let bodyLower = body.lowercased()
            let hasFilePattern = fileNotificationPatterns.contains { bodyLower.contains($0) }
            
            if hasFilePattern {
                matchedPatterns.append("file_notification: pattern match")
                return (.fileNotification, 0.75, matchedPatterns)
            }
            
            // Se nessun pattern, usa IA per analisi (se disponibile)
            // Questo verrà chiamato in modo asincrono dopo la classificazione iniziale
        }
        
        // MARK: - Default: Generic Communication
        
        return (.genericCommunication, 0.5, matchedPatterns)
    }
    
    /// Verifica se il mittente è interno (stesso dominio utente)
    private func isInternalSender(email: Email) -> Bool {
        return isInternalSender(senderEmail: email.sender.email)
    }
    
    /// Verifica se il mittente è interno dato l'indirizzo email
    private func isInternalSender(senderEmail: String) -> Bool {
        let senderDomain = senderEmail.lowercased().components(separatedBy: "@").last ?? ""
        
        // Domini considerati interni
        let internalDomains = [
            "actsrl.it",
            "allconsulting.org"
        ]
        
        return internalDomains.contains(senderDomain)
    }
    
    /// Analizza email con IA per determinare se parla di file caricati
    public func analyzeForFileNotification(body: String) async -> Bool {
        do {
            return try await HubAIManager.shared.analyzeForFileNotification(body: body)
        } catch {
            print("[EmailProcessor] AI analysis failed: \(error)")
            return false
        }
    }
    
    /// Reclassifica email come fileNotification e crea job scan
    public func reclassifyAsFileNotification(emailId: String, sinistroRef: String) async throws {
        let conn = try await db.db()
        
        // Aggiorna categoria
        try conn.run(
            DatabaseSchema.emails
                .filter(DatabaseSchema.EmailsColumns.messageId == emailId)
                .update(DatabaseSchema.EmailsColumns.category <- "fileNotification")
        )
        
        // Ottieni legacy path
        let sinistroQuery = DatabaseSchema.sinistri.filter(
            DatabaseSchema.SinistriColumns.riferimento == sinistroRef
        )
        
        guard let row = try conn.pluck(sinistroQuery),
              let legacyPath = row[DatabaseSchema.SinistriColumns.legacyPath] else {
            throw EmailProcessorError.sinistroNotFound
        }
        
        // Crea job scan
        _ = try await JobService.shared.createScanLegacyJob(
            sinistroRef: sinistroRef,
            legacyPath: legacyPath,
            priority: 5
        )
        
        print("[EmailProcessor] Email \(emailId) reclassified as fileNotification, scan job created")
    }
    
    // MARK: - Studio Domain Check
    
    private func isFromStudio(senderEmail: String) -> Bool {
        let senderLower = senderEmail.lowercased()
        
        for domain in studioDomains {
            if senderLower.contains(domain) {
                return true
            }
        }
        
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
            "\\[([A-Z0-9\\-/]{5,})\\]"
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
            let filename = attachment.filename.lowercased()
            let ext = (filename as NSString).pathExtension
            return "\(ext):\(filename)"
        }
    }
    
    // MARK: - Database Storage
    
    private func saveEmailToDatabase(email: Email, classified: ClassifiedEmail, accountId: String) async throws {
        let conn = try await db.db()
        
        // Serializza matchedPatterns
        let patternsJson = try? JSONEncoder().encode(classified.matchedPatterns)
        let patternsString = patternsJson.flatMap { String(data: $0, encoding: .utf8) }
        
        // Storage policy condizionale: salva body solo se sinistro attivo
        let bodyToStore = await determineBodyStoragePolicy(
            sinistroRef: classified.sinistroId,
            body: email.body
        )
        
        // Serializza recipients come JSON
        let recipientsJson: String
        if let recipientsData = try? JSONEncoder().encode(email.recipients.map { ["email": $0.email, "name": $0.name ?? ""] }),
           let recipientsString = String(data: recipientsData, encoding: .utf8) {
            recipientsJson = recipientsString
        } else {
            recipientsJson = "[]"
        }
        
        // Inserisci o aggiorna email
        try conn.run(DatabaseSchema.emails.insert(or: .replace,
            DatabaseSchema.emailMessageId <- email.id,
            DatabaseSchema.emailAccountId <- accountId,
            DatabaseSchema.emailSubject <- email.subject,
            DatabaseSchema.emailSenderEmail <- email.sender.email,
            DatabaseSchema.emailSenderName <- email.sender.name,
            DatabaseSchema.EmailsColumns.recipients <- recipientsJson,
            DatabaseSchema.emailDate <- email.date.timeIntervalSince1970,
            DatabaseSchema.emailBody <- bodyToStore,
            DatabaseSchema.emailCategory <- classified.category.rawValue,
            DatabaseSchema.emailDirection <- classified.direction.rawValue,
            DatabaseSchema.emailSenderType <- classified.senderType.rawValue,
            DatabaseSchema.emailSinistroRef <- classified.sinistroId,
            DatabaseSchema.emailConfidence <- classified.confidence,
            DatabaseSchema.emailMatchedPatterns <- patternsString,
            DatabaseSchema.emailIsRead <- email.isRead,
            DatabaseSchema.emailProcessedAt <- Date().timeIntervalSince1970,
            DatabaseSchema.emailSyncedToCK <- false
        ))
        
        // Se sinistro chiuso, salva solo riferimento in archived_email_refs
        if let sinistroRef = classified.sinistroId,
           await isSinistroClosed(sinistroRef: sinistroRef) {
            try conn.run(DatabaseSchema.archivedEmailRefs.insert(or: .replace,
                DatabaseSchema.ArchivedEmailRefsColumns.sinistroRef <- sinistroRef,
                DatabaseSchema.ArchivedEmailRefsColumns.messageId <- email.id,
                DatabaseSchema.ArchivedEmailRefsColumns.date <- email.date.timeIntervalSince1970,
                DatabaseSchema.ArchivedEmailRefsColumns.subject <- email.subject
            ))
        }
    }
    
    /// Determina se salvare il body dell'email o solo il riferimento
    private func determineBodyStoragePolicy(sinistroRef: String?, body: String?) async -> String? {
        guard let ref = sinistroRef, let body = body else {
            // Nessun sinistro associato o nessun body: salva comunque
            return body
        }
        
        // Verifica se il sinistro è chiuso
        if await isSinistroClosed(sinistroRef: ref) {
            // Sinistro chiuso: non salvare body, solo messageId in archived_email_refs
            return nil
        }
        
        // Sinistro attivo: salva body
        return body
    }
    
    /// Verifica se un sinistro è in stato chiuso
    private func isSinistroClosed(sinistroRef: String) async -> Bool {
        do {
            let conn = try await db.db()
            let query = DatabaseSchema.sinistri.filter(
                DatabaseSchema.SinistriColumns.riferimento == sinistroRef
            )
            
            guard let row = try conn.pluck(query) else { return false }
            
            let stato = row[DatabaseSchema.SinistriColumns.stato]
            
            // Stati considerati "chiusi"
            let closedStates = [
                StatoSinistro.chiusa.descrizione,
                StatoSinistro.revocata.descrizione
            ]
            
            return closedStates.contains(stato)
        } catch {
            return false
        }
    }
    
    // MARK: - Batch Classification
    
    func classifyBatch(_ emails: [Email], mailboxId: String? = nil) -> [ClassifiedEmail] {
        return emails.map { classify($0, mailboxId: mailboxId) }
    }
    
    func filterByCategory(_ classifiedEmails: [ClassifiedEmail], categories: [EmailCategory]) -> [ClassifiedEmail] {
        return classifiedEmails.filter { categories.contains($0.category) }
    }
    
    func groupByCategory(_ classifiedEmails: [ClassifiedEmail]) -> [EmailCategory: [ClassifiedEmail]] {
        return Dictionary(grouping: classifiedEmails, by: { $0.category })
    }
    
    // MARK: - Event Generation (Handler Logic)
    
    /// Genera evento basato sulla classificazione dell'email
    /// Replica la logica degli handler del client
    func generateEvent(from classified: ClassifiedEmail) -> HubEmailEvent? {
        let email = classified.originalEmail
        
        switch classified.category {
        case .assignment:
            return handleAssignment(classified)
            
        case .revocation:
            return handleRevocation(classified)
            
        case .actReceived:
            return HubEmailEvent.signedActReceived(
                emailId: email.id,
                sinistroId: classified.sinistroId,
                actType: nil,
                attachmentCount: email.attachments?.count ?? 0
            )
            
        case .actSent:
            return HubEmailEvent.actToSignSent(
                emailId: email.id,
                sinistroId: classified.sinistroId,
                actType: nil,
                recipients: email.recipients.map { $0.email }
            )
            
        case .reminderReceived:
            return HubEmailEvent.reminderReceived(
                emailId: email.id,
                sinistroId: classified.sinistroId,
                senderType: classified.senderType,
                subject: email.subject
            )
            
        case .reminderSent:
            return HubEmailEvent.reminderSent(
                emailId: email.id,
                sinistroId: classified.sinistroId,
                recipients: email.recipients.map { $0.email }
            )
            
        case .documentationReceived:
            return HubEmailEvent.documentationReceived(
                emailId: email.id,
                sinistroId: classified.sinistroId,
                attachmentCount: email.attachments?.count ?? 0,
                attachmentTypes: classified.attachmentTypes,
                senderType: classified.senderType
            )
            
        case .documentationRequest:
            return HubEmailEvent.documentationRequested(
                emailId: email.id,
                sinistroId: classified.sinistroId,
                direction: classified.direction,
                senderType: classified.senderType
            )
            
        case .surveyScheduled:
            return HubEmailEvent.surveyScheduled(
                emailId: email.id,
                sinistroId: classified.sinistroId,
                direction: classified.direction
            )
            
        case .surveyReturned:
            return HubEmailEvent.surveyReturned(
                emailId: email.id,
                sinistroId: classified.sinistroId
            )
            
        case .videocallScheduled:
            return HubEmailEvent.videocallScheduled(
                emailId: email.id,
                sinistroId: classified.sinistroId,
                direction: classified.direction
            )
            
        case .clarificationRequest:
            return HubEmailEvent.clarificationRequested(
                emailId: email.id,
                sinistroId: classified.sinistroId,
                direction: classified.direction,
                senderType: classified.senderType
            )
            
        case .controlled:
            return HubEmailEvent.controlled(
                emailId: email.id,
                sinistroId: classified.sinistroId
            )
            
        case .revisionRequested:
            return HubEmailEvent.revisionRequested(
                emailId: email.id,
                sinistroId: classified.sinistroId
            )
            
        case .outcomeSent:
            return HubEmailEvent.outcomeSent(
                emailId: email.id,
                sinistroId: classified.sinistroId,
                recipients: email.recipients.map { $0.email }
            )
            
        case .verbalAcceptance:
            return HubEmailEvent.verbalAcceptance(
                emailId: email.id,
                sinistroId: classified.sinistroId
            )
            
        case .genericCommunication:
            return HubEmailEvent.genericCommunication(
                emailId: email.id,
                sinistroId: classified.sinistroId,
                direction: classified.direction,
                subject: email.subject,
                sender: email.sender.email,
                hasAttachments: classified.hasAttachments
            )
            
        case .fileNotification:
            // Notifica file: genera evento generico (scan gestito separatamente)
            return HubEmailEvent(
                emailId: email.id,
                sinistroId: classified.sinistroId,
                direction: classified.direction,
                eventType: .genericCommunication
            )
            
        case .studioNews, .internalInfo, .procedure, .meeting, .training,
             .administrative, .newsletter, .spam:
            // Categorie non-sinistro: non generano eventi per ClaimEngine
            return nil
        }
    }
    
    // MARK: - Assignment Handler Logic
    
    private func handleAssignment(_ classified: ClassifiedEmail) -> HubEmailEvent? {
        let email = classified.originalEmail
        
        // Verifica mittente (sempre info@actsrl.it)
        guard email.sender.email.lowercased() == "info@actsrl.it" else {
            print("[EmailProcessor] ⚠️ Assignment: mittente non valido")
            return nil
        }
        
        // Verifica oggetto
        guard email.subject.lowercased().contains("assegnazione") else {
            print("[EmailProcessor] ⚠️ Assignment: oggetto non valido")
            return nil
        }
        
        // Estrai riferimento dal corpo
        guard let body = email.body else {
            print("[EmailProcessor] ⚠️ Assignment: corpo mancante")
            return nil
        }
        
        // Pattern per formato standard assegnazioni
        let pattern = #"per\s+il\s+sinistro\s+\[?([0-9]{7})\]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(location: 0, length: body.utf16.count)
        guard let match = regex.firstMatch(in: body, range: range),
              match.range(at: 1).location != NSNotFound else {
            print("[EmailProcessor] ⚠️ Assignment: riferimento non trovato")
            return nil
        }
        
        let riferimento = (body as NSString).substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !riferimento.isEmpty, riferimento.count == 7 else {
            print("[EmailProcessor] ⚠️ Assignment: riferimento non valido")
            return nil
        }
        
        // Determina assegnatario: chi riceve la mail
        let recipientEmail = email.recipients.first?.email
        let recipientName = email.recipients.first?.name
        
        // Estrai dati aggiuntivi
        let extractedData = extractDataFromBody(body)
        
        print("[EmailProcessor] ✅ Assignment: riferimento \(riferimento)")
        
        return HubEmailEvent.assignmentReceived(
            emailId: email.id,
            riferimento: riferimento,
            assignmentDate: email.date,
            assigneeEmail: recipientEmail,
            assigneeName: recipientName,
            extractedData: extractedData
        )
    }
    
    // MARK: - Revocation Handler Logic
    
    private func handleRevocation(_ classified: ClassifiedEmail) -> HubEmailEvent? {
        let email = classified.originalEmail
        
        // Verifica mittente
        guard email.sender.email.lowercased() == "info@actsrl.it" else {
            print("[EmailProcessor] ⚠️ Revocation: mittente non valido")
            return nil
        }
        
        // Estrai riferimento
        guard let riferimento = extractRevocationReference(from: email.subject) else {
            print("[EmailProcessor] ⚠️ Revocation: riferimento non trovato")
            return nil
        }
        
        // Estrai motivo se presente
        let reason = extractRevocationReason(from: email.body ?? "")
        
        print("[EmailProcessor] ✅ Revocation: riferimento \(riferimento)")
        
        return HubEmailEvent.revocationReceived(
            emailId: email.id,
            riferimento: riferimento,
            reason: reason
        )
    }
    
    private func extractRevocationReference(from subject: String) -> String? {
        let patterns = [
            #"revoca\s+incarico\s+(?:videoperizia\s+)?per\s+sinistro\s+([0-9]{7})"#,
            #"ns[.]?\s*rif[.]?\s+([0-9]{7})\s+REVOCA\s+INCARICO"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: subject.utf16.count)
                if let match = regex.firstMatch(in: subject, range: range),
                   match.range(at: 1).location != NSNotFound {
                    let riferimento = (subject as NSString).substring(with: match.range(at: 1))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !riferimento.isEmpty && riferimento.count == 7 {
                        return riferimento
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractRevocationReason(from body: String) -> String? {
        let patterns = [
            "motivo[:\\s]+(.+?)(?:\\n|\\.|$)",
            "causa[:\\s]+(.+?)(?:\\n|\\.|$)",
            "perch[eé][:\\s]+(.+?)(?:\\n|\\.|$)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(body.startIndex..<body.endIndex, in: body)
                if let match = regex.firstMatch(in: body, options: [], range: range),
                   let reasonRange = Range(match.range(at: 1), in: body) {
                    return String(body[reasonRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Data Extraction Helpers
    
    private func extractDataFromBody(_ body: String) -> [String: String] {
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
        
        // Pattern per nome
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
            let groupRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
            if let swiftRange = Range(groupRange, in: text) {
                return String(text[swiftRange])
            }
        }
        
        return nil
    }
    
    // MARK: - Save Event to Database
    
    func saveEvent(_ event: HubEmailEvent) async throws {
        let conn = try await db.db()
        
        let eventJson = try JSONEncoder().encode(event)
        guard let eventString = String(data: eventJson, encoding: .utf8) else {
            throw EmailProcessorError.encodingError
        }
        
        // Salva evento in tabella dedicata (se esiste) o log
        print("[EmailProcessor] 📤 Evento generato: \(event.eventType.rawValue) per email \(event.emailId)")
        
        // TODO: Inviare a ClaimEngine o salvare in tabella eventi
    }
}

// MARK: - Errors

enum EmailProcessorError: Error {
    case encodingError
    case decodingError
    case databaseError(String)
    case sinistroNotFound
}
