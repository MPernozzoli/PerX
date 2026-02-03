import SwiftUI
import CoreData

struct MailContainerView: View {
    @ObservedObject var viewModel: MailViewModel
    // Usa ObservedObject per singleton - evita problemi con StateObject(wrappedValue:)
    @ObservedObject private var principaleViewModel = PrincipaleViewModel.shared
    @Binding var selectedEmail: Email?
    
    @State private var selectedMailboxId: String = "PRINCIPALE"
    @State private var selectedThread: SinistroEmailThread?
    
    // --- Stati per filtri e ricerca ---
    @State private var filterByUnread = false
    @State private var searchText = ""
    @State private var searchIsExpanded = false
    @FocusState private var searchFieldIsFocused: Bool
    
    // Stato per la presentazione del foglio delle impostazioni
    @State private var showSettings = false
    
    // Stato per indicare l'attività di rete
    @State private var isSyncing = false
    
    init(viewModel: MailViewModel, selectedEmail: Binding<Email?>) {
        self.viewModel = viewModel
        self._selectedEmail = selectedEmail
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER TOOLBAR ---
            headerToolbar
            
            // --- LISTA EMAIL ---
            emailListView
        }
        .background(Color(.controlBackgroundColor))
        .sheet(isPresented: $showSettings) {
            MailboxSettingsView(viewModel: viewModel)
        }
        .onAppear {
            // Inizializza la cache in modo asincrono (non blocca)
            Task { @MainActor in
                // Non accedere a displayedThreads qui - potrebbe non essere ancora caricato
                updateFilteredThreads()
            }
        }
        .onChange(of: searchText) { _, _ in
            updateFilteredThreads()
        }
        .onChange(of: filterByUnread) { _, _ in
            updateFilteredThreads()
        }
        .onChange(of: principaleViewModel.displayedThreads.count) { _, _ in
            // Aggiorna i thread filtrati quando cambia il numero di thread visualizzati
            // ma solo se è già stata calcolata la cache iniziale e non stiamo rigenerando
            if hasComputedFilter && !isRegenerating {
                updateFilteredThreads()
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

    
    // MARK: - Header Toolbar
    private var headerToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Selettore casella con ScrollView orizzontale - esteso più a destra
                MailboxPickerView(
                    selection: $selectedMailboxId,
                    mailboxes: viewModel.displayableMailboxes.filter { $0.isVisible },
                    onSettingsTap: { showSettings = true }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Controlli toolbar - in estrema destra
                toolbarControls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.controlBackgroundColor))
            
            // Progress bar per il download
            if viewModel.isDownloading {
                VStack(spacing: 4) {
                    HStack {
                        Text(viewModel.downloadStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        // Tasto stop rapido
                        Button(action: { viewModel.stopSync() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .help("Interrompi")
                        
                        Text("\(Int(viewModel.downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color(.separatorColor))
                                .frame(height: 2)
                            
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: geometry.size.width * viewModel.downloadProgress, height: 2)
                                .animation(.linear(duration: 0.2), value: viewModel.downloadProgress)
                        }
                    }
                    .frame(height: 2)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
                .background(Color(.controlBackgroundColor))
            }
            
            // Separatore
            Rectangle()
                .fill(Color(.separatorColor))
                .frame(height: 0.5)
        }
    }
    
    
    // MARK: - Toolbar Controls
    private var toolbarControls: some View {
        HStack(spacing: 8) {
            // Status coda email (mostra se ci sono email in coda)
            EmailQueueStatusView()
            
            // Barra di ricerca espandibile
            if searchIsExpanded {
                TextField("Cerca email...", text: $searchText)
                    .focused($searchFieldIsFocused)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            
            // Pulsante ricerca
            Button(action: {
                withAnimation(.spring(duration: 0.3)) {
                    searchIsExpanded.toggle()
                    if searchIsExpanded {
                        searchFieldIsFocused = true
                    } else {
                        searchText = ""
                        searchFieldIsFocused = false
                    }
                }
            }) {
                Image(systemName: searchIsExpanded ? "xmark.circle.fill" : "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(searchIsExpanded ? .secondary : .primary)
            }
            .buttonStyle(.plain)
            .help(searchIsExpanded ? "Chiudi ricerca" : "Cerca")
            
            // Menu filtri
            Menu {
                Toggle(isOn: $filterByUnread) {
                    Label("Solo non lette", systemImage: "envelope.badge")
                }
                
                Divider()
                
                if viewModel.isDownloading {
                    Button(role: .destructive) {
                        viewModel.stopSync()
                    } label: {
                        Label("Interrompi sincronizzazione", systemImage: "stop.circle")
                    }
                } else {
                    Button("Aggiorna") {
                        Task {
                            isSyncing = true
                            await viewModel.fetchAllEmails(prioritize: selectedMailboxId)
                            try? await Task.sleep(for: .milliseconds(500))
                            isSyncing = false
                        }
                    }
                }
                
                if selectedMailboxId == "PRINCIPALE" {
                    Divider()
                    
                    Button("Rigenera thread") {
                        Task {
                            isSyncing = true
                            
                            // Marca che stiamo rigenerando per disabilitare onChange
                            await MainActor.run {
                                isRegenerating = true
                            }
                            
                            // Cancella eventuali task di filtraggio in corso
                            filterTask?.cancel()
                            
                            // Reset cache per evitare accessi concorrenti
                            await MainActor.run {
                                hasComputedFilter = false
                                cachedFilteredThreads = []
                            }
                            
                            let context = PersistenceController.shared.container.viewContext
                            
                            // 1. Cancella tutti i thread esistenti
                            let deletedCount = await EmailAssociationCleanup.shared.clearAllAssociations(context: context)
                            print("[MailContainerView] 🗑️ Cancellati \(deletedCount) thread esistenti")
                            
                            // 2. Rigenera tutte le associazioni email-sinistro con la nuova logica
                            await viewModel.recheckAllEmailAssociations(context: context)
                            
                            // 3. Indicizza tutti i sinistri per creare i nuovi thread (force refresh)
                            await viewModel.indexAllSinistri(forceRefresh: true)
                            
                            // 4. Ricarica i thread nella vista
                            await principaleViewModel.loadExistingThreadsAsync()
                            
                            // 5. Attendi che i thread siano caricati prima di aggiornare il filtro
                            try? await Task.sleep(for: .milliseconds(500))
                            
                            // 6. Aggiorna il filtro dopo la rigenerazione
                            await MainActor.run {
                                updateFilteredThreads()
                                isRegenerating = false
                            }
                            
                            try? await Task.sleep(for: .milliseconds(500))
                            isSyncing = false
                            print("[MailContainerView] ✅ Rigenerazione thread completata")
                        }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 16))
                    .symbolVariant(filterByUnread ? .fill : .none)
                    .foregroundColor(filterByUnread ? .accentColor : .primary)
            }
            .menuStyle(.borderlessButton)
            .help("Filtri e opzioni")
        }
    }
    
    // MARK: - Email List View
    private var emailListView: some View {
        ZStack {
            if selectedMailboxId == "PRINCIPALE" {
                // Vista thread per la casella principale
                principaleThreadList
            } else {
                // Vista email normale per le altre caselle
                standardEmailList
            }
            
            // Indicatore di sincronizzazione
            if isSyncing {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(8)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                            .shadow(radius: 2)
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
    }
    
    // MARK: - Principale Thread List
    private var principaleThreadList: some View {
        Group {
            // Mostra placeholder solo se non ci sono thread E non è ancora precaricato
            if filteredPrincipaleThreads.isEmpty && !principaleViewModel.isPreloaded {
                // Placeholder con animazione
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Caricamento thread...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredPrincipaleThreads.isEmpty {
                // Messaggio quando non ci sono thread
                VStack(spacing: 16) {
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
                    Button("Rigenera thread") {
                        Task {
                            isSyncing = true
                            
                            // Marca che stiamo rigenerando per disabilitare onChange
                            await MainActor.run {
                                isRegenerating = true
                            }
                            
                            // Cancella eventuali task di filtraggio in corso
                            filterTask?.cancel()
                            
                            // Reset cache per evitare accessi concorrenti
                            await MainActor.run {
                                hasComputedFilter = false
                                cachedFilteredThreads = []
                            }
                            
                            let context = PersistenceController.shared.container.viewContext
                            
                            // 1. Cancella tutti i thread esistenti
                            let deletedCount = await EmailAssociationCleanup.shared.clearAllAssociations(context: context)
                            print("[MailContainerView] 🗑️ Cancellati \(deletedCount) thread esistenti")
                            
                            // 2. Rigenera tutte le associazioni email-sinistro con la nuova logica
                            await viewModel.recheckAllEmailAssociations(context: context)
                            
                            // 3. Indicizza tutti i sinistri per creare i nuovi thread (force refresh)
                            await viewModel.indexAllSinistri(forceRefresh: true)
                            
                            // 4. Ricarica i thread nella vista
                            await principaleViewModel.loadExistingThreadsAsync()
                            
                            // 5. Attendi che i thread siano caricati prima di aggiornare il filtro
                            try? await Task.sleep(for: .milliseconds(500))
                            
                            // 6. Aggiorna il filtro dopo la rigenerazione
                            await MainActor.run {
                                updateFilteredThreads()
                                isRegenerating = false
                            }
                            
                            isSyncing = false
                            print("[MailContainerView] ✅ Rigenerazione thread completata")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedThread) {
                    ForEach(filteredPrincipaleThreads) { thread in
                        UnifiedThreadRow(sinistroThread: thread, isSelected: selectedThread?.wrappedId == thread.wrappedId, viewModel: principaleViewModel)
                            .tag(thread)
                            .onTapGesture {
                                selectedThread = thread
                                selectedEmail = principaleViewModel.latestEmail(for: thread)
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            .onAppear {
                                // Carica più thread quando si arriva vicino alla fine
                                if let lastThread = filteredPrincipaleThreads.last,
                                   thread.wrappedId == lastThread.wrappedId,
                                   principaleViewModel.hasMoreThreads {
                                    principaleViewModel.loadMoreThreads()
                                }
                            }
                    }
                    
                    // Indicatore "carica di più" in fondo
                    if principaleViewModel.hasMoreThreads {
                        HStack {
                            Spacer()
                            if principaleViewModel.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Button("Carica altri thread") {
                                    principaleViewModel.loadMoreThreads()
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(.textBackgroundColor))
            }
        }
    }
    
    // MARK: - Standard Email List
    private var standardEmailList: some View {
        Group {
            if viewModel.isLoading && emailsForSelectedMailbox.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Caricamento email...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if emailsForSelectedMailbox.isEmpty {
                Text("Nessuna email")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedEmail) {
                    ForEach(emailsForSelectedMailbox, id: \.id) { email in
                        UnifiedEmailRow(
                            email: email,
                            style: .standard,
                            isSelected: selectedEmail?.id == email.id,
                            isSentByUser: UnifiedEmailRow.checkIsSentByUser(email: email),
                            onSelect: { selectedEmail = email }
                        )
                            .tag(email)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(.textBackgroundColor))
            }
        }
    }
    
    // MARK: - Computed Properties
    @State private var cachedFilteredThreads: [SinistroEmailThread] = []
    @State private var hasComputedFilter = false
    @State private var filterTask: Task<Void, Never>?
    @State private var isRegenerating = false
    
    private var filteredPrincipaleThreads: [SinistroEmailThread] {
        // Ritorna sempre la cache (aggiornata via onChange)
        // NON accedere mai a displayedThreads direttamente qui - causa loop se la view non è visibile
        // Usa solo la cache che viene aggiornata tramite updateFilteredThreads()
        guard hasComputedFilter else {
            // Se non abbiamo ancora filtrato, ritorna array vuoto
            // La cache verrà popolata quando la view appare (onAppear -> updateFilteredThreads)
            return []
        }
        
        // Protezione finale: rimuovi eventuali duplicati rimasti per evitare errori SwiftUI
        // Crea una copia locale per evitare accessi concorrenti
        let threads = cachedFilteredThreads
        var uniqueThreads: [SinistroEmailThread] = []
        var seenIds: Set<UUID> = []
        
        for thread in threads {
            let threadId = thread.wrappedId
            if !seenIds.contains(threadId) {
                seenIds.insert(threadId)
                uniqueThreads.append(thread)
            }
        }
        
        return uniqueThreads
    }
    
    // MARK: - Helper Methods
    private func updateFilteredThreads() {
        filterTask?.cancel()
        
        // Calcola in background per non bloccare la UI (+ debounce leggero per digitazione)
        filterTask = Task.detached(priority: .utility) { [searchText, filterByUnread] in
            // Debounce minimo per evitare ricalcoli continui mentre si digita
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            if Task.isCancelled { return }
            
            // Verifica se è precaricato prima di accedere ai thread
            let isPreloaded = await MainActor.run { PrincipaleViewModel.shared.isPreloaded }
            if !isPreloaded {
                // Non ancora precaricato, non fare nulla (evita accessi sincroni pesanti)
                return
            }
            
            // Ottieni i thread in modo asincrono (solo se precaricato)
            let threads = await MainActor.run { PrincipaleViewModel.shared.displayedThreads }
            
            var filtered = threads
            
            // Filtra per ricerca (solo su dati sinistro, non email per performance)
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                filtered = filtered.filter { thread in
                    // Solo controlla dati sinistro (veloce, non blocca)
                    if let numero = thread.sinistro?.numeroSinistroCompagnia?.lowercased(),
                       numero.contains(searchLower) {
                        return true
                    }
                    if let nome = thread.sinistro?.nomeContraente?.lowercased(),
                       nome.contains(searchLower) {
                        return true
                    }
                    if let riferimento = thread.sinistro?.riferimento?.lowercased(),
                       riferimento.contains(searchLower) {
                        return true
                    }
                    return false
                }
            }
            
            // Filtra per thread con email non lette
            if filterByUnread {
                // Verifica se il thread ha almeno un'email non letta
                filtered = await MainActor.run {
                    filtered.filter { thread in
                        PrincipaleViewModel.shared.unreadCount(for: thread) > 0
                    }
                }
            }
            
            // Rimuovi duplicati prima di ordinare
            var uniqueFiltered: [SinistroEmailThread] = []
            var seenIds: Set<UUID> = []
            for thread in filtered {
                let threadId = thread.wrappedId
                if !seenIds.contains(threadId) {
                    seenIds.insert(threadId)
                    uniqueFiltered.append(thread)
                }
            }
            
            // Ordina per data più recente prima (mantiene ordine anche dopo filtro)
            let sorted = uniqueFiltered.sorted { thread1, thread2 in
                thread1.dataUltimaModifica > thread2.dataUltimaModifica
            }
            
            // Aggiorna cache sul main thread (operazione veloce)
            await MainActor.run {
                self.cachedFilteredThreads = sorted
                self.hasComputedFilter = true
            }
        }
    }
    
    private var emailsForSelectedMailbox: [Email] {
        guard let emails = viewModel.emailsByMailbox[selectedMailboxId] else {
            return []
        }
        
        var filteredEmails = emails
        
        if filterByUnread {
            filteredEmails = filteredEmails.filter { !$0.isRead }
        }
        
        if !searchText.isEmpty {
            filteredEmails = filteredEmails.filter { email in
                email.subject.localizedCaseInsensitiveContains(searchText) ||
                email.sender.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filteredEmails
    }
} 