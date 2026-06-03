import SwiftUI
import CoreData
import Combine

struct ComunicazioniView: View {
    // --- Tab principale ---
    private enum Tab: String, CaseIterable {
        case mail = "Mail"
        case messaggi = "Messaggi"
        case whatsapp = "WhatsApp"
        case telegram = "Telegram"
        case chiamate = "Chiamate"
        case ibrida = "Ibrida"
        case rubrica = "Rubrica"
    }
    @State private var selectedTab: Tab = .mail
    
    // State for Mail view - usa il singleton persistente
    @ObservedObject private var mailViewModel = MailViewModel.shared
    @State private var selectedEmail: Email?
    @State private var showingAssociationPopover = false
    @State private var emailToAssociate: Email?
    @State private var suggestedSinistri: [Sinistro] = []
    @State private var showingCreateTask = false
    @State private var taskEmail: Email?
    @State private var taskWhatsAppChat: WhatsAppChat?
    @State private var taskWhatsAppMessage: WhatsAppMessage?
    @Environment(\.managedObjectContext) private var viewContext
    
    // State for WhatsApp view
    @ObservedObject private var whatsappViewModel = WhatsAppViewModel.shared
    @State private var selectedWhatsAppChatId: String?
    @State private var showingQRCode = false
    @State private var incomingCall: CommunicationIncomingCallItem?
    @State private var showIncomingCallAlert = false

    // Layout preferences (persistenti)
    @AppStorage("mailSidebarWidth") private var sidebarWidth: Double = 320
    @AppStorage("mailDetailWidth") private var detailWidth: Double = 600

