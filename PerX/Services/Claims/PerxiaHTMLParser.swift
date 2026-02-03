import Foundation

/// Parser per estrarre beni e relazione complessiva da HTML streaming
class PerxiaHTMLParser {
    static let shared = PerxiaHTMLParser()
    
    private init() {}
    
    struct ParsedBene {
        var tipologia: String = ""
        var componenti: String?
        var modello: String?
        var anno: String?
        var osservazioniVisive: String?
        var valutazioneTest: String?
        var compatibilitaGaranzia: String?
        var stimaEconomica: String?
        var noteAggiuntive: String?
    }
    
    private var currentHTML = ""
    private var currentBene: ParsedBene?
    private var inBeneArticle = false
    private var inRelazioneSection = false
    private var currentTag = ""
    private var currentContent = ""
    
    /// Processa un chunk di HTML in streaming
    func processChunk(_ chunk: String) -> (beni: [ParsedBene], relazione: String?) {
        currentHTML += chunk
        
        var beni: [ParsedBene] = []
        var relazione: String?
        
        // Estrai tutti i beni completi
        beni = extractBeni(from: currentHTML)
        
        // Estrai relazione complessiva
        relazione = extractRelazione(from: currentHTML)
        
        return (beni, relazione)
    }
    
    /// Estrae tutti i beni dall'HTML
    private func extractBeni(from html: String) -> [ParsedBene] {
        var beni: [ParsedBene] = []
        
        // Pattern per trovare <article class="bene">...</article>
        let pattern = #"<article\s+class="bene">(.*?)</article>"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        
        guard let regex = regex else { return beni }
        
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: range)
        
        for match in matches {
            if let articleRange = Range(match.range(at: 1), in: html) {
                let articleContent = String(html[articleRange])
                if let bene = parseBeneArticle(articleContent) {
                    beni.append(bene)
                }
            }
        }
        
        return beni
    }
    
    /// Parsa un singolo article bene
    private func parseBeneArticle(_ content: String) -> ParsedBene? {
        var bene = ParsedBene()
        
        // Estrai h3 per tipologia
        if let h3Match = content.range(of: #"<h3>Bene \d+:\s*(.*?)</h3>"#, options: .regularExpression) {
            let h3Content = String(content[h3Match])
            if let tipologiaMatch = h3Content.range(of: #":\s*(.*?)$"#, options: .regularExpression) {
                bene.tipologia = String(h3Content[tipologiaMatch]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Estrai tutti i paragrafi <p><strong>...</strong>...</p>
        let pPattern = #"<p><strong>(.*?):</strong>\s*(.*?)</p>"#
        let pRegex = try? NSRegularExpression(pattern: pPattern, options: [.dotMatchesLineSeparators])
        
        if let pRegex = pRegex {
            let range = NSRange(content.startIndex..., in: content)
            let matches = pRegex.matches(in: content, options: [], range: range)
            
            for match in matches {
                if match.numberOfRanges >= 3,
                   let labelRange = Range(match.range(at: 1), in: content),
                   let valueRange = Range(match.range(at: 2), in: content) {
                    let label = String(content[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = String(content[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    switch label.lowercased() {
                    case "componente/i":
                        bene.componenti = value.isEmpty ? nil : value
                    case "modello":
                        bene.modello = value.isEmpty ? nil : value
                    case "anno":
                        bene.anno = value.isEmpty ? nil : value
                    case "osservazioni visive":
                        bene.osservazioniVisive = value.isEmpty ? nil : value
                    case "valutazione test e misure":
                        bene.valutazioneTest = value.isEmpty ? nil : value
                    case "compatibilità con garanzia fenomeno elettrico":
                        bene.compatibilitaGaranzia = value.isEmpty ? nil : value
                    case "stima economica del danno":
                        bene.stimaEconomica = value.isEmpty ? nil : value
                    case "note aggiuntive (giustificativi, incongruenze, beni non visti/visti ma non denunciati)":
                        bene.noteAggiuntive = value.isEmpty ? nil : value
                    default:
                        break
                    }
                }
            }
        }
        
        return bene.tipologia.isEmpty ? nil : bene
    }
    
    /// Estrae la relazione complessiva
    private func extractRelazione(from html: String) -> String? {
        // Cerca <section id="relazione-complessiva">...</section>
        let pattern = #"<section\s+id="relazione-complessiva">.*?<h2>.*?</h2>\s*<p>(.*?)</p>\s*</section>"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        
        guard let regex = regex else { return nil }
        
        let range = NSRange(html.startIndex..., in: html)
        if let match = regex.firstMatch(in: html, options: [], range: range),
           match.numberOfRanges >= 2,
           let contentRange = Range(match.range(at: 1), in: html) {
            let relazione = String(html[contentRange])
            return relazione.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    /// Reset del parser per una nuova analisi
    func reset() {
        currentHTML = ""
        currentBene = nil
        inBeneArticle = false
        inRelazioneSection = false
        currentTag = ""
        currentContent = ""
    }
    
    /// Estrae JSON per tagging foto se presente
    func extractFotoTags(from html: String) -> [[String: Any]]? {
        // Cerca JSON nel formato: {"foto_tags": [...]}
        let pattern = #"\{[^}]*"foto_tags"[^}]*\}"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        
        guard let regex = regex else { return nil }
        
        let range = NSRange(html.startIndex..., in: html)
        if let match = regex.firstMatch(in: html, options: [], range: range),
           let jsonRange = Range(match.range, in: html) {
            let jsonString = String(html[jsonRange])
            
            if let jsonData = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let fotoTags = json["foto_tags"] as? [[String: Any]] {
                return fotoTags
            }
        }
        
        return nil
    }
}

