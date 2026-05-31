import Foundation

/// Servizio per gestione messaggi WhatsApp programmati via Hub
@MainActor
class ScheduledWhatsAppService {
    static let shared = ScheduledWhatsAppService()
    
    private let hubClient = HubAPIClient.shared
    
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
        struct SchedulePayload: Encodable {
            let accountId: String
            let phoneNumber: String
            let body: String
            let mediaData: String?
            let mediaType: String?
            let mediaFilename: String?
            let scheduledFor: Date
            let sinistroRef: String?
        }

        return try await hubClient.localPost(
            endpoint: "whatsapp/schedule",
            body: SchedulePayload(
                accountId: accountId,
                phoneNumber: phoneNumber,
                body: body,
                mediaData: mediaData,
                mediaType: mediaType,
                mediaFilename: mediaFilename,
                scheduledFor: scheduledFor,
                sinistroRef: sinistroRef
            )
        )
    }
    
    /// Ottiene lista messaggi programmati per account
    func getScheduledMessages(accountId: String) async throws -> [ScheduledWhatsApp] {
        try await hubClient.localGet(endpoint: "whatsapp/scheduled?accountId=\(accountId)")
    }
    
    /// Cancella messaggio programmato (solo se pending)
    func cancelScheduledMessage(id: String) async throws {
        try await hubClient.localDelete(endpoint: "whatsapp/scheduled/\(id)")
    }
}
