import Foundation

// MARK: - WhatsAppChat

struct WhatsAppChat: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var phoneNumber: String?
    var profilePicture: String?
    var isGroup: Bool
    var lastMessage: String?
    var lastMessageDate: Date?
    var unreadCount: Int
    var isPinned: Bool
    var isMuted: Bool
    var sinistroRiferimento: String?
    
    var formattedPhone: String {
        guard let phone = phoneNumber, !phone.isEmpty else { return name }
        return "+\(phone)"
    }
    
    var timestamp: Date {
        lastMessageDate ?? Date()
    }
    
    init(id: String, name: String, phoneNumber: String? = nil, profilePicture: String? = nil, isGroup: Bool = false, lastMessage: String? = nil, lastMessageDate: Date? = nil, unreadCount: Int = 0, isPinned: Bool = false, isMuted: Bool = false, sinistroRiferimento: String? = nil) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
        self.profilePicture = profilePicture
        self.isGroup = isGroup
        self.lastMessage = lastMessage
        self.lastMessageDate = lastMessageDate
        self.unreadCount = unreadCount
        self.isPinned = isPinned
        self.isMuted = isMuted
        self.sinistroRiferimento = sinistroRiferimento
    }
}

// MARK: - MessageType

enum MessageType: String, Codable {
    case text
    case image
    case video
    case audio
    case document
    case sticker
    case location
    case contact
    case ptt // voice note
}

// MARK: - WhatsAppMediaType (legacy compatibility)

typealias WhatsAppMediaType = MessageType

// MARK: - WhatsAppMessage

struct WhatsAppMessage: Identifiable, Hashable, Codable {
    var id: String
    var chatId: String
    var from: String
    var to: String?
    var body: String
    var timestamp: Date
    var isFromMe: Bool
    var isRead: Bool
    var type: MessageType
    var mediaId: String?
    var mediaType: String?
    var mediaFilename: String?
    var mediaUrl: String?
    var quotedMessageId: String?
    var sinistroRiferimento: String?
    // ACK status: -1=error, 0=pending, 1=sent, 2=delivered, 3=read, 4=played
    var ackStatus: Int?
    var ackTimestamp: Date?
    
    // Status properties based on ackStatus
    var isSent: Bool { isFromMe && (ackStatus ?? 0) >= 1 }
    var isDelivered: Bool { isFromMe && (ackStatus ?? 0) >= 2 }
    var isReadByRecipient: Bool { isFromMe && (ackStatus ?? 0) >= 3 }
    var isPlayed: Bool { isFromMe && (ackStatus ?? 0) >= 4 }
    
    var hasMedia: Bool {
        mediaId != nil || mediaType != nil
    }
    
    init(id: String, chatId: String, from: String, to: String? = nil, body: String, timestamp: Date, isFromMe: Bool = false, isRead: Bool = false, type: MessageType = .text, mediaId: String? = nil, mediaType: String? = nil, mediaFilename: String? = nil, mediaUrl: String? = nil, quotedMessageId: String? = nil, sinistroRiferimento: String? = nil, ackStatus: Int? = nil, ackTimestamp: Date? = nil) {
        self.id = id
        self.chatId = chatId
        self.from = from
        self.to = to
        self.body = body
        self.timestamp = timestamp
        self.isFromMe = isFromMe
        self.isRead = isRead
        self.type = type
        self.mediaId = mediaId
        self.mediaType = mediaType
        self.mediaFilename = mediaFilename
        self.mediaUrl = mediaUrl
        self.quotedMessageId = quotedMessageId
        self.sinistroRiferimento = sinistroRiferimento
        self.ackStatus = ackStatus
        self.ackTimestamp = ackTimestamp
    }
}

// MARK: - ScheduledStatus

enum ScheduledStatus: String, Codable {
    case pending
    case sent
    case failed
    case cancelled
}

// MARK: - ScheduledWhatsAppMessage

struct ScheduledWhatsAppMessage: Identifiable, Codable {
    var id: String
    var phoneNumber: String
    var body: String
    var scheduledAt: Date
    var status: ScheduledStatus
    var sinistroRef: String?
    var mediaFilename: String?
    
    var formattedPhone: String {
        "+\(phoneNumber)"
    }
    
    var isPending: Bool {
        status == .pending
    }
}

struct WhatsAppContact: Identifiable, Hashable, Codable {
    var id: String { phoneNumber }
    let name: String?
    let phoneNumber: String
    let profilePicture: String?
    let isBusiness: Bool
    
    var displayName: String {
        name ?? phoneNumber
    }
    
    enum CodingKeys: String, CodingKey {
        case name, phoneNumber, profilePicture, isBusiness
    }
    
    init(name: String? = nil, phoneNumber: String, profilePicture: String? = nil, isBusiness: Bool = false) {
        self.name = name
        self.phoneNumber = phoneNumber
        self.profilePicture = profilePicture
        self.isBusiness = isBusiness
    }
}

// MARK: - API Response Models
struct WhatsAppAPIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: String?
}

struct QRCodeResponse: Codable {
    let qrCode: String
    let sessionId: String
}

struct ConnectionStatus: Codable {
    let status: String // "connecting", "connected", "disconnected", "qr_ready"
    let qrCode: String?
}

struct SendMessageResponse: Codable {
    let messageId: String
    let success: Bool?
}