    var body: some View {
        mainContent
            .background(Color(.windowBackgroundColor))
            .toolbar { toolbarContent }
            .navigationTitle("")
            .onReceive(IncomingCallPoller.shared.incomingCall) { item in
                incomingCall = item
                showIncomingCallAlert = true
            }
            .alert(
                "Chiamata in arrivo",
                isPresented: $showIncomingCallAlert,
                presenting: incomingCall
            ) { item in
                Button("Rispondi") { selectedTab = .chiamate }
                Button("Rifiuta", role: .destructive) { RingbackPlayer.shared.stop() }
            } message: { item in
                Text(item.displayName ?? "Comunicazione PerX")
            }
            .onChange(of: selectedEmail) { _, newValue in
                handleEmailChange(newValue)
            }
            .onChange(of: selectedWhatsAppChatId) { _, newValue in
                handleWhatsAppChatChange(newValue)
            }
            .onChange(of: selectedTab) { _, newValue in
                handleTabChange(newValue)
            }
            .onAppear(perform: handleOnAppear)
            .onDisappear(perform: handleOnDisappear)
            .sheet(isPresented: $showingQRCode) {
                if let qrCode = whatsappViewModel.qrCode {
                    QRCodeView(qrCode: qrCode)
                }
            }
    }
    
    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
        switch selectedTab {
        case .mail:
            mailViewBody
        case .messaggi:
            MessagesView()
        case .whatsapp:
            whatsappViewBody
        case .telegram:
            placeholderView(for: "Telegram")
        case .chiamate:
            TelefonoCommunicationView(
                myExtension: UserProfileService.shared.currentProfile?.extensionNumber,
                myExtensionEnabled: UserProfileService.shared.currentProfile?.extensionEnabled ?? false
            )
        case .ibrida:
            placeholderView(for: "Ibrida")
        case .rubrica:
            RubricaContainerView()
        }
    }
    
    // MARK: - Toolbar Content
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Comunicazioni", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 600)
        }
        
        // Pulsante Nuova Email (solo nella tab mail)
        if selectedTab == .mail {
            ToolbarItem(placement: .primaryAction) {
                Button(action: handleNewEmail) {
                    Label("Nuova Email", systemImage: "square.and.pencil")
                }
                .help("Scrivi una nuova email")
            }
        }
    }
    
    // MARK: - Event Handlers
    private func handleEmailChange(_ newEmail: Email?) {
        if let email = newEmail, !email.isRead {
            mailViewModel.markEmailAsRead(emailId: email.id)
        }
    }
    
    private func handleWhatsAppChatChange(_ chatId: String?) {
        if let chatId = chatId {
            Task { whatsappViewModel.selectChat(chatId) }
        }
    }
    
    private func handleTabChange(_ newTab: Tab) {
        if newTab == .whatsapp {
            Task {
                if !whatsappViewModel.isConnected {
                    await whatsappViewModel.connect()
                } else {
                    await whatsappViewModel.fetchChats()
                }
            }
        }
    }
    
    private func handleOnAppear() {
        if !PrincipaleViewModel.shared.isPreloaded {
            Task.detached(priority: .userInitiated) {
                await PrincipaleViewModel.shared.preload()
            }
        }
        if selectedTab == .whatsapp {
            Task {
                await WhatsAppViewModel.shared.connect()
            }
        }
    }
    
    private func handleOnDisappear() {
        // Placeholder per cleanup futuro
    }
    
    // MARK: - Mail View Body
    @ViewBuilder
    private var mailViewBody: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Sidebar (Lista email)
                MailContainerView(
                    viewModel: mailViewModel, 
                    selectedEmail: $selectedEmail
                )
                .frame(width: sidebarWidth)
                .background(Color(.controlBackgroundColor))
                
                // Divisore ridimensionabile
                ResizableDivider(
                    width: $sidebarWidth,
                    minWidth: 280,
                    maxWidth: min(500, geometry.size.width * 0.6)
                )
                
                // Detail view (Contenuto email)
                mailDetailSection
                    .frame(maxWidth: .infinity)
                    .background(Color(.textBackgroundColor))
            }
        }
    }
    
    // MARK: - Mail Detail Section
    private var mailDetailSection: some View {
        VStack(spacing: 0) {
            if let email = selectedEmail {
                // Usa un State per cache del thread (evita ricalcoli continui)
                ThreadCacheView(
                    email: email,
                    onReply: { handleReply(email) },
                    onReplyAll: { handleReplyAll(email) },
                    onForward: { handleForward(email) },
                    onToggleRead: { handleToggleRead(email) },
                    onCreateTask: { handleCreateTask(email) },
                    onAssociateClaim: { handleAssociateClaim(email) }
                )
                .popover(isPresented: $showingAssociationPopover, attachmentAnchor: .point(.top)) {
                    if let emailToAssociate = emailToAssociate {
                        EmailAssociationPopover(
                            email: emailToAssociate,
                            suggestedSinistri: suggestedSinistri,
                            onAssociate: { sinistri in
                                Task {
                                    await EmailAssociationService.shared.associateEmailToSinistri(emailToAssociate, sinistri: sinistri, context: viewContext)
                                }
                            }
                        )
                    }
                }
            } else {
                // Empty state elegante
                VStack(spacing: 16) {
                    Image(systemName: "envelope")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Seleziona un'email")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text("Scegli un'email dalla lista per visualizzarne il contenuto")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.textBackgroundColor))
            }
        }
    }
    
    // MARK: - Thread Cache View (mostra subito, aggiorna in streaming)
    private struct ThreadCacheView: View {
        let email: Email
        let onReply: () -> Void
        let onReplyAll: () -> Void
        let onForward: () -> Void
        let onToggleRead: () -> Void
        let onCreateTask: () -> Void
        let onAssociateClaim: () -> Void
        
        @State private var cachedThread: SinistroEmailThread?
        @State private var isSearching = false
        @State private var loadTask: Task<Void, Never>?
        
        var body: some View {
            Group {
                if let thread = cachedThread {
                    // Mostra la visualizzazione thread (quando trovato)
                    EmailThreadView(
                        mailViewModel: MailViewModel.shared,
                        principaleViewModel: PrincipaleViewModel.shared,
                        thread: thread
                    )
                    .transition(.opacity)
                } else {
                    // Mostra visualizzazione email singola (riusa stesso componente thread)
                    ZStack(alignment: .bottom) {
                        EmailThreadView(
                            mailViewModel: MailViewModel.shared,
                            principaleViewModel: PrincipaleViewModel.shared,
                            email: email,
                            onReply: { _ in onReply() },
                            onReplyAll: { _ in onReplyAll() },
                            onForward: { _ in onForward() },
                            onToggleRead: { _ in onToggleRead() },
                            onCreateTask: { _ in onCreateTask() },
                            onAssociateClaim: { _ in onAssociateClaim() }
                        )
                        
                        // Indicatore di ricerca thread in background (opzionale)
                        if isSearching {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Ricerca thread...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Color(.controlBackgroundColor).opacity(0.95))
                            .cornerRadius(8)
                            .padding(.bottom, 16)
                        }
                    }
                }
            }
            .onAppear {
                startThreadLoad()
            }
            .onChange(of: email.id) { _, _ in
                // Reset quando cambia l'email
                cachedThread = nil
                isSearching = false
                startThreadLoad()
            }
            .onDisappear {
                loadTask?.cancel()
                loadTask = nil
            }
        }
        
        private func startThreadLoad() {
            guard cachedThread == nil && !isSearching else { return }
            
            loadTask?.cancel()
            isSearching = true
            
            loadTask = Task { @MainActor in
                let emailId = email.id
                
                let thread = await ThreadSearchService.shared.findThread(forEmailId: emailId)
                if Task.isCancelled {
                    isSearching = false
                    return
                }
                
                cachedThread = thread
                isSearching = false
                
                // Prefetch on-demand del contenuto email del thread (priorità alta)
                if let thread {
                    await PrincipaleViewModel.shared.downloadThreadEmailsIfNeeded(thread, priority: _Concurrency.TaskPriority.userInitiated)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    // findThreadForEmail rimosso - ora usa ThreadSearchService che gestisce tutto in modo asincrono
    
    // MARK: - WhatsApp View Body
    @ViewBuilder
    private var whatsappViewBody: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Sidebar (Lista chat)
                WhatsAppContainerView(
                    viewModel: whatsappViewModel,
                    selectedChatId: $selectedWhatsAppChatId
                )
                .frame(width: sidebarWidth)
                .background(Color(.controlBackgroundColor))
                
                // Divisore ridimensionabile
                ResizableDivider(
                    width: $sidebarWidth,
                    minWidth: 280,
                    maxWidth: min(500, geometry.size.width * 0.6)
                )
                
                // Detail view (Conversazione)
                whatsappDetailSection
                    .frame(maxWidth: .infinity)
                    .background(Color(.textBackgroundColor))
            }
        }
        .overlay(alignment: .center) {
            // QR Code overlay se necessario
            if !whatsappViewModel.isConnected, let qrCode = whatsappViewModel.qrCode {
                QRCodeOverlay(qrCode: qrCode, onDismiss: {
                    showingQRCode = false
                })
            }
        }
        .sheet(isPresented: $showingQRCode) {
            if let qrCode = whatsappViewModel.qrCode {
                QRCodeView(qrCode: qrCode)
            }
        }
    }
    
    // MARK: - WhatsApp Detail Section
    private var whatsappDetailSection: some View {
        Group {
            if let chatId = selectedWhatsAppChatId,
               let chat = whatsappViewModel.chats.first(where: { $0.id == chatId }) {
                WhatsAppDetailView(viewModel: whatsappViewModel, chat: chat)
            } else {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "message.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Seleziona una chat")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text("Scegli una chat dalla lista per iniziare la conversazione")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.textBackgroundColor))
            }
        }
    }
    
    // MARK: - Placeholder Views
    private func placeholderView(for service: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: getIconName(for: service))
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("\(service) - Prossimamente")
                .font(.title)
                .fontWeight(.medium)
            
            Text("Questa funzionalità sarà disponibile in una versione futura")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.textBackgroundColor))
    }
    
    private func getIconName(for service: String) -> String {
        switch service {
        case "WhatsApp": return "message.circle"
        case "Telegram": return "paperplane.circle"
        case "Chiamate": return "phone.circle"
        case "Ibrida": return "bubble.left.and.bubble.right"
        case "Rubrica": return "person.2.circle"
        default: return "questionmark.circle"
        }
    }
    
    // MARK: - Action Handlers
    private func handleReply(_ email: Email) {
        ComposeEmailWindowManager.shared.openComposeEmail(mode: .reply(email))
    }
    
    private func handleReplyAll(_ email: Email) {
        ComposeEmailWindowManager.shared.openComposeEmail(mode: .replyAll(email))
    }
    
    private func handleForward(_ email: Email) {
        ComposeEmailWindowManager.shared.openComposeEmail(mode: .forward(email))
    }
    
    private func handleToggleRead(_ email: Email) {
        mailViewModel.toggleReadStatus(for: email.id)
    }
    
    private func handleNewEmail() {
        ComposeEmailWindowManager.shared.openComposeEmail(mode: .new())
    }
    
    private func handleCreateTask(_ email: Email) {
        taskEmail = email
        taskWhatsAppChat = nil
        taskWhatsAppMessage = nil
        showingCreateTask = true
    }
    
    private func handleCreateTaskFromWhatsApp(chat: WhatsAppChat, message: WhatsAppMessage? = nil) {
        taskEmail = nil
        taskWhatsAppChat = chat
        taskWhatsAppMessage = message
        showingCreateTask = true
    }
    
    private func handleAssociateClaim(_ email: Email) {
        emailToAssociate = email
        
        // Match esatti (immediato) - usa EmailAssociationService
        let exact = EmailAssociationService.shared.checkEmailAssociation(email, context: viewContext)
        suggestedSinistri = exact
        
        // Se ci sono più sinistri suggeriti, imposta lo stato "forse"
        if exact.count > 1 {
            print("[ComunicazioniView] ⚠️ Email \(email.id) ha \(exact.count) sinistri possibili")
        }
        
        showingAssociationPopover = true
        
        // Suggerimenti in background (non bloccante)
        Task {
            let suggestions = await mailViewModel.generateAssociationSuggestions(
                for: email,
                context: viewContext
            )
            // Aggiungi suggerimenti non già presenti
            await MainActor.run {
                let existingIds = Set(suggestedSinistri.map { $0.objectID })
                let newSuggestions = suggestions.filter { !existingIds.contains($0.objectID) }
                suggestedSinistri.append(contentsOf: newSuggestions)
            }
        }
    }
}

