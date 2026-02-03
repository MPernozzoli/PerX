import SwiftUI

struct MailDetailView: View {
    @ObservedObject var viewModel: MailViewModel
    let email: Email
    
    @State private var selectedContact: Contact?
    @State private var showContactModal = false
    @State private var webViewHeight: CGFloat = .zero
    @State private var showAllRecipients = false
    @State private var currentEmail: Email
    @State private var isSubjectExpanded = false
    @State private var isSentEmailRead: Bool?
    @State private var isLoadingBody = false
    @StateObject private var taskManager = TaskManager.shared
    
    init(viewModel: MailViewModel, email: Email) {
        self.viewModel = viewModel
        self.email = email
        self._currentEmail = State(initialValue: email)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                
                // --- HEADER EMAIL ---
                emailHeaderView
                
                Divider()
                
                // --- CORPO EMAIL ---
                emailBodyView
                
                // --- TASK ASSOCIATE ---
                if !emailTasks.isEmpty {
                    emailTasksView
                }
                
                // --- ALLEGATI ---
                if let attachments = currentEmail.attachments, !attachments.isEmpty {
                    attachmentsView(attachments)
                }
            }
        }
        .background(Color(.textBackgroundColor))
        .sheet(isPresented: $showContactModal) {
            if let contact = selectedContact {
                ContactDetailView(contact: contact)
            }
        }
        .onAppear {
            checkForCachedEmail()
            checkSentEmailReadStatus()
        }
        .onChange(of: email) { oldValue, newValue in
            currentEmail = newValue
            checkForCachedEmail()
            checkSentEmailReadStatus()
            // Reset body loading quando cambia email
            isLoadingBody = false
        }
        .task(id: currentEmail.id) {
            // Download body solo se necessario e non già in corso
            guard currentEmail.body == nil || currentEmail.body!.isEmpty,
                  !isLoadingBody else { return }
            
            isLoadingBody = true
            await loadEmailBody()
            isLoadingBody = false
        }
    }
    
    // MARK: - Email Header
    private var emailHeaderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Riga oggetto + tag categoria
            HStack(alignment: .top, spacing: 12) {
                // Oggetto email (espandibile)
                subjectView
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                // Tag categoria email (modificabile)
                EmailCategoryTagView(emailId: currentEmail.id)
            }
            
            // Metadati email compatti
            VStack(alignment: .leading, spacing: 6) {
                // Prima riga: Mittente e Data sulla stessa riga
                HStack(alignment: .top, spacing: 8) {
                    emailMetadataRowCompact(
                        label: "Da:",
                        content: {
                            HStack(spacing: 6) {
                                MailContactPillView(
                                    contact: currentEmail.sender,
                                    onSelect: handleContactSelection
                                )
                                
                                // Indicatore email inviata
                                if isEmailSentByUser() {
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                    
                                    // Indicatore lettura per email inviate (solo se il toggle è attivo)
                                    if ReadReceiptSettings.shared.isEnabled, let isRead = isSentEmailRead {
                                        Image(systemName: isRead ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 10))
                                            .foregroundColor(isRead ? .green : .gray)
                                            .help(isRead ? "Email letta dal destinatario" : "Email non letta")
                                    }
                                }
                            }
                        }
                    )
                    
                    Spacer()
                    
                    // Data sulla stessa riga
                    Text(currentEmail.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Destinatari (solo se presente)
                if !currentEmail.recipients.isEmpty {
                    emailMetadataRowCompact(
                        label: "A:",
                        content: {
                            recipientsViewCompact
                        }
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Subject View (Espandibile)
    
    @ViewBuilder
    private var subjectView: some View {
        let subject = currentEmail.subject.isEmpty ? "(Nessun oggetto)" : currentEmail.subject
        let isLong = subject.count > 80 // Soglia per considerare "lungo"
        
        if isLong {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSubjectExpanded.toggle()
                }
            }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subject)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .textSelection(.enabled)
                        .lineLimit(isSubjectExpanded ? nil : 2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack {
                        Text(isSubjectExpanded ? "Mostra meno" : "Mostra tutto")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        
                        Image(systemName: isSubjectExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            Text(subject)
                .font(.title3)
                .fontWeight(.semibold)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.tail)
        }
    }
    
    // MARK: - Email Metadata Row
    private func emailMetadataRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Email Metadata Row Compact
    private func emailMetadataRowCompact<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .leading)
            
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Recipients View
    private var recipientsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Pills dei destinatari
            FlowLayout(spacing: 6) {
                if showAllRecipients {
                    ForEach(currentEmail.recipients) { recipient in
                        MailContactPillView(
                            contact: recipient,
                            onSelect: handleContactSelection
                        )
                    }
                } else {
                    if let first = currentEmail.recipients.first {
                        MailContactPillView(
                            contact: first,
                            onSelect: handleContactSelection
                        )
                        
                        if currentEmail.recipients.count > 1 {
                            Text("e altri \(currentEmail.recipients.count - 1)...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
            
            // Toggle per mostrare tutti i destinatari
            if currentEmail.recipients.count > 1 {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAllRecipients.toggle()
                    }
                }) {
                    Text(showAllRecipients ? "Nascondi" : "Mostra tutti")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Recipients View Compact
    private var recipientsViewCompact: some View {
        FlowLayout(spacing: 4) {
            if showAllRecipients {
                ForEach(currentEmail.recipients.prefix(3)) { recipient in
                    MailContactPillView(
                        contact: recipient,
                        onSelect: handleContactSelection
                    )
                }
                if currentEmail.recipients.count > 3 {
                    Text("e altri \(currentEmail.recipients.count - 3)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                if let first = currentEmail.recipients.first {
                    MailContactPillView(
                        contact: first,
                        onSelect: handleContactSelection
                    )
                    
                    if currentEmail.recipients.count > 1 {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAllRecipients.toggle()
                            }
                        }) {
                            Text("+\(currentEmail.recipients.count - 1)")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    // MARK: - Email Body
    private var emailBodyView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Contenuto
            if let body = currentEmail.body, !body.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    MailHTMLView(htmlString: body, dynamicHeight: $webViewHeight)
                        .frame(height: min(max(webViewHeight, 100), 2000)) // Limite massimo 2000px
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Task associate (se presenti) - dentro lo stesso container
                    if !emailTasks.isEmpty {
                        Divider()
                            .padding(.vertical, 12)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(emailTasks) { task in
                                TaskAttachmentView(
                                    task: task,
                                    onEdit: nil
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            } else {
                // Mostra placeholder invece di bloccare
                placeholderView
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Email Tasks
    private var emailTasks: [DailyTask] {
        taskManager.tasks.filter { task in
            task.metadata["originalEmailId"]?.value as? String == currentEmail.id
        }
    }
    
    private var emailTasksView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(emailTasks) { task in
                    TaskAttachmentView(
                        task: task,
                        onEdit: nil
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Placeholder View
    private var placeholderView: some View {
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
        .padding(.horizontal, 20)
        // Il task è gestito a livello di body per evitare loop di pubblicazione
    }
    
    // MARK: - Attachments View
    private func attachmentsView(_ attachments: [EmailAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Separatore
            Rectangle()
                .fill(Color(.separatorColor))
                .frame(height: 1)
                .padding(.vertical, 8)
            
            // Header allegati
            HStack {
                Image(systemName: "paperclip")
                    .foregroundColor(.secondary)
                
                Text("Allegati (\(attachments.count))")
                    .font(.headline)
                    .fontWeight(.medium)
            }
            
            // Lista allegati
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)
            ], spacing: 12) {
                ForEach(attachments) { attachment in
                    AttachmentCardView(attachment: attachment) {
                        Task {
                            try? await viewModel.downloadAndOpen(
                                attachment: attachment,
                                messageId: currentEmail.id
                            )
                        }
                    }
                }
            }
        }
        .padding(.top, 16)
    }
    
    // MARK: - Helper Methods
    private func checkForCachedEmail() {
        // Legge dal repository (in memoria) senza toccare cache legacy direttamente
        if let cachedEmail = EmailRepository.shared.getEmail(byId: currentEmail.id) {
            currentEmail = cachedEmail
        }
    }
    
    private func isEmailSentByUser() -> Bool {
        guard let userEmail = GoogleAuthService.shared.userEmail?.lowercased() else {
            return false
        }
        return currentEmail.sender.email.lowercased() == userEmail
    }
    
    private func checkSentEmailReadStatus() {
        guard isEmailSentByUser() else {
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
    
    private func loadEmailBody() async {
        // Se già ha il corpo, non fare nulla
        if currentEmail.body != nil && !currentEmail.body!.isEmpty {
            return
        }
        
        // Avvia download con priorità alta
        await viewModel.fetchFullEmail(for: currentEmail.id)
        
        // Polling più efficiente con yield per non bloccare
        let maxAttempts = 30
        var attempt = 0
        var delay: UInt64 = 200_000_000 // 200ms
        
        while attempt < maxAttempts {
            await Task.yield() // Permette all'app di respirare
            try? await Task.sleep(nanoseconds: delay)
            attempt += 1
            
            // Controlla se l'email è stata aggiornata nel repository
            if let updatedEmail = EmailRepository.shared.getEmail(byId: currentEmail.id),
               let body = updatedEmail.body, !body.isEmpty {
                await MainActor.run {
                    currentEmail = updatedEmail
                }
                return
            }
            
            // Aumenta il delay gradualmente (max 1 secondo)
            delay = min(delay + 50_000_000, 1_000_000_000)
        }
    }
    
    private func handleContactSelection(_ contact: Contact) {
        selectedContact = contact
        showContactModal = true
    }
}

// MARK: - Flow Layout per Pills
struct FlowLayout: Layout {
    let spacing: CGFloat
    
    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        
        for (index, subview) in subviews.enumerated() {
            subview.place(at: result.positions[index], proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        let size: CGSize
        let positions: [CGPoint]
        
        init(in maxWidth: CGFloat, subviews: LayoutSubviews, spacing: CGFloat) {
            var positions: [CGPoint] = []
            var currentPosition = CGPoint.zero
            var lineHeight: CGFloat = 0
            var maxY: CGFloat = 0
            
            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)
                
                if currentPosition.x + subviewSize.width > maxWidth && currentPosition.x > 0 {
                    // Nuova riga
                    currentPosition.x = 0
                    currentPosition.y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(currentPosition)
                currentPosition.x += subviewSize.width + spacing
                lineHeight = max(lineHeight, subviewSize.height)
                maxY = max(maxY, currentPosition.y + subviewSize.height)
            }
            
            self.positions = positions
            self.size = CGSize(width: maxWidth, height: maxY)
        }
    }
}

// MARK: - Contact Pill (Migliorata)
struct MailContactPillView: View {
    let contact: Contact
    let onSelect: (Contact) -> Void

    var body: some View {
        Button(action: { onSelect(contact) }) {
            Text(contact.displayName)
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.controlColor))
                .foregroundColor(.primary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separatorColor), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(contact.email)
    }
}

// MARK: - Attachment Card
struct AttachmentCardView: View {
    let attachment: EmailAttachment
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icona file
                Image(systemName: getFileIcon(for: attachment.filename))
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 32)
                
                // Info file
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text(formattedSize(attachment.size))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Icona download
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func getFileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.text.fill"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx": return "tablecells"
        case "jpg", "jpeg", "png", "gif": return "photo"
        case "zip", "rar": return "archivebox"
        default: return "doc"
        }
    }

    private func formattedSize(_ size: Int) -> String {
        FileSizeFormatter.format(size)
    }
} 