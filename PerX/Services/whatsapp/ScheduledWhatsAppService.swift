import Foundation

/// Servizio per gestione messaggi WhatsApp programmati via Hub
@MainActor
class ScheduledWhatsAppService {
    static let shared = ScheduledWhatsAppService()
    
    private let hubService = HubService.shared
    
    private init() {}
    
    // MARK: - Models
    
    struct ScheduledWhatsApp: Codable, Identifiable {
        let id: String
        let accountId: String
        let phoneNumber: String
        let body: String
        let mediaData: String?
        let mediaType: String?
        let mediaFilename: String?
        let scheduledAt: Date
        let status: String
        let sinistroRef: String?
        let sentAt: Date?
        let sentMessageId: String?
        let errorMessage: String?
        
        var isScheduled: Bool { status == "pending" }
        var isSent: Bool { status == "sent" }
        var isFailed: Bool { status == "failed" }
        
        var scheduledAtFormatted: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: "it_IT")
            return formatter.string(from: scheduledAt)
        }
        
        var sentAtFormatted: String? {
            guard let sentAt = sentAt else { return nil }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: "it_IT")
            return formatter.string(from: sentAt)
        }
    }
    
    // MARK: - Schedule Message
    
    /// Programma invio di un messaggio WhatsApp
    func scheduleMessage(
        accountId: String,
        phoneNumber: String,
        body: String,
        mediaData: String?,
        mediaType: String?,
        mediaFilename: String?,
        scheduledFor: Date,
        sinistroRef: String?
    ) async throws -> ScheduledWhatsApp {
        let endpoint = "/whatsapp/schedule"
        
        var payload: [String: Any] = [
            "accountId": accountId,
            "phoneNumber": phoneNumber,
            "body": body,
            "scheduledFor": ISO8601DateFormatter().string(from: scheduledFor)
        ]
        
        if let mediaData = mediaData {
            payload["mediaData"] = mediaData
        }
        if let mediaType = mediaType {
            payload["mediaType"] = mediaType
        }
        if let mediaFilename = mediaFilename {
            payload["mediaFilename"] = mediaFilename
        }
        if let sinistroRef = sinistroRef {
            payload["sinistroRef"] = sinistroRef
        }
        
        let data = try await hubService.post(endpoint: endpoint, payload: payload)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(ScheduledWhatsApp.self, from: data)
    }
    
    /// Ottiene lista messaggi programmati per account
    func getScheduledMessages(accountId: String) async throws -> [ScheduledWhatsApp] {
        let endpoint = "/whatsapp/scheduled?accountId=\(accountId)"
        
        let data = try await hubService.get(endpoint: endpoint)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode([ScheduledWhatsApp].self, from: data)
    }
    
    /// Cancella messaggio programmato (solo se pending)
    func cancelScheduledMessage(id: String) async throws {
        let endpoint = "/whatsapp/scheduled/\(id)"
        
        try await hubService.delete(endpoint: endpoint)
    }
}
