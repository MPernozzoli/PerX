import Foundation
import CoreGraphics

/// Servizio per cacheare il testo OCR dei file
@MainActor
class OCRCacheService: ObservableObject {
    static let shared = OCRCacheService()
    
    // Cache: [filePath: [pageIndex: OCRData]]
    private var ocrCache: [String: [Int: OCRData]] = [:]
    
    struct OCRData: Codable {
        let text: String
        let textRanges: [TextRange] // Coordinate del testo riconosciuto
        
        struct TextRange: Codable {
            let text: String
            let bounds: CGRect
        }
    }
    
    private init() {
        loadCache()
    }
    
    // MARK: - Public API
    
    /// Ottiene il testo OCR per un file (immagine o PDF pagina)
    func getOCRText(for filePath: String, pageIndex: Int? = nil) -> String? {
        let pageKey = pageIndex ?? 0
        return ocrCache[filePath]?[pageKey]?.text
    }
    
    /// Ottiene i dati OCR completi per un file
    func getOCRData(for filePath: String, pageIndex: Int? = nil) -> OCRData? {
        let pageKey = pageIndex ?? 0
        return ocrCache[filePath]?[pageKey]
    }
    
    /// Ottiene tutto il testo OCR per un file (utile per PDF con più pagine)
    func getAllOCRText(for filePath: String) -> String {
        guard let pages = ocrCache[filePath] else { return "" }
        return pages.sorted(by: { $0.key < $1.key })
            .map { $0.value.text }
            .joined(separator: "\n")
    }
    
    /// Salva il testo OCR per un file
    func saveOCRText(_ text: String, for filePath: String, pageIndex: Int? = nil, textRanges: [OCRData.TextRange] = []) {
        let pageKey = pageIndex ?? 0
        if ocrCache[filePath] == nil {
            ocrCache[filePath] = [:]
        }
        ocrCache[filePath]?[pageKey] = OCRData(text: text, textRanges: textRanges)
        saveCache()
    }
    
    /// Rimuove il testo OCR per un file
    func removeOCRText(for filePath: String) {
        ocrCache.removeValue(forKey: filePath)
        saveCache()
    }
    
    /// Cerca il testo in tutti i file nella cache
    func searchInCache(_ searchText: String, in filePaths: [String]) -> [SearchResult] {
        guard !searchText.isEmpty else { return [] }
        
        var results: [SearchResult] = []
        let lowercasedSearch = searchText.lowercased()
        
        for filePath in filePaths {
            if let pages = ocrCache[filePath] {
                for (pageIndex, ocrData) in pages {
                    let text = ocrData.text
                    let lowercasedText = text.lowercased()
                    if lowercasedText.contains(lowercasedSearch) {
                        // Trova tutte le occorrenze nel testo
                        var searchIndex = lowercasedText.startIndex
                        var occurrenceIndex = 0
                        while let range = lowercasedText.range(of: lowercasedSearch, range: searchIndex..<lowercasedText.endIndex) {
                            let startIndex = text.index(text.startIndex, offsetBy: text.distance(from: lowercasedText.startIndex, to: range.lowerBound))
                            let endIndex = text.index(startIndex, offsetBy: searchText.count)
                            
                            // Cerca le coordinate corrispondenti nei textRanges
                            var matchingBounds: CGRect? = nil
                            if !ocrData.textRanges.isEmpty {
                                // Trova il range che contiene il testo cercato
                                let searchString = String(text[startIndex..<endIndex])
                                for textRange in ocrData.textRanges {
                                    if textRange.text.lowercased().contains(lowercasedSearch) {
                                        matchingBounds = textRange.bounds
                                        break
                                    }
                                }
                            }
                            
                            results.append(SearchResult(
                                filePath: filePath,
                                pageIndex: pageIndex,
                                range: startIndex..<endIndex,
                                context: getContext(from: text, around: startIndex),
                                bounds: matchingBounds,
                                occurrenceIndex: occurrenceIndex
                            ))
                            
                            searchIndex = range.upperBound
                            occurrenceIndex += 1
                        }
                    }
                }
            }
        }
        
        return results
    }
    
    // MARK: - Search Result
    
    struct SearchResult {
        let filePath: String
        let pageIndex: Int
        let range: Range<String.Index>
        let context: String
        let bounds: CGRect? // Coordinate per evidenziazione
        let occurrenceIndex: Int // Indice dell'occorrenza nella pagina
    }
    
    // MARK: - Private
    
    private func getContext(from text: String, around index: String.Index, contextLength: Int = 50) -> String {
        let start = text.index(max(text.startIndex, text.index(index, offsetBy: -contextLength)), offsetBy: 0)
        let end = text.index(min(text.endIndex, text.index(index, offsetBy: contextLength)), offsetBy: 0)
        return String(text[start..<end])
    }
    
    private func loadCache() {
        // Carica da UserDefaults o file system
        // Per ora usiamo UserDefaults per semplicità
        if let data = UserDefaults.standard.data(forKey: "OCRCacheService.cache"),
           let decoded = try? JSONDecoder().decode([String: [String: OCRData]].self, from: data) {
            ocrCache = decoded.mapValues { pages in
                pages.reduce(into: [Int: OCRData]()) { result, pair in
                    if let pageIndex = Int(pair.key) {
                        result[pageIndex] = pair.value
                    }
                }
            }
        }
    }
    
    private func saveCache() {
        // Salva in UserDefaults
        let encoded = ocrCache.mapValues { pages in
            pages.reduce(into: [String: OCRData]()) { result, pair in
                result[String(pair.key)] = pair.value
            }
        }
        
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: "OCRCacheService.cache")
        }
    }
}
