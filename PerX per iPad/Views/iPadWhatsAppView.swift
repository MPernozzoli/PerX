//
//  iPadWhatsAppView.swift
//  PerX per iPad
//
//  Vista WhatsApp principale raggruppata per sinistro.
//

import SwiftUI

// MARK: - WhatsApp View Mode

enum WhatsAppViewMode: String, CaseIterable {
    case sinistro = "Per Sinistro"
    case tutti = "Tutte le Chat"
}

// MARK: - WhatsApp Thread DTO

struct WhatsAppThreadDTO: Identifiable, Hashable {
    let id: String
    let sinistroRiferimento: String?
    let sinistroAssicurato: String?
    let chats: [WhatsAppChatDTO]
    let totalUnread: Int
    let latestDate: Date?
    
    var displayTitle: String {
        if let rif = sinistroRiferimento {
            return rif
        }
        return "Chat non associate"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: WhatsAppThreadDTO, rhs: WhatsAppThreadDTO) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - iPad WhatsApp View

struct iPadWhatsAppView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var viewMode: WhatsAppViewMode = .sinistro
    @State private var selectedThread: WhatsAppThreadDTO?
    @State private var selectedChat: WhatsAppChatDTO?
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var showingNewMessage = false
    
    // Data
    @State private var allChats: [WhatsAppChatDTO] = []
    @State private var sinistroThreads: [WhatsAppThreadDTO] = []
    
    var body: some View {
        NavigationSplitView {
            threadListSidebar
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingNewMessage) {
            ComposeWhatsAppView()
        }
        .task {
            await loadChats()
        }
        .onChange(of: viewMode) { _ in
            selectedThread = nil
            selectedChat = nil
        }
    }
    
    // MARK: - Thread List Sidebar
    
