import SwiftUI
import AppKit

// Alias per i componenti del design system
private typealias GDS = GlassmorphismDesignSystem
private typealias Colors = GlassmorphismDesignSystem.SystemColors
private typealias Typography = GlassmorphismDesignSystem.Typography
private typealias Spacing = GlassmorphismDesignSystem.Spacing
private typealias Dimensions = GlassmorphismDesignSystem.Dimensions
private typealias Animations = GlassmorphismDesignSystem.Animations

// MARK: - Pending Message Models

/// Messaggio temporaneo in attesa di invio
struct PendingMessage: Identifiable {
    let id: UUID
    let content: String
    let timestamp: Date
    let attachments: [URL]
    let senderName: String
    var progress: Double // 0.0 a 1.0
    
    init(content: String, attachments: [URL], senderName: String) {
        self.id = UUID()
        self.content = content
        self.timestamp = Date()
        self.attachments = attachments
        self.senderName = senderName
        self.progress = 0.0
    }
}

/// Wrapper per messaggi reali e pending
enum DisplayMessage: Identifiable {
    case real(ChatMessage)
    case pending(PendingMessage)
    
    var id: String {
        switch self {
        case .real(let msg): return msg.id.uuidString
        case .pending(let msg): return "pending_\(msg.id.uuidString)"
        }
    }
    
    var timestamp: Date {
        switch self {
        case .real(let msg): return msg.timestamp
        case .pending(let msg): return msg.timestamp
        }
    }
}

/// Vista principale per la chat interna dell'app - Design iMessage-like iOS26
struct MessagesView: View {
    @StateObject private var chatService = CloudKitChatService.shared
    @StateObject private var mentionParser = MentionParserService.shared
    @StateObject private var userDirectory = CloudKitUserDirectoryService.shared
    
    @State private var selectedRoomId: String?
    @State private var sidebarWidth: Double = 300
    
    // Inline composer (niente modale)
    @State private var isNewChatComposerVisible = false
    @State private var newChatText: String = ""
    @State private var newChatSuggestions: [AutocompleteSuggestion] = []
    @State private var isShowingNewChatSuggestions = false
    @State private var newChatError: String?
    @FocusState private var isNewChatFocused: Bool
    
    private let currentUserEmail = GoogleAuthService.shared.userEmail
    private let currentUserName: String = {
        guard let email = GoogleAuthService.shared.userEmail else { return "Utente" }
        return email.components(separatedBy: "@").first?.replacingOccurrences(of: ".", with: " ").capitalized ?? "Utente"
    }()
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Sidebar - Lista conversazioni
                chatListSidebar
                    .frame(width: sidebarWidth)
                    .background(Color(.controlBackgroundColor).opacity(0.95))
                
                Divider()
                
