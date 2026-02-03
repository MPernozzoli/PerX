import SwiftUI
import CoreData

enum ThreadViewMode: String, CaseIterable {
    case sinistro = "Per Sinistro"
    case oggetto = "Per Oggetto"
}

struct PrincipaleView: View {
    @ObservedObject private var mailViewModel = MailViewModel.shared
    // Usa ObservedObject per singleton - evita problemi con StateObject(wrappedValue:)
    @ObservedObject private var viewModel = PrincipaleViewModel.shared
    @State private var selectedThread: SinistroEmailThread?
    @State private var selectedSubjectThread: SubjectThread?
    @State private var showingCollegaSinistroSheet = false
    @State private var errorMessage: String?
    @State private var showingErrorAlert = false
    @State private var viewMode: ThreadViewMode = .sinistro
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Segmented control per alternare modalità
                Picker("Modalità visualizzazione", selection: $viewMode) {
                    ForEach(ThreadViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Divider()
                
                // Lista thread
                threadListView
            }
            .navigationTitle("Email")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await mailViewModel.indexAllSinistri()
                                await viewModel.loadExistingThreadsAsync()
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .help("Rigenera thread")
                        
                    if mailViewModel.isDownloading {
                        Button {
                            mailViewModel.stopSync()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .foregroundColor(.red)
                        }
                        .help("Interrompi")
                    } else {
                        Button {
                            Task {
                                await mailViewModel.fetchAllEmails(prioritize: "INBOX")
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Aggiorna")
                    }
                    }
                }
            }
        } detail: {
            detailView
        }
        .alert("Errore", isPresented: $showingErrorAlert, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
        .onChange(of: viewMode) { _, newValue in
            selectedThread = nil
            selectedSubjectThread = nil
            
            if newValue == .oggetto {
                viewModel.updateSubjectThreads()
            }
        }
        .onAppear {
            loadThreadsIfNeeded()
            viewModel.updateSubjectThreads()
        }
    }
    
    // MARK: - Thread List View
    
    @ViewBuilder
    private var threadListView: some View {
        if viewMode == .sinistro {
            sinistroThreadList
        } else {
            subjectThreadList
        }
    }
    
    @ViewBuilder
    private var sinistroThreadList: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if uniqueEmailThreads.isEmpty {
            emptyThreadsView
                                    } else {
            List(selection: $selectedThread) {
                ForEach(uniqueEmailThreads) { thread in
                    UnifiedThreadRow(sinistroThread: thread, isSelected: selectedThread?.wrappedId == thread.wrappedId, viewModel: viewModel)
                        .tag(thread)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.textBackgroundColor))
                                    }
                                }
    
    // Thread deduplicati per evitare errori SwiftUI con ID duplicati, ordinati per data mail più recente
    private var uniqueEmailThreads: [SinistroEmailThread] {
        var unique: [SinistroEmailThread] = []
        var seenIds: Set<UUID> = []
        for thread in viewModel.emailThreads {
            let threadId = thread.wrappedId
            if !seenIds.contains(threadId) {
                seenIds.insert(threadId)
                unique.append(thread)
            }
        }
        // Ordina per data della mail più recente (più recenti in alto)
        return unique.sorted { thread1, thread2 in
            let date1 = viewModel.latestEmail(for: thread1)?.date ?? Date.distantPast
            let date2 = viewModel.latestEmail(for: thread2)?.date ?? Date.distantPast
            return date1 > date2
        }
    }
    
    @ViewBuilder
    private var subjectThreadList: some View {
        if viewModel.subjectThreads.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.largeTitle)
                                .foregroundColor(.secondary)
                Text("Nessun thread")
                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selectedSubjectThread) {
                ForEach(viewModel.subjectThreads, id: \.id) { subjectThread in
                    UnifiedThreadRow(subjectThread: subjectThread, isSelected: selectedSubjectThread?.id == subjectThread.id, viewModel: viewModel)
                        .tag(subjectThread)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.textBackgroundColor))
        }
    }
    
    private var emptyThreadsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Nessun thread")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("I thread verranno creati automaticamente quando le email vengono associate ai sinistri")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Detail View
    
    @ViewBuilder
    private var detailView: some View {
        if viewMode == .sinistro {
            if let thread = selectedThread {
                ThreadDetailView(thread: thread, viewModel: viewModel, mailViewModel: mailViewModel)
                } else {
                Text("Seleziona un thread per visualizzare i dettagli")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
            if let subjectThread = selectedSubjectThread {
                SubjectThreadDetailView(subjectThread: subjectThread, viewModel: viewModel, mailViewModel: mailViewModel)
        } else {
                Text("Seleziona un thread per visualizzare i dettagli")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

    // MARK: - Helpers
    
    private func loadThreadsIfNeeded() {
        guard viewModel.emailThreads.isEmpty && !viewModel.isLoading else { return }
        
        Task {
            await viewModel.loadExistingThreadsAsync()
            
            if viewModel.emailThreads.isEmpty {
                await mailViewModel.indexAllSinistri()
                await viewModel.loadExistingThreadsAsync()
            }
        }
    }
}

// MARK: - Thread Detail View

struct ThreadDetailView: View {
    let thread: SinistroEmailThread
    let viewModel: PrincipaleViewModel
    let mailViewModel: MailViewModel
    @State private var showingCollegaSinistroSheet = false
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var appState: AppState
    
    private var sortedEmails: [Email] {
        viewModel.emails(for: thread)
            .sorted(by: { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) })
    }
    
    private var lastUnreadEmailId: String? {
        sortedEmails.last(where: { !$0.isRead })?.id ?? sortedEmails.last?.id
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            threadHeader
            
            Divider()
            
            // Lista email
            ScrollViewReader { proxy in
                List {
                    ForEach(sortedEmails, id: \.id) { email in
                        UnifiedEmailRow(
                            email: email,
                            style: .compact,
                            isSelected: viewModel.selectedEmail?.id == email.id,
                            isSentByUser: UnifiedEmailRow.checkIsSentByUser(email: email),
                            onSelect: { viewModel.selectEmail(email) }
                        )
                        .id(email.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowSeparator(.hidden)
                }
                }
                .listStyle(.plain)
                .onAppear {
                    if let targetId = lastUnreadEmailId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(targetId, anchor: .center)
        }
    }
                    }
                }
            }
            
            // Email detail
            if let selectedEmail = viewModel.selectedEmail {
                Divider()
                ScrollView {
                    MailDetailView(viewModel: mailViewModel, email: selectedEmail)
                }
                .frame(maxHeight: 400)
            }
        }
        .sheet(isPresented: $showingCollegaSinistroSheet) {
            SinistroSelectionView { sinistro in
                viewModel.associateThreadWithSinistro(thread, sinistro: sinistro)
                showingCollegaSinistroSheet = false
            }
        }
    }
    
    @ViewBuilder
    private var threadHeader: some View {
            HStack {
                if let sinistro = thread.sinistro {
                    VStack(alignment: .leading) {
                        Text(sinistro.riferimentoVisualizzato)
                            .font(.headline)
                        if let numero = sinistro.numeroSinistroCompagnia, !numero.isEmpty {
                            Text("N. Agenzia: \(numero)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        if let assicurato = sinistro.nomeAssicurato {
                            Text(assicurato)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        if let contraente = sinistro.nomeContraente {
                            Text("Contraente: \(contraente)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        appState.openSinistro(sinistro, openInNewWindow: true)
                    } label: {
                        Label("Apri Sinistro", systemImage: "rectangle.portrait.on.rectangle.portrait")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
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
                    
                    Button {
                        viewModel.removeThreadAssociation(thread)
                    } label: {
                        Label("Scollega", systemImage: "minus.circle")
                    }
                    .controlSize(.small)
                } else {
                    Button {
                        showingCollegaSinistroSheet = true
                    } label: {
                        Label("Collega a Sinistro", systemImage: "link")
                    }
                    
                    Spacer()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Subject Thread Detail View

struct SubjectThreadDetailView: View {
    let subjectThread: SubjectThread
    let viewModel: PrincipaleViewModel
    let mailViewModel: MailViewModel
    @Environment(\.managedObjectContext) private var viewContext
    
    private var sortedEmails: [Email] {
        subjectThread.emails.sorted(by: { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) })
    }
    
    private var lastUnreadEmailId: String? {
        sortedEmails.last(where: { !$0.isRead })?.id ?? sortedEmails.last?.id
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(subjectThread.originalSubject.isEmpty ? "(Nessun oggetto)" : subjectThread.originalSubject)
                        .font(.headline)
                    Text("\(subjectThread.emails.count) email")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Lista email
            ScrollViewReader { proxy in
                List {
                    ForEach(sortedEmails, id: \.id) { email in
                        UnifiedEmailRow(
                            email: email,
                            style: .compact,
                            isSelected: viewModel.selectedEmail?.id == email.id,
                            isSentByUser: UnifiedEmailRow.checkIsSentByUser(email: email),
                            onSelect: { viewModel.selectEmail(email) }
                        )
                            .id(email.id)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    if let targetId = lastUnreadEmailId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(targetId, anchor: .center)
                            }
                        }
                    }
                }
            }
            
            // Email detail
            if let selectedEmail = viewModel.selectedEmail {
                Divider()
                ScrollView {
                    MailDetailView(viewModel: mailViewModel, email: selectedEmail)
                }
                .frame(maxHeight: 400)
            }
        }
    }
}

// MARK: - Sinistro Selection View

struct SinistroSelectionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Sinistro.riferimento, ascending: true)],
        animation: .default
    ) private var sinistri: FetchedResults<Sinistro>
    
    @State private var searchText = ""
    let onSelect: (Sinistro) -> Void
    
    var body: some View {
        VStack {
            Text("Seleziona un sinistro")
                .font(.headline)
                .padding()
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Cerca sinistro...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            
            List(filteredSinistri, id: \.id) { sinistro in
                Button(action: {
                    onSelect(sinistro)
                }) {
                    HStack {
                        Text(sinistro.riferimentoVisualizzato)
                            .font(.headline)
                        
                        Spacer()
                        
                        if let nomeAssicurato = sinistro.nomeAssicurato {
                            Text(nomeAssicurato)
                                .foregroundColor(.secondary)
                        }
                        if let nomeContraente = sinistro.nomeContraente {
                            Text(nomeContraente)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            HStack {
                Spacer()
                
                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 300)
    }
    
    private var filteredSinistri: [Sinistro] {
        if searchText.isEmpty {
            return Array(sinistri)
        } else {
            return sinistri.filter { sinistro in
                (sinistro.riferimento ?? "").localizedCaseInsensitiveContains(searchText) ||
                (sinistro.numeroSinistroCompagnia ?? "").localizedCaseInsensitiveContains(searchText) ||
                (sinistro.nomeContraente ?? "").localizedCaseInsensitiveContains(searchText) ||
                (sinistro.nomeAssicurato ?? "").localizedCaseInsensitiveContains(searchText) ||
                (sinistro.nomeDanneggiato ?? "").localizedCaseInsensitiveContains(searchText) ||
                (sinistro.nomeCompagnia ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

// MARK: - Preview

struct PrincipaleView_Previews: PreviewProvider {
    static var previews: some View {
        PrincipaleView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
