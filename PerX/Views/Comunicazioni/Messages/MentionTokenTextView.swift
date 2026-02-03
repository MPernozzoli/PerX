import SwiftUI
import AppKit

/// Testo read-only con evidenziazione @/# e hover token (per i messaggi)
struct MentionTokenTextView: NSViewRepresentable {
    typealias HoverToken = MentionRichTextEditor.HoverToken
    
    let text: String
    var fontSize: CGFloat = 13
    var baseColor: NSColor = .labelColor
    var mentionColor: NSColor = .systemBlue
    var hashtagColor: NSColor = .systemPurple
    var onHoverTokenChange: ((HoverToken?) -> Void)? = nil
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> IntrinsicHoverTextView {
        let tv = IntrinsicHoverTextView()
        tv.isRichText = false
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 0, height: 0)
        tv.textContainer?.lineFragmentPadding = 0
        tv.font = NSFont.systemFont(ofSize: fontSize)
        tv.string = text
        
        context.coordinator.textView = tv
        tv.onHoverIndex = { idx in
            context.coordinator.handleHover(index: idx)
        }
        
        context.coordinator.applyHighlighting()
        return tv
    }
    
    func updateNSView(_ nsView: IntrinsicHoverTextView, context: Context) {
        if nsView.string != text {
            nsView.string = text
            context.coordinator.textView = nsView
            context.coordinator.applyHighlighting()
        }
    }
    
    final class Coordinator {
        private let parent: MentionTokenTextView
        weak var textView: IntrinsicHoverTextView?
        
        private var tokenRanges: [(range: NSRange, token: HoverToken)] = []
        private var lastHoverToken: HoverToken?
        
        init(_ parent: MentionTokenTextView) {
            self.parent = parent
        }
        
        func applyHighlighting() {
            guard let textView else { return }
            let s = textView.string
            let font = NSFont.systemFont(ofSize: parent.fontSize)
            let baseColor = parent.baseColor
            
            let attributed = NSMutableAttributedString(string: s, attributes: [
                .font: font,
                .foregroundColor: baseColor
            ])
            
            tokenRanges = []
            
            if let rx = try? NSRegularExpression(pattern: #"@([A-Za-z0-9._%+\-@/:\-]+)"#, options: []) {
                for m in rx.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                    guard m.range.location != NSNotFound, m.range.length > 1 else { continue }
                    if let valueRange = Range(m.range(at: 1), in: s) {
                        let value = String(s[valueRange])
                        let display = (s as NSString).substring(with: m.range)
                        tokenRanges.append((m.range, HoverToken(kind: .mention(value: value), displayText: display)))
                    }
                    attributed.addAttributes([
                        .foregroundColor: parent.mentionColor,
                        .font: NSFont.boldSystemFont(ofSize: parent.fontSize)
                    ], range: m.range)
                }
            }
            
            if let rx = try? NSRegularExpression(pattern: #"#(\w+)"#, options: []) {
                for m in rx.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                    guard m.range.location != NSNotFound, m.range.length > 1 else { continue }
                    if let tagRange = Range(m.range(at: 1), in: s) {
                        let tag = String(s[tagRange]).lowercased()
                        let display = (s as NSString).substring(with: m.range)
                        tokenRanges.append((m.range, HoverToken(kind: .hashtag(tag: tag), displayText: display)))
                    }
                    attributed.addAttributes([
                        .foregroundColor: parent.hashtagColor,
                        .font: NSFont.boldSystemFont(ofSize: parent.fontSize)
                    ], range: m.range)
                }
            }
            
            textView.textStorage?.setAttributedString(attributed)
            textView.invalidateIntrinsicContentSize()
        }
        
        func handleHover(index: Int?) {
            guard let idx = index else {
                if lastHoverToken != nil {
                    lastHoverToken = nil
                    parent.onHoverTokenChange?(nil)
                }
                return
            }
            
            let token = tokenRanges.first(where: { NSLocationInRange(idx, $0.range) })?.token
            if token != lastHoverToken {
                lastHoverToken = token
                parent.onHoverTokenChange?(token)
            }
        }
    }
}

// MARK: - IntrinsicHoverTextView

/// NSTextView con intrinsicContentSize che si adatta al contenuto.
final class IntrinsicHoverTextView: HoverTextView {
    override var isFlipped: Bool { true }
    
    override var intrinsicContentSize: NSSize {
        guard let lm = layoutManager, let tc = textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 18)
        }
        
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let h = ceil(used.size.height + textContainerInset.height * 2)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(18, h))
    }
}

