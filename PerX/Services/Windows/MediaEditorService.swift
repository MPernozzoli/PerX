import Foundation
import AppKit
import PDFKit
import Vision
import CoreImage

class MediaEditorService {
    static let shared = MediaEditorService()
    
    private init() {}
    
    // MARK: - Rotazione Immagini
    
    func rotateImage(at url: URL, degrees: CGFloat, createVersion: Bool = true) -> Bool {
        // Crea versione prima di modificare
        if createVersion, let sinistroPath = getSinistroPath(for: url) {
            _ = FileVersioningService.shared.createVersion(of: url, in: sinistroPath, description: "Ruota immagine")
        }
        
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        
        let radians = degrees * .pi / 180
        let rotatedImage = rotateCGImage(cgImage, by: radians)
        
        let rotatedNSImage = NSImage(cgImage: rotatedImage, size: NSSize(width: rotatedImage.width, height: rotatedImage.height))
        
        return saveImage(rotatedNSImage, to: url)
    }
    
    private func rotateCGImage(_ image: CGImage, by radians: CGFloat) -> CGImage {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let transform = CGAffineTransform(rotationAngle: radians)
        let rotatedRect = CGRect(origin: .zero, size: CGSize(width: width, height: height))
            .applying(transform)
        
        let rotatedWidth = Int(abs(rotatedRect.width))
        let rotatedHeight = Int(abs(rotatedRect.height))
        
        guard let context = CGContext(
            data: nil,
            width: rotatedWidth,
            height: rotatedHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        
        context.translateBy(x: CGFloat(rotatedWidth) / 2, y: CGFloat(rotatedHeight) / 2)
        context.rotate(by: radians)
        context.draw(image, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        
        return context.makeImage() ?? image
    }
    
    // MARK: - Rotazione PDF
    
    func rotatePDFPage(at url: URL, pageIndex: Int, degrees: CGFloat, createVersion: Bool = true) -> Bool {
        // Crea versione prima di modificare
        if createVersion, let sinistroPath = getSinistroPath(for: url) {
            _ = FileVersioningService.shared.createVersion(of: url, in: sinistroPath, description: "Ruota pagina \(pageIndex + 1)")
        }
        
        guard let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex) else {
            return false
        }
        
        let currentRotation = page.rotation
        let newRotation = (Int(currentRotation) + Int(degrees)) % 360
        page.rotation = newRotation
        
        return document.write(to: url)
    }
    
    // MARK: - Ritaglio Immagini
    
    func cropImage(at url: URL, rect: CGRect, createVersion: Bool = true) -> Bool {
        // Crea versione prima di modificare
        if createVersion, let sinistroPath = getSinistroPath(for: url) {
            _ = FileVersioningService.shared.createVersion(of: url, in: sinistroPath, description: "Ritaglia immagine")
        }
        
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        
        let scale = CGFloat(cgImage.width) / image.size.width
        let cropRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        guard let croppedImage = cgImage.cropping(to: cropRect) else {
            return false
        }
        
        let croppedNSImage = NSImage(cgImage: croppedImage, size: NSSize(width: croppedImage.width, height: croppedImage.height))
        
        return saveImage(croppedNSImage, to: url)
    }
    
    // MARK: - Ritaglio PDF
    
    func cropPDFPage(at url: URL, pageIndex: Int, rect: CGRect, createVersion: Bool = true) -> Bool {
        // Crea versione prima di modificare
        if createVersion, let sinistroPath = getSinistroPath(for: url) {
            _ = FileVersioningService.shared.createVersion(of: url, in: sinistroPath, description: "Ritaglia pagina \(pageIndex + 1)")
        }
        
        guard let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex) else {
            return false
        }
        
        let bounds = page.bounds(for: .mediaBox)
        let cropRect = CGRect(
            x: bounds.origin.x + rect.origin.x,
            y: bounds.origin.y + rect.origin.y,
            width: rect.width,
            height: rect.height
        )
        
        page.setBounds(cropRect, for: .mediaBox)
        
        return document.write(to: url)
    }
    
