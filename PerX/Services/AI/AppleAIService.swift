import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Wrapper per Apple Intelligence integrato nel manager AI
/// Usa FoundationModels su macOS 26+ / iOS 18.4+, fallback su NaturalLanguage
class AppleAIService {
    static let shared = AppleAIService()
    
    #if canImport(FoundationModels)
    private var languageModelSession: LanguageModelSession?
    #endif
    
    private let appleIntelligence = AppleIntelligenceService.shared
    
    /// Indica se Apple Intelligence (FoundationModels) è disponibile
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 18.4, *) {
            // Verifica se il dispositivo supporta Apple Intelligence
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        // Fallback: NaturalLanguage è sempre disponibile
        return true
    }
    
    /// Indica se FoundationModels è disponibile (vero Apple Intelligence)
    var isFoundationModelsAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 18.4, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }
    
    private init() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 18.4, *) {
            // Inizializza la sessione del modello linguistico
            initializeSession()
        }
        #endif
    }
    
    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 18.4, *)
    private func initializeSession() {
        Task {
            do {
                let model = SystemLanguageModel.default
                if model.isAvailable {
                    languageModelSession = LanguageModelSession()
                    print("[AppleAIService] ✅ FoundationModels inizializzato")
                } else {
                    print("[AppleAIService] ⚠️ Apple Intelligence non disponibile su questo dispositivo")
                }
            }
        }
    }
    #endif
    
    // MARK: - Public API
    
    /// Esegue un task usando Apple Intelligence
    func executeTask(_ task: AITask) async -> Result<AIResult, AIError> {
        let startTime = Date()
        
        do {
            switch task.type {
            case .emailSummary:
                return await handleEmailSummary(task: task, startTime: startTime)
            case .textAnalysis:
                return await handleTextAnalysis(task: task, startTime: startTime)
            case .guardrailing:
                return await handleGuardrailing(task: task, startTime: startTime)
            case .chat, .textGeneration:
                return await handleChat(task: task, startTime: startTime)
            default:
                return .failure(.invalidInput)
            }
        } catch {
            return .failure(.processingError(error.localizedDescription))
        }
    }
    
    // MARK: - FoundationModels Implementation
    
    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 18.4, *)
    private func generateWithFoundationModels(prompt: String, instructions: String? = nil) async throws -> String {
        // Crea una nuova sessione con le istruzioni (le istruzioni vanno nel costruttore)
        let session: LanguageModelSession
        if let instructions = instructions {
            session = LanguageModelSession(instructions: instructions)
        } else {
            session = languageModelSession ?? LanguageModelSession()
        }
        
        // Genera la risposta
        let response = try await session.respond(to: prompt)
        return response.content
    }
    
    @available(macOS 26.0, iOS 18.4, *)
    private func streamWithFoundationModels(prompt: String, instructions: String? = nil, streamCallback: @escaping (String) -> Void) async throws -> String {
        // Crea una nuova sessione con le istruzioni
        let session: LanguageModelSession
        if let instructions = instructions {
            session = LanguageModelSession(instructions: instructions)
        } else {
            session = languageModelSession ?? LanguageModelSession()
        }
        
        var fullResponse = ""
        
        // Usa streaming per risposte in tempo reale
        let stream = session.streamResponse(to: prompt)
        
        for try await partialResponse in stream {
            let newContent = partialResponse.content
            if newContent.count > fullResponse.count {
                let delta = String(newContent.dropFirst(fullResponse.count))
                streamCallback(delta)
            }
            fullResponse = newContent
        }
        
        return fullResponse
    }
    #endif
    
    // MARK: - Private Implementation
    
    private func handleEmailSummary(task: AITask, startTime: Date) async -> Result<AIResult, AIError> {
        guard let subject = task.parameters["subject"]?.value as? String,
              let body = task.parameters["body"]?.value as? String else {
            return .failure(.invalidInput)
        }
        
        // Pulisce il testo prima di analizzarlo
        let cleanedBody = body
            .strippingHTML()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Rimuovi firme e disclaimer
        let bodyWithoutSignature = EmailHelpers.removeSignatureAndDisclaimer(from: cleanedBody)
        
        let fullText = "\(subject)\n\(bodyWithoutSignature)"
        
        // Se il testo è troppo corto, non ha senso riassumerlo
        if fullText.count < 100 {
            let processingTime = Date().timeIntervalSince(startTime)
            let shortSummary = cleanedBody.isEmpty ? subject : cleanedBody
            return .success(AIResult.success(
                taskID: task.id,
                provider: .appleIntelligence,
                result: shortSummary.prefix(200).description,
                metadata: ["type": "email_summary", "short_text": true],
                processingTime: processingTime
            ))
        }
        
        // Usa FoundationModels se disponibile
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 18.4, *), isFoundationModelsAvailable {
            do {
                // Rimuovi firme e disclaimer prima di anonimizzare
                let bodyWithoutSignature = EmailHelpers.removeSignatureAndDisclaimer(from: cleanedBody)
                
                // Anonimizza il contenuto per evitare guardrail violations su dati personali
                let anonymizedBody = anonymizeForAI(bodyWithoutSignature)
                let anonymizedSubject = anonymizeForAI(subject)
                
                let prompt = """
                Riassumi questa comunicazione professionale in italiano in massimo 3 frasi concise.
                Focalizzati sui punti chiave e le azioni richieste.
                
                Oggetto: \(anonymizedSubject)
                
                Contenuto:
                \(anonymizedBody.prefix(3000))
                """
                
                let instructions = """
                Sei un assistente professionale.
                Rispondi sempre in italiano.
                Genera riassunti chiari e professionali.
                Non includere saluti, firme o formule di cortesia nel riassunto.
                """
                
                let summary = try await generateWithFoundationModels(prompt: prompt, instructions: instructions)
                let processingTime = Date().timeIntervalSince(startTime)
                
                if !summary.isEmpty {
                    return .success(AIResult.success(
                        taskID: task.id,
                        provider: .appleIntelligence,
                        result: summary,
                        metadata: ["type": "email_summary", "foundation_models": true],
                        processingTime: processingTime
                    ))
                }
            } catch let error as LanguageModelSession.GenerationError {
                // Guardrail violations sono normali per contenuti assicurativi (dati personali, incidenti)
                // Passiamo silenziosamente al fallback NaturalLanguage
                if case .guardrailViolation = error {
                    // Silenzioso - contenuto sensibile rilevato, usa fallback
                } else {
                    print("[AppleAIService] ⚠️ FoundationModels error: \(error)")
                }
            } catch {
                print("[AppleAIService] ⚠️ FoundationModels error: \(error)")
            }
        }
        #endif
        
        // Fallback: usa NaturalLanguage (AppleIntelligenceService)
        let summary = await appleIntelligence.summarizeEmailBodyIgnoringSignature(
            subject: subject,
            body: body
        )
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        if let summary = summary, !summary.isEmpty {
            return .success(AIResult.success(
                taskID: task.id,
                provider: .appleIntelligence,
                result: summary,
                metadata: ["type": "email_summary", "fallback": true],
                processingTime: processingTime
            ))
        } else {
            // Ultimo fallback: estrai prime frasi
            let sentences = fullText
                .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 15 }
                .prefix(3)
            
            if !sentences.isEmpty {
                let fallbackSummary = sentences.joined(separator: ". ") + "."
                return .success(AIResult.success(
                    taskID: task.id,
                    provider: .appleIntelligence,
                    result: fallbackSummary,
                    metadata: ["type": "email_summary", "simple_fallback": true],
                    processingTime: processingTime
                ))
            }
            
            return .failure(.processingError("Testo troppo breve o non strutturato per generare un riassunto"))
        }
    }
    
    private func handleTextAnalysis(task: AITask, startTime: Date) async -> Result<AIResult, AIError> {
        guard let text = task.parameters["text"]?.value as? String else {
            return .failure(.invalidInput)
        }
        
        let extractedInfo = await appleIntelligence.extractEmailInfo(from: text)
        let category = await MainActor.run {
            appleIntelligence.categorizeText(text)
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        let result: [String: Any] = [
            "category": category,
            "extractedInfo": [
                "sinistroID": extractedInfo.sinistroID ?? "",
                "dates": extractedInfo.dates.map { $0.timeIntervalSince1970 },
                "amounts": extractedInfo.amounts.map { $0.description },
                "names": extractedInfo.names,
                "phoneNumbers": extractedInfo.phoneNumbers,
                "emailAddresses": extractedInfo.emailAddresses,
                "addresses": extractedInfo.addresses,
                "isUrgent": extractedInfo.isUrgent
            ]
        ]
        
        return .success(AIResult.success(
            taskID: task.id,
            provider: .appleIntelligence,
            result: result,
            metadata: ["type": "text_analysis"],
            processingTime: processingTime
        ))
    }
    
    private func handleGuardrailing(task: AITask, startTime: Date) async -> Result<AIResult, AIError> {
        guard let content = task.parameters["content"]?.value as? String else {
            return .failure(.invalidInput)
        }
        
        // Analisi base: verifica presenza di contenuti inappropriati
        let lowercased = content.lowercased()
        let inappropriateKeywords = ["errore", "fallimento", "impossibile", "non valido"]
        let hasIssues = inappropriateKeywords.contains { lowercased.contains($0) }
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        let result: [String: Any] = [
            "isAppropriate": !hasIssues,
            "issues": hasIssues ? ["Contenuto potrebbe richiedere revisione"] : [],
            "suggestions": []
        ]
        
        return .success(AIResult.success(
            taskID: task.id,
            provider: .appleIntelligence,
            result: result,
            metadata: ["type": "guardrailing"],
            processingTime: processingTime
        ))
    }
    
    private func handleChat(task: AITask, startTime: Date) async -> Result<AIResult, AIError> {
        guard let prompt = resolvePrompt(for: task) else {
            return .failure(.invalidInput)
        }
        
        // Usa FoundationModels se disponibile
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 18.4, *), isFoundationModelsAvailable {
            do {
                let instructions = """
                Sei un assistente professionale per gestione documentale in Italia.
                Rispondi sempre in italiano in modo professionale e conciso.
                Aiuta con domande su pratiche, documentazione e procedure.
                """
                
                // Anonimizza il prompt per evitare guardrail su dati sensibili
                let safePrompt = anonymizeForAI(prompt)
                
                let response = try await generateWithFoundationModels(prompt: safePrompt, instructions: instructions)
                let processingTime = Date().timeIntervalSince(startTime)
                
                return .success(AIResult.success(
                    taskID: task.id,
                    provider: .appleIntelligence,
                    result: response,
                    metadata: ["type": "chat", "foundation_models": true],
                    processingTime: processingTime
                ))
            } catch let error as LanguageModelSession.GenerationError {
                // Guardrail violations sono normali per contenuti con dati personali
                if case .guardrailViolation = error {
                    // Silenzioso - usa fallback
                } else {
                    print("[AppleAIService] ⚠️ FoundationModels chat error: \(error)")
                }
            } catch {
                print("[AppleAIService] ⚠️ FoundationModels chat error: \(error)")
            }
        }
        #endif
        
        // Fallback: risposta semplice con NaturalLanguage
        let sentences = await MainActor.run {
            extractKeySentences(from: prompt, maxSentences: 3)
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        var response = "Ho compreso la tua richiesta"
        if !sentences.isEmpty {
            response += ": " + sentences.joined(separator: ". ")
        }
        response += ". Per risposte più complete, Apple Intelligence on-device richiede macOS 26+ con dispositivo compatibile."
        
        return .success(AIResult.success(
            taskID: task.id,
            provider: .appleIntelligence,
            result: response,
            metadata: ["type": "chat", "fallback": true],
            processingTime: processingTime
        ))
    }
    
    private func resolvePrompt(for task: AITask) -> String? {
        if task.requiresKnowledge || !task.knowledgeChunks.isEmpty {
            return buildPerXPrompt(from: task)
        }
        
        if let prompt = task.parameters["prompt"]?.value as? String, !prompt.isEmpty {
            return prompt
        }
        
        if let input = task.parameters["inputText"]?.value as? String, !input.isEmpty {
            return input
        }
        
        return nil
    }
    
    private func extractKeySentences(from text: String, maxSentences: Int) -> [String] {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 10 }
        
        if sentences.count <= maxSentences {
            return sentences
        }
        
        let keywords = ["sinistro", "assegnazione", "perito", "danno", "liquidazione", "stima", "urgente", "importante"]
        
        let scoredSentences = sentences.map { sentence -> (String, Int) in
            let lowercased = sentence.lowercased()
            let score = keywords.reduce(0) { $0 + (lowercased.contains($1) ? 1 : 0) }
            return (sentence, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(maxSentences)
        .map { $0.0 }
        
        return Array(scoredSentences)
    }
    
    // MARK: - Anonymization for AI
    
    /// Anonimizza il testo per evitare guardrail violations di Apple Intelligence
    /// Rimuove/sostituisce dati personali che potrebbero triggerare i filtri di sicurezza
    private func anonymizeForAI(_ text: String) -> String {
        var result = text
        
        // Sostituisci numeri di telefono con placeholder
        let phonePattern = #"(\+?\d{2,3}[\s.-]?)?\d{3}[\s.-]?\d{3,4}[\s.-]?\d{3,4}"#
        if let regex = try? NSRegularExpression(pattern: phonePattern, options: []) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[telefono]")
        }
        
        // Sostituisci email con placeholder
        let emailPattern = #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#
        if let regex = try? NSRegularExpression(pattern: emailPattern, options: []) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[email]")
        }
        
        // Sostituisci codici fiscali con placeholder
        let cfPattern = #"[A-Z]{6}\d{2}[A-Z]\d{2}[A-Z]\d{3}[A-Z]"#
        if let regex = try? NSRegularExpression(pattern: cfPattern, options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[codice fiscale]")
        }
        
        // Sostituisci IBAN con placeholder
        let ibanPattern = #"[A-Z]{2}\d{2}[A-Z0-9]{4}\d{7}[A-Z0-9]{0,16}"#
        if let regex = try? NSRegularExpression(pattern: ibanPattern, options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[IBAN]")
        }
        
        // Sostituisci importi monetari specifici con placeholder generico
        let moneyPattern = #"€\s*[\d.,]+|[\d.,]+\s*€|EUR\s*[\d.,]+|[\d.,]+\s*EUR"#
        if let regex = try? NSRegularExpression(pattern: moneyPattern, options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[importo]")
        }
        
        // Sostituisci indirizzi comuni (via, piazza, ecc.)
        let addressPattern = #"(Via|Viale|Piazza|Corso|Largo|Vicolo|Strada)\s+[A-Z][a-zA-Z\s]+,?\s*\d+"#
        if let regex = try? NSRegularExpression(pattern: addressPattern, options: []) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[indirizzo]")
        }
        
        return result
    }
}
