import SwiftUI
import CoreData

struct EmailThreadView: View {
    @ObservedObject var mailViewModel: MailViewModel
    @ObservedObject var principaleViewModel: PrincipaleViewModel
    
    // Thread opzionale - se nil, mostra solo la singola email
    let thread: SinistroEmailThread?
    // Email singola opzionale - usata quando non c'è un thread
    let singleEmail: Email?
    
    @State private var conversationSummary: String?
    @State private var isGeneratingSummary = false
    @State private var removingEmailIds: Set<String> = []
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var appState = AppState.shared
    
    private let disassociationService = EmailDisassociationService.shared
    private let threadCustomizationService = ThreadCustomizationService.shared
    
    // Callbacks per azioni toolbar (usati per email singola senza thread)
    var onReply: ((Email) -> Void)?
    var onReplyAll: ((Email) -> Void)?
    var onForward: ((Email) -> Void)?
    var onToggleRead: ((Email) -> Void)?
    var onCreateTask: ((Email) -> Void)?
    var onAssociateClaim: ((Email) -> Void)?
    
    /// Inizializzatore per thread completo
    init(mailViewModel: MailViewModel, principaleViewModel: PrincipaleViewModel, thread: SinistroEmailThread) {
        self.mailViewModel = mailViewModel
        self.principaleViewModel = principaleViewModel
        self.thread = thread
        self.singleEmail = nil
    }
    
    /// Inizializzatore per singola email (senza thread)
    init(
        mailViewModel: MailViewModel,
        principaleViewModel: PrincipaleViewModel,
        email: Email,
        onReply: ((Email) -> Void)? = nil,
        onReplyAll: ((Email) -> Void)? = nil,
        onForward: ((Email) -> Void)? = nil,
        onToggleRead: ((Email) -> Void)? = nil,
        onCreateTask: ((Email) -> Void)? = nil,
        onAssociateClaim: ((Email) -> Void)? = nil
    ) {
        self.mailViewModel = mailViewModel
        self.principaleViewModel = principaleViewModel
        self.thread = nil
        self.singleEmail = email
        self.onReply = onReply
        self.onReplyAll = onReplyAll
        self.onForward = onForward
        self.onToggleRead = onToggleRead
        self.onCreateTask = onCreateTask
        self.onAssociateClaim = onAssociateClaim
    }
    
    /// Verifica se il contenuto delle email è sufficiente per generare un riassunto (>= 100 caratteri)
    private var canShowSummary: Bool {
        guard let thread = thread else { return false }
        let emails = principaleViewModel.emails(for: thread)
        return ThreadSummaryCache.shared.canSummarize(emails: emails)
    }
    
    /// Email da mostrare (dal thread o singola)
    private var displayEmails: [Email] {
        if let thread = thread {
            let allEmails = principaleViewModel.emails(for: thread)
            return allEmails.filter { email in
                (!threadCustomizationService.isEmailExcluded(emailId: email.id) || thread.messageIds.contains(email.id)) &&
                !removingEmailIds.contains(email.id)
            }.sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
        } else if let email = singleEmail {
            return [email]
        }
        return []
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header (thread o email singola)
                headerView
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color(.textBackgroundColor))
                
                Divider()
                
                // Lista email
                let emails = displayEmails
                
