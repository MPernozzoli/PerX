import Foundation
import AppKit

// MARK: - TextFitter

/// Algoritmo per adattamento responsive del testo ai box PDF
/// Gestisce word wrap, riduzione font automatica e validazione in tempo reale
class TextFitter {
    
    // MARK: - Types
    
    struct FitResult {
        let text: String
        let fontSize: CGFloat
        let fits: Bool
        let lines: [String]
        let actualHeight: CGFloat
        let actualWidth: CGFloat
    }
    
    struct FitOptions {
        var minFontSize: CGFloat = 6
        var maxFontSize: CGFloat = 24
        var fontName: String = "Helvetica"
        var alignment: NSTextAlignment = .left
        var maxLines: Int? = nil
        var padding: CGFloat = 2
        var lineSpacing: CGFloat = 1.2
        var useBold: Bool = false
        
        static var `default`: FitOptions { FitOptions() }
    }
    
    // MARK: - Singleton
    
    static let shared = TextFitter()
    private init() {}
    
    // MARK: - Main Fit Method
    
    /// Calcola la dimensione font ottimale per far entrare il testo nel box
    /// - Parameters:
    ///   - text: Testo da fittare
    ///   - rect: Rettangolo di destinazione
    ///   - options: Opzioni di fitting
    /// - Returns: Risultato con font size ottimale e flag se il testo fitta
    func fitText(_ text: String, in rect: CGRect, options: FitOptions = .default) -> FitResult {
        guard !text.isEmpty else {
            return FitResult(text: "", fontSize: options.maxFontSize, fits: true, lines: [], actualHeight: 0, actualWidth: 0)
        }
        
        let availableWidth = rect.width - (options.padding * 2)
        let availableHeight = rect.height - (options.padding * 2)
        
        // Binary search per trovare font size ottimale
        var low = options.minFontSize
        var high = options.maxFontSize
        var bestResult: FitResult?
        
        while high - low > 0.5 {
            let mid = (low + high) / 2
            let result = measureText(text, fontSize: mid, width: availableWidth, options: options)
            
            let fits = result.actualHeight <= availableHeight &&
                       (options.maxLines == nil || result.lines.count <= options.maxLines!)
            
            if fits {
                bestResult = FitResult(
                    text: text,
                    fontSize: mid,
                    fits: true,
                    lines: result.lines,
                    actualHeight: result.actualHeight,
                    actualWidth: result.actualWidth
                )
                low = mid
            } else {
                high = mid
            }
        }
        
        // Se non abbiamo trovato un risultato valido, usa il font minimo
        if bestResult == nil {
            let result = measureText(text, fontSize: options.minFontSize, width: availableWidth, options: options)
            let fits = result.actualHeight <= availableHeight
            bestResult = FitResult(
                text: text,
                fontSize: options.minFontSize,
                fits: fits,
                lines: result.lines,
                actualHeight: result.actualHeight,
                actualWidth: result.actualWidth
            )
        }
        
        return bestResult!
    }
    
    /// Verifica rapidamente se il testo fitta nel box con un font specifico
    func textFits(_ text: String, in rect: CGRect, fontSize: CGFloat, options: FitOptions = .default) -> Bool {
        let availableWidth = rect.width - (options.padding * 2)
        let availableHeight = rect.height - (options.padding * 2)
        
        let result = measureText(text, fontSize: fontSize, width: availableWidth, options: options)
        
        let heightFits = result.actualHeight <= availableHeight
        let linesFit = options.maxLines == nil || result.lines.count <= options.maxLines!
        
        return heightFits && linesFit
    }
    
    // MARK: - Text Measurement
    
    private struct MeasureResult {
        let lines: [String]
        let actualHeight: CGFloat
        let actualWidth: CGFloat
    }
    
    /// Ottiene il font appropriato in base alle opzioni (normale o bold)
    private func getFont(size: CGFloat, options: FitOptions) -> NSFont {
        if options.useBold {
            // Prova font bold
            let boldFontName = options.fontName + "-Bold"
            if let boldFont = NSFont(name: boldFontName, size: size) {
                return boldFont
            }
            // Fallback a system bold
            return NSFont.boldSystemFont(ofSize: size)
        }
        return NSFont(name: options.fontName, size: size) ?? NSFont.systemFont(ofSize: size)
    }
    
    private func measureText(_ text: String, fontSize: CGFloat, width: CGFloat, options: FitOptions) -> MeasureResult {
        let font = getFont(size: fontSize, options: options)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = options.alignment
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = (fontSize * options.lineSpacing) - fontSize
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        
        // Word wrap manuale per maggior controllo
        let lines = wrapText(text, width: width, attributes: attributes)
        
        // Calcola altezza totale
        let lineHeight = fontSize * options.lineSpacing
        let totalHeight = CGFloat(lines.count) * lineHeight
        
        // Calcola larghezza massima
        var maxWidth: CGFloat = 0
        for line in lines {
            let lineWidth = (line as NSString).size(withAttributes: attributes).width
            maxWidth = max(maxWidth, lineWidth)
        }
        
        return MeasureResult(lines: lines, actualHeight: totalHeight, actualWidth: maxWidth)
    }
    
