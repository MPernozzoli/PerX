import Foundation
import CloudKit
import Combine
import CoreData
import UserNotifications

/// Servizio per sincronizzazione chat interna via CloudKit
@MainActor
final class CloudKitChatService: ObservableObject {
    static let shared = CloudKitChatService()
    
    // MARK: - Published Properties
    
    @Published private(set) var rooms: [ChatRoom] = []
    @Published private(set) var messages: [String: [ChatMessage]] = [:] // roomId -> messages
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var uploadProgress: Double = 0
    @Published private(set) var hiddenRoomIds: Set<String> = []
    @Published var activeRoomId: String? = nil
    
    // Collegamento sinistro attivo nella room corrente
    @Published var activeLinkedSinistro: String? = nil
    
    // MARK: - Private Properties
    
    private let container: CKContainer
    private let publicDB: CKDatabase
    private var subscriptionId: CKSubscription.ID?
    private var cancellables = Set<AnyCancellable>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let hiddenRoomsKey = "cloudkit_chat_hidden_rooms"
    private var pollTimer: Timer?
    
    /// ID dei messaggi per cui è già stata mostrata una notifica
    private var notifiedMessageIds: Set<UUID> = []
    /// Flag per primo fetch dopo avvio (non notificare messaggi esistenti)
    private var isFirstFetch = true
    
    private enum RecordType {
        static let chatRoom = "ChatRoom"
        static let chatMessage = "ChatMessage"
        static let chatAttachment = "ChatAttachment"
    }
    
    private enum RoomKeys {
        static let roomId = "roomId"
        static let name = "name"
        static let participants = "participants"
        static let admins = "admins"
        static let createdAt = "createdAt"
        static let createdBy = "createdBy"
        static let lastMessageAt = "lastMessageAt"
        static let lastMessagePreview = "lastMessagePreview"
        static let lastMessageSender = "lastMessageSender"
        static let roomType = "roomType"
        static let linkedSinistroRif = "linkedSinistroRif"
        static let isMuted = "isMuted"
    }
    
    private enum MessageKeys {
        static let messageId = "messageId"
        static let roomId = "roomId"
        static let senderEmail = "senderEmail"
        static let senderName = "senderName"
        static let content = "content"
        static let mentionsJSON = "mentionsJSON"
        static let hashtagsJSON = "hashtagsJSON"
        static let attachmentsJSON = "attachmentsJSON"
        static let timestamp = "timestamp"
        static let linkedSinistroRif = "linkedSinistroRif"
        static let isPinnedToDiario = "isPinnedToDiario"
        static let diarioEntryId = "diarioEntryId"
        static let linkedFromMessageId = "linkedFromMessageId"
        static let readReceiptsJSON = "readReceiptsJSON"
    }
    
    // MARK: - Init
    
    private init(container: CKContainer = CKContainer(identifier: "iCloud.it.pernozzoli.PerX")) {
        self.container = container
        self.publicDB = container.publicCloudDatabase
        
        // Directory per cache allegati
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cachesDir.appendingPathComponent("ChatAttachments", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Carica rooms salvate localmente
        loadHiddenRooms()
        loadLocalRooms()
        loadLocalMessages()
        
        // Richiedi permessi notifiche
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("[CloudKitChat] ✅ Notifiche autorizzate")
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Avvia il servizio e sincronizza
    func start() async {
        await fetchRooms()
        
        // Fetch iniziale messaggi per tutte le room (marca come già notificati)
        for room in rooms {
            await fetchMessages(for: room.id)
        }
        
        // Dopo il primo fetch, abilita le notifiche per i nuovi messaggi
        isFirstFetch = false
        
        await setupSubscription()
        startPolling()
    }
    
    /// Gestisce una notifica push CloudKit - fetch immediato
    func handleCloudKitNotification() async {
        print("[CloudKitChat] 📨 Notifica CloudKit - fetch immediato")
        
        // Fetch immediato delle room
        await fetchRooms()
        
        // Fetch messaggi per la room attiva
        if let activeRoom = activeRoomId {
            await fetchMessages(for: activeRoom)
        }
        
        // Fetch messaggi per tutte le room con attività recente
        let recentThreshold = Date().addingTimeInterval(-60)
        let recentRooms = rooms.filter { room in
            room.id != activeRoomId && room.lastMessageAt > recentThreshold
        }
        
        for room in recentRooms {
            await fetchMessages(for: room.id)
        }
    }

    /// Intervallo di polling in secondi
    private var pollingInterval: TimeInterval = 3.0
    
    /// Imposta l'intervallo di polling (per renderlo più aggressivo quando la vista è attiva)
    func setPollingInterval(_ interval: TimeInterval) {
        guard interval != pollingInterval else { return }
        pollingInterval = interval
        startPollingInternal() // riavvia con nuovo intervallo
    }
    
    func startPolling() {
        startPollingInternal()
    }
    
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    private func startPollingInternal() {
        pollTimer?.invalidate()
        // Polling configurabile per messaggi più reattivi
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await CPUThrottler.shared.runWithThrottle {
                    await self.fetchRooms()
                    if let active = self.activeRoomId {
                        await self.fetchMessages(for: active)
                    }
                    let recentThreshold = Date().addingTimeInterval(-30)
                    let recentRooms = self.rooms.filter { room in
                        room.id != self.activeRoomId && room.lastMessageAt > recentThreshold
                    }
                    for room in recentRooms {
                        await self.fetchMessages(for: room.id)
                    }
                }
            }
        }
    }

