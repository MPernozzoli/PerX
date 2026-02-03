import Foundation
import PDFKit

/// Parser per estrarre dati dal PDF "incarico" del Gruppo Generali
/// Estrae: Regolarità amministrativa (Si/No) e Data pagamento premio
class IncaricoPDFParser {
    static let shared = IncaricoPDFParser()
    
    private let fileService = FileService.shared
    
    private init() {}
    
    // MARK: - Result Type
    
    struct ParseResult {
        /// Regolarità amministrativa: true = Si, false = No, nil = non trovata
        let regolaritaAmministrativa: Bool?
        /// Data pagamento premio (valorizzata solo se regolarità = true)
        let dataPagamentoPremio: Date?
        
        // Altri dati estraibili da incarico
        let dataSinistro: Date?
        let dataDenuncia: Date?
        let dataIncarico: Date?
        let codiceAgenzia: String?
        let nomeAgenzia: String?
        let subagenzia: String?
        /// Indica se il parsing è andato a buon fine (PDF leggibile con dati estratti)
        let success: Bool
        /// Messaggio di errore/warning
        let message: String?
        
        static func notFound() -> ParseResult {
            ParseResult(
                regolaritaAmministrativa: nil,
                dataPagamentoPremio: nil,
                dataSinistro: nil,
                dataDenuncia: nil,
                dataIncarico: nil,
                codiceAgenzia: nil,
                nomeAgenzia: nil,
                subagenzia: nil,
                success: false,
                message: "Dati non trovati nel PDF"
            )
        }
        
        static func error(_ message: String) -> ParseResult {
            ParseResult(
                regolaritaAmministrativa: nil,
                dataPagamentoPremio: nil,
                dataSinistro: nil,
                dataDenuncia: nil,
                dataIncarico: nil,
                codiceAgenzia: nil,
                nomeAgenzia: nil,
                subagenzia: nil,
                success: false,
                message: message
            )
        }
    }
    
    // MARK: - Public API
    
    /// Parsifica un PDF incarico ed estrae regolarità amministrativa e data pagamento premio
    /// - Parameter pdfPath: Percorso del file PDF
    /// - Returns: Risultato del parsing
    func parse(pdfPath: String) -> ParseResult {
        let pdfURL = URL(fileURLWithPath: pdfPath)
        
        // Carica il PDF con security-scoped access
        guard let text = extractText(from: pdfURL) else {
            return .error("Impossibile estrarre testo dal PDF")
        }
        
        // Normalizza il testo per il parsing
        let normalizedText = normalizeText(text)
        
        // Estrai regolarità amministrativa
        let regolarita = extractRegolaritaAmministrativa(from: normalizedText)
        
        // Estrai data pagamento premio (solo se regolarità è presente)
        var dataPagamento: Date? = nil
        if regolarita == true {
            dataPagamento = extractDataPagamentoPremio(from: normalizedText)
        }
        
        // Altri dati (sempre)
        let dataSinistro = extractDate(forLabels: ["data sinistro"], from: normalizedText)
        let dataDenuncia = extractDate(forLabels: ["data denuncia"], from: normalizedText)
        let dataIncarico = extractDate(forLabels: ["data incarico"], from: normalizedText)
        let (codAgenzia, nomeAgenzia) = extractAgenzia(from: normalizedText)
        let subagenzia = extractSubagenzia(from: normalizedText)
        
        // Verifica se abbiamo trovato almeno un dato utile
        let hasAny =
        regolarita != nil ||
        dataPagamento != nil ||
        dataSinistro != nil ||
        dataDenuncia != nil ||
        dataIncarico != nil ||
        codAgenzia != nil ||
        nomeAgenzia != nil ||
        subagenzia != nil
        
        if hasAny {
            return ParseResult(
                regolaritaAmministrativa: regolarita,
                dataPagamentoPremio: dataPagamento,
                dataSinistro: dataSinistro,
                dataDenuncia: dataDenuncia,
                dataIncarico: dataIncarico,
                codiceAgenzia: codAgenzia,
                nomeAgenzia: nomeAgenzia,
                subagenzia: subagenzia,
                success: true,
                message: nil
            )
        }
        
        return .notFound()
    }
    
