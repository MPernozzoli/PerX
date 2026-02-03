import Foundation
import CloudKit
import UserNotifications

/// Servizio per l'invio di notifiche push quando un sinistro viene reclamato da un altro utente.
/// Le notifiche vengono salvate su CloudKit e il client destinatario le riceve tramite polling o subscription.
@MainActor
final class SinistroReclaimNotificationService {
    static let shared = SinistroReclaimNotificationService()
    
    private let container: CKContainer
    private let publicDB: CKDatabase
    
    private enum RecordType {
        static let reclaimNotification = "ReclaimNotification"
    }
    
    private enum Keys {
        static let notificationId = "notificationId"
        static let targetUserEmail = "targetUserEmail"
        static let reclaimedByEmail = "reclaimedByEmail"
        static let reclaimedByName = "reclaimedByName"
        static let sinistroRiferimento = "sinistroRiferimento"
        static let nomeAssicurato = "nomeAssicurato"
        static let createdAt = "createdAt"
        static let isRead = "isRead"
    }
    
    private init(container: CKContainer = CKContainer(identifier: "iCloud.it.pernozzoli.PerX")) {
        self.container = container
        self.publicDB = container.publicCloudDatabase
    }
    
    // MARK: - Send Notification
    
    /// Invia una notifica di reclamo sinistro all'utente precedente
    /// - Parameters:
    ///   - toUserEmail: Email dell'utente che ha perso il sinistro
    ///   - reclaimedByName: Nome dell'utente che ha reclamato
    ///   - riferimento: Riferimento del sinistro
    ///   - nomeAssicurato: Nome dell'assicurato
    func sendReclaimNotification(
        toUserEmail: String,
        reclaimedByName: String,
        riferimento: String,
        nomeAssicurato: String
    ) async {
        let notificationId = UUID().uuidString
        let now = Date()
        
        let recordID = CKRecord.ID(recordName: notificationId)
        let record = CKRecord(recordType: RecordType.reclaimNotification, recordID: recordID)
        
        record[Keys.notificationId] = notificationId as CKRecordValue
        record[Keys.targetUserEmail] = toUserEmail.lowercased() as CKRecordValue
        record[Keys.reclaimedByEmail] = (GoogleAuthService.shared.userEmail ?? "").lowercased() as CKRecordValue
        record[Keys.reclaimedByName] = reclaimedByName as CKRecordValue
        record[Keys.sinistroRiferimento] = riferimento as CKRecordValue
        record[Keys.nomeAssicurato] = nomeAssicurato as CKRecordValue
        record[Keys.createdAt] = now as CKRecordValue
        record[Keys.isRead] = false as CKRecordValue
        
        do {
            _ = try await publicDB.saveRecordAsync(record)
            print("[ReclaimNotification] ✅ Notifica inviata a \(toUserEmail) per sinistro \(riferimento)")
        } catch {
            print("[ReclaimNotification] ❌ Errore invio notifica: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Fetch Pending Notifications
    
    /// Scarica le notifiche di reclamo pending per l'utente corrente
    func fetchPendingNotifications() async -> [ReclaimNotification] {
        guard let currentEmail = GoogleAuthService.shared.userEmail?.lowercased() else {
            return []
        }
        
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %@", Keys.targetUserEmail, currentEmail),
            NSPredicate(format: "%K == %@", Keys.isRead, NSNumber(value: false))
        ])
        
        let query = CKQuery(recordType: RecordType.reclaimNotification, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: Keys.createdAt, ascending: false)]
        
        do {
            let records = try await publicDB.performQueryAsync(query)
            return records.compactMap { record -> ReclaimNotification? in
                guard let notificationId = record[Keys.notificationId] as? String,
                      let reclaimedByName = record[Keys.reclaimedByName] as? String,
                      let riferimento = record[Keys.sinistroRiferimento] as? String,
                      let nomeAssicurato = record[Keys.nomeAssicurato] as? String,
                      let createdAt = record[Keys.createdAt] as? Date else {
                    return nil
                }
                
                return ReclaimNotification(
                    id: notificationId,
                    reclaimedByName: reclaimedByName,
                    riferimento: riferimento,
                    nomeAssicurato: nomeAssicurato,
                    createdAt: createdAt
                )
            }
        } catch {
            print("[ReclaimNotification] ❌ Errore fetch notifiche: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Marca una notifica come letta
    func markAsRead(notificationId: String) async {
        let recordID = CKRecord.ID(recordName: notificationId)
        
        do {
            let record = try await publicDB.fetchRecordAsync(recordID)
            record[Keys.isRead] = true as CKRecordValue
            _ = try await publicDB.saveRecordAsync(record)
            print("[ReclaimNotification] ✅ Notifica \(notificationId) marcata come letta")
        } catch {
            print("[ReclaimNotification] ❌ Errore marking read: \(error.localizedDescription)")
        }
    }
    
    /// Controlla notifiche pending e mostra alert locali
    func checkAndShowLocalNotifications() async {
        let notifications = await fetchPendingNotifications()
        
        for notification in notifications {
            showLocalNotification(notification)
            await markAsRead(notificationId: notification.id)
        }
    }
    
    /// Mostra una notifica locale all'utente
    private func showLocalNotification(_ notification: ReclaimNotification) {
        let content = UNMutableNotificationContent()
        content.title = "Sinistro reclamato"
        content.body = "\(notification.reclaimedByName) ha richiesto la gestione del sinistro \(notification.riferimento) di \(notification.nomeAssicurato)."
        content.sound = .default
        content.userInfo = [
            "type": "sinistro_reclaimed",
            "riferimento": notification.riferimento
        ]
        
        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: nil // Immediate
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[ReclaimNotification] ❌ Errore notifica locale: \(error)")
            } else {
                print("[ReclaimNotification] 📢 Notifica locale mostrata per sinistro \(notification.riferimento)")
            }
        }
    }
}

// MARK: - Model

struct ReclaimNotification: Identifiable {
    let id: String
    let reclaimedByName: String
    let riferimento: String
    let nomeAssicurato: String
    let createdAt: Date
}
