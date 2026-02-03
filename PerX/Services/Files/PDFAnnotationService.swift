import Foundation
import PDFKit
import AppKit
import CoreGraphics

// MARK: - PDF Annotation Service

/// Servizio per gestire annotazioni PDF (evidenziazioni, forme, oscura)
@MainActor
class PDFAnnotationService: ObservableObject {
    static let shared = PDFAnnotationService()
    
    private let defaults = UserDefaults.standard
    private let annotationsKey = "PDFAnnotations"
    
    // MARK: - Annotation Types
    
    enum AnnotationType: String, Codable {
        case highlight // Evidenziazione testo
        case rectangle // Rettangolo
        case ellipse // Ellisse
        case obfuscate // Oscura (pixellazione)
    }
    
    struct PDFAnnotation: Codable, Identifiable {
        let id: String
        let type: AnnotationType
        let filePath: String
        let pageIndex: Int
        let bounds: CGRect
        let color: AnnotationColor
        let strokeWidth: CGFloat
        let fillColor: AnnotationColor?
        let isFilled: Bool
        let textSelection: TextSelection? // Per evidenziazioni
        let obfuscationIntensity: CGFloat? // Per oscura (0.0-1.0)
        
        struct AnnotationColor: Codable {
            let red: CGFloat
            let green: CGFloat
            let blue: CGFloat
            let alpha: CGFloat
            
            var nsColor: NSColor {
                NSColor(red: red, green: green, blue: blue, alpha: alpha)
            }
            
            init(nsColor: NSColor) {
                let rgb = nsColor.usingColorSpace(.deviceRGB) ?? NSColor.white
                self.red = rgb.redComponent
                self.green = rgb.greenComponent
                self.blue = rgb.blueComponent
                self.alpha = rgb.alphaComponent
            }
        }
        
        struct TextSelection: Codable {
            let startIndex: Int
            let endIndex: Int
            let text: String
        }
        
        enum CodingKeys: String, CodingKey {
            case id, type, filePath, pageIndex, textSelection, obfuscationIntensity, strokeWidth, isFilled
            case boundsX, boundsY, boundsWidth, boundsHeight
            case colorRed, colorGreen, colorBlue, colorAlpha
            case fillColorRed, fillColorGreen, fillColorBlue, fillColorAlpha
        }
        
        init(
            id: String = UUID().uuidString,
            type: AnnotationType,
            filePath: String,
            pageIndex: Int,
            bounds: CGRect,
            color: AnnotationColor,
            strokeWidth: CGFloat = 2.0,
            fillColor: AnnotationColor? = nil,
            isFilled: Bool = false,
            textSelection: TextSelection? = nil,
            obfuscationIntensity: CGFloat? = nil
        ) {
            self.id = id
            self.type = type
            self.filePath = filePath
            self.pageIndex = pageIndex
            self.bounds = bounds
            self.color = color
            self.strokeWidth = strokeWidth
            self.fillColor = fillColor
            self.isFilled = isFilled
            self.textSelection = textSelection
            self.obfuscationIntensity = obfuscationIntensity
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            type = try container.decode(AnnotationType.self, forKey: .type)
            filePath = try container.decode(String.self, forKey: .filePath)
            pageIndex = try container.decode(Int.self, forKey: .pageIndex)
            
            let x = try container.decode(CGFloat.self, forKey: .boundsX)
            let y = try container.decode(CGFloat.self, forKey: .boundsY)
            let width = try container.decode(CGFloat.self, forKey: .boundsWidth)
            let height = try container.decode(CGFloat.self, forKey: .boundsHeight)
            bounds = CGRect(x: x, y: y, width: width, height: height)
            
            let r = try container.decode(CGFloat.self, forKey: .colorRed)
            let g = try container.decode(CGFloat.self, forKey: .colorGreen)
            let b = try container.decode(CGFloat.self, forKey: .colorBlue)
            let a = try container.decode(CGFloat.self, forKey: .colorAlpha)
            color = AnnotationColor(nsColor: NSColor(red: r, green: g, blue: b, alpha: a))
            
            strokeWidth = try container.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 2.0
            isFilled = try container.decodeIfPresent(Bool.self, forKey: .isFilled) ?? false
            
            if let fillR = try? container.decode(CGFloat.self, forKey: .fillColorRed),
               let fillG = try? container.decode(CGFloat.self, forKey: .fillColorGreen),
               let fillB = try? container.decode(CGFloat.self, forKey: .fillColorBlue),
               let fillA = try? container.decode(CGFloat.self, forKey: .fillColorAlpha) {
                fillColor = AnnotationColor(nsColor: NSColor(red: fillR, green: fillG, blue: fillB, alpha: fillA))
            } else {
                fillColor = nil
            }
            
            textSelection = try container.decodeIfPresent(TextSelection.self, forKey: .textSelection)
            obfuscationIntensity = try container.decodeIfPresent(CGFloat.self, forKey: .obfuscationIntensity)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(type, forKey: .type)
            try container.encode(filePath, forKey: .filePath)
            try container.encode(pageIndex, forKey: .pageIndex)
            
            try container.encode(bounds.origin.x, forKey: .boundsX)
            try container.encode(bounds.origin.y, forKey: .boundsY)
            try container.encode(bounds.size.width, forKey: .boundsWidth)
            try container.encode(bounds.size.height, forKey: .boundsHeight)
            
            try container.encode(color.red, forKey: .colorRed)
            try container.encode(color.green, forKey: .colorGreen)
            try container.encode(color.blue, forKey: .colorBlue)
            try container.encode(color.alpha, forKey: .colorAlpha)
            
            try container.encode(strokeWidth, forKey: .strokeWidth)
            try container.encode(isFilled, forKey: .isFilled)
            
            if let fillColor = fillColor {
                try container.encode(fillColor.red, forKey: .fillColorRed)
                try container.encode(fillColor.green, forKey: .fillColorGreen)
                try container.encode(fillColor.blue, forKey: .fillColorBlue)
                try container.encode(fillColor.alpha, forKey: .fillColorAlpha)
            }
            
            try container.encodeIfPresent(textSelection, forKey: .textSelection)
            try container.encodeIfPresent(obfuscationIntensity, forKey: .obfuscationIntensity)
        }
    }
    