// MARK: - QR Code View
struct QRCodeView: View {
    let qrCode: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Scansiona il QR Code")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Apri WhatsApp sul tuo telefono e scansiona questo codice per collegare l'account")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // QR Code Image
            QRCodeImageView(qrCodeString: qrCode, size: 300)
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .shadow(radius: 4)
            
            Button("Chiudi") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(width: 450, height: 600)
    }
}

// MARK: - QR Code Overlay
struct QRCodeOverlay: View {
    let qrCode: String
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Collega WhatsApp")
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("Scansiona il QR Code con WhatsApp")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                
                QRCodeImageView(qrCodeString: qrCode, size: 300)
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 4)
                
                Button("Chiudi") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(40)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(16)
        }
    }
}

// MARK: - Resizable Divider
struct ResizableDivider: View {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double
    
    @State private var isDragging = false
    
    var body: some View {
        Rectangle()
            .fill(Color(.separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8) // Area di hit più ampia
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                width = max(minWidth, min(maxWidth, width + value.translation.width))
                            }
                    )
            )
            .background(
                isDragging ? Color.accentColor.opacity(0.3) : Color.clear
            )
    }
}

// MARK: - Email Toolbar
struct EmailToolbarView: View {
    let email: Email
    let viewModel: MailViewModel
    let onReply: () -> Void
    let onReplyAll: () -> Void
    let onForward: () -> Void
    let onToggleRead: () -> Void
    let onCreateTask: () -> Void
    let onAssociateClaim: () -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var appState: AppState
    @State private var associatedSinistri: [Sinistro] = []
    
