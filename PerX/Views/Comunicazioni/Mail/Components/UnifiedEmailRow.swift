import SwiftUI
import CoreData

/// Row email unificata e configurabile
/// Sostituisce: MailboxEmailRow, CompactEmailRow, EmailRow, EmailBoxView
/// OTTIMIZZATO: Niente @ObservedObject globali per evitare re-render di massa
struct UnifiedEmailRow: View {
    
    // MARK: - Style Configuration
    
    enum Style {
        case compact      // Solo info essenziali (avatar, mittente, oggetto, data)
        case standard     // Compatto + anteprima contenuto
        case detailed     // Completo con toolbar azioni
    }
    
    // MARK: - Properties
    
    let email: Email
    let style: Style
    let isSelected: Bool
    let showToolbar: Bool
    let thread: SinistroEmailThread?
    
    // OTTIMIZZAZIONE: Dati pre-calcolati passati dalla vista padre
    // Evita accesso a ViewModel/Managers globali che causano re-render
    let isSentByUser: Bool
    let hasGeneratedTask: Bool
    
    // Callbacks
    var onSelect: (() -> Void)?
    var onReply: (() -> Void)?
    var onReplyAll: (() -> Void)?
    var onForward: (() -> Void)?
    var onToggleRead: (() -> Void)?
    var onAssociate: (() -> Void)?
    var onDisassociate: (() -> Void)?
    var onCreateTask: (() -> Void)?
    var onDownloadAttachment: ((EmailAttachment) -> Void)?
    
    // MARK: - State
    
    @State private var currentEmail: Email
    @State private var previewText: String?
    @State private var isGeneratingPreview = false
    @State private var showAllRecipients = false
    @State private var isSubjectExpanded = false
    @State private var isSentEmailRead: Bool?
    @State private var isLoadingBody = false
    @State private var bodyLoadTask: Task<Void, Never>?
    
    // MARK: - Computed Properties
    
    private var sinistro: Sinistro? {
        thread?.sinistro
    }
    
    private var sinistroStato: String? {
        guard let sinistro = sinistro, let stato = sinistro.stato else { return nil }
        return stato
    }
    
