import Foundation

/// Risultato dell'analisi di una comunicazione
struct CommunicationAnalysisResult {
    var intent: CommunicationIntent
    var urgency: UrgencyLevel
    var context: CommunicationContext
    var extractedData: ExtractedData
    var requiresAction: Bool
    var suggestedActions: [SuggestedAction]
    var confidence: Double
}

/// Intenti possibili di una comunicazione
enum CommunicationIntent: String, Codable {
    case acceptAmount = "accept_amount"
    case contestAmount = "contest_amount"
    case requestDocumentation = "request_documentation"
    case provideDocumentation = "provide_documentation"
    case documentationReceived = "documentation_received"
    case requestRecontact = "request_recontact"
    case surveyReturned = "survey_returned"
    case surveyScheduled = "survey_scheduled"
    case surveyCompleted = "survey_completed"
    case revisionRequested = "revision_requested"
    case verbalAcceptance = "verbal_acceptance"
    case clarificationRequest = "clarification_request"
    case acknowledgment = "acknowledgment"
    case genericAction = "generic_action"
    case noAction = "no_action"
}

/// Livello di urgenza
enum UrgencyLevel: String, Codable {
    case low = "low"
    case normal = "normal"
    case high = "high"
    case urgent = "urgent"
}

/// Contesto della comunicazione
struct CommunicationContext: Codable {
    var senderType: SenderType
    var originalSender: String? // Mittente originale se inoltrata
    var isForwarded: Bool
    var domain: String?
}

enum SenderType: String, Codable {
    case insured = "insured"
    case agent = "agent"
    case broker = "broker"
    case liquidator = "liquidator"
    case company = "company"
    // Ruoli interni dello studio
    case partner = "partner" // Capo supremo
    case teamLeader = "team_leader"
    case secretary = "secretary" // Segreteria/back office
    case colleague = "colleague" // Altri periti/loss adjuster
    case companyGeneric = "company_generic" // info@actsrl.it o mail generica
    case unknown = "unknown"
}

/// Dati estratti dalla comunicazione
struct ExtractedData: Codable {
    var iban: String?
    var phoneNumbers: [String]
    var relevantPhoneNumber: String? // Numero da usare (filtrato)
    var amounts: [Decimal]
    var dates: [Date]
    var attachmentTypes: [String]
    var hasAttachments: Bool
}

/// Azione suggerita
struct SuggestedAction: Codable {
    var type: ActionType
    var title: String
    var description: String
    var priority: Double
    var deadline: Date?
    var metadata: [String: AnyCodable]
}

enum ActionType: String, Codable {
    case downloadAttachment = "download_attachment"
    case tagFile = "tag_file"
    case updateState = "update_state"
    case createTask = "create_task"
    case createFolder = "create_folder"
    case saveFiles = "save_files"
}

/// Servizio per analisi intelligente delle comunicazioni
@MainActor
class CommunicationAnalysisService {
    static let shared = CommunicationAnalysisService()
    
    private let appleAIService = AppleIntelligenceService.shared
    private let localModelService = LocalModelService.shared
    private let cloudAIService = CloudAIService.shared
    private let aiManager = AIManager.shared
    
    private init() {}
    
