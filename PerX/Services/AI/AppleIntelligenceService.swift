import Foundation
import NaturalLanguage
import CoreML

/// Servizio centralizzato per l'integrazione di Apple Intelligence nell'app
@MainActor
class AppleIntelligenceService {
    static let shared = AppleIntelligenceService()
    
    private let languageRecognizer = NLLanguageRecognizer()
    private let tokenizer = NLTokenizer(unit: .word)
    
    private init() {
        tokenizer.setLanguage(.italian)
    }
    
    // MARK: - Analisi Email
    
    /// Genera un riassunto intelligente di un'email
    func summarizeEmail(subject: String, body: String, maxSentences: Int = 3) async -> String? {
        let fullText = "\(subject)\n\n\(body)"
        
        // Per testi molto lunghi, aumenta il numero di frasi
        let textLength = fullText.count
        let adjustedMaxSentences: Int
        if textLength > 5000 {
            adjustedMaxSentences = min(maxSentences * 2, 8)
        } else if textLength > 2000 {
            adjustedMaxSentences = min(maxSentences + 2, 6)
        } else {
            adjustedMaxSentences = maxSentences
        }
        
        // Estrae le frasi chiave usando Natural Language
        let sentences = extractKeySentences(from: fullText, maxSentences: adjustedMaxSentences)
        
        if sentences.isEmpty {
            return nil
        }
        
        return sentences.joined(separator: ". ") + "."
    }
    
    /// Genera un riassunto intelligente di un'email ignorando firme e note di servizio
    func summarizeEmailBodyIgnoringSignature(subject: String, body: String, maxSentences: Int = 3) async -> String? {
        // Pulisce il corpo dell'email rimuovendo firme e note di servizio
        let cleanedBody = cleanEmailBody(body)
        let fullText = "\(subject)\n\n\(cleanedBody)"
        
        // Per testi molto lunghi (thread), aumenta il numero di frasi
        let textLength = fullText.count
        let adjustedMaxSentences: Int
        if textLength > 5000 {
            adjustedMaxSentences = min(maxSentences * 2, 8)
        } else if textLength > 2000 {
            adjustedMaxSentences = min(maxSentences + 2, 6)
        } else {
            adjustedMaxSentences = maxSentences
        }
        
        // Estrae le frasi chiave usando Natural Language
        let sentences = extractKeySentences(from: fullText, maxSentences: adjustedMaxSentences)
        
        if sentences.isEmpty {
            return nil
        }
        
        return sentences.joined(separator: ". ") + "."
    }
    
