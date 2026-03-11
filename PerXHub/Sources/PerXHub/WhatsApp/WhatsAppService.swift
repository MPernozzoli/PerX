import Foundation
import PerXCore
import SQLite

/// Servizio WhatsApp sull'Hub
/// Gestisce messaggi ricevuti dal WA Bridge e classificazione
public actor WhatsAppService {
    public static let shared = WhatsAppService()
    
    private var bridgeURL: String = "http://localhost:3000"
    
    private init() {}
    
    // MARK: - Configuration
    
    public func configure(bridgeURL: String) {
        self.bridgeURL = bridgeURL
        print("[WhatsAppService] Configured with bridge: \(bridgeURL)")
    }
    
    // MARK: - Receive Messages
    
    /// Processa messaggio ricevuto dal bridge
    public func processIncomingMessage(_ message: WAMessage) async throws -> ProcessedWAMessage {
        print("[WhatsAppService] Processing message: \(message.messageId)")
        
        // 1. Classifica messaggio (stessa logica delle email)
        let category = classifyMessage(message.body)
        
        // 2. Estrai riferimento sinistro
        let sinistroRef = extractSinistroRef(message.body)
        
        // 3. Crea messaggio processato
        let processed = ProcessedWAMessage(
            messageId: message.messageId,
            accountId: message.accountId,
            from: message.from,
            to: message.to,
            body: message.body,
            timestamp: message.timestamp,
            category: category,
            sinistroRef: sinistroRef,
            hasMedia: message.hasMedia
        )
        
        // 4. Salva nel database
        try await saveMessage(processed)
        
        // 5. Gestisci allegati
        if let media = message.media {
            try await AttachmentManager.shared.createAttachment(
                messageId: message.messageId,
                sourceType: .whatsapp,
                filename: media.filename,
                size: Int64(media.data.count),
                mimeType: media.mimetype,
                sinistroRef: sinistroRef
            )
        }
        
        return processed
    }
    
    // MARK: - Send Messages
    
    /// Invia messaggio tramite bridge
    public func sendMessage(accountId: String, to: String, body: String, media: WAMediaData? = nil) async throws -> String {
        let url = URL(string: "\(bridgeURL)/clients/\(accountId)/send")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct SendRequest: Encodable {
            let to: String
            let body: String
            let media: WAMediaData?
        }
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(SendRequest(to: to, body: body, media: media))
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WhatsAppError.sendFailed("Invalid response")
        }
        
        struct SendResponse: Decodable {
            let success: Bool
            let messageId: String
        }
        
        let result = try JSONDecoder().decode(SendResponse.self, from: data)
        
        if result.success {
            return result.messageId
        } else {
            throw WhatsAppError.sendFailed("Send failed")
        }
    }
    
    // MARK: - Classification
    
    private func classifyMessage(_ body: String?) -> EmailCategory? {
        guard let text = body?.lowercased() else { return nil }
        
        // Pattern semplificati per WA (usando categorie da PerXCore)
        if text.contains("fattura") || text.contains("pagamento") {
            return .administrative
        }
        if text.contains("urgente") || text.contains("sollecito") {
            return .reminderReceived
        }
        if text.contains("foto") || text.contains("immagini") {
            return .documentationReceived
        }
        if text.contains("documentazione") || text.contains("documenti") {
            return .documentationReceived
        }
        if text.contains("firmato") || text.contains("atto") {
            return .actReceived
        }
        
        return .genericCommunication
    }
    
    private func extractSinistroRef(_ body: String?) -> String? {
        guard let text = body else { return nil }
        
        // Pattern per riferimento sinistro
        let patterns = [
            "\\b(\\d{4}[-/]\\d{5,7})\\b",
            "\\b([A-Z]{2,3}[-/]?\\d{6,10})\\b"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    if match.numberOfRanges > 1,
                       let refRange = Range(match.range(at: 1), in: text) {
                        return String(text[refRange])
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Persistence
    
    private func saveMessage(_ message: ProcessedWAMessage) async throws {
        // TODO: Creare tabella whatsapp_messages e salvare
        print("[WhatsAppService] Saved message: \(message.messageId)")
    }
    
    // MARK: - Query
    
    public func getMessages(sinistroRef: String) async throws -> [ProcessedWAMessage] {
        // TODO: Query dal database
        return []
    }
    
    public func getUnassociatedMessages(limit: Int = 50) async throws -> [ProcessedWAMessage] {
        // TODO: Query messaggi senza sinistro
        return []
    }
}

// MARK: - Types

public struct WAMessage: Codable {
    public let accountId: String
    public let messageId: String
    public let from: String
    public let to: String
    public let body: String?
    public let timestamp: Int
    public let type: String
    public let hasMedia: Bool
    public let isGroup: Bool
    public let author: String?
    public let media: WAMediaData?
}

public struct WAMediaData: Codable {
    public let mimetype: String
    public let data: String  // base64
    public let filename: String
}

public struct ProcessedWAMessage: Codable, Identifiable {
    public var id: String { messageId }
    
    public let messageId: String
    public let accountId: String
    public let from: String
    public let to: String
    public let body: String?
    public let timestamp: Int
    public let category: EmailCategory?
    public let sinistroRef: String?
    public let hasMedia: Bool
}

// MARK: - Errors

public enum WhatsAppError: Error, LocalizedError {
    case bridgeNotAvailable
    case sendFailed(String)
    case accountNotFound
    
    public var errorDescription: String? {
        switch self {
        case .bridgeNotAvailable:
            return "WhatsApp bridge not available"
        case .sendFailed(let reason):
            return "Send failed: \(reason)"
        case .accountNotFound:
            return "WhatsApp account not found"
        }
    }
}
