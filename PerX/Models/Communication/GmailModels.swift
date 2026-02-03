import Foundation

// Modelli per le risposte Gmail API
struct GmailResponse: Codable {
    let messages: [GmailMessageInfo]?
    let nextPageToken: String?
}

struct GmailMessageInfo: Codable {
    let id: String
    let threadId: String
}

struct GmailMessageDetail: Codable {
    let id: String
    let threadId: String
    let labelIds: [String]
    let snippet: String
    let payload: MessagePayloadDetail
    let sizeEstimate: Int
    let historyId: String
    let internalDate: String
}

struct MessagePayloadDetail: Codable {
    let partId: String?
    let mimeType: String
    let filename: String?
    let headers: [MessageHeaderDetail]
    let body: MessageBodyDetail?
    let parts: [MessagePartDetail]?
}

struct MessageHeaderDetail: Codable {
    let name: String
    let value: String
}

struct MessageBodyDetail: Codable {
    let size: Int
    let attachmentId: String?
    let data: String?
}

struct MessagePartDetail: Codable {
    let partId: String
    let mimeType: String
    let filename: String
    let headers: [MessageHeaderDetail]
    let body: MessageBodyDetail
    let parts: [MessagePartDetail]?
}

struct GmailMessage: Codable {
    let id: String
    let payload: MessagePayload?
    
    struct MessagePayload: Codable {
        let headers: [MessageHeader]?
        let parts: [MessagePart]?
    }
    
    struct MessagePart: Codable {
        let mimeType: String
        let body: MessageBody?
    }
    
    struct MessageBody: Codable {
        let data: String?
    }
}

struct MessageHeader: Codable {
    let name: String
    let value: String
}

struct GmailMessageList: Codable {
    let messages: [GmailMessage]?
    let nextPageToken: String?
}

enum GoogleAuthError: Error {
    case noAccessToken
    case invalidResponse
    case networkError
}

// Modello per le Etichette di Gmail
struct GmailLabelList: Codable {
    let labels: [GmailLabel]
}

struct GmailLabel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String // "system" o "user"
}

struct MessageAttachmentData: Codable {
    let size: Int
    let data: String
}

// Modello per il corpo della richiesta di modifica delle etichette
struct ModifyLabelsRequest: Codable {
    let addLabelIds: [String]
    let removeLabelIds: [String]
} 