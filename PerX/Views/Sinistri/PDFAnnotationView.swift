import SwiftUI
import PDFKit
import AppKit

// MARK: - PDF Annotation View

/// Overlay per gestire annotazioni su PDF (evidenziazione, forme, oscura)
struct PDFAnnotationView: NSViewRepresentable {
    let pdfView: InfinitePDFView
    let pageIndex: Int
    let filePath: String
    let annotationMode: AnnotationMode?
    
    @Binding var strokeColor: Color
    @Binding var fillColor: Color?
    @Binding var strokeWidth: CGFloat
    @Binding var isFilled: Bool
    @Binding var obfuscationIntensity: CGFloat
    
    @StateObject private var annotationService = PDFAnnotationService.shared
    
    func makeNSView(context: Context) -> AnnotationOverlayView {
        let overlay = AnnotationOverlayView()
        overlay.setup(
            pdfView: pdfView,
            pageIndex: pageIndex,
            filePath: filePath,
            annotationService: annotationService
        )
        return overlay
    }
    
    func updateNSView(_ nsView: AnnotationOverlayView, context: Context) {
        nsView.update(
            annotationMode: annotationMode,
            strokeColor: NSColor(strokeColor),
            fillColor: fillColor.map { NSColor($0) },
            strokeWidth: strokeWidth,
            isFilled: isFilled,
            obfuscationIntensity: obfuscationIntensity
        )
    }
}

// MARK: - Annotation Overlay View

class AnnotationOverlayView: NSView {
    weak var pdfView: InfinitePDFView?
    var pageIndex: Int = 0
    var filePath: String = ""
    weak var annotationService: PDFAnnotationService?
    
    private var annotationMode: AnnotationMode?
    private var strokeColor: NSColor = .yellow
    private var fillColor: NSColor?
    private var strokeWidth: CGFloat = 2.0
    private var isFilled: Bool = false
    private var obfuscationIntensity: CGFloat = 0.8
    
    // Drawing state
    private var isDrawing = false
    private var startPoint: CGPoint = .zero
    private var currentRect: CGRect = .zero
    private var textSelection: PDFSelection?
    private var annotations: [PDFAnnotationService.PDFAnnotation] = []
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    func setup(pdfView: InfinitePDFView, pageIndex: Int, filePath: String, annotationService: PDFAnnotationService) {
        self.pdfView = pdfView
        self.pageIndex = pageIndex
        self.filePath = filePath
        self.annotationService = annotationService
        
        loadAnnotations()
        setupTrackingArea()
    }
    
    func update(
        annotationMode: AnnotationMode?,
        strokeColor: NSColor,
        fillColor: NSColor?,
        strokeWidth: CGFloat,
        isFilled: Bool,
        obfuscationIntensity: CGFloat
    ) {
        self.annotationMode = annotationMode
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.strokeWidth = strokeWidth
        self.isFilled = isFilled
        self.obfuscationIntensity = obfuscationIntensity
        
        loadAnnotations()
        needsDisplay = true
    }
    
    private func setupTrackingArea() {
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        setupTrackingArea()
    }
    
