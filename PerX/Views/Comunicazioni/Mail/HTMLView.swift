import SwiftUI
import WebKit

struct MailHTMLView: NSViewRepresentable {
    let htmlString: String
    @Binding var dynamicHeight: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Limita le risorse per evitare problemi di performance
        configuration.suppressesIncrementalRendering = false
        // Disabilita Java e altri contenuti non necessari
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // Imposta uno sfondo trasparente per integrarsi meglio
        webView.setValue(false, forKey: "drawsBackground")
        // Disabilita lo scroll interno per evitare conflitti con lo ScrollView principale
        webView.enclosingScrollView?.hasVerticalScroller = false
        webView.enclosingScrollView?.hasHorizontalScroller = false
        webView.enclosingScrollView?.verticalScrollElasticity = .none
        webView.enclosingScrollView?.horizontalScrollElasticity = .none
        
        // Imposta una larghezza iniziale
        webView.frame = CGRect(x: 0, y: 0, width: 800, height: 100)
        
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Evita ricaricamenti inutili se l'HTML è lo stesso
        if let lastLoadedHTML = context.coordinator.lastLoadedHTML, lastLoadedHTML == htmlString {
            // HTML non è cambiato, non ricaricare
            return
        }
        
        // Assicurati che il WebView abbia una larghezza definita prima di caricare
        // Questo è cruciale per il calcolo corretto dell'altezza
        if nsView.frame.width == 0 {
            // Usa una larghezza di default se non ancora impostata
            nsView.frame = CGRect(x: 0, y: 0, width: 800, height: 100)
        }
        
        // Aggiungo CSS migliorato per evitare tagli di testo + quote collassabili
        let styledHTML = """
        <!DOCTYPE html>
        <html>
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                    * {
                        box-sizing: border-box;
                    }
                    html, body {
                        margin: 0;
                        padding: 8px 12px;
                        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                        font-size: 14px;
                        line-height: 1.5;
                        color: \(NSColor.labelColor.hexString);
                        background-color: transparent;
                        word-wrap: break-word;
                        overflow-wrap: break-word;
                    }
                    body {
                        width: 100%;
                        max-width: 100%;
                    }
                    p, div, span {
                        word-wrap: break-word;
                        overflow-wrap: break-word;
                    }
                    pre {
                        white-space: pre-wrap;
                        word-wrap: break-word;
                        overflow-wrap: break-word;
                    }
                    a {
                        color: \(NSColor.linkColor.hexString);
                        word-break: break-all;
                    }
                    img {
                        max-width: 100%;
                        height: auto;
                    }
                    table {
                        max-width: 100%;
                        word-wrap: break-word;
                    }
                    
                    /* Quote collapsibili - stile Apple Mail */
                    .quote-container {
                        margin-top: 12px;
                        border-left: 3px solid \(NSColor.separatorColor.hexString);
                        padding-left: 12px;
                    }
                    .quote-toggle {
                        display: inline-flex;
                        align-items: center;
                        gap: 6px;
                        padding: 6px 12px;
                        margin: 8px 0;
                        background: \(NSColor.controlBackgroundColor.hexString);
                        border: 1px solid \(NSColor.separatorColor.hexString);
                        border-radius: 6px;
                        cursor: pointer;
                        font-size: 12px;
                        color: \(NSColor.secondaryLabelColor.hexString);
                        transition: background 0.2s;
                    }
                    .quote-toggle:hover {
                        background: \(NSColor.selectedContentBackgroundColor.hexString);
                    }
                    .quote-toggle::before {
                        content: '▶';
                        font-size: 10px;
                        transition: transform 0.2s;
                    }
                    .quote-toggle.expanded::before {
                        transform: rotate(90deg);
                    }
                    .quote-content {
                        display: none;
                        opacity: 0;
                        transition: opacity 0.3s;
                    }
                    .quote-content.visible {
                        display: block;
                        opacity: 1;
                    }
                    
                    /* Stile per blockquote esistenti */
                    blockquote, .gmail_quote, .yahoo_quoted, [class*="quote"] {
                        margin: 0;
                        padding: 0;
                        border: none;
                    }
                </style>
            </head>
            <body>
                \(Self.processQuotes(in: htmlString))
                <script>
                    // Inizializza tutti i toggle
                    document.querySelectorAll('.quote-toggle').forEach(function(toggle) {
                        toggle.addEventListener('click', function() {
                            var content = this.nextElementSibling;
                            var isExpanded = this.classList.contains('expanded');
                            
                            if (isExpanded) {
                                this.classList.remove('expanded');
                                content.classList.remove('visible');
                                this.innerHTML = this.getAttribute('data-show-text');
                            } else {
                                this.classList.add('expanded');
                                content.classList.add('visible');
                                this.innerHTML = this.getAttribute('data-hide-text');
                            }
                            
                            // Notifica cambio altezza dopo animazione
                            setTimeout(function() {
                                window.webkit.messageHandlers.heightChange && 
                                window.webkit.messageHandlers.heightChange.postMessage(document.body.scrollHeight);
                            }, 350);
                        });
                    });
                </script>
            </body>
        </html>
        """
        // Carica solo se l'HTML è cambiato
        context.coordinator.lastLoadedHTML = htmlString
        nsView.loadHTMLString(styledHTML, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: MailHTMLView
        var lastLoadedHTML: String? // Memorizza l'ultimo HTML caricato per evitare ricaricamenti
        var heightCalculationTask: Task<Void, Never>? // Task per il calcolo altezza con timeout

        init(_ parent: MailHTMLView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Annulla eventuali task precedenti
            heightCalculationTask?.cancel()
            
            // Timeout per evitare che il WebView resti bloccato
            heightCalculationTask = Task { @MainActor in
                // Aspetta un po' per assicurarsi che il rendering sia completo
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 secondi
                
                guard !Task.isCancelled else { return }
                
                // Calcola l'altezza usando JavaScript
                webView.evaluateJavaScript("""
                    (function() {
                        // Forza il reflow per assicurarsi che tutto sia renderizzato
                        document.body.style.display = 'none';
                        document.body.offsetHeight; // Trigger reflow
                        document.body.style.display = '';
                        
                        // Calcola l'altezza considerando tutti gli elementi
                        var bodyHeight = Math.max(
                            document.body.scrollHeight,
                            document.body.offsetHeight,
                            document.body.clientHeight
                        );
                        
                        var docHeight = Math.max(
                            document.documentElement.scrollHeight,
                            document.documentElement.offsetHeight,
                            document.documentElement.clientHeight
                        );
                        
                        return Math.max(bodyHeight, docHeight) + 20;
                    })();
                """) { [weak self] (height, error) in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        if let height = height as? CGFloat, height > 0 {
                            // Limita l'altezza massima per evitare espansione infinita
                            self.parent.dynamicHeight = min(height, 2000)
                        } else if let error = error {
                            print("[MailHTMLView] Errore calcolo altezza: \(error)")
                            // Fallback a un'altezza minima
                            self.parent.dynamicHeight = 200
                        } else {
                            // Se non c'è errore ma height è 0 o nil, usa un'altezza di default
                            self.parent.dynamicHeight = 200
                        }
                        // Task completato
                        self.heightCalculationTask = nil
                    }
                }
                
                // Timeout: se dopo 10 secondi non abbiamo l'altezza, usa un fallback
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 secondi
                
                guard !Task.isCancelled else { return }
                
                // Se siamo qui, il timeout è scattato
                if self.parent.dynamicHeight == 0 {
                    self.parent.dynamicHeight = 200
                    print("[MailHTMLView] ⚠️ Timeout calcolo altezza, usato fallback")
                }
                self.heightCalculationTask = nil
            }
        }
        
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // Gestisci il caso in cui il processo WebContent si interrompe
            print("[MailHTMLView] ⚠️ WebContent process terminato, reset height")
            heightCalculationTask?.cancel()
            heightCalculationTask = nil
            DispatchQueue.main.async {
                // Reset height e prepara per ricaricamento se necessario
                self.parent.dynamicHeight = 0
            }
        }
    }
}