    private var sinistroStatoColor: Color {
        guard let statoString = sinistroStato,
              let stato = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == statoString }) else {
            return .secondary
        }
        return stato.color
    }
    
    // MARK: - Init
    
    init(
        email: Email,
        style: Style = .standard,
        isSelected: Bool = false,
        showToolbar: Bool = false,
        thread: SinistroEmailThread? = nil,
        isSentByUser: Bool = false,
        hasGeneratedTask: Bool = false,
        onSelect: (() -> Void)? = nil,
        onReply: (() -> Void)? = nil,
        onReplyAll: (() -> Void)? = nil,
        onForward: (() -> Void)? = nil,
        onToggleRead: (() -> Void)? = nil,
        onAssociate: (() -> Void)? = nil,
        onDisassociate: (() -> Void)? = nil,
        onCreateTask: (() -> Void)? = nil,
        onDownloadAttachment: ((EmailAttachment) -> Void)? = nil
    ) {
        self.email = email
        self.style = style
        self.isSelected = isSelected
        self.showToolbar = showToolbar
        self.thread = thread
        self.isSentByUser = isSentByUser
        self.hasGeneratedTask = hasGeneratedTask
        self.onSelect = onSelect
        self.onReply = onReply
        self.onReplyAll = onReplyAll
        self.onForward = onForward
        self.onToggleRead = onToggleRead
        self.onAssociate = onAssociate
        self.onDisassociate = onDisassociate
        self.onCreateTask = onCreateTask
        self.onDownloadAttachment = onDownloadAttachment
        self._currentEmail = State(initialValue: email)
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar (solo per style detailed e se abilitato)
            if showToolbar && style == .detailed {
                toolbarView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor).opacity(0.3))
                
                Divider()
            }
            
            // Contenuto principale
            mainContent
                .padding(.horizontal, style == .compact ? 10 : 12)
                .padding(.vertical, style == .compact ? 8 : 10)
            
            // Body email (solo per style detailed)
            if style == .detailed {
                Divider()
                emailBodyView
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            
            // Allegati (solo per style detailed)
            if style == .detailed, let attachments = currentEmail.attachments, !attachments.isEmpty {
                Divider()
                attachmentsView(attachments)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background(Color(.textBackgroundColor))
        .cornerRadius(style == .compact ? 6 : 8)
        .overlay(
            RoundedRectangle(cornerRadius: style == .compact ? 6 : 8)
                .stroke(isSelected ? Color.accentColor : Color(.separatorColor), lineWidth: isSelected ? (style == .compact ? 1.5 : 2) : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?()
        }
        .onAppear {
            loadCachedEmail()
            checkSentEmailReadStatus()
            if style == .standard {
                generatePreviewIfNeeded()
            }
        }
        .onChange(of: email) { _, newValue in
            currentEmail = newValue
            loadCachedEmail()
            checkSentEmailReadStatus()
            if style == .standard {
                previewText = nil
                generatePreviewIfNeeded()
            }
            // Reset body loading quando cambia email
            bodyLoadTask?.cancel()
            isLoadingBody = false
        }
        .task(id: currentEmail.id) {
            // Download body solo se necessario e non già in corso
            guard style == .detailed,
                  currentEmail.body == nil || currentEmail.body!.isEmpty,
                  !isLoadingBody else { return }
            
            isLoadingBody = true
            bodyLoadTask = Task {
                await loadEmailBody()
                isLoadingBody = false
            }
        }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        HStack(alignment: style == .compact ? .center : .top, spacing: 10) {
            // Indicatore non letta (solo compact)
            if style == .compact {
                Circle()
                    .fill(currentEmail.isRead ? Color.clear : Color.accentColor)
                    .frame(width: 8, height: 8)
            }
            
            // Avatar
            avatarView
            
            // Info email
            VStack(alignment: .leading, spacing: style == .compact ? 2 : 4) {
                // Riga 1: Mittente/Oggetto + Data
                headerRow
                
                // Riga 2: Destinatari o Mittente (dipende dallo style)
                if style != .compact {
                    senderRecipientRow
                }
                
                // Riga 3: Anteprima (solo standard) - Oggetto già in headerRow
                if style == .standard {
                    previewRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Indicatori (allegati, task, non letta)
            indicatorsView
        }
    }
    
    // MARK: - Avatar
    
    private var avatarView: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: style == .compact ? 28 : 32, height: style == .compact ? 28 : 32)
            .overlay(
                Text(EmailHelpers.initials(from: currentEmail.sender.displayName))
                    .font(.system(size: style == .compact ? 10 : 11, weight: .medium))
                    .foregroundColor(.accentColor)
            )
    }
    
    // MARK: - Header Row
    
    private var headerRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                // Per compact: mostra mittente, per altri: oggetto
                if style == .compact {
                    Text(currentEmail.sender.displayName)
                        .font(.system(size: 12, weight: currentEmail.isRead ? .regular : .semibold))
                        .foregroundColor(currentEmail.isRead ? .secondary : .primary)
                        .lineLimit(1)
                    
                    if isSentByUser {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        
                        // Indicatore lettura per email inviate (solo se il toggle è attivo)
                        if ReadReceiptSettings.shared.isEnabled, let isRead = isSentEmailRead {
                            Image(systemName: isRead ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 9))
                                .foregroundColor(isRead ? .green : .gray)
                                .help(isRead ? "Email letta dal destinatario" : "Email non letta")
                        }
                    }
                } else {
                    // Oggetto espandibile
                    subjectView
                }
                
                // Mostra stato sinistro se presente e email è nel thread
                if let stato = sinistroStato, let thread = thread, thread.messageIds.contains(currentEmail.id) {
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        if let statoEnum = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == stato }) {
                            Image(systemName: statoEnum.icon)
                                .font(.system(size: 9))
                                .foregroundColor(sinistroStatoColor)
                        }
                        Text(stato)
                            .font(.system(size: 11))
                            .foregroundColor(sinistroStatoColor)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            Text(EmailHelpers.formatDate(currentEmail.date))
                .font(.system(size: style == .compact ? 10 : 11))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Subject View (Espandibile)
    
    @ViewBuilder
    private var subjectView: some View {
        let subject = currentEmail.subject.isEmpty ? "(Nessun oggetto)" : currentEmail.subject
        let isLong = subject.count > 60 // Soglia per considerare "lungo"
        
        if isLong {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSubjectExpanded.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Text(subject)
                        .font(.system(size: 13, weight: currentEmail.isRead ? .regular : .semibold))
                        .foregroundColor(currentEmail.isRead ? .secondary : .primary)
                        .lineLimit(isSubjectExpanded ? nil : 1)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Image(systemName: isSubjectExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        } else {
            Text(subject)
                .font(.system(size: 13, weight: currentEmail.isRead ? .regular : .semibold))
                .foregroundColor(currentEmail.isRead ? .secondary : .primary)
                .lineLimit(1)
        }
    }
    
    // MARK: - Sender/Recipient Row
    
    private var senderRecipientRow: some View {
        HStack(spacing: 4) {
            Text(currentEmail.sender.displayName)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            if isSentByUser {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                
                // Indicatore lettura per email inviate (solo se il toggle è attivo)
                if ReadReceiptSettings.shared.isEnabled, let isRead = isSentEmailRead {
                    Image(systemName: isRead ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 9))
                        .foregroundColor(isRead ? .green : .gray)
                        .help(isRead ? "Email letta dal destinatario" : "Email non letta")
                }
            }
            
            if !currentEmail.recipients.isEmpty {
                Text("→")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if let first = currentEmail.recipients.first {
                    Text(first.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if currentEmail.recipients.count > 1 {
                    Text("e altri \(currentEmail.recipients.count - 1)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Subject Row
    
    private var subjectRow: some View {
        Text(currentEmail.subject.isEmpty ? "(Nessun oggetto)" : currentEmail.subject)
            .font(.system(size: style == .detailed ? 15 : 13, weight: currentEmail.isRead ? .regular : .medium))
            .foregroundColor(currentEmail.isRead ? .secondary : .primary)
            .lineLimit(2)
    }
    
    // MARK: - Preview Row
    
    @ViewBuilder
    private var previewRow: some View {
        if let preview = previewText {
            Text(preview)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)
        } else if isGeneratingPreview {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Caricamento...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Indicators
    
    private var indicatorsView: some View {
        HStack(spacing: 4) {
            // Tag categoria email (compatto)
            EmailCategoryTagCompact(emailId: currentEmail.id)
            
            // Task generato
            if hasGeneratedTask {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.caption2)
            }
            
            // Allegati
            if let attachments = currentEmail.attachments, !attachments.isEmpty {
                Image(systemName: "paperclip")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // Non letta (solo per style non compact)
            if style != .compact && !currentEmail.isRead {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    // MARK: - Toolbar View
    
    private var toolbarView: some View {
        HStack(spacing: 8) {
            Button(action: { onReply?() ?? defaultReply() }) {
                toolbarButton(icon: "arrowshape.turn.up.left", label: "Rispondi")
            }
            .buttonStyle(.plain)
            
            Button(action: { onReplyAll?() ?? defaultReplyAll() }) {
                toolbarButton(icon: "arrowshape.turn.up.left.2", label: "Rispondi a tutti")
            }
            .buttonStyle(.plain)
            
            Button(action: { onForward?() ?? defaultForward() }) {
                toolbarButton(icon: "arrowshape.turn.up.right", label: "Inoltra")
            }
            .buttonStyle(.plain)
            
            Divider().frame(height: 16)
            
            // Per mail inviate: mostra indicatore lettura invece del toggle
            if isSentByUser && ReadReceiptSettings.shared.isEnabled {
                // Mostra indicatore stato lettura per mail inviate
                if let isRead = isSentEmailRead {
                    HStack(spacing: 6) {
                        Image(systemName: isRead ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isRead ? .green : .gray)
                            .font(.system(size: 12))
                        Text(isRead ? "Letta" : "Non letta")
                            .font(.caption)
                            .foregroundColor(isRead ? .green : .gray)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.controlColor))
                    .cornerRadius(4)
                }
            } else if !isSentByUser {
                // Per mail ricevute: mostra toggle normale
                Button(action: { onToggleRead?() ?? defaultToggleRead() }) {
                    toolbarButton(
                        icon: currentEmail.isRead ? "envelope.badge" : "envelope.open",
                        label: currentEmail.isRead ? "Non letta" : "Letta"
                    )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Disassocia (solo se in un thread con sinistro)
            if let thread = thread, thread.sinistro != nil, thread.messageIds.contains(currentEmail.id) {
                Button(action: { onDisassociate?() }) {
                    toolbarButton(icon: "minus.circle", label: "Rimuovi", color: .orange)
                }
                .buttonStyle(.plain)
            } else {
                // Associa (solo se non associata)
                Button(action: { onAssociate?() }) {
                    toolbarButton(icon: "link", label: "Associa", color: .accentColor)
                }
                .buttonStyle(.plain)
            }
            
            // Task
            Button(action: { onCreateTask?() }) {
                toolbarButton(icon: "checklist", label: "Task", color: .purple)
            }
            .buttonStyle(.plain)
            
            Divider().frame(height: 16)
            
            // Tag categoria email (modificabile)
            EmailCategoryTagView(emailId: currentEmail.id)
        }
    }
    
    private func toolbarButton(icon: String, label: String, color: Color = Color(.controlTextColor)) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(label)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color == .accentColor || color == .orange || color == .purple ? color.opacity(0.15) : Color(.controlColor))
        .foregroundColor(color)
        .cornerRadius(4)
    }
    
    // MARK: - Email Body View
    
    // Stato per altezza dinamica WebView
    @State private var webViewHeight: CGFloat = 200
    
    @ViewBuilder
    private var emailBodyView: some View {
        if let body = currentEmail.body, !body.isEmpty {
            // Usa WebView per renderizzare HTML con stili corretti
            MailHTMLView(htmlString: body, dynamicHeight: $webViewHeight)
                .frame(height: max(webViewHeight, 100))
                .frame(maxWidth: .infinity)
        } else {
            // Caricamento in corso - il task è gestito a livello di body
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Download in corso...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Il contenuto verrà visualizzato non appena disponibile")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 100)
            .padding(.vertical, 20)
        }
    }
    
    // MARK: - Attachments View
    
    private func attachmentsView(_ attachments: [EmailAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Allegati (\(attachments.count))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150, maximum: 250), spacing: 8)
            ], spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentCardView(attachment: attachment) {
                        onDownloadAttachment?(attachment)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadCachedEmail() {
        if let cached = EmailRepository.shared.getEmail(byId: currentEmail.id) {
            currentEmail = cached
        }
    }
    
    private func checkSentEmailReadStatus() {
        guard isSentByUser else {
            isSentEmailRead = nil
            return
        }
        
        // Verifica se l'email è nella mailbox SENT
        let mailboxId = EmailRepository.shared.getMailbox(forEmailId: currentEmail.id)
        if mailboxId == "SENT" {
            // Per email inviate: isRead == true significa che è stata letta dal destinatario
            isSentEmailRead = currentEmail.isRead
        } else {
            isSentEmailRead = nil
        }
    }
    
    private func generatePreviewIfNeeded() {
        guard previewText == nil, !isGeneratingPreview else { return }
        
        if let body = currentEmail.body, !body.isEmpty {
            previewText = EmailHelpers.generatePreview(from: body)
        } else {
            isGeneratingPreview = true
            Task(priority: .utility) {
                // Prova dal repository (in memoria)
                let cachedFromRepo = await MainActor.run { EmailRepository.shared.getEmail(byId: currentEmail.id) }
                if let cached = cachedFromRepo, let body = cached.body, !body.isEmpty {
                    await MainActor.run {
                        currentEmail = cached
                        previewText = EmailHelpers.generatePreview(from: body)
                        isGeneratingPreview = false
                    }
                    return
                }
                
                // Avvia download con priorità bassa (accesso diretto statico)
                await MailViewModel.shared.fetchFullEmail(for: currentEmail.id)
                
                var attempts = 0
                while attempts < 10 {
                    await Task.yield()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    
                    // Verifica aggiornamento nel repository
                    let updatedFromRepo = await MainActor.run { EmailRepository.shared.getEmail(byId: currentEmail.id) }
                    if let cached = updatedFromRepo, let body = cached.body, !body.isEmpty {
                        await MainActor.run {
                            currentEmail = cached
                            previewText = EmailHelpers.generatePreview(from: body)
                            isGeneratingPreview = false
                        }
                        return
                    }
                    
                    attempts += 1
                }
                
                await MainActor.run {
                    isGeneratingPreview = false
                }
            }
        }
    }
    
    private func loadEmailBody() async {
        // Prova dal repository
        if let updated = EmailRepository.shared.getEmail(byId: currentEmail.id),
           updated.body != nil {
            await MainActor.run {
                currentEmail = updated
            }
            return
        }
        
        // Richiedi download prioritario (l'utente sta visualizzando questa email)
        await EmailQueueService.shared.prioritizeEmail(currentEmail.id)
        
        let maxAttempts = 20
        var attempt = 0
        var delay: UInt64 = 200_000_000
        
        while attempt < maxAttempts {
            await Task.yield()
            try? await Task.sleep(nanoseconds: delay)
            attempt += 1
            
            if let updated = EmailRepository.shared.getEmail(byId: currentEmail.id),
               updated.body != nil {
                await MainActor.run {
                    currentEmail = updated
                }
                return
            }
            
            delay = min(delay + 50_000_000, 1_000_000_000)
        }
    }
    
    // MARK: - Default Actions
    
    private func defaultReply() {
        ComposeEmailWindowManager.shared.openComposeEmail(mode: .reply(currentEmail))
    }
    
    private func defaultReplyAll() {
        ComposeEmailWindowManager.shared.openComposeEmail(mode: .replyAll(currentEmail))
    }
    
    private func defaultForward() {
        ComposeEmailWindowManager.shared.openComposeEmail(mode: .forward(currentEmail))
    }
    
    private func defaultToggleRead() {
        // Accesso statico invece di @ObservedObject
        MailViewModel.shared.toggleReadStatus(for: currentEmail.id)
    }
}

// MARK: - Helpers per chiamate ottimizzate

extension UnifiedEmailRow {
    /// Helper per calcolare isSentByUser senza accedere a singleton ogni volta
    static func checkIsSentByUser(email: Email) -> Bool {
        guard let userEmail = GoogleAuthService.shared.userEmail?.lowercased() else { return false }
        return email.sender.email.lowercased() == userEmail
    }
    
    /// Helper per verificare se un task è stato generato per questa email
    static func checkHasGeneratedTask(emailId: String) -> Bool {
        TaskManager.shared.tasks.contains { $0.metadata["originalEmailId"]?.value as? String == emailId }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        UnifiedEmailRow(
            email: Email(
                id: "1",
                isRead: false,
                isDownloaded: true,
                sender: Contact(name: "Mario Rossi", email: "mario@test.com"),
                recipients: [Contact(name: "Test User", email: "test@test.com")],
                cc: nil,
                subject: "Test Email Subject",
                date: Date(),
                body: "Questo è il contenuto della mail di test.",
                attachments: nil,
                claimNumber: nil,
                insuredName: nil,
                associationStatus: nil
            ),
            style: .compact,
            isSelected: false
        )
        
        UnifiedEmailRow(
            email: Email(
                id: "2",
                isRead: true,
                isDownloaded: true,
                sender: Contact(name: "Luigi Verdi", email: "luigi@test.com"),
                recipients: [Contact(name: "Test User", email: "test@test.com")],
                cc: nil,
                subject: "Another Test Email",
                date: Date().addingTimeInterval(-3600),
                body: "Contenuto più lungo per testare l'anteprima del messaggio.",
                attachments: nil,
                claimNumber: nil,
                insuredName: nil,
                associationStatus: nil
            ),
            style: .standard,
            isSelected: true
        )
    }
    .padding()
}
