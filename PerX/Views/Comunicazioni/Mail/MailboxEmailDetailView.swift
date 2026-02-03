import SwiftUI
import CoreData

/// Vista dettaglio email singola dalle caselle - unificata con la vista thread
struct MailboxEmailDetailView: View {
    let email: Email
    @ObservedObject var viewModel: MailViewModel
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var appState: AppState
    
    @State private var currentEmail: Email
    @State private var showingAssociationPopover = false
    @State private var suggestedSinistri: [Sinistro] = []
    @State private var associatedSinistri: [Sinistro] = []
    @State private var associatedThread: SinistroEmailThread?
    @State private var showingTaskPopover = false
    
    init(email: Email, viewModel: MailViewModel) {
        self.email = email
        self.viewModel = viewModel
        self._currentEmail = State(initialValue: email)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header con informazioni sinistro (se associato) - stile thread
                if let sinistro = associatedSinistri.first {
                    sinistroHeaderView(sinistro)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(Color(.textBackgroundColor))
                    
                    Divider()
                } else {
                    // Header senza associazione
                    noAssociationHeaderView
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(.textBackgroundColor))
                    
                    Divider()
                }
                
                // Email singola - usa UnifiedEmailRow come nei thread
                VStack(spacing: 12) {
                    UnifiedEmailRow(
                        email: currentEmail,
                        style: .detailed,
                        isSelected: false,
                        showToolbar: true,
                        thread: associatedThread,
                        isSentByUser: UnifiedEmailRow.checkIsSentByUser(email: currentEmail),
                        onReply: { handleReply() },
                        onReplyAll: { handleReplyAll() },
                        onForward: { handleForward() },
                        onToggleRead: { handleToggleRead() },
                        onAssociate: { handleAssociateSinistro() },
                        onDisassociate: { handleDisassociateSinistro() }
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color(.textBackgroundColor))
        .onAppear {
            checkForCachedEmail()
            loadAssociatedSinistri()
            requestPriorityDownload()
        }
        .onChange(of: email) { oldValue, newValue in
            currentEmail = newValue
            checkForCachedEmail()
            loadAssociatedSinistri()
            requestPriorityDownload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .emailAssociated)) { notification in
            // Aggiorna l'UI quando viene creata un'associazione
            if let emailId = notification.userInfo?["emailId"] as? String,
               emailId == currentEmail.id {
                loadAssociatedSinistri()
                print("[MailboxEmailDetailView] 🔄 UI aggiornata dopo associazione email \(emailId)")
            }
        }
        .popover(isPresented: $showingAssociationPopover, attachmentAnchor: .point(.top)) {
            EmailAssociationPopover(
                email: currentEmail,
                suggestedSinistri: suggestedSinistri,
                onAssociate: { sinistri in
                    Task {
                        await EmailAssociationService.shared.associateEmailToSinistri(currentEmail, sinistri: sinistri, context: viewContext)
                        loadAssociatedSinistri()
                    }
                }
            )
        }
    }
    
    // MARK: - Sinistro Header (come in EmailThreadView)
    
    private func sinistroHeaderView(_ sinistro: Sinistro) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.accentColor)
                        .font(.subheadline)
                    
                    Text(sinistro.numeroSinistroCompagnia ?? "N/A")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    // Stato sinistro
                    if let stato = sinistro.stato {
                        Text(stato)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(statoColor(stato).opacity(0.15))
                            .foregroundColor(statoColor(stato))
                            .cornerRadius(4)
                    }
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
            
            // Pulsanti azione
            HStack(spacing: 8) {
                Button {
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
                        appState.openSinistro(sinistro, openInNewWindow: false)
                    } label: {
                        Label("Apri in questa finestra", systemImage: "rectangle.portrait")
                    }
                    
                    Button {
                        appState.openSinistro(sinistro, openInNewWindow: true)
                    } label: {
                        Label("Apri in nuova finestra", systemImage: "rectangle.portrait.on.rectangle.portrait")
                    }
                }
            }
        }
    }
    
    // MARK: - No Association Header
    
    private var noAssociationHeaderView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(currentEmail.subject.isEmpty ? "(Nessun oggetto)" : currentEmail.subject)
                    .font(.headline)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Image(systemName: "envelope")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Text("1 email")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Pulsante associa
            Button {
                handleAssociateSinistro()
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
    }
    
    // MARK: - Actions
    
    private func handleReply() {
        ComposeEmailWindowManager.shared.openComposeEmail(mode: .reply(currentEmail))
    }
    
    private func handleReplyAll() {
        ComposeEmailWindowManager.shared.openComposeEmail(mode: .replyAll(currentEmail))
    }
    
    private func handleForward() {
        ComposeEmailWindowManager.shared.openComposeEmail(mode: .forward(currentEmail))
    }
    
    private func handleToggleRead() {
        viewModel.toggleReadStatus(for: currentEmail.id)
    }
    
    private func handleAssociateSinistro() {
        let exact = EmailAssociationService.shared.checkEmailAssociation(currentEmail, context: viewContext)
        suggestedSinistri = exact
        showingAssociationPopover = true
        
        Task {
            let suggestions = await viewModel.generateAssociationSuggestions(
                for: currentEmail,
                context: viewContext
            )
            await MainActor.run {
                let existingIds = Set(suggestedSinistri.map { $0.objectID })
                let newSuggestions = suggestions.filter { !existingIds.contains($0.objectID) }
                suggestedSinistri.append(contentsOf: newSuggestions)
            }
        }
    }
    
    private func handleDisassociateSinistro() {
        guard let thread = associatedThread else { return }
        
        thread.removeEmailMessageId(currentEmail.id)
        thread.dataUltimaModifica = Date()
        
        do {
            try viewContext.save()
            loadAssociatedSinistri()
        } catch {
            print("[MailboxEmailDetailView] Errore disassociazione: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func checkForCachedEmail() {
        if let cachedEmail = EmailRepository.shared.getEmail(byId: currentEmail.id) {
            currentEmail = cachedEmail
        }
    }
    
    private func loadAssociatedSinistri() {
        let fetchRequest = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        fetchRequest.fetchLimit = 100
        
        guard let allThreads = try? viewContext.fetch(fetchRequest) else {
            return
        }
        
        let matchingThreads = allThreads.filter { $0.messageIds.contains(currentEmail.id) }
        associatedSinistri = matchingThreads.compactMap { $0.sinistro }
        associatedThread = matchingThreads.first
    }
    
    private func requestPriorityDownload() {
        // Richiede download prioritario del corpo email se non presente
        guard currentEmail.body == nil else { return }
        
        Task {
            await EmailQueueService.shared.prioritizeEmail(currentEmail.id)
        }
    }
    
    private func statoColor(_ stato: String) -> Color {
        if let statoEnum = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == stato }) {
            return statoEnum.color
        }
        return .secondary
    }
}
