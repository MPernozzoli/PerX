import Combine
import Foundation

@MainActor
final class CloudKitWhatsAppSyncService: ObservableObject {
    static let shared = CloudKitWhatsAppSyncService()

    @Published private(set) var messages: [String: [CloudKitWhatsAppMessage]] = [:]
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var isSyncing = false

    private let cursorKey = "backendWhatsAppLastCursor"
    private let cacheKey = "backendWhatsAppMessagesCache"

    private init() {
        loadLocalCache()
    }

    func syncFromHub(accountId: String, newMessages: [WhatsAppMessage], sinistroRiferimento: String?) async {
        guard !newMessages.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }

        for msg in newMessages {
            let cachedMessage = CloudKitWhatsAppMessage(from: msg, accountId: accountId, sinistroRiferimento: sinistroRiferimento)
            var chatMessages = messages[msg.chatId] ?? []
            if !chatMessages.contains(where: { $0.messageId == cachedMessage.messageId }) {
                chatMessages.append(cachedMessage)
                chatMessages.sort { $0.timestamp < $1.timestamp }
                messages[msg.chatId] = chatMessages
            }
        }

        saveLocalCache()
        lastSyncAt = Date()
    }

    func fetchMessages(forSinistro riferimento: String) async -> [CloudKitWhatsAppMessage] {
        messages.values
            .flatMap { $0 }
            .filter { $0.sinistroRiferimento == riferimento }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func fetchMessages(forChat chatId: String) async -> [CloudKitWhatsAppMessage] {
        messages[chatId] ?? []
    }

    func getLastSyncTimestamp(accountId: String) -> Date? {
        UserDefaults.standard.object(forKey: "\(cursorKey)_\(accountId)") as? Date
    }

    func setLastSyncTimestamp(_ date: Date, accountId: String) {
        UserDefaults.standard.set(date, forKey: "\(cursorKey)_\(accountId)")
    }

    private func loadLocalCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([String: [CloudKitWhatsAppMessage]].self, from: data) else {
            return
        }
        messages = cached
    }

    private func saveLocalCache() {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

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
        id = msg.id
        messageId = msg.id
        self.accountId = accountId
        chatId = msg.chatId
        from = msg.from
        to = msg.to ?? ""
        body = msg.body
        timestamp = msg.timestamp
        direction = msg.isFromMe ? "outbound" : "inbound"
        mediaType = msg.type != MessageType.text ? msg.type.rawValue : nil
        mediaId = msg.type != MessageType.text ? msg.id : nil
        mediaRelativePath = nil
        mediaFilename = msg.mediaFilename
        self.sinistroRiferimento = sinistroRiferimento ?? msg.sinistroRiferimento
        isRead = msg.isRead
        isSent = msg.isFromMe
    }
}
