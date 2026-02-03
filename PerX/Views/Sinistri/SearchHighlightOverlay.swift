import SwiftUI
import PDFKit

/// Overlay per evidenziare i risultati della ricerca
struct SearchHighlightOverlay: View {
    let searchResults: [OCRCacheService.SearchResult]
    let currentSearchIndex: Int
    let filePath: String
    let pageIndex: Int
    let isPDF: Bool
    
    var body: some View {
        if isPDF {
            PDFSearchHighlightOverlay(
                searchResults: searchResults,
                currentSearchIndex: currentSearchIndex,
                filePath: filePath,
                pageIndex: pageIndex
            )
        } else {
            ImageSearchHighlightOverlay(
                searchResults: searchResults,
                currentSearchIndex: currentSearchIndex,
                filePath: filePath
            )
        }
    }
}

// MARK: - PDF Search Highlight

struct PDFSearchHighlightOverlay: View {
    let searchResults: [OCRCacheService.SearchResult]
    let currentSearchIndex: Int
    let filePath: String
    let pageIndex: Int
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(searchResults.enumerated()), id: \.offset) { index, result in
                if let bounds = result.bounds {
                    let isActive = index == currentSearchIndex
                    
                    // Le coordinate bounds sono relative al documento PDF
                    // Dobbiamo convertirle in coordinate relative alla vista
                    // Per ora usiamo un approccio semplificato
                    Rectangle()
                        .fill(isActive ? Color.yellow.opacity(0.4) : Color.orange.opacity(0.3))
                        .border(isActive ? Color.yellow : Color.clear, width: 2)
                        .frame(width: bounds.width, height: bounds.height)
                        .position(
                            x: bounds.midX,
                            y: geometry.size.height - bounds.midY // Inverti Y per coordinate SwiftUI
                        )
                }
            }
        }
    }
}

// MARK: - Image Search Highlight

struct ImageSearchHighlightOverlay: View {
    let searchResults: [OCRCacheService.SearchResult]
    let currentSearchIndex: Int
    let filePath: String
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(searchResults.enumerated()), id: \.offset) { index, result in
                if let bounds = result.bounds {
                    let isActive = index == currentSearchIndex
                    let scaleX = geometry.size.width / bounds.width
                    let scaleY = geometry.size.height / bounds.height
                    // Assumiamo che bounds sia relativo all'immagine originale
                    // Qui dovremmo scalare in base alla dimensione dell'immagine visualizzata
                    
                    Rectangle()
                        .fill(isActive ? Color.yellow.opacity(0.4) : Color.orange.opacity(0.3))
                        .border(isActive ? Color.yellow : Color.clear, width: 2)
                        .frame(width: bounds.width, height: bounds.height)
                        .position(
                            x: bounds.midX,
                            y: geometry.size.height - bounds.midY // Inverti Y
                        )
                }
            }
        }
    }
}
