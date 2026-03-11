import Foundation

/// Salva le preferenze di visualizzazione per una singola casella di posta.
struct MailboxCustomization: Codable, Identifiable {
    /// Corrisponde all'ID dell'etichetta di Gmail.
    var id: String
    
    /// Nome personalizzato per la casella (se diverso dal default).
    var customName: String?
    
    /// Il nome dell'icona SF Symbol da visualizzare.
    var iconName: String
    
    /// Determina se la casella di posta deve essere visibile nel selettore.
    var isVisible: Bool
    
    /// Determina se mostrare il contatore delle email non lette.
    var showUnreadCount: Bool
} 