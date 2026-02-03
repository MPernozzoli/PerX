import Foundation
import Combine
import CoreData

/// ViewModel per WhatsApp - usa esclusivamente WhatsAppService (che comunica con Hub)
@MainActor
class WhatsAppViewModel: ObservableObject {
    static let shared = WhatsAppViewModel()
    
    // MARK: - Published Properties
    
    @Published var chats: [WhatsAppChat] = []
    @Published var messagesByChat: [String: [WhatsAppMessage]] = [:]
    @Published var selectedChatId: String?
    
    @Published var isLoading = false
    @Published var isLoadingMessages = false
    @Published var errorMessage: String?
    
    // Associazioni chat -> sinistri
    @Published var associatedSinistriByChat: [String: [Sinistro]] = [:]
    
    // MARK: - Private
    
    private let service = WhatsAppService.shared
    private let associationService = WhatsAppAssociationService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var isConnected: Bool { service.isConnected }
    var qrCode: String? { service.qrCode }
    var connectionStatus: String { service.connectionStatus }
    var selectedAccountId: String { service.selectedAccountId }
    var isServiceLoading: Bool { service.isLoading }
    
    // MARK: - Init
    
    private init() {
        // Osserva cambiamenti nel service
        service.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                if connected {
                    Task { await self?.fetchChats() }
                }
            }
            .store(in: &cancellables)
        
