import Foundation

// MARK: - Chat Message

/// Messaggio della chat interna sincronizzato via CloudKit
struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let roomId: String
    let senderEmail: String
    let senderName: String
    let content: String
    let mentions: [ChatMention]
    let hashtags: [ChatHashtag]
    let attachments: [ChatAttachment]
    let timestamp: Date
    var isRead: Bool
    var readReceipts: [ChatReadReceipt]
    
    // Collegamento sinistro
    var linkedSinistroRif: String?      // Riferimento sinistro collegato (es. "2412345")
    var isPinnedToDiario: Bool          // Se true, messaggio inserito nel diario del sinistro
    var diarioEntryId: UUID?            // ID dell'entry nel diario (se pinnato)
    
    // Riferimento al messaggio che ha iniziato il collegamento (per catena)
    var linkedFromMessageId: UUID?      // ID del messaggio che ha creato il collegamento
    
    init(
        id: UUID = UUID(),
        roomId: String,
        senderEmail: String,
        senderName: String,
        content: String,
        mentions: [ChatMention] = [],
        hashtags: [ChatHashtag] = [],
        attachments: [ChatAttachment] = [],
        timestamp: Date = Date(),
        isRead: Bool = false,
        readReceipts: [ChatReadReceipt] = [],
        linkedSinistroRif: String? = nil,
        isPinnedToDiario: Bool = false,
        diarioEntryId: UUID? = nil,
        linkedFromMessageId: UUID? = nil
    ) {
        self.id = id
        self.roomId = roomId
        self.senderEmail = senderEmail
        self.senderName = senderName
        self.content = content
        self.mentions = mentions
        self.hashtags = hashtags
        self.attachments = attachments
        self.timestamp = timestamp
        self.isRead = isRead
        self.readReceipts = readReceipts
        self.linkedSinistroRif = linkedSinistroRif
        self.isPinnedToDiario = isPinnedToDiario
        self.diarioEntryId = diarioEntryId
        self.linkedFromMessageId = linkedFromMessageId
    }
    
    /// Verifica se il messaggio è stato inviato dall'utente corrente
    func isSentByCurrentUser(currentEmail: String?) -> Bool {
        guard let currentEmail = currentEmail?.lowercased() else { return false }
        return senderEmail.lowercased() == currentEmail
    }
    
    /// Verifica se il messaggio è collegato a un sinistro
    var isLinkedToSinistro: Bool {
        linkedSinistroRif != nil
    }
    
    /// Verifica se ha allegati
    var hasAttachments: Bool {
        !attachments.isEmpty
    }
}

// MARK: - Read Receipt

struct ChatReadReceipt: Codable, Equatable, Hashable {
    let userEmail: String
    let userName: String?
    let readAt: Date
    
    init(userEmail: String, userName: String? = nil, readAt: Date = Date()) {
        self.userEmail = userEmail.lowercased()
        self.userName = userName
        self.readAt = readAt
    }
}

// MARK: - Chat Attachment

