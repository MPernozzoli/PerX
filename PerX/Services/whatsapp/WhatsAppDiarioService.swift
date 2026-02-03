import Foundation
import CoreData

/// Servizio per gestire le entry del diario per le conversazioni WhatsApp
@MainActor
class WhatsAppDiarioService {
    static let shared = WhatsAppDiarioService()
    
    private let diarioService = DiarioService.shared
    private let associationService = WhatsAppAssociationService.shared
    private let aiService = AppleIntelligenceService.shared
    private let fileService = FileService.shared
    
    // Traccia le entry WhatsApp attive per chat (per aggiornamento)
    private var activeWhatsAppEntries: [String: (entryId: UUID, lastMessageDate: Date)] = [:]
    
    private init() {}
    
    /// Processa nuovi messaggi WhatsApp e crea/aggiorna entry nel diario
    func processWhatsAppMessages(
        chatId: String,
        messages: [WhatsAppMessage],
        sinistro: Sinistro,
        context: NSManagedObjectContext
    ) async {
        // Filtra messaggi non ancora processati (per ID o per testo se ID non disponibile)
        let processedData = getProcessedMessagesData(for: chatId, sinistro: sinistro)
        let newMessages = messages.filter { message in
            // Verifica per ID (priorità massima) - gli ID di WhatsApp sono immutabili tra connessioni
            if !message.id.isEmpty && processedData.messageIds.contains(message.id) {
                return false
            }
            // Verifica per testo esatto (solo se ID non disponibile o vuoto)
            let messageText = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.id.isEmpty && !messageText.isEmpty {
                if processedData.messageTexts.contains(messageText) {
                    return false
                }
            }
            return true
        }
        
        guard !newMessages.isEmpty else { return }
        
        // Ordina per timestamp
        let sortedMessages = newMessages.sorted { $0.timestamp < $1.timestamp }
        
        // Raggruppa i messaggi in conversazioni (gap di 24 ore = nuova conversazione)
        let conversations = groupMessagesIntoConversations(sortedMessages)
        
        for conversation in conversations {
            await processConversation(
                chatId: chatId,
                conversation: conversation,
                sinistro: sinistro,
                context: context
            )
        }
    }
    
    /// Raggruppa i messaggi in conversazioni basate su gap di 24 ore
    private func groupMessagesIntoConversations(_ messages: [WhatsAppMessage]) -> [[WhatsAppMessage]] {
        guard !messages.isEmpty else { return [] }
        
        var conversations: [[WhatsAppMessage]] = []
        var currentConversation: [WhatsAppMessage] = [messages[0]]
        
        for i in 1..<messages.count {
            let previousMessage = messages[i - 1]
            let currentMessage = messages[i]
            
            let timeDifference = currentMessage.timestamp.timeIntervalSince(previousMessage.timestamp)
            let hoursDifference = timeDifference / 3600
            
            if hoursDifference > 24 {
                // Gap di più di 24 ore, nuova conversazione
                conversations.append(currentConversation)
                currentConversation = [currentMessage]
            } else {
                // Stessa conversazione
                currentConversation.append(currentMessage)
            }
        }
        
        // Aggiungi l'ultima conversazione
        if !currentConversation.isEmpty {
            conversations.append(currentConversation)
        }
        
        return conversations
    }
    
    /// Processa una singola conversazione (crea o aggiorna entry)
    private func processConversation(
        chatId: String,
        conversation: [WhatsAppMessage],
        sinistro: Sinistro,
        context: NSManagedObjectContext
    ) async {
        guard let firstMessage = conversation.first,
              let lastMessage = conversation.last else { return }
        
        // Verifica se esiste già un'entry attiva per questa chat
        let entryKey = "\(sinistro.objectID.uriRepresentation().absoluteString)_\(chatId)"
        
        if let activeEntry = activeWhatsAppEntries[entryKey] {
            // Verifica se l'entry è ancora valida (non interrotta da altre entry)
            if await isEntryStillActive(entryId: activeEntry.entryId, lastMessageDate: activeEntry.lastMessageDate, sinistro: sinistro) {
                // Aggiorna l'entry esistente
                await updateExistingEntry(
                    entryId: activeEntry.entryId,
                    chatId: chatId,
                    newMessages: conversation,
                    sinistro: sinistro,
                    context: context
                )
                
                // Aggiorna il timestamp dell'ultimo messaggio
                activeWhatsAppEntries[entryKey] = (activeEntry.entryId, lastMessage.timestamp)
                return
            } else {
                // L'entry è stata interrotta, rimuovila dalle attive
                activeWhatsAppEntries.removeValue(forKey: entryKey)
            }
        }
        
        // Crea una nuova entry
        await createNewEntry(
            chatId: chatId,
            messages: conversation,
            sinistro: sinistro,
            context: context
        )
        
        // Salva l'entry come attiva
        if let newEntryId = getLastWhatsAppEntryId(for: chatId, sinistro: sinistro) {
            activeWhatsAppEntries[entryKey] = (newEntryId, lastMessage.timestamp)
        }
    }
    
