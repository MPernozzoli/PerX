import Foundation
import CloudKit
import Combine

/// Sincronizza i metadata dei messaggi WhatsApp su CloudKit (no file binari)
/// NOTA: Con la nuova architettura Hub-only, i messaggi sono persistiti sull'Hub.
/// Questo servizio ora sincronizza solo per backup/cross-device tramite CloudKit.
@MainActor
final class CloudKitWhatsAppSyncService: ObservableObject {
    static let shared = CloudKitWhatsAppSyncService()
    
    @Published private(set) var messages: [String: [CloudKitWhatsAppMessage]] = [:] // chatId -> messages
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var isSyncing = false
    
    private let container: CKContainer
    private let publicDB: CKDatabase
    private var cancellables = Set<AnyCancellable>()
    
    private let recordType = "WhatsAppMessage"
    private let cursorKey = "cloudkitWhatsAppLastCursor"
    
    private init(container: CKContainer = CKContainer(identifier: "iCloud.it.pernozzoli.PerX")) {
        self.container = container
        self.publicDB = container.publicCloudDatabase
        loadLocalCache()
    }
    
    // MARK: - Public API
    
    /// Sincronizza i messaggi da Hub e salva su CloudKit per backup
    func syncFromHub(accountId: String, newMessages: [WhatsAppMessage], sinistroRiferimento: String?) async {
        guard !newMessages.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        for msg in newMessages {
            let record = createRecord(from: msg, accountId: accountId, sinistroRiferimento: sinistroRiferimento)
            do {
                _ = try await saveRecord(record)
                
                // Aggiorna cache locale
                let cloudMsg = CloudKitWhatsAppMessage(from: msg, accountId: accountId, sinistroRiferimento: sinistroRiferimento)
                let chatId = msg.chatId
                if messages[chatId] == nil { messages[chatId] = [] }
                if !messages[chatId]!.contains(where: { $0.messageId == cloudMsg.messageId }) {
                    messages[chatId]!.append(cloudMsg)
                    messages[chatId]!.sort { $0.timestamp < $1.timestamp }
                }
            } catch {
                print("[CloudKitWhatsApp] Errore salvataggio messaggio: \(error.localizedDescription)")
            }
        }
        
        saveLocalCache()
        lastSyncAt = Date()
    }
    