                // Dettaglio conversazione
                if let roomId = selectedRoomId {
                    ChatDetailView(
                        roomId: roomId,
                        currentUserEmail: currentUserEmail ?? "",
                        currentUserName: currentUserName
                    )
                    .frame(maxWidth: .infinity)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                    .onAppear {
                        chatService.activeRoomId = roomId
                        // Polling più aggressivo quando la vista è attiva
                        chatService.setPollingInterval(1.0)
                    }
                    .onDisappear {
                        if chatService.activeRoomId == roomId {
                            chatService.activeRoomId = nil
                        }
                        // Torna al polling normale
                        chatService.setPollingInterval(3.0)
                    }
                } else {
                    emptyStateView
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedRoomId)
        .onAppear {
            Task {
                await chatService.start()
                await userDirectory.start()
            }
        }
    }
    
    // MARK: - Sidebar
    
    private var chatListSidebar: some View {
        VStack(spacing: 0) {
            // Header con glassmorphism
            HStack {
                Text("Messaggi")
                    .font(Typography.headline)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Spacer()
                
                GlassmorphicIconButton(
                    icon: isNewChatComposerVisible ? "xmark" : "square.and.pencil",
                    isActive: isNewChatComposerVisible,
                    size: 36
                ) {
                    withAnimation(Animations.spring) {
                        newChatError = nil
                        isNewChatComposerVisible.toggle()
                        if isNewChatComposerVisible {
                            isNewChatFocused = true
                        } else {
                            isShowingNewChatSuggestions = false
                        }
                    }
                }
                .help(isNewChatComposerVisible ? "Chiudi" : "Inizia chat")
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            
            if isNewChatComposerVisible {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Text field con stile glassmorphism
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        TextField("Scrivi nome o email (più nomi = gruppo)...", text: $newChatText)
                            .textFieldStyle(.plain)
                            .font(Typography.body)
                            .focused($isNewChatFocused)
                            .onChange(of: newChatText) { _, _ in
                                newChatError = nil
                                updateNewChatSuggestions()
                            }
                            .onSubmit {
                                createChatFromInlineInput()
                            }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: Dimensions.cornerRadiusSmall)
                            .fill(GDS.Colors.secondaryGlass)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Dimensions.cornerRadiusSmall)
                            .strokeBorder(
                                isNewChatFocused ? Color.accentColor.opacity(0.5) : GDS.Colors.borderLight,
                                lineWidth: isNewChatFocused ? 1.5 : Dimensions.borderWidth
                            )
                    )
                    .animation(Animations.quickSpring, value: isNewChatFocused)
                    
                    if let err = newChatError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                            Text(err)
                                .font(.caption)
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    if userDirectory.users.isEmpty {
                        HStack(spacing: 8) {
                            Text("Nessun utente iCloud disponibile.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Aggiorna") {
                                Task { await userDirectory.refreshNow(reason: "manual") }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                    
                    if isShowingNewChatSuggestions && !newChatSuggestions.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(newChatSuggestions.prefix(6)) { suggestion in
                                SuggestionRow(suggestion: suggestion, isSelected: false)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            applyNewChatSuggestion(suggestion)
                                        }
                                    }
                                
                                if suggestion.id != newChatSuggestions.prefix(6).last?.id {
                                    Divider()
                                        .padding(.leading, 44)
                                }
                            }
                        }
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.95).combined(with: .opacity),
                            removal: .scale(scale: 0.95).combined(with: .opacity)
                        ))
                    }
                    
                    HStack(spacing: Spacing.md) {
                        Button {
                            withAnimation(Animations.spring) {
                                newChatText = ""
                                newChatSuggestions = []
                                isShowingNewChatSuggestions = false
                                newChatError = nil
                                isNewChatComposerVisible = false
                            }
                        } label: {
                            Text("Annulla")
                                .font(Typography.bodyMedium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: Dimensions.cornerRadiusSmall)
                                        .fill(GDS.Colors.secondaryGlass)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Dimensions.cornerRadiusSmall)
                                        .strokeBorder(GDS.Colors.borderLight, lineWidth: Dimensions.borderWidth)
                                )
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            createChatFromInlineInput()
                        } label: {
                            Text("Crea")
                                .font(Typography.bodySemibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: Dimensions.cornerRadiusSmall)
                                        .fill(parseNewChatEmails().isEmpty ? Color.secondary.opacity(0.2) : Color.accentColor)
                                )
                                .foregroundColor(.white)
                                .shadow(color: parseNewChatEmails().isEmpty ? .clear : Color.accentColor.opacity(0.3), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .disabled(parseNewChatEmails().isEmpty)
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.lg)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Divider()
            
            // Lista conversazioni
            if chatService.rooms.isEmpty {
                VStack(spacing: Spacing.xl) {
                    Spacer()
                    
                    // Icona con effetto glassmorphism
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.15), Color.accentColor.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 90, height: 90)
                            .blur(radius: 10)
                        
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 72, height: 72)
                        
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.accentColor, .accentColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .shadow(color: Color.accentColor.opacity(0.2), radius: 15, y: 8)
                    
                    VStack(spacing: Spacing.sm) {
                        Text("Nessuna conversazione")
                            .font(Typography.title)
                            .foregroundColor(.primary)
                        
                        Text("Inizia una nuova chat per comunicare con il team")
                            .font(Typography.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    GlassmorphicButton(title: "Inizia una chat", icon: "plus.circle.fill") {
                        withAnimation(Animations.spring) {
                            newChatError = nil
                            isNewChatComposerVisible = true
                            isNewChatFocused = true
                        }
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(chatService.rooms) { room in
                            ChatRoomRow(
                                room: room,
                                isSelected: selectedRoomId == room.id,
                                currentUserEmail: currentUserEmail
                            )
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        chatService.hideRoomLocally(room.id)
                                        if selectedRoomId == room.id {
                                            selectedRoomId = nil
                                        }
                                    }
                                } label: {
                                    Label("Elimina chat (solo per me)", systemImage: "trash")
                                }
                            }
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedRoomId = room.id
                                    chatService.activeRoomId = room.id
                                }
                                Task {
                                    await chatService.fetchMessages(for: room.id)
                                    // Invia read receipt solo se l'utente ha abilitato le notifiche di lettura
                                    let profile = UserProfileService.shared.currentProfile
                                    let sendReceipts = profile?.sendReadReceipts ?? true
                                    chatService.markMessagesAsRead(
                                        in: room.id,
                                        currentUserEmail: currentUserEmail ?? "",
                                        sendReadReceipts: sendReceipts
                                    )
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        ZStack {
            // Background con gradiente subtile
            LinearGradient(
                colors: [
                    Colors.textBackground,
                    Colors.textBackground.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: Spacing.xxl) {
                Spacer()
                
                // Icona con effetto glassmorphism stile WhatsApp
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.15),
                                    Color.accentColor.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .blur(radius: 12)
                    
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: Color.accentColor.opacity(0.2), radius: 20, y: 10)
                
                VStack(spacing: Spacing.md) {
                    Text("Seleziona una conversazione")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Scegli una chat dalla lista per iniziare\na comunicare con il team")
                        .font(Typography.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Inline New Chat Helpers

private extension MessagesView {
    func updateNewChatSuggestions() {
        let query = currentNewChatQuery().lowercased()
        guard !query.isEmpty else {
            newChatSuggestions = []
            isShowingNewChatSuggestions = false
            return
        }
        
        let currentEmailLower = (currentUserEmail ?? "").lowercased()
        let candidates = userDirectory.users
            .map { (email: $0.email.lowercased(), name: $0.displayName) }
            .filter { $0.email != currentEmailLower }
        
        let matches = candidates.filter { user in
            user.name.lowercased().contains(query) || user.email.contains(query)
        }
        
        newChatSuggestions = matches.map { user in
            AutocompleteSuggestion(
                id: "user_\(user.email)",
                type: .user(email: user.email, name: user.name),
                displayText: "\(user.name) (\(user.email))",
                insertText: user.email,
                icon: "person.circle.fill"
            )
        }
        
        isShowingNewChatSuggestions = !newChatSuggestions.isEmpty
    }
    
    func currentNewChatQuery() -> String {
        // Prende l'ultimo token dopo separatori
        let separators = CharacterSet(charactersIn: ",;\n")
        let parts = newChatText.components(separatedBy: separators)
        return (parts.last ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func applyNewChatSuggestion(_ suggestion: AutocompleteSuggestion) {
        guard case .user(let email, _) = suggestion.type else { return }
        
        let separators = CharacterSet(charactersIn: ",;\n")
        var parts = newChatText.components(separatedBy: separators)
        if parts.isEmpty {
            newChatText = email + ", "
        } else {
            // Sostituisce l'ultimo token con l'email selezionata
            parts[parts.count - 1] = " " + email
            let joined = parts.joined(separator: ",")
            newChatText = joined.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newChatText.hasSuffix(",") {
                newChatText += ","
            }
            newChatText += " "
        }
        
        newChatSuggestions = []
        isShowingNewChatSuggestions = false
    }
    
    func parseNewChatEmails() -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n")
        let rawTokens = newChatText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !rawTokens.isEmpty else { return [] }
        
        var emails: [String] = []
        for token in rawTokens {
            if token.contains("@") {
                emails.append(token.lowercased())
                continue
            }
            
            // match per nome
            let directory = userDirectory.users.map { (email: $0.email.lowercased(), name: $0.displayName) }
            if let match = directory.first(where: { $0.name.lowercased() == token.lowercased() }) {
                emails.append(match.email)
            } else if let match = directory.first(where: { $0.name.lowercased().contains(token.lowercased()) }) {
                emails.append(match.email)
            } else {
                // token non risolto
                return []
            }
        }
        
        // Rimuovi duplicati e self
        let currentEmailLower = (currentUserEmail ?? "").lowercased()
        let unique = Array(Set(emails)).filter { $0 != currentEmailLower }
        return unique.sorted()
    }
    
    func createChatFromInlineInput() {
        let emails = parseNewChatEmails()
        guard !emails.isEmpty else {
            newChatError = "Seleziona almeno un utente valido dall'elenco."
            return
        }
        
        Task {
            do {
                let room: ChatRoom
                if emails.count == 1, let only = emails.first, let me = currentUserEmail {
                    room = try await chatService.findOrCreateDirectChat(with: only, currentUserEmail: me)
                } else {
                    // Nome gruppo: se l'utente ha scritto solo nomi/emails, usiamo elenco
                    let names = emails.compactMap { email in
                        userDirectory.users.first(where: { $0.email.lowercased() == email.lowercased() })?.displayName
                    }
                    let groupName = "Gruppo: " + names.prefix(3).joined(separator: ", ")
                    room = try await chatService.createGroup(name: groupName, participants: emails)
                }
                
                await MainActor.run {
                    selectedRoomId = room.id
                    newChatText = ""
                    newChatSuggestions = []
                    isShowingNewChatSuggestions = false
                    newChatError = nil
                    isNewChatComposerVisible = false
                }
            } catch {
                await MainActor.run {
                    newChatError = "Errore creazione chat: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Chat Room Row

struct ChatRoomRow: View {
    let room: ChatRoom
    let isSelected: Bool
    let currentUserEmail: String?
    
    @State private var isHovered = false
    private var userDirectory: CloudKitUserDirectoryService { CloudKitUserDirectoryService.shared }
    
    var body: some View {
        HStack(spacing: Spacing.lg) {
            // Avatar con indicatore online - stile moderno
            ZStack(alignment: .bottomTrailing) {
                if room.isGroup {
                    // Avatar gruppo
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [avatarColor.opacity(0.7), avatarColor.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: avatarColor.opacity(0.3), radius: 6, y: 3)
                        .overlay {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                        }
                } else if let otherEmail = otherUserEmail {
                    // Avatar utente dal profilo
                    AvatarFromEmailView(
                        email: otherEmail,
                        size: 48,
                        fallbackName: room.displayName(currentUserEmail: currentUserEmail),
                        showOnlineStatus: true
                    )
                } else {
                    // Fallback
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [avatarColor.opacity(0.7), avatarColor.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: avatarColor.opacity(0.3), radius: 6, y: 3)
                        .overlay {
                            Text(room.displayName(currentUserEmail: currentUserEmail).prefix(2).uppercased())
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                }
                
                // Badge sinistro collegato
                if room.isGroup || otherUserEmail == nil, room.linkedSinistroRif != nil {
                    ZStack {
                        Circle()
                            .fill(Colors.controlBackground)
                            .frame(width: 18, height: 18)
                        
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                    }
                    .offset(x: 4, y: 4)
                }
            }
            
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(displayName)
                        .font(isSelected ? Typography.bodySemibold : Typography.bodyMedium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if room.isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(Typography.small)
                            .foregroundColor(.orange.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    Text(formatDate(room.lastMessageAt))
                        .font(Typography.caption)
                        .foregroundColor(isSelected ? .accentColor : Colors.secondaryLabel)
                        .fontWeight(room.unreadCount > 0 ? .medium : .regular)
                }
                
                HStack(spacing: Spacing.sm) {
                    // Icona luogo di lavoro
                    if !room.isGroup, let otherUser = otherUserInRoom, let loc = otherUser.workLocation {
                        Image(systemName: loc.icon)
                            .font(Typography.extraSmall)
                            .foregroundColor(loc == .notWorking ? .secondary : (loc == .remote ? .green : .blue))
                    }
                    
                    if let sender = room.lastMessageSender, room.isGroup {
                        Text("\(sender):")
                            .font(Typography.body)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    
                    if let preview = room.lastMessagePreview {
                        Text(preview)
                            .font(Typography.body)
                            .foregroundColor(Colors.secondaryLabel)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                }
            }
            
            if room.unreadCount > 0 {
                GlassmorphicBadge(text: "\(room.unreadCount)", color: .accentColor)
                    .scaleEffect(isHovered ? 1.05 : 1.0)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Dimensions.cornerRadius)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? GDS.Colors.primaryGlass : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.cornerRadius)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.3) : (isHovered ? GDS.Colors.borderLight : Color.clear),
                    lineWidth: isSelected ? 1.5 : Dimensions.borderWidth
                )
        )
        .padding(.horizontal, Spacing.md)
        .scaleEffect(isHovered ? 0.99 : 1.0)
        .animation(Animations.quickSpring, value: isSelected)
        .animation(Animations.quickSpring, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var otherUserEmail: String? {
        room.participants.first { $0.lowercased() != (currentUserEmail ?? "").lowercased() }
    }
    
    private var otherUserInRoom: CloudKitUserDirectoryService.CloudUser? {
        guard let email = otherUserEmail else { return nil }
        return userDirectory.user(email: email)
    }
    
    /// Nome visualizzato usando il sistema profili
    private var displayName: String {
        if room.isGroup {
            return room.displayName(currentUserEmail: currentUserEmail)
        }
        if let email = otherUserEmail {
            return UserDisplayNameHelper.displayName(for: email, fallbackName: room.displayName(currentUserEmail: currentUserEmail))
        }
        return room.displayName(currentUserEmail: currentUserEmail)
    }
    
    private var avatarColor: Color {
        switch room.roomType {
        case .sinistro: return .orange
        case .group: return .purple
        case .team: return .green
        case .direct: return .accentColor
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        DateUtils.formatSmart(date)
    }
}

// MARK: - Chat Detail View

struct ChatDetailView: View {
    let roomId: String
    let currentUserEmail: String
    let currentUserName: String
    
    @StateObject private var chatService = CloudKitChatService.shared
    @StateObject private var mentionParser = MentionParserService.shared
    @StateObject private var userDirectory = CloudKitUserDirectoryService.shared
    
    @State private var messageText = ""
    @State private var showingAutocomplete = false
    @State private var autocompleteContext: AutocompleteContext?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var selectedAttachments: [URL] = []
    @State private var showingFilePicker = false
    @State private var pinToDiario = false
    @State private var showingLinkSinistroSheet = false
    
    // Hashtag options (UI-only, non visibile nel testo)
    @State private var hashtagFilterOverrides: [String: String] = [:] // tag -> filter (es. "sinistri" -> "utente")
    
    // Hover token (editor) - sticky popover
    @State private var hoveredInputToken: MentionRichTextEditor.HoverToken?
    @State private var activeInputPopoverToken: MentionRichTextEditor.HoverToken?
    @State private var isInputPopoverHovered: Bool = false
    @State private var inputPopoverDismissTask: Task<Void, Never>?
    @State private var emptySendShake: Int = 0
    
    // Floating composer behavior
    @State private var editorIsFocused: Bool = false
    @State private var editorFocusTrigger: Int = 0
    @State private var keyMonitor: Any?
    @State private var inputHeight: CGFloat = 36
    @State private var showingAttachmentPopover = false
    
    // Typing indicator
    @State private var typingUsers: [CloudKitUserDirectoryService.CloudUser] = []
    @State private var typingTimer: Timer?
    @State private var lastTypingSignal: Date = .distantPast
    
    // Animazioni invio messaggio
    @State private var isSending = false
    @State private var sendAnimationTrigger = 0
    @State private var lastMessageCount = 0
    
    // Messaggi pending (ottimistici)
    @State private var pendingMessages: [PendingMessage] = []
    @State private var uploadProgress: Double = 0.0
    
    private var messages: [ChatMessage] {
        chatService.messages[roomId] ?? []
    }
    
    private var allMessages: [DisplayMessage] {
        let realMessages = messages.map { DisplayMessage.real($0) }
        let pending = pendingMessages.map { DisplayMessage.pending($0) }
        return realMessages + pending
    }
    
    private var room: ChatRoom? {
        chatService.rooms.first(where: { $0.id == roomId })
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background con gradiente subtile
            LinearGradient(
                colors: [
                    Color(.textBackgroundColor),
                    Color(.textBackgroundColor).opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                chatHeader
                
                Divider()
                
                if let linkedRif = chatService.activeLinkedSinistro {
                    linkedSinistroBar(riferimento: linkedRif)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(allMessages) { displayMessage in
                                Group {
                                    switch displayMessage {
                                    case .real(let message):
                                        MessageBubble(
                                            message: message,
                                            isCurrentUser: message.isSentByCurrentUser(currentEmail: currentUserEmail),
                                            isGroupChat: room?.isGroup ?? false,
                                            onLinkToSinistro: { rif in
                                                chatService.linkToSinistro(rif, in: roomId)
                                            },
                                            onPinToDiario: { msg in
                                                Task {
                                                    try? await chatService.updateMessageLink(
                                                        msg.id,
                                                        in: roomId,
                                                        linkedSinistroRif: msg.linkedSinistroRif ?? chatService.activeLinkedSinistro,
                                                        pinToDiario: true
                                                    )
                                                }
                                            }
                                        )
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.85, anchor: message.isSentByCurrentUser(currentEmail: currentUserEmail) ? .bottomTrailing : .bottomLeading)
                                                .combined(with: .opacity)
                                                .combined(with: .move(edge: .bottom)),
                                            removal: .scale(scale: 0.9).combined(with: .opacity)
                                        ))
                                        
                                    case .pending(let pendingMessage):
                                        PendingMessageBubble(
                                            message: pendingMessage,
                                            uploadProgress: pendingMessage.progress
                                        )
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.85, anchor: .bottomTrailing)
                                                .combined(with: .opacity)
                                                .combined(with: .move(edge: .bottom)),
                                            removal: .scale(scale: 0.9).combined(with: .opacity)
                                        ))
                                    }
                                }
                                .id(displayMessage.id)
                            }
                            
                            // Typing indicator
                            if !typingUsers.isEmpty {
                                HStack {
                                    TypingIndicatorBubble(users: typingUsers)
                                        .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 160)
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: allMessages.count)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: typingUsers.count)
                    }
                    .onAppear {
                        scrollProxy = proxy
                        lastMessageCount = messages.count
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollToBottom(animated: false)
                        }
                    }
                    .onChange(of: allMessages.count) { oldCount, newCount in
                        // Scroll automatico quando aumentano
                        if newCount > oldCount {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                scrollToBottom()
                            }
                        }
                    }
                }
            }
            
            // Composer con effetto glassmorphism
            floatingComposer
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .scaleEffect(isSending ? 0.97 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isSending)
        }
        .onAppear {
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.image, .movie, .pdf, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedAttachments.append(contentsOf: urls)
                }
            }
        }
    }
    
    // MARK: - Linked Sinistro Bar (stile WhatsApp)
    
    private func linkedSinistroBar(riferimento: String) -> some View {
        HStack(spacing: Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.orange)
            }
            
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Sinistro \(riferimento)")
                    .font(Typography.bodySemibold)
                    .foregroundColor(.primary)
                
                Text("I messaggi verranno associati a questo sinistro")
                    .font(Typography.small)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Pulsante apri sinistro
            Button {
                NotificationCenter.default.post(
                    name: NSNotification.Name("OpenSinistroByRif"),
                    object: nil,
                    userInfo: ["riferimento": riferimento]
                )
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12))
                    Text("Apri")
                        .font(Typography.caption)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(Dimensions.cornerRadiusSmall)
            }
            .buttonStyle(.plain)
            .help("Apri sinistro")
            
            // Pulsante scollega
            Button {
                withAnimation(Animations.spring) {
                    chatService.unlinkFromSinistro(in: roomId)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Scollega dal sinistro")
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .background(
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.12),
                    Color.orange.opacity(0.06)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            Divider()
                .offset(y: 0.5),
            alignment: .bottom
        )
    }
    
    // MARK: - Header (Stile iMessage/macOS 26)
    
    private var chatHeader: some View {
        HStack(spacing: 0) {
            // Controlli sinistra con GlassmorphicIconButton
            if let room = room {
                HStack(spacing: Spacing.sm) {
                    // Mute/Notifiche
                    GlassmorphicIconButton(
                        icon: room.isMuted ? "bell.slash.fill" : "bell.fill",
                        isActive: room.isMuted,
                        size: 36
                    ) {
                        Task {
                            try? await chatService.toggleMute(for: roomId)
                        }
                    }
                    .help(room.isMuted ? "Riattiva notifiche" : "Silenzia")
                    
                    // Refresh
                    GlassmorphicIconButton(
                        icon: "arrow.clockwise",
                        size: 36
                    ) {
                        Task {
                            await chatService.fetchMessages(for: roomId)
                        }
                    }
                    .help("Aggiorna")
                }
                .padding(.leading, Spacing.xl)
            }
            
            Spacer()
            
            // Centro: Avatar + Info (stile iMessage/WhatsApp)
            if let room = room {
                VStack(spacing: Spacing.md) {
                    // Avatar grande con status indicator - stile WhatsApp
                    ZStack {
                        if room.isGroup {
                            // Avatar gruppo con gradiente
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.7), .purple.opacity(0.5)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 52, height: 52)
                                .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
                                .overlay {
                                    Image(systemName: "person.3.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                        } else if let otherEmail = otherUserEmailInRoom(room) {
                            // Avatar utente dal profilo
                            AvatarFromEmailView(
                                email: otherEmail,
                                size: 52,
                                fallbackName: room.displayName(currentUserEmail: currentUserEmail),
                                showOnlineStatus: true
                            )
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
                        } else {
                            // Fallback
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor.opacity(0.7), Color.accentColor.opacity(0.5)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 52, height: 52)
                                .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
                                .overlay {
                                    Text(room.displayName(currentUserEmail: currentUserEmail).prefix(1).uppercased())
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                        }
                    }
                    
                    // Nome utente/room
                    Button {
                        // TODO: Dettagli chat
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text(headerDisplayName(for: room))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // Pills con info
                    HStack(spacing: Spacing.sm) {
                        // Badge sinistro collegato
                        if let linkedRif = room.linkedSinistroRif {
                            headerPill(text: linkedRif, icon: "folder.fill", color: .orange)
                        }
                        
                        // Badge tipo
                        headerPill(
                            text: room.isGroup ? "Gruppo" : "Chat diretta",
                            icon: room.isGroup ? "person.3.fill" : "person.fill",
                            color: room.isGroup ? .purple : .blue
                        )
                    }
                    
                    // Info contestuale (orario lavoro + sede/remoto)
                    if !typingUsers.isEmpty {
                        typingIndicatorLabel
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.95).combined(with: .opacity),
                                removal: .scale(scale: 0.95).combined(with: .opacity)
                            ))
                    } else if !room.isGroup, let otherUser = otherUserInRoom(room) {
                        modernWorkScheduleInfo(for: otherUser)
                            .transition(.opacity)
                    }
                }
                .animation(Animations.spring, value: typingUsers.count)
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.xs)
            }
            
            Spacer()
            
            // Controlli destra con GlassmorphicIconButton
            if room != nil {
                HStack(spacing: Spacing.sm) {
                    // Apri in finestra
                    GlassmorphicIconButton(
                        icon: "rectangle.portrait.on.rectangle.portrait",
                        size: 36
                    ) {
                        openChatInNewWindow()
                    }
                    .help("Apri in finestra")
                    
                    // Info/Dettagli
                    GlassmorphicIconButton(
                        icon: "info.circle",
                        size: 36
                    ) {
                        // TODO: Mostra dettagli chat
                    }
                    .help("Info")
                }
                .padding(.trailing, Spacing.xl)
            }
        }
        .padding(.vertical, Spacing.xl)
        .background(
            ZStack {
                // Sfondo glassmorphism
                VisualEffectBlur(material: .headerView)
                
                // Glass overlay
                GDS.Colors.primaryGlass
            }
        )
        .overlay(
            Rectangle()
                .fill(GDS.Colors.borderLight)
                .frame(height: 0.5),
            alignment: .bottom
        )
        .onAppear {
            startTypingPolling()
        }
        .onDisappear {
            stopTypingPolling()
        }
    }
    
    // MARK: - Modern Work Schedule Info (Stile iOS 26)
    
    private func modernWorkScheduleInfo(for user: CloudKitUserDirectoryService.CloudUser) -> some View {
        HStack(spacing: Spacing.md) {
            // Orario di lavoro
            HStack(spacing: Spacing.xs) {
                Image(systemName: workScheduleIcon(for: user))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(workScheduleText(for: user))
                    .font(Typography.bodyMedium)
                    .foregroundColor(.secondary)
            }
            
            // Separatore
            Text("·")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary.opacity(0.5))
            
            // Sede / Remoto / Non lavora
            HStack(spacing: Spacing.xs) {
                let location = user.workLocation ?? .office
                
                Image(systemName: location.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(locationColor(for: location))
                
                Text(locationLabel(for: location))
                    .font(Typography.bodyMedium)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(
            Capsule()
                .fill(GDS.Colors.secondaryGlass)
                .overlay(
                    Capsule()
                        .strokeBorder(GDS.Colors.borderLight, lineWidth: Dimensions.borderWidth)
                )
        )
    }
    
    private func workScheduleIcon(for user: CloudKitUserDirectoryService.CloudUser) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let isWorkingHours = (9...18).contains(hour)
        
        if user.workLocation == .notWorking {
            return "moon.zzz.fill"
        }
        
        if isWorkingHours && user.onlineStatus == .online {
            return "clock.fill"
        } else if !isWorkingHours {
            return "moon.fill"
        } else {
            return "clock"
        }
    }
    
    private func workScheduleText(for user: CloudKitUserDirectoryService.CloudUser) -> String {
        if user.workLocation == .notWorking {
            return "Non lavora oggi"
        }
        
        let hour = Calendar.current.component(.hour, from: Date())
        let isWorkingHours = (9...18).contains(hour)
        
        if isWorkingHours {
            return "Orario lavorativo"
        } else if hour < 9 {
            return "Fuori orario"
        } else {
            return "Dopo lavoro"
        }
    }
    
    private func locationColor(for location: CloudKitUserDirectoryService.WorkLocation) -> Color {
        switch location {
        case .remote: return .green
        case .office: return .blue
        case .notWorking: return .secondary
        }
    }
    
    private func locationLabel(for location: CloudKitUserDirectoryService.WorkLocation) -> String {
        switch location {
        case .remote: return "Remoto"
        case .office: return "In sede"
        case .notWorking: return "Libero"
        }
    }
    
    // MARK: - Header Pill (stile WhatsApp)
    
    private func headerPill(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(Typography.small)
                .fontWeight(.medium)
        }
        .foregroundColor(color)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Chat Header Helpers
    
    private func otherUserEmailInRoom(_ room: ChatRoom) -> String? {
        room.participants.first { $0.lowercased() != currentUserEmail.lowercased() }
    }
    
    private func otherUserInRoom(_ room: ChatRoom) -> CloudKitUserDirectoryService.CloudUser? {
        guard let email = otherUserEmailInRoom(room) else { return nil }
        return userDirectory.user(email: email)
    }
    
    /// Nome visualizzato per l'header usando il sistema profili
    private func headerDisplayName(for room: ChatRoom) -> String {
        if room.isGroup {
            return room.displayName(currentUserEmail: currentUserEmail)
        }
        if let email = otherUserEmailInRoom(room) {
            return UserDisplayNameHelper.displayName(for: email, fallbackName: room.displayName(currentUserEmail: currentUserEmail))
        }
        return room.displayName(currentUserEmail: currentUserEmail)
    }
    
    private var typingIndicatorLabel: some View {
        HStack(spacing: 4) {
            TypingDotsView()
            
            let names = typingUsers.prefix(2).map(\.displayName)
            if names.count == 1 {
                Text("\(names[0]) sta scrivendo...")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .italic()
            } else if names.count == 2 {
                Text("\(names[0]) e \(names[1]) stanno scrivendo...")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .italic()
            } else {
                Text("Stanno scrivendo...")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .italic()
            }
        }
    }
    
    private func startTypingPolling() {
        stopTypingPolling()
        typingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                typingUsers = await userDirectory.fetchTypingUsers(in: roomId)
            }
        }
    }
    
    private func stopTypingPolling() {
        typingTimer?.invalidate()
        typingTimer = nil
    }
    
    private func openChatInNewWindow() {
        guard let room = room else { return }
        
        let detailView = ChatDetailView(
            roomId: roomId,
            currentUserEmail: currentUserEmail,
            currentUserName: currentUserName
        )
        
        let hostingController = NSHostingController(rootView: detailView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Chat: \(room.displayName(currentUserEmail: currentUserEmail))"
        window.setContentSize(NSSize(width: 600, height: 700))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        // Mantieni riferimento
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Message Input (Floating Composer stile WhatsApp/iMessage)
    
    private var floatingComposer: some View {
        VStack(spacing: Spacing.md) {
            if !selectedAttachments.isEmpty {
                attachmentsPreview
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            if showingAutocomplete && !mentionParser.suggestions.isEmpty {
                GlassmorphicPopover {
                    MentionAutocompleteView(
                        suggestions: mentionParser.suggestions,
                        onSelect: { suggestion in
                            withAnimation(Animations.spring) {
                                insertSuggestion(suggestion)
                                showingAutocomplete = false
                            }
                        }
                    )
                    .frame(maxHeight: 220)
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92, anchor: .bottom).combined(with: .opacity),
                    removal: .scale(scale: 0.95, anchor: .bottom).combined(with: .opacity)
                ))
            }
            
            HStack(spacing: Spacing.md) {
                // Pulsante allega
                Button {
                    withAnimation(Animations.spring) {
                        showingAttachmentPopover.toggle()
                    }
                } label: {
                    Image(systemName: showingAttachmentPopover ? "xmark" : "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 32, height: 32)
                        .background(showingAttachmentPopover ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                        .rotationEffect(.degrees(showingAttachmentPopover ? 90 : 0))
                }
                .buttonStyle(.plain)
                .help("Allega file")
                .popover(isPresented: $showingAttachmentPopover) {
                    AttachmentPickerPopover(
                        roomId: roomId,
                        onFileSelected: { urls in
                            selectedAttachments.append(contentsOf: urls)
                            showingAttachmentPopover = false
                        },
                        onPickFiles: {
                            showingAttachmentPopover = false
                            showingFilePicker = true
                        }
                    )
                }
                
                // Editor con design iOS-like
                ZStack(alignment: .topLeading) {
                    MentionRichTextEditor(
                        text: $messageText,
                        isFocused: $editorIsFocused,
                        focusTrigger: editorFocusTrigger,
                        fontSize: 15,
                        onTextChange: { newValue in
                            handleTextChange(newValue)
                            updateInputHeight(for: newValue)
                        },
                        onSubmit: {
                            if canSendByEnter {
                                sendMessage()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                    emptySendShake += 1
                                }
                            }
                        },
                        onEmptySubmit: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                emptySendShake += 1
                            }
                        },
                        onHoverTokenChange: { token in
                            hoveredInputToken = token
                            handleInputTokenHoverChange(token)
                        }
                    )
                    .frame(minHeight: inputHeight, maxHeight: min(120, 34 + 4 * 20)) // max 5 righe
                    .modifier(ShakeEffect(trigger: emptySendShake))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: inputHeight)
                    
                    if messageText.isEmpty && !editorIsFocused {
                        Text("Messaggio")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let token = activeInputPopoverToken {
                        TokenPopoverContainer(
                            token: token,
                            hashtagFilterOverrides: $hashtagFilterOverrides,
                            isPopoverHovered: $isInputPopoverHovered,
                            onHoverChange: { hovering in
                                if !hovering && hoveredInputToken == nil {
                                    scheduleInputPopoverDismiss()
                                }
                            },
                            onHashtagClick: { hashtag, email, name in
                                openHashtagWindow(hashtag: hashtag, senderEmail: currentUserEmail, senderName: currentUserName)
                            },
                            senderEmail: currentUserEmail,
                            senderName: currentUserName
                        )
                        .frame(maxWidth: 380)
                        .padding(.top, -12)
                        .offset(y: -10)
                    }
                }
                
                if chatService.activeLinkedSinistro != nil || hasMentionedRiferimento {
                    Button {
                        withAnimation(Animations.spring) {
                            pinToDiario.toggle()
                        }
                    } label: {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(pinToDiario ? .orange : .secondary)
                            .frame(width: 32, height: 32)
                            .background(pinToDiario ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                            .rotationEffect(.degrees(pinToDiario ? 45 : 0))
                    }
                    .buttonStyle(.plain)
                    .help("Salva nel diario del sinistro")
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Pulsante invio stile WhatsApp
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            canSend
                                ? Color.accentColor
                                : Color.secondary.opacity(0.3)
                        )
                        .clipShape(Circle())
                        .shadow(color: canSend ? Color.accentColor.opacity(0.3) : .clear, radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .animation(Animations.easeInOut, value: canSend)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Colors.controlBackground.opacity(0.95))
                    .shadow(color: GDS.Colors.shadowDark.opacity(0.5), radius: 8, y: 2)
            )
        }
        .animation(Animations.spring, value: showingAutocomplete)
        .animation(Animations.spring, value: selectedAttachments.count)
    }
    
    private var canSendByEnter: Bool {
        // richiesta: almeno 1 carattere (gli allegati non contano per Enter)
        !messageText.isEmpty
    }

    private func updateInputHeight(for text: String) {
        // Stima semplice: cresce con righe (Shift+Invio) fino a max 5
        let lines = max(1, min(5, text.split(separator: "\n", omittingEmptySubsequences: false).count))
        let base: CGFloat = 34 // Più compatto
        let extraPerLine: CGFloat = 20
        inputHeight = base + CGFloat(lines - 1) * extraPerLine
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // se già in input, non intercettare
            if editorIsFocused { return event }
            
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
                return event
            }
            
            guard let chars = event.characters, !chars.isEmpty else { return event }
            
            // ignora tasti speciali
            if chars == "\r" || chars == "\n" || chars == "\t" || chars == "\u{1b}" {
                return event
            }
            
            // se l'utente inizia a scrivere: focus + inserisci caratteri
            messageText.append(chars)
            updateInputHeight(for: messageText)
            editorFocusTrigger += 1
            return nil
        }
    }
    
    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
    
    private var attachmentsPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                ForEach(selectedAttachments, id: \.absoluteString) { url in
                    AttachmentPreviewChip(url: url) {
                        withAnimation(Animations.spring) {
                            selectedAttachments.removeAll { $0 == url }
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
        }
        .background(
            RoundedRectangle(cornerRadius: Dimensions.cornerRadius)
                .fill(Colors.controlBackground.opacity(0.9))
        )
    }
    
    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedAttachments.isEmpty
    }
    
    private var hasMentionedRiferimento: Bool {
        let mentions = mentionParser.parseMentions(from: messageText)
        return mentions.contains { $0.type == .riferimento }
    }

    private func handleInputTokenHoverChange(_ token: MentionRichTextEditor.HoverToken?) {
        inputPopoverDismissTask?.cancel()
        inputPopoverDismissTask = nil
        
        if let token {
            activeInputPopoverToken = token
            return
        }
        
        // mouse left token: dismiss only if not over popover (with delay)
        scheduleInputPopoverDismiss()
    }
    
    private func scheduleInputPopoverDismiss() {
        inputPopoverDismissTask?.cancel()
        inputPopoverDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000) // 220ms grace
            if hoveredInputToken == nil && !isInputPopoverHovered {
                activeInputPopoverToken = nil
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleTextChange(_ text: String) {
        let cursorPosition = text.count
        
        if let context = mentionParser.detectAutocompleteContext(in: text, cursorPosition: cursorPosition) {
            autocompleteContext = context
            showingAutocomplete = true
            
            Task {
                await mentionParser.generateSuggestions(for: context)
            }
        } else {
            showingAutocomplete = false
            autocompleteContext = nil
        }
        
        // Segnala "sta scrivendo" ogni 3 secondi
        if Date().timeIntervalSince(lastTypingSignal) > 3 && !text.isEmpty {
            lastTypingSignal = Date()
            Task {
                await userDirectory.setTyping(in: roomId)
            }
        }
    }
    
    private func insertSuggestion(_ suggestion: AutocompleteSuggestion) {
        guard let context = autocompleteContext else { return }
        
        let startIndex = context.startIndex
        let prefix = String(messageText[..<startIndex])
        let insertText = suggestion.insertText + " "
        
        messageText = prefix + insertText
        autocompleteContext = nil
    }
    
    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        
        // Crea messaggio pending immediatamente
        let pendingMsg = PendingMessage(
            content: content,
            attachments: selectedAttachments,
            senderName: currentUserName
        )
        
        // Feedback immediato - aggiungi alla UI
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            pendingMessages.append(pendingMsg)
            isSending = true
            sendAnimationTrigger += 1
        }
        
        // Salva stato locale
        let localContent = content
        let localAttachments = selectedAttachments
        let localPinToDiario = pinToDiario
        let pendingId = pendingMsg.id
        
        // Pulisci UI immediatamente per feedback rapido
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            messageText = ""
            selectedAttachments = []
            pinToDiario = false
            inputHeight = 36
        }
        
        // Scroll immediato al messaggio pending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                scrollToBottom()
            }
        }
        
        let mentions = mentionParser.parseMentions(from: localContent)
        let hashtags = mentionParser.parseHashtags(from: localContent, overrides: hashtagFilterOverrides)
        
        Task {
            // Pulisci indicatore typing
            await userDirectory.clearTyping(in: roomId)
            
            do {
                // Upload allegati con progress
                var uploadedAttachments: [ChatAttachment] = []
                let totalAttachments = localAttachments.count
                
                if totalAttachments > 0 {
                    // Con allegati: mostra progress
                    for (index, url) in localAttachments.enumerated() {
                        _ = url.startAccessingSecurityScopedResource()
                        defer { url.stopAccessingSecurityScopedResource() }
                        
                        // Update progress (0.0-0.7 per upload allegati)
                        let progress = 0.7 * (Double(index) / Double(totalAttachments))
                        await MainActor.run {
                            if let idx = pendingMessages.firstIndex(where: { $0.id == pendingId }) {
                                pendingMessages[idx].progress = progress
                            }
                        }
                        
                        let attachment = try await chatService.uploadAttachment(from: url, roomId: roomId)
                        uploadedAttachments.append(attachment)
                    }
                    
                    // Allegati caricati
                    await MainActor.run {
                        if let idx = pendingMessages.firstIndex(where: { $0.id == pendingId }) {
                            pendingMessages[idx].progress = 0.8
                        }
                    }
                } else {
                    // Senza allegati: progress simulato veloce
                    await MainActor.run {
                        if let idx = pendingMessages.firstIndex(where: { $0.id == pendingId }) {
                            pendingMessages[idx].progress = 0.3
                        }
                    }
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                }
                
                // Invio messaggio
                await MainActor.run {
                    if let idx = pendingMessages.firstIndex(where: { $0.id == pendingId }) {
                        pendingMessages[idx].progress = 0.9
                    }
                }
                
                _ = try await chatService.sendMessage(
                    roomId: roomId,
                    content: localContent,
                    mentions: mentions,
                    hashtags: hashtags,
                    attachments: uploadedAttachments,
                    senderEmail: currentUserEmail,
                    senderName: currentUserName,
                    pinToDiario: localPinToDiario
                )
                
                // Progress completo
                await MainActor.run {
                    if let idx = pendingMessages.firstIndex(where: { $0.id == pendingId }) {
                        pendingMessages[idx].progress = 1.0
                    }
                }
                
                // Piccolo delay per mostrare il completamento
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                
                // Fetch immediato per vedere il messaggio reale
                await chatService.fetchMessages(for: roomId)
                
                await MainActor.run {
                    // Rimuovi pending message con animazione
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        pendingMessages.removeAll { $0.id == pendingId }
                        isSending = false
                    }
                    
                    // Scroll al messaggio reale
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            scrollToBottom()
                        }
                    }
                }
            } catch {
                print("[ChatDetail] ❌ Errore invio messaggio: \(error)")
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        // Rimuovi pending message
                        pendingMessages.removeAll { $0.id == pendingId }
                        isSending = false
                        // Ripristina in caso di errore
                        messageText = localContent
                        selectedAttachments = localAttachments
                        pinToDiario = localPinToDiario
                    }
                }
            }
        }
    }
    
    private func scrollToBottom(animated: Bool = true) {
        guard let lastMessage = allMessages.last else { return }
        
        if animated {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
            }
        } else {
            scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}

