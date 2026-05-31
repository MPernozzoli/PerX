//
//  iPadWhatsAppListView.swift
//  PerX per iPad
//
//  Vista WhatsApp con lista chat e messaggi.
//

import SwiftUI

struct iPadWhatsAppListView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var chats: [WhatsAppChatDTO] = []
    @State private var selectedChat: WhatsAppChatDTO?
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var showingNewMessage = false
    
    private var filteredChats: [WhatsAppChatDTO] {
        if searchText.isEmpty {
            return chats
        }
        let query = searchText.lowercased()
        return chats.filter {
            $0.name.lowercased().contains(query) ||
            $0.phoneNumber.contains(query)
        }
    }
    
    var body: some View {
        NavigationSplitView {
            chatListSidebar
        } detail: {
            if let chat = selectedChat {
                WhatsAppChatDetailView(chat: chat)
            } else {
                ContentUnavailableView(
                    "Seleziona una chat",
                    systemImage: "message",
                    description: Text("Scegli una conversazione dalla lista")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingNewMessage) {
            ComposeWhatsAppView()
        }
        .task {
            await loadChats()
        }
    }
    
    @ViewBuilder
    private var chatListSidebar: some View {
        List {
            ForEach(filteredChats, id: \.id) { chat in
                Button {
                    selectedChat = chat
                } label: {
                    WhatsAppChatRow(chat: chat)
                }
                .buttonStyle(.plain)
                .listRowBackground(selectedChat?.id == chat.id ? Color.accentColor.opacity(0.2) : Color.clear)
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Cerca chat...")
        .navigationTitle("WhatsApp")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewMessage = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadChats() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .refreshable {
            await loadChats()
        }
        .overlay {
            if isLoading && chats.isEmpty {
                ProgressView()
            } else if chats.isEmpty {
                ContentUnavailableView(
                    "Nessuna chat",
                    systemImage: "message",
                    description: Text("Le chat WhatsApp appariranno qui")
                )
            }
        }
    }
    
    private func loadChats() async {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Implementare caricamento chat da CloudKit
        // Per ora usa dati di esempio
    }
}

// MARK: - WhatsApp Chat DTO

struct WhatsAppChatDTO: Identifiable, Hashable {
    let id: String
    let name: String
    let phoneNumber: String
    let lastMessage: String?
    let lastMessageDate: Date?
    let unreadCount: Int
    let sinistroRiferimento: String?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: WhatsAppChatDTO, rhs: WhatsAppChatDTO) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - WhatsApp Chat Row

struct WhatsAppChatRow: View {
    let chat: WhatsAppChatDTO
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay {
                    Text(String(chat.name.prefix(2)).uppercased())
                        .font(.headline)
                        .foregroundColor(.green)
                }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let date = chat.lastMessageDate {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    if let lastMessage = chat.lastMessage {
                        Text(lastMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }
                }
                
                if let rif = chat.sinistroRiferimento {
                    Label(rif, systemImage: "folder")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - WhatsApp Chat Detail View

struct WhatsAppChatDetailView: View {
    let chat: WhatsAppChatDTO
    
    @EnvironmentObject var session: SessionCoordinator
    @State private var messages: [WhatsAppMessageDTO] = []
    @State private var newMessage = ""
    @State private var isLoading = false
    @State private var isSending = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in
                            WhatsAppMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let lastId = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input
            HStack(spacing: 12) {
                TextField("Scrivi un messaggio...", text: $newMessage, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .lineLimit(1...5)
                
                Button {
                    Task { await sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(canSend ? .green : .gray)
                }
                .disabled(!canSend || isSending)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
        }
        .navigationTitle(chat.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let phone = chat.phoneNumber.nilIfEmpty {
                        Button {
                            callPhone(phone)
                        } label: {
                            Label("Chiama", systemImage: "phone")
                        }
                    }
                    
                    if let rif = chat.sinistroRiferimento {
                        Button {
                            // Navigate to sinistro
                        } label: {
                            Label("Vai al sinistro", systemImage: "folder")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await loadMessages()
        }
    }
    
    private var canSend: Bool {
        !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func loadMessages() async {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Implementare caricamento messaggi da CloudKit
    }
    
    private func sendMessage() async {
        let text = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        isSending = true
        newMessage = ""
        
        do {
            _ = try await HubOutboxService.shared.sendWhatsApp(
                phoneNumber: chat.phoneNumber,
                chatId: chat.id,
                message: text,
                sinistroRiferimento: chat.sinistroRiferimento
            )
            
            // Aggiungi messaggio locale per feedback immediato
            let localMessage = WhatsAppMessageDTO(
                id: UUID().uuidString,
                chatId: chat.id,
                from: session.currentUserEmail ?? "",
                body: text,
                timestamp: Date(),
                direction: "outbound",
                mediaType: nil
            )
            messages.append(localMessage)
        } catch {
            print("Errore invio: \(error)")
        }
        
        isSending = false
    }
    
    private func callPhone(_ number: String) {
        guard let url = URL(string: "tel://\(number.replacingOccurrences(of: " ", with: ""))") else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - WhatsApp Message Bubble

struct WhatsAppMessageBubble: View {
    let message: WhatsAppMessageDTO
    
    private var isOutbound: Bool {
        message.direction == "outbound"
    }
    
    var body: some View {
        HStack {
            if isOutbound { Spacer(minLength: 60) }
            
            VStack(alignment: isOutbound ? .trailing : .leading, spacing: 4) {
                Text(message.body)
                    .font(.subheadline)
                
                if let mediaType = message.mediaType {
                    Label(mediaType, systemImage: "paperclip")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(isOutbound ? .white.opacity(0.7) : .secondary)
            }
            .padding(12)
            .background(isOutbound ? Color.green : Color(.systemGray5))
            .foregroundColor(isOutbound ? .white : .primary)
            .cornerRadius(16)
            
            if !isOutbound { Spacer(minLength: 60) }
        }
    }
}

// MARK: - String Extension

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
