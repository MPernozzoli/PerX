import Foundation

/// Servizio per l'estrazione di pattern da email (oggetto e corpo)
/// Estrae: riferimento interno, numero sinistro agenzia, nome assicurato
/// Priorità: 1) Riferimento, 2) Numero agenzia, 3) Nome assicurato
class EmailPatternMatcher {
    static let shared = EmailPatternMatcher()
    
    private init() {}
    
    /// Risultato dell'estrazione pattern
    struct ExtractedPatterns {
        let riferimento: String?
        let numeroAgenzia: String?
        let nomeAssicurato: String?
        
        /// Verifica se almeno un pattern valido è stato trovato
        /// Un pattern è valido solo se ha la lunghezza minima richiesta
        var hasAnyPattern: Bool {
            // Riferimento: deve essere esattamente 7 cifre
            if let rif = riferimento, rif.count == 7, rif.allSatisfy({ $0.isNumber }) {
                return true
            }
            // Numero agenzia: deve avere almeno 4 caratteri
            if let num = numeroAgenzia, num.count >= 4 {
                return true
            }
            // Nome assicurato: deve avere almeno 3 caratteri
            if let nome = nomeAssicurato, nome.count >= 3 {
                return true
            }
            return false
        }
    }
    
    /// Estrae tutti i pattern dall'email (oggetto prima, corpo se oggetto vuoto)
    /// - Parameters:
    ///   - subject: Oggetto dell'email
    ///   - body: Corpo dell'email (opzionale)
    /// - Returns: Pattern estratti con priorità: riferimento > numero agenzia > nome assicurato
    func extractPatterns(subject: String, body: String?) -> ExtractedPatterns {
        // Cerca prima nell'oggetto
        let subjectRiferimento = extractRiferimento(from: subject)
        let subjectNumeroAgenzia = extractNumeroAgenzia(from: subject)
        let subjectNomeAssicurato = extractNomeAssicurato(from: subject)
        
        // Se l'oggetto è vuoto o non ha trovato nulla, cerca nel corpo
        let useBody = subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
                     (subjectRiferimento == nil && subjectNumeroAgenzia == nil && subjectNomeAssicurato == nil)
        
        var riferimento = subjectRiferimento
        var numeroAgenzia = subjectNumeroAgenzia
        var nomeAssicurato = subjectNomeAssicurato
        
        if useBody, let body = body, !body.isEmpty {
            // Cerca nel corpo solo se non trovato nell'oggetto
            if riferimento == nil {
                riferimento = extractRiferimento(from: body)
            }
            if numeroAgenzia == nil {
                numeroAgenzia = extractNumeroAgenzia(from: body)
            }
            if nomeAssicurato == nil {
                nomeAssicurato = extractNomeAssicurato(from: body)
            }
        }
        
        return ExtractedPatterns(
            riferimento: riferimento,
            numeroAgenzia: numeroAgenzia,
            nomeAssicurato: nomeAssicurato
        )
    }
    
    // MARK: - Riferimento Interno
    