// MARK: - Attachment Preview Chip

struct AttachmentPreviewChip: View {
    let url: URL
    let onRemove: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)
                
                Text(formatFileSize())
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Button {
                onRemove()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 20, height: 20)
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.controlColor).opacity(isHovered ? 1.0 : 0.8))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var iconName: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic": return "photo.fill"
        case "mp4", "mov", "m4v": return "video.fill"
        case "pdf": return "doc.text.fill"
        default: return "doc.fill"
        }
    }
    
    private var iconColor: Color {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic": return .blue
        case "mp4", "mov", "m4v": return .purple
        case "pdf": return .red
        default: return .secondary
        }
    }
    
    private func formatFileSize() -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            return "—"
        }
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    let isCurrentUser: Bool
    let isGroupChat: Bool  // Nuovo: per mostrare nome solo in gruppi
    var onLinkToSinistro: ((String) -> Void)?
    var onPinToDiario: ((ChatMessage) -> Void)?
    
    @StateObject private var mentionParser = MentionParserService.shared
    @State private var showingContextMenu = false
    @State private var hoveredToken: MentionRichTextEditor.HoverToken?
    @State private var activeBubblePopoverToken: MentionRichTextEditor.HoverToken?
    @State private var isBubblePopoverHovered: Bool = false
    @State private var bubblePopoverDismissTask: Task<Void, Never>?
    @State private var appeared = false
    
    var body: some View {
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
            // Box collegamento sinistro
            if let linkedRif = message.linkedSinistroRif {
                linkedSinistroBox(riferimento: linkedRif)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            HStack(alignment: .bottom, spacing: 10) {
                if isCurrentUser { Spacer(minLength: 60) }
                
                // Avatar mittente per chat di gruppo (solo messaggi non propri)
                if !isCurrentUser && isGroupChat {
                    AvatarFromEmailView(
                        email: message.senderEmail,
                        size: 32,
                        fallbackName: message.senderName
                    )
                }
                
                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 3) {
                    // Nome mittente SOLO per chat di gruppo - usa nome dal profilo
                    if !isCurrentUser && isGroupChat {
                        Text(UserDisplayNameHelper.displayName(for: message.senderEmail, fallbackName: message.senderName))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.85))
                            .padding(.leading, 6)
                    }
                    
                    // Contenuto messaggio con bolla
                    HStack(spacing: 0) {
                        if isCurrentUser { Spacer(minLength: 0) }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // Allegati
                            if !message.attachments.isEmpty {
                                attachmentsGrid
                            }
                            
                            // Testo con menzioni/hashtag
                            if !message.content.isEmpty {
                                MentionTokenTextView(
                                    text: message.content,
                                    fontSize: 15,
                                    baseColor: bubbleTextBaseColor,
                                    mentionColor: bubbleTokenColor,
                                    hashtagColor: bubbleTokenColor,
                                    onHoverTokenChange: { token in
                                        hoveredToken = token
                                        handleBubbleTokenHoverChange(token)
                                    }
                                )
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(
                            Group {
                                if isCurrentUser {
                                    LinearGradient(
                                        colors: message.isLinkedToSinistro
                                            ? [Color.orange, Color.orange.opacity(0.9)]
                                            : [Color.accentColor, Color.accentColor.opacity(0.9)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                } else {
                                    LinearGradient(
                                        colors: message.isLinkedToSinistro
                                            ? [Color.orange.opacity(0.18), Color.orange.opacity(0.12)]
                                            : [Color(.windowBackgroundColor), Color(.windowBackgroundColor).opacity(0.95)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                }
                            }
                        )
                        .clipShape(ModernBubbleShape(isFromCurrentUser: isCurrentUser))
                        .shadow(
                            color: isCurrentUser
                                ? (message.isLinkedToSinistro ? Color.orange.opacity(0.25) : Color.accentColor.opacity(0.25))
                                : Color.black.opacity(0.08),
                            radius: isCurrentUser ? 6 : 4,
                            y: isCurrentUser ? 3 : 2
                        )
                        .overlay(alignment: .topLeading) {
                            if let token = activeBubblePopoverToken {
                                TokenPopoverContainer(
                                    token: token,
                                    hashtagFilterOverrides: .constant([:]),
                                    isPopoverHovered: $isBubblePopoverHovered,
                                    onHoverChange: { hovering in
                                        if !hovering && hoveredToken == nil {
                                            scheduleBubblePopoverDismiss()
                                        }
                                    },
                                    onHashtagClick: { hashtag, _, _ in
                                        // Apri finestra hashtag con i dati del sender del messaggio
                                        ChatDetailViewHelper.openHashtagWindow(
                                            hashtag: hashtag,
                                            senderEmail: message.senderEmail,
                                            senderName: message.senderName
                                        )
                                    },
                                    senderEmail: message.senderEmail,
                                    senderName: message.senderName
                                )
                                .frame(maxWidth: 380)
                                .padding(.top, -10)
                                .offset(y: -8)
                            }
                        }
                        .contextMenu {
                            contextMenuItems
                        }
                        
                        if !isCurrentUser { Spacer(minLength: 0) }
                    }
                    .frame(maxWidth: 500)
                    
                    // Footer: timestamp e indicatori
                    HStack(spacing: 5) {
                        Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                        
                        if message.isPinnedToDiario {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                        
                        // Indicatore letto per messaggi inviati
                        if isCurrentUser {
                            readStatusIcon
                        }
                    }
                    .padding(.horizontal, 6)
                    
                    // Visualizzato alle (dettaglio orario)
                    if isCurrentUser {
                        ReadReceiptsView(message: message)
                    }
                }
                
                if !isCurrentUser { Spacer(minLength: 60) }
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.9, anchor: isCurrentUser ? .bottomTrailing : .bottomLeading)
        .offset(y: appeared ? 0 : 15)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }
    
    // Icona di stato lettura
    @ViewBuilder
    private var readStatusIcon: some View {
        let hasReaders = message.readReceipts.contains { $0.userEmail.lowercased() != message.senderEmail.lowercased() }
        
        if hasReaders {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(.accentColor)
        } else {
            Image(systemName: "checkmark.circle")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var bubbleTextBaseColor: NSColor {
        if isCurrentUser { return .white }
        return .labelColor
    }
    
    private var bubbleTokenColor: NSColor {
        if isCurrentUser { return .white.withAlphaComponent(0.9) }
        return .systemBlue
    }

    private func handleBubbleTokenHoverChange(_ token: MentionRichTextEditor.HoverToken?) {
        bubblePopoverDismissTask?.cancel()
        bubblePopoverDismissTask = nil
        
        if let token {
            activeBubblePopoverToken = token
            return
        }
        
        scheduleBubblePopoverDismiss()
    }
    
    private func scheduleBubblePopoverDismiss() {
        bubblePopoverDismissTask?.cancel()
        bubblePopoverDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            if hoveredToken == nil && !isBubblePopoverHovered {
                activeBubblePopoverToken = nil
            }
        }
    }
    
    // MARK: - Linked Sinistro Box
    
    private func linkedSinistroBox(riferimento: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "link.circle.fill")
                .foregroundColor(.orange)
                .font(.caption)
            
            Text("Collegato a \(riferimento)")
                .font(.caption2)
                .foregroundColor(.orange)
            
            if message.isPinnedToDiario {
                Text("- Salvato nel diario")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Attachments Grid
    
    private var attachmentsGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(message.attachments) { attachment in
                AttachmentBubbleView(attachment: attachment, isCurrentUser: isCurrentUser)
            }
        }
    }
    
    private var bubbleBackground: some ShapeStyle {
        if message.isLinkedToSinistro {
            return isCurrentUser ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color.orange.opacity(0.15))
        }
        // Colore più visibile per i messaggi ricevuti
        return isCurrentUser ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.windowBackgroundColor).opacity(0.95))
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        // Collega a sinistro (se ha menzione riferimento)
        if let riferimento = message.mentions.first(where: { $0.type == .riferimento })?.value {
            Button {
                onLinkToSinistro?(riferimento)
            } label: {
                Label("Collega a \(riferimento)", systemImage: "link")
            }
        }

        // Pin al diario
        if message.linkedSinistroRif != nil && !message.isPinnedToDiario {
            Button {
                onPinToDiario?(message)
            } label: {
                Label("Salva nel diario", systemImage: "pin")
            }
        }

        // Undo send (entro 5 minuti)
        if isCurrentUser {
            let canUndo = CloudKitChatService.shared.canUndoSend(message, currentUserEmail: GoogleAuthService.shared.userEmail)
            if canUndo {
                Divider()
                Button(role: .destructive) {
                    Task {
                        try? await CloudKitChatService.shared.undoSend(
                            messageId: message.id,
                            roomId: message.roomId,
                            currentUserEmail: GoogleAuthService.shared.userEmail
                        )
                    }
                } label: {
                    Label("Annulla invio", systemImage: "arrow.uturn.backward")
                }
            }
        }

        Divider()

        Button {
            let content = message.content
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
        } label: {
            Label("Copia testo", systemImage: "doc.on.doc")
        }
    }
}

