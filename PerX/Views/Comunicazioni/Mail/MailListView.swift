import SwiftUI

struct MailListView: View {
    let emails: [Email]
    @Binding var selectedEmail: Email?
    let isLoading: Bool
    let errorMessage: String?
    let onToggleReadStatus: (String) -> Void
    @ObservedObject var viewModel: MailViewModel
    let selectedMailboxId: String
    
    init(emails: [Email], selectedEmail: Binding<Email?>, isLoading: Bool, errorMessage: String?, onToggleReadStatus: @escaping (String) -> Void, viewModel: MailViewModel, selectedMailboxId: String) {
        self.emails = emails
        self._selectedEmail = selectedEmail
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.onToggleReadStatus = onToggleReadStatus
        self.viewModel = viewModel
        self.selectedMailboxId = selectedMailboxId
    }
    
    var body: some View {
        Group {
            if let errorMessage = errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Errore nel caricamento delle email")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else if isLoading && emails.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if emails.isEmpty {
                Text("Nessuna email")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Mostra direttamente le email senza thread (stile macOS Mail)
                List(selection: $selectedEmail) {
                    ForEach(emails, id: \.id) { email in
                        UnifiedEmailRow(
                            email: email,
                            style: .standard,
                            isSelected: selectedEmail?.id == email.id,
                            isSentByUser: UnifiedEmailRow.checkIsSentByUser(email: email),
                            onSelect: { selectedEmail = email },
                            onToggleRead: { onToggleReadStatus(email.id) }
                        )
                            .tag(email)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    onToggleReadStatus(email.id)
                                } label: {
                                    Label(email.isRead ? "Non Letta" : "Letta", 
                                          systemImage: email.isRead ? "envelope.open.fill" : "envelope.fill")
                                }
                                .tint(.blue)
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(.textBackgroundColor))
            }
        }
        .onChange(of: selectedEmail) { oldValue, newValue in
            // Priorità massima per download quando viene selezionata una mail
            if let email = newValue {
                let emailRepository = EmailRepository.shared
                if let cachedEmail = emailRepository.getEmail(byId: email.id) {
                    // Se il body non è presente, prioritizza il download
                    if cachedEmail.body == nil || cachedEmail.body?.isEmpty == true {
                        Task {
                            await EmailQueueService.shared.prioritizeEmail(email.id)
                        }
                    }
                } else {
                    // Email non in repository, prioritizza immediatamente
                    Task {
                        await EmailQueueService.shared.prioritizeEmail(email.id)
                    }
                }
            }
        }
    }
    
    // Rimossa threadRow perché ora mostriamo direttamente le email
}

// Rimossa l'estensione perché non usiamo più i thread in MailListView 