    /// Pulisce il corpo dell'email rimuovendo firme, note di servizio e informazioni privacy
    private func cleanEmailBody(_ body: String) -> String {
        var cleaned = body
        
        // Rimuove HTML se presente
        cleaned = cleaned.strippingHTML()
        
        // Usa il metodo centralizzato di EmailHelpers per rimuovere firme e disclaimer
        cleaned = EmailHelpers.removeSignatureAndDisclaimer(from: cleaned)
        
        // Pattern aggiuntivi per identificare la firma/separatore (per tagliare tutto dopo)
        let signaturePatterns = [
            "--\\s*$",  // Separatore standard --
            "---\\s*$",  // Separatore ---
            "________________________________",  // Linea separatrice
            "Sent from",  // Sent from...
            "Inviato da",  // Inviato da...
            "Da:",
            "Il giorno"
        ]
        
        // Trova la posizione della prima occorrenza di un pattern di firma
        var cutIndex: String.Index? = nil
        
        for pattern in signaturePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]) {
                let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
                if let match = regex.firstMatch(in: cleaned, options: [], range: range) {
                    if let matchRange = Range(match.range, in: cleaned) {
                        let candidateIndex = matchRange.lowerBound
                        if cutIndex == nil || candidateIndex < cutIndex! {
                            cutIndex = candidateIndex
                        }
                    }
                }
            }
        }
        
        // Taglia tutto ciò che viene dopo la firma
        if let cutIndex = cutIndex {
            cleaned = String(cleaned[..<cutIndex])
        }
        
        // Rimuove linee vuote eccessive
        cleaned = cleaned.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Estrae informazioni strutturate da un'email
    func extractEmailInfo(from body: String) async -> EmailExtractedInfo {
        var info = EmailExtractedInfo()
        
        // Estrazione ID sinistro con pattern multipli
        info.sinistroID = extractSinistroID(from: body)
        
        // Estrazione date
        info.dates = extractDates(from: body)
        
        // Estrazione importi monetari
        info.amounts = extractAmounts(from: body)
        
        // Estrazione nomi e contatti
        info.names = extractNames(from: body)
        info.phoneNumbers = extractPhoneNumbers(from: body)
        info.emailAddresses = extractEmailAddresses(from: body)
        
        // Estrazione indirizzi
        info.addresses = extractAddresses(from: body)
        
        // Rilevamento urgenza
        info.isUrgent = detectUrgency(in: body)
        
        // Categorizzazione automatica
        info.category = categorizeEmail(body: body)
        
        return info
    }
    
    // MARK: - Analisi Sinistri
    
    /// Suggerisce informazioni per un sinistro basandosi sul testo
    func suggestSinistroInfo(from text: String) async -> SinistroSuggestion {
        var suggestion = SinistroSuggestion()
        
        // Estrazione dati base
        suggestion.riferimento = extractSinistroID(from: text)
        suggestion.nomeAssicurato = extractNames(from: text).first
        suggestion.telefono = extractPhoneNumbers(from: text).first
        suggestion.email = extractEmailAddresses(from: text).first
        suggestion.indirizzo = extractAddresses(from: text).first
        
        // Estrazione importi
        let amounts = extractAmounts(from: text)
        if let firstAmount = amounts.first {
            suggestion.richiesta = firstAmount
        }
        
        // Estrazione date
        let dates = extractDates(from: text)
        suggestion.dataSinistro = dates.first
        
        // Suggerimento stato basato su keywords
        suggestion.suggestedStatus = suggestStatus(from: text)
        
        // Rilevamento tipo danno
        suggestion.tipoDanno = detectDamageType(from: text)
        
        return suggestion
    }
    
    // MARK: - Categorizzazione
    
    /// Categorizza automaticamente un testo
    func categorizeText(_ text: String) -> String {
        let lowercased = text.lowercased()
        
        // Categorie principali
        if lowercased.contains("assegnazione") || lowercased.contains("incarico") {
            return "Assegnazione"
        }
        if lowercased.contains("sopralluogo") || lowercased.contains("visita") {
            return "Sopralluogo"
        }
        if lowercased.contains("liquidazione") || lowercased.contains("stima") {
            return "Liquidazione"
        }
        if lowercased.contains("revoca") || lowercased.contains("annullamento") {
            return "Revoca"
        }
        if lowercased.contains("documentazione") || lowercased.contains("giustificativo") {
            return "Documentazione"
        }
        
        return "Generale"
    }
    
    // MARK: - Helper Methods Privati
    
    private func extractKeySentences(from text: String, maxSentences: Int) -> [String] {
        let originalLength = text.count
        
        // Per testi molto brevi, non ha senso fare un riassunto
        if originalLength < 100 {
            return []
        }
        
        let maxSummaryLength = max(100, originalLength / 3) // Riassunto max 1/3 del testo originale, minimo 100 caratteri
        
        // Divide il testo in frasi più intelligenti
        var sentences: [String] = []
        let sentenceEnders = CharacterSet(charactersIn: ".!?\n")
        
        // Prima prova a dividere per punti, esclamativi, interrogativi
        let parts = text.components(separatedBy: sentenceEnders)
        
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            // Filtra frasi troppo corte o troppo lunghe
            if trimmed.count >= 15 && trimmed.count <= 500 {
                sentences.append(trimmed)
            } else if trimmed.count > 500 {
                // Se una frase è troppo lunga, prova a dividerla per virgole
                let subParts = trimmed.components(separatedBy: ",")
                var currentSentence = ""
                for subPart in subParts {
                    let trimmedSub = subPart.trimmingCharacters(in: .whitespacesAndNewlines)
                    if currentSentence.isEmpty {
                        currentSentence = trimmedSub
                    } else if (currentSentence + ", " + trimmedSub).count <= 300 {
                        currentSentence += ", " + trimmedSub
                    } else {
                        if currentSentence.count >= 15 {
                            sentences.append(currentSentence)
                        }
                        currentSentence = trimmedSub
                    }
                }
                if !currentSentence.isEmpty && currentSentence.count >= 15 {
                    sentences.append(currentSentence)
                }
            }
        }
        
        guard !sentences.isEmpty else { return [] }
        
        // Se ci sono poche frasi, restituisci solo le più importanti
        if sentences.count <= maxSentences {
            // Anche se ci sono poche frasi, assicurati che il riassunto sia più corto
        let totalLength = sentences.joined(separator: ". ").count
        if Double(totalLength) >= Double(originalLength) * 0.8 {
                // Se il riassunto è troppo lungo, prendi solo le prime frasi più corte
                return sentences
                    .sorted { $0.count < $1.count }
                    .prefix(max(1, maxSentences / 2))
                    .map { $0 }
            }
            return sentences
        }
        
        // Keyword scoring migliorato
        let keywords = ["sinistro", "assegnazione", "perito", "danno", "liquidazione", "stima", "urgente", "importante", "richiesta", "compagnia", "assicurato", "pratica", "riferimento"]
        
        // Calcola score per ogni frase
        let scoredSentences = sentences.enumerated().map { index, sentence -> (String, Int, Int) in
            let lowercased = sentence.lowercased()
            var score = 0
            
            // Score per keyword
            for keyword in keywords {
                if lowercased.contains(keyword) {
                    score += 2
                }
            }
            
            // Bonus per frasi all'inizio (spesso più importanti)
            if index < 3 {
                score += 1
            }
            
            // Penalità per frasi troppo lunghe
            if sentence.count > 200 {
                score -= 1
            }
            
            return (sentence, score, sentence.count)
        }
        
        // Ordina per score (decrescente), poi per lunghezza (crescente per preferire frasi più concise)
        let sorted = scoredSentences.sorted { first, second in
            if first.1 != second.1 {
                return first.1 > second.1
            }
            return first.2 < second.2
        }
        
        // Seleziona le frasi migliori rispettando il limite di lunghezza
        var selected: [String] = []
        var currentLength = 0
        
        for (sentence, _, length) in sorted {
            if selected.count >= maxSentences {
                break
            }
            
            let potentialLength = currentLength + length + (selected.isEmpty ? 0 : 2) // +2 per ". "
            
            if potentialLength <= maxSummaryLength {
                selected.append(sentence)
                currentLength = potentialLength
            } else if selected.isEmpty {
                // Se anche la prima frase è troppo lunga, prendila comunque ma troncata
                let truncated = String(sentence.prefix(maxSummaryLength - 10)) + "..."
                selected.append(truncated)
                break
            } else {
                // Abbiamo già alcune frasi, fermiamoci qui
                break
            }
        }
        
        // Se non abbiamo selezionato abbastanza frasi, prendi le prime più corte
        if selected.count < maxSentences && selected.count < sentences.count {
            let remaining = sentences.filter { !selected.contains($0) }
                .sorted { $0.count < $1.count }
                .prefix(maxSentences - selected.count)
            
            for sentence in remaining {
                let potentialLength = currentLength + sentence.count + 2
                if potentialLength <= maxSummaryLength {
                    selected.append(sentence)
                    currentLength = potentialLength
                } else {
                    break
                }
            }
        }
        
        // Assicurati che il riassunto sia sempre più corto dell'originale
        let summaryText = selected.joined(separator: ". ")
        if Double(summaryText.count) >= Double(originalLength) * 0.9 {
            // Se è ancora troppo lungo, prendi solo le prime frasi più corte
            return sentences
                .sorted { $0.count < $1.count }
                .prefix(max(1, maxSentences / 2))
                .map { $0 }
        }
        
        return selected.isEmpty ? [] : selected
    }
    
    private func extractSinistroID(from text: String) -> String? {
        let patterns = [
            "per il sinistro \\[([^\\]]+)\\]",
            "sinistro n[°.]?\\s*([\\w\\-/]+)",
            "pratica[\\s:]+(\\w+[\\-/]?\\w*)",
            "riferimento[\\s:]+(\\w+[\\-/]?\\w*)",
            "\\bsinistro[\\s:]+(\\w+[\\-/]?\\w*)",
            "\\[([\\w\\-/]+)\\]"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    if let idRange = Range(match.range(at: 1), in: text) {
                        let foundID = String(text[idRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !foundID.isEmpty && foundID.count > 2 {
                            return foundID
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractDates(from text: String) -> [Date] {
        var dates: [Date] = []
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        
        detector?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let match = match, let date = match.date {
                dates.append(date)
            }
        }
        
        return dates
    }
    
    private func extractAmounts(from text: String) -> [Decimal] {
        var amounts: [Decimal] = []
        
        // Pattern per importi in formato italiano ed europeo
        let patterns = [
            "€\\s*([\\d.,]+)",
            "euro\\s*([\\d.,]+)",
            "EUR\\s*([\\d.,]+)",
            "([\\d.,]+)\\s*€",
            "([\\d.,]+)\\s*euro"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                    if let match = match, let amountRange = Range(match.range(at: 1), in: text) {
                        let amountString = String(text[amountRange])
                            .replacingOccurrences(of: ".", with: "")
                            .replacingOccurrences(of: ",", with: ".")
                        
                        if let amount = Decimal(string: amountString) {
                            amounts.append(amount)
                        }
                    }
                }
            }
        }
        
        return amounts
    }
    
    private func extractNames(from text: String) -> [String] {
        var names: [String] = []
        
        // Pattern per estrarre nomi comuni nei testi italiani
        let patterns = [
            // Sig./Sig.ra/Sig.na Nome Cognome
            "(?:Sig\\.|Sig\\.ra|Sig\\.na|Dott\\.|Dott\\.ssa|Avv\\.|Ing\\.|Arch\\.)\\s+([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)+)",
            // Nome Cognome (pattern base: due parole maiuscole/minuscole)
            "\\b([A-Z][a-z]+\\s+[A-Z][a-z]+)\\b",
            // Nome Cognome Cognome (tre parole)
            "\\b([A-Z][a-z]+\\s+[A-Z][a-z]+\\s+[A-Z][a-z]+)\\b"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                    if let match = match {
                        // Prendi il primo gruppo catturato (indice 1)
                        if match.numberOfRanges > 1,
                           let nameRange = Range(match.range(at: 1), in: text) {
                            let name = String(text[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                            // Filtra nomi validi (almeno 3 caratteri, max 50, non numeri)
                            if name.count >= 3 && name.count <= 50 && !name.allSatisfy({ $0.isNumber }) {
                                // Evita duplicati
                                if !names.contains(name) {
                                    names.append(name)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Rimuovi nomi che sono probabilmente false positive (parole comuni)
        let commonWords = ["Data", "Sinistro", "Pratica", "Riferimento", "Email", "Telefono", "Indirizzo", "Compagnia", "Agenzia"]
        names = names.filter { name in
            !commonWords.contains { name.localizedCaseInsensitiveContains($0) }
        }
        
        return names
    }
    
    private func extractPhoneNumbers(from text: String) -> [String] {
        var phones: [String] = []
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        
        detector?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let match = match, let phoneRange = Range(match.range, in: text) {
                let phone = String(text[phoneRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                phones.append(phone)
            }
        }
        
        return phones
    }
    
    private func extractEmailAddresses(from text: String) -> [String] {
        var emails: [String] = []
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        
        detector?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let match = match, let url = match.url, url.scheme == "mailto" {
                if let email = url.absoluteString.replacingOccurrences(of: "mailto:", with: "").removingPercentEncoding {
                    emails.append(email)
                }
            }
        }
        
        // Pattern aggiuntivo per email nel testo
        let emailPattern = "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"
        if let regex = try? NSRegularExpression(pattern: emailPattern, options: []) {
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                if let match = match, let emailRange = Range(match.range, in: text) {
                    let email = String(text[emailRange])
                    if !emails.contains(email) {
                        emails.append(email)
                    }
                }
            }
        }
        
        return emails
    }
    
    private func extractAddresses(from text: String) -> [String] {
        var addresses: [String] = []
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        
        detector?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let match = match, let addressRange = Range(match.range, in: text) {
                let address = String(text[addressRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if address.count > 10 {
                    addresses.append(address)
                }
            }
        }
        
        return addresses
    }
    
    private func detectUrgency(in text: String) -> Bool {
        let urgentKeywords = ["urgente", "immediato", "asap", "subito", "priorità", "importante", "critico"]
        let lowercased = text.lowercased()
        return urgentKeywords.contains { lowercased.contains($0) }
    }
    
    private func categorizeEmail(body: String) -> String {
        return categorizeText(body)
    }
    
    private func suggestStatus(from text: String) -> String {
        let lowercased = text.lowercased()
        
        if lowercased.contains("assegnazione") || lowercased.contains("incarico") {
            return "Incaricato"
        }
        if lowercased.contains("sopralluogo") {
            return "Sopralluogo"
        }
        if lowercased.contains("liquidazione") {
            return "Liquidazione"
        }
        if lowercased.contains("chiuso") || lowercased.contains("completato") {
            return "Chiuso"
        }
        
        return "Incaricato"
    }
    
    private func detectDamageType(from text: String) -> String? {
        let lowercased = text.lowercased()
        
        if lowercased.contains("fulminazione") || lowercased.contains("fulmine") {
            return "Fulminazione"
        }
        if lowercased.contains("allagamento") || lowercased.contains("acqua") {
            return "Allagamento"
        }
        if lowercased.contains("incendio") || lowercased.contains("fuoco") {
            return "Incendio"
        }
        if lowercased.contains("furto") {
            return "Furto"
        }
        
        return nil
    }
    
    /// Migliora il testo di un'email usando Apple Intelligence
    func improveEmailText(subject: String, body: String) async -> String? {
        // Per ora usa un miglioramento semplice basato su Natural Language
        // In futuro può essere integrato con modelli più avanzati
        
        let fullText = "\(subject)\n\n\(body)"
        
        // Estrae frasi chiave e le migliora
        let sentences = extractKeySentences(from: fullText, maxSentences: 10)
        
        // Rimuove ripetizioni e migliora la struttura
        var improvedSentences: [String] = []
        var seenWords = Set<String>()
        
        for sentence in sentences {
            let words = sentence.lowercased().components(separatedBy: .whitespaces)
            let uniqueWords = Set(words)
            
            // Evita frasi troppo simili
            let similarity = uniqueWords.intersection(seenWords).count
            if similarity < uniqueWords.count / 2 {
                improvedSentences.append(sentence)
                seenWords.formUnion(uniqueWords)
            }
        }
        
        if improvedSentences.isEmpty {
            return body
        }
        
        return improvedSentences.joined(separator: " ")
    }
    
    // MARK: - Integrazione con AIManager
    
    /// Genera un riassunto email usando il manager AI (con priorità)
    func summarizeEmailWithManager(subject: String, body: String, priority: AITaskPriority = .primary) async -> String? {
        let task = AITask.emailSummary(subject: subject, body: body, priority: priority)
        
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                AIManager.shared.enqueue(task) { result in
                    if result.success, let summary = result.result?.value as? String {
                        continuation.resume(returning: summary)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
    
    /// Estrae informazioni da un testo usando il manager AI
    func extractInfoWithManager(from text: String, priority: AITaskPriority = .secondary) async -> EmailExtractedInfo? {
        let task = AITask(
            type: .textAnalysis,
            priority: priority,
            preferredProvider: .appleIntelligence,
            parameters: ["text": AnyCodable(text)]
        )
        
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                AIManager.shared.enqueue(task) { result in
                    if result.success,
                       let resultData = result.result?.value as? [String: Any],
                       let extractedInfo = resultData["extractedInfo"] as? [String: Any] {
                        var info = EmailExtractedInfo()
                        info.sinistroID = extractedInfo["sinistroID"] as? String
                        // ... altri campi
                        continuation.resume(returning: info)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}

// MARK: - Data Structures

struct EmailExtractedInfo {
    var sinistroID: String?
    var dates: [Date] = []
    var amounts: [Decimal] = []
    var names: [String] = []
    var phoneNumbers: [String] = []
    var emailAddresses: [String] = []
    var addresses: [String] = []
    var isUrgent: Bool = false
    var category: String = "Generale"
}

struct SinistroSuggestion {
    var riferimento: String?
    var nomeAssicurato: String?
    var telefono: String?
    var email: String?
    var indirizzo: String?
    var richiesta: Decimal?
    var dataSinistro: Date?
    var suggestedStatus: String?
    var tipoDanno: String?
}