    /// Estrae il riferimento interno
    /// Priorità: 1) Pattern con contesto, 2) Pattern formato standard, 3) Riferimento sparso (7 cifre esatte)
    private func extractRiferimento(from text: String) -> String? {
        // PRIORITÀ 1: Pattern specifici con contesto chiaro
        let contextualPatterns = [
            "per il sinistro \\[([0-9]{7})\\]",  // "per il sinistro [1234567]"
            "per il sinistro\\s+([0-9]{7})\\b",  // "per il sinistro 1234567"
            "sinistro n[°.]?\\s*([0-9]{7})\\b",  // "sinistro n° 1234567"
            "pratica[\\s:]+([0-9]{7})\\b",       // "pratica: 1234567"
            "riferimento[\\s:]+([0-9]{7})\\b",   // "riferimento: 1234567"
            "\\bsinistro[\\s:]+([0-9]{7})\\b",   // "sinistro: 1234567"
            "(?:sinistro|pratica|riferimento|rif\\.)\\s*[n°:.]?\\s*([0-9]{7})\\b"
        ]
        
        for pattern in contextualPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   let idRange = Range(match.range(at: 1), in: text) {
                    let foundID = String(text[idRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if foundID.count == 7 && foundID.allSatisfy({ $0.isNumber }) {
                        return foundID
                    }
                }
            }
        }
        
        // PRIORITÀ 2: Formato standard completo "[azione] - sinistro n. [numero] - Assicurato [nome] - ns. rif. [riferimento]"
        let standardFormatPattern = #"ns\.?\s*rif\.?\s*([0-9]{7})\b"#
        if let regex = try? NSRegularExpression(pattern: standardFormatPattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let idRange = Range(match.range(at: 1), in: text) {
                let foundID = String(text[idRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if foundID.count == 7 && foundID.allSatisfy({ $0.isNumber }) {
                    return foundID
                }
            }
        }
        
        // PRIORITÀ 3: Riferimento sparso senza contesto (solo se è esattamente 7 cifre)
        // Cerca sequenze isolate di 7 cifre che non fanno parte di numeri più lunghi
        let isolatedPattern = #"\b([0-9]{7})\b"#
        if let regex = try? NSRegularExpression(pattern: isolatedPattern, options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let idRange = Range(match.range(at: 1), in: text) {
                let foundID = String(text[idRange])
                // Verifica che non sia parte di un numero più lungo (controlla caratteri prima e dopo)
                let matchStart = match.range.location
                let matchEnd = matchStart + match.range.length
                
                // Controlla caratteri adiacenti (non devono essere cifre)
                let beforeChar = matchStart > 0 ? (text as NSString).substring(with: NSRange(location: matchStart - 1, length: 1)) : ""
                let afterChar = matchEnd < text.utf16.count ? (text as NSString).substring(with: NSRange(location: matchEnd, length: 1)) : ""
                
                // Accetta solo se non è circondato da altre cifre
                if (!beforeChar.isEmpty && beforeChar.first?.isNumber == true) || 
                   (!afterChar.isEmpty && afterChar.first?.isNumber == true) {
                    // È parte di un numero più lungo, salta
                } else {
                    // È un riferimento valido (7 cifre isolate)
                    return foundID
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Numero Sinistro Agenzia
    
    /// Estrae il numero sinistro compagnia/agenzia
    /// Supporta formati standard: "sinistro n. [numero]", "SX N. [numero]", formato completo
    private func extractNumeroAgenzia(from text: String) -> String? {
        let patterns = [
            // Formato standard completo: "[azione] - sinistro n. [numero] - ..."
            #"sinistro\s+n[°.]?\s*([0-9A-Z\-/]{4,})"#,  // "sinistro n° 123456" (min 4 caratteri)
            // Abbreviazione SX: "SX N. [numero]"
            #"SX\s+N[°.]?\s*([0-9A-Z\-/]{4,})"#,        // "SX N. 123456" (min 4 caratteri)
            // Altri pattern comuni
            #"sinistro\s+([0-9A-Z\-/]{4,})"#,           // "sinistro 123456" (min 4 caratteri)
            #"pratica\s+n[°.]?\s*([0-9A-Z\-/]{4,})"#,   // "pratica n° 123456" (min 4 caratteri)
            #"pratica\s+([0-9A-Z\-/]{4,})"#,            // "pratica 123456" (min 4 caratteri)
            #"numero\s+sinistro[:\s]+([0-9A-Z\-/]{4,})"#, // "numero sinistro: 123456" (min 4 caratteri)
            #"n[°.]?\s*sinistro[:\s]+([0-9A-Z\-/]{4,})"#, // "n° sinistro: 123456" (min 4 caratteri)
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: text.utf16.count)
                if let match = regex.firstMatch(in: text, range: range) {
                    let matchRange = match.range(at: 1)
                    if matchRange.location != NSNotFound {
                        let numero = (text as NSString).substring(with: matchRange)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        // Richiedi almeno 4 caratteri per evitare falsi positivi (es. "n° 1")
                        if !numero.isEmpty && numero.count >= 4 {
                            return numero
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Nome Assicurato
    
    /// Estrae il nome assicurato
    /// Supporta formati standard: "Assicurato [nome]", formato completo, e pattern dopo "SX N."
    private func extractNomeAssicurato(from text: String) -> String? {
        // Pattern 1: Formato standard completo "[azione] - sinistro n. [numero] - Assicurato [nome] - ..."
        let pattern1 = #"Assicurato\s+([A-Za-zÀ-ÿ\s]{3,}?)(?:\s+-\s+|$)"#
        
        if let regex = try? NSRegularExpression(pattern: pattern1, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: text.utf16.count)
            if let match = regex.firstMatch(in: text, range: range) {
                let matchRange = match.range(at: 1)
                if matchRange.location != NSNotFound {
                    let nome = (text as NSString).substring(with: matchRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !nome.isEmpty && nome.count >= 3 {
                        return nome
                    }
                }
            }
        }
        
        // Pattern 2: "Assicurato: [nome]" con contesto chiaro
        let pattern2 = #"[Aa]ssicurato[:\s]+([A-Za-zÀ-ÿ\s]{3,}?)(?:\s*-\s*|$)"#
        
        if let regex = try? NSRegularExpression(pattern: pattern2, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: text.utf16.count)
            if let match = regex.firstMatch(in: text, range: range) {
                let matchRange = match.range(at: 1)
                if matchRange.location != NSNotFound {
                    let nome = (text as NSString).substring(with: matchRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !nome.isEmpty && nome.count >= 3 {
                        return nome
                    }
                }
            }
        }
        
        // Pattern 3: Formato "SX N. [numero] - [nome assicurato]"
        // Cerca il nome dopo "SX N. [numero] -"
        let pattern3 = #"SX\s+N[°.]?\s*[0-9A-Z\-/]+\s*-\s+([A-Za-zÀ-ÿ\s]{3,}?)(?:\s*-\s*|$)"#
        
        if let regex = try? NSRegularExpression(pattern: pattern3, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: text.utf16.count)
            if let match = regex.firstMatch(in: text, range: range) {
                let matchRange = match.range(at: 1)
                if matchRange.location != NSNotFound {
                    let nome = (text as NSString).substring(with: matchRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !nome.isEmpty && nome.count >= 3 {
                        return nome
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Normalizza un numero sinistro rimuovendo separatori comuni
    /// Utile per confrontare numeri con formati diversi (es. "123-456" vs "123456")
    func normalizeNumber(_ number: String) -> String {
        return number
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