/// Allegato di un messaggio (foto, video, PDF, etc.)
struct ChatAttachment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let type: AttachmentType
    let fileName: String
    let fileSize: Int64           // dimensione in bytes
    let mimeType: String
    let cloudKitAssetURL: String? // URL dell'asset su CloudKit
    var localURL: String?         // URL locale (cache)
    var thumbnailURL: String?     // URL thumbnail (per immagini/video)
    let uploadedAt: Date
    
    enum AttachmentType: String, Codable {
        case image = "image"
        case video = "video"
        case pdf = "pdf"
        case document = "document"
        case audio = "audio"
        case other = "other"
        
        var icon: String {
            switch self {
            case .image: return "photo.fill"
            case .video: return "video.fill"
            case .pdf: return "doc.fill"
            case .document: return "doc.text.fill"
            case .audio: return "waveform"
            case .other: return "paperclip"
            }
        }
        
        static func from(mimeType: String) -> AttachmentType {
            let lower = mimeType.lowercased()
            if lower.hasPrefix("image/") { return .image }
            if lower.hasPrefix("video/") { return .video }
            if lower.hasPrefix("audio/") { return .audio }
            if lower == "application/pdf" { return .pdf }
            if lower.hasPrefix("application/") || lower.hasPrefix("text/") { return .document }
            return .other
        }
    }
    
    init(
        id: UUID = UUID(),
        type: AttachmentType,
        fileName: String,
        fileSize: Int64,
        mimeType: String,
        cloudKitAssetURL: String? = nil,
        localURL: String? = nil,
        thumbnailURL: String? = nil,
        uploadedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.fileName = fileName
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.cloudKitAssetURL = cloudKitAssetURL
        self.localURL = localURL
        self.thumbnailURL = thumbnailURL
        self.uploadedAt = uploadedAt
    }
    
    /// Formatta la dimensione del file
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

// MARK: - Chat Mention

/// Menzione in un messaggio (@utente, @riferimento, @assicurato)
struct ChatMention: Codable, Equatable, Hashable {
    enum MentionType: String, Codable {
        case user           // @mario.rossi@actsrl.it - menzione utente
        case riferimento    // @24/12345 - riferimento sinistro
        case assicurato     // @assicurato:24/12345 - assicurato del sinistro
    }
    
    let type: MentionType
    let value: String       // valore effettivo (email, riferimento, etc.)
    let displayText: String // testo visualizzato (@Mario Rossi, @24/12345, etc.)
    let range: Range<String.Index>? // posizione nel testo originale (non codificato)
    
    init(type: MentionType, value: String, displayText: String, range: Range<String.Index>? = nil) {
        self.type = type
        self.value = value
        self.displayText = displayText
        self.range = range
    }
    
    // Codable senza range (non serializzabile)
    enum CodingKeys: String, CodingKey {
        case type, value, displayText
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(MentionType.self, forKey: .type)
        self.value = try container.decode(String.self, forKey: .value)
        self.displayText = try container.decode(String.self, forKey: .displayText)
        self.range = nil
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(value, forKey: .value)
        try container.encode(displayText, forKey: .displayText)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(value)
        hasher.combine(displayText)
    }
    
    static func == (lhs: ChatMention, rhs: ChatMention) -> Bool {
        lhs.type == rhs.type && lhs.value == rhs.value && lhs.displayText == rhs.displayText
    }
}

// MARK: - Chat Hashtag

/// Hashtag in un messaggio (#chiusure, #sinistri, etc.)
struct ChatHashtag: Codable, Equatable, Hashable {
    let tag: String         // es. "chiusure", "sinistri", "aperti"
    let filter: String?     // sottofiltro opzionale (es. "studio", "utente")
    let range: Range<String.Index>? // posizione nel testo originale
    
    init(tag: String, filter: String? = nil, range: Range<String.Index>? = nil) {
        self.tag = tag
        self.filter = filter
        self.range = range
    }
    
    // Codable senza range
    enum CodingKeys: String, CodingKey {
        case tag, filter
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tag = try container.decode(String.self, forKey: .tag)
        self.filter = try container.decodeIfPresent(String.self, forKey: .filter)
        self.range = nil
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tag, forKey: .tag)
        try container.encodeIfPresent(filter, forKey: .filter)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
        hasher.combine(filter)
    }
    
    static func == (lhs: ChatHashtag, rhs: ChatHashtag) -> Bool {
        lhs.tag == rhs.tag && lhs.filter == rhs.filter
    }
    
    /// Hashtag predefiniti supportati
    static let predefinedTags: [String: String] = [
        "chiusure": "Sinistri chiusi",
        "sinistri": "Tutti i sinistri",
        "aperti": "Sinistri aperti",
        "assegnati": "Sinistri assegnati a me",
        "urgenti": "Sinistri urgenti",
        "scadenze": "Sinistri con scadenze imminenti"
    ]
}