// MARK: - Modern Bubble Shape (stile iOS 26)

struct ModernBubbleShape: Shape {
    let isFromCurrentUser: Bool
    
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 20
        let tailSize: CGFloat = 8
        
        var path = Path()
        
        if isFromCurrentUser {
            // Bolla a destra con coda smooth
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius - tailSize))
            
            // Coda curva moderna
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius + tailSize, y: rect.maxY - tailSize),
                control: CGPoint(x: rect.maxX, y: rect.maxY - tailSize)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX - radius + tailSize * 0.3, y: rect.maxY - tailSize * 0.3)
            )
            
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        } else {
            // Bolla a sinistra con coda smooth
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            
            // Coda curva sinistra
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - tailSize),
                control: CGPoint(x: rect.minX + radius * 0.3, y: rect.maxY - tailSize * 0.3)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - radius - tailSize),
                control: CGPoint(x: rect.minX, y: rect.maxY - tailSize)
            )
            
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        }
        
        path.closeSubpath()
        return path
    }
}

// MARK: - Bubble Shape (legacy - manteniamo per compatibilità)

struct BubbleShape: Shape {
    let isFromCurrentUser: Bool
    
    func path(in rect: CGRect) -> Path {
        ModernBubbleShape(isFromCurrentUser: isFromCurrentUser).path(in: rect)
    }
}

