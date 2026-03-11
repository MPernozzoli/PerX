import Foundation
import PerXCore
import SQLite

/// Servizio per gestione notifiche cross-user
/// Quando una email arriva all'utente A ma riguarda un sinistro assegnato all'utente B,
/// notifica anche B e inserisce l'email nel thread del sinistro.
public actor CrossUserNotificationService {
    public static let shared = CrossUserNotificationService()
    
    // Cache sinistri -> user assignments
    private var sinistroAssignments: [String: SinistroAssignment] = [:]
    
    private init() {}
    
    // MARK: - Check & Notify
    
    /// Verifica se l'email deve essere notificata ad altri utenti
    public func checkAndNotifyCrossUser(email: ClassifiedEmail, accountId: String) async throws -> CrossUserNotification? {
        guard let sinistroRef = email.sinistroId else {
            return nil
        }
        
        // Ottieni assegnazione sinistro
        let assignment = try await getAssignment(sinistroRef: sinistroRef)
        
        guard let assignment = assignment else {
            return nil
        }
        
        // Se l'email è arrivata a un account diverso dal perito assegnato
        if accountId != assignment.assignedUserId {
            // Crea notifica cross-user
            let notification = CrossUserNotification(
                emailMessageId: email.originalEmail.id,
                sinistroRef: sinistroRef,
                receivedByUserId: accountId,
                assignedToUserId: assignment.assignedUserId,
                emailSubject: email.originalEmail.subject,
                emailDate: email.originalEmail.date,
                notificationType: .emailForOtherUserSinistro
            )
            
            // Salva notifica
            try await saveNotification(notification)
            
            // Inserisci email anche nel thread del sinistro dell'altro utente
            try await addToUserThread(email: email, userId: assignment.assignedUserId)
            
            print("[CrossUser] Notification created: \(email.originalEmail.id) -> \(assignment.assignedUserId)")
            
            return notification
        }
        
        return nil
    }
    
    /// Batch check per multiple email
    public func checkAndNotifyBatch(emails: [(ClassifiedEmail, String)]) async throws -> [CrossUserNotification] {
        var notifications: [CrossUserNotification] = []
        
        for (email, accountId) in emails {
            if let notification = try await checkAndNotifyCrossUser(email: email, accountId: accountId) {
                notifications.append(notification)
            }
        }
        
        return notifications
    }
    
    // MARK: - Assignment Management
    
    /// Ottiene assegnazione di un sinistro
    private func getAssignment(sinistroRef: String) async throws -> SinistroAssignment? {
        // Check cache
        if let cached = sinistroAssignments[sinistroRef] {
            return cached
        }
        
        // TODO: Query da CloudKit o database locale
        // Per ora ritorna nil - in produzione questo andrebbe a cercare
        // nel database dei sinistri chi è il perito assegnato
        
        return nil
    }
    
    /// Aggiorna cache assegnazioni
    public func updateAssignment(sinistroRef: String, userId: String) {
        sinistroAssignments[sinistroRef] = SinistroAssignment(
            sinistroRef: sinistroRef,
            assignedUserId: userId,
            updatedAt: Date()
        )
    }
    
    /// Pulisce cache
    public func clearCache() {
        sinistroAssignments.removeAll()
    }
    
    // MARK: - Thread Management
    
    /// Aggiunge email al thread di un utente
    private func addToUserThread(email: ClassifiedEmail, userId: String) async throws {
        let db = try await DatabaseManager.shared.db()
        
        // Aggiungi mapping email-account
        try db.run(DatabaseSchema.emailAccounts.insert(or: .ignore,
            DatabaseSchema.EmailAccountsColumns.messageId <- email.originalEmail.id,
            DatabaseSchema.EmailAccountsColumns.accountId <- userId,
            DatabaseSchema.EmailAccountsColumns.mailbox <- "cross_user",
            DatabaseSchema.EmailAccountsColumns.isRead <- false
        ))
    }
    
    // MARK: - Notifications
    
    private func saveNotification(_ notification: CrossUserNotification) async throws {
        // TODO: Salvare in tabella notifiche o inviare via push
        // Per ora solo log
        print("[CrossUser] Saved notification: \(notification.id)")
    }
    
    /// Ottiene notifiche pending per un utente
    public func getPendingNotifications(userId: String) async throws -> [CrossUserNotification] {
        // TODO: Query dal database
        return []
    }
    
    /// Marca notifica come letta
    public func markAsRead(notificationId: String) async throws {
        // TODO: Update nel database
    }
    
    // MARK: - Scheduled Message Notifications
    
    /// Notifica che una email programmata è stata inviata
    public func notifyScheduledEmailSent(scheduledId: String, sentMessageId: String) async {
        // Qui si potrebbe usare WebSocket o Server-Sent Events per notificare i client in real-time
        // Per ora usiamo un sistema di polling: i client controllano periodicamente lo stato
        
        // Salva evento in una tabella di eventi per i client
        print("[CrossUser] 📧 Scheduled email \(scheduledId) sent as \(sentMessageId)")
        
        // In futuro: Inviare push notification o WebSocket event
        await broadcastEvent(
            type: "scheduled_email_sent",
            payload: ["scheduledId": scheduledId, "messageId": sentMessageId]
        )
    }
    
    /// Notifica che una email programmata è fallita
    public func notifyScheduledEmailFailed(scheduledId: String, error: String) async {
        print("[CrossUser] ❌ Scheduled email \(scheduledId) failed: \(error)")
        
        await broadcastEvent(
            type: "scheduled_email_failed",
            payload: ["scheduledId": scheduledId, "error": error]
        )
    }
    
    /// Notifica che un messaggio WhatsApp programmato è stato inviato
    public func notifyScheduledWhatsAppSent(scheduledId: String, sentMessageId: String) async {
        print("[CrossUser] 📱 Scheduled WhatsApp \(scheduledId) sent as \(sentMessageId)")
        
        await broadcastEvent(
            type: "scheduled_whatsapp_sent",
            payload: ["scheduledId": scheduledId, "messageId": sentMessageId]
        )
    }
    
    /// Notifica che un messaggio WhatsApp programmato è fallito
    public func notifyScheduledWhatsAppFailed(scheduledId: String, error: String) async {
        print("[CrossUser] ❌ Scheduled WhatsApp \(scheduledId) failed: \(error)")
        
        await broadcastEvent(
            type: "scheduled_whatsapp_failed",
            payload: ["scheduledId": scheduledId, "error": error]
        )
    }
    
    // MARK: - Event Broadcasting
    
    /// Broadcast evento a tutti i client (per ora salva in tabella eventi)
    private func broadcastEvent(type: String, payload: [String: String]) async {
        // In produzione questo potrebbe essere:
        // 1. WebSocket broadcast
        // 2. Server-Sent Events
        // 3. Push notification
        // 4. Salvare in tabella eventi che i client polleranno
        
        // Per ora salviamo in memoria e i client polleranno /events/pending
        await EventBroadcaster.shared.addEvent(type: type, payload: payload)
    }
}