    // MARK: - Local-only deletion (hide)
    
    /// Nasconde una chat SOLO per l'utente corrente (all'altro resta).
    func hideRoomLocally(_ roomId: String) {
        hiddenRoomIds.insert(roomId)
        persistHiddenRooms()
        
        rooms.removeAll { $0.id == roomId }
        messages.removeValue(forKey: roomId)
        saveLocalRooms()
        saveLocalMessages()
    }
    
    /// Crea una nuova stanza di chat
    func createRoom(
        name: String,
        participants: [String],
        roomType: ChatRoom.RoomType = .direct,
        linkedSinistroRif: String? = nil
    ) async throws -> ChatRoom {
        let currentEmail = GoogleAuthService.shared.userEmail ?? ""
        
        let room = ChatRoom(
            name: name,
            participants: participants,
            admins: [currentEmail],
            createdBy: currentEmail,
            roomType: roomType,
            linkedSinistroRif: linkedSinistroRif
        )
        
        let record = CKRecord(recordType: RecordType.chatRoom, recordID: CKRecord.ID(recordName: room.id))
        record[RoomKeys.roomId] = room.id as CKRecordValue
        record[RoomKeys.name] = name as CKRecordValue
        record[RoomKeys.participants] = participants as CKRecordValue
        record[RoomKeys.admins] = room.admins as CKRecordValue
        record[RoomKeys.createdAt] = room.createdAt as CKRecordValue
        record[RoomKeys.createdBy] = currentEmail as CKRecordValue
        record[RoomKeys.lastMessageAt] = room.lastMessageAt as CKRecordValue
        record[RoomKeys.roomType] = roomType.rawValue as CKRecordValue
        if let sinistroRif = linkedSinistroRif {
            record[RoomKeys.linkedSinistroRif] = sinistroRif as CKRecordValue
        }
        
        _ = try await publicDB.saveRecordAsync(record)
        
        rooms.append(room)
        saveLocalRooms()
        
        return room
    }
    
    /// Crea un gruppo con più partecipanti
    func createGroup(name: String, participants: [String]) async throws -> ChatRoom {
        let currentEmail = GoogleAuthService.shared.userEmail?.lowercased() ?? ""
        var allParticipants = Set(participants.map { $0.lowercased() })
        allParticipants.insert(currentEmail)
        
        return try await createRoom(
            name: name,
            participants: Array(allParticipants),
            roomType: .group
        )
    }
    
    /// Crea o trova una chat collegata a un sinistro
    func findOrCreateSinistroChat(riferimento: String, participants: [String]) async throws -> ChatRoom {
        // Cerca room esistente per questo sinistro
        if let existingRoom = rooms.first(where: { $0.linkedSinistroRif == riferimento }) {
            return existingRoom
        }
        
        let currentEmail = GoogleAuthService.shared.userEmail?.lowercased() ?? ""
        var allParticipants = Set(participants.map { $0.lowercased() })
        allParticipants.insert(currentEmail)
        
        return try await createRoom(
            name: "Sinistro \(riferimento)",
            participants: Array(allParticipants),
            roomType: .sinistro,
            linkedSinistroRif: riferimento
        )
    }
    
    /// Trova o crea una chat diretta con un utente
    func findOrCreateDirectChat(with userEmail: String, currentUserEmail: String) async throws -> ChatRoom {
        let participants = [currentUserEmail.lowercased(), userEmail.lowercased()].sorted()
        
        if let existingRoom = rooms.first(where: { room in
            room.isDirect && Set(room.participants.map { $0.lowercased() }) == Set(participants)
        }) {
            return existingRoom
        }
        
        let userName = userEmail.components(separatedBy: "@").first?.replacingOccurrences(of: ".", with: " ").capitalized ?? userEmail
        return try await createRoom(name: "Chat con \(userName)", participants: participants, roomType: .direct)
    }
    
    /// Aggiunge partecipanti a un gruppo
    func addParticipants(_ emails: [String], to roomId: String) async throws {
        guard let index = rooms.firstIndex(where: { $0.id == roomId }) else { return }
        
        var room = rooms[index]
        let newParticipants = Set(emails.map { $0.lowercased() })
        let existingParticipants = Set(room.participants.map { $0.lowercased() })
        room.participants = Array(existingParticipants.union(newParticipants))
        
        let recordID = CKRecord.ID(recordName: roomId)
        let record = try await publicDB.fetchRecordAsync(recordID)
        record[RoomKeys.participants] = room.participants as CKRecordValue
        _ = try await publicDB.saveRecordAsync(record)
        
        rooms[index] = room
        saveLocalRooms()
    }
    
