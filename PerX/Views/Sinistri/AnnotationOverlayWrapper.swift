import SwiftUI
import PDFKit

// MARK: - Annotation Overlay Wrapper

/// Wrapper SwiftUI per gestire annotazioni PDF senza accesso diretto al PDFView
struct AnnotationOverlayWrapper: View {
    let filePath: String
    let pageIndex: Int
    let annotationMode: AnnotationMode?
    
    @Binding var strokeColor: Color
    @Binding var fillColor: Color?
    @Binding var strokeWidth: CGFloat
    @Binding var isFilled: Bool
    @Binding var obfuscationIntensity: CGFloat
    
    @StateObject private var annotationService = PDFAnnotationService.shared
    @State private var annotations: [PDFAnnotationService.PDFAnnotation] = []
    @State private var isDrawing = false
    @State private var startPoint: CGPoint = .zero
    @State private var currentRect: CGRect = .zero
    @State private var textSelection: PDFSelection?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Overlay trasparente per intercettare gesti
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleDrag(value: value, in: geometry.size)
                            }
                            .onEnded { _ in
                                handleDragEnd(in: geometry.size)
                            }
                    )
                
                // Disegna annotazioni esistenti
                ForEach(annotations) { annotation in
                    AnnotationShape(annotation: annotation, geometry: geometry)
                }
                
                // Disegna annotazione in corso
                if isDrawing {
                    DrawingShape(
                        mode: annotationMode,
                        rect: currentRect,
                        strokeColor: strokeColor,
                        fillColor: fillColor,
                        strokeWidth: strokeWidth,
                        isFilled: isFilled
                    )
                }
            }
        }
        .onAppear {
            loadAnnotations()
        }
        .onChange(of: pageIndex) { _ in
            loadAnnotations()
        }
        .onChange(of: filePath) { _ in
            loadAnnotations()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PDFAnnotationAdded"))) { _ in
            loadAnnotations()
        }
    }
    
    private func loadAnnotations() {
        annotations = annotationService.getAnnotations(for: filePath, pageIndex: pageIndex)
    }
    
    private func handleDrag(value: DragGesture.Value, in size: CGSize) {
        guard let mode = annotationMode else { return }
        
        if !isDrawing {
            isDrawing = true
            startPoint = value.location
            currentRect = .zero
        }
        
        switch mode {
        case .highlight:
            // Per evidenziazione, seleziona testo
            updateTextSelection(from: startPoint, to: value.location, in: size)
        case .shape, .obfuscate:
            currentRect = CGRect(
                x: min(startPoint.x, value.location.x),
                y: min(startPoint.y, value.location.y),
                width: abs(value.location.x - startPoint.x),
                height: abs(value.location.y - startPoint.y)
            )
        }
    }
    
    private func handleDragEnd(in size: CGSize) {
        guard isDrawing, let mode = annotationMode else { return }
        isDrawing = false
        
        guard let document = PDFDocument(url: URL(fileURLWithPath: filePath)),
              let page = document.page(at: pageIndex) else {
            currentRect = .zero
            return
        }
        
        let pageBounds = page.bounds(for: .mediaBox)
        let scaleX = pageBounds.width / size.width
        let scaleY = pageBounds.height / size.height
        
        switch mode {
        case .highlight:
            if let selection = textSelection, let selectionText = selection.string, !selectionText.isEmpty {
                let bounds = selection.bounds(for: page)
                let annotation = PDFAnnotationService.PDFAnnotation(
                    type: .highlight,
                    filePath: filePath,
                    pageIndex: pageIndex,
                    bounds: bounds,
                    color: PDFAnnotationService.PDFAnnotation.AnnotationColor(nsColor: NSColor(strokeColor)),
                    textSelection: PDFAnnotationService.PDFAnnotation.TextSelection(
                        startIndex: 0,
                        endIndex: selectionText.count,
                        text: selectionText
                    )
                )
                annotationService.addAnnotation(annotation)
            }
            
        case .shape:
            if currentRect.width > 5 && currentRect.height > 5 {
                let pdfRect = CGRect(
                    x: currentRect.origin.x * scaleX,
                    y: (size.height - currentRect.origin.y - currentRect.height) * scaleY,
                    width: currentRect.width * scaleX,
                    height: currentRect.height * scaleY
                )
                
                let annotation = PDFAnnotationService.PDFAnnotation(
                    type: .rectangle,
                    filePath: filePath,
                    pageIndex: pageIndex,
                    bounds: pdfRect,
                    color: PDFAnnotationService.PDFAnnotation.AnnotationColor(nsColor: NSColor(strokeColor)),
                    strokeWidth: strokeWidth,
                    fillColor: isFilled ? PDFAnnotationService.PDFAnnotation.AnnotationColor(nsColor: NSColor(fillColor ?? strokeColor)) : nil,
                    isFilled: isFilled
                )
                
                annotationService.addAnnotation(annotation)
            }
            
        case .obfuscate:
            if currentRect.width > 5 && currentRect.height > 5 {
                let pdfRect = CGRect(
                    x: currentRect.origin.x * scaleX,
                    y: (size.height - currentRect.origin.y - currentRect.height) * scaleY,
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
                
                annotationService.addAnnotation(annotation)
            }
        }
        
        currentRect = .zero
        textSelection = nil
        loadAnnotations()
        
        NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
    }
    
    private func updateTextSelection(from start: CGPoint, to end: CGPoint, in size: CGSize) {
        guard let document = PDFDocument(url: URL(fileURLWithPath: filePath)),
              let page = document.page(at: pageIndex) else { return }
        
        let pageBounds = page.bounds(for: .mediaBox)
        let scaleX = pageBounds.width / size.width
        let scaleY = pageBounds.height / size.height
        
        let startPDF = CGPoint(
            x: start.x * scaleX,
            y: (size.height - start.y) * scaleY
        )
        let endPDF = CGPoint(
            x: end.x * scaleX,
            y: (size.height - end.y) * scaleY
        )
        
        let selectionRect = CGRect(
            x: min(startPDF.x, endPDF.x),
            y: min(startPDF.y, endPDF.y),
            width: abs(endPDF.x - startPDF.x),
            height: abs(endPDF.y - startPDF.y)
        )
        
        textSelection = page.selection(for: selectionRect)
    }
}