    /// Verifica se un'entry è ancora attiva (non interrotta da altre entry)
    private func isEntryStillActive(entryId: UUID, lastMessageDate: Date, sinistro: Sinistro) async -> Bool {
        let allEntries = sinistro.diarioArray.sorted { $0.timestamp < $1.timestamp }
        
        // Trova l'entry WhatsApp
        guard let whatsAppEntryIndex = allEntries.firstIndex(where: { $0.id == entryId && $0.tipo == .whatsapp }) else {
            return false
        }
        
        // Verifica se ci sono altre entry dopo l'ultimo messaggio WhatsApp
        // Se ci sono entry con timestamp maggiore dell'ultimo messaggio WhatsApp, l'entry è stata interrotta
        let entriesAfter = Array(allEntries.suffix(from: allEntries.index(after: whatsAppEntryIndex)))
        
        for entry in entriesAfter {
            // Se c'è un'entry (di qualsiasi tipo) dopo l'ultimo messaggio WhatsApp, l'entry è stata interrotta
            if entry.timestamp > lastMessageDate {
                return false
            }
        }
        
        return true
    }
    
    /// Aggiorna un'entry esistente con nuovi messaggi
    private func updateExistingEntry(
        entryId: UUID,
        chatId: String,
        newMessages: [WhatsAppMessage],
        sinistro: Sinistro,
        context: NSManagedObjectContext
    ) async {
        var allEntries = sinistro.diarioArray
        guard let entryIndex = allEntries.firstIndex(where: { $0.id == entryId }) else { return }
        
        var entry = allEntries[entryIndex]
        
        // Aggiungi i nuovi message IDs
        var messageIds = getMessageIds(from: entry)
        let newMessageIds = newMessages.map { $0.id }
        messageIds.append(contentsOf: newMessageIds)
        
        // Salva i nuovi media ricevuti
        await saveMediaFiles(messages: newMessages, sinistro: sinistro)
        
        // Aggiungi i nuovi messaggi al contenuto esistente (salviamo tutto per persistenza)
        let existingContent = entry.contenutoCompleto ?? ""
        let newMessagesText = formatConversationText(messages: newMessages)
        let updatedContent = existingContent.isEmpty 
            ? newMessagesText 
            : "\(existingContent)\n\n--- Nuovi messaggi ---\n\n\(newMessagesText)"
        
        // Genera nuovo nome e riassunto con AI usando tutto il contenuto aggiornato
        let allMessages = getAllMessagesFromEntry(entry: entry) + newMessages
        let (titolo, riassunto) = await generateEntryTitleAndSummary(messages: allMessages)
        
        // Aggiorna l'entry
        let updatedEntry = DiarioEntry(
            id: entry.id,
            timestamp: entry.timestamp, // Mantieni il timestamp originale
            tipo: .whatsapp,
            titolo: titolo,
            riassunto: riassunto,
            contenutoCompleto: updatedContent, // Salva conversazione completa aggiornata
            whatsAppChatId: chatId,
            whatsAppMessageIds: messageIds,
            processedWhatsAppDate: newMessages.last?.timestamp
        )
        
        allEntries[entryIndex] = updatedEntry
        sinistro.diarioArray = allEntries
        
        try? context.save()
        print("[WhatsAppDiario] ✅ Entry \(entryId) aggiornata con \(newMessages.count) nuovi messaggi")
        
        // Attiva trigger intelligenti per i nuovi messaggi
        await ActiveTriggerService.shared.processDiarioEntry(
            updatedEntry,
            sinistro: sinistro,
            whatsAppMessages: newMessages,
            context: context
        )
    }
    
