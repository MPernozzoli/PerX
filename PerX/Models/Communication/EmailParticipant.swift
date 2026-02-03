import Foundation

struct EmailParticipant: Identifiable, Hashable {
    let id: String
    let email: String
    let displayName: String
    
    init(id: String = UUID().uuidString, email: String, displayName: String) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }
    
    static func == (lhs: EmailParticipant, rhs: EmailParticipant) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
} 