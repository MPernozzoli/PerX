import Foundation
import Combine

/// Servizio WhatsApp - comunica SOLO tramite Hub
/// L'Hub fa da proxy verso il WA Bridge
@MainActor
class WhatsAppService: ObservableObject {
    static let shared = WhatsAppService()
    
    /// WhatsApp è disponibile solo se l'Hub è raggiungibile
    static var isAvailable: Bool {
        !HubConfigService.shared.resolvedHubBaseURL().isEmpty
    }
    
    // MARK: - Published Properties
    
    @Published var connectionStatus: String = "disconnected"
    @Published var isConnected = false
    @Published var qrCode: String?
    @Published var selectedAccountId: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private
    
    private var pollingTimer: Timer?
    private let hubClient = HubAPIClient.shared
    private var cancellables = Set<AnyCancellable>()
    private let legacySelectedAccountKey = "whatsapp_selected_account"
    
    private init() {
        syncSelectedAccountWithCurrentUser()

        CurrentUserService.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleCurrentUserChanged()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .init("GoogleAuthStateChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleCurrentUserChanged()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Lifecycle
    
    func start() {
        guard Self.isAvailable else {
            print("[WhatsAppService] ⚠️ Hub non configurato")
            return
        }
        
        syncSelectedAccountWithCurrentUser()
        
        Task { await checkStatus() }
    }
    
    func stop() {
        stopPolling()
    }
    
    // MARK: - Account Management
    
    func selectAccount(_ accountId: String) {
        let normalized = normalizedAccountId(accountId)
        guard isAccountAllowedForCurrentUser(normalized) else {
            print("[WhatsAppService] selectAccount bloccato: accountId '\(accountId)' non appartiene all'utente corrente")
            syncSelectedAccountWithCurrentUser(forceCurrentUser: true)
            return
        }

        selectedAccountId = normalized
        UserDefaults.standard.set(normalized, forKey: selectedAccountKey)
        Task { await checkStatus() }
    }
    
    // MARK: - Connection
    
    func connect() async {
        syncSelectedAccountWithCurrentUser(forceCurrentUser: true)
        
        guard !selectedAccountId.isEmpty else {
            errorMessage = "Nessun account selezionato"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Inizializza client tramite Hub
            try await hubClient.localPost(
                endpoint: "whatsapp/clients/\(selectedAccountId)/init",
                body: ["phoneNumber": ""]
            )
            
            connectionStatus = "initializing"
            
            // Avvia polling per QR/status
            startPolling()
            
        } catch {
            errorMessage = "Errore connessione: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    func disconnect() async {
        guard !selectedAccountId.isEmpty else { return }
        
        stopPolling()
        
        do {
            try await hubClient.localPost(
                endpoint: "whatsapp/clients/\(selectedAccountId)/disconnect",
                body: EmptyBody()
            )
            
            isConnected = false
            qrCode = nil
            connectionStatus = "disconnected"
            
        } catch {
            print("[WhatsAppService] Errore disconnessione: \(error)")
        }
    }
    
    func checkStatus() async {
        syncSelectedAccountWithCurrentUser()
        guard !selectedAccountId.isEmpty else { return }
        
        do {
            let response: QRStatusResponse = try await hubClient.localGet(
                endpoint: "whatsapp/clients/\(selectedAccountId)/qr"
            )
            
            qrCode = response.qr
            connectionStatus = response.status
            isConnected = response.status == "ready"
            
            if isConnected {
                isLoading = false
            }
            
        } catch {
            // Client non esiste o Hub non raggiungibile
            connectionStatus = "disconnected"
            isConnected = false
        }
    }
    
    // MARK: - Polling
    
    private func startPolling() {
        stopPolling()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await CPUThrottler.shared.runWithThrottle {
                    await self.checkStatus()
                    if self.isConnected {
                        self.stopPolling()
                        self.isLoading = false
                    }
                }
            }
        }
    }
    
    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    // MARK: - Chats & Messages (via Hub)
    
    func fetchChats() async throws -> [WhatsAppChat] {
        syncSelectedAccountWithCurrentUser()
        guard !selectedAccountId.isEmpty else {
            print("[WhatsAppService] fetchChats: accountId vuoto")
            return []
        }
        
        let encodedAccountId = selectedAccountId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? selectedAccountId
        let endpoint = "whatsapp/chats?accountId=\(encodedAccountId)"
        print("[WhatsAppService] fetchChats: \(endpoint)")
        
        let response: [WhatsAppChatResponse] = try await hubClient.localGet(endpoint: endpoint)
        print("[WhatsAppService] fetchChats: ricevute \(response.count) chat")
        
        return response.map { WhatsAppChat(from: $0) }
    }
    
    func fetchMessages(chatId: String, limit: Int = 100) async throws -> [WhatsAppMessage] {
        syncSelectedAccountWithCurrentUser()
        guard !selectedAccountId.isEmpty else { return [] }
        
        let encodedChatId = chatId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? chatId
        let encodedAccountId = selectedAccountId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? selectedAccountId
        let response: [WhatsAppMessageResponse] = try await hubClient.localGet(
            endpoint: "whatsapp/messages?accountId=\(encodedAccountId)&chatId=\(encodedChatId)&limit=\(limit)"
        )
        
        return response.map { WhatsAppMessage(from: $0) }
    }
    
    func fetchMessagesForSinistro(sinistroRef: String) async throws -> [WhatsAppMessage] {
        syncSelectedAccountWithCurrentUser()
        guard !selectedAccountId.isEmpty else { return [] }
        
        let encodedAccountId = selectedAccountId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? selectedAccountId
        let encodedSinistroRef = sinistroRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sinistroRef
        let response: [WhatsAppMessageResponse] = try await hubClient.localGet(
            endpoint: "whatsapp/messages?accountId=\(encodedAccountId)&sinistroRef=\(encodedSinistroRef)"
        )
        
        return response.map { WhatsAppMessage(from: $0) }
    }
    
    // MARK: - Check Number Registration
    
    /// Verifica se un numero è registrato su WhatsApp
    /// - Returns: true se il numero è su WhatsApp, false altrimenti
    func checkNumberRegistered(phoneNumber: String) async throws -> Bool {
        guard !selectedAccountId.isEmpty else { throw WhatsAppError.notConnected }
        guard isConnected else { throw WhatsAppError.notConnected }
        
        struct CheckRequest: Codable {
            let phoneNumber: String
        }
        
        struct CheckResponse: Codable {
            let isRegistered: Bool
            let numberId: String?
        }
        
        let response: CheckResponse = try await hubClient.localPost(
            endpoint: "whatsapp/clients/\(selectedAccountId)/check-number",
            body: CheckRequest(phoneNumber: normalizePhoneNumber(phoneNumber))
        )
        
        return response.isRegistered
    }
    
    /// Ottiene l'URL della foto profilo di un contatto
    /// - Returns: URL della foto profilo o nil se non disponibile
    func getProfilePicUrl(contactId: String) async throws -> String? {
        guard !selectedAccountId.isEmpty else { throw WhatsAppError.notConnected }
        guard isConnected else { throw WhatsAppError.notConnected }
        
        struct ProfilePicResponse: Codable {
            let contactId: String
            let profilePicUrl: String?
            let error: String?
        }
        
        // Encode contactId per URL (potrebbe contenere @)
        let encodedContactId = contactId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? contactId
        
        let response: ProfilePicResponse = try await hubClient.localGet(
            endpoint: "whatsapp/clients/\(selectedAccountId)/profile-pic/\(encodedContactId)"
        )
        
        return response.profilePicUrl
    }
    
    // MARK: - Send Messages (via Hub)
    
    func sendMessage(to: String, body: String, mediaUrl: String? = nil) async throws -> String {
        guard !selectedAccountId.isEmpty else { throw WhatsAppError.notConnected }
        guard isConnected else { throw WhatsAppError.notConnected }
        
        var mediaPayload: SendMessagePayload.MediaPayload? = nil
        
        // Se c'è un media, caricalo
        if let mediaUrl = mediaUrl, FileManager.default.fileExists(atPath: mediaUrl) {
            let result = try WhatsAppMediaService.shared.prepareMediaForSending(filePath: mediaUrl)
            mediaPayload = SendMessagePayload.MediaPayload(
                mimetype: result.mimeType,
                data: result.base64,
                filename: URL(fileURLWithPath: mediaUrl).lastPathComponent
            )
        }
        
        let payload = SendMessagePayload(
            to: normalizePhoneNumber(to),
            body: body,
            media: mediaPayload
        )
        
        let response: SendMessageResponse = try await hubClient.localPost(
            endpoint: "whatsapp/clients/\(selectedAccountId)/send",
            body: payload
        )
        
        return response.messageId
    }
    
    func sendMessageToChat(chatId: String, message: String, mediaUrl: String? = nil) async throws -> String {
        // Per chat esistenti, usa il chatId direttamente come destinatario
        return try await sendMessage(to: chatId, body: message, mediaUrl: mediaUrl)
    }
    
    // MARK: - Scheduled Messages (via Hub)
    
    func scheduleMessage(phoneNumber: String, message: String, scheduledAt: Date, sinistroRef: String? = nil, mediaPath: String? = nil) async throws -> String {
        guard !selectedAccountId.isEmpty else { throw WhatsAppError.notConnected }
        
        var payload = ScheduleMessagePayload(
            accountId: selectedAccountId,
            phoneNumber: normalizePhoneNumber(phoneNumber).replacingOccurrences(of: "@c.us", with: ""),
            body: message,
            scheduledFor: ISO8601DateFormatter().string(from: scheduledAt),
            sinistroRef: sinistroRef
        )
        
        if let mediaPath = mediaPath, FileManager.default.fileExists(atPath: mediaPath) {
            let result = try WhatsAppMediaService.shared.prepareMediaForSending(filePath: mediaPath)
            payload.mediaData = result.base64
            payload.mediaType = result.mimeType
            payload.mediaFilename = URL(fileURLWithPath: mediaPath).lastPathComponent
        }
        
        let response: ScheduleResponse = try await hubClient.localPost(
            endpoint: "whatsapp/schedule",
            body: payload
        )
        
        return response.id
    }
    
    func fetchScheduledMessages() async throws -> [ScheduledWhatsAppMessage] {
        syncSelectedAccountWithCurrentUser()
        guard !selectedAccountId.isEmpty else { return [] }
        
        let encodedAccountId = selectedAccountId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? selectedAccountId
        let response: [ScheduledWhatsAppMessageResponse] = try await hubClient.localGet(
            endpoint: "whatsapp/scheduled?accountId=\(encodedAccountId)"
        )
        
        return response.map { ScheduledWhatsAppMessage(from: $0) }
    }
    
    func cancelScheduledMessage(id: String) async throws {
        try await hubClient.localDelete(endpoint: "whatsapp/scheduled/\(id)")
    }
    
    // MARK: - Chat Management (via Hub)
    
    func markAsRead(chatId: String) async throws {
        let encodedChatId = chatId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? chatId
        try await hubClient.localPost(
            endpoint: "whatsapp/chats/\(encodedChatId)/read",
            body: EmptyBody()
        )
    }
    
    func associateChatToSinistro(chatId: String, sinistroRef: String) async throws {
        let encodedChatId = chatId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? chatId
        try await hubClient.localPost(
            endpoint: "whatsapp/chats/\(encodedChatId)/associate",
            body: ["sinistroRef": sinistroRef]
        )
    }
    
    // MARK: - Helpers

    private var selectedAccountKey: String {
        "whatsapp_selected_account.\(currentUserScope)"
    }

    private var currentUserScope: String {
        if let username = CurrentUserService.shared.currentUsername, !username.isEmpty {
            return normalizedAccountId(username)
        }
        if let email = CurrentUserService.shared.currentEmail, !email.isEmpty {
            return normalizedAccountId(UserProfile.generateUsername(from: email))
        }
        return "anonymous"
    }

    private func handleCurrentUserChanged() {
        stopPolling()
        qrCode = nil
        isConnected = false
        connectionStatus = "disconnected"
        syncSelectedAccountWithCurrentUser(forceCurrentUser: true)
    }

    private func syncSelectedAccountWithCurrentUser(forceCurrentUser: Bool = false) {
        guard let currentUsername = CurrentUserService.shared.currentUsername, !currentUsername.isEmpty else {
            if !selectedAccountId.isEmpty {
                selectedAccountId = ""
            }
            return
        }

        let currentAccount = normalizedAccountId(currentUsername)
        let saved = UserDefaults.standard.string(forKey: selectedAccountKey).map(normalizedAccountId)

        if !forceCurrentUser,
           let saved,
           !saved.isEmpty,
           isAccountAllowedForCurrentUser(saved) {
            selectedAccountId = saved
            return
        }

        if selectedAccountId.isEmpty || !isAccountAllowedForCurrentUser(selectedAccountId) || forceCurrentUser {
            selectedAccountId = currentAccount
            UserDefaults.standard.set(currentAccount, forKey: selectedAccountKey)
        }

        if let legacy = UserDefaults.standard.string(forKey: legacySelectedAccountKey),
           normalizedAccountId(legacy) != currentAccount {
            UserDefaults.standard.removeObject(forKey: legacySelectedAccountKey)
        }
    }

    private func isAccountAllowedForCurrentUser(_ accountId: String) -> Bool {
        guard let username = CurrentUserService.shared.currentUsername else { return false }
        return normalizedAccountId(accountId) == normalizedAccountId(username)
    }

    private func normalizedAccountId(_ accountId: String) -> String {
        accountId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    private func normalizePhoneNumber(_ number: String) -> String {
        var cleaned = number
        // Rimuovi @c.us se presente
        cleaned = cleaned.replacingOccurrences(of: "@c.us", with: "")
        cleaned = cleaned.replacingOccurrences(of: "@g.us", with: "")
        // Rimuovi caratteri non numerici
        cleaned = cleaned.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return "\(cleaned)@c.us"
    }
}

// MARK: - Response Types

private struct QRStatusResponse: Codable {
    let qr: String?
    let status: String
}

// SendMessageResponse definito in WhatsAppModels.swift

private struct ScheduleResponse: Codable {
    let id: String
}

private struct EmptyBody: Codable {}

// Request payload types
private struct SendMessagePayload: Codable {
    let to: String
    let body: String
    var media: MediaPayload?
    
    struct MediaPayload: Codable {
        let mimetype: String
        let data: String
        let filename: String
    }
}

private struct ScheduleMessagePayload: Codable {
    let accountId: String
    let phoneNumber: String
    let body: String
    let scheduledFor: String
    var sinistroRef: String?
    var mediaData: String?
    var mediaType: String?
    var mediaFilename: String?
}

// Hub response types
struct WhatsAppChatResponse: Codable {
    let id: String
    let accountId: String
    let chatId: String
    let name: String?
    let phoneNumber: String?
    let isGroup: Bool
    let lastMessageBody: String?
    let lastMessageAt: Date?
    let unreadCount: Int
    let sinistroRef: String?
}

struct WhatsAppMessageResponse: Codable {
    let id: String
    let accountId: String
    let chatId: String
    let waMessageId: String
    let fromNumber: String
    let toNumber: String?
    let body: String?
    let timestamp: Date
    let direction: String
    let type: String
    let mediaType: String?
    let mediaFilename: String?
    let hasMedia: Bool
    let isRead: Bool
    let sinistroRef: String?
    // ACK status: -1=error, 0=pending, 1=sent, 2=delivered, 3=read, 4=played
    let ackStatus: Int?
    let ackTimestamp: Date?
}

struct ScheduledWhatsAppMessageResponse: Codable {
    let id: String
    let accountId: String
    let phoneNumber: String
    let body: String
    let mediaData: String?
    let mediaType: String?
    let mediaFilename: String?
    let scheduledAt: Date
    let status: String
    let sinistroRef: String?
}

// MARK: - Model Extensions

extension WhatsAppChat {
    init(from response: WhatsAppChatResponse) {
        self.id = response.chatId
        self.name = response.name ?? response.phoneNumber ?? response.chatId
        self.phoneNumber = response.phoneNumber
        self.profilePicture = nil
        self.isGroup = response.isGroup
        self.lastMessage = response.lastMessageBody
        self.lastMessageDate = response.lastMessageAt
        self.unreadCount = response.unreadCount
        self.isPinned = false
        self.isMuted = false
        self.sinistroRiferimento = response.sinistroRef
    }
}

extension WhatsAppMessage {
    init(from response: WhatsAppMessageResponse) {
        self.id = response.waMessageId
        self.chatId = response.chatId
        self.from = response.fromNumber
        self.to = response.toNumber
        self.body = response.body ?? ""
        self.timestamp = response.timestamp
        self.isFromMe = response.direction == "out"
        self.type = MessageType(rawValue: response.type) ?? .text
        self.mediaType = response.mediaType
        self.mediaFilename = response.mediaFilename
        self.mediaId = response.hasMedia ? response.waMessageId : nil
        self.isRead = response.isRead
        self.sinistroRiferimento = response.sinistroRef
        self.ackStatus = response.ackStatus
        self.ackTimestamp = response.ackTimestamp
    }
}

extension ScheduledWhatsAppMessage {
    init(from response: ScheduledWhatsAppMessageResponse) {
        self.id = response.id
        self.phoneNumber = response.phoneNumber
        self.body = response.body
        self.scheduledAt = response.scheduledAt
        self.status = ScheduledStatus(rawValue: response.status) ?? .pending
        self.sinistroRef = response.sinistroRef
    }
}

// MARK: - Errors

enum WhatsAppError: Error, LocalizedError {
    case notConnected
    case sendFailed(String)
    case hubNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "WhatsApp non connesso"
        case .sendFailed(let reason):
            return "Invio fallito: \(reason)"
        case .hubNotAvailable:
            return "Hub non raggiungibile"
        }
    }
}