    /// Rimuove un partecipante dal gruppo
    func removeParticipant(_ email: String, from roomId: String) async throws {
        guard let index = rooms.firstIndex(where: { $0.id == roomId }) else { return }
        
        var room = rooms[index]
        room.participants.removeAll { $0.lowercased() == email.lowercased() }
        
        let recordID = CKRecord.ID(recordName: roomId)
        let record = try await publicDB.fetchRecordAsync(recordID)
        record[RoomKeys.participants] = room.participants as CKRecordValue
        _ = try await publicDB.saveRecordAsync(record)
        
        rooms[index] = room
        saveLocalRooms()
    }
    
    /// Invia un messaggio con supporto per allegati e collegamento sinistro
    func sendMessage(
        roomId: String,
        content: String,
        mentions: [ChatMention],
        hashtags: [ChatHashtag],
        attachments: [ChatAttachment] = [],
        senderEmail: String,
        senderName: String,
        linkedSinistroRif: String? = nil,
        pinToDiario: Bool = false
    ) async throws -> ChatMessage {
        // Determina il collegamento sinistro (da menzione o attivo nella room)
        let sinistroRif = linkedSinistroRif ?? activeLinkedSinistro
        
        // Se c'è un riferimento sinistro nelle menzioni e si vuole collegare
        let mentionedRiferimento = mentions.first(where: { $0.type == .riferimento })?.value
        let finalSinistroRif = sinistroRif ?? (pinToDiario ? mentionedRiferimento : nil)
        
        var message = ChatMessage(
            roomId: roomId,
            senderEmail: senderEmail,
            senderName: senderName,
            content: content,
            mentions: mentions,
            hashtags: hashtags,
            attachments: attachments,
            linkedSinistroRif: finalSinistroRif,
            isPinnedToDiario: pinToDiario && finalSinistroRif != nil
        )
        
        // Se pinnato al diario, crea l'entry
        if message.isPinnedToDiario, let riferimento = finalSinistroRif {
            let diarioId = try await pinMessageToDiario(message: message, riferimento: riferimento)
            message.diarioEntryId = diarioId
        }
        
        let record = CKRecord(recordType: RecordType.chatMessage, recordID: CKRecord.ID(recordName: message.id.uuidString))
        record[MessageKeys.messageId] = message.id.uuidString as CKRecordValue
        record[MessageKeys.roomId] = roomId as CKRecordValue
        record[MessageKeys.senderEmail] = senderEmail as CKRecordValue
        record[MessageKeys.senderName] = senderName as CKRecordValue
        record[MessageKeys.content] = content as CKRecordValue
        record[MessageKeys.timestamp] = message.timestamp as CKRecordValue
        
        // Serializza mentions, hashtags e attachments
        if let mentionsData = try? JSONEncoder().encode(mentions),
           let mentionsJSON = String(data: mentionsData, encoding: .utf8) {
            record[MessageKeys.mentionsJSON] = mentionsJSON as CKRecordValue
        }
        
        if let hashtagsData = try? JSONEncoder().encode(hashtags),
           let hashtagsJSON = String(data: hashtagsData, encoding: .utf8) {
            record[MessageKeys.hashtagsJSON] = hashtagsJSON as CKRecordValue
        }
        
        if !attachments.isEmpty,
           let attachmentsData = try? JSONEncoder().encode(attachments),
           let attachmentsJSON = String(data: attachmentsData, encoding: .utf8) {
            record[MessageKeys.attachmentsJSON] = attachmentsJSON as CKRecordValue
        }
        
        // Campi collegamento sinistro
        if let sinistroRif = message.linkedSinistroRif {
            record[MessageKeys.linkedSinistroRif] = sinistroRif as CKRecordValue
        }
        record[MessageKeys.isPinnedToDiario] = message.isPinnedToDiario as CKRecordValue
        if let diarioId = message.diarioEntryId {
            record[MessageKeys.diarioEntryId] = diarioId.uuidString as CKRecordValue
        }
        
        // Read receipts (vuoto alla creazione)
        record[MessageKeys.readReceiptsJSON] = "[]" as CKRecordValue
        
        _ = try await publicDB.saveRecordAsync(record)
        
        // Aggiorna locale
        var roomMessages = messages[roomId] ?? []
        roomMessages.append(message)
        roomMessages.sort { $0.timestamp < $1.timestamp }
        messages[roomId] = roomMessages
        
        // Aggiorna room
        if let index = rooms.firstIndex(where: { $0.id == roomId }) {
            rooms[index].lastMessageAt = message.timestamp
            rooms[index].lastMessagePreview = content.isEmpty && !attachments.isEmpty ? "📎 Allegato" : String(content.prefix(50))
            rooms[index].lastMessageSender = senderName
        }
        
        saveLocalMessages()
        saveLocalRooms()
        
        // Aggiorna lastMessageAt su CloudKit
        await updateRoomLastMessage(roomId: roomId, message: message)
        
        // Segna il messaggio come già notificato (è mio, non devo ricevere notifica)
        notifiedMessageIds.insert(message.id)
        
        return message
    }
    
    // MARK: - Attachment Upload
    