    /// Verifica se un PDF contiene i campi attesi per un incarico Generali
    /// Usato per selezionare il PDF corretto quando ce ne sono più con tag "incarico"
    func isValidIncaricoGenerali(pdfPath: String) -> Bool {
        let pdfURL = URL(fileURLWithPath: pdfPath)
        
        guard let text = extractText(from: pdfURL) else {
            return false
        }
        
        let normalizedText = normalizeText(text)
        
        // Verifica presenza di entrambi i campi chiave
        let hasRegolarita = normalizedText.contains("regolarita amministrativa")
        let hasDataPremio = normalizedText.contains("data pag") || normalizedText.contains("data pag.")
        
        return hasRegolarita && hasDataPremio
    }
    
    // MARK: - Text Extraction
    
    private func extractText(from url: URL) -> String? {
        // Prova prima con security-scoped access
        if let text: String = fileService.performWithSecurityScopedAccess(to: url.deletingLastPathComponent().path, operation: {
            guard let document = PDFDocument(url: url) else {
                throw NSError(
                    domain: "IncaricoPDFParser",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "PDF non leggibile"]
                )
            }
            guard let extracted = extractTextFromDocument(document) else {
                throw NSError(
                    domain: "IncaricoPDFParser",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Testo PDF vuoto"]
                )
            }
            return extracted
        }) {
            return text
        }
        
