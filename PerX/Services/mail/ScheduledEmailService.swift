import Foundation

/// Servizio per gestione email via Hub (invio immediato e programmato)
@MainActor
class ScheduledEmailService {
    static let shared = ScheduledEmailService()
    
    private let hubEmailService = HubEmailService.shared
    
    private init() {}
    
    // MARK: - Send Email (Immediate)
    
    struct SendEmailResponse: Codable {
        let success: Bool
        let messageId: String?
        let error: String?
        
        enum CodingKeys: String, CodingKey {
            case success
            case messageId = "message_id"
            case error
        }
    }
    
    /// Invia email immediatamente tramite il flusso backend/Resend configurato nell'Hub.
    func sendEmail(
        accountId: String,
        to: [String],
        cc: [String]?,
        bcc: [String]?,
        subject: String,
        body: String,
        isHtml: Bool = true,
        replyToThreadId: String? = nil,
        inReplyTo: String? = nil,
        references: String? = nil,
        attachments: [[String: String]]? = nil
    ) async throws -> SendEmailResponse {
        let mappedAttachments = attachments?.compactMap { item -> (filename: String, data: Data, mimeType: String?)? in
            guard let filename = item["filename"], let base64 = item["data"], let decoded = Data(base64Encoded: base64) else {
                return nil
            }
            return (filename: filename, data: decoded, mimeType: item["mimeType"])
        }

        let response = try await hubEmailService.sendEmail(
            accountId: accountId,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            body: body,
            isHtml: isHtml,
            replyToThreadId: replyToThreadId,
            inReplyTo: inReplyTo,
            references: references,
            attachments: mappedAttachments
        )
        return SendEmailResponse(success: response.success, messageId: response.messageId, error: response.error)
    }
    
    // MARK: - Schedule Email
    
    struct ScheduledEmail: Codable, Identifiable {
        let id: String
        let accountId: String
        let to: [String]
        let cc: [String]?
        let subject: String
        let body: String?
        let scheduledAt: Date
        let status: String
        let sinistroRef: String?
        let sentAt: Date?
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
    }
    
    /// Programma invio di una email
    func scheduleEmail(
        accountId: String,
        to: [String],
        cc: [String]?,
        subject: String,
        body: String,
        scheduledFor: Date,
        sinistroRef: String?
    ) async throws -> ScheduledEmail {
        let scheduled = try await hubEmailService.scheduleEmail(
            accountId: accountId,
            to: to,
            cc: cc,
            subject: subject,
            body: body,
            scheduledFor: scheduledFor,
            sinistroRef: sinistroRef
        )
        return ScheduledEmail(
            id: scheduled.id,
            accountId: scheduled.accountId,
            to: scheduled.to,
            cc: nil,
            subject: scheduled.subject,
            body: body,
            scheduledAt: scheduled.scheduledFor,
            status: scheduled.status,
            sinistroRef: nil,
            sentAt: nil,
            errorMessage: nil
        )
    }
    
    /// Ottiene lista email programmate per utente
    func getScheduledEmails(accountId: String) async throws -> [ScheduledEmail] {
        let items = try await hubEmailService.getScheduledEmails(forAccount: accountId)
        return items.map {
            ScheduledEmail(
                id: $0.id,
                accountId: $0.accountId,
                to: $0.to,
                cc: nil,
                subject: $0.subject,
                body: nil,
                scheduledAt: $0.scheduledFor,
                status: $0.status,
                sinistroRef: nil,
                sentAt: nil,
                errorMessage: nil
            )
        }
    }
    
    /// Cancella email programmata (solo se pending)
    func cancelScheduledEmail(id: String) async throws {
        try await hubEmailService.cancelScheduledEmail(id: id)
    }
}