    private func wrapText(_ text: String, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> [String] {
        var lines: [String] = []
        let paragraphs = text.components(separatedBy: "\n")
        
        for paragraph in paragraphs {
            if paragraph.isEmpty {
                lines.append("")
                continue
            }
            
            let words = paragraph.components(separatedBy: " ")
            var currentLine = ""
            
            for word in words {
                let testLine = currentLine.isEmpty ? word : currentLine + " " + word
                let testWidth = (testLine as NSString).size(withAttributes: attributes).width
                
                if testWidth <= width {
                    currentLine = testLine
                } else {
                    if !currentLine.isEmpty {
                        lines.append(currentLine)
                    }
                    // Se la parola singola è troppo lunga, spezzala
                    if (word as NSString).size(withAttributes: attributes).width > width {
                        let brokenLines = breakWord(word, width: width, attributes: attributes)
                        lines.append(contentsOf: brokenLines.dropLast())
                        currentLine = brokenLines.last ?? ""
                    } else {
                        currentLine = word
                    }
                }
            }
            
            if !currentLine.isEmpty {
                lines.append(currentLine)
            }
        }
        
        return lines
    }
    
    private func breakWord(_ word: String, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> [String] {
        var lines: [String] = []
        var currentPart = ""
        
        for char in word {
            let testPart = currentPart + String(char)
            let testWidth = (testPart as NSString).size(withAttributes: attributes).width
            
            if testWidth <= width {
                currentPart = testPart
            } else {
                if !currentPart.isEmpty {
                    lines.append(currentPart)
                }
                currentPart = String(char)
            }
        }
        
        if !currentPart.isEmpty {
            lines.append(currentPart)
        }
        
        return lines
    }
    
    // MARK: - Rendering
    
    /// Genera NSAttributedString formattata per il rendering
    func attributedString(for text: String, fontSize: CGFloat, options: FitOptions = .default) -> NSAttributedString {
        let font = getFont(size: fontSize, options: options)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = options.alignment
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = (fontSize * options.lineSpacing) - fontSize
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ]
        
        return NSAttributedString(string: text, attributes: attributes)
    }
    
    /// Disegna il testo nel contesto grafico specificato
    func drawText(_ text: String, in rect: CGRect, context: CGContext, options: FitOptions = .default) {
        let fitResult = fitText(text, in: rect, options: options)
        
        guard fitResult.fits else { return }
        
        let attrString = attributedString(for: text, fontSize: fitResult.fontSize, options: options)
        
        // Salva stato contesto
        context.saveGState()
        
        // Imposta clipping rect per sicurezza
        let paddedRect = rect.insetBy(dx: options.padding, dy: options.padding)
        context.clip(to: paddedRect)
        
        // Disegna con NSAttributedString
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        
        // Calcola posizione Y (dal basso verso l'alto in PDF)
        let font = getFont(size: fitResult.fontSize, options: options)
        let lineHeight = fitResult.fontSize * options.lineSpacing
        
        var yOffset = paddedRect.maxY - lineHeight
        
        for line in fitResult.lines {
            let lineAttr = NSAttributedString(string: line, attributes: [
                .font: font,
                .foregroundColor: NSColor.black
            ])
            
            var xOffset: CGFloat = paddedRect.minX
            let lineWidth = lineAttr.size().width
            
            switch options.alignment {
            case .center:
                xOffset = paddedRect.minX + (paddedRect.width - lineWidth) / 2
            case .right:
                xOffset = paddedRect.maxX - lineWidth
            default:
                break
            }
            
            lineAttr.draw(at: NSPoint(x: xOffset, y: yOffset))
            yOffset -= lineHeight
        }
        
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }
    
    // MARK: - Validation
    
    /// Valida se il testo può entrare nel box - utile per feedback UI in tempo reale
    func validate(_ text: String, in rect: CGRect, options: FitOptions = .default) -> ValidationResult {
        let result = fitText(text, in: rect, options: options)
        
        if result.fits {
            return ValidationResult(isValid: true, message: nil, suggestedFontSize: result.fontSize)
        } else {
            let overflow = result.actualHeight - (rect.height - options.padding * 2)
            return ValidationResult(
                isValid: false,
                message: "Testo troppo lungo (overflow: \(Int(overflow))pt)",
                suggestedFontSize: options.minFontSize
            )
        }
    }
    
    struct ValidationResult {
        let isValid: Bool
        let message: String?
        let suggestedFontSize: CGFloat
    }
}

// MARK: - Currency Formatter

extension TextFitter {
    