        service.$errorMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$errorMessage)
    }
    
    // MARK: - Connection
    
    func connect() async {
        errorMessage = nil
        await service.connect()
    }
    
    func disconnect() async {
        await service.disconnect()
        chats = []
        messagesByChat = [:]
        selectedChatId = nil
    }
    
    func restartConnection() async {
        await disconnect()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await connect()
    }
    
    func checkConnectionStatus() async {
        await service.checkStatus()
    }
    
    // MARK: - Data Fetching
    
    func fetchChats() async {
        guard isConnected else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            chats = try await service.fetchChats()
            errorMessage = nil
            print("[WhatsAppVM] Caricati \(chats.count) chat")
        } catch {
            errorMessage = "Errore caricamento chat: \(error.localizedDescription)"
            print("[WhatsAppVM] ❌ \(errorMessage ?? "")")
        }
    }
    
    /// Aggiorna la lista chat (chiamato dal notification service per aggiornare la UI)
    func updateChats(_ newChats: [WhatsAppChat]) {
        // Merge intelligente per non perdere lo stato locale
        for newChat in newChats {
            if let index = chats.firstIndex(where: { $0.id == newChat.id }) {
                // Aggiorna solo se ci sono cambiamenti rilevanti
                if chats[index].unreadCount != newChat.unreadCount ||
                   chats[index].lastMessage != newChat.lastMessage ||
                   chats[index].lastMessageDate != newChat.lastMessageDate {
                    chats[index] = newChat
                }
            } else {
                // Nuova chat
                chats.append(newChat)
            }
        }
        // Riordina per data ultimo messaggio
        chats.sort { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
    }
    
    func fetchMessages(for chatId: String) async {
        guard isConnected else { return }
        
        isLoadingMessages = true
        defer { isLoadingMessages = false }
        
        do {
            let messages = try await service.fetchMessages(chatId: chatId)
            messagesByChat[chatId] = messages
            errorMessage = nil
            print("[WhatsAppVM] Caricati \(messages.count) messaggi per chat \(chatId)")
        } catch {
            errorMessage = "Errore caricamento messaggi: \(error.localizedDescription)"
            print("[WhatsAppVM] ❌ \(errorMessage ?? "")")
        }
    }
    
    func refreshCurrentChat() async {
        guard let chatId = selectedChatId else { return }
        await fetchMessages(for: chatId)
    }
    
    // MARK: - Actions
    
    func sendMessage(to phoneNumber: String, message: String, mediaUrl: String? = nil) async throws {
        guard isConnected else {
            throw WhatsAppError.notConnected
        }
        
        let messageId = try await service.sendMessage(to: phoneNumber, body: message, mediaUrl: mediaUrl)
        print("[WhatsAppVM] ✅ Messaggio inviato: \(messageId)")
        
        // Ricarica messaggi della chat
        if let chatId = selectedChatId {
            await fetchMessages(for: chatId)
        }
    }
    
    func sendMessageToCurrentChat(message: String, mediaUrl: String? = nil) async throws {
        guard let chatId = selectedChatId else {
            throw WhatsAppError.notConnected
        }
        
        let messageId = try await service.sendMessageToChat(chatId: chatId, message: message, mediaUrl: mediaUrl)
        print("[WhatsAppVM] ✅ Messaggio inviato a chat \(chatId): \(messageId)")
        
        // Ricarica messaggi
        await fetchMessages(for: chatId)
    }
    
    func scheduleMessage(to phoneNumber: String, message: String, scheduledFor: Date, sinistroRef: String?) async throws {
        let id = try await service.scheduleMessage(
            phoneNumber: phoneNumber,
            message: message,
            scheduledAt: scheduledFor,
            sinistroRef: sinistroRef
        )
        
        print("[WhatsAppVM] ✅ Messaggio programmato: \(id) per \(scheduledFor)")
    }
    
    // MARK: - Chat Selection
    
    func selectChat(_ chatId: String) {
        selectedChatId = chatId
        Task {
            await fetchMessages(for: chatId)
            try? await service.markAsRead(chatId: chatId)
        }
    }
    
    func deselectChat() {
        selectedChatId = nil
    }
    
    // MARK: - Association
    
    func loadAssociatedSinistri(for chatId: String, context: NSManagedObjectContext) {
        let request = NSFetchRequest<SinistroWhatsAppThread>(entityName: "SinistroWhatsAppThread")
        request.predicate = NSPredicate(format: "chatIds CONTAINS %@", chatId)
        
        if let threads = try? context.fetch(request) {
            let sinistri = threads.compactMap { $0.sinistro }.filter { $0 != nil }
            if !sinistri.isEmpty {
                associatedSinistriByChat[chatId] = sinistri
            }
        }
    }
    
    func associateChatManually(chatId: String, sinistri: [Sinistro], context: NSManagedObjectContext) {
        associatedSinistriByChat[chatId] = sinistri
        associationService.associateChatToSinistri(chatId, sinistri: sinistri, context: context)
        
        // Associa anche su Hub
        if let firstSinistro = sinistri.first, let riferimento = firstSinistro.riferimento {
            Task {
                try? await service.associateChatToSinistro(chatId: chatId, sinistroRef: riferimento)
            }
        }
    }
    
    func associateChatToSinistro(chatId: String, sinistroRef: String) async {
        do {
            try await service.associateChatToSinistro(chatId: chatId, sinistroRef: sinistroRef)
            
            // Aggiorna anche la chat locale
            if let index = chats.firstIndex(where: { $0.id == chatId }) {
                chats[index].sinistroRiferimento = sinistroRef
            }
            
            print("[WhatsAppVM] ✅ Chat \(chatId) associata a sinistro \(sinistroRef)")
        } catch {
            errorMessage = "Errore associazione: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Computed Properties
    
    var selectedChat: WhatsAppChat? {
        guard let chatId = selectedChatId else { return nil }
        return chats.first { $0.id == chatId }
    }
    
    var selectedChatMessages: [WhatsAppMessage] {
        guard let chatId = selectedChatId else { return [] }
        return messagesByChat[chatId] ?? []
    }
    
    var selectedChatAssociatedSinistri: [Sinistro] {
        guard let chatId = selectedChatId else { return [] }
        return associatedSinistriByChat[chatId] ?? []
    }
    
    var unreadChatsCount: Int {
        chats.filter { $0.unreadCount > 0 }.count
    }
    
    var totalUnreadCount: Int {
        chats.reduce(0) { $0 + $1.unreadCount }
    }
}
