import Foundation
import Combine
import UniformTypeIdentifiers

/// Chat interna compatibile con le viste esistenti, alimentata dal backend Supabase.
@MainActor
final class CloudKitChatService: ObservableObject {
    static let shared = CloudKitChatService()

    @Published private(set) var rooms: [ChatRoom] = []
    @Published private(set) var messages: [String: [ChatMessage]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var uploadProgress: Double = 0
    @Published private(set) var hiddenRoomIds: Set<String> = []
    @Published var activeRoomId: String? = nil
    @Published var activeLinkedSinistro: String? = nil

    private let adapter = CloudCollaborationAdapter.shared
    private let hiddenRoomsKey = "backend_chat_hidden_rooms"
    private let localRoomsKey = "backend_chat_rooms_cache"
    private let localMessagesKey = "backend_chat_messages_cache"
    private var pollTimer: Timer?
    private var pollingInterval: TimeInterval = 5.0

    private init() {
        loadHiddenRooms()
        loadLocalRooms()
        loadLocalMessages()
    }

    func start() async {
        await fetchRooms()
        if let activeRoomId {
            await fetchMessages(for: activeRoomId)
        }
        startPolling()
    }

    func handleCloudKitNotification() async {
        await fetchRooms()
        if let activeRoomId {
            await fetchMessages(for: activeRoomId)
        }
    }

    func setPollingInterval(_ interval: TimeInterval) {
        guard interval != pollingInterval else { return }
        pollingInterval = interval
        startPolling()
    }

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchRooms()
                if let active = self.activeRoomId {
                    await self.fetchMessages(for: active)
                }
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func hideRoomLocally(_ roomId: String) {
        hiddenRoomIds.insert(roomId)
        persistHiddenRooms()
        rooms.removeAll { $0.id == roomId }
        messages.removeValue(forKey: roomId)
        saveLocalRooms()
        saveLocalMessages()
    }

    func createRoom(
        name: String,
        participants: [String],
        roomType: ChatRoom.RoomType = .direct,
        linkedSinistroRif: String? = nil
    ) async throws -> ChatRoom {
        let memberIds = participants.compactMap { email in
            CloudKitUserDirectoryService.shared.user(email: email)?.backendUserId
        }
        let dto = try await adapter.createInternalThread(
            sinistroRef: linkedSinistroRif,
            title: name,
            memberUserIds: Array(Set(memberIds))
        )
        let currentEmail = CurrentUserService.shared.currentEmail?.lowercased() ?? GoogleAuthService.shared.userEmail?.lowercased() ?? ""
        let room = ChatRoom(
            id: dto.id,
            name: dto.title,
            participants: Array(Set((participants + [currentEmail]).filter { !$0.isEmpty }.map { $0.lowercased() })),
            admins: currentEmail.isEmpty ? [] : [currentEmail],
            createdAt: dto.created_at,
            createdBy: currentEmail,
            roomType: roomType,
            linkedSinistroRif: linkedSinistroRif
        )
        upsertRoom(room)
        return room
    }

    func createGroup(name: String, participants: [String]) async throws -> ChatRoom {
        try await createRoom(name: name, participants: participants, roomType: .group)
    }

    func findOrCreateSinistroChat(riferimento: String, participants: [String]) async throws -> ChatRoom {
        if let existing = rooms.first(where: { $0.linkedSinistroRif == riferimento }) {
            return existing
        }
        return try await createRoom(
            name: "Sinistro \(riferimento)",
            participants: participants,
            roomType: .sinistro,
            linkedSinistroRif: riferimento
        )
    }

    func findOrCreateDirectChat(with userEmail: String, currentUserEmail: String) async throws -> ChatRoom {
        let normalized = [userEmail, currentUserEmail].map { $0.lowercased() }.sorted()
        if let existing = rooms.first(where: { room in
            room.isDirect && normalized.allSatisfy { room.participants.map { $0.lowercased() }.contains($0) }
        }) {
            return existing
        }
        let otherName = CloudKitUserDirectoryService.shared.user(email: userEmail)?.displayName ?? userEmail
        return try await createRoom(name: otherName, participants: normalized, roomType: .direct)
    }

    func addParticipants(_ emails: [String], to roomId: String) async throws {
        guard let index = rooms.firstIndex(where: { $0.id == roomId }) else { return }
        rooms[index].participants = Array(Set(rooms[index].participants + emails.map { $0.lowercased() }))
        saveLocalRooms()
    }

    func removeParticipant(_ email: String, from roomId: String) async throws {
        guard let index = rooms.firstIndex(where: { $0.id == roomId }) else { return }
        rooms[index].participants.removeAll { $0.lowercased() == email.lowercased() }
        saveLocalRooms()
    }

    func sendMessage(
        roomId: String,
        content: String,
        mentions: [ChatMention] = [],
        hashtags: [ChatHashtag] = [],
        attachments: [ChatAttachment] = [],
        senderEmail: String? = nil,
        senderName: String? = nil,
        pinToDiario: Bool = false,
        linkedSinistroRif: String? = nil,
        linkedFromMessageId: UUID? = nil
    ) async throws -> ChatMessage {
        let dto = try await adapter.sendInternalMessage(threadId: roomId, body: content)
        let senderEmail = senderEmail?.lowercased() ?? CurrentUserService.shared.currentEmail?.lowercased() ?? GoogleAuthService.shared.userEmail?.lowercased() ?? ""
        let message = ChatMessage(
            id: UUID(uuidString: dto.id) ?? UUID(),
            roomId: roomId,
            senderEmail: senderEmail,
            senderName: senderName ?? UserProfileService.shared.currentProfile?.displayName ?? CurrentUserService.shared.currentUsernameOrDefault(senderEmail),
            content: dto.body_text ?? content,
            mentions: mentions,
            hashtags: hashtags,
            attachments: attachments,
            timestamp: dto.created_at,
            linkedSinistroRif: linkedSinistroRif,
            isPinnedToDiario: pinToDiario,
            linkedFromMessageId: linkedFromMessageId
        )
        appendMessage(message)
        return message
    }

    func uploadAttachment(from url: URL, roomId: String) async throws -> ChatAttachment {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        return ChatAttachment(
            type: .from(mimeType: values.contentType?.preferredMIMEType ?? "application/octet-stream"),
            fileName: url.lastPathComponent,
            fileSize: Int64(values.fileSize ?? 0),
            mimeType: values.contentType?.preferredMIMEType ?? "application/octet-stream",
            localURL: url.path
        )
    }

    func downloadAttachment(_ attachment: ChatAttachment) async throws -> URL {
        if let localURL = attachment.localURL {
            return URL(fileURLWithPath: localURL)
        }
        throw NSError(domain: "BackendChatService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Allegato non disponibile localmente"])
    }