    /// Carica messaggi da CloudKit per un sinistro
    func fetchMessages(forSinistro riferimento: String) async -> [CloudKitWhatsAppMessage] {
        let predicate = NSPredicate(format: "sinistroRiferimento == %@", riferimento)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        do {
            let records = try await performQuery(query)
            return records.compactMap { CloudKitWhatsAppMessage(from: $0) }
        } catch {
            print("[CloudKitWhatsApp] Errore fetch: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Carica messaggi da CloudKit per una chat
    func fetchMessages(forChat chatId: String) async -> [CloudKitWhatsAppMessage] {
        // Prima controlla cache
        if let cached = messages[chatId], !cached.isEmpty {
            return cached
        }
        
        let predicate = NSPredicate(format: "chatId == %@", chatId)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        do {
            let records = try await performQuery(query)
            let msgs = records.compactMap { CloudKitWhatsAppMessage(from: $0) }
            messages[chatId] = msgs
            return msgs
        } catch {
            print("[CloudKitWhatsApp] Errore fetch chat: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Ultimo timestamp sincronizzato per un account
    func getLastSyncTimestamp(accountId: String) -> Date? {
        let key = "\(cursorKey)_\(accountId)"
        return UserDefaults.standard.object(forKey: key) as? Date
    }
    
    func setLastSyncTimestamp(_ date: Date, accountId: String) {
        let key = "\(cursorKey)_\(accountId)"
        UserDefaults.standard.set(date, forKey: key)
    }
    
    // MARK: - Private
    
    private func createRecord(from msg: WhatsAppMessage, accountId: String, sinistroRiferimento: String?) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "wa_\(msg.id)")
        let record = CKRecord(recordType: recordType, recordID: recordID)
        
        record["messageId"] = msg.id as CKRecordValue
        record["accountId"] = accountId as CKRecordValue
        record["chatId"] = msg.chatId as CKRecordValue
        record["from"] = msg.from as CKRecordValue
        record["to"] = (msg.to ?? "") as CKRecordValue
        record["direction"] = (msg.isFromMe ? "outbound" : "inbound") as CKRecordValue
        record["timestamp"] = msg.timestamp as CKRecordValue
        record["body"] = msg.body as CKRecordValue
        
        // Media info (solo metadata, no file)
        if msg.type != MessageType.text {
            record["mediaType"] = msg.type.rawValue as CKRecordValue
            record["mediaId"] = msg.id as CKRecordValue
        }
        
        // Collegamento sinistro
        if let rif = sinistroRiferimento ?? msg.sinistroRiferimento {
            record["sinistroRiferimento"] = rif as CKRecordValue
        }
        
        record["isRead"] = msg.isRead as CKRecordValue
        record["isSent"] = msg.isFromMe as CKRecordValue
        
        return record
    }
    
    // MARK: - CloudKit wrappers
    
    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        do {
            return try await publicDB.saveRecordAsync(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            return record
        }
    }
    
    private func performQuery(_ query: CKQuery) async throws -> [CKRecord] {
        try await publicDB.performQueryAsync(query)
    }
    
    // MARK: - Local Cache
    
    private let cacheKey = "cloudkitWhatsAppMessagesCache"
    
    private func loadLocalCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }
        if let cached = try? JSONDecoder().decode([String: [CloudKitWhatsAppMessage]].self, from: data) {
            messages = cached
        }
    }
    
    private func saveLocalCache() {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}

// MARK: - CloudKit Message Model

struct CloudKitWhatsAppMessage: Codable, Identifiable {
    let id: String
    let messageId: String
    let accountId: String
    let chatId: String
    let from: String
    let to: String
    let body: String
    let timestamp: Date
    let direction: String
    let mediaType: String?
    let mediaId: String?
    let mediaRelativePath: String?
    let mediaFilename: String?
    let sinistroRiferimento: String?
    let isRead: Bool
    let isSent: Bool
    
    init(from msg: WhatsAppMessage, accountId: String, sinistroRiferimento: String?) {
        self.id = msg.id
        self.messageId = msg.id
        self.accountId = accountId
        self.chatId = msg.chatId
        self.from = msg.from
        self.to = msg.to ?? ""
        self.body = msg.body
        self.timestamp = msg.timestamp
        self.direction = msg.isFromMe ? "outbound" : "inbound"
        self.mediaType = msg.type != MessageType.text ? msg.type.rawValue : nil
        self.mediaId = msg.type != MessageType.text ? msg.id : nil
        self.mediaRelativePath = nil
        self.mediaFilename = msg.mediaFilename
        self.sinistroRiferimento = sinistroRiferimento ?? msg.sinistroRiferimento
        self.isRead = msg.isRead
        self.isSent = msg.isFromMe
    }
    
    init?(from record: CKRecord) {
        guard let messageId = record["messageId"] as? String else { return nil }
        
        self.id = messageId
        self.messageId = messageId
        self.accountId = record["accountId"] as? String ?? ""
        self.chatId = record["chatId"] as? String ?? ""
        self.from = record["from"] as? String ?? ""
        self.to = record["to"] as? String ?? ""
        self.body = record["body"] as? String ?? ""
        self.timestamp = record["timestamp"] as? Date ?? Date()
        self.direction = record["direction"] as? String ?? "inbound"
        self.mediaType = record["mediaType"] as? String
        self.mediaId = record["mediaId"] as? String ?? ((self.mediaType != nil) ? messageId : nil)
        self.mediaRelativePath = record["mediaRelativePath"] as? String
        self.mediaFilename = record["mediaFilename"] as? String
        self.sinistroRiferimento = record["sinistroRiferimento"] as? String
        self.isRead = record["isRead"] as? Bool ?? false
        self.isSent = record["isSent"] as? Bool ?? false
    }
    
    func toWhatsAppMessage() -> WhatsAppMessage {
        WhatsAppMessage(
            id: messageId,
            chatId: chatId,
            from: from,
            to: to.isEmpty ? nil : to,
            body: body,
            timestamp: timestamp,
            isFromMe: isSent,
            isRead: isRead,
            type: mediaType.flatMap { MessageType(rawValue: $0) } ?? MessageType.text,
            mediaFilename: mediaFilename,
            sinistroRiferimento: sinistroRiferimento
        )
    }
}
