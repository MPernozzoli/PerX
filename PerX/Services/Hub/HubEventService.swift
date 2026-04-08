import Foundation
import Combine

/// Servizio per polling eventi dall'Hub (scheduled sent/failed)
@MainActor
class HubEventService: ObservableObject {
    static let shared = HubEventService()
    
    // Eventi ricevuti
    @Published var scheduledEmailsSent: [String: String] = [:] // scheduledId -> sentMessageId
    @Published var scheduledEmailsFailed: [String: String] = [:] // scheduledId -> error
    @Published var scheduledWhatsAppSent: [String: String] = [:] // scheduledId -> sentMessageId
    @Published var scheduledWhatsAppFailed: [String: String] = [:] // scheduledId -> error
    
    private let cloudClient = HubAPIAdapterClient.shared
    private var pollingTask: Task<Void, Never>?
    private var lastEventTimestamp: Date = Date().addingTimeInterval(-60) // Ultimi 60 secondi
    
    private init() {}
    
    // MARK: - Start/Stop
    
    func startPolling() {
        guard pollingTask == nil else { return }
        
        pollingTask = Task {
            while !Task.isCancelled {
                await pollEvents()
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 secondi
            }
        }
        
        print("[HubEventService] Started polling")
    }
    
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        print("[HubEventService] Stopped polling")
    }
    
    // MARK: - Polling
    
    private func pollEvents() async {
        do {
            let sinceTimestamp = lastEventTimestamp.timeIntervalSince1970
            let events: [HubEvent] = try await cloudClient.cloudGet("/api/v1/hub/internal/events?since=\(sinceTimestamp)")
            
            for event in events {
                processEvent(event)
                
                // Aggiorna timestamp
                if event.timestamp > lastEventTimestamp {
                    lastEventTimestamp = event.timestamp
                }
            }
            
        } catch {
            // Silently ignore polling errors
        }
    }
    
    private func processEvent(_ event: HubEvent) {
        switch event.type {
        case "scheduled_email_sent":
            if let scheduledId = event.payload["scheduledId"],
               let messageId = event.payload["messageId"] {
                scheduledEmailsSent[scheduledId] = messageId
                print("[HubEventService] 📧 Email programmata inviata: \(scheduledId)")
                
                // Notifica locale
                NotificationCenter.default.post(
                    name: .scheduledEmailSent,
                    object: nil,
                    userInfo: ["scheduledId": scheduledId, "messageId": messageId]
                )
            }
            
        case "scheduled_email_failed":
            if let scheduledId = event.payload["scheduledId"],
               let error = event.payload["error"] {
                scheduledEmailsFailed[scheduledId] = error
                print("[HubEventService] ❌ Email programmata fallita: \(scheduledId)")
                
                NotificationCenter.default.post(
                    name: .scheduledEmailFailed,
                    object: nil,
                    userInfo: ["scheduledId": scheduledId, "error": error]
                )
            }
            
        case "scheduled_whatsapp_sent":
            if let scheduledId = event.payload["scheduledId"],
               let messageId = event.payload["messageId"] {
                scheduledWhatsAppSent[scheduledId] = messageId
                print("[HubEventService] 📱 WhatsApp programmato inviato: \(scheduledId)")
                
                NotificationCenter.default.post(
                    name: .scheduledWhatsAppSent,
                    object: nil,
                    userInfo: ["scheduledId": scheduledId, "messageId": messageId]
                )
            }
            
        case "scheduled_whatsapp_failed":
            if let scheduledId = event.payload["scheduledId"],
               let error = event.payload["error"] {
                scheduledWhatsAppFailed[scheduledId] = error
                print("[HubEventService] ❌ WhatsApp programmato fallito: \(scheduledId)")
                
                NotificationCenter.default.post(
                    name: .scheduledWhatsAppFailed,
                    object: nil,
                    userInfo: ["scheduledId": scheduledId, "error": error]
                )
            }
            
        default:
            break
        }
    }
    
    // MARK: - Query State
    
    func isEmailSent(scheduledId: String) -> Bool {
        scheduledEmailsSent[scheduledId] != nil
    }
    
    func isEmailFailed(scheduledId: String) -> Bool {
        scheduledEmailsFailed[scheduledId] != nil
    }
    
    func isWhatsAppSent(scheduledId: String) -> Bool {
        scheduledWhatsAppSent[scheduledId] != nil
    }
    
    func isWhatsAppFailed(scheduledId: String) -> Bool {
        scheduledWhatsAppFailed[scheduledId] != nil
    }
}

// MARK: - Models

struct HubEvent: Codable {
    let id: String
    let type: String
    let payload: [String: String]
    let timestamp: Date
}

// MARK: - Notification Names

extension Notification.Name {
    static let scheduledEmailSent = Notification.Name("scheduledEmailSent")
    static let scheduledEmailFailed = Notification.Name("scheduledEmailFailed")
    static let scheduledWhatsAppSent = Notification.Name("scheduledWhatsAppSent")
    static let scheduledWhatsAppFailed = Notification.Name("scheduledWhatsAppFailed")
}
