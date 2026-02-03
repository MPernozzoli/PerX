//
//  iPadChatService.swift
//  PerX per iPad
//
//  Servizio chat per iPad basato su CloudKit.
//  Riusa la logica del CloudKitChatService ma con scope per utente.
//

import Foundation
import CloudKit
import Combine

@MainActor
final class iPadChatService: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var rooms: [ChatRoomDTO] = []
    @Published private(set) var messages: [String: [ChatMessageDTO]] = [:] // roomId -> messages
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    
    // MARK: - Dependencies
    
    private let container: CKContainer
    private let publicDB: CKDatabase
    private let userEmail: String
    private var pollTimer: Timer?
    
    // MARK: - Record Types
    
    private enum RecordType {
        static let chatRoom = "ChatRoom"
        static let chatMessage = "ChatMessage"
    }
    
    // MARK: - Init
    
    init(userEmail: String, container: CKContainer = CKContainer(identifier: "iCloud.it.pernozzoli.PerX")) {
        self.userEmail = userEmail.lowercased()
        self.container = container
        self.publicDB = container.publicCloudDatabase
    }
    
    // MARK: - Lifecycle
    
    func start() async {
        print("[iPadChat] ▶️ Avvio chat per: \(userEmail)")
        
        await fetchRooms()
        startPolling()
    }
    
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        print("[iPadChat] ⏹️ Chat stoppato")
    }
    
    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchRooms()
            }
        }
    }
    
    // MARK: - Rooms
    
    func fetchRooms() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Fetch rooms dove l'utente è partecipante
            let predicate = NSPredicate(format: "%@ IN participants", userEmail)
            let query = CKQuery(recordType: RecordType.chatRoom, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "lastMessageAt", ascending: false)]
            
            let records = try await performQuery(query)
            rooms = records.compactMap { ChatRoomDTO(from: $0) }
            
        } catch {
            lastError = error.localizedDescription
            print("[iPadChat] ❌ Errore fetch rooms: \(error)")
        }
    }
    
    // MARK: - Messages
    
    func fetchMessages(for roomId: String) async -> [ChatMessageDTO] {
        do {
            let predicate = NSPredicate(format: "roomId == %@", roomId)
            let query = CKQuery(recordType: RecordType.chatMessage, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            
            let records = try await performQuery(query)
            let msgs = records.compactMap { ChatMessageDTO(from: $0) }
            
            messages[roomId] = msgs
            return msgs
            
        } catch {
            lastError = error.localizedDescription
            print("[iPadChat] ❌ Errore fetch messages: \(error)")
            return []
        }
    }
    
    func sendMessage(to roomId: String, content: String, linkedSinistroRif: String? = nil) async throws -> ChatMessageDTO {
        let messageId = UUID().uuidString
        let record = CKRecord(recordType: RecordType.chatMessage, recordID: CKRecord.ID(recordName: messageId))
        
        record["messageId"] = messageId as CKRecordValue
        record["roomId"] = roomId as CKRecordValue
        record["senderEmail"] = userEmail as CKRecordValue
        record["senderName"] = (SessionCoordinator.shared.currentUserName ?? userEmail) as CKRecordValue
        record["content"] = content as CKRecordValue
        record["timestamp"] = Date() as CKRecordValue
        
        if let rif = linkedSinistroRif {
            record["linkedSinistroRif"] = rif as CKRecordValue
        }
        
        _ = try await saveRecord(record)
        
        // Aggiorna lastMessageAt nella room
        await updateRoomLastMessage(roomId: roomId, preview: content)
        
        let message = ChatMessageDTO(from: record)!
        
        // Aggiungi alla cache locale
        if messages[roomId] == nil {
            messages[roomId] = []
        }
        messages[roomId]?.append(message)
        
        return message
    }
    
    private func updateRoomLastMessage(roomId: String, preview: String) async {
        do {
            let recordID = CKRecord.ID(recordName: roomId)
            let record = try await fetchRecord(recordID)
            
            record["lastMessageAt"] = Date() as CKRecordValue
            record["lastMessagePreview"] = String(preview.prefix(100)) as CKRecordValue
            record["lastMessageSender"] = userEmail as CKRecordValue
            
            _ = try await saveRecord(record)
            
        } catch {
            print("[iPadChat] ⚠️ Errore update room: \(error)")
        }
    }
    
    // MARK: - Create Room
    
    func createDirectChat(with otherUserEmail: String) async throws -> ChatRoomDTO {
        let participants = [userEmail, otherUserEmail.lowercased()].sorted()
        let roomId = "direct_\(participants.joined(separator: "_").hashValue)"
        
        // Verifica se esiste già
        if let existing = rooms.first(where: { $0.id == roomId }) {
            return existing
        }
        
        let record = CKRecord(recordType: RecordType.chatRoom, recordID: CKRecord.ID(recordName: roomId))
        record["roomId"] = roomId as CKRecordValue
        record["name"] = otherUserEmail as CKRecordValue
        record["participants"] = participants as CKRecordValue
        record["admins"] = [userEmail] as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        record["createdBy"] = userEmail as CKRecordValue
        record["lastMessageAt"] = Date() as CKRecordValue
        record["roomType"] = "direct" as CKRecordValue
        
        _ = try await saveRecord(record)
        
        let room = ChatRoomDTO(from: record)!
        rooms.insert(room, at: 0)
        
        return room
    }
    
    // MARK: - CloudKit Helpers
    
    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            publicDB.save(record) { saved, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: saved ?? record)
                }
            }
        }
    }
    
    private func fetchRecord(_ recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            publicDB.fetch(withRecordID: recordID) { record, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let record = record {
                    continuation.resume(returning: record)
                } else {
                    continuation.resume(throwing: NSError(domain: "CK", code: -1, userInfo: nil))
                }
            }
        }
    }
    
    private func performQuery(_ query: CKQuery) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            publicDB.perform(query, inZoneWith: nil) { records, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: records ?? [])
                }
            }
        }
    }
}