    /// Analizza una comunicazione e determina intento, urgenza e azioni necessarie
    func analyzeCommunication(
        subject: String?,
        body: String,
        senderEmail: String?,
        hasAttachments: Bool,
        attachmentTypes: [String] = [],
        sinistroID: String? = nil
    ) async -> CommunicationAnalysisResult {
        let fullText = "\(subject ?? "")\n\n\(body)"
        let lowercased = fullText.lowercased()
        
        // Estrazione rapida con Apple Intelligence
        let extractedInfo = await appleAIService.extractEmailInfo(from: body)
        
        // Analisi semantica con AI (ibrido)
        let semanticAnalysis = await performSemanticAnalysis(
            subject: subject ?? "",
            body: body,
            senderEmail: senderEmail ?? "",
            hasAttachments: hasAttachments,
            attachmentTypes: attachmentTypes
        )
        
        // Classificazione intento
        let intent = classifyIntent(
            text: lowercased,
            semanticAnalysis: semanticAnalysis,
            hasAttachments: hasAttachments,
            attachmentTypes: attachmentTypes
        )
        
        // Estrazione dati
        let extractedData = extractData(
            text: body,
            extractedInfo: extractedInfo,
            senderEmail: senderEmail ?? "",
            hasAttachments: hasAttachments,
            attachmentTypes: attachmentTypes
        )
        
        // Rilevamento urgenza
        let urgency = detectUrgency(text: lowercased, semanticAnalysis: semanticAnalysis)
        
        // Contesto
        let context = determineContext(senderEmail: senderEmail ?? "", body: body, text: lowercased)
        
        // Azioni suggerite
        let suggestedActions = generateSuggestedActions(
            intent: intent,
            extractedData: extractedData,
            urgency: urgency,
            context: context,
            sinistroID: sinistroID
        )
        
        let requiresAction = !suggestedActions.isEmpty && intent != .noAction && intent != .acknowledgment
        
        return CommunicationAnalysisResult(
            intent: intent,
            urgency: urgency,
            context: context,
            extractedData: extractedData,
            requiresAction: requiresAction,
            suggestedActions: suggestedActions,
            confidence: semanticAnalysis.confidence
        )
    }
    
    // MARK: - Semantic Analysis
    
    private struct SemanticAnalysisResult {
        var summary: String
        var keyPoints: [String]
        var tone: String
        var confidence: Double
    }
    
    private func performSemanticAnalysis(
        subject: String,
        body: String,
        senderEmail: String,
        hasAttachments: Bool,
        attachmentTypes: [String]
    ) async -> SemanticAnalysisResult {
        let prompt = """
        Analizza questa comunicazione e fornisci:
        1. Riassunto breve (max 2 frasi)
        2. Punti chiave (lista)
        3. Tono (formale/informale/urgente/neutro)
        4. Livello di confidenza (0.0-1.0)
        
        Oggetto: \(subject)
        Corpo: \(body)
        Allegati: \(hasAttachments ? "Sì (\(attachmentTypes.joined(separator: ", ")))" : "No")
        
        Rispondi in formato JSON:
        {
            "summary": "...",
            "keyPoints": ["...", "..."],
            "tone": "...",
            "confidence": 0.0
        }
        """
        
        // Prova prima con Apple Intelligence (veloce)
        if AppleAIService.shared.isAvailable {
            let task = AITask(
                type: .textAnalysis,
                priority: .primary,
                preferredProvider: .appleIntelligence,
                parameters: ["text": AnyCodable(prompt)]
            )
            
            let result = await withCheckedContinuation { continuation in
                aiManager.enqueue(task) { result in
                    if result.success, let text = result.result?.value as? String {
                        continuation.resume(returning: self.parseSemanticResponse(text))
                    } else {
                        continuation.resume(returning: SemanticAnalysisResult(
                            summary: "",
                            keyPoints: [],
                            tone: "neutro",
                            confidence: 0.5
                        ))
                    }
                }
            }
            
            if result.confidence > 0.6 {
                return result
            }
        }
        
        // Fallback su Phi-4 (locale) per complessità
        if localModelService.isTextAvailable {
            let task = AITask(
                type: .textAnalysis,
                priority: .primary,
                preferredProvider: .localText,
                parameters: ["text": AnyCodable(prompt)]
            )
            
            let result = await withCheckedContinuation { continuation in
                aiManager.enqueue(task) { result in
                    if result.success, let text = result.result?.value as? String {
                        continuation.resume(returning: self.parseSemanticResponse(text))
                    } else {
                        continuation.resume(returning: SemanticAnalysisResult(
                            summary: "",
                            keyPoints: [],
                            tone: "neutro",
                            confidence: 0.5
                        ))
                    }
                }
            }
            
            if result.confidence > 0.5 {
                return result
            }
        }
        
        // Fallback finale su OpenAI
        if cloudAIService.isAvailable {
            let task = AITask(
                type: .textAnalysis,
                priority: .primary,
                preferredProvider: .cloudOpenAI,
                parameters: ["text": AnyCodable(prompt)]
            )
            
            let result = await withCheckedContinuation { continuation in
                aiManager.enqueue(task) { result in
                    if result.success, let text = result.result?.value as? String {
                        continuation.resume(returning: self.parseSemanticResponse(text))
                    } else {
                        continuation.resume(returning: SemanticAnalysisResult(
                            summary: "",
                            keyPoints: [],
                            tone: "neutro",
                            confidence: 0.5
                        ))
                    }
                }
            }
            
            return result
        }
        
        // Fallback base senza AI
        return SemanticAnalysisResult(
            summary: String(body.prefix(200)),
            keyPoints: [],
            tone: "neutro",
            confidence: 0.3
        )
    }
    