    /// Converte un numero in lettere (italiano)
    static func numeroInLettere(_ numero: Decimal) -> String {
        let intPart = NSDecimalNumber(decimal: numero).intValue
        let decPart = Int(((numero as NSDecimalNumber).doubleValue - Double(intPart)) * 100)
        
        var result = inLettere(intPart)
        
        if decPart > 0 {
            result += "/" + String(format: "%02d", decPart)
        } else {
            result += "/00"
        }
        
        return result
    }
    
    private static func inLettere(_ n: Int) -> String {
        if n == 0 { return "zero" }
        if n < 0 { return "meno " + inLettere(-n) }
        
        let unita = ["", "uno", "due", "tre", "quattro", "cinque", "sei", "sette", "otto", "nove",
                     "dieci", "undici", "dodici", "tredici", "quattordici", "quindici", "sedici",
                     "diciassette", "diciotto", "diciannove"]
        
        let decine = ["", "", "venti", "trenta", "quaranta", "cinquanta", "sessanta", "settanta", "ottanta", "novanta"]
        
        if n < 20 {
            return unita[n]
        }
        
        if n < 100 {
            let d = n / 10
            let u = n % 10
            var result = decine[d]
            if u == 1 || u == 8 {
                result = String(result.dropLast())
            }
            return result + unita[u]
        }
        
        if n < 1000 {
            let c = n / 100
            let resto = n % 100
            var result = c == 1 ? "cento" : unita[c] + "cento"
            if resto > 0 {
                if resto >= 80 {
                    result = String(result.dropLast())
                }
                result += inLettere(resto)
            }
            return result
        }
        
        if n < 1_000_000 {
            let m = n / 1000
            let resto = n % 1000
            var result = m == 1 ? "mille" : inLettere(m) + "mila"
            if resto > 0 {
                result += inLettere(resto)
            }
            return result
        }
        
        if n < 1_000_000_000 {
            let mil = n / 1_000_000
            let resto = n % 1_000_000
            var result = mil == 1 ? "unmilione" : inLettere(mil) + "milioni"
            if resto > 0 {
                result += inLettere(resto)
            }
            return result
        }
        
        return String(n)
    }
    
    /// Formatta importo in euro
    static func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "€"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: amount as NSDecimalNumber) ?? "€ 0,00"
    }
}

// MARK: - IBAN Utilities

extension TextFitter {
    
    /// Valida formato IBAN italiano
    static func validateIBAN(_ iban: String) -> Bool {
        let cleaned = iban.replacingOccurrences(of: " ", with: "").uppercased()
        
        guard cleaned.count == 27 else { return false }
        guard cleaned.hasPrefix("IT") else { return false }
        
        let pattern = "^IT[0-9]{2}[A-Z][0-9]{10}[A-Z0-9]{12}$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        
        return regex?.firstMatch(in: cleaned, range: range) != nil
    }
    
    /// Splitta IBAN in array di 27 caratteri
    static func splitIBAN(_ iban: String) -> [String] {
        let cleaned = iban.replacingOccurrences(of: " ", with: "").uppercased()
        var chars = Array(cleaned).map { String($0) }
        
        // Pad a 27 caratteri se necessario
        while chars.count < 27 {
            chars.append("")
        }
        
        return Array(chars.prefix(27))
    }
    
    /// Formatta IBAN con spazi
    static func formatIBAN(_ iban: String) -> String {
        let cleaned = iban.replacingOccurrences(of: " ", with: "").uppercased()
        var result = ""
        for (index, char) in cleaned.enumerated() {
            if index > 0 && index % 4 == 0 {
                result += " "
            }
            result.append(char)
        }
        return result
    }
}

// MARK: - Date Utilities

extension TextFitter {
    
    /// Splitta data in componenti giorno/mese/anno
    static func splitDate(_ date: Date) -> (giorno: String, mese: String, anno: String) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .month, .year], from: date)
        
        let giorno = String(format: "%02d", components.day ?? 1)
        let mese = String(format: "%02d", components.month ?? 1)
        let anno = String(components.year ?? 2024)
        
        return (giorno, mese, anno)
    }
    
    /// Formatta data in italiano
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: date)
    }
}

// MARK: - Checkbox Rendering

extension TextFitter {
    
    /// Caratteri per checkbox - solo spunta, il box è nel PDF sottostante
    static let checkboxChecked = "✓"
    static let checkboxUnchecked = "" // Vuoto se non spuntato
    
    /// Disegna checkbox nel contesto (solo spunta, senza box)
    static func drawCheckbox(checked: Bool, in rect: CGRect, context: CGContext) {
        guard checked else { return } // Non disegna nulla se non spuntato
        
        let symbol = checkboxChecked
        
        // Usa font bold per la spunta
        let font = NSFont.boldSystemFont(ofSize: min(rect.width, rect.height) * 0.85)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        
        let attrString = NSAttributedString(string: symbol, attributes: attributes)
        let size = attrString.size()
        
        let x = rect.minX + (rect.width - size.width) / 2
        let y = rect.minY + (rect.height - size.height) / 2
        
        context.saveGState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        
        attrString.draw(at: NSPoint(x: x, y: y))
        
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }
}
