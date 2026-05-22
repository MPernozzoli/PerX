import Foundation
import Combine

// MARK: - DTOs

struct ChatRoomDTO: Identifiable, Codable {
    let id: String
    let name: String
    let lastMessageAt: Date
    let lastMessagePreview: String?
    let lastMessageSender: String?
}

struct ChatMessageDTO: Identifiable, Codable {
    let id: String
    let senderName: String
    let content: String
    let timestamp: Date
}

// MARK: - Service

/// Servizio chat per iPad basato sul backend Supabase (internal-chat API).
/// CloudKit rimosso: tutti i messaggi passano per il backend.
@MainActor
final class iPadChatService: ObservableObject {

    @Published private(set) var rooms: [ChatRoomDTO] = []
    @Published private(set) var messages: [String: [ChatMessageDTO]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let hubClient = HubAPIClient.shared
    private let userEmail: String
    private var pollTimer: Timer?

    init(userEmail: String) {
        self.userEmail = userEmail.lowercased()
    }

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
        pollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.fetchRooms() }
        }
    }

    func fetchRooms() async {
        guard hubClient.isCloudConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            rooms = try await hubClient.getChatThreads()
        } catch {
            lastError = error.localizedDescription
            print("[iPadChat] ❌ Errore fetch rooms: \(error)")
        }
    }

    func fetchMessages(for roomId: String) async -> [ChatMessageDTO] {
        guard hubClient.isCloudConfigured else { return [] }
        do {
            let msgs = try await hubClient.getChatMessages(threadId: roomId)
            messages[roomId] = msgs
            return msgs
        } catch {
            lastError = error.localizedDescription
            print("[iPadChat] ❌ Errore fetch messages: \(error)")
            return []
        }
    }

    func sendMessage(to roomId: String, content: String, linkedSinistroRif: String? = nil) async throws -> ChatMessageDTO {
        let sent = try await hubClient.sendChatMessage(threadId: roomId, content: content)
        if messages[roomId] == nil { messages[roomId] = [] }
        messages[roomId]?.append(sent)
        // Aggiorna preview nella room
        if let idx = rooms.firstIndex(where: { $0.id == roomId }) {
            let r = rooms[idx]
            rooms[idx] = ChatRoomDTO(id: r.id, name: r.name, lastMessageAt: sent.timestamp,
                                     lastMessagePreview: content, lastMessageSender: userEmail)
        }
        return sent
    }

    func createDirectChat(with otherUserEmail: String) async throws -> ChatRoomDTO {
        let room = try await hubClient.createChatThread(with: otherUserEmail)
        rooms.insert(room, at: 0)
        return room
    }
}
