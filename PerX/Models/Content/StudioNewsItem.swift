import Foundation

// MARK: - Birthday Messages

struct BirthdayMessages {
    static let messages: [String] = [
        "Tanti auguri! 🎂",
        "Buon compleanno! 🎉",
        "Augurissimi! 🎈",
        "Che sia un anno fantastico! ✨",
        "Un brindisi per te! 🥂",
        "Festa! 🎊",
        "Hip hip urrà! 🎁",
        "Compleanno in ufficio! 🎂",
    ]
    
    static func randomMessage() -> String {
        messages.randomElement() ?? "Buon compleanno! 🎂"
    }
}

// MARK: - Studio News CTA

struct StudioNewsCTA: Codable, Equatable {
    var title: String
    var deadline: Date?
    var taskType: String?
}

/// Tipo di news dello studio
enum StudioNewsType: String, Codable {
    case general       // News generica (email interna, annuncio)
    case birthday      // Compleanno di un collega
    case event         // Evento aziendale
    case announcement  // Comunicazione ufficiale
}

// MARK: - Studio News Item

struct StudioNewsItem: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let summary: String
    let createdAt: Date
    let eventDate: Date?
    let icon: String
    let sourceEmailId: String?
    let sourceBody: String?
    let sender: String?
    let cta: StudioNewsCTA?
    let newsType: StudioNewsType
    let userEmail: String? // Per i compleanni: email dell'utente festeggiato
    
    // MARK: - Init
    
    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        createdAt: Date = Date(),
        eventDate: Date? = nil,
        icon: String = "megaphone",
        sourceEmailId: String? = nil,
        sourceBody: String? = nil,
        sender: String? = nil,
        cta: StudioNewsCTA? = nil,
        newsType: StudioNewsType = .general,
        userEmail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
        self.eventDate = eventDate
        self.icon = icon
        self.sourceEmailId = sourceEmailId
        self.sourceBody = sourceBody
        self.sender = sender
        self.cta = cta
        self.newsType = newsType
        self.userEmail = userEmail
    }
    
    // MARK: - Codable (migrazione per vecchi dati)
    
    enum CodingKeys: String, CodingKey {
        case id, title, summary, createdAt, eventDate, icon
        case sourceEmailId, sourceBody, sender, cta
        case newsType, userEmail
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        eventDate = try container.decodeIfPresent(Date.self, forKey: .eventDate)
        icon = try container.decode(String.self, forKey: .icon)
        sourceEmailId = try container.decodeIfPresent(String.self, forKey: .sourceEmailId)
        sourceBody = try container.decodeIfPresent(String.self, forKey: .sourceBody)
        sender = try container.decodeIfPresent(String.self, forKey: .sender)
        cta = try container.decodeIfPresent(StudioNewsCTA.self, forKey: .cta)
        // Migrazione: newsType default a .general se non presente
        newsType = try container.decodeIfPresent(StudioNewsType.self, forKey: .newsType) ?? .general
        userEmail = try container.decodeIfPresent(String.self, forKey: .userEmail)
    }
    
    // MARK: - Computed Properties
    
    var isExpired: Bool {
        // I compleanni scadono alla fine del giorno
        if newsType == .birthday {
            let calendar = Calendar.current
            guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: createdAt) else {
                return true
            }
            return Date() > endOfDay
        }
        
        if let eventDate, eventDate < Date() {
            return true
        }
        return false
    }
    
    var isBirthday: Bool {
        newsType == .birthday
    }
    
    // MARK: - Factory Methods
    
    /// Crea una news di compleanno
    static func birthday(
        userName: String,
        userEmail: String,
        message: String? = nil
    ) -> StudioNewsItem {
        let birthdayMessage = message ?? BirthdayMessages.randomMessage()
        return StudioNewsItem(
            title: "È il compleanno di \(userName)! 🎂",
            summary: birthdayMessage,
            createdAt: Date(),
            eventDate: nil,
            icon: "gift.fill",
            sourceEmailId: nil,
            sourceBody: nil,
            sender: nil,
            cta: nil,
            newsType: .birthday,
            userEmail: userEmail
        )
    }
}