    var body: some View {
        HStack(spacing: 12) {
            // Gruppo azioni email standard
            HStack(spacing: 8) {
                ToolbarButton(
                    icon: "arrowshape.turn.up.left",
                    title: "Rispondi",
                    action: onReply
                )
                
                ToolbarButton(
                    icon: "arrowshape.turn.up.left.2",
                    title: "Rispondi a tutti",
                    action: onReplyAll
                )
                
                ToolbarButton(
                    icon: "arrowshape.turn.up.right",
                    title: "Inoltra",
                    action: onForward
                )
            }
            
            Divider()
                .frame(height: 20)
            
            // Gruppo azioni stato
            HStack(spacing: 8) {
                ToolbarButton(
                    icon: email.isRead ? "envelope.badge" : "envelope.open",
                    title: email.isRead ? "Segna come non letta" : "Segna come letta",
                    action: onToggleRead
                )
            }
            
            Spacer()
            
            // Gruppo azioni app-specific
            HStack(spacing: 8) {
                ToolbarButton(
                    icon: "link",
                    title: "Associa Sinistro",
                    action: onAssociateClaim,
                    style: .accent
                )
                
                ToolbarButton(
                    icon: "checklist",
                    title: "Crea Task",
                    action: onCreateTask,
                    style: .accent
                )
                
                // Pulsante Apri Sinistro (se associato)
                if let firstSinistro = associatedSinistri.first {
                    Divider()
                        .frame(height: 20)
                    
                    Button {
                        appState.openSinistro(firstSinistro, openInNewWindow: true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                                .font(.system(size: 13, weight: .medium))
                            Text("Apri Sinistro")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            appState.openSinistro(firstSinistro, openInNewWindow: false)
                        } label: {
                            Label("Apri in questa finestra", systemImage: "rectangle.portrait")
                        }
                        
                        Button {
                            appState.openSinistro(firstSinistro, openInNewWindow: true)
                        } label: {
                            Label("Apri in nuova finestra", systemImage: "rectangle.portrait.on.rectangle.portrait")
                        }
                    }
                    
                    // Menu per altri sinistri se ce ne sono di più
                    if associatedSinistri.count > 1 {
                        Menu {
                            ForEach(Array(associatedSinistri.dropFirst()), id: \.objectID) { sinistro in
                                Button {
                                    appState.openSinistro(sinistro, openInNewWindow: true)
                                } label: {
                                    Label(sinistro.riferimentoVisualizzato, systemImage: "rectangle.portrait.on.rectangle.portrait")
                                }
                            }
                        } label: {
                            Text("+\(associatedSinistri.count - 1)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.controlColor))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.controlBackgroundColor))
        .onAppear {
            loadAssociatedSinistri()
        }
        .onChange(of: email.id) { _, _ in
            loadAssociatedSinistri()
        }
    }
    
    private func loadAssociatedSinistri() {
        // Cattura solo l'ID dell'email (Sendable)
        let emailId = email.id
        
        // Esegui il fetch in background per non bloccare la UI
        Task.detached(priority: .utility) {
            let context = PersistenceController.shared.container.newBackgroundContext()
            
            var threadObjectIDs: [NSManagedObjectID] = []
            
            context.performAndWait {
                // Non possiamo usare CONTAINS su campi Transformable, quindi facciamo fetch e filtriamo in memoria
                let fetchRequest = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
                
                do {
                    let threads = try context.fetch(fetchRequest)
                    
                    // Filtra in memoria usando messageIds (proprietà calcolata)
                    let matchingThreads = threads.filter { thread in
                        thread.messageIds.contains(emailId)
                    }
                    
                    // Estrai objectID dei thread (non dei sinistri, per evitare fault)
                    threadObjectIDs = matchingThreads.map { $0.objectID }
                } catch {
                    print("[EmailToolbarView] Errore fetch thread: \(error)")
                }
            }
            
            // Ora recupera i thread dal viewContext e poi i sinistri
            await MainActor.run {
                let viewContext = PersistenceController.shared.container.viewContext
                
                // Recupera i thread dal viewContext
                let threads = threadObjectIDs.compactMap { objectID in
                    try? viewContext.existingObject(with: objectID) as? SinistroEmailThread
                }
                
                // Estrai i sinistri dai thread (ora siamo sul main thread con viewContext)
                let sinistri = threads.compactMap { $0.sinistro }
                associatedSinistri = sinistri
            }
        }
    }
}

// MARK: - Toolbar Button
struct ToolbarButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    var style: ButtonStyle = .standard
    
    enum ButtonStyle {
        case standard
        case accent
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                style == .accent ? 
                Color.accentColor.opacity(0.1) : 
                Color(.controlColor)
            )
            .foregroundColor(
                style == .accent ? 
                Color.accentColor : 
                Color.primary
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

#Preview {
    ComunicazioniView()
} 
