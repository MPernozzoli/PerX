import SwiftUI

/// Vista per inviare un nuovo messaggio WhatsApp a un numero specifico
/// Design moderno in stile iMessage - Mostra anche cronologia messaggi se esiste
struct WhatsAppNewChatView: View {
    let phoneNumber: String
    let prefilledMessage: String
    let sinistroRiferimento: String?
    let sinistro: Sinistro?
    
    @ObservedObject private var service = WhatsAppService.shared
    @StateObject private var fileTagManager = FileTagManager.shared
    private let templateService = WhatsAppMessageTemplateService.shared
    private let fileService = FileService.shared
    
    @State private var messageText: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var messageSent = false
    @State private var selectedMediaURL: URL? = nil
    @State private var showingTemplatePicker = false
    @State private var showingFileSelector = false
    @State private var emptySendShake: Int = 0
    @State private var isAlwaysOnTop = false
    
    // Stato verifica numero
    @State private var isCheckingNumber = false
    @State private var isNumberRegistered: Bool? = nil
    
    // Chat esistente e messaggi
    @State private var existingChat: WhatsAppChat? = nil
    @State private var messages: [WhatsAppMessage] = []
    @State private var isLoadingMessages = false
    
    // Contatto info
    @State private var contactName: String? = nil
    @State private var contactProfilePic: String? = nil
    
    // Window identifier per gestire on-top
    private var windowIdentifier: String {
        let cleanNumber = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        return "whatsapp-chat-\(cleanNumber)"
    }
    
