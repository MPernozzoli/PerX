//
//  ChatListView.swift
//  PerX per iPad
//
//  Lista chat con dettaglio messaggi.
//

import SwiftUI

struct ChatListView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var selectedRoom: ChatRoomDTO?
    @State private var showingNewChat = false
    
    private var chatService: iPadChatService? {
        session.chatService
    }
    
    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            if let room = selectedRoom {
                ChatDetailView(room: room)
            } else {
                ContentUnavailableView(
                    "Seleziona una chat",
                    systemImage: "message",
                    description: Text("Scegli una conversazione dalla lista")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingNewChat) {
            NewChatView { room in
                selectedRoom = room
                showingNewChat = false
            }
        }
    }
    
    @ViewBuilder
    private var sidebarContent: some View {
        List {
            ForEach(chatService?.rooms ?? [], id: \.id) { room in
                Button {
                    selectedRoom = room
                } label: {
                    ChatRoomRow(room: room)
                }
                .buttonStyle(.plain)
                .listRowBackground(selectedRoom?.id == room.id ? Color.accentColor.opacity(0.2) : Color.clear)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Chat")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewChat = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await chatService?.fetchRooms()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .refreshable {
            await chatService?.fetchRooms()
        }
    }
}

// MARK: - Chat Room Row

struct ChatRoomRow: View {
    let room: ChatRoomDTO
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "person.fill")
                    .foregroundColor(.accentColor)

                Text(room.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Text(room.lastMessageAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if let preview = room.lastMessagePreview {
                HStack {
                    if let sender = room.lastMessageSender {
                        Text("\(sender.components(separatedBy: "@").first ?? sender):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(preview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Chat Detail View

struct ChatDetailView: View {
    let room: ChatRoomDTO
    
    @EnvironmentObject var session: SessionCoordinator
    @State private var messages: [ChatMessageDTO] = []
    @State private var newMessage = ""
    @State private var isLoading = false
    @State private var isSending = false
    
    private var chatService: iPadChatService? {
        session.chatService
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in
                            ChatMessageBubble(message: message)
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
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                
                Button {
                    Task { await sendMessage() }
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .disabled(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMessages()
        }
        .refreshable {
            await loadMessages()
        }
    }
    
    private func loadMessages() async {
        isLoading = true
        defer { isLoading = false }
        
        messages = await chatService?.fetchMessages(for: room.id) ?? []
    }
    
    private func sendMessage() async {
        let content = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        isSending = true
        newMessage = ""
        
        do {
            let sent = try await chatService?.sendMessage(to: room.id, content: content)
            if let sent = sent {
                messages.append(sent)
            }
        } catch {
            // Restore message on error
            newMessage = content
            print("Errore invio: \(error)")
        }
        
        isSending = false
    }
}

// MARK: - Chat Message Bubble

struct ChatMessageBubble: View {
    let message: ChatMessageDTO
    @EnvironmentObject var session: SessionCoordinator

    private var isFromCurrentUser: Bool {
        guard let email = session.currentUserEmail else { return false }
        return message.senderName.lowercased() == email.lowercased()
    }

    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer()
            }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isFromCurrentUser {
                    Text(message.senderName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isFromCurrentUser ? Color.accentColor : Color(.systemGray5))
                    .foregroundColor(isFromCurrentUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !isFromCurrentUser {
                Spacer()
            }
        }
    }
}

// MARK: - New Chat View

struct NewChatView: View {
    let onCreated: (ChatRoomDTO) -> Void
    
    @EnvironmentObject var session: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Nuova conversazione") {
                    TextField("Email utente", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Nuova Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea") {
                        Task { await createChat() }
                    }
                    .disabled(email.isEmpty || isCreating)
                }
            }
        }
    }
    
    private func createChat() async {
        isCreating = true
        errorMessage = nil
        
        do {
            let room = try await session.chatService?.createDirectChat(with: email)
            if let room = room {
                onCreated(room)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isCreating = false
    }
}