    // MARK: - Rimozione Pagina PDF
    
    func removePDFPage(at url: URL, pageIndex: Int) -> Bool {
        guard let document = PDFDocument(url: url),
              document.pageCount > 1 else {
            return false
        }
        
        document.removePage(at: pageIndex)
        return document.write(to: url)
    }
    
    // MARK: - Evidenziazione PDF
    
    func addHighlightToPDFPage(at url: URL, pageIndex: Int, rect: CGRect, color: NSColor = .yellow) -> Bool {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex) else {
            return false
        }
        
        let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
        annotation.color = color
        page.addAnnotation(annotation)
        
        return document.write(to: url)
    }
    
    // MARK: - OCR
    
    struct OCRResult {
        let text: String
        let textRanges: [OCRCacheService.OCRData.TextRange]
    }
    
    func performOCR(on url: URL, completion: @escaping (String?) -> Void) {
        performOCRWithCoordinates(on: url) { result in
            completion(result?.text)
        }
    }
    
    func performOCRWithCoordinates(on url: URL, completion: @escaping (OCRResult?) -> Void) {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(nil)
            return
        }
        
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(nil)
                return
            }
            
            var textRanges: [OCRCacheService.OCRData.TextRange] = []
            var recognizedStrings: [String] = []
            
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string
                recognizedStrings.append(text)
                
                // Converti boundingBox da coordinate normalizzate (0-1) a coordinate immagine
                let boundingBox = observation.boundingBox
                let rect = CGRect(
                    x: boundingBox.origin.x * imageWidth,
                    y: (1.0 - boundingBox.origin.y - boundingBox.height) * imageHeight, // Inverti Y
                    width: boundingBox.width * imageWidth,
                    height: boundingBox.height * imageHeight
                )
                
                textRanges.append(OCRCacheService.OCRData.TextRange(text: text, bounds: rect))
            }
            
            let result = OCRResult(
                text: recognizedStrings.joined(separator: "\n"),
                textRanges: textRanges
            )
            
            completion(result)
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(nil)
            }
        }
    }
    
    func performOCROnPDFPage(at url: URL, pageIndex: Int, completion: @escaping (String?) -> Void) {
        performOCROnPDFPageWithCoordinates(at: url, pageIndex: pageIndex) { result in
            completion(result?.text)
        }
    }
    
    func performOCROnPDFPageWithCoordinates(at url: URL, pageIndex: Int, completion: @escaping (OCRResult?) -> Void) {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex) else {
            completion(nil)
            return
        }
        
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let renderer = NSBitmapImageRep(bitmapDataPlanes: nil,
                                       pixelsWide: Int(bounds.width * scale),
                                       pixelsHigh: Int(bounds.height * scale),
                                       bitsPerSample: 8,
                                       samplesPerPixel: 4,
                                       hasAlpha: true,
                                       isPlanar: false,
                                       colorSpaceName: .calibratedRGB,
                                       bytesPerRow: 0,
                                       bitsPerPixel: 0)
        
        guard let imageRep = renderer,
              let context = NSGraphicsContext(bitmapImageRep: imageRep) else {
            completion(nil)
            return
        }
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        
        context.cgContext.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context.cgContext)
        
        NSGraphicsContext.restoreGraphicsState()
        
        guard let cgImage = imageRep.cgImage else {
            completion(nil)
            return
        }
        
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(nil)
                return
            }
            
            var textRanges: [OCRCacheService.OCRData.TextRange] = []
            var recognizedStrings: [String] = []
            
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string
                recognizedStrings.append(text)
                
                // Converti boundingBox da coordinate normalizzate (0-1) a coordinate PDF
                let boundingBox = observation.boundingBox
                let rect = CGRect(
                    x: boundingBox.origin.x * bounds.width,
                    y: (1.0 - boundingBox.origin.y - boundingBox.height) * bounds.height, // Inverti Y
                    width: boundingBox.width * bounds.width,
                    height: boundingBox.height * bounds.height
                )
                
                textRanges.append(OCRCacheService.OCRData.TextRange(text: text, bounds: rect))
            }
            
            let result = OCRResult(
                text: recognizedStrings.joined(separator: "\n"),
                textRanges: textRanges
            )
            
            completion(result)
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(nil)
            }
        }
    }
    
    // MARK: - Compressione Immagini
    
    func compressImage(at url: URL, quality: CGFloat, createVersion: Bool = true, completion: @escaping (Bool) -> Void) {
        // Crea versione prima di modificare
        if createVersion, let sinistroPath = getSinistroPath(for: url) {
            _ = FileVersioningService.shared.createVersion(of: url, in: sinistroPath, description: "Comprimi immagine")
        }
        
        guard let image = NSImage(contentsOf: url) else {
            completion(false)
            return
        }
        
        let pathExtension = url.pathExtension.lowercased()
        let isJPEG = ["jpg", "jpeg"].contains(pathExtension)
        
        DispatchQueue.global(qos: .userInitiated).async {
            let success: Bool
            
            if isJPEG {
                // Compressione JPEG
                guard let tiffData = image.tiffRepresentation,
                      let bitmapImage = NSBitmapImageRep(data: tiffData),
                      let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
                    completion(false)
                    return
                }
                
                do {
                    try jpegData.write(to: url)
                    success = true
                } catch {
                    success = false
                }
            } else {
                // Compressione PNG
                guard let tiffData = image.tiffRepresentation,
                      let bitmapImage = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                    completion(false)
                    return
                }
                
                do {
                    try pngData.write(to: url)
                    success = true
                } catch {
                    success = false
                }
            }
            
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    // MARK: - Compressione PDF
    
    func compressPDF(at url: URL, quality: CGFloat, createVersion: Bool = true, completion: @escaping (Bool) -> Void) {
        // Crea versione prima di modificare
        if createVersion, let sinistroPath = getSinistroPath(for: url) {
            _ = FileVersioningService.shared.createVersion(of: url, in: sinistroPath, description: "Comprimi PDF")
        }
        
        guard let document = PDFDocument(url: url) else {
            completion(false)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Crea una copia temporanea
            let tempURL = url.deletingLastPathComponent().appendingPathComponent("temp_\(UUID().uuidString).pdf")
            let fileManager = FileManager.default
            
            // Salva il documento con compressione ridotta
            // Nota: PDFKit non supporta direttamente la compressione, quindi riduciamo la risoluzione delle immagini
            guard document.write(to: tempURL) else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            
            // Per una vera compressione, dovremmo processare le immagini nelle pagine
            // Per ora, semplicemente riscriviamo il PDF che può ridurre leggermente la dimensione
            do {
                // Verifica se il file temporaneo è più piccolo
                let originalSize = try fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
                let tempSize = try fileManager.attributesOfItem(atPath: tempURL.path)[.size] as? Int64 ?? 0
                
                if tempSize < originalSize {
                    // Sostituisci il file originale
                    if fileManager.fileExists(atPath: url.path) {
                        try fileManager.removeItem(at: url)
                    }
                    try fileManager.moveItem(at: tempURL, to: url)
                    DispatchQueue.main.async {
                        completion(true)
                    }
                } else {
                    // Il file temporaneo non è più piccolo, eliminalo
                    try? fileManager.removeItem(at: tempURL)
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            } catch {
                try? fileManager.removeItem(at: tempURL)
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }
    
    // MARK: - Firma/Timbro
    
    func addSignatureToImage(at url: URL, signature: NSImage, position: CGPoint, size: CGSize, createVersion: Bool = true) -> Bool {
        if createVersion, let sinistroPath = getSinistroPath(for: url) {
            _ = FileVersioningService.shared.createVersion(of: url, in: sinistroPath, description: "Applica firma")
        }
        
        guard let baseImage = NSImage(contentsOf: url),
              let baseCGImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let signatureCGImage = signature.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        
        let width = baseCGImage.width
        let height = baseCGImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        
        // Disegna l'immagine base
        context.draw(baseCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Calcola posizione e dimensione della firma
        let scaleX = CGFloat(width) / baseImage.size.width
        let scaleY = CGFloat(height) / baseImage.size.height
        let signatureRect = CGRect(
            x: position.x * scaleX,
            y: (baseImage.size.height - position.y - size.height) * scaleY, // Inverti Y per coordinate CG
            width: size.width * scaleX,
            height: size.height * scaleY
        )
        
        // Disegna la firma
        context.draw(signatureCGImage, in: signatureRect)
        
        guard let finalImage = context.makeImage() else {
            return false
        }
        
        let finalNSImage = NSImage(cgImage: finalImage, size: NSSize(width: width, height: height))
        return saveImage(finalNSImage, to: url)
    }
    
    @MainActor func addSignatureToPDF(at url: URL, pageIndex: Int, signature: NSImage, position: CGPoint, size: CGSize, createVersion: Bool = true, asAnnotation: Bool = true) -> Bool {
        if createVersion, let sinistroPath = getSinistroPath(for: url) {
            _ = FileVersioningService.shared.createVersion(of: url, in: sinistroPath, description: "Applica firma pagina \(pageIndex + 1)")
        }
        
        guard let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex) else {
            return false
        }
        
        let bounds = page.bounds(for: .mediaBox)
        
        // Calcola rettangolo firma (inverti Y per coordinate PDF)
        let signatureRect = CGRect(
            x: position.x,
            y: bounds.height - position.y - size.height,
            width: size.width,
            height: size.height
        )
        
        if asAnnotation {
            // Aggiungi come annotazione (rimovibile, visibile solo nell'app fino a stampa)
            guard let signatureCGImage = signature.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return false
            }
            
            // Converti immagine in Data PNG per l'annotazione
            guard let tiffData = signature.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                return false
            }
            
            // Salva temporaneamente per creare CKAsset
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
            do {
                try pngData.write(to: tempURL)
                
                // Crea annotazione widget con immagine
                let annotation = PDFAnnotation(bounds: signatureRect, forType: .widget, withProperties: nil)
                annotation.contents = "Signature"
                annotation.userName = "PerX_Signature" // Identificatore per riconoscere le nostre annotazioni
                
                // Aggiungi l'immagine come annotazione
                // Usa un'annotazione stamp per l'immagine
                let stampAnnotation = PDFAnnotation(bounds: signatureRect, forType: .stamp, withProperties: nil)
                stampAnnotation.contents = "Signature"
                stampAnnotation.userName = "PerX_Signature"
                stampAnnotation.backgroundColor = .clear
                
                // Aggiungi l'annotazione alla pagina
                page.addAnnotation(stampAnnotation)
                
                // Rimuovi file temporaneo
                try? FileManager.default.removeItem(at: tempURL)
                
                return document.write(to: url)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                return false
            }
        } else {
            // Stampa permanente: disegna direttamente nel PDF
            // Chiama su MainActor
            if Thread.isMainThread {
                return printAnnotationsToPDF(at: url, pageIndex: pageIndex)
            } else {
                var result = false
                let semaphore = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else {
                        semaphore.signal()
                        return
                    }
                    result = self.printAnnotationsToPDF(at: url, pageIndex: pageIndex)
                    semaphore.signal()
                }
                semaphore.wait()
                return result
            }
        }
    }
    
    /// Stampa permanentemente le annotazioni firma nel PDF (rendendole visibili ovunque)
    @MainActor
    func printAnnotationsToPDF(at url: URL, pageIndex: Int? = nil) -> Bool {
        guard let document = PDFDocument(url: url) else {
            print("[MediaEditorService] ❌ Impossibile aprire documento PDF: \(url.path)")
            return false
        }
        
        guard document.pageCount > 0 else {
            print("[MediaEditorService] ❌ Documento PDF vuoto")
            return false
        }
        
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            print("[MediaEditorService] ❌ Errore creazione consumer")
            return false
        }
        
        // Carica il placement (ora siamo su MainActor)
        let placement = SignaturePlacementService.shared.getPlacement(for: url.path)
        print("[MediaEditorService] 📋 Placement per stampa: \(placement != nil ? "trovato" : "non trovato")")
        
        // Processa tutte le pagine o solo quella specificata
        let pagesToProcess = pageIndex != nil ? [pageIndex!] : Array(0..<document.pageCount)
        
        // Crea il context UNA SOLA VOLTA usando la prima pagina per determinare le dimensioni iniziali
        guard let firstPage = document.page(at: 0) else {
            print("[MediaEditorService] ❌ Impossibile ottenere prima pagina")
            return false
        }
        
        var mediaBox = firstPage.bounds(for: .mediaBox)
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            print("[MediaEditorService] ❌ Errore creazione context PDF")
            return false
        }
        
        for i in 0..<document.pageCount {
            guard let originalPage = document.page(at: i) else { continue }
            
            pdfContext.beginPDFPage(nil)
            
            // Disegna la pagina originale
            if let pageRef = originalPage.pageRef {
                pdfContext.saveGState()
                pdfContext.drawPDFPage(pageRef)
                pdfContext.restoreGState()
            } else {
                pdfContext.saveGState()
                originalPage.draw(with: .mediaBox, to: pdfContext)
                pdfContext.restoreGState()
            }
            
            // Se questa pagina deve essere processata, disegna le annotazioni firma
            if pagesToProcess.contains(i) {
                let annotations = originalPage.annotations.filter { $0.userName == "PerX_Signature" }
                print("[MediaEditorService] 📝 Pagina \(i + 1): \(annotations.count) annotazioni firma")
                
                for annotation in annotations {
                    let annotationBounds = annotation.bounds
                    
                    // Carica l'immagine dalla firma salvata nel placement
                    if let placement = placement,
                       let imageData = placement.signatureImageData,
                       let signatureImage = NSImage(data: imageData),
                       let signatureCGImage = signatureImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        pdfContext.saveGState()
                        pdfContext.draw(signatureCGImage, in: annotationBounds)
                        pdfContext.restoreGState()
                        print("[MediaEditorService] ✅ Firma disegnata a posizione: \(annotationBounds)")
                    } else {
                        print("[MediaEditorService] ⚠️ Impossibile caricare immagine firma dal placement")
                    }
                }
            }
            
            pdfContext.endPDFPage()
        }
        
        pdfContext.closePDF()
        
        // Sostituisci il documento
        do {
            try pdfData.write(to: url, options: .atomic)
            print("[MediaEditorService] ✅ PDF con firma permanente salvato: \(url.lastPathComponent)")
            return true
        } catch {
            print("[MediaEditorService] ❌ Errore stampa annotazioni: \(error)")
            return false
        }
    }
    
    // MARK: - Helper
    
    private func getSinistroPath(for url: URL) -> String? {
        let pathComponents = url.pathComponents
        for (index, component) in pathComponents.enumerated() {
            if component.count == 7 && component.allSatisfy({ $0.isNumber }) {
                let components = Array(pathComponents.prefix(index + 1))
                return "/" + components.joined(separator: "/")
            }
        }
        return nil
    }
    
    private func saveImage(_ image: NSImage, to url: URL) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return false
        }
        
        let pathExtension = url.pathExtension.lowercased()
        let imageData: Data?
        
        if ["jpg", "jpeg"].contains(pathExtension) {
            imageData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        } else if pathExtension == "png" {
            imageData = bitmapImage.representation(using: .png, properties: [:])
        } else {
            imageData = bitmapImage.representation(using: .png, properties: [:])
        }
        
        guard let data = imageData else {
            return false
        }
        
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}