    /// Carica un allegato e restituisce ChatAttachment
    func uploadAttachment(from url: URL, roomId: String) async throws -> ChatAttachment {
        let fileName = url.lastPathComponent
        let fileSize = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let mimeType = getMimeType(for: url)
        let attachmentType = ChatAttachment.AttachmentType.from(mimeType: mimeType)
        
        // Copia file nella cache locale
        let localCacheURL = cacheDirectory.appendingPathComponent(UUID().uuidString + "_" + fileName)
        try fileManager.copyItem(at: url, to: localCacheURL)
        
        // Crea asset CloudKit
        let asset = CKAsset(fileURL: localCacheURL)
        let attachmentId = UUID()
        
        let record = CKRecord(recordType: RecordType.chatAttachment, recordID: CKRecord.ID(recordName: attachmentId.uuidString))
        record["attachmentId"] = attachmentId.uuidString as CKRecordValue
        record["roomId"] = roomId as CKRecordValue
        record["fileName"] = fileName as CKRecordValue
        record["fileSize"] = fileSize as CKRecordValue
        record["mimeType"] = mimeType as CKRecordValue
        record["file"] = asset
        
        let saved = try await publicDB.saveRecordAsync(record)
        
        // Recupera URL dell'asset salvato
        let assetURL = (saved["file"] as? CKAsset)?.fileURL?.absoluteString
        
        return ChatAttachment(
            id: attachmentId,
            type: attachmentType,
            fileName: fileName,
            fileSize: fileSize,
            mimeType: mimeType,
            cloudKitAssetURL: assetURL,
            localURL: localCacheURL.absoluteString
        )
    }
    
    /// Scarica un allegato
    func downloadAttachment(_ attachment: ChatAttachment) async throws -> URL {
        // Controlla cache locale
        if let localPath = attachment.localURL,
           let localURL = URL(string: localPath),
           fileManager.fileExists(atPath: localURL.path) {
            return localURL
        }
        
        // Scarica da CloudKit
        let recordID = CKRecord.ID(recordName: attachment.id.uuidString)
        let record = try await publicDB.fetchRecordAsync(recordID)
        
        guard let asset = record["file"] as? CKAsset,
              let assetURL = asset.fileURL else {
            throw NSError(domain: "CloudKitChat", code: -1, userInfo: [NSLocalizedDescriptionKey: "Allegato non trovato"])
        }
        
        // Copia nella cache locale
        let localURL = cacheDirectory.appendingPathComponent(attachment.fileName)
        try? fileManager.removeItem(at: localURL)
        try fileManager.copyItem(at: assetURL, to: localURL)
        
        return localURL
    }
    
