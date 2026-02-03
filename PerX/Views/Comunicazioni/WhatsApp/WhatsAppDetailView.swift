import SwiftUI
import UniformTypeIdentifiers
import CoreData

@MainActor

struct WhatsAppDetailView: View {
    @ObservedObject var viewModel: WhatsAppViewModel
    let chat: WhatsAppChat
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var messageText = ""
    @State private var selectedMediaURL: URL?
    @FocusState private var isMessageFieldFocused: Bool
    @State private var showingAssociationPopover = false
    @State private var suggestedSinistri: [Sinistro] = []
    @State private var showingTemplatePicker = false
    @State private var showingFileSelector = false
    @State private var showingCreateTask = false
    @State private var showingTaskPopover = false
    @State private var showSchedulePicker = false
    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var isScheduled = false
    
    // Messaggi programmati
    @State private var pendingScheduledMessages: [ScheduledWhatsAppService.ScheduledWhatsApp] = []
    @State private var editingScheduledMessage: ScheduledWhatsAppService.ScheduledWhatsApp? = nil
    
    // Smart Scheduling
    @State private var showSmartSchedulePrompt = false
    @State private var smartScheduleReason: SmartScheduleService.ScheduleReason = .afterHours
    @State private var smartScheduleSuggestedDate = Date()
    @StateObject private var smartScheduleService = SmartScheduleService.shared
    
    // Design moderno
    @State private var isSending = false
    @State private var emptySendShake: Int = 0
    @State private var screenshotFeedback: String? = nil
    
    private let templateService = WhatsAppMessageTemplateService.shared
    @StateObject private var fileTagManager = FileTagManager.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var messageTagManager = WhatsAppMessageTagManager.shared
    private let fileService = FileService.shared
    
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
            .allowsHitTesting(false)
            
