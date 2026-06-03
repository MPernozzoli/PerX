import Foundation
import AppKit

// MARK: - User Profile Model

/// Ruoli disponibili nell'app
enum UserRole: String, Codable, CaseIterable, Identifiable {
    case admin = "admin"
    case director = "direttore"
    case teamLeader = "capoTeam"
    case manager = "gestore"
    case expert = "perito"
    case cat = "cat"
    case secretary = "segreteria"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .admin: return "Amministratore"
        case .director: return "Direttore"
        case .teamLeader: return "Capo Team"
        case .manager: return "Gestore"
        case .expert: return "Perito"
        case .cat: return "CAT"
        case .secretary: return "Segreteria"
        }
    }
    
    var icon: String {
        switch self {
        case .admin: return "shield.checkered"
        case .director: return "crown"
        case .teamLeader: return "person.3"
        case .manager: return "tray.full"
        case .expert: return "briefcase"
        case .cat: return "mappin.and.ellipse"
        case .secretary: return "doc.text"
        }
    }
}

/// Tipo di contratto
enum ContractType: String, Codable, CaseIterable, Identifiable {
    case employee = "subordinato"
    case contractor = "collaboratore"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .employee: return "Dipendente"
        case .contractor: return "Collaboratore Esterno"
        }
    }
    
    var icon: String {
        switch self {
        case .employee: return "person.badge.clock"
        case .contractor: return "person.badge.key"
        }
    }
}

/// Visibilità della data di nascita
enum BirthdayVisibility: String, Codable, CaseIterable, Identifiable {
    case everyone = "tutti"
    case adminsOnly = "soloAdmin"
    case hidden = "nascosto"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .everyone: return "Visibile a tutti"
        case .adminsOnly: return "Solo Amministratori"
        case .hidden: return "Nascosto"
        }
    }
}

/// Tipo di avatar dell'utente
enum AvatarType: String, Codable {
    case photo
    case generated
    case gif
}

/// Avatar generato con colore e icona
struct GeneratedAvatar: Codable, Equatable {
    var backgroundColor: String // Hex color
    var icon: String // SF Symbol name
    
    static let `default` = GeneratedAvatar(
        backgroundColor: "#4A90D9",
        icon: "person.fill"
    )
    
    static let availableColors: [String] = [
        "#4A90D9", "#50C878", "#FF6B6B", "#FFD93D",
        "#6C5CE7", "#00CEC9", "#FF7675", "#FDCB6E",
        "#A29BFE", "#74B9FF", "#55EFC4", "#FFEAA7",
        "#DFE6E9", "#636E72", "#2D3436", "#E17055"
    ]
    
    static let availableIcons: [String] = [
        "person.fill", "star.fill", "heart.fill", "bolt.fill",
        "flame.fill", "leaf.fill", "cloud.fill", "moon.fill",
        "sun.max.fill", "sparkles", "crown.fill", "peacesign",
        "figure.wave", "cat.fill", "dog.fill", "hare.fill"
    ]
}

/// Profilo utente completo
struct UserProfile: Codable, Equatable, Identifiable {
    var id: String { email }
    
    // Identificazione (da Google)
    let email: String
    var personalEmail: String?
    var professionalEmail: String?
    var emailAliases: [String]
    var username: String // Auto-generato dalla mail, non modificabile
    
    // Dati personali
    var firstName: String
    var lastName: String
    var jobTitle: String?
    var phoneNumber: String?
    var birthDate: Date?
    var birthdayVisibility: BirthdayVisibility
    var notifyBirthday: Bool
    
    // Avatar
    var avatarType: AvatarType
    var avatarPhotoData: Data?
    var avatarAssetURL: String?
    var generatedAvatar: GeneratedAvatar
    var avatarGifURL: String?
    var signatureImageURL: String?
    
    // Lavoro
    var contractType: ContractType?
    var roles: [UserRole]

    // Comunicazioni / interni PerX
    var extensionNumber: String?
    var extensionEnabled: Bool?
    var extensionAssignedAt: Date?
    var extensionDisplayName: String?
    var availabilityStatus: AvailabilityStatus?
    var communicationStatus: CommunicationStatus?
    
    // Preferenze
    var enableBadges: Bool
    var sendReadReceipts: Bool
    var emailSignatureHTML: String?
    var emailSignatureText: String?
    
    // Metadata
    var createdAt: Date
    var updatedAt: Date
    
    // MARK: - Computed
    
    var displayName: String {
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return fullName.isEmpty ? username : fullName
    }
    
    var isPlatformAdmin: Bool {
        email.lowercased() == "info@pynkstudio.it"
    }

    var isAdmin: Bool {
        isPlatformAdmin || roles.contains(.admin)
    }

    var isTenantAdmin: Bool {
        roles.contains(.admin) || email.lowercased() == "admin@demo.com"
    }

    var canManageTenantSettings: Bool {
        isPlatformAdmin || isTenantAdmin
    }
    
    var canSeeAdminRole: Bool {
        isAdmin
    }
    
    var availableRoles: [UserRole] {
        if canSeeAdminRole {
            return UserRole.allCases
        }
        return UserRole.allCases.filter { $0 != .admin }
    }
    
    var birthdayToday: Bool {
        guard let birthDate = birthDate else { return false }
        let calendar = Calendar.current
        let today = Date()
        return calendar.component(.month, from: birthDate) == calendar.component(.month, from: today) &&
               calendar.component(.day, from: birthDate) == calendar.component(.day, from: today)
    }
    
    // MARK: - Init
    
    init(email: String) {
        self.email = email.lowercased()
        self.personalEmail = email.lowercased()
        self.professionalEmail = nil
        self.emailAliases = []
        self.username = Self.generateUsername(from: email)
        self.firstName = ""
        self.lastName = ""
        self.jobTitle = nil
        self.phoneNumber = nil
        self.birthDate = nil
        self.birthdayVisibility = .everyone
        self.notifyBirthday = true
        self.avatarType = .generated
        self.avatarPhotoData = nil
        self.avatarAssetURL = nil
        self.generatedAvatar = .default
        self.avatarGifURL = nil
        self.signatureImageURL = nil
        self.contractType = nil
        self.roles = []
        self.extensionNumber = nil
        self.extensionEnabled = false
        self.extensionAssignedAt = nil
        self.extensionDisplayName = nil
        self.availabilityStatus = .available
        self.communicationStatus = .idle
        self.enableBadges = false
        self.sendReadReceipts = true
        self.emailSignatureHTML = nil
        self.emailSignatureText = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// Formato valido: parola.parola (tutto attaccato, minuscolo, solo lettere/numeri e punti, no spazi)
    /// Es. massimo.pernozzoli ✓ | m.p ✓ | Massimo Pernozzoli ✗
    static func isValidUsername(_ username: String) -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return false }
        let parts = trimmed.split(separator: ".")
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber }
        }
    }
    
    static func generateUsername(from email: String) -> String {
        (email.components(separatedBy: "@").first ?? email).lowercased()
    }
    
    /// Restituisce username validato: se non conforme lo rigenera da email
    /// - Returns: (username validato, true se è stato rigenerato)
    static func validatedUsername(_ stored: String?, email: String) -> (String, Bool) {
        let generated = generateUsername(from: email)
        guard let s = stored?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else {
            return (generated, true)
        }
        if isValidUsername(s) { return (s, false) }
        return (generated, true)
    }
    
    // MARK: - Avatar Image
    
    var avatarImage: NSImage? {
        switch avatarType {
        case .photo:
            guard let data = avatarPhotoData else { return nil }
            return NSImage(data: data)
        case .generated, .gif:
            return nil
        }
    }
}