    private func loadAnnotations() {
        annotations = annotationService?.getAnnotations(for: filePath, pageIndex: pageIndex) ?? []
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        guard let mode = annotationMode else { return }
        
        let location = convert(event.locationInWindow, from: nil)
        startPoint = location
        isDrawing = true
        currentRect = .zero
        
        switch mode {
        case .highlight:
            startTextSelection(at: location)
        case .shape, .obfuscate:
            // Inizia disegno forma
            break
        }
        
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDrawing, let mode = annotationMode else { return }
        
        let location = convert(event.locationInWindow, from: nil)
        
        switch mode {
        case .highlight:
            updateTextSelection(to: location)
        case .shape, .obfuscate:
            // Aggiorna rettangolo disegno
            currentRect = CGRect(
                x: min(startPoint.x, location.x),
                y: min(startPoint.y, location.y),
                width: abs(location.x - startPoint.x),
                height: abs(location.y - startPoint.y)
            )
        }
        
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isDrawing else { return }
        isDrawing = false
        
        guard let mode = annotationMode,
              let pdfView = pdfView,
              let document = pdfView.document,
              let page = document.page(at: pageIndex) else {
            needsDisplay = true
            return
        }
        
        let pageBounds = page.bounds(for: .mediaBox)
        let viewBounds = bounds
        let scaleX = pageBounds.width / viewBounds.width
        let scaleY = pageBounds.height / viewBounds.height
        
        switch mode {
        case .highlight:
            finishTextHighlight(page: page, pageBounds: pageBounds, scaleX: scaleX, scaleY: scaleY)
            
        case .shape:
            if currentRect.width > 5 && currentRect.height > 5 {
                let pdfRect = CGRect(
                    x: currentRect.origin.x * scaleX,
                    y: (viewBounds.height - currentRect.origin.y - currentRect.height) * scaleY,
                    width: currentRect.width * scaleX,
                    height: currentRect.height * scaleY
                )
                
                let annotation = PDFAnnotationService.PDFAnnotation(
                    type: .rectangle,
                    filePath: filePath,
                    pageIndex: pageIndex,
                    bounds: pdfRect,
                    color: PDFAnnotationService.PDFAnnotation.AnnotationColor(nsColor: strokeColor),
                    strokeWidth: strokeWidth,
                    fillColor: isFilled ? PDFAnnotationService.PDFAnnotation.AnnotationColor(nsColor: fillColor ?? strokeColor) : nil,
                    isFilled: isFilled
                )
                
                annotationService?.addAnnotation(annotation)
                loadAnnotations()
            }
            
        case .obfuscate:
            if currentRect.width > 5 && currentRect.height > 5 {
                let pdfRect = CGRect(
                    x: currentRect.origin.x * scaleX,
                    y: (viewBounds.height - currentRect.origin.y - currentRect.height) * scaleY,
                    width: currentRect.width * scaleX,
                    height: currentRect.height * scaleY
                )
                
                let annotation = PDFAnnotationService.PDFAnnotation(
                    type: .obfuscate,
                    filePath: filePath,
                    pageIndex: pageIndex,
                    bounds: pdfRect,
                    color: PDFAnnotationService.PDFAnnotation.AnnotationColor(nsColor: .black),
                    obfuscationIntensity: obfuscationIntensity
                )
                
                annotationService?.addAnnotation(annotation)
                loadAnnotations()
            }
        }
        
        currentRect = .zero
        textSelection = nil
        needsDisplay = true
        
        // Notifica ricaricamento
        NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
    }
    
    // MARK: - Text Selection for Highlight
    
    private func startTextSelection(at location: CGPoint) {
        guard let pdfView = pdfView,
              let document = pdfView.document,
              let page = document.page(at: pageIndex) else { return }
        
        let pageBounds = page.bounds(for: .mediaBox)
        let viewBounds = bounds
        let scaleX = pageBounds.width / viewBounds.width
        let scaleY = pageBounds.height / viewBounds.height
        
        let pdfPoint = CGPoint(
            x: location.x * scaleX,
            y: (viewBounds.height - location.y) * scaleY
        )
        
        // Trova selezione testo alla posizione
        if let selection = page.selection(for: CGRect(origin: pdfPoint, size: CGSize(width: 1, height: 1))) {
            textSelection = selection
        }
    }
    
    private func updateTextSelection(to location: CGPoint) {
        guard let pdfView = pdfView,
              let document = pdfView.document,
              let page = document.page(at: pageIndex) else { return }
        
        let pageBounds = page.bounds(for: .mediaBox)
        let viewBounds = bounds
        let scaleX = pageBounds.width / viewBounds.width
        let scaleY = pageBounds.height / viewBounds.height
        
        let startPDF = CGPoint(
            x: startPoint.x * scaleX,
            y: (viewBounds.height - startPoint.y) * scaleY
        )
        let endPDF = CGPoint(
            x: location.x * scaleX,
            y: (viewBounds.height - location.y) * scaleY
        )
        
        let selectionRect = CGRect(
            x: min(startPDF.x, endPDF.x),
            y: min(startPDF.y, endPDF.y),
            width: abs(endPDF.x - startPDF.x),
            height: abs(endPDF.y - startPDF.y)
        )
        
        textSelection = page.selection(for: selectionRect)
        needsDisplay = true
    }
    