    @ViewBuilder
    private var threadListSidebar: some View {
        VStack(spacing: 0) {
            // View mode picker
            Picker("Modalità", selection: $viewMode) {
                ForEach(WhatsAppViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // List
            if viewMode == .sinistro {
                sinistroThreadList
            } else {
                allChatsList
            }
        }
        .navigationTitle("WhatsApp")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Cerca...")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showingNewMessage = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    
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
        }
        .refreshable {
            await loadChats()
        }
    }
    
    // MARK: - Sinistro Thread List
    
    @ViewBuilder
    private var sinistroThreadList: some View {
        let filtered = filteredSinistroThreads
        
        if isLoading && sinistroThreads.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            ContentUnavailableView {
                Label("Nessuna chat", systemImage: "message")
            } description: {
                Text("Le chat raggruppate per sinistro appariranno qui")
            }
        } else {
            List(selection: $selectedThread) {
                ForEach(filtered) { thread in
                    WhatsAppThreadRowView(thread: thread, isSelected: selectedThread?.id == thread.id)
                        .tag(thread)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
            }
            .listStyle(.plain)
        }
    }
    
    private var filteredSinistroThreads: [WhatsAppThreadDTO] {
        guard !searchText.isEmpty else { return sinistroThreads }
        let query = searchText.lowercased()
        return sinistroThreads.filter { thread in
            thread.displayTitle.lowercased().contains(query) ||
            thread.chats.contains { $0.name.lowercased().contains(query) || $0.phoneNumber.contains(query) }
        }
    }
    
    // MARK: - All Chats List
    
    @ViewBuilder
    private var allChatsList: some View {
        let filtered = filteredChats
        
        if isLoading && allChats.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            ContentUnavailableView {
                Label("Nessuna chat", systemImage: "message")
            } description: {
                Text("Le chat WhatsApp appariranno qui")
            }
        } else {
            List(selection: $selectedChat) {
                ForEach(filtered) { chat in
                    WhatsAppChatRow(chat: chat)
                        .tag(chat)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
            }
            .listStyle(.plain)
        }
    }
    
    private var filteredChats: [WhatsAppChatDTO] {
        guard !searchText.isEmpty else { return allChats }
        let query = searchText.lowercased()
        return allChats.filter { chat in
            chat.name.lowercased().contains(query) || chat.phoneNumber.contains(query)
        }
    }
    
    // MARK: - Detail Content
    
    @ViewBuilder
    private var detailContent: some View {
        if viewMode == .sinistro {
            if let thread = selectedThread {
                WhatsAppThreadDetailView(
                    thread: thread,
                    selectedChat: $selectedChat,
                    onOpenSinistro: { riferimento in
                        print("Open sinistro: \(riferimento)")
                    }
                )
            } else {
                ContentUnavailableView(
                    "Seleziona un sinistro",
                    systemImage: "message",
                    description: Text("Scegli un sinistro per visualizzare le chat associate")
                )
            }
        } else {
            if let chat = selectedChat {
                WhatsAppChatDetailView(chat: chat)
            } else {
                ContentUnavailableView(
                    "Seleziona una chat",
                    systemImage: "message",
                    description: Text("Scegli una chat dalla lista")
                )
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadChats() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let syncService = session.cloudKitSyncService else { return }
        
        // Load all chats
        allChats = await syncService.fetchAllWhatsAppChats()
        
        // Group by sinistro
        buildSinistroThreads()
    }
    
    private func buildSinistroThreads() {
        var threadMap: [String: [WhatsAppChatDTO]] = [:]
        var unassociatedChats: [WhatsAppChatDTO] = []
        
        for chat in allChats {
            if let riferimento = chat.sinistroRiferimento, !riferimento.isEmpty {
                threadMap[riferimento, default: []].append(chat)
            } else {
                unassociatedChats.append(chat)
            }
        }
        
        var threads: [WhatsAppThreadDTO] = []
        
        for (riferimento, chats) in threadMap {
            let sortedChats = chats.sorted { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
            let totalUnread = sortedChats.reduce(0) { $0 + $1.unreadCount }
            let latest = sortedChats.first?.lastMessageDate
            
            threads.append(WhatsAppThreadDTO(
                id: riferimento,
                sinistroRiferimento: riferimento,
                sinistroAssicurato: nil,
                chats: sortedChats,
                totalUnread: totalUnread,
                latestDate: latest
            ))
        }
        
        if !unassociatedChats.isEmpty {
            let sorted = unassociatedChats.sorted { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
            threads.append(WhatsAppThreadDTO(
                id: "_unassociated_",
                sinistroRiferimento: nil,
                sinistroAssicurato: nil,
                chats: sorted,
                totalUnread: sorted.reduce(0) { $0 + $1.unreadCount },
                latestDate: sorted.first?.lastMessageDate
            ))
        }
        
        sinistroThreads = threads.sorted { ($0.latestDate ?? .distantPast) > ($1.latestDate ?? .distantPast) }
    }
}

// MARK: - WhatsApp Thread Row View

struct WhatsAppThreadRowView: View {
    let thread: WhatsAppThreadDTO
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: thread.sinistroRiferimento != nil ? "folder" : "bubble.left.and.bubble.right")
                        .foregroundColor(.green)
                }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let date = thread.latestDate {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text("\(thread.chats.count) chat")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if thread.totalUnread > 0 {
                        Text("\(thread.totalUnread)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green))
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
    }
}

// MARK: - WhatsApp Thread Detail View

struct WhatsAppThreadDetailView: View {
    let thread: WhatsAppThreadDTO
    @Binding var selectedChat: WhatsAppChatDTO?
    var onOpenSinistro: ((String) -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if let riferimento = thread.sinistroRiferimento {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(riferimento)
                            .font(.headline)
                        Text("\(thread.chats.count) chat associate")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        onOpenSinistro?(riferimento)
                    } label: {
                        Label("Apri Sinistro", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Text("Chat non associate")
                        .font(.headline)
                    Spacer()
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            
            Divider()
            
            // Split: chat list and detail
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Chat list
                    List(selection: $selectedChat) {
                        ForEach(thread.chats) { chat in
                            WhatsAppChatRow(chat: chat)
                                .tag(chat)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .frame(width: geometry.size.width * 0.35)
                    
                    Divider()
                    
                    // Chat detail
                    if let chat = selectedChat {
                        WhatsAppChatDetailView(chat: chat)
                            .frame(width: geometry.size.width * 0.65)
                    } else {
                        ContentUnavailableView(
                            "Seleziona una chat",
                            systemImage: "message",
                            description: Text("Scegli una chat dalla lista")
                        )
                        .frame(width: geometry.size.width * 0.65)
                    }
                }
            }
        }
    }
}

// MARK: - Compose WhatsApp View

struct ComposeWhatsAppView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: SessionCoordinator
    
    @State private var phoneNumber = ""
    @State private var message = ""
    @State private var isSending = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Destinatario") {
                    TextField("Numero di telefono", text: $phoneNumber)
                        .keyboardType(.phonePad)
                }
                
                Section("Messaggio") {
                    TextEditor(text: $message)
                        .frame(minHeight: 150)
                }
            }
            .navigationTitle("Nuovo Messaggio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invia") {
                        Task { await sendMessage() }
                    }
                    .disabled(!canSend || isSending)
                }
            }
        }
    }
    
    private var canSend: Bool {
        !phoneNumber.isEmpty && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func sendMessage() async {
        isSending = true
        defer { isSending = false }
        
        do {
            _ = try await HubOutboxService.shared.sendWhatsApp(
                phoneNumber: phoneNumber,
                chatId: nil,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                sinistroRiferimento: nil
            )
            dismiss()
        } catch {
            print("Errore invio: \(error)")
        }
    }
}

// MARK: - iPadCloudKitSyncService Extension

extension iPadCloudKitSyncService {
    func fetchAllWhatsAppChats() async -> [WhatsAppChatDTO] {
        // TODO: Implementare fetch da CloudKit
        return []
    }
}
