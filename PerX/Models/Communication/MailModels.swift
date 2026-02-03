import Foundation

struct Email: Identifiable, Hashable, Codable {
    let id: String
    var isRead: Bool
    var isDownloaded: Bool?
    let sender: Contact
    let recipients: [Contact]
    let cc: [Contact]?
    let subject: String
    let date: Date
    var body: String?
    var attachments: [EmailAttachment]?
    let claimNumber: String?
    let insuredName: String?
    var associationStatus: EmailAssociationStatus?
    
    enum CodingKeys: String, CodingKey {
        case id, isRead, isDownloaded, sender, recipients, cc, subject, date, body, attachments, claimNumber, insuredName, associationStatus
    }
    
    init(id: String, isRead: Bool, isDownloaded: Bool? = nil, sender: Contact, recipients: [Contact], cc: [Contact]? = nil, subject: String, date: Date, body: String? = nil, attachments: [EmailAttachment]? = nil, claimNumber: String? = nil, insuredName: String? = nil, associationStatus: EmailAssociationStatus? = nil) {
        self.id = id
        self.isRead = isRead
        self.isDownloaded = isDownloaded
        self.sender = sender
        self.recipients = recipients
        self.cc = cc
        self.subject = subject
        self.date = date
        self.body = body
        self.attachments = attachments
        self.claimNumber = claimNumber
        self.insuredName = insuredName
        self.associationStatus = associationStatus
    }
    
    // Decodifica custom per default false
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        isRead = try container.decode(Bool.self, forKey: .isRead)
        isDownloaded = try container.decodeIfPresent(Bool.self, forKey: .isDownloaded) ?? false
        sender = try container.decode(Contact.self, forKey: .sender)
        recipients = try container.decode([Contact].self, forKey: .recipients)
        cc = try container.decodeIfPresent([Contact].self, forKey: .cc)
        subject = try container.decode(String.self, forKey: .subject)
        date = try container.decode(Date.self, forKey: .date)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        attachments = try container.decodeIfPresent([EmailAttachment].self, forKey: .attachments)
        claimNumber = try container.decodeIfPresent(String.self, forKey: .claimNumber)
        insuredName = try container.decodeIfPresent(String.self, forKey: .insuredName)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isRead, forKey: .isRead)
        try container.encode(isDownloaded ?? false, forKey: .isDownloaded)
        try container.encode(sender, forKey: .sender)
        try container.encode(recipients, forKey: .recipients)
        try container.encodeIfPresent(cc, forKey: .cc)
        try container.encode(subject, forKey: .subject)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(attachments, forKey: .attachments)
        try container.encodeIfPresent(claimNumber, forKey: .claimNumber)
        try container.encodeIfPresent(insuredName, forKey: .insuredName)
    }
}

struct EmailAttachment: Identifiable, Hashable, Codable {
    var id: String { attachmentId }
    let attachmentId: String
    let filename: String
    let size: Int // in bytes
}

enum EmailAssociationStatus: String, Codable {
    case associated
    case maybe
    case unassociated
}

struct Contact: Identifiable, Hashable, Codable {
    var id: String { email }
    let name: String?
    let email: String
    
    var displayName: String {
        name ?? email
    }
} 