// MARK: - DTOs

struct ChatRoomDTO: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let participants: [String]
    let admins: [String]
    let createdAt: Date
    let createdBy: String
    let lastMessageAt: Date
    let lastMessagePreview: String?
    let lastMessageSender: String?
    let roomType: String
    let linkedSinistroRif: String?
    
    init?(from record: CKRecord) {
        guard let roomId = record["roomId"] as? String else { return nil }
        
        self.id = roomId
        self.name = record["name"] as? String ?? ""
        self.participants = record["participants"] as? [String] ?? []
        self.admins = record["admins"] as? [String] ?? []
        self.createdAt = record["createdAt"] as? Date ?? Date()
        self.createdBy = record["createdBy"] as? String ?? ""
        self.lastMessageAt = record["lastMessageAt"] as? Date ?? Date()
        self.lastMessagePreview = record["lastMessagePreview"] as? String
        self.lastMessageSender = record["lastMessageSender"] as? String
        self.roomType = record["roomType"] as? String ?? "direct"
        self.linkedSinistroRif = record["linkedSinistroRif"] as? String
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ChatRoomDTO, rhs: ChatRoomDTO) -> Bool {
        lhs.id == rhs.id
    }
}

struct ChatMessageDTO: Identifiable, Codable {
    let id: String
    let roomId: String
    let senderEmail: String
    let senderName: String
    let content: String
    let timestamp: Date
    let linkedSinistroRif: String?
    
    var isFromCurrentUser: Bool {
        senderEmail.lowercased() == SessionCoordinator.shared.currentUserEmail?.lowercased()
    }
    
    init?(from record: CKRecord) {
        guard let messageId = record["messageId"] as? String else { return nil }
        
        self.id = messageId
        self.roomId = record["roomId"] as? String ?? ""
        self.senderEmail = record["senderEmail"] as? String ?? ""
        self.senderName = record["senderName"] as? String ?? ""
        self.content = record["content"] as? String ?? ""
        self.timestamp = record["timestamp"] as? Date ?? Date()
        self.linkedSinistroRif = record["linkedSinistroRif"] as? String
    }
}