    private func finishTextHighlight(page: PDFPage, pageBounds: CGRect, scaleX: CGFloat, scaleY: CGFloat) {
        guard let selection = textSelection,
              let selectionText = selection.string,
              !selectionText.isEmpty else { return }
        
        let selectionBounds = selection.bounds(for: page)
        
        let annotation = PDFAnnotationService.PDFAnnotation(
            type: .highlight,
            filePath: filePath,
            pageIndex: pageIndex,
            bounds: selectionBounds,
            color: PDFAnnotationService.PDFAnnotation.AnnotationColor(nsColor: strokeColor),
            textSelection: PDFAnnotationService.PDFAnnotation.TextSelection(
                startIndex: 0, // Semplificato
                endIndex: selectionText.count,
                text: selectionText
            )
        )
        
        annotationService?.addAnnotation(annotation)
        loadAnnotations()
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Disegna annotazioni esistenti
        for annotation in annotations {
            drawAnnotation(annotation, in: context)
        }
        
        // Disegna annotazione in corso
        if isDrawing, let mode = annotationMode {
            switch mode {
            case .highlight:
                if let selection = textSelection {
                    drawTextSelection(selection, in: context)
                }
            case .shape:
                drawShape(in: context, rect: currentRect, isFilled: isFilled)
            case .obfuscate:
                drawObfuscate(in: context, rect: currentRect)
            }
        }
    }
    
    private func drawAnnotation(_ annotation: PDFAnnotationService.PDFAnnotation, in context: CGContext) {
        guard let pdfView = pdfView,
              let document = pdfView.document,
              let page = document.page(at: pageIndex) else { return }
        
        let pageBounds = page.bounds(for: .mediaBox)
        let viewBounds = bounds
        let scaleX = viewBounds.width / pageBounds.width
        let scaleY = viewBounds.height / pageBounds.height
        
        let viewRect = CGRect(
            x: annotation.bounds.origin.x * scaleX,
            y: viewBounds.height - (annotation.bounds.origin.y + annotation.bounds.height) * scaleY,
            width: annotation.bounds.width * scaleX,
            height: annotation.bounds.height * scaleY
        )
        
        context.saveGState()
        
        switch annotation.type {
        case .highlight:
            context.setFillColor(annotation.color.nsColor.withAlphaComponent(0.3).cgColor)
            context.fill(viewRect)
            
        case .rectangle:
            context.setStrokeColor(annotation.color.nsColor.cgColor)
            context.setLineWidth(annotation.strokeWidth)
            if annotation.isFilled, let fillColor = annotation.fillColor {
                context.setFillColor(fillColor.nsColor.cgColor)
                context.fill(viewRect)
            }
            context.stroke(viewRect)
            
        case .ellipse:
            context.setStrokeColor(annotation.color.nsColor.cgColor)
            context.setLineWidth(annotation.strokeWidth)
            if annotation.isFilled, let fillColor = annotation.fillColor {
                context.setFillColor(fillColor.nsColor.cgColor)
                context.fillEllipse(in: viewRect)
            }
            context.strokeEllipse(in: viewRect)
            
        case .obfuscate:
            // Per preview, disegna pattern
            context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            context.fill(viewRect)
        }
        
        context.restoreGState()
    }
    
    private func drawTextSelection(_ selection: PDFSelection, in context: CGContext) {
        guard let pdfView = pdfView,
              let document = pdfView.document,
              let page = document.page(at: pageIndex) else { return }
        
        let bounds = selection.bounds(for: page)
        let pageBounds = page.bounds(for: .mediaBox)
        let viewBounds = self.bounds
        let scaleX = viewBounds.width / pageBounds.width
        let scaleY = viewBounds.height / pageBounds.height
        
        let viewRect = CGRect(
            x: bounds.origin.x * scaleX,
            y: viewBounds.height - (bounds.origin.y + bounds.height) * scaleY,
            width: bounds.width * scaleX,
            height: bounds.height * scaleY
        )
        
        context.setFillColor(strokeColor.withAlphaComponent(0.3).cgColor)
        context.fill(viewRect)
    }
    
    private func drawShape(in context: CGContext, rect: CGRect, isFilled: Bool) {
        context.saveGState()
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(strokeWidth)
        
        if isFilled {
            context.setFillColor((fillColor ?? strokeColor).cgColor)
            context.fill(rect)
        }
        
        context.stroke(rect)
        context.restoreGState()
    }
    
    private func drawObfuscate(in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        context.fill(rect)
        context.restoreGState()
    }
}