    private func parseSemanticResponse(_ text: String) -> SemanticAnalysisResult {
        // Prova a parsare JSON
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let summary = json["summary"] as? String ?? ""
            let keyPoints = json["keyPoints"] as? [String] ?? []
            let tone = json["tone"] as? String ?? "neutro"
            let confidence = json["confidence"] as? Double ?? 0.5
            
            return SemanticAnalysisResult(
                summary: summary,
                keyPoints: keyPoints,
                tone: tone,
                confidence: confidence
            )
        }
        
        // Fallback: analisi semplice
        return SemanticAnalysisResult(
            summary: String(text.prefix(200)),
            keyPoints: [],
            tone: "neutro",
            confidence: 0.5
        )
    }
    
    // MARK: - Intent Classification
    
    private func classifyIntent(
        text: String,
        semanticAnalysis: SemanticAnalysisResult,
        hasAttachments: Bool,
        attachmentTypes: [String]
    ) -> CommunicationIntent {
        // Documentazione ricevuta
        if hasAttachments && (text.contains("documentazione") || text.contains("allego") || text.contains("in allegato")) {
            return .documentationReceived
        }
        
        // Revisione richiesta
        if text.contains("richiesta revisione") || text.contains("chiediamo revisione") || text.contains("da rivedere") {
            return .revisionRequested
        }
        
        // Accettazione verbale
        if text.contains("accettazione verbale") || text.contains("accettiamo senza atto") || text.contains("accetto senza firmare") {
            return .verbalAcceptance
        }
        
        // Sopralluogo/videoperizia fissato
        if (text.contains("sopralluogo") || text.contains("videoperizia")) &&
            (text.contains("fissato") || text.contains("concordato") || text.contains("programmato")) {
            return .surveyScheduled
        }
        
        // Sopralluogo restituito/completato
        if text.contains("sopralluogo restituito") || text.contains("sopralluogo eseguito") || text.contains("rapporto sopralluogo") {
            return .surveyCompleted
        }
        
        // Pattern per accettazione importo
        if text.contains("accetto") || text.contains("accettiamo") || text.contains("accettato") {
            if text.contains("importo") || text.contains("liquidazione") || text.contains("stima") {
                return .acceptAmount
            }
        }
        
        // Pattern per contestazione
        if text.contains("contest") || text.contains("non concord") || text.contains("non accett") {
            if text.contains("importo") || text.contains("liquidazione") || text.contains("stima") {
                return .contestAmount
            }
        }
        
        // Pattern per documentazione
        if text.contains("alleg") || text.contains("documentaz") || text.contains("foto") {
            if hasAttachments {
                return .provideDocumentation
            } else if text.contains("richied") || text.contains("inviat") {
                return .requestDocumentation
            }
        }
        
        // Pattern per ricontatto
        if text.contains("ricontatt") || text.contains("richiam") || text.contains("chiamat") {
            return .requestRecontact
        }
        
        // Pattern per sopralluogo restituito
        if text.contains("sopralluogo") && (text.contains("restituit") || text.contains("eseguit") || text.contains("completat")) {
            return .surveyReturned
        }
        
        // Pattern per chiarimenti
        if text.contains("chiariment") || text.contains("spiegazion") || text.contains("domanda") {
            if text.contains("liquidazione") || text.contains("importo") {
                return .clarificationRequest
            }
        }
        
        // Pattern per riconoscimento
        if text.contains("grazie") && !text.contains("richied") && !text.contains("chied") {
            return .acknowledgment
        }
        
        // Se ha allegati e richiede azione
        if hasAttachments && !semanticAnalysis.keyPoints.isEmpty {
            return .genericAction
        }
        
        return .noAction
    }
    
    // MARK: - Data Extraction
    
    private func extractData(
        text: String,
        extractedInfo: EmailExtractedInfo,
        senderEmail: String,
        hasAttachments: Bool,
        attachmentTypes: [String]
    ) -> ExtractedData {
        // Estrazione IBAN
        let iban = extractIBAN(from: text)
        
        // Estrazione numeri telefono (con filtro per @actsrl.it)
        let allPhones = extractedInfo.phoneNumbers
        let relevantPhone = filterRelevantPhoneNumber(
            phones: allPhones,
            senderEmail: senderEmail,
            text: text
        )
        
        return ExtractedData(
            iban: iban,
            phoneNumbers: allPhones,
            relevantPhoneNumber: relevantPhone,
            amounts: extractedInfo.amounts,
            dates: extractedInfo.dates,
            attachmentTypes: attachmentTypes,
            hasAttachments: hasAttachments
        )
    }
    
    private func extractIBAN(from text: String) -> String? {
        // Pattern IBAN italiano (IT + 2 caratteri + 1 lettera + 23 cifre)
        let pattern = "IT\\d{2}[A-Z]\\d{22}"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let ibanRange = Range(match.range, in: text) {
                return String(text[ibanRange]).uppercased()
            }
        }
        return nil
    }
    
    private func filterRelevantPhoneNumber(
        phones: [String],
        senderEmail: String,
        text: String
    ) -> String? {
        // Se la mail arriva da @actsrl.it, ignora numeri in firma
        if senderEmail.lowercased().contains("@actsrl.it") {
            // Cerca solo nel corpo principale (prima di pattern di firma)
            let cleanedText = cleanEmailBody(text)
            let phonesInBody = extractPhonesFromText(cleanedText)
            return phonesInBody.first
        }
        
        // Cerca pattern espliciti nel testo
        let lowercased = text.lowercased()
        if lowercased.contains("ha chiesto ricontatto") || lowercased.contains("chiediamo ricontatto") {
            // Cerca numero dopo il pattern
            for phone in phones {
                if let range = text.range(of: phone, options: .caseInsensitive) {
                    let contextBefore = String(text[..<range.lowerBound]).lowercased()
                    if contextBefore.contains("ricontatto") || contextBefore.contains("chiamat") {
                        return phone
                    }
                }
            }
        }
        
        return phones.first
    }
    
    private func cleanEmailBody(_ body: String) -> String {
        // Rimuove firma e note di servizio (simile a AppleIntelligenceService)
        var cleaned = body
        let signaturePatterns = [
            "--\\s*$",
            "---\\s*$",
            "________________________________",
            "Sent from",
            "Inviato da"
        ]
        
        for pattern in signaturePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]) {
                let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
                if let match = regex.firstMatch(in: cleaned, options: [], range: range),
                   let matchRange = Range(match.range, in: cleaned) {
                    cleaned = String(cleaned[..<matchRange.lowerBound])
                    break
                }
            }
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractPhonesFromText(_ text: String) -> [String] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var phones: [String] = []
        
        detector?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let match = match, let phoneRange = Range(match.range, in: text) {
                phones.append(String(text[phoneRange]))
            }
        }
        
        return phones
    }
    
    // MARK: - Urgency Detection
    
    private func detectUrgency(
        text: String,
        semanticAnalysis: SemanticAnalysisResult
    ) -> UrgencyLevel {
        let urgentKeywords = ["urgente", "immediato", "asap", "subito", "priorità", "critico"]
        let highKeywords = ["importante", "tempestivo", "presto"]
        
        if urgentKeywords.contains(where: { text.contains($0) }) || semanticAnalysis.tone == "urgente" {
            return .urgent
        }
        
        if highKeywords.contains(where: { text.contains($0) }) {
            return .high
        }
        
        return .normal
    }
    
    // MARK: - Context Determination
    
    private func determineContext(
        senderEmail: String,
        body: String,
        text: String
    ) -> CommunicationContext {
        let lowercasedEmail = senderEmail.lowercased()
        let lowercasedText = text.lowercased()
        
        var senderType: SenderType = .unknown
        
        // Verifica se è una comunicazione interna dello studio
        let isInternalEmail = lowercasedEmail.contains("@actsrl.it") || lowercasedEmail.contains("@allconsulting.org")
        
        if isInternalEmail {
            // Determina il ruolo dalla firma
            senderType = detectInternalRole(senderEmail: senderEmail, body: body)
        } else {
            // Logica esistente per email esterne
            if lowercasedEmail.contains("liquidatore") || lowercasedEmail.contains("perito") {
                senderType = .liquidator
            } else if lowercasedEmail.contains("agenzia") || lowercasedEmail.contains("agente") {
                senderType = .agent
            } else if lowercasedEmail.contains("broker") || lowercasedEmail.contains("intermediario") {
                senderType = .broker
            } else if lowercasedEmail.contains("compagnia") || lowercasedEmail.contains("assicurazione") {
                senderType = .company
            } else {
                senderType = .insured
            }
        }
        
        // Rileva se è inoltrata
        let isForwarded = lowercasedText.contains("inoltro") || lowercasedText.contains("forwarded") || isInternalEmail
        
        // Estrai mittente originale se inoltrata
        var originalSender: String? = nil
        if isForwarded {
            // Cerca pattern "Da: email" o "From: email"
            let patterns = [
                "da:\\s*([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})",
                "from:\\s*([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})"
            ]
            
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(text.startIndex..<text.endIndex, in: text)
                    if let match = regex.firstMatch(in: text, options: [], range: range),
                       let emailRange = Range(match.range(at: 1), in: text) {
                        originalSender = String(text[emailRange])
                        break
                    }
                }
            }
        }
        
        let domain = senderEmail.components(separatedBy: "@").last
        
        return CommunicationContext(
            senderType: senderType,
            originalSender: originalSender,
            isForwarded: isForwarded,
            domain: domain
        )
    }
    
    /// Rileva il ruolo interno dello studio dalla firma dell'email
    private func detectInternalRole(senderEmail: String, body: String) -> SenderType {
        // Mail generica dello studio
        if senderEmail.lowercased() == "info@actsrl.it" || senderEmail.lowercased() == "info@allconsulting.org" {
            return .companyGeneric
        }
        
        // Estrai la firma dal body (parte dopo separatori comuni)
        let signature = extractSignature(from: body)
        let lowercasedSignature = signature.lowercased()
        
        // Pattern per Partner (capo supremo)
        let partnerPatterns = [
            "partner",
            "socio",
            "amministratore",
            "ad",
            "amministratore delegato",
            "ceo",
            "presidente"
        ]
        if partnerPatterns.contains(where: { lowercasedSignature.contains($0) }) {
            return .partner
        }
        
        // Pattern per Team Leader
        let teamLeaderPatterns = [
            "team leader",
            "responsabile",
            "coordinatore",
            "supervisore",
            "capo team",
            "head of"
        ]
        if teamLeaderPatterns.contains(where: { lowercasedSignature.contains($0) }) {
            return .teamLeader
        }
        
        // Pattern per Segreteria/Back Office
        let secretaryPatterns = [
            "segreteria",
            "back office",
            "ufficio",
            "assistente",
            "segretaria",
            "segretario",
            "amministrazione",
            "amministrativo"
        ]
        if secretaryPatterns.contains(where: { lowercasedSignature.contains($0) }) {
            return .secretary
        }
        
        // Pattern per altri periti/loss adjuster
        let colleaguePatterns = [
            "perito",
            "loss adjuster",
            "liquidatore",
            "tecnico",
            "consulente"
        ]
        if colleaguePatterns.contains(where: { lowercasedSignature.contains($0) }) {
            return .colleague
        }
        
        // Default: collega generico se è interno ma non si trova un ruolo specifico
        return .colleague
    }
    
    /// Estrae la firma dal body dell'email
    private func extractSignature(from body: String) -> String {
        // Cerca separatori comuni di firma
        let signatureSeparators = [
            "--",
            "---",
            "________________________________",
            "Sent from",
            "Inviato da",
            "Da:",
            "Il giorno"
        ]
        
        var signature = body
        
        // Trova il primo separatore e prendi tutto ciò che viene dopo
        for separator in signatureSeparators {
            if let range = signature.range(of: separator, options: [.caseInsensitive, .diacriticInsensitive]) {
                signature = String(signature[range.upperBound...])
                break
            }
        }
        
        // Se non trovato, prova a cercare pattern HTML comuni per firme
        if signature == body {
            // Cerca tag HTML comuni per firme
            let htmlPatterns = [
                "<div[^>]*class[^>]*signature[^>]*>",
                "<div[^>]*id[^>]*signature[^>]*>",
                "<table[^>]*class[^>]*signature[^>]*>"
            ]
            
            for pattern in htmlPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                    let range = NSRange(body.startIndex..<body.endIndex, in: body)
                    if let match = regex.firstMatch(in: body, options: [], range: range) {
                        // Estrai tutto dopo il match
                        if let matchRange = Range(match.range, in: body) {
                            signature = String(body[matchRange.upperBound...])
                            break
                        }
                    }
                }
            }
        }
        
        // Pulisci HTML se presente
        signature = signature.strippingHTML()
        
        // Limita la lunghezza (le firme sono generalmente brevi)
        return String(signature.prefix(500))
    }
    
    // MARK: - Action Generation
    
    private func generateSuggestedActions(
        intent: CommunicationIntent,
        extractedData: ExtractedData,
        urgency: UrgencyLevel,
        context: CommunicationContext,
        sinistroID: String?
    ) -> [SuggestedAction] {
        var actions: [SuggestedAction] = []
        
        switch intent {
        case .acceptAmount:
            if extractedData.iban != nil || extractedData.hasAttachments {
                actions.append(SuggestedAction(
                    type: .downloadAttachment,
                    title: "Scarica e tagga atto sottoscritto",
                    description: "Scarica l'allegato e taggalo come 'atto sottoscritto'",
                    priority: urgency == .urgent ? 0.9 : 0.7,
                    deadline: nil,
                    metadata: [
                        "tag": AnyCodable("atto sottoscritto"),
                        "newState": AnyCodable("Atto ricevuto sottoscritto")
                    ]
                ))
                
                actions.append(SuggestedAction(
                    type: .updateState,
                    title: "Aggiorna stato in Atto ricevuto sottoscritto",
                    description: "Aggiorna lo stato del sinistro",
                    priority: 0.8,
                    deadline: nil,
                    metadata: ["newState": AnyCodable("Atto ricevuto sottoscritto")]
                ))
                
                let closeTitle = sinistroID.map { "Chiudere sinistro \($0)" } ?? "Chiudere sinistro"
                actions.append(SuggestedAction(
                    type: .createTask,
                    title: closeTitle,
                    description: "Chiudere il sinistro dopo verifica atto",
                    priority: 0.6,
                    deadline: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
                    metadata: ["taskType": AnyCodable("close_sinistro")]
                ))
            }
            
        case .provideDocumentation:
            if extractedData.hasAttachments {
                let folderName = context.senderType == .insured ? "da WA" : "da mail"
                actions.append(SuggestedAction(
                    type: .saveFiles,
                    title: "Salva documentazione",
                    description: "Salva gli allegati nella cartella '\(folderName)'",
                    priority: 0.7,
                    deadline: nil,
                    metadata: [
                        "folder": AnyCodable(folderName),
                        "createFolderIfNeeded": AnyCodable(true)
                    ]
                ))
                
                let verifyTitle = sinistroID.map { "Verificare documentazione - \($0)" } ?? "Verificare documentazione pervenuta"
                actions.append(SuggestedAction(
                    type: .createTask,
                    title: verifyTitle,
                    description: "Verifica la documentazione ricevuta",
                    priority: 0.6,
                    deadline: nil,
                    metadata: ["taskType": AnyCodable("verify_documentation")]
                ))
            }
            
        case .contestAmount:
            let contestTitle = sinistroID.map { "Gestire contestazione - \($0)" } ?? "Gestire contestazione esito"
            actions.append(SuggestedAction(
                type: .createTask,
                title: contestTitle,
                description: "Gestisci la contestazione dell'importo proposto",
                priority: urgency == .urgent ? 0.9 : 0.8,
                deadline: urgency == .urgent ? Calendar.current.date(byAdding: .day, value: 1, to: Date()) : Calendar.current.date(byAdding: .day, value: 3, to: Date()),
                metadata: [
                    "taskType": AnyCodable("handle_contestation"),
                    "linkToCommunication": AnyCodable(true)
                ]
            ))
            
        case .requestRecontact:
            let recontactTitle = sinistroID.map { "Ricontattare - \($0)" } ?? "Ricontattare cliente"
            actions.append(SuggestedAction(
                type: .createTask,
                title: recontactTitle,
                description: extractedData.relevantPhoneNumber != nil 
                    ? "Ricontattare al numero \(extractedData.relevantPhoneNumber!)"
                    : "Ricontattare il cliente",
                priority: urgency == .urgent ? 0.8 : 0.6,
                deadline: urgency == .urgent ? Date() : Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                metadata: [
                    "taskType": AnyCodable("recontact"),
                    "phoneNumber": AnyCodable(extractedData.relevantPhoneNumber ?? ""),
                    "senderType": AnyCodable(context.senderType.rawValue)
                ]
            ))
            
        case .surveyReturned:
            actions.append(SuggestedAction(
                type: .updateState,
                title: "Aggiorna stato in Da Eseguire",
                description: "Sopralluogo restituito",
                priority: 0.7,
                deadline: nil,
                metadata: ["newState": AnyCodable("Da Eseguire")]
            ))
            
            let periziaTitle = sinistroID.map { "Eseguire perizia - \($0)" } ?? "Eseguire perizia: sopralluogo restituito"
            actions.append(SuggestedAction(
                type: .createTask,
                title: periziaTitle,
                description: "Esegui la perizia dopo il sopralluogo",
                priority: 0.8,
                deadline: Calendar.current.date(byAdding: .day, value: 5, to: Date()),
                metadata: ["taskType": AnyCodable("execute_survey")]
            ))
            
        case .clarificationRequest:
            let clarificationTitle = sinistroID.map { "Rispondere chiarimenti - \($0)" } ?? "Rispondere a richiesta chiarimenti"
            actions.append(SuggestedAction(
                type: .createTask,
                title: clarificationTitle,
                description: "Fornisci chiarimenti sulla liquidazione",
                priority: urgency == .urgent ? 0.7 : 0.5,
                deadline: urgency == .urgent ? Calendar.current.date(byAdding: .day, value: 1, to: Date()) : Calendar.current.date(byAdding: .day, value: 3, to: Date()),
                metadata: ["taskType": AnyCodable("clarification")]
            ))
            
        case .genericAction:
            let genericTitle = sinistroID.map { "Gestire comunicazione - \($0)" } ?? "Gestire comunicazione"
            actions.append(SuggestedAction(
                type: .createTask,
                title: genericTitle,
                description: "Comunicazione che richiede attenzione",
                priority: urgency == .urgent ? 0.7 : 0.5,
                deadline: urgency == .urgent ? Date() : Calendar.current.date(byAdding: .day, value: 2, to: Date()),
                metadata: ["taskType": AnyCodable("generic")]
            ))
            
        case .documentationReceived:
            actions.append(SuggestedAction(
                type: .updateState,
                title: "Aggiorna stato: doc ricevuta",
                description: "Documentazione ricevuta",
                priority: 0.7,
                deadline: nil,
                metadata: ["newState": AnyCodable("Perizia da eseguire (documentale)")]
            ))
            actions.append(SuggestedAction(
                type: .createTask,
                title: "Verificare documentazione ricevuta",
                description: "Controlla e processa la documentazione arrivata",
                priority: 0.6,
                deadline: nil,
                metadata: ["taskType": AnyCodable("verify_documentation")]
            ))
            
        case .surveyScheduled:
            actions.append(SuggestedAction(
                type: .updateState,
                title: "Aggiorna stato: sopralluogo fissato",
                description: "Sopralluogo/Videoperizia fissata",
                priority: 0.7,
                deadline: nil,
                metadata: ["newState": AnyCodable("Sopralluogo fissato")]
            ))
            
        case .surveyCompleted:
            actions.append(SuggestedAction(
                type: .updateState,
                title: "Aggiorna stato: sopralluogo restituito",
                description: "Rapporto sopralluogo ricevuto",
                priority: 0.7,
                deadline: nil,
                metadata: ["newState": AnyCodable("Sopralluogo restituito")]
            ))
            actions.append(SuggestedAction(
                type: .createTask,
                title: "Eseguire perizia post sopralluogo",
                description: "Completa la perizia con i dati del sopralluogo",
                priority: 0.7,
                deadline: Calendar.current.date(byAdding: .day, value: 5, to: Date()),
                metadata: ["taskType": AnyCodable("execute_survey")]
            ))
            
        case .revisionRequested:
            actions.append(SuggestedAction(
                type: .updateState,
                title: "Aggiorna stato: richiesta revisione",
                description: "Gestire la revisione richiesta",
                priority: 0.9,
                deadline: nil,
                metadata: ["newState": AnyCodable("Richiesta revisione")]
            ))
            actions.append(SuggestedAction(
                type: .createTask,
                title: "Gestire richiesta revisione",
                description: "Rivedi il fascicolo e aggiorna l'esito",
                priority: 0.9,
                deadline: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
                metadata: ["taskType": AnyCodable("handle_contestation")]
            ))
            
        case .verbalAcceptance:
            actions.append(SuggestedAction(
                type: .updateState,
                title: "Aggiorna stato: accettazione verbale",
                description: "Accettazione senza atto sottoscritto",
                priority: 0.8,
                deadline: nil,
                metadata: ["newState": AnyCodable("Accettata verbalmente")]
            ))
            actions.append(SuggestedAction(
                type: .createTask,
                title: "Chiudere sinistro (accettazione verbale)",
                description: "Formalizza chiusura o ottieni atto firmato",
                priority: 0.8,
                deadline: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
                metadata: ["taskType": AnyCodable("close_sinistro")]
            ))
            
        default:
            break
        }
        
        return actions
    }
}