    init(phoneNumber: String, prefilledMessage: String = "", sinistroRiferimento: String? = nil, sinistro: Sinistro? = nil) {
        self.phoneNumber = phoneNumber
        self.prefilledMessage = prefilledMessage
        self.sinistroRiferimento = sinistroRiferimento
        self.sinistro = sinistro
        _messageText = State(initialValue: prefilledMessage)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            LinearGradient(
                colors: [
                    Color(.textBackgroundColor),
                    Color(.textBackgroundColor).opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            
            VStack(spacing: 0) {
                // Header moderno
                modernHeader
                
                // Contenuto
                if !service.isConnected {
                    notConnectedView
                } else if isCheckingNumber || isLoadingMessages {
                    loadingView
                } else if isNumberRegistered == false {
                    numberNotRegisteredView
                } else if messageSent {
                    messageSentView
                } else {
                    // Area messaggi
                    messagesListView
                }
            }
            
            // Composer floating (solo se pronto a comporre)
            if service.isConnected && isNumberRegistered != false && !messageSent && !isCheckingNumber && !isLoadingMessages {
                floatingComposer
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .frame(minWidth: 450, minHeight: 500)
        .onAppear {
            if service.isConnected {
                loadChatHistory()
            }
        }
        .onChange(of: service.isConnected) { _, newValue in
            if newValue {
                loadChatHistory()
            }
        }
        .sheet(isPresented: $showingFileSelector) {
            WhatsAppFileSelectorView(
                sinistro: sinistro,
                onFileSelected: { url in
                    selectedMediaURL = url
                    showingFileSelector = false
                }
            )
        }
    }
    
    // MARK: - Load Chat History
    
    private func loadChatHistory() {
        isCheckingNumber = true
        isLoadingMessages = true
        
        Task {
            do {
                // Prima verifica il numero
                var cleanNumber = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                if !cleanNumber.hasPrefix("39") && cleanNumber.count <= 10 {
                    cleanNumber = "39\(cleanNumber)"
                }
                
                let registered = try await service.checkNumberRegistered(phoneNumber: cleanNumber)
                
                await MainActor.run {
                    isNumberRegistered = registered
                    isCheckingNumber = false
                }
                
                guard registered else {
                    await MainActor.run { isLoadingMessages = false }
                    return
                }
                
                // Cerca chat esistente
                let chats = try await service.fetchChats()
                
                // Trova chat che corrisponde al numero
                let foundChat = chats.first { chat in
                    guard let chatPhone = chat.phoneNumber else { return false }
                    // Normalizza entrambi i numeri per il confronto
                    let normalizedChatPhone = chatPhone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    return normalizedChatPhone == cleanNumber || 
                           normalizedChatPhone.hasSuffix(cleanNumber.suffix(10)) ||
                           cleanNumber.hasSuffix(normalizedChatPhone.suffix(10))
                }
                
                if let chat = foundChat {
                    // Carica messaggi della chat
                    let fetchedMessages = try await service.fetchMessages(chatId: chat.id, limit: 100)
                    
                    await MainActor.run {
                        existingChat = chat
                        messages = fetchedMessages.sorted { $0.timestamp < $1.timestamp }
                        contactName = chat.name
                        contactProfilePic = chat.profilePicture
                        isLoadingMessages = false
                    }
                    
                    // Carica foto profilo
                    if let profilePic = try? await service.getProfilePicUrl(contactId: chat.id) {
                        await MainActor.run {
                            contactProfilePic = profilePic
                        }
                    }
                } else {
                    await MainActor.run {
                        isLoadingMessages = false
                    }
                }
                
            } catch {
                await MainActor.run {
                    isCheckingNumber = false
                    isLoadingMessages = false
                    isNumberRegistered = true // Permetti di procedere comunque
                }
            }
        }
    }
    
    // MARK: - Modern Header
    
    private var modernHeader: some View {
        ZStack {
            // Centro: Avatar + Info
            VStack(spacing: 8) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.green.opacity(0.7), Color.green.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .shadow(color: .green.opacity(0.3), radius: 8, y: 4)
                    
                    if let profilePic = contactProfilePic, !profilePic.isEmpty {
                        AsyncImage(url: URL(string: profilePic)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                Image(systemName: "person.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                
                // Nome/Numero
                VStack(spacing: 4) {
                    Text(contactName ?? formattedPhoneNumber)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if contactName != nil {
                        Text(formattedPhoneNumber)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Pills
                HStack(spacing: 6) {
                    if let rif = sinistroRiferimento {
                        headerPill(text: rif, icon: "folder.fill", color: .orange)
                    }
                    
                    headerPill(text: "Assicurato", icon: "person.fill", color: .blue)
                    
                    // Status connessione
                    headerPill(
                        text: service.isConnected ? "Connesso" : "Offline",
                        icon: service.isConnected ? "checkmark.circle.fill" : "wifi.slash",
                        color: service.isConnected ? .green : .red
                    )
                    
                    // Indicatore messaggi esistenti
                    if !messages.isEmpty {
                        headerPill(text: "\(messages.count) msg", icon: "bubble.left.fill", color: .purple)
                    }
                }
            }
            .padding(.top, 8)
            
            // Pulsanti a destra: Pin + Chiudi
            HStack {
                Spacer()
                
                HStack(spacing: 8) {
                    // Pulsante refresh
                    Button {
                        loadChatHistory()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.6))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Aggiorna messaggi")
                    
                    // Pulsante On Top
                    Button {
                        isAlwaysOnTop.toggle()
                        WindowManager.shared.updateAlwaysOnTop(identifier: windowIdentifier, value: isAlwaysOnTop)
                    } label: {
                        Image(systemName: isAlwaysOnTop ? "pin.fill" : "pin")
                            .font(.system(size: 16))
                            .foregroundColor(isAlwaysOnTop ? .blue : .secondary.opacity(0.6))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(isAlwaysOnTop ? "Disattiva sempre in primo piano" : "Attiva sempre in primo piano")
                    
                    // Pulsante Chiudi
                    Button {
                        NSApp.keyWindow?.close()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.6))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.trailing, 12)
            }
        }
        .padding(.vertical, 16)
    }
    
    private func headerPill(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Messages List View
    
    private var messagesListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if messages.isEmpty {
                        // Empty state
                        VStack(spacing: 20) {
                            Spacer()
                            
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.green.opacity(0.15), Color.green.opacity(0.05)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                
                                Image(systemName: "message.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.green.opacity(0.6))
                            }
                            
                            VStack(spacing: 8) {
                                Text("Inizia la conversazione")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                
                                Text("Scrivi un messaggio per iniziare a chattare con questo contatto")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        // Mostra messaggi
                        ForEach(messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.85, anchor: message.isFromMe ? .bottomTrailing : .bottomLeading)
                                        .combined(with: .opacity)
                                        .combined(with: .move(edge: .bottom)),
                                    removal: .scale(scale: 0.9).combined(with: .opacity)
                                ))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 140) // Spazio per floating composer
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = messages.last {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
    
    // MARK: - Message Bubble (simplified version)
    
    private struct MessageBubbleView: View {
        let message: WhatsAppMessage
        
        var body: some View {
            HStack {
                if message.isFromMe { Spacer(minLength: 60) }
                
                VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
                    // Contenuto messaggio
                    if !message.body.isEmpty {
                        Text(message.body)
                            .font(.system(size: 14))
                            .foregroundColor(message.isFromMe ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(message.isFromMe ? Color.green : Color(.controlBackgroundColor))
                            )
                    }
                    
                    // Media se presente
                    if message.hasMedia {
                        HStack(spacing: 4) {
                            Image(systemName: mediaIcon(for: message.type))
                                .font(.caption)
                            Text(message.mediaFilename ?? message.type.rawValue.capitalized)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.controlBackgroundColor))
                        )
                    }
                    
                    // Timestamp e status
                    HStack(spacing: 4) {
                        Text(formatTime(message.timestamp))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        if message.isFromMe {
                            Image(systemName: statusIcon(for: message))
                                .font(.system(size: 10))
                                .foregroundColor(message.isReadByRecipient ? .blue : .secondary)
                        }
                    }
                }
                
                if !message.isFromMe { Spacer(minLength: 60) }
            }
        }
        
        private func mediaIcon(for type: MessageType) -> String {
            switch type {
            case .image: return "photo"
            case .video: return "video"
            case .audio, .ptt: return "waveform"
            case .document: return "doc"
            case .sticker: return "face.smiling"
            case .location: return "location"
            case .contact: return "person"
            default: return "doc"
            }
        }
        
        private func statusIcon(for message: WhatsAppMessage) -> String {
            if message.isReadByRecipient { return "checkmark.circle.fill" }
            if message.isDelivered { return "checkmark.circle" }
            if message.isSent { return "checkmark" }
            return "clock"
        }
        
        private func formatTime(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
    
    // MARK: - Floating Composer
    
    private var floatingComposer: some View {
        VStack(spacing: 8) {
            // Anteprima allegato
            if let mediaURL = selectedMediaURL {
                attachmentPreview(url: mediaURL)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Errore
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button {
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .cornerRadius(10)
            }
            
            HStack(spacing: 10) {
                // Pulsante allega
                Button {
                    showingFileSelector = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.green)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
                
                // Pulsante template
                Button {
                    showingTemplatePicker = true
                } label: {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(width: 32, height: 32)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showingTemplatePicker) {
                    templatePickerPopover
                }
                
                // Campo testo
                TextField("Scrivi un messaggio...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(18)
                    .modifier(ShakeEffectModifier(trigger: emptySendShake))
                
                // Pulsante invio
                Button {
                    if canSend { sendMessage() }
                } label: {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(canSend ? Color.green : Color.secondary.opacity(0.3))
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                }
                .buttonStyle(.borderless)
                .disabled(!canSend || isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(.controlBackgroundColor).opacity(0.95))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            )
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selectedMediaURL != nil)
    }
    
    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedMediaURL != nil
    }
    
    // MARK: - Template Picker
    
    private var templatePickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Messaggi predefiniti")
                    .font(.headline)
                Spacer()
                Button { showingTemplatePicker = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(WhatsAppMessageTemplateService.TemplateType.allCases) { template in
                        Button {
                            applyTemplate(template)
                            showingTemplatePicker = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: template.iconName)
                                    .font(.system(size: 18))
                                    .foregroundColor(.blue)
                                    .frame(width: 32)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    
                                    Text(template.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            
            if sinistro != nil {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Sinistro collegato")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
            }
        }
        .frame(width: 320, height: 380)
    }
    
    private func applyTemplate(_ template: WhatsAppMessageTemplateService.TemplateType) {
        let message = templateService.generateMessage(template: template, sinistro: sinistro)
        messageText = message
        
        // Cerca allegato con tag richiesto
        if let requiredTagId = template.requiredTag,
           let sinistro = sinistro,
           let tag = FileTagManager.FileTag.availableTags.first(where: { $0.id == requiredTagId }),
           let sinistroPath = fileService.getSinistroPath(riferimento: sinistro.riferimento ?? "") {
            let filesWithTag = fileTagManager.getFilesWithTag(tag)
            for filePath in filesWithTag {
                if filePath.hasPrefix(sinistroPath) {
                    selectedMediaURL = URL(fileURLWithPath: filePath)
                    break
                }
            }
        }
    }
    
    // MARK: - Attachment Preview
    
    private func attachmentPreview(url: URL) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: iconForFile(url))
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button {
                withAnimation { selectedMediaURL = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.controlBackgroundColor))
        )
    }
    
    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.text.fill"
        case "jpg", "jpeg", "png", "heic", "gif": return "photo.fill"
        case "mp4", "mov", "m4v": return "video.fill"
        default: return "doc.fill"
        }
    }
    
    // MARK: - Other Views
    
    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("WhatsApp non connesso")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Connetti WhatsApp per inviare messaggi.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Connetti") {
                Task { await service.connect() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            
            Spacer()
        }
        .padding()
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text(isCheckingNumber ? "Verifica numero..." : "Caricamento messaggi...")
                .font(.title3)
                .fontWeight(.medium)
            Spacer()
        }
    }
    
    private var numberNotRegisteredView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Numero non su WhatsApp")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Il numero \(formattedPhoneNumber) non risulta registrato su WhatsApp.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Button("Chiudi") {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.bordered)
                
                Button("Prova comunque") {
                    isNumberRegistered = true
                }
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var messageSentView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("Messaggio inviato!")
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack(spacing: 16) {
                Button("Invia un altro") {
                    messageText = ""
                    selectedMediaURL = nil
                    messageSent = false
                    // Ricarica messaggi per vedere quello appena inviato
                    loadChatHistory()
                }
                .buttonStyle(.bordered)
                
                Button("Chiudi") {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private var formattedPhoneNumber: String {
        let clean = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if clean.hasPrefix("39") {
            return "+\(clean)"
        } else if !clean.isEmpty {
            return "+39\(clean)"
        }
        return phoneNumber
    }
    
    private func sendMessage() {
        guard canSend else { return }
        
        isSending = true
        errorMessage = nil
        
        Task {
            do {
                var cleanNumber = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                if !cleanNumber.hasPrefix("39") && cleanNumber.count <= 10 {
                    cleanNumber = "39\(cleanNumber)"
                }
                
                // Se abbiamo una chat esistente, usiamo il suo ID
                let destination = existingChat?.id ?? cleanNumber
                
                _ = try await service.sendMessage(
                    to: destination,
                    body: messageText.trimmingCharacters(in: .whitespacesAndNewlines),
                    mediaUrl: selectedMediaURL?.path
                )
                
                await MainActor.run {
                    isSending = false
                    messageSent = true
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