    // MARK: - Storage
    
    private var annotations: [String: [PDFAnnotation]] = [:] // filePath -> [annotations]
    
    private init() {
        loadAnnotations()
    }
    
    // MARK: - Public API
    
    /// Ottiene tutte le annotazioni per un file
    func getAnnotations(for filePath: String) -> [PDFAnnotation] {
        annotations[filePath] ?? []
    }
    
    /// Ottiene annotazioni per una pagina specifica
    func getAnnotations(for filePath: String, pageIndex: Int) -> [PDFAnnotation] {
        getAnnotations(for: filePath).filter { $0.pageIndex == pageIndex }
    }
    
    /// Aggiunge un'annotazione
    func addAnnotation(_ annotation: PDFAnnotation) {
        if annotations[annotation.filePath] == nil {
            annotations[annotation.filePath] = []
        }
        annotations[annotation.filePath]?.append(annotation)
        saveAnnotations()
    }
    
    /// Rimuove un'annotazione
    func removeAnnotation(id: String, filePath: String) {
        annotations[filePath]?.removeAll { $0.id == id }
        saveAnnotations()
    }
    
    /// Aggiorna un'annotazione
    func updateAnnotation(_ annotation: PDFAnnotation) {
        removeAnnotation(id: annotation.id, filePath: annotation.filePath)
        addAnnotation(annotation)
    }
    
    /// Rimuove tutte le annotazioni per un file
    func clearAnnotations(for filePath: String) {
        annotations.removeValue(forKey: filePath)
        saveAnnotations()
    }
    
    /// Controlla se un file ha annotazioni
    func hasAnnotations(for filePath: String) -> Bool {
        !(annotations[filePath]?.isEmpty ?? true)
    }
    
    // MARK: - Private Helpers
    
    private func loadAnnotations() {
        guard let data = defaults.data(forKey: annotationsKey),
              let decoded = try? JSONDecoder().decode([String: [PDFAnnotation]].self, from: data) else {
            return
        }
        annotations = decoded
        print("[PDFAnnotationService] ✅ Caricate \(annotations.values.reduce(0) { $0 + $1.count }) annotazioni")
    }
    
    private func saveAnnotations() {
        guard let encoded = try? JSONEncoder().encode(annotations) else {
            print("[PDFAnnotationService] ❌ Errore salvataggio annotazioni")
            return
        }
        defaults.set(encoded, forKey: annotationsKey)
    }
}

// MARK: - PDF Annotation Rendering

extension PDFAnnotationService {
    