    private func getMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "pdf": return "application/pdf"
        case "doc", "docx": return "application/msword"
        case "xls", "xlsx": return "application/vnd.ms-excel"
        case "txt": return "text/plain"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        default: return "application/octet-stream"
        }
    }
    
    // MARK: - Collegamento Sinistro e Diario
    
    /// Collega i messaggi successivi a un sinistro
    func linkToSinistro(_ riferimento: String, in roomId: String) {
        activeLinkedSinistro = riferimento
        
        // Notifica cambio stato
        objectWillChange.send()
    }
    
    /// Scollega dal sinistro
    func unlinkFromSinistro(in roomId: String) {
        activeLinkedSinistro = nil
        objectWillChange.send()
    }
    
    /// Pinna un messaggio al diario del sinistro
    private func pinMessageToDiario(message: ChatMessage, riferimento: String) async throws -> UUID {
        let context = PersistenceController.shared.container.viewContext
        
        return try await context.perform {
            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
            request.fetchLimit = 1
            
            guard let sinistro = try context.fetch(request).first else {
                throw NSError(domain: "CloudKitChat", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sinistro non trovato"])
            }
            
            // Crea entry diario
            let entryId = UUID()
            let attachmentInfo = message.attachments.isEmpty ? "" : " [📎 \(message.attachments.count) allegati]"
            
            let entry = DiarioEntry(
                id: entryId,
                timestamp: message.timestamp,
                tipo: .notaUtente,
                titolo: "💬 Messaggio chat da \(message.senderName)",
                riassunto: message.content + attachmentInfo,
                contenutoCompleto: """
                Messaggio chat interno
                
                Da: \(message.senderName) (\(message.senderEmail))
                Data: \(message.timestamp.formatted())
                
                \(message.content)
                \(attachmentInfo)
                """,
                emailMessageId: nil,
                processedEmailDate: nil,
                whatsAppChatId: nil,
                whatsAppMessageIds: nil,
                processedWhatsAppDate: nil,
                generatedTaskId: nil
            )
            
            sinistro.addDiarioEntry(entry)
            try context.save()
            
            return entryId
        }
    }
    
    /// Aggiorna un messaggio esistente per collegarlo/scollegarlo dal sinistro
    func updateMessageLink(_ messageId: UUID, in roomId: String, linkedSinistroRif: String?, pinToDiario: Bool) async throws {
        guard var roomMessages = messages[roomId],
              let index = roomMessages.firstIndex(where: { $0.id == messageId }) else { return }
        
        var message = roomMessages[index]
        message.linkedSinistroRif = linkedSinistroRif
        message.isPinnedToDiario = pinToDiario && linkedSinistroRif != nil
        
        if message.isPinnedToDiario, let riferimento = linkedSinistroRif, message.diarioEntryId == nil {
            message.diarioEntryId = try await pinMessageToDiario(message: message, riferimento: riferimento)
        }
        
        roomMessages[index] = message
        messages[roomId] = roomMessages
        
        // Aggiorna su CloudKit
        let recordID = CKRecord.ID(recordName: messageId.uuidString)
        let record = try await publicDB.fetchRecordAsync(recordID)
        
        if let sinistroRif = linkedSinistroRif {
            record[MessageKeys.linkedSinistroRif] = sinistroRif as CKRecordValue
        } else {
            record[MessageKeys.linkedSinistroRif] = nil
        }
        record[MessageKeys.isPinnedToDiario] = message.isPinnedToDiario as CKRecordValue
        if let diarioId = message.diarioEntryId {
            record[MessageKeys.diarioEntryId] = diarioId.uuidString as CKRecordValue
        }
        
        _ = try await publicDB.saveRecordAsync(record)
        saveLocalMessages()
    }
    
    // MARK: - Local Notifications
    
    /// Mostra una notifica locale per un messaggio ricevuto (solo se chat non attiva e non silenziata)
    private func showLocalNotification(for message: ChatMessage, roomId: String) async {
        guard let room = rooms.first(where: { $0.id == roomId }),
              !room.isMuted else { return }
        
        let content = UNMutableNotificationContent()
        content.title = room.isGroup ? "\(message.senderName) in \(room.name)" : message.senderName
        content.body = message.content.isEmpty && message.hasAttachments ? "📎 Ha inviato un allegato" : message.content
        content.sound = .default
        content.userInfo = [
            "roomId": roomId,
            "messageId": message.id.uuidString,
            "senderEmail": message.senderEmail
        ]
        
        // Badge per messaggi non letti
        let totalUnread = rooms.reduce(0) { $0 + $1.unreadCount }
        content.badge = NSNumber(value: totalUnread + 1)
        
        let request = UNNotificationRequest(
            identifier: message.id.uuidString,
            content: content,
            trigger: nil // Immediata
        )
        
        try? await UNUserNotificationCenter.current().add(request)
        print("[CloudKitChat] 🔔 Notifica locale: \(message.senderName): \(message.content.prefix(30))")
    }
    
    /// Recupera i messaggi di una stanza
    func fetchMessages(for roomId: String) async {
        isLoading = true
        defer { isLoading = false }
        
        let currentEmail = GoogleAuthService.shared.userEmail?.lowercased() ?? ""
        let existingIds = Set((messages[roomId] ?? []).map(\.id))
        
        do {
            let predicate = NSPredicate(format: "%K == %@", MessageKeys.roomId, roomId)
            let query = CKQuery(recordType: RecordType.chatMessage, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: MessageKeys.timestamp, ascending: true)]
            
            let records = try await publicDB.performQueryAsync(query)
            let fetchedMessages = records.compactMap { recordToMessage($0) }
            
            // Al primo fetch, marca tutti i messaggi come già notificati (non notificare l'esistente)
            if isFirstFetch {
                for msg in fetchedMessages {
                    notifiedMessageIds.insert(msg.id)
                }
            } else {
                // Trova nuovi messaggi (non esistevano prima)
                let newMessages = fetchedMessages.filter { !existingIds.contains($0.id) }
                
                // Notifica per nuovi messaggi non miei e se la chat non è attiva
                for msg in newMessages {
                    let isMyMessage = msg.senderEmail.lowercased() == currentEmail
                    let isChatActive = activeRoomId == roomId
                    let alreadyNotified = notifiedMessageIds.contains(msg.id)
                    
                    if !isMyMessage && !isChatActive && !alreadyNotified {
                        await showLocalNotification(for: msg, roomId: roomId)
                        notifiedMessageIds.insert(msg.id)
                    }
                }
            }
            
            messages[roomId] = fetchedMessages
            saveLocalMessages()
        } catch {
            self.error = "Errore caricamento messaggi: \(error.localizedDescription)"
            print("[CloudKitChat] ❌ Errore fetch messaggi: \(error)")
        }
    }
    
    /// Recupera tutte le stanze dell'utente
    func fetchRooms() async {
        guard let currentEmail = GoogleAuthService.shared.userEmail?.lowercased() else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // participants è una lista CloudKit → usare ANY == per funzionare correttamente
            let predicate = NSPredicate(format: "ANY \(RoomKeys.participants) == %@", currentEmail)
            let query = CKQuery(recordType: RecordType.chatRoom, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: RoomKeys.lastMessageAt, ascending: false)]
            
            let records = try await publicDB.performQueryAsync(query)
            let fetched = records.compactMap { recordToRoom($0) }
            rooms = fetched.filter { hiddenRoomIds.contains($0.id) == false }
            saveLocalRooms()
        } catch {
            self.error = "Errore caricamento stanze: \(error.localizedDescription)"
            print("[CloudKitChat] ❌ Errore fetch rooms: \(error)")
        }
    }
    
    /// Segna i messaggi come letti
    /// - Parameters:
    ///   - roomId: ID della stanza
    ///   - currentUserEmail: Email dell'utente corrente
    ///   - sendReadReceipts: Se inviare le conferme di lettura (rispetta preferenze utente)
    func markMessagesAsRead(in roomId: String, currentUserEmail: String, sendReadReceipts: Bool = true) {
        guard var roomMessages = messages[roomId] else { return }
        
        for i in 0..<roomMessages.count {
            if !roomMessages[i].isSentByCurrentUser(currentEmail: currentUserEmail) {
                roomMessages[i].isRead = true
                
                // Persisti read receipt su CloudKit solo se l'utente ha abilitato le notifiche
                if sendReadReceipts {
                    let msgId = roomMessages[i].id
                    // Usa il nome dal profilo se disponibile
                    let userName = UserProfileService.shared.currentProfile?.displayName
                        ?? GoogleAuthService.shared.userEmail?.components(separatedBy: "@").first?.capitalized
                    
                    Task {
                        try? await self.addReadReceipt(
                            messageId: msgId,
                            roomId: roomId,
                            userEmail: currentUserEmail,
                            userName: userName
                        )
                    }
                }
            }
        }
        
        messages[roomId] = roomMessages
        
        // Azzera unread count
        if let index = rooms.firstIndex(where: { $0.id == roomId }) {
            rooms[index].unreadCount = 0
        }
        
        saveLocalMessages()
        saveLocalRooms()
    }
    
    // MARK: - Private Methods
    
    private func updateRoomLastMessage(roomId: String, message: ChatMessage) async {
        let recordID = CKRecord.ID(recordName: roomId)
        
        do {
            let record = try await publicDB.fetchRecordAsync(recordID)
            record[RoomKeys.lastMessageAt] = message.timestamp as CKRecordValue
            let preview = message.content.isEmpty && message.hasAttachments ? "📎 Allegato" : String(message.content.prefix(50))
            record[RoomKeys.lastMessagePreview] = preview as CKRecordValue
            record[RoomKeys.lastMessageSender] = message.senderName as CKRecordValue
            _ = try await publicDB.saveRecordAsync(record)
        } catch {
            print("[CloudKitChat] ⚠️ Errore aggiornamento room: \(error)")
        }
    }
    
    /// Silenzia/riattiva notifiche per una room
    func toggleMute(for roomId: String) async throws {
        guard let index = rooms.firstIndex(where: { $0.id == roomId }) else { return }
        
        rooms[index].isMuted.toggle()
        
        let recordID = CKRecord.ID(recordName: roomId)
        let record = try await publicDB.fetchRecordAsync(recordID)
        record[RoomKeys.isMuted] = rooms[index].isMuted as CKRecordValue
        _ = try await publicDB.saveRecordAsync(record)
        
        saveLocalRooms()
    }
    
    private func setupSubscription() async {
        // Sottoscrizione 1: nuovi messaggi
        let messageSubscription = CKQuerySubscription(
            recordType: RecordType.chatMessage,
            predicate: NSPredicate(value: true),
            subscriptionID: "new-chat-messages",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        
        let messageNotification = CKSubscription.NotificationInfo()
        messageNotification.shouldSendContentAvailable = true
        messageNotification.shouldBadge = true
        messageSubscription.notificationInfo = messageNotification
        
        // Sottoscrizione 2: aggiornamenti room
        let roomSubscription = CKQuerySubscription(
            recordType: RecordType.chatRoom,
            predicate: NSPredicate(value: true),
            subscriptionID: "chat-room-updates",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        
        let roomNotification = CKSubscription.NotificationInfo()
        roomNotification.shouldSendContentAvailable = true
        roomSubscription.notificationInfo = roomNotification
        
        do {
            // Salva entrambe le sottoscrizioni
            _ = try await publicDB.save(messageSubscription)
            _ = try await publicDB.save(roomSubscription)
            subscriptionId = messageSubscription.subscriptionID
            print("[CloudKitChat] ✅ Sottoscrizioni attivate (messaggi + room)")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Sottoscrizione già esistente, ok
            print("[CloudKitChat] ℹ️ Sottoscrizioni già esistenti")
        } catch {
            print("[CloudKitChat] ⚠️ Errore sottoscrizione: \(error)")
        }
    }
    
    // MARK: - Record Conversion
    
    private func recordToRoom(_ record: CKRecord) -> ChatRoom? {
        guard let roomId = record[RoomKeys.roomId] as? String,
              let name = record[RoomKeys.name] as? String,
              let participants = record[RoomKeys.participants] as? [String],
              let createdAt = record[RoomKeys.createdAt] as? Date else {
            return nil
        }
        
        let roomTypeRaw = record[RoomKeys.roomType] as? String ?? "direct"
        let roomType = ChatRoom.RoomType(rawValue: roomTypeRaw) ?? .direct
        
        return ChatRoom(
            id: roomId,
            name: name,
            participants: participants,
            admins: record[RoomKeys.admins] as? [String] ?? [],
            createdAt: createdAt,
            createdBy: record[RoomKeys.createdBy] as? String ?? "",
            lastMessageAt: record[RoomKeys.lastMessageAt] as? Date ?? createdAt,
            lastMessagePreview: record[RoomKeys.lastMessagePreview] as? String,
            lastMessageSender: record[RoomKeys.lastMessageSender] as? String,
            unreadCount: 0,
            roomType: roomType,
            linkedSinistroRif: record[RoomKeys.linkedSinistroRif] as? String,
            isMuted: record[RoomKeys.isMuted] as? Bool ?? false
        )
    }
    
    private func recordToMessage(_ record: CKRecord) -> ChatMessage? {
        guard let messageIdString = record[MessageKeys.messageId] as? String,
              let messageId = UUID(uuidString: messageIdString),
              let roomId = record[MessageKeys.roomId] as? String,
              let senderEmail = record[MessageKeys.senderEmail] as? String,
              let senderName = record[MessageKeys.senderName] as? String,
              let content = record[MessageKeys.content] as? String,
              let timestamp = record[MessageKeys.timestamp] as? Date else {
            return nil
        }
        
        // Deserializza mentions
        var mentions: [ChatMention] = []
        if let mentionsJSON = record[MessageKeys.mentionsJSON] as? String,
           let data = mentionsJSON.data(using: .utf8) {
            mentions = (try? JSONDecoder().decode([ChatMention].self, from: data)) ?? []
        }
        
        // Deserializza hashtags
        var hashtags: [ChatHashtag] = []
        if let hashtagsJSON = record[MessageKeys.hashtagsJSON] as? String,
           let data = hashtagsJSON.data(using: .utf8) {
            hashtags = (try? JSONDecoder().decode([ChatHashtag].self, from: data)) ?? []
        }
        
        // Deserializza attachments
        var attachments: [ChatAttachment] = []
        if let attachmentsJSON = record[MessageKeys.attachmentsJSON] as? String,
           let data = attachmentsJSON.data(using: .utf8) {
            attachments = (try? JSONDecoder().decode([ChatAttachment].self, from: data)) ?? []
        }
        
        // Campi collegamento sinistro
        let linkedSinistroRif = record[MessageKeys.linkedSinistroRif] as? String
        let isPinnedToDiario = record[MessageKeys.isPinnedToDiario] as? Bool ?? false
        var diarioEntryId: UUID? = nil
        if let diarioIdString = record[MessageKeys.diarioEntryId] as? String {
            diarioEntryId = UUID(uuidString: diarioIdString)
        }
        var linkedFromMessageId: UUID? = nil
        if let linkedFromString = record[MessageKeys.linkedFromMessageId] as? String {
            linkedFromMessageId = UUID(uuidString: linkedFromString)
        }
        
        // Read receipts
        var readReceipts: [ChatReadReceipt] = []
        if let rrJSON = record[MessageKeys.readReceiptsJSON] as? String,
           let data = rrJSON.data(using: .utf8) {
            readReceipts = (try? JSONDecoder().decode([ChatReadReceipt].self, from: data)) ?? []
        }
        
        return ChatMessage(
            id: messageId,
            roomId: roomId,
            senderEmail: senderEmail,
            senderName: senderName,
            content: content,
            mentions: mentions,
            hashtags: hashtags,
            attachments: attachments,
            timestamp: timestamp,
            isRead: false,
            readReceipts: readReceipts,
            linkedSinistroRif: linkedSinistroRif,
            isPinnedToDiario: isPinnedToDiario,
            diarioEntryId: diarioEntryId,
            linkedFromMessageId: linkedFromMessageId
        )
    }

    // MARK: - Undo send (5 min)
    
    func canUndoSend(_ message: ChatMessage, currentUserEmail: String?) -> Bool {
        guard message.isSentByCurrentUser(currentEmail: currentUserEmail) else { return false }
        guard message.isPinnedToDiario == false else { return false }
        return Date().timeIntervalSince(message.timestamp) <= 300
    }
    
    func undoSend(messageId: UUID, roomId: String, currentUserEmail: String?) async throws {
        guard let roomMessages = messages[roomId],
              let msg = roomMessages.first(where: { $0.id == messageId }) else { return }
        guard canUndoSend(msg, currentUserEmail: currentUserEmail) else { return }
        
        // 1) Delete CloudKit message record
        let recordID = CKRecord.ID(recordName: messageId.uuidString)
        _ = try await publicDB.deleteRecordReturningIDAsync(recordID)
        
        // 2) Delete attachment records (best-effort)
        for att in msg.attachments {
            let attID = CKRecord.ID(recordName: att.id.uuidString)
            _ = try? await publicDB.deleteRecordReturningIDAsync(attID)
        }
        
        // 3) Update local cache
        var updated = roomMessages
        updated.removeAll { $0.id == messageId }
        messages[roomId] = updated
        saveLocalMessages()
        
        // 4) Refresh room last message based on remaining messages
        await refreshRoomLastMessage(roomId: roomId)
    }
    
    private func refreshRoomLastMessage(roomId: String) async {
        do {
            // Fetch latest message
            let predicate = NSPredicate(format: "%K == %@", MessageKeys.roomId, roomId)
            let query = CKQuery(recordType: RecordType.chatMessage, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: MessageKeys.timestamp, ascending: false)]
            let records = try await publicDB.performQueryAsync(query)
            let latest = records.first.flatMap { recordToMessage($0) }
            
            guard let idx = rooms.firstIndex(where: { $0.id == roomId }) else { return }
            var room = rooms[idx]
            
            if let latest {
                room.lastMessageAt = latest.timestamp
                room.lastMessagePreview = latest.content.isEmpty && latest.hasAttachments ? "📎 Allegato" : String(latest.content.prefix(50))
                room.lastMessageSender = latest.senderName
            } else {
                room.lastMessageAt = room.createdAt
                room.lastMessagePreview = nil
                room.lastMessageSender = nil
            }
            
            // Persist CloudKit room metadata
            let roomRecordID = CKRecord.ID(recordName: roomId)
            let record = try await publicDB.fetchRecordAsync(roomRecordID)
            record[RoomKeys.lastMessageAt] = room.lastMessageAt as CKRecordValue
            record[RoomKeys.lastMessagePreview] = (room.lastMessagePreview ?? "") as CKRecordValue
            record[RoomKeys.lastMessageSender] = (room.lastMessageSender ?? "") as CKRecordValue
            _ = try await publicDB.saveRecordAsync(record)
            
            rooms[idx] = room
            saveLocalRooms()
        } catch {
            print("[CloudKitChat] ⚠️ refreshRoomLastMessage error: \(error)")
        }
    }

    // MARK: - Read Receipts
    
    private func addReadReceipt(messageId: UUID, roomId: String, userEmail: String, userName: String?) async throws {
        let normalizedEmail = userEmail.lowercased()
        
        // aggiorna locale
        if var roomMessages = messages[roomId],
           let idx = roomMessages.firstIndex(where: { $0.id == messageId }) {
            var msg = roomMessages[idx]
            if msg.readReceipts.contains(where: { $0.userEmail == normalizedEmail }) == false {
                msg.readReceipts.append(ChatReadReceipt(userEmail: normalizedEmail, userName: userName))
                roomMessages[idx] = msg
                messages[roomId] = roomMessages
                saveLocalMessages()
            } else {
                // già letto
                return
            }
        }
        
        // aggiorna CloudKit
        let recordID = CKRecord.ID(recordName: messageId.uuidString)
        let record = try await publicDB.fetchRecordAsync(recordID)
        
        var receipts: [ChatReadReceipt] = []
        if let rrJSON = record[MessageKeys.readReceiptsJSON] as? String,
           let data = rrJSON.data(using: .utf8) {
            receipts = (try? JSONDecoder().decode([ChatReadReceipt].self, from: data)) ?? []
        }
        
        if receipts.contains(where: { $0.userEmail == normalizedEmail }) == false {
            receipts.append(ChatReadReceipt(userEmail: normalizedEmail, userName: userName))
        }
        
        if let data = try? JSONEncoder().encode(receipts),
           let json = String(data: data, encoding: .utf8) {
            record[MessageKeys.readReceiptsJSON] = json as CKRecordValue
        }
        
        _ = try await publicDB.saveRecordAsync(record)
    }
    
    // MARK: - CloudKit Wrappers (using shared extensions)
    
    // MARK: - Local Persistence
    
    private let roomsKey = "cloudkit_chat_rooms"
    private let messagesKey = "cloudkit_chat_messages"
    
    private func saveLocalRooms() {
        if let data = try? JSONEncoder().encode(rooms) {
            UserDefaults.standard.set(data, forKey: roomsKey)
        }
    }
    
    private func loadLocalRooms() {
        if let data = UserDefaults.standard.data(forKey: roomsKey),
           let saved = try? JSONDecoder().decode([ChatRoom].self, from: data) {
            rooms = saved.filter { hiddenRoomIds.contains($0.id) == false }
        }
    }
    
    private func saveLocalMessages() {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: messagesKey)
        }
    }
    
    private func loadLocalMessages() {
        if let data = UserDefaults.standard.data(forKey: messagesKey),
           let saved = try? JSONDecoder().decode([String: [ChatMessage]].self, from: data) {
            // rimuovi messaggi delle room nascoste
            var cleaned = saved
            for rid in hiddenRoomIds {
                cleaned.removeValue(forKey: rid)
            }
            messages = cleaned
        }
    }
    
    private func persistHiddenRooms() {
        let arr = Array(hiddenRoomIds)
        UserDefaults.standard.set(arr, forKey: hiddenRoomsKeyForCurrentUser())
    }
    
    private func loadHiddenRooms() {
        let key = hiddenRoomsKeyForCurrentUser()
        let arr = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        hiddenRoomIds = Set(arr)
    }
    
    private func hiddenRoomsKeyForCurrentUser() -> String {
        let email = (GoogleAuthService.shared.userEmail ?? "unknown").lowercased()
        return "\(hiddenRoomsKey).\(email)"
    }
}