// MARK: - Chat Room

/// Stanza/conversazione della chat
struct ChatRoom: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var participants: [String]          // email partecipanti
    var admins: [String]                // email admin del gruppo
    let createdAt: Date
    let createdBy: String               // email creatore
    var lastMessageAt: Date
    var lastMessagePreview: String?
    var lastMessageSender: String?      // nome mittente ultimo messaggio
    var unreadCount: Int
    var roomType: RoomType
    var avatarURL: String?              // URL avatar gruppo
    var linkedSinistroRif: String?      // Se la room è collegata a un sinistro specifico
    var isMuted: Bool                   // Notifiche disattivate
    
    enum RoomType: String, Codable {
        case direct = "direct"          // Chat 1:1
        case group = "group"            // Gruppo generico
        case sinistro = "sinistro"      // Chat collegata a sinistro
        case team = "team"              // Chat di team/studio
    }
    
    init(
        id: String = UUID().uuidString,
        name: String,
        participants: [String],
        admins: [String] = [],
        createdAt: Date = Date(),
        createdBy: String = "",
        lastMessageAt: Date = Date(),
        lastMessagePreview: String? = nil,
        lastMessageSender: String? = nil,
        unreadCount: Int = 0,
        roomType: RoomType = .direct,
        avatarURL: String? = nil,
        linkedSinistroRif: String? = nil,
        isMuted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.participants = participants
        self.admins = admins.isEmpty ? [createdBy] : admins
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.lastMessageAt = lastMessageAt
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageSender = lastMessageSender
        self.unreadCount = unreadCount
        self.roomType = roomType
        self.avatarURL = avatarURL
        self.linkedSinistroRif = linkedSinistroRif
        self.isMuted = isMuted
    }
    
    /// È una chat diretta (1:1)
    var isDirect: Bool {
        roomType == .direct || participants.count == 2
    }
    
    /// È un gruppo
    var isGroup: Bool {
        roomType == .group || roomType == .team || participants.count > 2
    }
    
    /// Nome visualizzato (se è una chat 1:1, mostra il nome dell'altro partecipante)
    func displayName(currentUserEmail: String?) -> String {
        guard let currentEmail = currentUserEmail?.lowercased() else { return name }
        
        // Se è una chat 1:1, mostra il nome dell'altro utente
        if isDirect {
            if let otherUser = participants.first(where: { $0.lowercased() != currentEmail }) {
                return formatUserName(otherUser)
            }
        }
        
        return name
    }
    
    /// Sottotitolo (es. "3 partecipanti" per gruppi)
    func subtitle(currentUserEmail: String?) -> String? {
        if isGroup {
            return "\(participants.count) partecipanti"
        }
        return nil
    }
    
    /// Verifica se l'utente è admin
    func isAdmin(_ email: String) -> Bool {
        admins.contains(where: { $0.lowercased() == email.lowercased() })
    }
    
    private func formatUserName(_ email: String) -> String {
        guard let namePart = email.components(separatedBy: "@").first else { return email }
        return namePart
            .replacingOccurrences(of: ".", with: " ")
            .capitalized
    }
}

// MARK: - Autocomplete Suggestion

/// Suggerimento per autocompletamento menzioni/hashtag
struct AutocompleteSuggestion: Identifiable, Equatable {
    enum SuggestionType {
        case user(email: String, name: String)
        case sinistro(riferimento: String, assicurato: String?)
        case assicurato(riferimento: String, nome: String)
        case hashtag(tag: String, description: String)
    }
    
    let id: String
    let type: SuggestionType
    let displayText: String
    let insertText: String
    let icon: String
    
    static func == (lhs: AutocompleteSuggestion, rhs: AutocompleteSuggestion) -> Bool {
        lhs.id == rhs.id
    }
}
