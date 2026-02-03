import Foundation
import Network

class LocalServer {
    static let shared = LocalServer()
    private var serverSocket: NWListener?
    var onCodeReceived: ((String) -> Void)?
    
    private let successHTML = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Autenticazione Completata</title>
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                display: flex;
                justify-content: center;
                align-items: center;
                height: 100vh;
                margin: 0;
                background-color: #f5f5f7;
            }
            .container {
                text-align: center;
                padding: 40px;
                background: white;
                border-radius: 10px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                max-width: 400px;
            }
            h1 {
                color: #1d1d1f;
                margin-bottom: 20px;
            }
            p {
                color: #86868b;
                line-height: 1.5;
                margin-bottom: 30px;
            }
            .icon {
                font-size: 48px;
                color: #34c759;
                margin-bottom: 20px;
            }
            .close-button {
                background-color: #0071e3;
                color: white;
                border: none;
                padding: 10px 20px;
                border-radius: 6px;
                font-size: 14px;
                cursor: pointer;
                transition: background-color 0.2s;
            }
            .close-button:hover {
                background-color: #0077ed;
            }
        </style>
        <script>
            function closeWindow() {
                window.close();
            }
            // Chiudi automaticamente dopo 3 secondi
            setTimeout(closeWindow, 3000);
        </script>
    </head>
    <body>
        <div class="container">
            <div class="icon">✓</div>
            <h1>Autenticazione Completata</h1>
            <p>L'accesso è stato effettuato con successo.<br>Questa finestra si chiuderà automaticamente.</p>
            <button class="close-button" onclick="closeWindow()">Chiudi</button>
        </div>
    </body>
    </html>
    """
    
    func start() {
        do {
            let parameters = NWParameters.tcp
            serverSocket = try NWListener(using: parameters, on: 3000)
            
            serverSocket?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("🚀 Server locale in ascolto su 127.0.0.1:3000")
                case .failed(let error):
                    print("❌ Errore server locale: \(error)")
                default:
                    break
                }
            }
            
            serverSocket?.newConnectionHandler = { [weak self] connection in
                guard let self = self else { return }
                
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                    if let data = data,
                       let request = String(data: data, encoding: .utf8),
                       let codeParam = request.components(separatedBy: " ")[1]
                        .components(separatedBy: "?")
                        .last?
                        .components(separatedBy: "&")
                        .first(where: { $0.starts(with: "code=") }) {
                        
                        let code = String(codeParam.dropFirst(5))
                        print("🎫 Codice ricevuto: \(code)")
                        self.onCodeReceived?(code)
                        
                        // Invia risposta HTTP con la pagina di successo
                        let response = """
                        HTTP/1.1 200 OK\r
                        Content-Type: text/html; charset=utf-8\r
                        Content-Length: \(self.successHTML.utf8.count)\r
                        Cache-Control: no-store\r
                        Connection: close\r
                        \r
                        \(self.successHTML)
                        """
                        
                        connection.send(content: response.data(using: .utf8), completion: .idempotent)
                    }
                    
                    connection.cancel()
                }
                
                connection.start(queue: .main)
            }
            
            serverSocket?.start(queue: .main)
            
        } catch {
            print("❌ Errore avvio server: \(error)")
        }
    }
    
    func stop() {
        serverSocket?.cancel()
        serverSocket = nil
    }
} 