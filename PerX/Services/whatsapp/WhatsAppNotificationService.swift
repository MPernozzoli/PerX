import Foundation
import UserNotifications
import AppKit

/// Servizio per gestire notifiche WhatsApp
@MainActor
class WhatsAppNotificationService: ObservableObject {
    static let shared = WhatsAppNotificationService()
    
    /// Chat attualmente attiva (non mostrare notifiche per questa)
    @Published var activeChatId: String?
    
    /// Polling interval (secondi)
    private let pollingInterval: TimeInterval = 15
    
    /// Timer per polling
    private var pollingTimer: Timer?
    
    /// Ultimo timestamp controllato per nuovi messaggi
    private var lastCheckTimestamp: Date = Date()
    
    /// ID degli ultimi messaggi notificati (per evitare duplicati) - persistito in UserDefaults
    private var notifiedMessageIds: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: "whatsapp_notified_message_ids") ?? [])
        }
        set {
            // Mantieni solo gli ultimi 500 per non crescere troppo
            let array = Array(newValue.suffix(500))
            UserDefaults.standard.set(array, forKey: "whatsapp_notified_message_ids")
        }
    }
    
    private init() {
        // Il delegate UNUserNotificationCenter è gestito da AppDelegate
    }
    
    /// Pulisce i messaggi notificati più vecchi di 7 giorni (chiamare periodicamente)
    func cleanupOldNotifiedMessages() {
        // Per ora manteniamo solo gli ultimi 500 (gestito nel setter)
    }
    
    // MARK: - Polling
    
    /// Avvia il polling per nuovi messaggi
    func startPolling() {
        guard pollingTimer == nil else { return }
        
        print("[WhatsAppNotification] Avvio polling ogni \(pollingInterval)s")
        
        // Timer periodico
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await CPUThrottler.shared.runWithThrottle {
                    await WhatsAppService.shared.checkStatus()
                    await self?.checkForNewMessages()
                }
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await CPUThrottler.shared.runWithThrottle {
                await WhatsAppService.shared.checkStatus()
                await checkForNewMessages()
            }
        }
    }
    
    /// Ferma il polling
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        print("[WhatsAppNotification] Polling fermato")
    }
    
    /// Controlla nuovi messaggi
    private func checkForNewMessages() async {
        let service = WhatsAppService.shared
        let viewModel = WhatsAppViewModel.shared
        
        print("[WhatsAppNotification] Check: accountId='\(service.selectedAccountId)', isConnected=\(service.isConnected), status=\(service.connectionStatus)")
        
        guard service.isConnected else {
            print("[WhatsAppNotification] Skip polling: WhatsApp non connesso")
            return
        }
        
        do {
            let chats = try await WhatsAppService.shared.fetchChats()
            print("[WhatsAppNotification] Polling: trovate \(chats.count) chat")
            
            // Aggiorna la lista chat nel ViewModel per aggiornare la UI
            viewModel.updateChats(chats)
            
            let unreadChats = chats.filter { $0.unreadCount > 0 }
            if !unreadChats.isEmpty {
                print("[WhatsAppNotification] Chat con messaggi non letti: \(unreadChats.map { "\($0.name): \($0.unreadCount)" })")
            }
            
            for chat in unreadChats {
                // Non notificare se è la chat attiva
                if chat.id == activeChatId {
                    print("[WhatsAppNotification] Skip chat attiva: \(chat.name)")
                    // Ma aggiorna comunque i messaggi nella UI
                    if viewModel.selectedChatId == chat.id {
                        await viewModel.fetchMessages(for: chat.id)
                    }
                    continue
                }
                
                // Fetch messaggi recenti per questa chat
                let messages = try await WhatsAppService.shared.fetchMessages(chatId: chat.id, limit: 5)
                
                // Solo messaggi in entrata: nessuna notifica UI per messaggi in uscita (anche da altro dispositivo)
                var currentIds = notifiedMessageIds
                for message in messages {
                    guard !message.isFromMe else { continue } // out: salvati silent, in UI solo se chat aperta
                    if !currentIds.contains(message.id) {
                        print("[WhatsAppNotification] 🔔 Nuova notifica: \(chat.name) - \(message.body.prefix(30))")
                        sendNotification(for: message, chat: chat)
                        currentIds.insert(message.id)
                    }
                }
                notifiedMessageIds = currentIds
            }
            
            // Chat aperta: aggiorna messaggi (inclusi quelli in uscita arrivati da altro dispositivo)
            if let selectedChatId = viewModel.selectedChatId {
                await viewModel.fetchMessages(for: selectedChatId)
            }
        } catch {
            print("[WhatsAppNotification] Errore polling: \(error)")
        }
    }
    
    // MARK: - Notifiche
    
    /// Invia notifica locale per un messaggio
    func sendNotification(for message: WhatsAppMessage, chat: WhatsAppChat) {
        let content = UNMutableNotificationContent()
        
        // Titolo: nome chat o numero
        content.title = "💬 \(chat.name)"
        
        // Corpo: anteprima messaggio
        let bodyPreview: String
        switch message.type {
        case .image:
            bodyPreview = "📷 Foto"
        case .video:
            bodyPreview = "🎥 Video"
        case .audio, .ptt:
            bodyPreview = "🎤 Messaggio vocale"
        case .document:
            bodyPreview = "📄 Documento"
        case .sticker:
            bodyPreview = "🏷️ Sticker"
        case .location:
            bodyPreview = "📍 Posizione"
        case .contact:
            bodyPreview = "👤 Contatto"
        default:
            bodyPreview = message.body.isEmpty ? "[Messaggio]" : String(message.body.prefix(100))
        }
        content.body = bodyPreview
        
        content.sound = .default
        content.categoryIdentifier = "WHATSAPP_MESSAGE"
        
        // UserInfo per gestire il click
        content.userInfo = [
            "type": "whatsapp_message",
            "chatId": chat.id,
            "chatName": chat.name,
            "phoneNumber": chat.phoneNumber ?? "",
            "messageId": message.id,
            "sinistroRef": chat.sinistroRiferimento ?? ""
        ]
        
        // Thread identifier per raggruppare notifiche della stessa chat
        content.threadIdentifier = "whatsapp-\(chat.id)"
        
        let request = UNNotificationRequest(
            identifier: "whatsapp-\(message.id)",
            content: content,
            trigger: nil // Immediata
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[WhatsAppNotification] Errore invio notifica: \(error)")
            } else {
                print("[WhatsAppNotification] Notifica inviata per messaggio da \(chat.name)")
            }
        }
    }
    
    /// Notifica manuale per messaggio in arrivo (chiamata dall'esterno). Messaggi in uscita: mai notifica, solo silent in memoria/UI se chat aperta.
    func notifyNewMessage(chatId: String, chatName: String, messageBody: String, phoneNumber: String, sinistroRef: String?, isOutgoing: Bool = false) {
        guard !isOutgoing else { return }
        guard chatId != activeChatId else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "💬 \(chatName)"
        content.body = messageBody.isEmpty ? "[Messaggio]" : String(messageBody.prefix(100))
        content.sound = .default
        content.categoryIdentifier = "WHATSAPP_MESSAGE"
        
        content.userInfo = [
            "type": "whatsapp_message",
            "chatId": chatId,
            "chatName": chatName,
            "phoneNumber": phoneNumber,
            "sinistroRef": sinistroRef ?? ""
        ]
        
        content.threadIdentifier = "whatsapp-\(chatId)"
        
        let request = UNNotificationRequest(
            identifier: "whatsapp-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Click Handler
    
    /// Apre la finestra chat per un chatId specifico
    func openChatWindow(chatId: String, chatName: String, phoneNumber: String, sinistroRef: String?) {
        Task { @MainActor in
            // Cerca la chat completa
            var chat: WhatsAppChat?
            
            do {
                let chats = try await WhatsAppService.shared.fetchChats()
                chat = chats.first { $0.id == chatId }
            } catch {
                print("[WhatsAppNotification] Errore recupero chat: \(error)")
            }
            
            // Se non trovata, crea una chat temporanea
            let targetChat = chat ?? WhatsAppChat(
                id: chatId,
                name: chatName,
                phoneNumber: phoneNumber,
                isGroup: false,
                unreadCount: 0,
                sinistroRiferimento: sinistroRef
            )
            
            // Apri finestra WhatsApp
            let windowId = "whatsapp-detail-\(chatId)"
            
            // Crea la view
            let detailView = WhatsAppChatWindowView(chat: targetChat)
            
            WindowManager.shared.openWindow(
                identifier: windowId,
                content: detailView,
                configuration: WindowConfiguration(
                    identifier: windowId,
                    title: "WhatsApp - \(chatName)",
                    minSize: CGSize(width: 500, height: 600),
                    defaultSize: CGSize(width: 600, height: 800)
                )
            )
            
            // Porta l'app in primo piano
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            print("[WhatsAppNotification] Aperta finestra chat: \(chatName)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

// Nota: Il delegate UNUserNotificationCenterDelegate è gestito in AppDelegate (PerXApp.swift)