    func linkToSinistro(_ riferimento: String, in roomId: String) {
        activeLinkedSinistro = riferimento
        if let index = rooms.firstIndex(where: { $0.id == roomId }) {
            rooms[index].linkedSinistroRif = riferimento
            saveLocalRooms()
        }
    }

    func unlinkFromSinistro(in roomId: String) {
        activeLinkedSinistro = nil
        if let index = rooms.firstIndex(where: { $0.id == roomId }) {
            rooms[index].linkedSinistroRif = nil
            saveLocalRooms()
        }
    }

    func updateMessageLink(_ messageId: UUID, in roomId: String, linkedSinistroRif: String?, pinToDiario: Bool) async throws {
        guard var roomMessages = messages[roomId],
              let index = roomMessages.firstIndex(where: { $0.id == messageId }) else { return }
        roomMessages[index].linkedSinistroRif = linkedSinistroRif
        roomMessages[index].isPinnedToDiario = pinToDiario
        messages[roomId] = roomMessages
        saveLocalMessages()
    }

    func fetchMessages(for roomId: String) async {
        guard adapter.isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let remote = try await adapter.getInternalMessages(threadId: roomId)
            messages[roomId] = remote.map { dto in
                ChatMessage(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    roomId: dto.thread_id,
                    senderEmail: dto.sender_user_id ?? "",
                    senderName: dto.sender_user_id ?? "Utente",
                    content: dto.body_text ?? "",
                    timestamp: dto.created_at,
                    linkedSinistroRif: dto.claim_id
                )
            }
            saveLocalMessages()
        } catch {
            self.error = error.localizedDescription
            print("[BackendChat] fetchMessages failed: \(error)")
        }
    }

    func fetchRooms() async {
        guard adapter.isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let remote = try await adapter.getInternalThreads()
            rooms = remote.map { dto in
                ChatRoom(
                    id: dto.id,
                    name: dto.title,
                    participants: [],
                    createdAt: dto.created_at,
                    createdBy: dto.created_by_user_id ?? "",
                    roomType: ChatRoom.RoomType(rawValue: dto.thread_type) ?? .group,
                    linkedSinistroRif: dto.claim_id
                )
            }.filter { !hiddenRoomIds.contains($0.id) }
            saveLocalRooms()
        } catch {
            self.error = error.localizedDescription
            print("[BackendChat] fetchRooms failed: \(error)")
        }
    }

    func markMessagesAsRead(in roomId: String, currentUserEmail: String, sendReadReceipts: Bool = true) {
        guard var roomMessages = messages[roomId] else { return }
        for index in roomMessages.indices where roomMessages[index].senderEmail.lowercased() != currentUserEmail.lowercased() {
            roomMessages[index].isRead = true
        }
        messages[roomId] = roomMessages
        saveLocalMessages()
    }

    func toggleMute(for roomId: String) async throws {
        guard let index = rooms.firstIndex(where: { $0.id == roomId }) else { return }
        rooms[index].isMuted.toggle()
        saveLocalRooms()
    }

    func canUndoSend(_ message: ChatMessage, currentUserEmail: String?) -> Bool {
        message.senderEmail.lowercased() == currentUserEmail?.lowercased()
            && Date().timeIntervalSince(message.timestamp) < 120
    }

    func undoSend(messageId: UUID, roomId: String, currentUserEmail: String?) async throws {
        guard var roomMessages = messages[roomId],
              let index = roomMessages.firstIndex(where: { $0.id == messageId }),
              canUndoSend(roomMessages[index], currentUserEmail: currentUserEmail) else { return }
        roomMessages.remove(at: index)
        messages[roomId] = roomMessages
        saveLocalMessages()
    }

    private func appendMessage(_ message: ChatMessage) {
        var roomMessages = messages[message.roomId] ?? []
        roomMessages.append(message)
        messages[message.roomId] = roomMessages
        if let index = rooms.firstIndex(where: { $0.id == message.roomId }) {
            rooms[index].lastMessageAt = message.timestamp
            rooms[index].lastMessagePreview = message.content
            rooms[index].lastMessageSender = message.senderName
        }
        saveLocalMessages()
        saveLocalRooms()
    }

    private func upsertRoom(_ room: ChatRoom) {
        if let index = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[index] = room
        } else if !hiddenRoomIds.contains(room.id) {
            rooms.insert(room, at: 0)
        }
        saveLocalRooms()
    }

    private func saveLocalRooms() {
        if let data = try? JSONEncoder().encode(rooms) {
            UserDefaults.standard.set(data, forKey: localRoomsKey)
        }
    }

    private func loadLocalRooms() {
        guard let data = UserDefaults.standard.data(forKey: localRoomsKey),
              let saved = try? JSONDecoder().decode([ChatRoom].self, from: data) else { return }
        rooms = saved.filter { !hiddenRoomIds.contains($0.id) }
    }

    private func saveLocalMessages() {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: localMessagesKey)
        }
    }

    private func loadLocalMessages() {
        guard let data = UserDefaults.standard.data(forKey: localMessagesKey),
              let saved = try? JSONDecoder().decode([String: [ChatMessage]].self, from: data) else { return }
        messages = saved
    }

    private func persistHiddenRooms() {
        UserDefaults.standard.set(Array(hiddenRoomIds), forKey: hiddenRoomsKeyForCurrentUser())
    }

    private func loadHiddenRooms() {
        hiddenRoomIds = Set(UserDefaults.standard.stringArray(forKey: hiddenRoomsKeyForCurrentUser()) ?? [])
    }

    private func hiddenRoomsKeyForCurrentUser() -> String {
        let email = CurrentUserService.shared.currentEmail?.lowercased() ?? GoogleAuthService.shared.userEmail?.lowercased() ?? "anonymous"
        return "\(hiddenRoomsKey)_\(email)"
    }
}
