import Foundation

/// Stub legacy: la V1 usa solo backend/Resend per email in ingresso e uscita.
class GmailService {
    
    static let shared = GmailService()
    
    private init() {}
    
    /// Scarica i dettagli completi di una singola email.
    func fetchEmailDetails(messageId: String) async throws -> GmailMessageDetail {
        throw GmailAPIError.tokenError("GmailService disabilitato: usare backend/Resend.")
    }

    /// Scarica solo i metadati di una lista di email.
    func fetchEmailMetadata(for messageIds: [String]) async throws -> [GmailMessageDetail] {
        throw GmailAPIError.tokenError("GmailService disabilitato: usare backend/Resend.")
    }
    
    /// Invia un'email tramite Gmail API
    func sendEmail(
        to: [Contact],
        cc: [Contact]? = nil,
        bcc: [Contact]? = nil,
        subject: String,
        body: String,
        isHTML: Bool = true,
        replyToMessageId: String? = nil,
        replyToThreadId: String? = nil,
        inReplyTo: String? = nil,
        references: String? = nil,
        attachments: [URL] = []
    ) async throws -> String {
        throw GmailAPIError.tokenError("GmailService disabilitato: usare backend/Resend.")
    }
    
    /// Ottiene il threadId di un messaggio
    func getThreadId(for messageId: String) async throws -> String? {
        throw GmailAPIError.tokenError("GmailService disabilitato: usare backend/Resend.")
    }
}