// MARK: - Read Receipts View

private struct ReadReceiptsView: View {
    let message: ChatMessage
    
    private var readers: [ChatReadReceipt] {
        message.readReceipts
            .filter { $0.userEmail.lowercased() != message.senderEmail.lowercased() }
            .sorted { $0.readAt < $1.readAt }
    }
    
    var body: some View {
        if !readers.isEmpty {
            HStack(spacing: 6) {
                // Avatar mini dei lettori
                HStack(spacing: -6) {
                    ForEach(readers.prefix(3), id: \.userEmail) { reader in
                        AvatarFromEmailView(
                            email: reader.userEmail,
                            size: 16,
                            fallbackName: reader.userName
                        )
                        .overlay(
                            Circle()
                                .stroke(Color(.controlBackgroundColor), lineWidth: 1)
                        )
                    }
                }
                
                // Mostra "Visualizzato alle HH:mm" per l'ultimo lettore
                if let lastRead = readers.last {
                    let timeStr = lastRead.readAt.formatted(date: .omitted, time: .shortened)
                    
                    if readers.count == 1 {
                        // Usa nome dal profilo se disponibile
                        let displayName = UserDisplayNameHelper.displayName(for: lastRead.userEmail, fallbackName: lastRead.userName)
                        Text("Visualizzato da \(displayName) alle \(timeStr)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        // Più lettori - usa nomi dal profilo
                        let names = readers.prefix(2).map { reader in
                            UserDisplayNameHelper.displayName(for: reader.userEmail, fallbackName: reader.userName)
                        }
                        let namesStr = names.joined(separator: ", ")
                        let extra = readers.count > 2 ? " e altri \(readers.count - 2)" : ""
                        Text("Visualizzato da \(namesStr)\(extra) alle \(timeStr)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Shake Effect

private struct ShakeEffect: GeometryEffect {
    var trigger: Int
    var amplitude: CGFloat = 6
    var shakes: CGFloat = 3
    
    var animatableData: CGFloat {
        get { CGFloat(trigger) }
        set { /* no-op */ }
    }
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amplitude * sin(animatableData * .pi * shakes)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

// MARK: - Attachment Bubble View

struct AttachmentBubbleView: View {
    let attachment: ChatAttachment
    let isCurrentUser: Bool
    
    @StateObject private var chatService = CloudKitChatService.shared
    @State private var isDownloading = false
    @State private var isHovered = false
    
    var body: some View {
        Button {
            downloadAndOpen()
        } label: {
            HStack(spacing: 12) {
                // Icona tipo con background
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isCurrentUser ? Color.white.opacity(0.2) : attachmentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: attachment.type.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isCurrentUser ? .white.opacity(0.9) : attachmentColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(attachment.fileName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isCurrentUser ? .white : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: 180, alignment: .leading)
                    
                    Text(attachment.formattedSize)
                        .font(.system(size: 11))
                        .foregroundColor(isCurrentUser ? .white.opacity(0.75) : .secondary)
                }
                
                Spacer()
                
                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(isCurrentUser ? .white : .accentColor)
                } else {
                    ZStack {
                        Circle()
                            .fill(isCurrentUser ? Color.white.opacity(0.2) : Color.accentColor.opacity(0.12))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: isHovered ? "arrow.down.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(isCurrentUser ? .white.opacity(0.9) : .accentColor)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isCurrentUser ? Color.white.opacity(0.15) : Color(.controlColor).opacity(0.8))
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var attachmentColor: Color {
        switch attachment.type {
        case .image: return .blue
        case .video: return .purple
        case .pdf: return .red
        case .document: return .orange
        case .audio: return .green
        case .other: return .secondary
        }
    }
    
    private func downloadAndOpen() {
        guard !isDownloading else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isDownloading = true
        }
        
        Task {
            do {
                let localURL = try await chatService.downloadAttachment(attachment)
                NSWorkspace.shared.open(localURL)
            } catch {
                print("[Attachment] ❌ Errore download: \(error)")
            }
            
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isDownloading = false
                }
            }
        }
    }
}

// MARK: - New Chat View

struct NewChatView: View {
    let onChatCreated: (ChatRoom) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var chatService = CloudKitChatService.shared
    
    @State private var chatType: ChatType = .direct
    @State private var chatName = ""
    @State private var selectedEmail = ""
    @State private var selectedParticipants: Set<String> = []
    @State private var isCreating = false
    
    enum ChatType: String, CaseIterable {
        case direct = "Chat diretta"
        case group = "Gruppo"
    }
    
    private let currentUserEmail = GoogleAuthService.shared.userEmail ?? ""
    
    // Lista utenti disponibili
    private let availableUsers = [
        ("m.pernozzoli@actsrl.it", "Marco Pernozzoli"),
        ("s.pernozzoli@actsrl.it", "Simone Pernozzoli"),
        ("info@actsrl.it", "ACT Srl"),
        ("segreteria@actsrl.it", "Segreteria")
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Nuova conversazione")
                .font(.title2)
                .fontWeight(.semibold)
            
            // Tipo chat
            Picker("Tipo", selection: $chatType) {
                ForEach(ChatType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            
            if chatType == .direct {
                // Chat diretta
                VStack(alignment: .leading, spacing: 8) {
                    Text("Seleziona utente")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("Utente", selection: $selectedEmail) {
                        Text("Seleziona...").tag("")
                        ForEach(availableUsers.filter { $0.0.lowercased() != currentUserEmail.lowercased() }, id: \.0) { user in
                            Text("\(user.1) (\(user.0))").tag(user.0)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } else {
                // Gruppo
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nome gruppo")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("Es. Team Sinistri Generali", text: $chatName)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Partecipanti")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(availableUsers.filter { $0.0.lowercased() != currentUserEmail.lowercased() }, id: \.0) { user in
                                HStack {
                                    Toggle(isOn: Binding(
                                        get: { selectedParticipants.contains(user.0) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedParticipants.insert(user.0)
                                            } else {
                                                selectedParticipants.remove(user.0)
                                            }
                                        }
                                    )) {
                                        HStack {
                                            Text(user.1)
                                                .font(.subheadline)
                                            Spacer()
                                            Text(user.0)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(height: 120)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            
            Spacer()
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Crea") {
                    createChat()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate || isCreating)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 450, height: chatType == .direct ? 280 : 400)
    }
    
    private var canCreate: Bool {
        if chatType == .direct {
            return !selectedEmail.isEmpty
        } else {
            return !chatName.isEmpty && selectedParticipants.count >= 1
        }
    }
    
    private func createChat() {
        guard canCreate else { return }
        
        isCreating = true
        
        Task {
            do {
                let room: ChatRoom
                
                if chatType == .direct {
                    room = try await chatService.findOrCreateDirectChat(
                        with: selectedEmail,
                        currentUserEmail: currentUserEmail
                    )
                } else {
                    room = try await chatService.createGroup(
                        name: chatName,
                        participants: Array(selectedParticipants)
                    )
                }
                
                await MainActor.run {
                    onChatCreated(room)
                }
            } catch {
                print("[NewChat] ❌ Errore creazione chat: \(error)")
                isCreating = false
            }
        }
    }
}

// MARK: - Hashtag Window Helper

struct ChatDetailViewHelper {
    static func openHashtagWindow(hashtag: ChatHashtag, senderEmail: String, senderName: String) {
        let config = FilterConfig.from(hashtag: hashtag, senderEmail: senderEmail, senderName: senderName)
        
        let windowView = FilteredSinistriWindow(config: config)
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        
        let hostingController = NSHostingController(rootView: windowView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = config.title
        window.setContentSize(NSSize(width: 900, height: 600))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension ChatDetailView {
    func openHashtagWindow(hashtag: ChatHashtag, senderEmail: String, senderName: String) {
        ChatDetailViewHelper.openHashtagWindow(hashtag: hashtag, senderEmail: senderEmail, senderName: senderName)
    }
}

// MARK: - Hover Token Popover

private struct TokenPopoverView: View {
    let token: MentionRichTextEditor.HoverToken
    @Binding var hashtagFilterOverrides: [String: String]
    let onHashtagClick: ((ChatHashtag, String, String) -> Void)?
    let senderEmail: String
    let senderName: String
    
    @State private var hoveredSinistro: Sinistro?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(token.displayText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            switch token.kind {
            case .mention(let value):
                mentionDetails(value: value)
            case .hashtag(let tag):
                hashtagDetails(tag: tag)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
        .shadow(radius: 6)
        .task(id: token.id) {
            await loadSinistroIfNeeded()
        }
    }
    
    private var icon: String {
        switch token.kind {
        case .mention: return "at"
        case .hashtag: return "number"
        }
    }
    
    private var color: Color {
        switch token.kind {
        case .mention: return .blue
        case .hashtag: return .purple
        }
    }
    
    @ViewBuilder
    private func mentionDetails(value: String) -> some View {
        if value.contains("@") {
            Text("Utente: \(value)")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if value.lowercased().hasPrefix("assicurato:") {
            let rif = String(value.dropFirst("assicurato:".count))
            sinistroDetailsBlock(riferimento: rif, label: "Assicurato del sinistro")
        } else {
            sinistroDetailsBlock(riferimento: value, label: "Riferimento sinistro")
        }
    }
    
    @ViewBuilder
    private func hashtagDetails(tag: String) -> some View {
        let description = ChatHashtag.predefinedTags[tag] ?? "Filtro"
        Text(description)
            .font(.caption)
            .foregroundColor(.secondary)
        
        // Opzioni solo per alcuni tag
        if tag == "sinistri" {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ambito")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Picker("Ambito", selection: Binding(
                    get: { hashtagFilterOverrides["sinistri"] ?? "studio" },
                    set: { hashtagFilterOverrides["sinistri"] = $0 }
                )) {
                    Text("Studio").tag("studio")
                    Text("Miei").tag("utente")
                    Text("Destinatario").tag("destinatario")
                }
                .pickerStyle(.segmented)
            }
        }
        
        // Pulsante per visualizzare l'elenco
        if ChatHashtag.predefinedTags.keys.contains(tag) {
            Divider()
            
            Button {
                if case .hashtag(let tagValue) = token.kind {
                    let filter = hashtagFilterOverrides[tag] ?? "utente"
                    let hashtag = ChatHashtag(tag: tagValue, filter: filter)
                    
                    onHashtagClick?(hashtag, senderEmail, senderName)
                }
            } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                    Text("Visualizza elenco")
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
    
    // MARK: - Sinistro details
    
    private func loadSinistroIfNeeded() async {
        guard case .mention(let value) = token.kind else {
            hoveredSinistro = nil
            return
        }
        
        // email -> no sinistro
        if value.contains("@") {
            hoveredSinistro = nil
            return
        }
        
        let rif: String
        if value.lowercased().hasPrefix("assicurato:") {
            rif = String(value.dropFirst("assicurato:".count))
        } else {
            rif = value
        }
        
        let trimmed = rif.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hoveredSinistro = nil
            return
        }
        
        let context = PersistenceController.shared.container.viewContext
        let result: Sinistro? = await context.perform {
            let req = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            req.fetchLimit = 1
            // Ricerca case-insensitive e con CONTAINS per maggiore flessibilità
            req.predicate = NSPredicate(format: "riferimento ==[cd] %@ OR riferimento CONTAINS[cd] %@", trimmed, trimmed)
            req.sortDescriptors = [NSSortDescriptor(keyPath: \Sinistro.dataIncarico, ascending: false)]
            return try? context.fetch(req).first
        }
        
        hoveredSinistro = result
    }
    
    @ViewBuilder
    private func sinistroDetailsBlock(riferimento: String, label: String) -> some View {
        Text("\(label): \(riferimento)")
            .font(.caption)
            .foregroundColor(.secondary)
        
        if let sinistro = hoveredSinistro {
            VStack(alignment: .leading, spacing: 6) {
                // Nome assicurato
                if let nome = sinistro.nomeAssicurato, !nome.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .foregroundColor(.secondary)
                        Text(nome)
                            .font(.caption)
                    }
                }
                
                // Indirizzo
                if let indirizzo = sinistro.indirizzoAssicurato, !indirizzo.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.secondary)
                        Text(indirizzo)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
                
                // Stato
                if let stato = sinistro.stato, !stato.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.fill")
                            .foregroundColor(.secondary)
                        Text(stato)
                            .font(.caption)
                    }
                }
                
                // Contatti (telefono/email)
                let telefoni = sinistro.telefoniAssicuratoArray.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let emails = sinistro.emailAssicuratoArray.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                
                if let tel = telefoni.first ?? sinistro.telefonoAssicurato, !(tel ?? "").isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.fill")
                            .foregroundColor(.secondary)
                        Text(tel ?? "")
                            .font(.caption)
                    }
                }
                
                if let em = emails.first ?? sinistro.emailAssicurato, !(em ?? "").isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.secondary)
                        Text(em ?? "")
                            .font(.caption)
                    }
                }
                
                Divider()
                
                Button {
                    AppState.shared.openSinistro(sinistro, openInNewWindow: true)
                } label: {
                    Label("Apri sinistro", systemImage: "rectangle.portrait.on.rectangle.portrait")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(10)
            .background(Color(.windowBackgroundColor).opacity(0.6))
            .cornerRadius(8)
        } else {
            Text("Sinistro non trovato in archivio")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Popover container (hover-safe)

private struct TokenPopoverContainer: View {
    let token: MentionRichTextEditor.HoverToken
    var hashtagFilterOverrides: Binding<[String: String]>
    @Binding var isPopoverHovered: Bool
    var onHoverChange: (Bool) -> Void
    let onHashtagClick: ((ChatHashtag, String, String) -> Void)?
    let senderEmail: String
    let senderName: String
    
    var body: some View {
        // Area di tolleranza: 18px intorno, così non sparisce al volo
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .frame(width: 1, height: 1)
                .padding(18)
            
            TokenPopoverView(
                token: token,
                hashtagFilterOverrides: hashtagFilterOverrides,
                onHashtagClick: { hashtag, _, _ in
                    onHashtagClick?(hashtag, senderEmail, senderName)
                },
                senderEmail: senderEmail,
                senderName: senderName
            )
        }
        .onHover { hovering in
            isPopoverHovered = hovering
            onHoverChange(hovering)
        }
    }
}

// MARK: - Typing Dots Animation

private struct TypingDotsView: View {
    @State private var animationOffset: Int = 0
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
                    .opacity(animationOffset == index ? 1.0 : 0.4)
                    .scaleEffect(animationOffset == index ? 1.2 : 1.0)
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                animationOffset = (animationOffset + 1) % 3
            }
        }
    }
}

// MARK: - Pending Message Bubble

private struct PendingMessageBubble: View {
    let message: PendingMessage
    let uploadProgress: Double
    @State private var appeared = false
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .bottom, spacing: 10) {
                Spacer(minLength: 60)
                
                VStack(alignment: .trailing, spacing: 3) {
                    // Contenuto messaggio
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // Allegati se presenti
                            if !message.attachments.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(message.attachments, id: \.absoluteString) { url in
                                        HStack(spacing: 8) {
                                            Image(systemName: "doc.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            Text(url.lastPathComponent)
                                                .font(.system(size: 12))
                                                .foregroundColor(.white.opacity(0.9))
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                            
                            // Testo
                            if !message.content.isEmpty {
                                Text(message.content)
                                    .font(.system(size: 15))
                                    .foregroundColor(.white.opacity(0.95))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            // Mini progress bar elegante e integrata
                            if uploadProgress > 0 && uploadProgress < 1.0 {
                                VStack(spacing: 6) {
                                    Divider()
                                        .background(Color.white.opacity(0.2))
                                    
                                    HStack(spacing: 8) {
                                        // Spinner minimalista
                                        ZStack {
                                            Circle()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                                                .frame(width: 14, height: 14)
                                            
                                            Circle()
                                                .trim(from: 0, to: 0.7)
                                                .stroke(Color.white, lineWidth: 1.5)
                                                .frame(width: 14, height: 14)
                                                .rotationEffect(.degrees(-90))
                                                .rotationEffect(.degrees(appeared ? 360 : 0))
                                                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: appeared)
                                        }
                                        
                                        // Progress bar ultra-sottile
                                        GeometryReader { geometry in
                                            ZStack(alignment: .leading) {
                                                // Background
                                                Capsule()
                                                    .fill(Color.white.opacity(0.25))
                                                    .frame(height: 2)
                                                
                                                // Progress con shimmer effect
                                                Capsule()
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [
                                                                Color.white.opacity(0.8),
                                                                Color.white,
                                                                Color.white.opacity(0.8)
                                                            ],
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                                    .frame(width: max(20, geometry.size.width * uploadProgress), height: 2)
                                                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: uploadProgress)
                                            }
                                        }
                                        .frame(height: 2)
                                        
                                        // Percentuale
                                        Text("\(Int(uploadProgress * 100))%")
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundColor(.white.opacity(0.9))
                                            .monospacedDigit()
                                            .frame(minWidth: 32, alignment: .trailing)
                                    }
                                    .padding(.top, 2)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.7),
                                    Color.accentColor.opacity(0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(ModernBubbleShape(isFromCurrentUser: true))
                        .shadow(
                            color: uploadProgress >= 1.0 
                                ? Color.green.opacity(0.3)
                                : Color.accentColor.opacity(uploadProgress > 0 && uploadProgress < 1.0 ? 0.3 : 0.2),
                            radius: uploadProgress >= 1.0 ? 8 : 6,
                            y: 3
                        )
                        .scaleEffect(uploadProgress >= 1.0 ? 1.02 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: uploadProgress >= 1.0)
                        
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: 500)
                    
                    // Footer
                    HStack(spacing: 5) {
                        Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                        
                        // Icona stato
                        if uploadProgress >= 1.0 {
                            // Completato
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            // In invio
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: uploadProgress >= 1.0)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.9, anchor: .bottomTrailing)
        .offset(y: appeared ? 0 : 15)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }
}

// MARK: - Typing Indicator Bubble

private struct TypingIndicatorBubble: View {
    let users: [CloudKitUserDirectoryService.CloudUser]
    @State private var animationOffset: Int = 0
    
    var body: some View {
        HStack(spacing: 8) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                
                if let firstUser = users.first {
                    Text(firstUser.displayName.prefix(1).uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            
            // Bolla typing
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 7, height: 7)
                        .scaleEffect(animationOffset == index ? 1.3 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                            value: animationOffset
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.windowBackgroundColor).opacity(0.95))
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            )
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            animationOffset = (animationOffset + 1) % 3
        }
    }
}

// MARK: - Attachment Picker Popover (Smart File Selection)

struct AttachmentPickerPopover: View {
    let roomId: String
    let onFileSelected: ([URL]) -> Void
    let onPickFiles: () -> Void
    
    @State private var searchText = ""
    @State private var recentFiles: [RecentFile] = []
    
    struct RecentFile: Identifiable {
        let id = UUID()
        let url: URL
        let name: String
        let sinistroRiferimento: String?
        let lastAccessDate: Date
        let fileType: String
        
        var icon: String {
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "pdf": return "doc.fill"
            case "jpg", "jpeg", "png", "heic": return "photo.fill"
            case "doc", "docx": return "doc.text.fill"
            case "xls", "xlsx": return "tablecells.fill"
            case "zip": return "archivebox.fill"
            default: return "doc"
            }
        }
        
        var iconColor: Color {
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "pdf": return .red
            case "jpg", "jpeg", "png", "heic": return .blue
            case "doc", "docx": return .indigo
            case "xls", "xlsx": return .green
            case "zip": return .orange
            default: return .secondary
            }
        }
    }
    
    var filteredFiles: [RecentFile] {
        if searchText.isEmpty {
            return recentFiles
        }
        return recentFiles.filter { file in
            file.name.localizedCaseInsensitiveContains(searchText) ||
            (file.sinistroRiferimento?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "paperclip")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
                
                Text("Allega File")
                    .font(.system(size: 15, weight: .semibold))
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                TextField("Cerca file sinistri...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            // File recenti
            ScrollView {
                VStack(spacing: 0) {
                    if !filteredFiles.isEmpty {
                        // Sezione file recenti
                        VStack(alignment: .leading, spacing: 4) {
                            Text(searchText.isEmpty ? "File Recenti" : "Risultati")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                            
                            ForEach(filteredFiles.prefix(8)) { file in
                                RecentFileRow(file: file) {
                                    onFileSelected([file.url])
                                }
                            }
                        }
                    } else if searchText.isEmpty {
                        // Empty state
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.5))
                            
                            Text("Nessun file recente")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Text("Cerca tra i file dei sinistri\no seleziona \"Allega altri file\"")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        // No results
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary.opacity(0.5))
                            
                            Text("Nessun risultato")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                }
            }
            .frame(minHeight: 200, maxHeight: 320)
            
            Divider()
            
            // Footer actions
            VStack(spacing: 8) {
                // GIF e meme (placeholder)
                Button {
                    // TODO: Implementare GIF picker
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.purple)
                        
                        Text("GIF e meme")
                            .font(.system(size: 13, weight: .medium))
                        
                        Spacer()
                        
                        Text("In arrivo...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(6)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(true)
                .opacity(0.6)
                
                Divider()
                    .padding(.horizontal, 12)
                
                // Allega altri file
                Button {
                    onPickFiles()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.accentColor)
                        
                        Text("Allega altri file")
                            .font(.system(size: 13, weight: .semibold))
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
        }
        .frame(width: 360)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            loadRecentFiles()
        }
    }
    
    private func loadRecentFiles() {
        // TODO: Implementare caricamento file recenti da FileService
        // Per ora placeholder con file fittizi
        recentFiles = []
    }
}

// MARK: - Recent File Row

struct RecentFileRow: View {
    let file: AttachmentPickerPopover.RecentFile
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(file.iconColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: file.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(file.iconColor)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        if let riferimento = file.sinistroRiferimento {
                            HStack(spacing: 3) {
                                Image(systemName: "link")
                                    .font(.system(size: 9))
                                Text(riferimento)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.orange)
                            
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        
                        Text(file.lastAccessDate, style: .relative)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(isHovered ? .accentColor : .secondary.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isHovered ? Color.accentColor.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    MessagesView()
}
