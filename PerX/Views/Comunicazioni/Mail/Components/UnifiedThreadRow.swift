import SwiftUI
import CoreData

/// Row thread unificata e configurabile
/// Sostituisce: ThreadRow, SubjectThreadRow, PrincipaleThreadRow
struct UnifiedThreadRow: View {
    
    // MARK: - Thread Type
    
    enum ThreadType {
        case sinistro(SinistroEmailThread)
        case subject(SubjectThread)
    }
    
    // MARK: - Properties
    
    let threadType: ThreadType
    let isSelected: Bool
    
    @ObservedObject var viewModel: PrincipaleViewModel
    @ObservedObject private var summaryCache = ThreadSummaryCache.shared
    @ObservedObject private var mailViewModel = MailViewModel.shared
    
    // MARK: - Computed Properties
    
    private var threadId: UUID {
        switch threadType {
        case .sinistro(let thread): return thread.wrappedId
        case .subject(let thread): return thread.id
        }
    }
    
    private var emails: [Email] {
        switch threadType {
        case .sinistro(let thread): return viewModel.emails(for: thread)
        case .subject(let thread): return thread.emails
        }
    }
    
    private var unreadCount: Int {
        switch threadType {
        case .sinistro(let thread): return viewModel.unreadCount(for: thread)
        case .subject(let thread): return viewModel.unreadCount(for: thread)
        }
    }
    
    private var latestEmail: Email? {
        switch threadType {
        case .sinistro(let thread): return viewModel.latestEmail(for: thread)
        case .subject(let thread): return viewModel.latestEmail(for: thread)
        }
    }
    
    private var hasUnread: Bool { unreadCount > 0 }
    
    private var threadTitle: String {
        switch threadType {
        case .sinistro(let thread):
            if let sinistro = thread.sinistro {
                return sinistro.riferimentoVisualizzato
            } else if let customName = ThreadCustomizationService.shared.getCustomThreadName(threadId: thread.wrappedId) {
                return customName
            } else {
                return latestEmail?.subject ?? "Nessun oggetto"
            }
        case .subject(let thread):
            return thread.originalSubject.isEmpty ? "(Nessun oggetto)" : thread.originalSubject
        }
    }
    
    private var sinistro: Sinistro? {
        switch threadType {
        case .sinistro(let thread):
            return thread.sinistro
        case .subject:
            return nil
        }
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
    
    private var subtitle: String? {
        switch threadType {
        case .sinistro(let thread):
            return thread.sinistro?.nomeContraente ?? latestEmail?.sender.displayName
        case .subject:
            return latestEmail?.sender.displayName
        }
    }
    
    private var interlocutors: [String] {
        // Ottieni email utente per escluderla
        let userEmail = GoogleAuthService.shared.userEmail?.lowercased() ?? ""
        
        var uniqueContacts: Set<Contact> = []
        for email in emails {
            // Escludi mittente se è l'utente
            if email.sender.email.lowercased() != userEmail {
                uniqueContacts.insert(email.sender)
            }
            // Escludi destinatari se sono l'utente
            for recipient in email.recipients {
                if recipient.email.lowercased() != userEmail {
                    uniqueContacts.insert(recipient)
                }
            }
        }
        
        // Converti in array di nomi (nome se disponibile, altrimenti email)
        return uniqueContacts.map { contact in
            let displayName = contact.displayName
            if !displayName.isEmpty && displayName != contact.email {
                return displayName
            } else {
                return contact.email
            }
        }.sorted()
    }
    
    private var summaryState: ThreadSummaryCache.SummaryState {
        summaryCache.getState(for: threadId)
    }
    
    /// Verifica se il contenuto delle email è sufficiente per generare un riassunto
    private var canShowSummary: Bool {
        let emailsWithBody = emails.filter { $0.body != nil }
        return summaryCache.canSummarize(emails: emailsWithBody)
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    // Avatar
                    avatarView
                    
                    // Info thread
                    VStack(alignment: .leading, spacing: 4) {
                        // Titolo e data
                        titleRow
                        
                        // Interlocutori
                        interlocutorsRow
                        
                        // Riassunto (con streaming)
                        summaryRow
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Badge non lette
                    if hasUnread {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color(.separatorColor), lineWidth: isSelected ? 3 : 1)
            )
        }
        .onAppear {
            requestSummaryIfNeeded()
        }
        .onChange(of: emails.count) { _, _ in
            // Richiedi nuovo riassunto se cambiano le email
            requestSummaryIfNeeded()
        }
    }
    
