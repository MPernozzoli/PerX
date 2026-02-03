import Foundation

/// Categorie di email riconosciute dal sistema
enum EmailCategory: String, CaseIterable, Codable {
    // MARK: - Inbound from Company
    case assignment = "assignment"                    // Assegnazione perito
    case revocation = "revocation"                    // Revoca incarico
    case controlled = "controlled"                    // Perizia controllata
    case revisionRequested = "revision_requested"     // Richiesta revisione
    
    // MARK: - Documentation
    case documentationRequest = "documentation_request"   // Richiesta documentazione
    case documentationReceived = "documentation_received" // Documentazione ricevuta
    
    // MARK: - Reminders
    case reminderReceived = "reminder_received"       // Sollecito ricevuto
    case reminderSent = "reminder_sent"               // Sollecito inviato
    
    // MARK: - Survey
    case surveyScheduled = "survey_scheduled"         // Sopralluogo fissato
    case surveyReturned = "survey_returned"           // Sopralluogo restituito
    case videocallScheduled = "videocall_scheduled"   // Videoperizia fissata
    
    // MARK: - Acts
    case actSent = "act_sent"                         // Atto da firmare inviato
    case actReceived = "act_received"                 // Atto firmato ricevuto
    
    // MARK: - Clarification
    case clarificationRequest = "clarification_request" // Richiesta chiarimenti
    
    // MARK: - Outcome
    case outcomeSent = "outcome_sent"                 // Esito comunicato
    case verbalAcceptance = "verbal_acceptance"       // Accettazione verbale assicurato
    
    // MARK: - Generic
    case genericCommunication = "generic"             // Comunicazione generica
    
    // MARK: - Studio (non sinistro)
    case studioNews = "studio_news"                   // Notizie dello studio
    case internalInfo = "internal_info"               // Info interne
    case procedure = "procedure"                      // Procedure
    case meeting = "meeting"                          // Riunioni
    case training = "training"                        // Formazione
    case administrative = "administrative"            // Amministrativo (fatture, pagamenti)
    case newsletter = "newsletter"                    // Newsletter
    case spam = "spam"                                // Spam/Pubblicità
    
    // MARK: - Properties
    
    /// Descrizione user-friendly
    var displayName: String {
        switch self {
        case .assignment: return "Assegnazione"
        case .revocation: return "Revoca"
        case .controlled: return "Perizia controllata"
        case .revisionRequested: return "Richiesta revisione"
        case .documentationRequest: return "Richiesta documentazione"
        case .documentationReceived: return "Documentazione ricevuta"
        case .reminderReceived: return "Sollecito ricevuto"
        case .reminderSent: return "Sollecito inviato"
        case .surveyScheduled: return "Sopralluogo fissato"
        case .surveyReturned: return "Sopralluogo restituito"
        case .videocallScheduled: return "Videoperizia fissata"
        case .actSent: return "Atto inviato"
        case .actReceived: return "Atto firmato ricevuto"
        case .clarificationRequest: return "Richiesta chiarimenti"
        case .outcomeSent: return "Esito comunicato"
        case .verbalAcceptance: return "Accettazione verbale"
        case .genericCommunication: return "Comunicazione generica"
        case .studioNews: return "Notizie studio"
        case .internalInfo: return "Info interne"
        case .procedure: return "Procedure"
        case .meeting: return "Riunione"
        case .training: return "Formazione"
        case .administrative: return "Amministrativo"
        case .newsletter: return "Newsletter"
        case .spam: return "Spam"
        }
    }
    
    /// Icona SF Symbol
    var iconName: String {
        switch self {
        case .assignment: return "plus.circle.fill"
        case .revocation: return "xmark.circle.fill"
        case .controlled: return "checkmark.seal.fill"
        case .revisionRequested: return "arrow.triangle.2.circlepath"
        case .documentationRequest: return "doc.badge.clock"
        case .documentationReceived: return "doc.badge.checkmark"
        case .reminderReceived: return "bell.badge.fill"
        case .reminderSent: return "bell.fill"
        case .surveyScheduled: return "calendar.badge.clock"
        case .surveyReturned: return "arrow.uturn.left.circle"
        case .videocallScheduled: return "video.badge.checkmark"
        case .actSent: return "doc.text.fill"
        case .actReceived: return "signature"
        case .clarificationRequest: return "questionmark.circle"
        case .outcomeSent: return "checkmark.message"
        case .verbalAcceptance: return "hand.thumbsup.fill"
        case .genericCommunication: return "envelope"
        case .studioNews: return "newspaper.fill"
        case .internalInfo: return "info.circle.fill"
        case .procedure: return "list.clipboard.fill"
        case .meeting: return "person.3.fill"
        case .training: return "graduationcap.fill"
        case .administrative: return "banknote.fill"
        case .newsletter: return "scroll.fill"
        case .spam: return "xmark.bin.fill"
        }
    }
    
    /// Direzioni possibili per questa categoria
    var possibleDirections: [EmailDirection] {
        switch self {
        case .assignment, .revocation, .controlled, .revisionRequested,
             .reminderReceived, .surveyReturned, .actReceived, .verbalAcceptance:
            return [.inbound]
        case .reminderSent, .actSent, .outcomeSent:
            return [.outbound]
        case .documentationRequest, .documentationReceived, .surveyScheduled,
             .videocallScheduled, .clarificationRequest, .genericCommunication,
             .studioNews, .internalInfo, .procedure, .meeting, .training,
             .administrative, .newsletter, .spam:
            return [.inbound, .outbound]
        }
    }
    
    /// Priorità di base per task generate da questa categoria
    var basePriority: Double {
        switch self {
        case .assignment: return 0.9
        case .revocation: return 1.0
        case .revisionRequested: return 0.85
        case .controlled: return 0.5
        case .reminderReceived: return 0.8
        case .actReceived: return 0.75
        case .verbalAcceptance: return 0.75
        case .documentationReceived: return 0.7
        case .clarificationRequest: return 0.65
        case .surveyReturned: return 0.6
        case .surveyScheduled, .videocallScheduled: return 0.55
        case .meeting: return 0.7  // Riunioni hanno priorità alta
        case .training: return 0.6
        case .administrative: return 0.5
        case .studioNews, .internalInfo, .procedure: return 0.4
        case .newsletter, .spam: return 0.1
        default: return 0.5
        }
    }
    
    /// Indica se la categoria è legata a un sinistro
    var isSinistroRelated: Bool {
        switch self {
        case .studioNews, .internalInfo, .procedure, .meeting, .training,
             .administrative, .newsletter, .spam:
            return false
        default:
            return true
        }
    }
}

/// Risultato della classificazione email
struct ClassifiedEmail {
    let originalEmail: Email
    let category: EmailCategory
    let direction: EmailDirection
    let senderType: EmailSenderType
    let sinistroId: String?
    let confidence: Double
    let matchedPatterns: [String]
    
    /// Email ha allegati
    var hasAttachments: Bool {
        return originalEmail.attachments?.isEmpty == false
    }
    
    /// Tipi di allegati
    var attachmentTypes: [String] {
        return originalEmail.attachments?.compactMap { attachment in
            // Estrai estensione dal nome file
            let filename = attachment.filename
            return (filename as NSString).pathExtension.lowercased()
        } ?? []
    }
}