// MARK: - Event Broadcaster (in-memory per semplicità)

public actor EventBroadcaster {
    public static let shared = EventBroadcaster()
    
    private var pendingEvents: [BroadcastEvent] = []
    private let maxEvents = 100
    
    private init() {}
    
    public func addEvent(type: String, payload: [String: String]) {
        let event = BroadcastEvent(type: type, payload: payload)
        pendingEvents.append(event)
        
        // Mantieni solo gli ultimi N eventi
        if pendingEvents.count > maxEvents {
            pendingEvents.removeFirst(pendingEvents.count - maxEvents)
        }
    }
    
    public func getEventsSince(_ since: Date) -> [BroadcastEvent] {
        return pendingEvents.filter { $0.timestamp > since }
    }
    
    public func acknowledgeEvent(id: String) {
        pendingEvents.removeAll { $0.id == id }
    }
}

public struct BroadcastEvent: Codable, Identifiable, Sendable {
    public let id: String
    public let type: String
    public let payload: [String: String]
    public let timestamp: Date
    
    public init(type: String, payload: [String: String]) {
        self.id = UUID().uuidString
        self.type = type
        self.payload = payload
        self.timestamp = Date()
    }
}

// MARK: - Types

public struct SinistroAssignment: Codable {
    public let sinistroRef: String
    public let assignedUserId: String
    public let updatedAt: Date
}

public struct CrossUserNotification: Codable, Identifiable, Sendable {
    public let id: String
    public let emailMessageId: String
    public let sinistroRef: String
    public let receivedByUserId: String
    public let assignedToUserId: String
    public let emailSubject: String?
    public let emailDate: Date
    public let notificationType: NotificationType
    public let createdAt: Date
    public var isRead: Bool
    
    public init(
        id: String = UUID().uuidString,
        emailMessageId: String,
        sinistroRef: String,
        receivedByUserId: String,
        assignedToUserId: String,
        emailSubject: String?,
        emailDate: Date,
        notificationType: NotificationType,
        createdAt: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.emailMessageId = emailMessageId
        self.sinistroRef = sinistroRef
        self.receivedByUserId = receivedByUserId
        self.assignedToUserId = assignedToUserId
        self.emailSubject = emailSubject
        self.emailDate = emailDate
        self.notificationType = notificationType
        self.createdAt = createdAt
        self.isRead = isRead
    }
}

public enum NotificationType: String, Codable, Sendable {
    case emailForOtherUserSinistro   // Email arrivata a A per sinistro di B
    case documentShared               // Documento condiviso tra utenti
    case statusUpdate                 // Aggiornamento stato sinistro
    case reminder                     // Promemoria
}
