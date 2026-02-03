import Foundation
import SwiftUI

/// Funzioni helper centralizzate per la gestione delle email
/// Elimina duplicazione di codice presente in MailboxEmailRow, PrincipaleView, EmailThreadView, etc.
enum EmailHelpers {
    
    // MARK: - Date Formatting (delegates to DateUtils)
    
    /// Formatta la data dell'email in modo intelligente (oggi = ora, ieri = "Ieri", etc.)
    static func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        return DateUtils.formatSmart(date)
    }
    
    /// Formatta la data con ora relativa (es. "2 ore fa")
    static func formatRelativeDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        return DateUtils.formatRelative(date)
    }
    
    /// Formatta la data completa (es. "10 dic 2024, 14:30")
    static func formatFullDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    
    // MARK: - Name/Initials
    
    /// Estrae le iniziali dal nome (es. "Mario Rossi" -> "MR")
    static func initials(from name: String) -> String {
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1)) + String(components[1].prefix(1))
        } else if !components.isEmpty {
            return String(components[0].prefix(2))
        }
        return "??"
    }
    
    // MARK: - HTML/Body Processing
    
    /// Pulisce il body HTML rimuovendo tag, entità e formattazione
    static func cleanHTMLBody(_ body: String) -> String {
        var cleaned = body
        
        // Rimuovi style e script usando NSRegularExpression per supportare multiline
        if let styleRegex = try? NSRegularExpression(pattern: "<style[^>]*>.*?</style>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            cleaned = styleRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        if let scriptRegex = try? NSRegularExpression(pattern: "<script[^>]*>.*?</script>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            cleaned = scriptRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        
        // Rimuovi tag HTML
        cleaned = cleaned
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&hellip;", with: "...")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    /// Rimuove firme e disclaimer comuni dal testo
    static func removeSignatureAndDisclaimer(from text: String) -> String {
        var cleaned = text
        
        // Pattern comuni per firme e saluti
        let signaturePatterns = [
            "(?i)(cordiali\\s+saluti|distinti\\s+saluti|saluti|cordialmente|buona\\s+giornata).*",
            "(?i)(best\\s+regards|regards|kind\\s+regards|sincerely).*",
            "--.*",
            "_{2,}.*",
            "(?i)(questa\\s+email.*confidenziale|this\\s+email.*confidential).*",
            "(?i)(informazioni\\s+confidenziali|confidential\\s+information).*"
        ]
        
        for pattern in signaturePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: cleaned.utf16.count)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
            }
        }
        
        // Rimuove disclaimer privacy e ambiente comuni (pattern più specifici)
        let disclaimerPatterns = [
            "(?i)(prima\\s+di\\s+stampare.*ambiente).*",
            "(?i)(informativa\\s+privacy.*regolamento.*679/2016).*",
            "(?i)(informativa\\s+privacy.*artt?\\.\\s*13.*14.*regolamento.*ue.*2016/679).*",
            "(?i)(informativa\\s+privacy.*ai\\s+sensi.*artt?\\.\\s*13.*14.*regolamento.*679/2016).*",
            "(?i)(informazioni\\s+contenute.*messaggio.*riservate.*destinatario).*",
            "(?i)(se\\s+avete\\s+ricevuto.*messaggio.*errore.*distruggerlo).*",
            "(?i)(informativa\\s+privacy|privacy\\s+notice|privacy\\s+policy).*",
            "(?i)(ai\\s+sensi.*gdpr|pursuant\\s+to.*gdpr).*",
            "(?i)(d\\.lgs\\.\\s*196/2003|regolamento\\s+ue.*679/2016).*",
            "(?i)(regolamento.*ue.*2016/679).*",
            "(?i)(artt?\\.\\s*13.*14.*regolamento).*"
        ]
        
        for pattern in disclaimerPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: cleaned.utf16.count)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
            }
        }
        
        // Rimuove email alla fine (probabilmente firma)
        if let regex = try? NSRegularExpression(pattern: "([a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,})", options: .caseInsensitive) {
            let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: cleaned.utf16.count))
            if matches.count > 1 {
                if let lastMatch = matches.last, lastMatch.range.location > cleaned.utf16.count / 2 {
                    let startIndex = cleaned.index(cleaned.startIndex, offsetBy: lastMatch.range.location)
                    cleaned = String(cleaned[..<startIndex])
                }
            }
        }
        
        return cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Estrae il contenuto principale separando le citazioni
    static func extractQuote(from body: String) -> (main: String, quote: String) {
        let quotePatterns: [(String, Bool)] = [
            ("-----Messaggio originale-----", false),
            ("<div class=\"gmail_quote\">", true),
            ("<blockquote", true),
            ("From:", false),
            ("Da:", false),
            ("Il giorno", false),
            ("On ", false),
            ("Inviato da", false),
            ("> ", false)
        ]
        
        var mainBody = body
        var quote = ""
        
        // Prima prova pattern HTML
        for (pattern, isHTML) in quotePatterns where isHTML {
            if let range = body.range(of: pattern, options: .caseInsensitive) {
                let mainPart = String(body[..<range.lowerBound])
                let quotePart = String(body[range.lowerBound...])
                
                if !mainPart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    mainBody = mainPart.trimmingCharacters(in: .whitespacesAndNewlines)
                    quote = quotePart
                    break
                }
            }
        }
        
        // Se non trovato, prova pattern testo
        if quote.isEmpty {
            for (pattern, isHTML) in quotePatterns where !isHTML {
                if let range = body.range(of: pattern, options: .caseInsensitive) {
                    let distance = body.distance(from: body.startIndex, to: range.lowerBound)
                    if distance > 50 {
                        let mainPart = String(body[..<range.lowerBound])
                        let quotePart = String(body[range.lowerBound...])
                        
                        if !mainPart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            mainBody = mainPart.trimmingCharacters(in: .whitespacesAndNewlines)
                            quote = quotePart
                            break
                        }
                    }
                }
            }
        }
        
        return (mainBody, quote)
    }
    
    /// Genera un'anteprima del contenuto email
    static func generatePreview(from body: String, maxLength: Int = 200) -> String? {
        let cleaned = cleanHTMLBody(body)
        let withoutSignature = removeSignatureAndDisclaimer(from: cleaned)
        
        guard !withoutSignature.isEmpty else { return nil }
        
        if withoutSignature.count <= maxLength {
            return withoutSignature
        }
        
        return String(withoutSignature.prefix(maxLength)) + "..."
    }
    
    // MARK: - Email Cache
    
    /// Carica email completa dalla cache se disponibile
    static func loadCachedEmail(id: String) -> Email? {
        return EmailCacheService.shared.loadFullEmail(forId: id)
    }
    
    /// Verifica se l'email ha citazioni
    static func hasQuote(in body: String?) -> Bool {
        guard let body = body else { return false }
        let (_, quote) = extractQuote(from: body)
        return !quote.isEmpty
    }
    
    // MARK: - File Icons
    
    /// Restituisce l'icona SF Symbol appropriata per un file
    static func fileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.text.fill"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx": return "tablecells"
        case "jpg", "jpeg", "png", "gif", "webp": return "photo"
        case "zip", "rar", "7z": return "archivebox"
        case "mp4", "mov", "avi": return "film"
        case "mp3", "wav", "m4a": return "waveform"
        case "txt": return "doc.plaintext"
        case "html", "htm": return "globe"
        default: return "doc"
        }
    }
    
    /// Formatta la dimensione del file in modo leggibile
    /// Formatta la dimensione del file (delega a FileSizeFormatter)
    static func formattedFileSize(_ size: Int) -> String {
        FileSizeFormatter.format(size)
    }
}

// MARK: - String Extension for HTML Stripping (già esistente ma centralizzata)

extension String {
    /// Rimuove tag HTML dalla stringa
    func strippingHTMLTags() -> String {
        return EmailHelpers.cleanHTMLBody(self)
    }
}

