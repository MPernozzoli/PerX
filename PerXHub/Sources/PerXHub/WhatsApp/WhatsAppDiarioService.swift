import Foundation

/// Servizio per raggruppare messaggi WhatsApp in entry di diario
/// Raggruppa tutti i messaggi (in/out) entro 24 ore dal primo come una conversazione
public actor WhatsAppDiarioService {
    public static let shared = WhatsAppDiarioService()
    
    /// Finestra temporale per raggruppare messaggi (24 ore)
    private let groupingWindow: TimeInterval = 86400 // 24 ore
    
    /// Cache conversazioni aperte (sinistroRef -> conversazione)
    private var openConversations: [String: WhatsAppConversation] = [:]
    
    private init() {}
    
    /// Processa un nuovo messaggio WhatsApp e lo aggiunge alla conversazione appropriata
    public func processMessage(
        sinistroRef: String,
        chatId: String,
        messageBody: String?,
        direction: String,
        timestamp: Date,
        fromNumber: String,
        toNumber: String?
    ) async {
        // Crea il messaggio
        let message = ConversationMessage(
            body: messageBody ?? "[media]",
            direction: direction,
            timestamp: timestamp,
            fromNumber: fromNumber,
            toNumber: toNumber
        )
        
        // Chiave conversazione: sinistroRef + chatId
        let conversationKey = "\(sinistroRef)_\(chatId)"
        
        if var conversation = openConversations[conversationKey] {
            // Verifica se la conversazione è ancora nella finestra temporale
            let timeSinceStart = timestamp.timeIntervalSince(conversation.startedAt)
            
            if timeSinceStart <= groupingWindow {
                // Aggiungi messaggio alla conversazione esistente
                conversation.messages.append(message)
                conversation.lastMessageAt = timestamp
                openConversations[conversationKey] = conversation
                
                print("[WhatsAppDiario] 📝 Messaggio aggiunto a conversazione esistente: \(conversationKey)")
            } else {
                // Finestra scaduta: chiudi la vecchia e aprine una nuova
                await closeConversation(key: conversationKey, conversation: conversation)
                
                // Crea nuova conversazione
                let newConversation = WhatsAppConversation(
                    sinistroRef: sinistroRef,
                    chatId: chatId,
                    startedAt: timestamp,
                    lastMessageAt: timestamp,
                    messages: [message]
                )
                openConversations[conversationKey] = newConversation
                
                print("[WhatsAppDiario] 🆕 Nuova conversazione dopo timeout: \(conversationKey)")
            }
        } else {
            // Prima conversazione per questa chiave
            let newConversation = WhatsAppConversation(
                sinistroRef: sinistroRef,
                chatId: chatId,
                startedAt: timestamp,
                lastMessageAt: timestamp,
                messages: [message]
            )
            openConversations[conversationKey] = newConversation
            
            print("[WhatsAppDiario] 🆕 Nuova conversazione: \(conversationKey)")
        }
        
        // Aggiorna/crea entry diario (debounced - ogni 5 messaggi o ogni minuto)
        if let conversation = openConversations[conversationKey],
           conversation.messages.count % 5 == 0 || conversation.needsSync {
            await syncConversationToDiario(key: conversationKey, conversation: conversation)
        }
    }
    
    /// Chiude una conversazione e la salva definitivamente nel diario
    private func closeConversation(key: String, conversation: WhatsAppConversation) async {
        await syncConversationToDiario(key: key, conversation: conversation, isFinal: true)
        openConversations.removeValue(forKey: key)
        
        print("[WhatsAppDiario] ✅ Conversazione chiusa e salvata: \(key)")
    }
    
    /// Sincronizza una conversazione con il diario
    private func syncConversationToDiario(key: String, conversation: WhatsAppConversation, isFinal: Bool = false) async {
        do {
            // Genera riassunto
            let summary = generateSummary(conversation: conversation)
            let fullContent = generateFullContent(conversation: conversation, isFinal: isFinal)
            
            // Genera ID deterministico basato su sinistroRef + chatId + data inizio
            // Così aggiorniamo sempre la stessa entry invece di crearne di nuove
            let entryIdString = "\(conversation.sinistroRef)_\(conversation.chatId)_\(Int(conversation.startedAt.timeIntervalSince1970))"
            let entryId = UUID(uuidString: entryIdString.md5UUID()) ?? UUID()
            
            // Salva entry diario
            try await CloudKitSyncManager.shared.saveDiarioEntry(
                entryId: entryId,
                sinistroRef: conversation.sinistroRef,
                timestamp: conversation.startedAt,
                tipo: "conversazione_whatsapp",
                titolo: "💬 WhatsApp - \(formatPhoneNumber(conversation.chatId))",
                riassunto: summary,
                contenutoCompleto: fullContent,
                createdBy: "PerXHub"
            )
            
            print("[WhatsAppDiario] ☁️ Diario sincronizzato: \(conversation.sinistroRef) (\(conversation.messages.count) msg)")
        } catch {
            print("[WhatsAppDiario] ❌ Errore sync diario: \(error)")
        }
    }
    
    /// Genera un riassunto breve della conversazione
    private func generateSummary(conversation: WhatsAppConversation) -> String {
        let inCount = conversation.messages.filter { $0.direction == "in" }.count
        let outCount = conversation.messages.filter { $0.direction == "out" }.count
        
        // Prendi i primi 100 caratteri del primo messaggio in uscita (o in entrata)
        let firstOutMessage = conversation.messages.first { $0.direction == "out" }?.body
        let firstInMessage = conversation.messages.first { $0.direction == "in" }?.body
        let previewMessage = (firstOutMessage ?? firstInMessage ?? "").prefix(100)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "it_IT")
        
        return "📱 \(inCount) ricevuti, \(outCount) inviati - \(dateFormatter.string(from: conversation.startedAt))\n\"\(previewMessage)...\""
    }
    
    /// Genera il contenuto completo formattato
    private func generateFullContent(conversation: WhatsAppConversation, isFinal: Bool = false) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short
        
        var content = "Conversazione WhatsApp con \(formatPhoneNumber(conversation.chatId))\n"
        content += "Iniziata: \(conversation.startedAt.formatted())\n\n"
        
        for msg in conversation.messages {
            let arrow = msg.direction == "out" ? "→" : "←"
            let time = dateFormatter.string(from: msg.timestamp)
            content += "[\(time)] \(arrow) \(msg.body)\n"
        }
        
        return content
    }
    
    /// Formatta numero telefono per display
    private func formatPhoneNumber(_ chatId: String) -> String {
        let number = chatId.replacingOccurrences(of: "@c.us", with: "")
        if number.hasPrefix("39") && number.count > 10 {
            let index = number.index(number.startIndex, offsetBy: 2)
            return "+39 \(number[index...])"
        }
        return "+\(number)"
    }
    
    /// Forza chiusura di tutte le conversazioni aperte (chiamato periodicamente o allo shutdown)
    public func flushAllConversations() async {
        for (key, conversation) in openConversations {
            await closeConversation(key: key, conversation: conversation)
        }
        openConversations.removeAll()
        
        print("[WhatsAppDiario] 🔄 Tutte le conversazioni salvate")
    }
    
    /// Chiude conversazioni scadute (da chiamare periodicamente)
    public func closeExpiredConversations() async {
        let now = Date()
        var keysToClose: [String] = []
        
        for (key, conversation) in openConversations {
            let timeSinceLastMessage = now.timeIntervalSince(conversation.lastMessageAt)
            // Chiudi se sono passate più di 2 ore dall'ultimo messaggio
            if timeSinceLastMessage > 7200 {
                keysToClose.append(key)
            }
        }
        
        for key in keysToClose {
            if let conversation = openConversations[key] {
                await closeConversation(key: key, conversation: conversation)
            }
        }
        
        if !keysToClose.isEmpty {
            print("[WhatsAppDiario] 🔄 Chiuse \(keysToClose.count) conversazioni scadute")
        }
    }
}

// MARK: - Models

struct WhatsAppConversation {
    let sinistroRef: String
    let chatId: String
    let startedAt: Date
    var lastMessageAt: Date
    var messages: [ConversationMessage]
    var needsSync: Bool = true
}

struct ConversationMessage {
    let body: String
    let direction: String
    let timestamp: Date
    let fromNumber: String
    let toNumber: String?
}

// MARK: - String Extension for deterministic UUID

import CryptoKit

extension String {
    /// Genera un UUID-like string da un hash MD5 (per ID deterministici)
    func md5UUID() -> String {
        let digest = Insecure.MD5.hash(data: Data(self.utf8))
        let bytes = Array(digest)
        
        // Formatta come UUID (8-4-4-4-12)
        return String(format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                      bytes[0], bytes[1], bytes[2], bytes[3],
                      bytes[4], bytes[5],
                      bytes[6], bytes[7],
                      bytes[8], bytes[9],
                      bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
    }
}
