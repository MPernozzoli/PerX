import Foundation
import PDFKit
import AppKit

/// Genera un PDF riassuntivo delle comunicazioni completate prima della revoca
class RevocationPDFService {
    static let shared = RevocationPDFService()
    private init() {}
    
    /// Crea il PDF e lo salva nella cartella "azioni compiute finora" del sinistro
    /// - Returns: URL del PDF generato, se riuscito
    func generateSummary(for sinistro: Sinistro, communications: [DiarioEntry]) -> URL? {
        guard let riferimento = sinistro.riferimento,
              let sinistroPath = FileService.shared.getSinistroPath(riferimento: riferimento) else {
            return nil
        }
        
        let folderPath = (sinistroPath as NSString).appendingPathComponent("azioni compiute finora")
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: folderPath) {
            do {
                try fileManager.createDirectory(atPath: folderPath, withIntermediateDirectories: true)
            } catch {
                print("[RevocationPDF] ❌ Errore creazione cartella: \(error)")
                return nil
            }
        }
        
        let fileName = "Riassunto automatico sinistro \(riferimento) revocato.pdf"
        let fileURL = URL(fileURLWithPath: (folderPath as NSString).appendingPathComponent(fileName))
        
        let ordered = communications.sorted { $0.timestamp < $1.timestamp }
        let assicurato = sinistro.nomeAssicurato ?? sinistro.nomeContraente ?? sinistro.nomeDanneggiato
        
        guard createPDF(at: fileURL, riferimento: riferimento, assicurato: assicurato, communications: ordered) else {
            return nil
        }
        
        return fileURL
    }
    
    // MARK: - PDF Creation
    
    private func createPDF(
        at url: URL,
        riferimento: String,
        assicurato: String?,
        communications: [DiarioEntry]
    ) -> Bool {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return false }
        var mediaBox = pageRect
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return false }
        
        var cursorY = pageRect.height - 40
        context.beginPDFPage(nil)
        cursorY = drawHeader(in: context, pageRect: pageRect, cursorY: cursorY, riferimento: riferimento, assicurato: assicurato)
        
        for entry in communications {
            let blockHeight = estimateHeight(for: entry, pageWidth: pageRect.width - 80)
            if cursorY - blockHeight < 80 {
                drawFooter(in: context, pageRect: pageRect)
                context.endPDFPage()
                context.beginPDFPage(nil)
                cursorY = pageRect.height - 40
                cursorY = drawHeader(in: context, pageRect: pageRect, cursorY: cursorY, riferimento: riferimento, assicurato: assicurato)
            }
            cursorY = draw(entry: entry, in: context, pageRect: pageRect, cursorY: cursorY)
        }
        
        drawFooter(in: context, pageRect: pageRect)
        context.endPDFPage()
        context.closePDF()
        
        do {
            try pdfData.write(to: url, options: .atomic)
            return true
        } catch {
            print("[RevocationPDF] ❌ Errore scrittura PDF: \(error)")
            return false
        }
    }
    
    // MARK: - Drawing helpers
    
    private func drawHeader(in context: CGContext, pageRect: CGRect, cursorY: CGFloat, riferimento: String, assicurato: String?) -> CGFloat {
        var y = cursorY
        let title = "Riassunto automatico per il sinistro \(riferimento) revocato"
        y = draw(text: title, at: CGPoint(x: 40, y: y), maxWidth: pageRect.width - 80, font: .boldSystemFont(ofSize: 16), context: context)
        if let assicurato = assicurato, !assicurato.isEmpty {
            y = draw(text: "Assicurato: \(assicurato)", at: CGPoint(x: 40, y: y - 4), maxWidth: pageRect.width - 80, font: .systemFont(ofSize: 12), context: context)
        }
        y -= 12
        let linePath = CGMutablePath()
        linePath.move(to: CGPoint(x: 40, y: y))
        linePath.addLine(to: CGPoint(x: pageRect.width - 40, y: y))
        context.addPath(linePath)
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.setLineWidth(0.5)
        context.strokePath()
        return y - 16
    }
    
    private func drawFooter(in context: CGContext, pageRect: CGRect) {
        let footerText = "Generato automaticamente con PerX"
        let y: CGFloat = 40
        _ = draw(text: footerText, at: CGPoint(x: 40, y: y), maxWidth: pageRect.width - 120, font: .systemFont(ofSize: 10), context: context)
        
        if let logo = loadLogo() {
            let logoSize = CGSize(width: 60, height: 60)
            let logoOrigin = CGPoint(x: pageRect.width - logoSize.width - 40, y: y - 8)
            draw(image: logo, in: CGRect(origin: logoOrigin, size: logoSize), context: context)
        }
    }
    
    private func draw(entry: DiarioEntry, in context: CGContext, pageRect: CGRect, cursorY: CGFloat) -> CGFloat {
        var y = cursorY
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        let header = "\(dateFormatter.string(from: entry.timestamp)) · \(entry.tipo.rawValue)"
        y = draw(text: header, at: CGPoint(x: 40, y: y), maxWidth: pageRect.width - 80, font: .boldSystemFont(ofSize: 12), context: context)
        
        if let titolo = entry.titolo ?? entry.riassunto {
            y = draw(text: titolo, at: CGPoint(x: 40, y: y - 2), maxWidth: pageRect.width - 80, font: .systemFont(ofSize: 12), context: context)
        }
        
        let body = entry.contenutoCompleto ?? entry.testo
        y = draw(text: body, at: CGPoint(x: 40, y: y - 4), maxWidth: pageRect.width - 80, font: .systemFont(ofSize: 11), context: context)
        
        return y - 14
    }
    
    private func draw(text: String, at point: CGPoint, maxWidth: CGFloat, font: NSFont, context: CGContext) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let bounding = attributed.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        let drawRect = CGRect(x: point.x, y: point.y - bounding.height, width: maxWidth, height: bounding.height)
        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        
        return point.y - bounding.height - 6
    }
    
    private func draw(image: NSImage, in rect: CGRect, context: CGContext) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        context.saveGState()
        context.translateBy(x: 0, y: rect.origin.y * 2 + rect.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(cgImage, in: rect)
        context.restoreGState()
    }
    
    private func estimateHeight(for entry: DiarioEntry, pageWidth: CGFloat) -> CGFloat {
        let dateFont = NSFont.boldSystemFont(ofSize: 12)
        let bodyFont = NSFont.systemFont(ofSize: 11)
        let titleFont = NSFont.systemFont(ofSize: 12)
        
        let dateText: NSString = "Date"
        let dateHeight = dateText.boundingRect(with: CGSize(width: pageWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: [.font: dateFont]).height
        
        var total: CGFloat = dateHeight + 10
        if let titolo = entry.titolo ?? entry.riassunto {
            let h = (titolo as NSString).boundingRect(with: CGSize(width: pageWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: [.font: titleFont]).height
            total += h + 4
        }
        
        let body = entry.contenutoCompleto ?? entry.testo
        let bodyHeight = (body as NSString).boundingRect(with: CGSize(width: pageWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: [.font: bodyFont]).height
        total += bodyHeight + 14
        
        return total
    }
    
    private func loadLogo() -> NSImage? {
        if let img = NSImage(named: "AppIcon") {
            return img
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "png") {
            return NSImage(contentsOfFile: path)
        }
        return nil
    }
}

