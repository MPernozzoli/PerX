import Foundation
import UserNotifications

class NotificationService {
    static let shared = NotificationService()
    
    private init() {
        requestAuthorization()
    }
    
    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[NotificationService] Errore autorizzazione: \(error)")
            }
        }
    }
    
    func sendNotification(title: String, body: String, userInfo: [String: Any]? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let userInfo = userInfo {
            content.userInfo = userInfo
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediate
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationService] Errore invio notifica: \(error)")
            }
        }
    }
    
    func sendAnalisiCompletataNotification(sinistro: Sinistro, beniCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = sinistro.riferimento ?? "Sinistro"
        content.body = "Analisi foto completata: \(beniCount) beni analizzati"
        content.sound = .default
        content.userInfo = [
            "sinistroID": sinistro.objectID.uriRepresentation().absoluteString,
            "type": "analisi_completata"
        ]
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediate
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationService] Errore invio notifica: \(error)")
            }
        }
    }
    
    // MARK: - Notifiche Chiusura Sinistro
    
    /// Notifica errore nella generazione dei file di chiusura
    func sendClosureErrorNotification(sinistro: Sinistro, errors: [String]) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Errore Chiusura - \(sinistro.riferimento ?? "Sinistro")"
        content.body = errors.joined(separator: "\n")
        content.sound = .default
        content.userInfo = [
            "sinistroID": sinistro.objectID.uriRepresentation().absoluteString,
            "type": "closure_error"
        ]
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationService] Errore invio notifica: \(error)")
            }
        }
    }
    
    /// Notifica file mancanti per la chiusura
    func sendMissingFilesNotification(sinistro: Sinistro, missingFiles: [String]) {
        let content = UNMutableNotificationContent()
        content.title = "📁 File Mancanti - \(sinistro.riferimento ?? "Sinistro")"
        content.body = "Mancano: \(missingFiles.joined(separator: ", "))"
        content.sound = .default
        content.userInfo = [
            "sinistroID": sinistro.objectID.uriRepresentation().absoluteString,
            "type": "missing_files"
        ]
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationService] Errore invio notifica: \(error)")
            }
        }
    }
}