        // Fallback: prova direttamente
        guard let document = PDFDocument(url: url) else { return nil }
        return extractTextFromDocument(document)
    }
    
    private func extractTextFromDocument(_ document: PDFDocument) -> String? {
        var fullText = ""
        
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            if let pageText = page.string {
                fullText += pageText + "\n"
            }
        }
        
        return fullText.isEmpty ? nil : fullText
    }
    
    // MARK: - Text Normalization
    
    private func normalizeText(_ text: String) -> String {
        var normalized = text.lowercased()
        
        // Rimuovi accenti da "Regolarità" per tollerare "Regolarita"
        normalized = normalized.replacingOccurrences(of: "à", with: "a")
        normalized = normalized.replacingOccurrences(of: "è", with: "e")
        normalized = normalized.replacingOccurrences(of: "é", with: "e")
        normalized = normalized.replacingOccurrences(of: "ì", with: "i")
        normalized = normalized.replacingOccurrences(of: "ò", with: "o")
        normalized = normalized.replacingOccurrences(of: "ù", with: "u")
        
        // Normalizza spazi multipli e newline
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return normalized
    }
    
    // MARK: - Field Extraction
    
    /// Estrae regolarità amministrativa dal testo
    /// Cerca pattern: "regolarita amministrativa: si" o "regolarita amministrativa: no"
    private func extractRegolaritaAmministrativa(from text: String) -> Bool? {
        // Pattern: "regolarita amministrativa" seguito da ":" e poi "si" o "no"
        // Tollerando spazi e varianti
        let patterns = [
            #"regolarita\s*amministrativa\s*[:\s]+\s*(si|no)\b"#,
            #"regolarita\s*amministrativa\s*[:\s]+\s*(sì|sÌ)\b"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    if let valueRange = Range(match.range(at: 1), in: text) {
                        let value = String(text[valueRange]).lowercased()
                        if value == "si" || value == "sì" {
                            return true
                        } else if value == "no" {
                            return false
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Estrae data pagamento premio dal testo
    /// Formato atteso: YYYY-MM-DD (es. 2025-12-09 = 9 dicembre 2025)
    private func extractDataPagamentoPremio(from text: String) -> Date? {
        // Pattern per "Data pag. premio:" o "Data pag premio:" seguito da data
        // Formato: YYYY-MM-DD o YYYY/MM/DD
        let patterns = [
            #"data\s*pag\.?\s*premio\s*[:\s]+\s*(\d{4}[-/]\d{2}[-/]\d{2})"#,
            #"data\s*pagamento\s*premio\s*[:\s]+\s*(\d{4}[-/]\d{2}[-/]\d{2})"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    if let dateRange = Range(match.range(at: 1), in: text) {
                        let dateString = String(text[dateRange])
                        if let date = parseDate(dateString) {
                            return date
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Parsifica una data in formato YYYY-MM-DD o YYYY/MM/DD
    private func parseDate(_ dateString: String) -> Date? {
        let normalized = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "/")
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")

        let candidateFormats = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "dd/MM/yyyy",
            "dd-MM-yyyy",
            "dd/MM/yy",
            "dd-MM-yy"
        ]
        
        for format in candidateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return date
            }
        }
        
        // Prova anche con separatori '-' se arriva con '/'
        let dashNormalized = normalized.replacingOccurrences(of: "/", with: "-")
        if dashNormalized != normalized {
            for format in ["yyyy-MM-dd", "dd-MM-yyyy", "dd-MM-yy"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: dashNormalized) {
                    return date
                }
            }
        }
        
        return nil
    }
    
    private func extractDate(forLabels labels: [String], from text: String) -> Date? {
        // Cattura date in vari formati dopo etichetta (es. "data sinistro: 2025-12-09" o "data denuncia 09/12/2025")
        let datePattern = #"(\d{4}[-/]\d{2}[-/]\d{2}|\d{2}[-/]\d{2}[-/]\d{2,4})"#
        
        for label in labels {
            let pattern = #"\#(label)\s*[:\s]+\s*\#(datePattern)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   let dateRange = Range(match.range(at: 1), in: text) {
                    return parseDate(String(text[dateRange]))
                }
            }
        }
        
        return nil
    }
    
    private func extractAgenzia(from text: String) -> (codice: String?, nome: String?) {
        // Pattern atteso: "agenzia: SIGLA NOME..." oppure "agenzia: SIGLA - NOME..."
        // Non-greedy fino al prossimo campo noto.
        let pattern = #"agenzia\s*[:\s]+\s*([a-z0-9]{2,10})\s*(?:-\s*)?(.+?)(?=\s+(subagenzia|data\s+sinistro|data\s+denuncia|data\s+incarico|regolarita|data\s+pag)|$)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (nil, nil)
        }
        
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return (nil, nil)
        }
        
        let codice: String?
        if let r = Range(match.range(at: 1), in: text) {
            codice = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        } else {
            codice = nil
        }
        
        let nome: String?
        if let r = Range(match.range(at: 2), in: text) {
            let raw = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            nome = raw.isEmpty ? nil : raw
        } else {
            nome = nil
        }
        
        return (codice, nome)
    }
    
    private func extractSubagenzia(from text: String) -> String? {
        let pattern = #"subagenzia\s*[:\s]+\s*(.+?)(?=\s+(agenzia|data\s+sinistro|data\s+denuncia|data\s+incarico|regolarita|data\s+pag)|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let value = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    
    // MARK: - PDF Selection
    
    /// Trova il PDF incarico corretto tra più file taggati
    /// Preferisce quello che contiene i campi attesi e il più recente
    func findBestIncaricoFile(fromPaths paths: [String]) -> String? {
        // Filtra solo PDF
        let pdfPaths = paths.filter { $0.lowercased().hasSuffix(".pdf") }
        
        if pdfPaths.isEmpty { return nil }
        if pdfPaths.count == 1 { return pdfPaths.first }
        
        // Trova quelli validi (contengono i campi attesi)
        let validPaths = pdfPaths.filter { isValidIncaricoGenerali(pdfPath: $0) }
        
        if validPaths.isEmpty {
            // Nessuno valido, prendi il primo PDF
            return pdfPaths.first
        }
        
        if validPaths.count == 1 {
            return validPaths.first
        }
        
        // Più di uno valido: prendi il più recente per data modifica
        let sortedByDate = validPaths.sorted { path1, path2 in
            let date1 = getModificationDate(path: path1)
            let date2 = getModificationDate(path: path2)
            return date1 > date2
        }
        
        return sortedByDate.first
    }
    
    private func getModificationDate(path: String) -> Date {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.modificationDate] as? Date) ?? .distantPast
    }
}
