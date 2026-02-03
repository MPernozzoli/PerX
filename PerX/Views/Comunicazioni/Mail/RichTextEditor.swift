import SwiftUI
import AppKit

struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var htmlString: String
    let isHTML: Bool
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.isAutomaticDataDetectionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        
        // Imposta il layout
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        context.coordinator.textView = textView
        textView.delegate = context.coordinator
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        // Assicurati che il delegate sia sempre impostato
        if textView.delegate !== context.coordinator {
            textView.delegate = context.coordinator
            context.coordinator.textView = textView
        }
        
        if isHTML {
            // Se è HTML, converti in NSAttributedString
            if let htmlData = htmlString.data(using: .utf8),
               let attributed = try? NSAttributedString(
                   data: htmlData,
                   options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                   documentAttributes: nil
               ) {
                if textView.attributedString() != attributed {
                    textView.textStorage?.setAttributedString(attributed)
                }
            }
        } else {
            // Testo semplice
            if textView.attributedString() != attributedText {
                textView.textStorage?.setAttributedString(attributedText)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?
        
        init(_ parent: RichTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            
            if parent.isHTML {
                // Converti NSAttributedString in HTML
                let html = textView.attributedString().toHTML()
                parent.htmlString = html
            } else {
                parent.attributedText = textView.attributedString()
            }
        }
    }
}

extension NSAttributedString {
    func toHTML() -> String {
        let documentAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html
        ]
        
        do {
            let htmlData = try self.data(from: NSRange(location: 0, length: self.length), documentAttributes: documentAttributes)
            return String(data: htmlData, encoding: .utf8) ?? ""
        } catch {
            return self.string
        }
    }
}

