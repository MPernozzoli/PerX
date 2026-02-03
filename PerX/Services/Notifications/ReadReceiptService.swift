import Foundation

/// Servizio per tracciare le letture delle email inviate
class ReadReceiptService {
    static let shared = ReadReceiptService()
    
    private let userDefaults = UserDefaults.standard
    private let readReceiptsKey = "readReceipts"
    private let authService = GoogleAuthService.shared
    
    private init() {}
    
    /// Verifica se un'email è stata letta dal destinatario
    func isEmailReadByRecipient(emailId: String, labelIds: [String]) -> Bool {
        // Un'email inviata è stata letta se:
        // 1. Ha il labelId "SENT" (è stata inviata da noi)
        // 2. NON ha il labelId "UNREAD" (è stata letta)
        let isSent = labelIds.contains("SENT")
        let isUnread = labelIds.contains("UNREAD")
        
        if isSent {
            return !isUnread
        }
        
        return false
    }
    
    /// Salva lo stato di lettura di un'email
    func saveReadStatus(emailId: String, isRead: Bool) {
        var receipts = getReadReceipts()
        receipts[emailId] = isRead
        userDefaults.set(receipts, forKey: readReceiptsKey)
    }
    
    /// Ottiene lo stato di lettura salvato
    func getReadStatus(emailId: String) -> Bool? {
        let receipts = getReadReceipts()
        return receipts[emailId]
    }
    
    private func getReadReceipts() -> [String: Bool] {
        return userDefaults.dictionary(forKey: readReceiptsKey) as? [String: Bool] ?? [:]
    }
    
    /// Verifica se un'email è stata inviata dall'utente corrente
    @MainActor
    func isEmailSentByUser(email: Email) -> Bool {
        guard let userEmail = authService.userEmail?.lowercased() else {
            return false
        }
        return email.sender.email.lowercased() == userEmail
    }
}