                VStack(spacing: 12) {
                    ForEach(Array(emails.enumerated()), id: \.element.id) { index, email in
                        UnifiedEmailRow(
                            email: email,
                            style: .detailed,
                            isSelected: false,
                            showToolbar: true,
                            thread: thread,
                            isSentByUser: UnifiedEmailRow.checkIsSentByUser(email: email),
                            onReply: { handleReply(email) },
                            onReplyAll: { handleReplyAll(email) },
                            onForward: { handleForward(email) },
                            onToggleRead: { handleToggleRead(email) },
                            onAssociate: { handleAssociateSinistro(email) },
                            onDisassociate: { handleDisassociateSinistro(email) }
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, index == 0 ? 16 : 0)
                        .padding(.bottom, index == emails.count - 1 ? 16 : 0)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    }
                }
                .padding(.vertical, 8)
                .animation(.easeOut(duration: 0.3), value: emails.count)
                .animation(.easeOut(duration: 0.3), value: removingEmailIds)
            }
        }
        .background(Color(.textBackgroundColor))
        .onChange(of: thread?.id) { _, _ in
            conversationSummary = nil
            isGeneratingSummary = false
        }
    }
    
    // MARK: - Header View (Thread o Email singola)
    @ViewBuilder
    private var headerView: some View {
        if let thread = thread {
            threadHeaderView(thread: thread)
        } else if let email = singleEmail {
            singleEmailHeaderView(email: email)
        }
    }
    
    // MARK: - Single Email Header
    private func singleEmailHeaderView(email: Email) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(email.subject.isEmpty ? "(Nessun oggetto)" : email.subject)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "envelope")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Text("Email singola")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Toolbar azioni (per email singola)
                HStack(spacing: 8) {
                    if let onAssociate = onAssociateClaim {
                        Button {
                            onAssociate(email)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text("Associa Sinistro")
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if let onCreateTask = onCreateTask {
                        Button {
                            onCreateTask(email)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checklist")
                                Text("Crea Task")
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    // MARK: - Thread Header
    private func threadHeaderView(thread: SinistroEmailThread) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Info sinistro o thread personalizzato
            if let sinistro = thread.sinistro {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundColor(.accentColor)
                                .font(.subheadline)
                            
                            Text(sinistro.numeroSinistroCompagnia ?? "N/A")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        
                        Text("Rif: \(sinistro.riferimentoVisualizzato)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if let nomeAssicurato = sinistro.nomeAssicurato {
                            Text(nomeAssicurato)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        saveCurrentPosition()
                        appState.openSinistro(sinistro, openInNewWindow: true)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                            Text("Apri Sinistro")
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            saveCurrentPosition()
                            appState.openSinistro(sinistro, openInNewWindow: false)
                        } label: {
                            Label("Apri in questa finestra", systemImage: "rectangle.portrait")
                        }
                        
                        Button {
                            saveCurrentPosition()
                            appState.openSinistro(sinistro, openInNewWindow: true)
                        } label: {
                            Label("Apri in nuova finestra", systemImage: "rectangle.portrait.on.rectangle.portrait")
                        }
                    }
                }
            } else if let customName = threadCustomizationService.getCustomThreadName(threadId: thread.wrappedId) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundColor(.accentColor)
                                .font(.subheadline)
                            
                            Text(customName)
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        
                        Text("Thread personalizzato")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            } else {
                HStack {
                    Text("Sinistro non associato")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            
            // Statistiche thread
            HStack(spacing: 16) {
                let unreadCount = principaleViewModel.unreadCount(for: thread)
                if unreadCount > 0 {
                    Label("\(unreadCount) non letta\(unreadCount == 1 ? "" : "e")", systemImage: "envelope.badge")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                
                Label("\(thread.messageIds.count) email", systemImage: "envelope")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Riassunto conversazione
            summarySectionView(thread: thread)
        }
    }
    
    @ViewBuilder
    private func summarySectionView(thread: SinistroEmailThread) -> some View {
        // Non mostrare nulla se il contenuto è troppo corto per un riassunto
        if !canShowSummary {
            EmptyView()
        } else if let summary = conversationSummary {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                    
                    Text("Riassunto conversazioni")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                Text(summary)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .padding(.leading, 20)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        } else if isGeneratingSummary {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                
                Text("Generazione riassunto...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        } else {
            Button(action: { generateSummary(thread: thread) }) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                    
                    Text("Riassumi conversazioni")
                        .font(.caption)
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Helpers
    
    private func saveCurrentPosition() {
        guard let thread = thread else { return }
        UserDefaults.standard.set(thread.wrappedId.uuidString, forKey: "lastViewedThreadId")
    }
    
    private func generateSummary(thread: SinistroEmailThread) {
        isGeneratingSummary = true
        
        Task {
            let emails = principaleViewModel.emails(for: thread)
                .sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
            
            var summary = ""
            var participants: Set<String> = []
            var keyActions: [String] = []
            var dates: [Date] = []
            
            for email in emails.prefix(15) {
                participants.insert(email.sender.displayName)
                dates.append(email.date)
                
                if let body = email.body {
                    let (mainBody, _) = EmailHelpers.extractQuote(from: body)
                    let cleanBody = EmailHelpers.cleanHTMLBody(mainBody)
                    
                    let sentences = cleanBody.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { $0.count > 30 && $0.count < 150 && !$0.contains("<") }
                    
                    if let firstSentence = sentences.first, !keyActions.contains(firstSentence) {
                        keyActions.append("• \(firstSentence)")
                    }
                }
            }
            
            if !participants.isEmpty {
                summary = "Partecipanti: \(participants.joined(separator: ", "))\n\n"
            }
            
            if let firstDate = dates.first, let lastDate = dates.last {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                summary += "Periodo: \(formatter.string(from: firstDate)) - \(formatter.string(from: lastDate))\n\n"
            }
            
            if !keyActions.isEmpty {
                summary += "Punti salienti:\n\(keyActions.prefix(8).joined(separator: "\n"))"
            }
            
            await MainActor.run {
                conversationSummary = summary.isEmpty ? nil : summary
                isGeneratingSummary = false
            }
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleReply(_ email: Email) {
        if let callback = onReply {
            callback(email)
        } else {
            ComposeEmailWindowManager.shared.openComposeEmail(mode: .reply(email))
        }
    }
    
    private func handleReplyAll(_ email: Email) {
        if let callback = onReplyAll {
            callback(email)
        } else {
            ComposeEmailWindowManager.shared.openComposeEmail(mode: .replyAll(email))
        }
    }
    
    private func handleForward(_ email: Email) {
        if let callback = onForward {
            callback(email)
        } else {
            ComposeEmailWindowManager.shared.openComposeEmail(mode: .forward(email))
        }
    }
    
    private func handleToggleRead(_ email: Email) {
        if let callback = onToggleRead {
            callback(email)
        } else {
            mailViewModel.toggleReadStatus(for: email.id)
        }
    }
    
    private func handleAssociateSinistro(_ email: Email) {
        if let callback = onAssociateClaim {
            callback(email)
        } else {
            print("Associate sinistro for: \(email.subject)")
        }
    }
    
    private func handleDisassociateSinistro(_ email: Email) {
        guard let thread = thread, let sinistro = thread.sinistro else { return }
        
        removingEmailIds.insert(email.id)
        
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            await MainActor.run {
                let sinistroId = sinistro.objectID.uriRepresentation().absoluteString
                
                disassociationService.markAsDisassociated(emailId: email.id, sinistroId: sinistroId)
                
                thread.removeEmailMessageId(email.id)
                thread.dataUltimaModifica = Date()
                
                do {
                    try viewContext.save()
                    print("[EmailThreadView] ✅ Email \(email.id) disassociata")
                } catch {
                    print("[EmailThreadView] ❌ Errore disassociazione: \(error)")
                }
                
                removingEmailIds.remove(email.id)
            }
        }
    }
}