    // MARK: - Avatar
    
    private var avatarView: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .frame(width: 32, height: 32)
            .overlay(
                Text(EmailHelpers.initials(from: latestEmail?.sender.displayName ?? "??"))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            )
    }
    
    // MARK: - Title Row
    
    private var titleRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(threadTitle)
                    .font(.system(size: 13, weight: hasUnread ? .semibold : .regular))
                    .foregroundColor(hasUnread ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // Mostra stato sinistro se presente
                if let stato = sinistroStato {
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
            
            Text(EmailHelpers.formatDate(latestEmail?.date))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Interlocutors Row
    
    @ViewBuilder
    private var interlocutorsRow: some View {
        if !interlocutors.isEmpty {
            HStack(spacing: 4) {
                if let first = interlocutors.first {
                    Text(first)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                if interlocutors.count > 1 {
                    Text("→")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if interlocutors.count == 2 {
                        Text(interlocutors[1])
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text("e altri \(interlocutors.count - 1)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
    
    // MARK: - Summary Row (con streaming)
    
    @ViewBuilder
    private var summaryRow: some View {
        // Non mostrare nulla se il contenuto è troppo corto per un riassunto
        if !canShowSummary {
            EmptyView()
        } else {
            switch summaryState {
            case .ready(let text), .streaming(let text):
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .animation(.easeInOut(duration: 0.2), value: text)
                
            case .loading:
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                    Text("Generazione riassunto in corso...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
            case .error(let message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.8))
                    .lineLimit(1)
                
            case .notRequested:
                // Mostra placeholder se non ancora richiesto (ma solo se ci sono email con body)
                if !emails.filter({ $0.body != nil }).isEmpty {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 12, height: 12)
                        Text("Generazione riassunto in corso...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    EmptyView()
                }
            }
        }
    }
    
    // MARK: - Summary Request
    
    private func requestSummaryIfNeeded() {
        // Solo se abbiamo email con body
        let emailsWithBody = emails.filter { $0.body != nil }
        
        guard !emailsWithBody.isEmpty else {
            // Carica i body mancanti in background
            loadMissingBodies()
            return
        }
        
        // Richiedi riassunto (il cache gestisce invalidazione)
        summaryCache.requestSummary(for: threadId, emails: emailsWithBody)
    }
    
    private func loadMissingBodies() {
        Task {
            for email in emails.prefix(5) where email.body == nil {
                await mailViewModel.fetchFullEmail(for: email.id)
            }
            
            // Riprova dopo aver caricato
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            await MainActor.run {
                let emailsWithBody = emails.filter { 
                    if $0.body != nil { return true }
                    if let cached = EmailRepository.shared.getEmail(byId: $0.id), cached.body != nil {
                        return true
                    }
                    return false
                }
                
                if !emailsWithBody.isEmpty {
                    summaryCache.requestSummary(for: threadId, emails: emailsWithBody)
                }
            }
        }
    }
}

// MARK: - Convenience Initializers

extension UnifiedThreadRow {
    /// Inizializza con SinistroEmailThread
    init(sinistroThread: SinistroEmailThread, isSelected: Bool, viewModel: PrincipaleViewModel) {
        self.threadType = .sinistro(sinistroThread)
        self.isSelected = isSelected
        self.viewModel = viewModel
    }
    
    /// Inizializza con SubjectThread
    init(subjectThread: SubjectThread, isSelected: Bool, viewModel: PrincipaleViewModel) {
        self.threadType = .subject(subjectThread)
        self.isSelected = isSelected
        self.viewModel = viewModel
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        // Simulazione di thread row
        Text("UnifiedThreadRow Preview")
            .font(.headline)
    }
    .padding()
}

