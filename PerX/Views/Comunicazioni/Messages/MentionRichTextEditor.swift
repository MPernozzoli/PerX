import SwiftUI
import AppKit

/// Editor testo con evidenziazione @ / # e hover token
struct MentionRichTextEditor: NSViewRepresentable {
    struct HoverToken: Equatable, Identifiable {
        enum Kind: Equatable {
            case mention(value: String)
            case hashtag(tag: String)
        }
        let kind: Kind
        let displayText: String
        
        var id: String {
            switch kind {
            case .mention(let value): return "m:\(value)|\(displayText)"
            case .hashtag(let tag): return "h:\(tag)|\(displayText)"
            }
        }
    }
    
    @Binding var text: String
    @Binding var isFocused: Bool
    var focusTrigger: Int = 0
    var fontSize: CGFloat = 13
    var onTextChange: ((String) -> Void)? = nil
    var onSubmit: (() -> Void)? = nil
    var onEmptySubmit: (() -> Void)? = nil
    var onHoverTokenChange: ((HoverToken?) -> Void)? = nil
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        
        let textView = HoverTextView()
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.string = text
        
        context.coordinator.textView = textView
        textView.onHoverIndex = { idx in
            context.coordinator.handleHover(index: idx)
        }
        
        scrollView.documentView = textView
        
        // Applica evidenziazione iniziale
        context.coordinator.applyHighlighting()
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        
        if textView.string != text {
            textView.string = text
            context.coordinator.applyHighlighting()
        }
        
        // Focus request
        if context.coordinator.lastFocusTrigger != focusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            if let window = textView.window {
                window.makeFirstResponder(textView)
            }
            // caret at end
            let end = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
        }
    }
    
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: MentionRichTextEditor
        weak var textView: HoverTextView?
        var lastFocusTrigger: Int = 0
        
        // token ranges in current text
        private var tokenRanges: [(range: NSRange, token: HoverToken)] = []
        private var lastHoverToken: HoverToken?
        
        init(_ parent: MentionRichTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            parent.onTextChange?(textView.string)
            applyHighlighting()
        }
        
        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }
        
        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Enter: invia se c'è testo; Shift+Enter: a capo
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) {
                    return false // inserisce newline
                }
                
                let trimmed = parent.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    parent.onSubmit?()
                } else {
                    parent.onEmptySubmit?()
                }
                return true
            }
            return false
        }
        
        func applyHighlighting() {
            guard let textView else { return }
            
            let s = textView.string
            let font = NSFont.systemFont(ofSize: parent.fontSize)
            let baseColor = NSColor.labelColor
            
            let attributed = NSMutableAttributedString(string: s, attributes: [
                .font: font,
                .foregroundColor: baseColor
            ])
            
            tokenRanges = []
            
            // Mentions: @token (no spaces)
            if let rx = try? NSRegularExpression(pattern: #"@([A-Za-z0-9._%+\-@/:\-]+)"#, options: []) {
                for m in rx.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                    guard m.range.location != NSNotFound, m.range.length > 1 else { continue }
                    if let valueRange = Range(m.range(at: 1), in: s) {
                        let value = String(s[valueRange])
                        let display = (s as NSString).substring(with: m.range)
                        let token = HoverToken(kind: .mention(value: value), displayText: display)
                        tokenRanges.append((m.range, token))
                    }
                    
                    attributed.addAttributes([
                        .foregroundColor: NSColor.systemBlue,
                        .font: NSFont.boldSystemFont(ofSize: parent.fontSize)
                    ], range: m.range)
                }
            }
            
            // Hashtags: #tag
            if let rx = try? NSRegularExpression(pattern: #"#(\w+)"#, options: []) {
                for m in rx.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                    guard m.range.location != NSNotFound, m.range.length > 1 else { continue }
                    if let tagRange = Range(m.range(at: 1), in: s) {
                        let tag = String(s[tagRange]).lowercased()
                        let display = (s as NSString).substring(with: m.range)
                        let token = HoverToken(kind: .hashtag(tag: tag), displayText: display)
                        tokenRanges.append((m.range, token))
                    }
                    
                    attributed.addAttributes([
                        .foregroundColor: NSColor.systemPurple,
                        .font: NSFont.boldSystemFont(ofSize: parent.fontSize)
                    ], range: m.range)
                }
            }
            
            let selected = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributed)
            textView.setSelectedRange(selected)
        }
        
        func handleHover(index: Int?) {
            guard let idx = index else {
                if lastHoverToken != nil {
                    lastHoverToken = nil
                    parent.onHoverTokenChange?(nil)
                }
                return
            }
            
            let nsIdx = idx
            let token = tokenRanges.first(where: { NSLocationInRange(nsIdx, $0.range) })?.token
            
            if token != lastHoverToken {
                lastHoverToken = token
                parent.onHoverTokenChange?(token)
            }
        }
    }
}

// MARK: - HoverTextView

class HoverTextView: NSTextView {
    var onHoverIndex: ((Int?) -> Void)?
    
    private var tracking: NSTrackingArea?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let tracking {
            removeTrackingArea(tracking)
        }
        
        let options: NSTrackingArea.Options = [
            .activeInActiveApp,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        tracking = trackingArea
    }
    
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onHoverIndex?(characterIndex(at: event))
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverIndex?(nil)
    }
    
    private func characterIndex(at event: NSEvent) -> Int? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let pointInView = convert(event.locationInWindow, from: nil)
        let pointInText = NSPoint(x: pointInView.x - textContainerInset.width,
                                  y: pointInView.y - textContainerInset.height)
        let glyphIndex = lm.glyphIndex(for: pointInText, in: tc)
        let charIndex = lm.characterIndexForGlyph(at: glyphIndex)
        if charIndex >= 0 && charIndex <= string.count {
            return charIndex
        }
        return nil
    }
}