    /// Applica annotazioni a un PDFDocument per la stampa/esportazione
    func applyAnnotationsToPDF(_ document: PDFDocument, filePath: String, includeAnnotations: Bool) -> PDFDocument? {
        guard includeAnnotations, let annotations = annotations[filePath], !annotations.isEmpty else {
            return document
        }
        
        // Crea nuovo documento
        let newDocument = PDFDocument()
        
        for pageIndex in 0..<document.pageCount {
            guard let originalPage = document.page(at: pageIndex) else { continue }
            
            let pageAnnotations = annotations.filter { $0.pageIndex == pageIndex }
            
            if pageAnnotations.isEmpty {
                // Nessuna annotazione, copia pagina originale
                newDocument.insert(originalPage, at: newDocument.pageCount)
            } else {
                // Crea nuova pagina con annotazioni
                var bounds = originalPage.bounds(for: .mediaBox)
                let newPage = PDFPage()
                newPage.setBounds(bounds, for: .mediaBox)
                
                // Renderizza pagina originale e annotazioni
                let pdfData = NSMutableData()
                guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
                      let context = CGContext(consumer: consumer, mediaBox: &bounds, nil as CFDictionary?) else {
                    newDocument.insert(originalPage, at: newDocument.pageCount)
                    continue
                }
                
                context.beginPDFPage(nil as CFDictionary?)
                
                // Disegna pagina originale
                if let pageRef = originalPage.pageRef {
                    context.drawPDFPage(pageRef)
                } else {
                    originalPage.draw(with: .mediaBox, to: context)
                }
                
                // Disegna annotazioni
                for annotation in pageAnnotations {
                    drawAnnotation(annotation, in: context, pageBounds: bounds)
                }
                
                context.endPDFPage()
                context.closePDF()
                
                // Crea pagina dal data
                if let renderedDocument = PDFDocument(data: pdfData as Data),
                   let renderedPage = renderedDocument.page(at: 0) {
                    newDocument.insert(renderedPage, at: newDocument.pageCount)
                } else {
                    newDocument.insert(originalPage, at: newDocument.pageCount)
                }
            }
        }
        
        return newDocument
    }
    
    private func drawAnnotation(_ annotation: PDFAnnotation, in context: CGContext, pageBounds: CGRect) {
        context.saveGState()
        
        // Converti bounds da coordinate view a coordinate PDF (Y invertito)
        let pdfBounds = CGRect(
            x: annotation.bounds.origin.x,
            y: pageBounds.height - annotation.bounds.origin.y - annotation.bounds.height,
            width: annotation.bounds.width,
            height: annotation.bounds.height
        )
        
        switch annotation.type {
        case .highlight:
            // Evidenziazione testo
            context.setFillColor(annotation.color.nsColor.cgColor)
            context.setBlendMode(.multiply)
            context.fill(pdfBounds)
            
        case .rectangle, .ellipse:
            // Forme
            context.setStrokeColor(annotation.color.nsColor.cgColor)
            context.setLineWidth(annotation.strokeWidth)
            
            if annotation.isFilled, let fillColor = annotation.fillColor {
                context.setFillColor(fillColor.nsColor.cgColor)
            }
            
            if annotation.type == .rectangle {
                if annotation.isFilled {
                    context.fill(pdfBounds)
                }
                context.stroke(pdfBounds)
            } else { // ellipse
                if annotation.isFilled {
                    context.fillEllipse(in: pdfBounds)
                }
                context.strokeEllipse(in: pdfBounds)
            }
            
        case .obfuscate:
            // Oscura (pixellazione)
            let intensity = annotation.obfuscationIntensity ?? 0.8
            obfuscateArea(in: context, bounds: pdfBounds, intensity: intensity)
        }
        
        context.restoreGState()
    }
    
    private func obfuscateArea(in context: CGContext, bounds: CGRect, intensity: CGFloat) {
        // Cattura l'area corrente
        guard let image = context.makeImage()?.cropping(to: bounds) else { return }
        
        // Crea immagine pixellata
        let pixelSize = max(8, 16 * intensity) // Dimensione pixel basata su intensità
        let scaledSize = CGSize(
            width: max(1, Int(bounds.width / pixelSize)),
            height: max(1, Int(bounds.height / pixelSize))
        )
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let smallContext = CGContext(
            data: nil,
            width: Int(scaledSize.width),
            height: Int(scaledSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        
        smallContext.interpolationQuality = .none
        smallContext.draw(image, in: CGRect(origin: .zero, size: scaledSize))
        
        guard let pixelatedImage = smallContext.makeImage() else { return }
        
        // Ridisegna pixellata nell'area originale
        context.interpolationQuality = .none
        context.draw(pixelatedImage, in: bounds)
    }
}
