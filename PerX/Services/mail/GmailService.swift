import Foundation

/// Servizio dedicato per interagire con le API di Gmail.
class GmailService {
    
    static let shared = GmailService()
    private let authService = GoogleAuthService.shared
    
    private init() {}
    
    /// Scarica i dettagli completi di una singola email.
    func fetchEmailDetails(messageId: String) async throws -> GmailMessageDetail {
        guard let accessToken = try? await authService.getAccessToken() else {
            throw GmailAPIError.tokenError("Token di accesso non valido.")
        }
        
        let url = URL(string: "https://www.googleapis.com/gmail/v1/users/me/messages/\(messageId)?format=full")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GmailAPIError.badServerResponse(statusCode: statusCode, responseBody: body)
        }

        return try JSONDecoder().decode(GmailMessageDetail.self, from: data)
    }

    /// Scarica solo i metadati di una lista di email.
    func fetchEmailMetadata(for messageIds: [String]) async throws -> [GmailMessageDetail] {
        // Questa funzione può essere implementata in futuro se serve scaricare i metadati in batch
        // Per ora, un esempio con un singolo ID
        guard let messageId = messageIds.first else { return [] }
        
        guard let accessToken = try? await authService.getAccessToken() else {
            throw GmailAPIError.tokenError("Token di accesso non valido.")
        }
        
        let url = URL(string: "https://www.googleapis.com/gmail/v1/users/me/messages/\(messageId)?format=metadata")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GmailAPIError.badServerResponse(statusCode: statusCode, responseBody: body)
        }
        
        let detail = try JSONDecoder().decode(GmailMessageDetail.self, from: data)
        return [detail]
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
        guard let accessToken = try? await authService.getAccessToken() else {
            throw GmailAPIError.tokenError("Token di accesso non valido.")
        }
        
        // Costruisci il messaggio email in formato RFC 2822
        var messageHeaders: [String] = []
        
        // To
        let toAddresses = to.map { contact in
            if let name = contact.name, !name.isEmpty {
                return "\(name) <\(contact.email)>"
            }
            return contact.email
        }.joined(separator: ", ")
        messageHeaders.append("To: \(toAddresses)")
        
        // CC
        if let cc = cc, !cc.isEmpty {
            let ccAddresses = cc.map { contact in
                if let name = contact.name, !name.isEmpty {
                    return "\(name) <\(contact.email)>"
                }
                return contact.email
            }.joined(separator: ", ")
            messageHeaders.append("Cc: \(ccAddresses)")
        }
        
        // BCC
        if let bcc = bcc, !bcc.isEmpty {
            let bccAddresses = bcc.map { contact in
                if let name = contact.name, !name.isEmpty {
                    return "\(name) <\(contact.email)>"
                }
                return contact.email
            }.joined(separator: ", ")
            messageHeaders.append("Bcc: \(bccAddresses)")
        }
        
        // Subject
        messageHeaders.append("Subject: \(subject)")
        
        // Content-Type
        if isHTML {
            messageHeaders.append("Content-Type: text/html; charset=UTF-8")
        } else {
            messageHeaders.append("Content-Type: text/plain; charset=UTF-8")
        }
        
        // In-Reply-To e References per risposte
        if let inReplyTo = inReplyTo {
            messageHeaders.append("In-Reply-To: \(inReplyTo)")
        }
        if let references = references {
            messageHeaders.append("References: \(references)")
        }
        
        // Costruisci il messaggio completo
        let headersString = messageHeaders.joined(separator: "\r\n")
        let fullMessage = "\(headersString)\r\n\r\n\(body)"
        
        // Codifica in base64url
        guard let messageData = fullMessage.data(using: .utf8) else {
            throw GmailAPIError.badServerResponse(statusCode: -1, responseBody: "Errore codifica messaggio")
        }
        
        let base64Message = messageData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        // Prepara la richiesta
        var requestBody: [String: Any] = ["raw": base64Message]
        
        if let threadId = replyToThreadId {
            requestBody["threadId"] = threadId
        }
        
        guard let url = URL(string: "https://www.googleapis.com/gmail/v1/users/me/messages/send") else {
            throw GmailAPIError.badServerResponse(statusCode: -1, responseBody: "URL non valido")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.badServerResponse(statusCode: -1, responseBody: "Risposta non valida")
        }
        
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "N/A"
            throw GmailAPIError.badServerResponse(statusCode: httpResponse.statusCode, responseBody: body)
        }
        
        // Decodifica la risposta per ottenere l'ID del messaggio inviato
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let messageId = json["id"] as? String {
            return messageId
        }
        
        throw GmailAPIError.badServerResponse(statusCode: httpResponse.statusCode, responseBody: "ID messaggio non trovato nella risposta")
    }
    
    /// Ottiene il threadId di un messaggio
    func getThreadId(for messageId: String) async throws -> String? {
        guard let accessToken = try? await authService.getAccessToken() else {
            throw GmailAPIError.tokenError("Token di accesso non valido.")
        }
        
        let url = URL(string: "https://www.googleapis.com/gmail/v1/users/me/messages/\(messageId)?format=metadata&metadataHeaders=Message-ID")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        
        let detail = try JSONDecoder().decode(GmailMessageDetail.self, from: data)
        return detail.threadId
    }
} 