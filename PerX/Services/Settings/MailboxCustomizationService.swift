import Foundation

/// Gestisce la persistenza delle personalizzazioni delle caselle di posta tramite UserDefaults.
class MailboxCustomizationService {
    
    static let shared = MailboxCustomizationService()
    private let userDefaultsKey = "MailboxCustomizations"
    private let defaults = UserDefaults.standard
    
    private init() {}
    
    /// Salva un intero dizionario di personalizzazioni.
    func saveCustomizations(_ customizations: [String: MailboxCustomization]) {
        do {
            let data = try JSONEncoder().encode(customizations)
            defaults.set(data, forKey: userDefaultsKey)
        } catch {
            print("Errore durante il salvataggio delle personalizzazioni delle caselle di posta: \(error)")
        }
    }
    
    /// Carica tutte le personalizzazioni salvate.
    func loadCustomizations() -> [String: MailboxCustomization] {
        guard let data = defaults.data(forKey: userDefaultsKey) else { return [:] }
        
        do {
            let customizations = try JSONDecoder().decode([String: MailboxCustomization].self, from: data)
            return customizations
        } catch {
            print("Errore durante il caricamento delle personalizzazioni delle caselle di posta: \(error)")
            return [:]
        }
    }
    
    /// Fornisce un'icona di default per le etichette di sistema più comuni.
    static func defaultIcon(for mailboxId: String) -> String {
        switch mailboxId {
        case "INBOX": return "tray.fill"
        case "SENT": return "paperplane.fill"
        case "SPAM": return "exclamationmark.triangle.fill"
        case "TRASH": return "trash.fill"
        case "DRAFT": return "doc.fill"
        case "IMPORTANT": return "exclamationmark.bubble.fill"
        case "STARRED": return "star.fill"
        // L'icona per la nostra casella "Principale"
        case "PRINCIPALE": return "house.fill"
        // Icona generica per tutte le etichette utente
        default: return "folder.fill"
        }
    }
} 