// MARK: - Annotation Shape

struct AnnotationShape: View {
    let annotation: PDFAnnotationService.PDFAnnotation
    let geometry: GeometryProxy
    
    var body: some View {
        let pageBounds = getPageBounds()
        let scaleX = geometry.size.width / pageBounds.width
        let scaleY = geometry.size.height / pageBounds.height
        
        let viewRect = CGRect(
            x: annotation.bounds.origin.x * scaleX,
            y: geometry.size.height - (annotation.bounds.origin.y + annotation.bounds.height) * scaleY,
            width: annotation.bounds.width * scaleX,
            height: annotation.bounds.height * scaleY
        )
        
        Group {
            switch annotation.type {
            case .highlight:
                Rectangle()
                    .fill(Color(annotation.color.nsColor).opacity(0.3))
                    .frame(width: viewRect.width, height: viewRect.height)
                    .position(x: viewRect.midX, y: viewRect.midY)
                    
            case .rectangle:
                Rectangle()
                    .stroke(Color(annotation.color.nsColor), lineWidth: annotation.strokeWidth)
                    .background(
                        annotation.isFilled ?
                        Rectangle().fill(Color(annotation.fillColor?.nsColor ?? annotation.color.nsColor)) :
                        nil
                    )
                    .frame(width: viewRect.width, height: viewRect.height)
                    .position(x: viewRect.midX, y: viewRect.midY)
                    
            case .ellipse:
                Ellipse()
                    .stroke(Color(annotation.color.nsColor), lineWidth: annotation.strokeWidth)
                    .background(
                        annotation.isFilled ?
                        Ellipse().fill(Color(annotation.fillColor?.nsColor ?? annotation.color.nsColor)) :
                        nil
                    )
                    .frame(width: viewRect.width, height: viewRect.height)
                    .position(x: viewRect.midX, y: viewRect.midY)
                    
            case .obfuscate:
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: viewRect.width, height: viewRect.height)
                    .position(x: viewRect.midX, y: viewRect.midY)
            }
        }
    }
    
    private func getPageBounds() -> CGRect {
        guard let document = PDFDocument(url: URL(fileURLWithPath: annotation.filePath)),
              let page = document.page(at: annotation.pageIndex) else {
            return CGRect(x: 0, y: 0, width: 612, height: 792) // Default A4
        }
        return page.bounds(for: .mediaBox)
    }
}

// MARK: - Drawing Shape

struct DrawingShape: View {
    let mode: AnnotationMode?
    let rect: CGRect
    let strokeColor: Color
    let fillColor: Color?
    let strokeWidth: CGFloat
    let isFilled: Bool
    
    var body: some View {
        if rect.width > 0 && rect.height > 0 {
            Group {
                switch mode {
                case .highlight:
                    Rectangle()
                        .fill(strokeColor.opacity(0.3))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        
                case .shape:
                    Rectangle()
                        .stroke(strokeColor, lineWidth: strokeWidth)
                        .background(
                            isFilled ?
                            Rectangle().fill(fillColor ?? strokeColor) :
                            nil
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        
                case .obfuscate:
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        
                case .none:
                    EmptyView()
                }
            }
        }
    }
}