// MARK: - Quote Processing

extension MailHTMLView {
    /// Processa l'HTML per rendere le quote collassabili (come Apple Mail)
    static func processQuotes(in html: String) -> String {
        var processedHTML = html
        
        // Pattern per identificare le quote (Gmail, Yahoo, Outlook, etc.)
        let quotePatterns = [
            // Gmail quote
            #"(<div\s+class="gmail_quote"[^>]*>)([\s\S]*?)(</div>)"#,
            // Blockquote generico
            #"(<blockquote[^>]*>)([\s\S]*?)(</blockquote>)"#,
            // Pattern "On ... wrote:"
            #"(<div[^>]*>On\s+.+?\s+wrote:</div>\s*<blockquote[^>]*>)([\s\S]*?)(</blockquote>)"#,
            // Yahoo quote
            #"(<div\s+class="yahoo_quoted"[^>]*>)([\s\S]*?)(</div>)"#
        ]
        
        for pattern in quotePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(processedHTML.startIndex..., in: processedHTML)
                
                // Trova tutte le quote e le sostituisce con versione collassabile
                let matches = regex.matches(in: processedHTML, options: [], range: range)
                
                // Processa in ordine inverso per non invalidare gli offset
                for match in matches.reversed() {
                    guard let fullRange = Range(match.range, in: processedHTML) else { continue }
                    
                    let quoteContent = String(processedHTML[fullRange])
                    
                    // Estrai il nome del mittente se possibile
                    let senderName = extractSenderName(from: quoteContent) ?? "precedente"
                    
                    // Crea la versione collassabile
                    let collapsibleQuote = """
                    <div class="quote-container">
                        <div class="quote-toggle" data-show-text="Mostra altro da \(senderName)" data-hide-text="Mostra meno">
                            Mostra altro da \(senderName)
                        </div>
                        <div class="quote-content">
                            \(quoteContent)
                        </div>
                    </div>
                    """
                    
                    processedHTML.replaceSubrange(fullRange, with: collapsibleQuote)
                }
            }
        }
        
        return processedHTML
    }
    
    /// Estrae il nome del mittente dalla quote
    private static func extractSenderName(from quoteHTML: String) -> String? {
        // Pattern per estrarre il nome dopo "wrote:" o "scrisse:" o simili
        let patterns = [
            #"On\s+.+?,\s*(.+?)\s+wrote:"#,
            #"Il\s+.+?,\s*(.+?)\s+ha scritto:"#,
            #"Da:\s*(.+?)\s*<"#,
            #"From:\s*(.+?)\s*<"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: quoteHTML, options: [], range: NSRange(quoteHTML.startIndex..., in: quoteHTML)),
               let nameRange = Range(match.range(at: 1), in: quoteHTML) {
                let name = String(quoteHTML[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    return name
                }
            }
        }
        
        return nil
    }
}

// Estensione per ottenere il colore in formato esadecimale per il CSS
extension NSColor {
    var hexString: String {
        let cgColor = self.cgColor
        let components = cgColor.components
        let r: CGFloat = components?[0] ?? 0.0
        let g: CGFloat = components?[1] ?? 0.0
        let b: CGFloat = components?[2] ?? 0.0

        return String(
            format: "#%02lX%02lX%02lX",
            lround(r * 255),
            lround(g * 255),
            lround(b * 255)
        )
    }
} 