    /// Crea una nuova entry per una conversazione
    private func createNewEntry(
        chatId: String,
        messages: [WhatsAppMessage],
        sinistro: Sinistro,
        context: NSManagedObjectContext
    ) async {
        // Salva i media ricevuti nella cartella del sinistro
        await saveMediaFiles(messages: messages, sinistro: sinistro)
        
        // Formatta la conversazione completa (salviamo tutto per persistenza)
        let conversationText = formatConversationText(messages: messages)
        let messageIds = messages.map { $0.id }
        
        // Genera nome e riassunto con Apple Intelligence
        let (titolo, riassunto) = await generateEntryTitleAndSummary(messages: messages)
        
        // Crea entry con contenuto completo salvato
        let entry = DiarioEntry(
            timestamp: messages.first?.timestamp ?? Date(),
            tipo: .whatsapp,
            titolo: titolo,
            riassunto: riassunto,
            contenutoCompleto: conversationText, // Salva conversazione completa
            whatsAppChatId: chatId,
            whatsAppMessageIds: messageIds,
            processedWhatsAppDate: messages.last?.timestamp
        )
        
        sinistro.addDiarioEntry(entry)
        try? context.save()
        print("[WhatsAppDiario] ✅ Creata nuova entry per conversazione WhatsApp con \(messages.count) messaggi")
        
        // Attiva trigger intelligenti
        await ActiveTriggerService.shared.processDiarioEntry(
            entry,
            sinistro: sinistro,
            whatsAppMessages: messages,
            context: context
        )
    }
    