            VStack(spacing: 0) {
                // Header sinistro (se associato)
                if let sinistro = viewModel.selectedChatAssociatedSinistri.first {
                    linkedSinistroBar(sinistro: sinistro)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Header chat con design moderno
                modernChatHeader
                
                // Lista messaggi
                modernMessagesList
            }
            
            // Composer e messaggi programmati
            VStack(spacing: 8) {
                // Messaggi programmati in attesa
                ForEach(pendingScheduledMessagesForChat) { scheduled in
                    scheduledMessageRow(scheduled)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Composer floating con glassmorphism
                floatingComposer
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .scaleEffect(isSending ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isSending)
        }
        .onAppear {
            // Setta questa chat come attiva (disabilita notifiche per questa chat)
            WhatsAppNotificationService.shared.activeChatId = chat.id
            
            viewModel.loadAssociatedSinistri(for: chat.id, context: viewContext)
            loadScheduledMessages()
            Task {
                if viewModel.selectedChatId != chat.id {
                    viewModel.selectChat(chat.id)
                } else if viewModel.selectedChatMessages.isEmpty {
                    await viewModel.fetchMessages(for: chat.id)
                }
            }
        }
        .onDisappear {
            // Rimuovi chat attiva quando chiudi
            if WhatsAppNotificationService.shared.activeChatId == chat.id {
                WhatsAppNotificationService.shared.activeChatId = nil
            }
        }
        .onChange(of: chat.id) { oldValue, newValue in
            viewModel.loadAssociatedSinistri(for: newValue, context: viewContext)
            Task {
                if viewModel.selectedChatId != newValue {
                    viewModel.selectChat(newValue)
                } else if viewModel.selectedChatMessages.isEmpty {
                    await viewModel.fetchMessages(for: newValue)
                }
            }
        }
        .popover(isPresented: $showingAssociationPopover, attachmentAnchor: .point(.top)) {
            WhatsAppAssociationPopover(
                chat: chat,
                messages: viewModel.selectedChatMessages,
                suggestedSinistri: suggestedSinistri,
                onAssociate: { sinistri in
                    viewModel.associateChatManually(chatId: chat.id, sinistri: sinistri, context: viewContext)
                }
            )
        }
        .sheet(isPresented: $showingFileSelector) {
            WhatsAppFileSelectorView(sinistro: viewModel.selectedChatAssociatedSinistri.first) { url in
                selectedMediaURL = url
            }
            .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showingCreateTask) {
            CreateTaskView(
                email: nil,
                whatsAppChat: chat,
                whatsAppMessage: viewModel.selectedChatMessages.last
            )
        }
    }
    
    // MARK: - Modern Chat Header (stile iMessage)
    
    private var modernChatHeader: some View {
        HStack(alignment: .top, spacing: 0) {
            // Controlli sinistra
            HStack(spacing: 6) {
                // Refresh
                GlassmorphicIconButton(icon: "arrow.clockwise", size: 32) {
                    Task {
                        await viewModel.fetchMessages(for: chat.id)
                    }
                }
                .help("Aggiorna messaggi")
                
                // Task
                GlassmorphicIconButton(icon: "checklist", size: 32) {
                    showingTaskPopover = true
                }
                .help("Crea task")
                .popover(isPresented: $showingTaskPopover) {
                    TaskPopoverView(
                        email: nil,
                        whatsAppChat: chat,
                        whatsAppMessage: viewModel.selectedChatMessages.last,
                        sinistro: viewModel.selectedChatAssociatedSinistri.first
                    )
                    .environment(\.managedObjectContext, viewContext)
                }
            }
            .padding(.leading, 12)
            .padding(.top, 20)
            
            Spacer()
            
            // Centro: Avatar + Pills
            VStack(spacing: 8) {
                // Avatar con foto profilo
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
                    
                    if let profilePicture = chat.profilePicture, !profilePicture.isEmpty {
                        AsyncImage(url: URL(string: profilePicture)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure:
                                Image(systemName: chat.isGroup ? "person.2.fill" : "person.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                            case .empty:
                                ProgressView()
                                    .scaleEffect(0.6)
                            @unknown default:
                                Image(systemName: "person.fill")
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: chat.isGroup ? "person.2.fill" : "person.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                
                // Nome chat
                Button {
                    // Navigazione a dettagli chat (TODO)
                } label: {
                    HStack(spacing: 4) {
                        Text(chat.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                
                // Pills con info
                HStack(spacing: 6) {
                    // Riferimento sinistro
                    if let sinistro = viewModel.selectedChatAssociatedSinistri.first {
                        headerPill(
                            text: sinistro.riferimentoVisualizzato,
                            icon: "folder.fill",
                            color: .orange
                        )
                    }
                    
                    // Tipo interlocutore (TODO: da rubrica)
                    headerPill(
                        text: chat.isGroup ? "Gruppo" : "Assicurato",
                        icon: chat.isGroup ? "person.2.fill" : "person.fill",
                        color: .blue
                    )
                }
            }
            .padding(.top, 4)
            
            Spacer()
            
            // Controlli destra
            HStack(spacing: 6) {
                // Associa/Modifica sinistro
                GlassmorphicIconButton(
                    icon: viewModel.selectedChatAssociatedSinistri.isEmpty ? "link.badge.plus" : "link",
                    isActive: !viewModel.selectedChatAssociatedSinistri.isEmpty,
                    size: 32
                ) {
                    let suggested = WhatsAppAssociationService.shared.checkChatAssociation(
                        chat,
                        messages: viewModel.selectedChatMessages,
                        context: viewContext
                    )
                    suggestedSinistri = suggested
                    showingAssociationPopover = true
                }
                .help(viewModel.selectedChatAssociatedSinistri.isEmpty ? "Associa a sinistro" : "Modifica associazione")
                
                // Screenshot conversazione
                GlassmorphicIconButton(icon: "camera.viewfinder", size: 32) {
                    captureConversationScreenshot()
                }
                .help("Salva screenshot conversazione")
                
                // Menu azioni
                Menu {
                    Button {
                        reconnect()
                    } label: {
                        Label("Riconnetti WhatsApp", systemImage: "arrow.clockwise")
                    }
                    
                    Divider()
                    
                    Button {
                        // TODO: Info chat
                    } label: {
                        Label("Info chat", systemImage: "info.circle")
                    }
                    
                    Button {
                        // TODO: Archivia
                    } label: {
                        Label("Archivia", systemImage: "archivebox")
                    }
                    
                    if viewModel.selectedChatAssociatedSinistri.first != nil {
                        Button {
                            WhatsAppAssociationService.shared.disassociateChat(chatId: chat.id, context: viewContext)
                            // Ricarica le associazioni
                            viewModel.loadAssociatedSinistri(for: chat.id, context: viewContext)
                        } label: {
                            Label("Scollega sinistro", systemImage: "link.badge.minus")
                        }
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        disconnect()
                    } label: {
                        Label("Disconnetti WhatsApp", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.secondary.opacity(0.1))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
            }
            .padding(.trailing, 12)
            .padding(.top, 20)
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Header Pill
    
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
    
    // MARK: - Screenshot Conversazione
    
    private func captureConversationScreenshot() {
        // Trova la finestra corrente
        guard let window = NSApp.keyWindow else {
            showScreenshotFeedback("Impossibile catturare la finestra")
            return
        }
        
        // Cattura screenshot della content view (area messaggi)
        guard let contentView = window.contentView else {
            showScreenshotFeedback("Impossibile catturare il contenuto")
            return
        }
        
        // Crea immagine dalla vista
        let bounds = contentView.bounds
        guard let bitmapRep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            showScreenshotFeedback("Errore creazione immagine")
            return
        }
        
        contentView.cacheDisplay(in: bounds, to: bitmapRep)
        
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmapRep)
        
        // Converti in PNG
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            showScreenshotFeedback("Errore conversione immagine")
            return
        }
        
        // Genera nome file con timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "AccettazioneVerbale_\(chat.name.replacingOccurrences(of: " ", with: "_"))_\(timestamp).png"
        
        // Determina percorso di salvataggio
        var savedPath: String? = nil
        
        if let sinistro = viewModel.selectedChatAssociatedSinistri.first,
           let riferimento = sinistro.riferimento,
           let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) {
            // Salva nella cartella del sinistro
            let fileURL = URL(fileURLWithPath: sinistroPath).appendingPathComponent(fileName)
            
            do {
                try pngData.write(to: fileURL)
                savedPath = fileURL.path
                
                // Applica tag "allegati_atto" con sottotipo "accettazione"
                if let allegatiAttoTag = FileTagManager.FileTag.availableTags.first(where: { $0.id == "allegati_atto" }) {
                    fileTagManager.addTag(allegatiAttoTag, toFile: fileURL.path)
                    fileTagManager.setAllegatiAttoSottotipo("accettazione", forFile: fileURL.path, tagId: allegatiAttoTag.id)
                }
                
                showScreenshotFeedback("Screenshot salvato in \(sinistro.riferimentoVisualizzato)")
                
            } catch {
                showScreenshotFeedback("Errore salvataggio: \(error.localizedDescription)")
            }
        } else {
            // Nessun sinistro associato - chiedi dove salvare
            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = fileName
            savePanel.allowedContentTypes = [.png]
            savePanel.canCreateDirectories = true
            
            if savePanel.runModal() == .OK, let url = savePanel.url {
                do {
                    try pngData.write(to: url)
                    savedPath = url.path
                    showScreenshotFeedback("Screenshot salvato")
                } catch {
                    showScreenshotFeedback("Errore salvataggio: \(error.localizedDescription)")
                }
            }
        }
        
        // Apri il file nel Finder se salvato
        if let path = savedPath {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        }
    }
    
    private func showScreenshotFeedback(_ message: String) {
        screenshotFeedback = message
        
        // Nascondi dopo 3 secondi
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if screenshotFeedback == message {
                screenshotFeedback = nil
            }
        }
    }
    
    // MARK: - Modern Messages List
    
    private var modernMessagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.selectedChatMessages.isEmpty {
                        VStack(spacing: 16) {
                            Spacer(minLength: 100)
                            
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.green.opacity(0.15),
                                                Color.green.opacity(0.08)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 80, height: 80)
                                    .blur(radius: 10)
                                
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 64, height: 64)
                                
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.green, .green.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            
                            Text("Nessun messaggio")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("I messaggi appariranno qui")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ForEach(viewModel.selectedChatMessages) { message in
                            ModernWhatsAppMessageBubble(
                                message: message,
                                chat: chat,
                                onTagMessage: { msg in
                                    // Tag action handled by context menu
                                }
                            )
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.85, anchor: message.isSent ? .bottomTrailing : .bottomLeading)
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
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.selectedChatMessages.count)
            }
            .onAppear {
                if let lastMessage = viewModel.selectedChatMessages.last {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: viewModel.selectedChatMessages.count) { oldCount, newCount in
                if newCount > oldCount, let lastMessage = viewModel.selectedChatMessages.last {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Floating Composer (stile iMessage/iOS 26)
    
    private var floatingComposer: some View {
        VStack(spacing: 8) {
            // Anteprima allegato
            if let mediaURL = selectedMediaURL {
                attachmentPreview(url: mediaURL)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                .help("Allega file")
                
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
                .help("Messaggi predefiniti")
                .popover(isPresented: $showingTemplatePicker) {
                    templatePickerPopover
                }
                
                // Campo testo compatto
                TextField("Scrivi un messaggio...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isMessageFieldFocused)
                    .lineLimit(1...5)
                    .onSubmit {
                        if canSend { attemptSendMessage() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(18)
                    .modifier(ShakeEffectModifier(trigger: emptySendShake))
                
                // Pulsante invio
                Button {
                    if canSend { attemptSendMessage() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            canSend
                                ? Color.green
                                : Color.secondary.opacity(0.3)
                        )
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
                .disabled(!canSend)
                .animation(.easeInOut(duration: 0.2), value: canSend)
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
        .sheet(isPresented: $showSchedulePicker) {
            WhatsAppSchedulePickerView(
                scheduledDate: $scheduledDate,
                onConfirm: {
                    showSchedulePicker = false
                    scheduleMessage()
                },
                onCancel: {
                    showSchedulePicker = false
                }
            )
        }
        .sheet(isPresented: $showSmartSchedulePrompt) {
            SmartSchedulePromptView(
                reason: smartScheduleReason,
                suggestedDate: $smartScheduleSuggestedDate,
                contextId: viewModel.selectedChatAssociatedSinistri.first?.riferimento ?? chat.id,
                messageType: "messaggio",
                onSendNow: {
                    showSmartSchedulePrompt = false
                    sendMessageNow()
                },
                onSchedule: { date in
                    showSmartSchedulePrompt = false
                    scheduledDate = date
                    scheduleMessage()
                },
                onCancel: {
                    showSmartSchedulePrompt = false
                }
            )
        }
        .overlay(alignment: .top) {
            // Feedback screenshot
            if let feedback = screenshotFeedback {
                HStack(spacing: 8) {
                    Image(systemName: feedback.contains("Errore") ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(feedback.contains("Errore") ? .red : .green)
                    Text(feedback)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                )
                .padding(.top, 80)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: screenshotFeedback)
                .allowsHitTesting(false)
            }
        }
    }
    
    // MARK: - Window Title (usato solo da WhatsAppChatWindowView)
    
    var windowTitle: String {
        var parts: [String] = ["WhatsApp"]
        
        // Riferimento sinistro
        if let sinistro = viewModel.selectedChatAssociatedSinistri.first {
            parts.append(sinistro.riferimentoVisualizzato)
            
            // Nome assicurato
            if let nomeAssicurato = sinistro.nomeAssicurato, !nomeAssicurato.isEmpty {
                parts.append(nomeAssicurato)
            }
        } else {
            // Se non c'è sinistro, usa il nome della chat
            parts.append(chat.name)
        }
        
        // Tipo interlocutore (TODO: da rubrica)
        parts.append(chat.isGroup ? "Gruppo" : "Assicurato")
        
        return parts.joined(separator: " - ")
    }
    
    // MARK: - Attachment Preview
    
    private func attachmentPreview(url: URL) -> some View {
        HStack(spacing: 10) {
            // Icona/anteprima
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
                
                if let size = fileSizeString(url) {
                    Text(size)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedMediaURL = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.controlBackgroundColor).opacity(0.9))
        )
    }
    
    // MARK: - Template Picker Popover
    
    private var templatePickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Messaggi predefiniti")
                    .font(.headline)
                Spacer()
                Button {
                    showingTemplatePicker = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Lista template
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
                                
                                if template.requiredTag != nil {
                                    Image(systemName: "paperclip")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
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
            
            // Info sinistro
            if let sinistro = viewModel.selectedChatAssociatedSinistri.first {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sinistro collegato")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(sinistro.riferimentoVisualizzato)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .padding(12)
            } else {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                    Text("Nessun sinistro collegato. I valori saranno da compilare.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
            }
        }
        .frame(width: 320, height: 380)
    }
    
    private func applyTemplate(_ template: WhatsAppMessageTemplateService.TemplateType) {
        let sinistro = viewModel.selectedChatAssociatedSinistri.first
        let userName = appState.googleAuthService.userEmail?.components(separatedBy: "@").first?.capitalized
        
        // Genera messaggio
        let message = templateService.generateMessage(template: template, sinistro: sinistro, userName: userName)
        messageText = message
        
        // Se il template richiede un allegato, cerca il file con il tag corrispondente
        if let requiredTagId = template.requiredTag,
           let sinistro = sinistro,
           let tag = FileTagManager.FileTag.availableTags.first(where: { $0.id == requiredTagId }) {
            let filesWithTag = fileTagManager.getFilesWithTag(tag)
            
            if let sinistroPath = fileService.getSinistroPath(riferimento: sinistro.riferimento ?? "") {
                for filePath in filesWithTag {
                    if filePath.hasPrefix(sinistroPath) {
                        selectedMediaURL = URL(fileURLWithPath: filePath)
                        break
                    }
                }
            }
        }
        
        isMessageFieldFocused = true
    }
    
    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedMediaURL != nil
    }
    
    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.text.fill"
        case "jpg", "jpeg", "png", "heic", "gif": return "photo.fill"
        case "mp4", "mov", "m4v": return "video.fill"
        case "mp3", "m4a", "wav": return "waveform"
        default: return "doc.fill"
        }
    }
    
    private func fileSizeString(_ url: URL) -> String? {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attr[.size] as? Int64 else { return nil }
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    private func selectPhoto() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .movie]
        
        if panel.runModal() == .OK {
            selectedMediaURL = panel.url
        }
    }
    
    // MARK: - Linked Sinistro Bar (stile iMessage)
    
    private func linkedSinistroBar(sinistro: Sinistro) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.orange)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Sinistro \(sinistro.riferimentoVisualizzato)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                if let nomeAssicurato = sinistro.nomeAssicurato, !nomeAssicurato.isEmpty {
                    Text(nomeAssicurato)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Pulsante Riassumi (Apple Intelligence)
            Button {
                // TODO: Riassumi conversazione con Apple Intelligence
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                    Text("Riassumi")
                        .font(.caption)
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.12))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .help("Riassumi la conversazione con Apple Intelligence")
            
            // Pulsante Apri Sinistro
            Button {
                NotificationCenter.default.post(
                    name: NSNotification.Name("OpenSinistro"),
                    object: nil,
                    userInfo: ["sinistro": sinistro]
                )
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12))
                    Text("Apri")
                        .font(.caption)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .help("Apri sinistro in nuova finestra")
            
            // Pulsante scollega
            Button {
                // Rimuovi associazione sinistro dalla chat
                WhatsAppAssociationService.shared.disassociateChat(chatId: chat.id, context: viewContext)
                viewModel.loadAssociatedSinistri(for: chat.id, context: viewContext)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
    
    // MARK: - Actions
    private func reconnect() {
        Task {
            await viewModel.restartConnection()
        }
    }
    
    private func disconnect() {
        Task {
            await viewModel.disconnect()
        }
    }
    
    private func selectMedia() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .image, .movie, .audio, .pdf,
            UTType(filenameExtension: "doc") ?? .data,
            UTType(filenameExtension: "docx") ?? .data
        ]
        
        if panel.runModal() == .OK {
            selectedMediaURL = panel.url
        }
    }
    
    
    /// Valuta se mostrare prompt smart schedule o inviare direttamente
    private func attemptSendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || selectedMediaURL != nil else { return }
        
        // Ottieni sinistroRef se associato
        let sinistroRef = viewModel.selectedChatAssociatedSinistri.first?.riferimento
        
        // Valuta smart scheduling
        let evaluation = smartScheduleService.evaluateSend(
            for: .whatsapp,
            sinistroRef: sinistroRef,
            conversationId: chat.id
        )
        
        switch evaluation {
        case .sendNow:
            sendMessageNow()
            
        case .shouldPrompt(let suggestedTime, let reason):
            smartScheduleSuggestedDate = suggestedTime
            smartScheduleReason = reason
            showSmartSchedulePrompt = true
            
        case .autoSchedule(let scheduledFor):
            scheduledDate = scheduledFor
            scheduleMessage()
        }
    }
    
    private func sendMessageNow() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        let media = selectedMediaURL
        messageText = ""
        selectedMediaURL = nil
        
        // Permetti invio anche solo con media (senza testo)
        guard !text.isEmpty || media != nil else { return }
        
        Task {
            do {
                let mediaUrlString = media?.absoluteString
                try await viewModel.sendMessage(to: chat.id, message: text, mediaUrl: mediaUrlString)
                await viewModel.fetchMessages(for: chat.id)
            } catch {
                print("Errore invio messaggio: \(error)")
            }
        }
    }
    
    private func scheduleMessage() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        let media = selectedMediaURL
        let phoneNumber = chat.phoneNumber ?? chat.id
        let scheduleFor = scheduledDate
        let sinistroRef = viewModel.selectedChatAssociatedSinistri.first?.riferimento
        
        messageText = ""
        selectedMediaURL = nil
        isScheduled = false
        
        guard !text.isEmpty || media != nil else { return }
        guard scheduleFor > Date() else {
            print("[WhatsApp] Data programmazione non valida")
            return
        }
        
        Task {
            do {
                // Leggi media come base64 se presente
                var mediaData: String? = nil
                var mediaType: String? = nil
                var mediaFilename: String? = nil
                
                if let mediaURL = media, let data = try? Data(contentsOf: mediaURL) {
                    mediaData = data.base64EncodedString()
                    mediaType = UTType(filenameExtension: mediaURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    mediaFilename = mediaURL.lastPathComponent
                }
                
                let scheduled = try await ScheduledWhatsAppService.shared.scheduleMessage(
                    accountId: "default", // TODO: supporto multi-account WA
                    phoneNumber: phoneNumber,
                    body: text,
                    mediaData: mediaData,
                    mediaType: mediaType,
                    mediaFilename: mediaFilename,
                    scheduledFor: scheduleFor,
                    sinistroRef: sinistroRef
                )
                
                print("[WhatsApp] ✅ Messaggio programmato: \(scheduled.id) per \(scheduleFor)")
                
                // Ricarica la lista
                loadScheduledMessages()
                
            } catch {
                print("[WhatsApp] ❌ Errore programmazione: \(error)")
            }
        }
    }
    
    // MARK: - Scheduled Messages
    
    /// Messaggi programmati filtrati per questa chat
    private var pendingScheduledMessagesForChat: [ScheduledWhatsAppService.ScheduledWhatsApp] {
        let phoneNumber = chat.phoneNumber ?? chat.id
        return pendingScheduledMessages.filter { scheduled in
            scheduled.phoneNumber == phoneNumber && scheduled.isScheduled
        }
    }
    
    /// Carica messaggi programmati
    private func loadScheduledMessages() {
        Task {
            do {
                let messages = try await ScheduledWhatsAppService.shared.getScheduledMessages(accountId: "default")
                pendingScheduledMessages = messages.filter { $0.isScheduled }
            } catch {
                print("[WhatsApp] Errore caricamento messaggi programmati: \(error)")
            }
        }
    }
    
    /// Vista per singolo messaggio programmato
    private func scheduledMessageRow(_ scheduled: ScheduledWhatsAppService.ScheduledWhatsApp) -> some View {
        HStack(spacing: 12) {
            // Icona
            Image(systemName: "clock.fill")
                .font(.system(size: 18))
                .foregroundColor(.orange)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text("Programmato per \(scheduled.scheduledAtFormatted)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(scheduled.body.prefix(50) + (scheduled.body.count > 50 ? "..." : ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Azioni
            HStack(spacing: 8) {
                // Invia subito
                Button {
                    sendScheduledNow(scheduled)
                } label: {
                    Text("Invia ora")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                
                // Modifica
                Button {
                    editingScheduledMessage = scheduled
                    scheduledDate = scheduled.scheduledAt
                    showSchedulePicker = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                
                // Annulla
                Button {
                    cancelScheduledMessage(scheduled)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                        )
                        .foregroundColor(.orange.opacity(0.4))
                )
        )
    }
    
    /// Invia subito un messaggio programmato
    private func sendScheduledNow(_ scheduled: ScheduledWhatsAppService.ScheduledWhatsApp) {
        Task {
            do {
                // Cancella il programmato
                try await ScheduledWhatsAppService.shared.cancelScheduledMessage(id: scheduled.id)
                
                // Invia subito
                try await viewModel.sendMessage(
                    to: chat.id,
                    message: scheduled.body,
                    mediaUrl: nil
                )
                
                // Ricarica lista
                loadScheduledMessages()
                
            } catch {
                print("[WhatsApp] Errore invio immediato: \(error)")
            }
        }
    }
    
    /// Cancella messaggio programmato
    private func cancelScheduledMessage(_ scheduled: ScheduledWhatsAppService.ScheduledWhatsApp) {
        Task {
            do {
                try await ScheduledWhatsAppService.shared.cancelScheduledMessage(id: scheduled.id)
                loadScheduledMessages()
            } catch {
                print("[WhatsApp] Errore cancellazione: \(error)")
            }
        }
    }
}

// MARK: - WhatsApp Schedule Picker

struct WhatsAppSchedulePickerView: View {
    @Binding var scheduledDate: Date
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Programma messaggio")
                .font(.headline)
            
            DatePicker(
                "Invia il",
                selection: $scheduledDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            
            HStack {
                Button("Annulla") { onCancel() }
                    .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Conferma") { onConfirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(scheduledDate <= Date())
            }
        }
        .padding()
        .frame(width: 350, height: 400)
    }
}

// MARK: - Association Popover
struct WhatsAppAssociationPopover: View {
    let chat: WhatsAppChat
    let messages: [WhatsAppMessage]
    let suggestedSinistri: [Sinistro]
    let onAssociate: ([Sinistro]) -> Void
    
    @State private var selectedSinistri: Set<Sinistro> = []
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Associa Chat a Sinistro")
                .font(.headline)
            
            if suggestedSinistri.isEmpty {
                Text("Nessun sinistro trovato automaticamente")
                    .foregroundColor(.secondary)
            } else {
                Text("Sinistri suggeriti:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                List(suggestedSinistri, id: \.objectID) { sinistro in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if let riferimento = sinistro.riferimento {
                                Text(riferimento)
                                    .font(.headline)
                            }
                            if let nomeAssicurato = sinistro.nomeAssicurato {
                                Text(nomeAssicurato)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if selectedSinistri.contains(sinistro) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedSinistri.contains(sinistro) {
                            selectedSinistri.remove(sinistro)
                        } else {
                            selectedSinistri.insert(sinistro)
                        }
                    }
                }
                .frame(height: 200)
            }
            
            HStack {
                Spacer()
                Button("Annulla") {
                    dismiss()
                }
                Button("Associa") {
                    onAssociate(Array(selectedSinistri))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedSinistri.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            selectedSinistri = Set(suggestedSinistri)
        }
    }
}

// MARK: - Message Bubble
struct WhatsAppMessageBubble: View {
    let message: WhatsAppMessage
    let chat: WhatsAppChat
    @StateObject private var taskManager = TaskManager.shared
    @State private var downloadedMediaURL: URL?
    @State private var isDownloading = false
    @State private var isHovering = false
    
    var isSent: Bool {
        message.isSent
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isSent {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: isSent ? .trailing : .leading, spacing: 2) {
                // Media se presente
                if let mediaUrl = message.mediaUrl, message.type != .text {
                    let fullUrl = mediaUrl
                    let mediaType = message.type
                    
                    Group {
                        switch mediaType {
                        case .image:
                            AsyncImage(url: URL(string: fullUrl)) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 200, height: 200)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: 250, maxHeight: 300)
                                        .cornerRadius(8)
                                case .failure:
                                    Image(systemName: "photo")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary)
                                        .frame(width: 200, height: 200)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        case .sticker:
                            AsyncImage(url: URL(string: fullUrl)) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 160, height: 160)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: 180, maxHeight: 180)
                                case .failure:
                                    Image(systemName: "face.smiling")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary)
                                        .frame(width: 160, height: 160)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        case .video:
                            VStack {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                                Text("Video")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                            .frame(width: 200, height: 150)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                        case .audio:
                            HStack {
                                Image(systemName: "waveform")
                                    .font(.system(size: 20))
                                Text("Audio")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        case .document:
                            HStack {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 20))
                                Text("Documento")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        case .ptt:
                            HStack {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 20))
                                Text("Nota vocale")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        case .text, .location, .contact:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, message.body.isEmpty ? 10 : 0)
                    .padding(.vertical, message.body.isEmpty ? 8 : 0)
                    .padding(.bottom, message.body.isEmpty ? 0 : 4)
                    .background(
                        Group {
                            if isSent {
                                LinearGradient(
                                    colors: [Color(red: 0.18, green: 0.78, blue: 0.44), Color(red: 0.18, green: 0.78, blue: 0.44)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            } else {
                                Color(.controlBackgroundColor)
                            }
                        }
                    )
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
                    .overlay(
                        // Overlay per indicare che è cliccabile
                        Group {
                            if isDownloading {
                                ProgressView()
                                    .frame(width: 40, height: 40)
                                    .background(Color.black.opacity(0.5))
                                    .cornerRadius(8)
                            } else if isHovering {
                                // Icona per indicare che è cliccabile (appare al hover)
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(6)
                                    .transition(.opacity.combined(with: .scale))
                            }
                        }
                    )
                    .onTapGesture {
                        openMediaInViewer(mediaUrl: fullUrl, mediaType: mediaType)
                    }
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isHovering = hovering
                        }
                        if hovering && !isDownloading {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
                
                // Bubble del messaggio (solo se c'è testo)
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        if !message.body.isEmpty {
                            HStack(alignment: .bottom, spacing: 6) {
                                Text(message.body)
                                    .font(.system(size: 15))
                                    .foregroundColor(isSent ? .white : .primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                
                                // Timestamp e stato lettura dentro la bubble
                                HStack(spacing: 3) {
                                    // Indicatore task generato (solo per messaggi ricevuti)
                                    if !isSent && hasGeneratedTask(for: message) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 11))
                                        .foregroundColor(isSent ? .white.opacity(0.8) : .secondary)
                                    
                                    if isSent {
                                        MessageStatusIndicator(message: message, lightMode: true)
                                    }
                                }
                                .padding(.leading, 4)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        } else {
                            // Se c'è solo media, mostra timestamp sotto
                            HStack(spacing: 3) {
                                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                
                                if isSent {
                                    MessageStatusIndicator(message: message, lightMode: false)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .background(
                        Group {
                            if isSent {
                                // Verde per messaggi inviati (stile WhatsApp)
                                LinearGradient(
                                    colors: [Color(red: 0.18, green: 0.78, blue: 0.44), Color(red: 0.18, green: 0.78, blue: 0.44)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            } else {
                                // Grigio chiaro per messaggi ricevuti
                                Color(.controlBackgroundColor)
                            }
                        }
                    )
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
                    
                    // Task associate (se presenti) - dentro la stessa bolla
                    let messageTasks = getTasksForMessage(message)
                    if !messageTasks.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(messageTasks) { task in
                                TaskAttachmentView(
                                    task: task,
                                    onEdit: nil
                                )
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(maxWidth: 500, alignment: isSent ? .trailing : .leading)
            
            if !isSent {
                Spacer(minLength: 50)
            }
        }
        .padding(.vertical, 2)
    }
    
    private func hasGeneratedTask(for message: WhatsAppMessage) -> Bool {
        return taskManager.tasks.contains { task in
            if let whatsAppChatId = task.metadata["whatsAppChatId"]?.value as? String {
                return whatsAppChatId == chat.id
            }
            return false
        }
    }
    
    private func getTasksForMessage(_ message: WhatsAppMessage) -> [DailyTask] {
        return taskManager.tasks.filter { task in
            if let whatsAppChatId = task.metadata["whatsAppChatId"]?.value as? String {
                return whatsAppChatId == chat.id
            }
            return false
        }
    }
    
    private func openMediaInViewer(mediaUrl: String, mediaType: WhatsAppMediaType) {
        guard let url = URL(string: mediaUrl) else { return }
        
        // Se è già un file locale, apri direttamente
        if url.scheme == "file" {
            MediaViewerWindowManager.shared.openMediaViewer(for: url)
            return
        }
        
        // Altrimenti, scarica il file temporaneamente
        isDownloading = true
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("[WhatsApp] ❌ Errore download media: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                    await MainActor.run {
                        isDownloading = false
                    }
                    return
                }
                
                // Determina estensione dal tipo media o dall'URL
                let fileExtension = getFileExtension(for: mediaType, url: mediaUrl)
                let fileName = "\(message.id).\(fileExtension)"
                
                // Salva in directory temporanea
                let tempDir = FileManager.default.temporaryDirectory
                let tempFileURL = tempDir.appendingPathComponent("WhatsAppMedia_\(fileName)")
                
                try data.write(to: tempFileURL)
                
                await MainActor.run {
                    isDownloading = false
                    downloadedMediaURL = tempFileURL
                    MediaViewerWindowManager.shared.openMediaViewer(for: tempFileURL)
                }
            } catch {
                print("[WhatsApp] ❌ Errore download media: \(error)")
                await MainActor.run {
                    isDownloading = false
                }
            }
        }
    }
    
    private func getFileExtension(for mediaType: WhatsAppMediaType, url: String) -> String {
        // Prova a estrarre l'estensione dall'URL
        if let urlObj = URL(string: url),
           !urlObj.pathExtension.isEmpty {
            return urlObj.pathExtension
        }
        
        // Fallback basato sul tipo media
        switch mediaType {
        case .text:
            return "txt"
        case .image:
            return "jpg"
        case .video:
            return "mp4"
        case .audio, .ptt:
            return "mp3"
        case .document:
            return "pdf"
        case .sticker:
            return "webp"
        case .location, .contact:
            return "txt"
        }
    }
}

// MARK: - Message Status Indicator

/// Indicatore stato messaggio (spunte WhatsApp)
/// ackStatus: -1=error, 0=pending, 1=sent, 2=delivered, 3=read, 4=played
struct MessageStatusIndicator: View {
    let message: WhatsAppMessage
    let lightMode: Bool // true per sfondo scuro (messaggi inviati)
    
    private var ackStatus: Int { message.ackStatus ?? 0 }
    
    var body: some View {
        HStack(spacing: 1) {
            switch ackStatus {
            case -1: // Error
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            case 0: // Pending (orologio)
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundColor(lightMode ? .white.opacity(0.6) : .secondary)
            case 1: // Sent (una spunta grigia)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(lightMode ? .white.opacity(0.7) : .secondary)
            case 2: // Delivered (due spunte grigie)
                ZStack {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .offset(x: -2)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .offset(x: 2)
                }
                .foregroundColor(lightMode ? .white.opacity(0.7) : .secondary)
            case 3, 4: // Read/Played (due spunte blu)
                ZStack {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .offset(x: -2)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .offset(x: 2)
                }
                .foregroundColor(.blue)
            default:
                // Nessun ACK ancora, mostra pending
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundColor(lightMode ? .white.opacity(0.6) : .secondary)
            }
        }
        .frame(width: 18)
    }
}

// MARK: - Modern WhatsApp Message Bubble (stile iMessage/iOS 26)

struct ModernWhatsAppMessageBubble: View {
    let message: WhatsAppMessage
    let chat: WhatsAppChat
    var onTagMessage: ((WhatsAppMessage) -> Void)?
    
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = WhatsAppMessageTagManager.shared
    @State private var downloadedMediaURL: URL?
    @State private var isDownloading = false
    @State private var isHovering = false
    @State private var showingTagSheet = false
    
    var isSent: Bool { message.isSent }
    
    private var messageTags: Set<WhatsAppMessageTag> {
        tagManager.getTags(forMessageId: message.id)
    }
    
    private var sinistroRif: String? {
        tagManager.getSinistroRif(forMessageId: message.id)
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isSent {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: isSent ? .trailing : .leading, spacing: 6) {
                // Tag e sinistro associato (se presenti)
                if !messageTags.isEmpty || sinistroRif != nil {
                    HStack(spacing: 6) {
                        // Badge sinistro
                        if let rif = sinistroRif {
                            HStack(spacing: 3) {
                                Image(systemName: "link")
                                    .font(.system(size: 9))
                                Text(rif)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(6)
                        }
                        
                        // Tag
                        ForEach(Array(messageTags).prefix(3), id: \.self) { tag in
                            WhatsAppTagBadge(tag: tag, isCompact: true)
                        }
                        
                        if messageTags.count > 3 {
                            Text("+\(messageTags.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Bubble principale
                VStack(alignment: .leading, spacing: 0) {
                    // Media se presente
                    if let mediaUrl = message.mediaUrl, message.type != .text {
                        mediaContent(mediaUrl: mediaUrl, mediaType: message.type)
                    }
                    
                    // Testo messaggio
                    if !message.body.isEmpty {
                        messageTextContent
                    } else if message.type == .text || message.mediaUrl == nil {
                        // Solo timestamp per messaggi vuoti
                        timestampOnly
                    }
                }
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
                .contextMenu {
                    // Context menu per azioni
                    Button {
                        showingTagSheet = true
                    } label: {
                        Label("Tagga messaggio", systemImage: "tag")
                    }
                    
                    Button {
                        copyMessageToClipboard()
                    } label: {
                        Label("Copia", systemImage: "doc.on.doc")
                    }
                    
                    Divider()
                    
                    if !isSent {
                        Button {
                            // TODO: Crea task da messaggio
                        } label: {
                            Label("Crea task", systemImage: "checklist")
                        }
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovering = hovering
                    }
                }
                
                // Task associate
                let messageTasks = getTasksForMessage(message)
                if !messageTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(messageTasks) { task in
                            TaskAttachmentView(task: task, onEdit: nil)
                        }
                    }
                    .padding(.top, 4)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: 480, alignment: isSent ? .trailing : .leading)
            
            if !isSent {
                Spacer(minLength: 60)
            }
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $showingTagSheet) {
            WhatsAppMessageTagSheet(message: message, chatId: chat.id)
        }
    }
    
    // MARK: - Message Text Content
    
    private var messageTextContent: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(message.body)
                .font(.system(size: 15))
                .foregroundColor(isSent ? .white : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            
            // Timestamp e status
            HStack(spacing: 3) {
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundColor(isSent ? .white.opacity(0.7) : .secondary)
                
                if isSent {
                    MessageStatusIndicator(message: message, lightMode: true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    private var timestampOnly: some View {
        HStack(spacing: 3) {
            Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            if isSent {
                MessageStatusIndicator(message: message, lightMode: false)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
    
    // MARK: - Media Content
    
    @ViewBuilder
    private func mediaContent(mediaUrl: String, mediaType: WhatsAppMediaType) -> some View {
        Group {
            switch mediaType {
            case .image:
                AsyncImage(url: URL(string: mediaUrl)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 220, height: 180)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: 280, maxHeight: 320)
                            .clipped()
                    case .failure:
                        mediaPlaceholder(icon: "photo", label: "Immagine")
                    @unknown default:
                        EmptyView()
                    }
                }
            case .sticker:
                AsyncImage(url: URL(string: mediaUrl)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 140, height: 140)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 160, maxHeight: 160)
                    case .failure:
                        mediaPlaceholder(icon: "face.smiling", label: "Sticker")
                    @unknown default:
                        EmptyView()
                    }
                }
            case .video:
                mediaPlaceholder(icon: "play.circle.fill", label: "Video", large: true)
            case .audio:
                audioWaveform
            case .document:
                documentPreview
            case .ptt:
                voiceNotePreview
            case .text, .location, .contact:
                EmptyView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(4)
        .overlay(
            Group {
                if isDownloading {
                    ProgressView()
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                } else if isHovering && mediaType != .text {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .transition(.scale.combined(with: .opacity))
                }
            }
        )
        .onTapGesture {
            openMediaInViewer(mediaUrl: mediaUrl, mediaType: mediaType)
        }
    }
    
    private func mediaPlaceholder(icon: String, label: String, large: Bool = false) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: large ? 36 : 28))
                .foregroundColor(isSent ? .white.opacity(0.9) : .secondary)
            Text(label)
                .font(.caption)
                .foregroundColor(isSent ? .white.opacity(0.8) : .secondary)
        }
        .frame(width: large ? 200 : 120, height: large ? 140 : 100)
        .background(isSent ? Color.white.opacity(0.1) : Color.secondary.opacity(0.1))
    }
    
    private var audioWaveform: some View {
        HStack(spacing: 10) {
            Button {
                // Play audio
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(isSent ? .white : .green)
            }
            .buttonStyle(.plain)
            
            // Waveform placeholder
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isSent ? Color.white.opacity(0.6) : Color.secondary.opacity(0.4))
                        .frame(width: 3, height: CGFloat.random(in: 8...24))
                }
            }
            
            Text("0:00")
                .font(.caption)
                .foregroundColor(isSent ? .white.opacity(0.8) : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    private var documentPreview: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.system(size: 28))
                .foregroundColor(isSent ? .white : .blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Documento")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isSent ? .white : .primary)
                Text("PDF")
                    .font(.caption)
                    .foregroundColor(isSent ? .white.opacity(0.7) : .secondary)
            }
            
            Spacer()
            
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 22))
                .foregroundColor(isSent ? .white.opacity(0.8) : .blue)
        }
        .padding(12)
        .frame(width: 220)
    }
    
    private var voiceNotePreview: some View {
        HStack(spacing: 10) {
            Button {
                // Play voice note
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(isSent ? .white : .green)
            }
            .buttonStyle(.plain)
            
            // Waveform
            HStack(spacing: 2) {
                ForEach(0..<15, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isSent ? Color.white.opacity(0.6) : Color.green.opacity(0.6))
                        .frame(width: 3, height: CGFloat.random(in: 6...20))
                }
            }
            
            Text("0:00")
                .font(.caption)
                .foregroundColor(isSent ? .white.opacity(0.8) : .secondary)
            
            // Icona microfono
            Image(systemName: "mic.fill")
                .font(.system(size: 12))
                .foregroundColor(isSent ? .white.opacity(0.6) : .green.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    // MARK: - Background
    
    @ViewBuilder
    private var bubbleBackground: some View {
        if isSent {
            LinearGradient(
                colors: [
                    Color(red: 0.2, green: 0.75, blue: 0.45),
                    Color(red: 0.15, green: 0.68, blue: 0.40)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(.controlBackgroundColor)
        }
    }
    
    // MARK: - Actions
    
    private func copyMessageToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.body, forType: .string)
    }
    
    private func getTasksForMessage(_ message: WhatsAppMessage) -> [DailyTask] {
        return taskManager.tasks.filter { task in
            if let whatsAppChatId = task.metadata["whatsAppChatId"]?.value as? String {
                return whatsAppChatId == chat.id
            }
            return false
        }
    }
    
    private func openMediaInViewer(mediaUrl: String, mediaType: WhatsAppMediaType) {
        guard let url = URL(string: mediaUrl) else { return }
        
        if url.scheme == "file" {
            MediaViewerWindowManager.shared.openMediaViewer(for: url)
            return
        }
        
        isDownloading = true
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    await MainActor.run { isDownloading = false }
                    return
                }
                
                let fileExtension = getFileExtension(for: mediaType, url: mediaUrl)
                let fileName = "\(message.id).\(fileExtension)"
                let tempDir = FileManager.default.temporaryDirectory
                let tempFileURL = tempDir.appendingPathComponent("WhatsAppMedia_\(fileName)")
                
                try data.write(to: tempFileURL)
                
                await MainActor.run {
                    isDownloading = false
                    downloadedMediaURL = tempFileURL
                    MediaViewerWindowManager.shared.openMediaViewer(for: tempFileURL)
                }
            } catch {
                await MainActor.run { isDownloading = false }
            }
        }
    }
    
    private func getFileExtension(for mediaType: WhatsAppMediaType, url: String) -> String {
        if let urlObj = URL(string: url), !urlObj.pathExtension.isEmpty {
            return urlObj.pathExtension
        }
        
        switch mediaType {
        case .text: return "txt"
        case .image: return "jpg"
        case .video: return "mp4"
        case .audio, .ptt: return "mp3"
        case .document: return "pdf"
        case .sticker: return "webp"
        case .location, .contact: return "txt"
        }
    }
}

// MARK: - Shake Effect Modifier

struct ShakeEffectModifier: ViewModifier {
    var trigger: Int
    
    func body(content: Content) -> some View {
        content
            .offset(x: trigger > 0 ? shakeOffset : 0)
            .animation(.default, value: trigger)
    }
    
    private var shakeOffset: CGFloat {
        let sequence: [CGFloat] = [0, -10, 10, -8, 8, -5, 5, 0]
        let index = abs(trigger) % sequence.count
        return sequence[index]
    }
}