    /// Formatta i messaggi in un testo conversazione
    private func formatConversationText(messages: [WhatsAppMessage]) -> String {
        var text = ""
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        for message in messages {
            let dateStr = formatter.string(from: message.timestamp)
            let sender = message.isSent ? "Tu" : "Contatto"
            text += "[\(dateStr)] \(sender): \(message.body)\n\n"
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Ottiene tutti i messaggi per un'entry (esistenti + nuovi)
    private func getAllMessagesForEntry(entry: DiarioEntry, chatId: String, newMessages: [WhatsAppMessage]) -> [WhatsAppMessage] {
        // TODO: Recuperare i messaggi esistenti dalla chat
        // Per ora restituiamo solo i nuovi messaggi
        // In futuro potremmo salvare i messaggi completi nell'entry o recuperarli dalla chat
        return newMessages
    }
    
    /// Ottiene i message IDs da un'entry
    private func getMessageIds(from entry: DiarioEntry) -> [String] {
        return entry.whatsAppMessageIds ?? []
    }
    
    /// Ottiene i dati dei messaggi già processati (ID e testo) per una chat
    private func getProcessedMessagesData(for chatId: String, sinistro: Sinistro) -> (messageIds: Set<String>, messageTexts: Set<String>) {
        let allEntries = sinistro.diarioArray
        var processedIds = Set<String>()
        var processedTexts = Set<String>()
        
        for entry in allEntries {
            if entry.whatsAppChatId == chatId {
                // Aggiungi gli ID dei messaggi
                if let messageIds = entry.whatsAppMessageIds {
                    processedIds.formUnion(messageIds)
                }
                
                // Estrai i testi dei messaggi dal contenuto completo per deduplicazione
                if let content = entry.contenutoCompleto {
                    let texts = extractMessageTexts(from: content)
                    processedTexts.formUnion(texts)
                }
            }
        }
        
        return (processedIds, processedTexts)
    }
    
    /// Estrae i testi dei messaggi dal contenuto formattato
    private func extractMessageTexts(from content: String) -> Set<String> {
        var texts = Set<String>()
        let lines = content.components(separatedBy: .newlines)
        var currentMessage = ""
        
        for line in lines {
            // Pattern: [data] Mittente: testo
            if line.hasPrefix("[") && line.contains("]: ") {
                // Salva il messaggio precedente se non vuoto
                if !currentMessage.isEmpty {
                    texts.insert(currentMessage.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                // Estrai il testo dopo "]: "
                if let textStart = line.range(of: "]: ") {
                    currentMessage = String(line[textStart.upperBound...])
                } else {
                    currentMessage = ""
                }
            } else if !line.isEmpty {
                // Continua del messaggio precedente
                currentMessage += " " + line
            }
        }
        
        // Aggiungi l'ultimo messaggio
        if !currentMessage.isEmpty {
            texts.insert(currentMessage.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        return texts
    }
    
    /// Ottiene tutti i messaggi da un'entry (per ricostruire la conversazione completa)
    private func getAllMessagesFromEntry(entry: DiarioEntry) -> [WhatsAppMessage] {
        // TODO: In futuro potremmo salvare i messaggi completi nell'entry o recuperarli dalla chat
        // Per ora restituiamo array vuoto, il contenuto è già salvato in contenutoCompleto
        return []
    }
    
    /// Ottiene l'ID dell'ultima entry WhatsApp per una chat
    private func getLastWhatsAppEntryId(for chatId: String, sinistro: Sinistro) -> UUID? {
        let allEntries = sinistro.diarioArray
            .filter { $0.whatsAppChatId == chatId && $0.tipo == .whatsapp }
            .sorted { $0.timestamp > $1.timestamp }
        
        return allEntries.first?.id
    }
    
    // MARK: - Media Handling
    
    /// Salva i media ricevuti nella cartella "da WA" del sinistro
    private func saveMediaFiles(messages: [WhatsAppMessage], sinistro: Sinistro) async {
        guard let riferimento = sinistro.riferimento else { return }
        
        // Salva solo i media ricevuti (non inviati) usando mediaId stabile (message.id)
        var savedMediaIds = Set<String>()
        let accountId = WhatsAppService.shared.selectedAccountId
        guard !accountId.isEmpty else { return }
        
        for message in messages where !message.isSent {
            // Salta i messaggi di solo testo
            guard message.type != .text else { continue }
            
            let mediaId = message.mediaId ?? message.id
            if mediaId.isEmpty { continue }
            
            if savedMediaIds.contains(mediaId) { continue }
            savedMediaIds.insert(mediaId)
            
            // Se già presente localmente, non riscaricare
            if WhatsAppMediaService.shared.resolveLocalMediaURL(mediaId: mediaId, sinistroRiferimento: riferimento) != nil {
                continue
            }
            
            do {
                _ = try await WhatsAppMediaService.shared.downloadAndSaveMedia(
                    accountId: accountId,
                    messageId: mediaId,
                    sinistroRiferimento: riferimento,
                    suggestedFilename: message.mediaFilename,
                    mimeType: mimeType(for: message.type)
                )
            } catch {
                print("[WhatsAppDiario] ❌ Errore download/salvataggio media \(mediaId): \(error.localizedDescription)")
            }
        }
    }
    
    private func mimeType(for mediaType: MessageType) -> String? {
        switch mediaType {
        case .text: return nil
        case .image: return "image/jpeg"
        case .video: return "video/mp4"
        case .audio, .ptt: return "audio/ogg"
        case .document: return "application/octet-stream"
        case .sticker: return "image/webp"
        case .location, .contact: return "text/plain"
        }
    }
    
    // MARK: - AI Generation
    
    /// Genera nome e riassunto dell'entry usando Apple Intelligence
    private func generateEntryTitleAndSummary(messages: [WhatsAppMessage]) async -> (titolo: String, riassunto: String) {
        let conversationText = formatConversationText(messages: messages)
        
        // Genera riassunto
        let riassunto = await aiService.summarizeEmailBodyIgnoringSignature(
            subject: "Conversazione WhatsApp",
            body: conversationText
        ) ?? "Conversazione WhatsApp"
        
        // Genera titolo basato sul contenuto (primi messaggi o riassunto)
        let titolo: String
        if let firstMessage = messages.first, !firstMessage.body.isEmpty {
            // Usa le prime parole del primo messaggio o del riassunto come titolo
            let firstWords = String(firstMessage.body.prefix(50))
            if firstWords.count < 20 {
                // Se troppo corto, usa il riassunto
                titolo = String(riassunto.prefix(50))
            } else {
                titolo = firstWords
            }
        } else {
            titolo = "Conversazione WhatsApp"
        }
        
        return (titolo, riassunto)
    }
}

