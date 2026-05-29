import SwiftUI
import CoreData

@MainActor
struct SinistriView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = SinistriViewModel()
    @ObservedObject private var appState = AppState.shared
    
    @FetchRequest(
        entity: Sinistro.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Sinistro.riferimento, ascending: true)]
    ) private var sinistri: FetchedResults<Sinistro>
    
    // MARK: - Computed (delegato al ViewModel)
    
    var filteredSinistri: [Sinistro] {
        viewModel.filterSinistri(sinistri)
    }
    
    var suggestedSinistri: [SuggestedSinistroItem] {
        viewModel.computeSuggestedSinistri(sinistri: sinistri)
    }
    
    var activeTasksByRiferimento: [String: [DailyTask]] {
        viewModel.getActiveTasks()
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                tabBarView
                Divider()
                mainContentView
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .onAppear {
            performFolderScanIfNeeded()
        }
        .onChange(of: sinistri.count) { _ in
            viewModel.invalidateCache()
        }
        .background(
            Group {
                Button("") {
                    withAnimation(.spring()) {
                        viewModel.searchIsExpanded.toggle()
                    }
                }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                
                Button("") {
                    viewModel.clearSelection()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
            }
        )
    }
    
    // MARK: - View Components
    
    private var tabBarView: some View {
        ZStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    mainTabButton
                    openTabsButtons
                    suggestedTabsButtons
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(height: 40)
            .background(tabBarBackground)
            
            // Indicatore per detach (stile Chrome)
            if viewModel.showDetachIndicator && viewModel.isDragging {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "rectangle.split.2x1")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                            Text("Rilascia per aprire\nin nuova finestra")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.regularMaterial)
                                .shadow(radius: 8)
                        )
                        .padding(.trailing, 20)
                        .padding(.bottom, 60)
                        Spacer()
                    }
                }
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.showDetachIndicator)
            }
        }
    }
    
    private var mainTabButton: some View {
        TabButton(
            title: "Sinistri",
            isSelected: appState.selectedTabId == nil,
            canClose: false,
            onSelect: { appState.selectedTabId = nil },
            onClose: nil
        )
    }
    
    private var openTabsButtons: some View {
        ForEach(appState.openTabs, id: \.id) { tab in
            tabButton(for: tab)
        }
    }
    
    private var suggestedTabsButtons: some View {
        ForEach(suggestedSinistri, id: \.sinistro.objectID) { item in
            suggestedTabButton(for: item.sinistro, badgeCount: item.unreadCount)
        }
    }
    
    private func suggestedTabButton(for sinistro: Sinistro, badgeCount: Int) -> some View {
        TabButton(
            title: sinistro.riferimentoVisualizzato,
            isSelected: false,
            canClose: false,
            onSelect: {
                // Cmd+Click: segna tutti come letti
                if NSEvent.modifierFlags.contains(.command) {
                    markAllSuggestedAsRead()
                } else {
                    // Azzera le notifiche quando si apre il sinistro
                    markSinistroAsRead(sinistro)
                    appState.openSinistro(sinistro)
                }
            },
            onClose: nil,
            isSuggested: true,
            badgeCount: badgeCount > 0 ? badgeCount : nil
        )
        .contextMenu {
            if badgeCount > 0 {
                Button {
                    markSinistroAsRead(sinistro)
                } label: {
                    Label("Segna come letto", systemImage: "envelope.open")
                }
                .keyboardShortcut("l", modifiers: .command)
                
                Divider()
                
                Button {
                    markAllSuggestedAsRead()
                } label: {
                    Label("Segna tutti come letti", systemImage: "envelope.open.fill")
                }
            }
        }
    }
    
    /// Segna un singolo sinistro come letto (azzera tutte le notifiche)
    private func markSinistroAsRead(_ sinistro: Sinistro) {
        viewModel.markSinistroAsRead(sinistro)
    }
    
    /// Segna tutti i sinistri suggeriti con notifiche come letti
    private func markAllSuggestedAsRead() {
        viewModel.markAllSuggestedAsRead(suggested: suggestedSinistri)
    }
    
    private func tabButton(for tab: TabInfo) -> some View {
        let isDragged = viewModel.draggedTab?.id == tab.id
        
        return TabButton(
            title: tab.sinistro.riferimentoVisualizzato,
            isSelected: appState.selectedTabId == tab.id,
            canClose: true,
            onSelect: { appState.selectedTabId = tab.id },
            onClose: { appState.closeTab(id: tab.id) }
        )
        .opacity(isDragged ? 0.5 : 1.0)
        .scaleEffect(isDragged ? 0.95 : 1.0)
        .contextMenu {
            copyReferenceButton(for: tab)
            detachTabButton(for: tab)
        }
        .onDrag {
            viewModel.draggedTab = tab
            viewModel.draggedTabSourceWindowId = nil
            viewModel.isDragging = true
            let riferimento = tab.sinistro.riferimento ?? ""
            return NSItemProvider(object: riferimento as NSString)
        }
        .onDrop(of: [.text], delegate: MainTabDropDelegate(
            tab: tab,
            appState: appState,
            draggedTab: $viewModel.draggedTab,
            draggedTabSourceWindowId: $viewModel.draggedTabSourceWindowId,
            isDragging: $viewModel.isDragging,
            showDetachIndicator: $viewModel.showDetachIndicator,
            dragLocation: $viewModel.dragLocation,
            onDetach: {
                if let draggedTab = viewModel.draggedTab {
                    appState.detachTab(draggedTab, fromWindowId: nil)
                }
            }
        ))
    }
    
    private func copyReferenceButton(for tab: TabInfo) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tab.sinistro.riferimento ?? "", forType: .string)
        } label: {
            Label("Copia Riferimento", systemImage: "doc.on.doc")
        }
    }
    
    private func detachTabButton(for tab: TabInfo) -> some View {
        Button {
            appState.detachTab(tab, fromWindowId: nil)
        } label: {
            Label("Sposta in nuova finestra", systemImage: "rectangle.split.2x1")
        }
    }
    
    private var tabBarBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(NSColor.windowBackgroundColor),
                Color(NSColor.windowBackgroundColor).opacity(0.95)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        if appState.selectedTabId == nil {
            sinistriListView
        } else {
            selectedTabContentView
        }
    }
    
    private var sinistriListView: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 16) {
                StateCounterView(
                    sinistri: sinistri,
                    selectedStates: $viewModel.selectedStates,
                    searchText: $viewModel.searchText,
                    searchInFilteredOnly: $viewModel.searchInFilteredOnly,
                    selectedCompanies: $viewModel.selectedCompanies,
                    selectedAgenzie: $viewModel.selectedAgenzie,
                    selectedTipoPolizze: $viewModel.selectedTipoPolizze,
                    recentOnly: $viewModel.recentOnly,
                    showUltimiOnly: $viewModel.showUltimiOnly,
                    filterAssigneeEnabled: $viewModel.filterAssigneeEnabled,
                    selectedAssigneeEmail: $viewModel.filterAssigneeEmail,
                    searchIsExpanded: $viewModel.searchIsExpanded
                )
                
                if filteredSinistri.isEmpty && !viewModel.searchText.isEmpty {
                    NoResultsView(
                        searchInFilteredOnly: viewModel.searchInFilteredOnly,
                        onToggleSearch: {
                            viewModel.searchInFilteredOnly.toggle()
                        }
                    )
                } else {
                    sinistriTable
                }
            }
            
            // Barra di selezione multipla ancorata in basso
            if !viewModel.selectedSinistri.isEmpty {
                multiSelectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.selectedSinistri.isEmpty)
    }
    
    private var multiSelectionBar: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.accentColor)
            Text("\(viewModel.selectedSinistri.count) sinistri selezionati")
                .font(.subheadline.weight(.medium))
            
            Spacer()
            
            // Menu cambia stato
            Menu {
                ForEach(StatoManager.StatoSinistro.allCases.filter { $0.isVisible }, id: \.id) { stato in
                    Button {
                        changeStateForSelectedSinistri(to: stato)
                    } label: {
                        Label(stato.descrizione, systemImage: stato.icon)
                    }
                }
            } label: {
                Label("Cambia stato", systemImage: "arrow.triangle.2.circlepath")
            }
            .menuStyle(.borderlessButton)
            
            Divider()
                .frame(height: 20)
            
            // Rimuovi (Debug)
            Button(role: .destructive) {
                deleteSelectedSinistri()
            } label: {
                Label("Rimuovi", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
            
            Divider()
                .frame(height: 20)
            
            // Deseleziona tutti
            Button {
                viewModel.clearSelection()
            } label: {
                Label("Deseleziona", systemImage: "xmark.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, y: -2)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    private var sinistriTable: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider()
            tableList
        }
    }
    
    private var tableHeader: some View {
        HStack(spacing: 0) {
            sortableHeaderColumn(.riferimento, width: viewModel.mostraSiglaCompagnia ? 150 : 120)
            sortableHeaderColumn(.stato, width: 180)
            sortableHeaderColumn(.assicurato, width: 180)
            sortableHeaderColumn(.prioritaDinamica, width: 80)
            if !viewModel.mostraSiglaCompagnia {
                sortableHeaderColumn(.compagnia, width: 140)
            }
            sortableHeaderColumn(.complessita, width: 90)
            headerColumn("Beni", width: 70)
            headerColumn("Solleciti", width: 80)
            sortableHeaderColumn(.task, width: 60)
            sortableHeaderColumn(.liquidato, width: nil)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func headerColumn(_ title: String, width: CGFloat?) -> some View {
        Group {
            if let width = width {
                Text(title)
                    .frame(width: width, alignment: .leading)
            } else {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.headline)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
    
    private func sortableHeaderColumn(_ column: SortColumn, width: CGFloat?) -> some View {
        Button {
            if viewModel.sortColumn == column {
                viewModel.sortAscending.toggle()
            } else {
                viewModel.sortColumn = column
                viewModel.sortAscending = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(column.rawValue)
                    .font(.headline)
                
                if viewModel.sortColumn == column {
                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .frame(width: width)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    private var tableList: some View {
        let tasksByRif = activeTasksByRiferimento
        let currentList = filteredSinistri
        
        return List {
            ForEach(currentList, id: \.objectID) { sinistro in
                SinistroTableRow(
                    sinistro: sinistro,
                    viewModel: viewModel,
                    activeTaskCount: viewModel.activeTaskCount(for: sinistro),
                    activeTasks: tasksByRif[sinistro.riferimento ?? ""] ?? [],
                    statoColor: viewModel.statoColor(for: sinistro),
                    priorityValue: viewModel.calculatePriority(for: sinistro, sinistri: sinistri),
                    mostraSiglaCompagnia: viewModel.mostraSiglaCompagnia,
                    isSelected: viewModel.selectedSinistri.contains(sinistro.objectID),
                    onTap: {
                        guard !sinistro.isDeleted else { return }
                        let modifiers = NSEvent.modifierFlags
                        
                        if modifiers.contains(.shift) {
                            viewModel.selectRange(to: sinistro, in: currentList)
                        } else if modifiers.contains(.command) {
                            viewModel.toggleSelection(sinistro)
                            viewModel.lastSelectedSinistroID = sinistro.objectID
                        } else {
                            // Singolo click: solo selezione
                            viewModel.clearSelection()
                            viewModel.selectedSinistri.insert(sinistro.objectID)
                            viewModel.lastSelectedSinistroID = sinistro.objectID
                        }
                    },
                    onDoubleTap: {
                        guard !sinistro.isDeleted else { return }
                        appState.openSinistro(sinistro)
                    },
                    onOpenInNewWindow: {
                        guard !sinistro.isDeleted else { return }
                        appState.openSinistro(sinistro, openInNewWindow: true)
                    }
                )
                .contextMenu {
                    if viewModel.selectedSinistri.contains(sinistro.objectID) && viewModel.selectedSinistri.count > 1 {
                        multiSelectionContextMenu
                    } else {
                        singleSinistroContextMenu(sinistro)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                .id("\(sinistro.objectID)-\(sinistro.riferimento ?? "")")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .id("\(viewModel.debouncedSearchText)-\(viewModel.searchInFilteredOnly)-\(viewModel.selectedStates.sorted().joined(separator: ","))")
    }
    
    @ViewBuilder
    private func singleSinistroContextMenu(_ sinistro: Sinistro) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(sinistro.riferimento ?? "", forType: .string)
        } label: {
            Label("Copia Riferimento", systemImage: "doc.on.doc")
        }
        
        Button {
            guard !sinistro.isDeleted else { return }
            appState.openSinistro(sinistro, openInNewWindow: true)
        } label: {
            Label("Apri in nuova finestra", systemImage: "rectangle.split.2x1")
        }
        
        Divider()
        
        // Menu cambia stato
        Menu {
            ForEach(StatoManager.StatoSinistro.allCases.filter { $0.isVisible }, id: \.id) { stato in
                Button {
                    changeStatoForSinistro(sinistro, to: stato)
                } label: {
                    Label(stato.descrizione, systemImage: stato.icon)
                }
            }
        } label: {
            Label("Cambia stato", systemImage: "arrow.triangle.2.circlepath")
        }
        
        // Menu cambia priorità
        Menu {
            ForEach(ManualPriorityLevel.allCases, id: \.rawValue) { level in
                Button {
                    viewModel.changePriority(for: sinistro, to: level, context: viewContext)
                } label: {
                    HStack {
                        Label(level.rawValue, systemImage: level.icon)
                        if let current = sinistro.value(forKey: "prioritaManuale") as? Double,
                           ManualPriorityLevel.from(value: current) == level {
                            Spacer()
                            Image(systemName: "checkmark")
                        } else if level == .automatica && sinistro.value(forKey: "prioritaManuale") == nil {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Cambia priorità", systemImage: "gauge.with.dots.needle.33percent")
        }
        
        Divider()
        
        // Opzione debug: Rimuovi
        Button(role: .destructive) {
            deleteSinistro(sinistro)
        } label: {
            Label("Rimuovi (Debug)", systemImage: "trash")
        }
    }
    
    private func changeStatoForSinistro(_ sinistro: Sinistro, to newState: StatoManager.StatoSinistro) {
        Task {
            do {
                try await StatoManager.shared.changeState(
                    for: sinistro,
                    to: newState,
                    context: viewContext,
                    userEmail: GoogleAuthService.shared.userEmail,
                    skipValidation: true
                )
                print("[SinistriView] ✅ Stato cambiato per \(sinistro.riferimento ?? "N/A") → \(newState.descrizione)")
            } catch {
                print("[SinistriView] ❌ Errore cambio stato per \(sinistro.riferimento ?? "N/A"): \(error)")
            }
        }
    }
    
    private func deleteSinistro(_ sinistro: Sinistro) {
        // Chiudi eventuale tab aperto
        if let tab = appState.openTabs.first(where: { $0.sinistro.objectID == sinistro.objectID }) {
            appState.closeTab(id: tab.id)
        }
        
        let riferimento = sinistro.riferimento ?? "N/A"
        print("[SinistriView] 🗑️ Eliminazione sinistro \(riferimento)")
        
        // Salva il riferimento per tracking locale.
        let rifToDelete = sinistro.riferimento
        
        // Traccia localmente per evitare rientri da sync.
        if let rif = rifToDelete, !rif.isEmpty {
            DeletedSinistriTracker.shared.markAsDeleted(riferimento: rif)
        }
        
        // Elimina dal database locale
        viewContext.delete(sinistro)
        
        do {
            try viewContext.save()
            print("[SinistriView] ✅ Sinistro \(riferimento) eliminato localmente")
        } catch {
            print("[SinistriView] ❌ Errore durante l'eliminazione: \(error)")
        }
    }
    
    @ViewBuilder
    private var multiSelectionContextMenu: some View {
        let count = viewModel.selectedSinistri.count
        
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.accentColor)
            Text("\(count) sinistri selezionati")
                .font(.headline)
        }
        
        Divider()
        
        // Menu cambia stato
        Menu {
            ForEach(StatoManager.StatoSinistro.allCases.filter { $0.isVisible }, id: \.id) { stato in
                Button {
                    changeStateForSelectedSinistri(to: stato)
                } label: {
                    Label(stato.descrizione, systemImage: stato.icon)
                }
            }
        } label: {
            Label("Cambia stato", systemImage: "arrow.triangle.2.circlepath")
        }
        
        // Menu cambia priorità
        Menu {
            ForEach(ManualPriorityLevel.allCases, id: \.rawValue) { level in
                Button {
                    changePriorityForSelectedSinistri(to: level)
                } label: {
                    Label(level.rawValue, systemImage: level.icon)
                }
            }
        } label: {
            Label("Cambia priorità", systemImage: "gauge.with.dots.needle.33percent")
        }
        
        Divider()
        
        // Opzione debug: Rimuovi
        Button(role: .destructive) {
            deleteSelectedSinistri()
        } label: {
            Label("Rimuovi (Debug)", systemImage: "trash")
        }
    }
    
    private func changePriorityForSelectedSinistri(to level: ManualPriorityLevel) {
        let sinistriToUpdate = viewModel.selectedSinistriObjects(from: filteredSinistri)
        guard !sinistriToUpdate.isEmpty else { return }
        
        for sinistro in sinistriToUpdate {
            viewModel.changePriority(for: sinistro, to: level, context: viewContext)
        }
        
        viewModel.clearSelection()
    }
    
    private func changeStateForSelectedSinistri(to newState: StatoManager.StatoSinistro) {
        let sinistriToUpdate = viewModel.selectedSinistriObjects(from: filteredSinistri)
        guard !sinistriToUpdate.isEmpty else { return }
        
        Task {
            for sinistro in sinistriToUpdate {
                await viewModel.changeState(for: sinistro, to: newState, context: viewContext)
            }
            
            await MainActor.run {
                viewModel.clearSelection()
            }
        }
    }
    
    private func deleteSelectedSinistri() {
        let sinistriToDelete = viewModel.selectedSinistriObjects(from: filteredSinistri)
        guard !sinistriToDelete.isEmpty else { return }
        
        // Chiudi eventuali tab aperti per i sinistri da eliminare
        for sinistro in sinistriToDelete {
            if let tab = appState.openTabs.first(where: { $0.sinistro.objectID == sinistro.objectID }) {
                appState.closeTab(id: tab.id)
            }
        }
        
        // Raccogli i riferimenti e traccia localmente (fallback)
        var deletedRiferimenti: [String] = []
        for sinistro in sinistriToDelete {
            if let rif = sinistro.riferimento, !rif.isEmpty {
                DeletedSinistriTracker.shared.markAsDeleted(riferimento: rif)
                deletedRiferimenti.append(rif)
            }
            viewContext.delete(sinistro)
        }
        
        do {
            try viewContext.save()
            print("[SinistriView] ✅ \(sinistriToDelete.count) sinistri eliminati localmente: \(deletedRiferimenti.joined(separator: ", "))")
        } catch {
            print("[SinistriView] ❌ Errore durante l'eliminazione: \(error)")
        }
        
        // Deseleziona
        viewModel.clearSelection()
    }
    
    @ViewBuilder
    private var selectedTabContentView: some View {
        if let selectedTabId = appState.selectedTabId,
           let tab = appState.openTabs.first(where: { $0.id == selectedTabId }) {
            tabContent(for: tab)
        }
    }
    
    @ViewBuilder
    private func tabContent(for tab: TabInfo) -> some View {
        let isObjectValid: Bool = {
            guard !tab.sinistro.isDeleted else { return false }
            guard tab.sinistro.managedObjectContext != nil else { return false }
            
            // Verifica se l'oggetto esiste ancora nel contesto in modo sicuro
            do {
                _ = try viewContext.existingObject(with: tab.sinistro.objectID)
                return true
            } catch {
                return false
            }
        }()
        
        if isObjectValid {
            SinistroDetailView(sinistro: tab.sinistro)
                .environment(\.managedObjectContext, viewContext)
                .id(tab.id)
                .onAppear {
                    viewContext.refresh(tab.sinistro, mergeChanges: true)
                }
        } else {
            Text("Sinistro non più disponibile")
                .foregroundColor(.secondary)
                .onAppear {
                    appState.closeTab(id: tab.id)
                }
        }
    }
    
    // MARK: - Helper Methods
    
    private func performFolderScanIfNeeded() {
        // I file sono ora gestiti internamente in Application Support
        // Non è più necessaria la scansione delle cartelle esterne
    }
    
    private func formatCurrency(_ value: Double) -> String {
        CurrencyFormatter.shared.format(value)
    }
}

// Vista per le righe della tabella sinistri
struct SinistroTableRow: View {
    @Environment(\.managedObjectContext) private var viewContext
    let sinistro: Sinistro
    let viewModel: SinistriViewModel
    let activeTaskCount: Int
    let activeTasks: [DailyTask] // Pre-calcolato dalla vista padre
    let statoColor: Color
    let priorityValue: Double
    let mostraSiglaCompagnia: Bool
    var isSelected: Bool = false
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onOpenInNewWindow: () -> Void
    
    private let maxBeniVisibili = 3

    private var isSinistroClosed: Bool {
        let closedStates = [
            StatoManager.StatoSinistro.chiusa.descrizione,
            StatoManager.StatoSinistro.revocata.descrizione,
            StatoManager.StatoSinistro.annullata.descrizione
        ]
        return closedStates.contains(sinistro.stato ?? "")
    }

    private var shouldShowAssigneeIndicator: Bool {
        guard
            let current = GoogleAuthService.shared.userEmail?.lowercased(),
            !current.isEmpty
        else { return false }
        let assigned = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail ?? "").lowercased()
        return !assigned.isEmpty && assigned != current
    }
    
    private var priorityLabel: String {
        if priorityValue > 0.90 {
            if PriorityCalculator.shared.isCriticallyUrgent(for: sinistro) {
                return "Critica"
            } else {
                return "Molto Alta"
            }
        }
        
        switch priorityValue {
        case ..<0.25:       // Include valori negativi
            return "Bassa"
        case 0.25..<0.60:
            return "Media"
        case 0.60..<0.90:
            return "Alta"
        default:
            return "Alta"
        }
    }
    
    private var priorityColor: Color {
        if priorityValue > 0.90 {
            if PriorityCalculator.shared.isCriticallyUrgent(for: sinistro) {
                return .red
            } else {
                return Color(nsColor: .systemPurple)
            }
        }
        
        switch priorityValue {
        case ..<0.25:       // Include valori negativi
            return .green
        case 0.25..<0.60:
            return .yellow
        case 0.60..<0.90:
            return .orange
        default:
            return .orange
        }
    }
    
    // priorityBreakdown calcolato lazy solo quando si apre il popover
    private var priorityBreakdown: PriorityBreakdown {
        return PriorityCalculator.shared.calculatePriorityBreakdown(for: sinistro)
    }
    
    private var hasManualPriority: Bool {
        return sinistro.value(forKey: "prioritaManuale") as? Double != nil
    }
    
    private var taskTooltip: String {
        guard !activeTasks.isEmpty else { return "" }
        
        let taskNames = activeTasks.map { task -> String in
            let statusIcon = (task.status == TaskStatus.inProgress) ? "▶" : "○"
            return "\(statusIcon) \(task.title)"
        }
        
        return taskNames.joined(separator: "\n")
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Riferimento (visualizzato con sigla compagnia se abilitato)
            HStack(spacing: 6) {
                Text(sinistro.riferimentoVisualizzato)
                    .lineLimit(1)
                if shouldShowAssigneeIndicator {
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .help("Assegnato a \(sinistro.assignedToUserName ?? sinistro.assignedToUserEmail ?? "utente")")
                }
            }
            .frame(width: mostraSiglaCompagnia ? 150 : 120, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .onTapGesture(count: 2, perform: onDoubleTap)
            .onTapGesture(count: 1, perform: onTap)
            .contextMenu {
                    Button {
                        // Copia sempre il riferimento numerico puro
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(sinistro.riferimento ?? "", forType: .string)
                    } label: {
                        Label("Copia Riferimento", systemImage: "doc.on.doc")
                    }
                    
                    Button {
                        onOpenInNewWindow()
                    } label: {
                        Label("Apri in nuova finestra", systemImage: "rectangle.split.2x1")
                    }
            }
            
            // Stato - Expandable Pill
            ExpandableStatoPill(sinistro: sinistro, viewModel: viewModel)
                .frame(width: 180, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            
            // Assicurato
            Text(sinistro.nomeAssicurato ?? "N/D")
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            
            // Priorità - Expandable Pill
            Group {
                if isSinistroClosed && activeTasks.isEmpty {
                    Text("-")
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .center)
                } else {
                    ExpandablePriorityPill(
                        sinistro: sinistro,
                        priorityValue: priorityValue,
                        priorityLabel: priorityLabel,
                        priorityColor: priorityColor,
                        breakdown: priorityBreakdown,
                        hasManualPriority: hasManualPriority,
                        isCompensated: priorityBreakdown.isCompensated,
                        onManualPriorityChange: { level in
                            viewModel.changePriority(for: sinistro, to: level, context: viewContext)
                        }
                    )
                    .environment(\.managedObjectContext, viewContext)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            
            // Compagnia (solo se sigla non mostrata nel riferimento)
            if !mostraSiglaCompagnia {
                Text(sinistro.nomeCompagnia ?? "N/D")
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
            
            // Grado (Complessità)
            ExpandableComplessitaPill(
                sinistro: sinistro,
                grado: sinistro.gradoComplessita,
                complessitaText: sinistro.complessita
            )
            .environment(\.managedObjectContext, viewContext)
            .frame(width: 90, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            
            // Beni coinvolti
            ExpandableBeniPill(beni: sinistro.beniPerxia)
                .frame(width: 70, alignment: .center)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            
            // Solleciti ricevuti
            ExpandableSollecitiPill(sinistro: sinistro)
                .environment(\.managedObjectContext, viewContext)
                .frame(width: 80, alignment: .center)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            
            // Task
            ExpandableTaskPill(tasks: activeTasks)
                .frame(width: 60, alignment: .center)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            
            // Liquidato
            if let liquidato = sinistro.liquidato?.doubleValue, liquidato > 0 {
                Text(CurrencyFormatter.shared.formatWithSymbol(liquidato))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            } else {
                Text("-")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : statoColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : statoColor.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                )
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onDoubleTap)
        .onTapGesture(count: 1, perform: onTap)
    }
}

// MARK: - Bubble Components

/// Bubble per il grado di complessità
// MARK: - Expandable Complessità Pill

struct ExpandableComplessitaPill: View {
    @Environment(\.managedObjectContext) private var viewContext
    let sinistro: Sinistro
    let grado: Sinistro.GradoComplessita
    let complessitaText: String?
    
    @State private var showPopover = false
    @State private var isHovering = false
    @State private var selectedGrado: Sinistro.GradoComplessita = .unknown
    @State private var hoveringGrado: Sinistro.GradoComplessita? = nil
    
    private var gradoColor: Color {
        Color(red: grado.color.red, green: grado.color.green, blue: grado.color.blue)
    }
    
    private var fontWeight: Font.Weight {
        switch grado {
        case .bassa: return .regular
        case .media: return .medium
        case .alta: return .semibold
        case .moltaAlta: return .bold
        case .unknown: return .regular
        }
    }
    
    var body: some View {
        if grado == .unknown {
            Text("-")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        } else {
            pillView
                .onHover { hovering in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        isHovering = hovering
                    }
                }
                .onTapGesture { showPopover = true }
                .popover(isPresented: $showPopover, arrowEdge: .bottom) { popoverContent }
                .onAppear { selectedGrado = grado }
        }
    }
    
    private var pillView: some View {
        Text(grado.rawValue)
            .font(.system(size: 11, weight: fontWeight))
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.gray.opacity(0.12))
                    .shadow(color: Color.gray.opacity(isHovering ? 0.2 : 0.08), radius: isHovering ? 4 : 2, y: 1)
            )
            .overlay(Capsule().stroke(Color.gray.opacity(isHovering ? 0.25 : 0.12), lineWidth: 1))
            .scaleEffect(isHovering ? 1.03 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
    }
    
    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Complessità")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(grado.rawValue)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(gradoColor)
            }
            .padding(14)
            .background(LinearGradient(colors: [gradoColor.opacity(0.12), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            
            Divider()
            
            // Criteri determinazione
            VStack(alignment: .leading, spacing: 10) {
                Text("CRITERI DI VALUTAZIONE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                criterioRow(icon: "cube.box", label: "Numero beni", value: "\(sinistro.beniPerxia.count)", highlight: sinistro.beniPerxia.count > 5)
                criterioRow(icon: "eurosign.circle", label: "Importo richiesta", value: formatImporto(sinistro.richiesta?.doubleValue), highlight: (sinistro.richiesta?.doubleValue ?? 0) > 10000)
                criterioRow(icon: "doc.text", label: "Tipo polizza", value: sinistro.tipoPolizza ?? "N/D", highlight: false)
                
                if sinistro.oltreDieciBeni {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Oltre 10 beni dichiarati")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(14)
            
            Divider()
            
            // Cambia manualmente
            VStack(alignment: .leading, spacing: 8) {
                Text("IMPOSTA MANUALMENTE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 6) {
                    ForEach(Sinistro.GradoComplessita.allCases.filter { $0 != .unknown }, id: \.rawValue) { g in
                        gradoButton(g)
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 280)
    }
    
    @ViewBuilder
    private func criterioRow(icon: String, label: String, value: String, highlight: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(highlight ? .orange : .secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(highlight ? .orange : .primary)
        }
    }
    
    @ViewBuilder
    private func gradoButton(_ g: Sinistro.GradoComplessita) -> some View {
        let isSelected = selectedGrado == g
        let isHovered = hoveringGrado == g
        let color = Color(red: g.color.red, green: g.color.green, blue: g.color.blue)
        
        Button {
            setComplessita(g)
        } label: {
            Text(String(g.rawValue.prefix(3)))
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : (isHovered ? color : .secondary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? color : (isHovered ? color.opacity(0.15) : Color.clear)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(isSelected ? 0 : 0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { h in hoveringGrado = h ? g : nil }
    }
    
    private func formatImporto(_ value: Double?) -> String {
        guard let v = value, v > 0 else { return "N/D" }
        return CurrencyFormatter.shared.formatWithSymbol(v)
    }
    
    private func setComplessita(_ g: Sinistro.GradoComplessita) {
        selectedGrado = g
        sinistro.complessita = g.rawValue
        try? viewContext.save()
    }
}

// MARK: - Expandable Beni Pill

struct ExpandableBeniPill: View {
    let beni: [PerxiaBene]
    
    @State private var showPopover = false
    @State private var isHovering = false
    
    private var fontWeight: Font.Weight {
        switch beni.count {
        case 1...2: return .regular
        case 3...5: return .medium
        case 6...10: return .semibold
        default: return .bold
        }
    }
    
    var body: some View {
        if beni.isEmpty {
            Text("-")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        } else {
            pillView
                .onHover { hovering in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        isHovering = hovering
                    }
                }
                .onTapGesture { showPopover = true }
                .popover(isPresented: $showPopover, arrowEdge: .bottom) { popoverContent }
        }
    }
    
    private var pillView: some View {
        HStack(spacing: 4) {
            Image(systemName: "cube.box.fill")
                .font(.system(size: 9))
            Text("\(beni.count)")
                .font(.system(size: 11, weight: fontWeight))
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.gray.opacity(0.12))
                .shadow(color: Color.gray.opacity(isHovering ? 0.2 : 0.08), radius: isHovering ? 4 : 2, y: 1)
        )
        .overlay(Capsule().stroke(Color.gray.opacity(isHovering ? 0.25 : 0.12), lineWidth: 1))
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
    }
    
    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Beni Coinvolti")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(beni.count)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)
            }
            .padding(14)
            .background(LinearGradient(colors: [Color.blue.opacity(0.1), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            
            Divider()
            
            // Lista beni compatta
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(beni.enumerated()), id: \.element.id) { index, bene in
                        beneRow(bene, index: index + 1)
                        if index < beni.count - 1 { Divider().padding(.leading, 32) }
                    }
                }
            }
            .frame(maxHeight: 250)
        }
        .frame(width: 300)
    }
    
    @ViewBuilder
    private func beneRow(_ bene: PerxiaBene, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.blue))
            
            VStack(alignment: .leading, spacing: 3) {
                Text(bene.tipologia)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                // Richiesta se presente
                if let stima = bene.stimaEconomica, !stima.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "eurosign.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                        Text(stima)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.green)
                    }
                }
                
                // Componenti se presenti
                if let componenti = bene.componenti, !componenti.isEmpty {
                    Text(componenti)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Expandable Solleciti Pill

struct ExpandableSollecitiPill: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var sinistro: Sinistro
    
    @State private var showPopover = false
    @State private var isHovering = false
    
    // Form per nuovo sollecito
    @State private var nuovoTipoMittente: TipoMittenteSollecito = .unknown
    @State private var nuoveNote: String = ""
    @State private var nuovaData: Date = Date()
    
    private var solleciti: [SollecitoRicevuto] {
        sinistro.sollecitiRicevutiArray
    }
    
    private var count: Int {
        Int(sinistro.sollecitiRicevutiCount)
    }
    
    private var pillColor: Color {
        guard count > 0 else { return .secondary }
        switch sinistro.tipoMittenteSollecitoMaxEnum {
        case .liquidatoreCompagnia: return .red
        case .studio: return .orange
        case .agenzia: return .yellow
        case .assicurato: return .mint
        case .unknown: return .gray
        }
    }
    
    var body: some View {
        if count == 0 {
            Text("-")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .onTapGesture { showPopover = true }
                .popover(isPresented: $showPopover, arrowEdge: .bottom) { popoverContent }
        } else {
            pillView
                .onHover { hovering in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        isHovering = hovering
                    }
                }
                .onTapGesture { showPopover = true }
                .popover(isPresented: $showPopover, arrowEdge: .bottom) { popoverContent }
        }
    }
    
    private var pillView: some View {
        HStack(spacing: 4) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 9))
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.gray.opacity(0.12))
                .shadow(color: Color.gray.opacity(isHovering ? 0.2 : 0.08), radius: isHovering ? 4 : 2, y: 1)
        )
        .overlay(Capsule().stroke(Color.gray.opacity(isHovering ? 0.25 : 0.12), lineWidth: 1))
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
    }
    
    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 14))
                        .foregroundColor(count > 0 ? pillColor : .secondary)
                    Text("Solleciti Ricevuti")
                        .font(.system(size: 14, weight: .semibold))
                }
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(pillColor)
                }
            }
            .padding(14)
            .background(
                LinearGradient(colors: [pillColor.opacity(count > 0 ? 0.1 : 0.05), Color.clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            
            Divider()
            
            // Lista solleciti
            if solleciti.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                        Text("Nessun sollecito ricevuto")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(solleciti) { sollecito in
                            sollecitoRow(sollecito)
                            if sollecito.id != solleciti.last?.id {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            
            Divider()
            
            // Sezione per aggiungere nuovo sollecito
            VStack(alignment: .leading, spacing: 10) {
                Text("REGISTRA SOLLECITO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                // Tipo mittente
                HStack(spacing: 6) {
                    ForEach(TipoMittenteSollecito.allCases, id: \.rawValue) { tipo in
                        tipoMittenteButton(tipo)
                    }
                }
                
                // Data ricezione
                DatePicker("Data:", selection: $nuovaData, displayedComponents: [.date])
                    .datePickerStyle(.compact)
                    .font(.system(size: 11))
                
                // Note (opzionali)
                TextField("Note (opzionale)", text: $nuoveNote)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                
                // Pulsante aggiungi
                Button {
                    aggiungiSollecito()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Aggiungi Sollecito")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(nuovoTipoMittente != .unknown ? Color.accentColor : Color.secondary.opacity(0.3))
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(nuovoTipoMittente == .unknown)
            }
            .padding(14)
        }
        .frame(width: 320)
    }
    
    @ViewBuilder
    private func sollecitoRow(_ sollecito: SollecitoRicevuto) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Icona mittente
            Image(systemName: iconForMittente(sollecito.tipoMittente))
                .font(.system(size: 12))
                .foregroundColor(colorForMittente(sollecito.tipoMittente))
                .frame(width: 24, height: 24)
                .background(Circle().fill(colorForMittente(sollecito.tipoMittente).opacity(0.15)))
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("da \(sollecito.tipoMittente.descrizione)")
                        .font(.system(size: 12, weight: .medium))
                    
                    if sollecito.isManuale {
                        Text("(manuale)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(sollecito.dataFormattata)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                if let note = sollecito.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Pulsante rimuovi
            Button {
                rimuoviSollecito(id: sollecito.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Rimuovi sollecito")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    @ViewBuilder
    private func tipoMittenteButton(_ tipo: TipoMittenteSollecito) -> some View {
        let isSelected = nuovoTipoMittente == tipo
        let color = colorForMittente(tipo)
        
        Button {
            nuovoTipoMittente = tipo
        } label: {
            VStack(spacing: 2) {
                Image(systemName: iconForMittente(tipo))
                    .font(.system(size: 12))
                Text(shortLabel(tipo))
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? color : color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func iconForMittente(_ tipo: TipoMittenteSollecito) -> String {
        switch tipo {
        case .unknown: return "questionmark.circle"
        case .assicurato: return "person.fill"
        case .agenzia: return "building.2.fill"
        case .studio: return "briefcase.fill"
        case .liquidatoreCompagnia: return "building.columns.fill"
        }
    }
    
    private func colorForMittente(_ tipo: TipoMittenteSollecito) -> Color {
        switch tipo {
        case .unknown: return .gray
        case .assicurato: return .mint
        case .agenzia: return .yellow
        case .studio: return .orange
        case .liquidatoreCompagnia: return .red
        }
    }
    
    private func shortLabel(_ tipo: TipoMittenteSollecito) -> String {
        switch tipo {
        case .unknown: return "N/D"
        case .assicurato: return "Ass."
        case .agenzia: return "Ag."
        case .studio: return "Studio"
        case .liquidatoreCompagnia: return "Liq."
        }
    }
    
    private func aggiungiSollecito() {
        let nuovo = SollecitoRicevuto(
            dataRicezione: nuovaData,
            tipoMittente: nuovoTipoMittente,
            note: nuoveNote.isEmpty ? nil : nuoveNote,
            isManuale: true
        )
        
        sinistro.aggiungiSollecito(nuovo)
        
        do {
            try viewContext.save()
            print("[SollecitiPill] ✅ Sollecito aggiunto per \(sinistro.riferimento ?? "N/A")")
            
            // Reset form
            nuovoTipoMittente = .unknown
            nuoveNote = ""
            nuovaData = Date()
        } catch {
            print("[SollecitiPill] ❌ Errore salvataggio: \(error)")
        }
    }
    
    private func rimuoviSollecito(id: UUID) {
        sinistro.rimuoviSollecito(id: id)
        
        do {
            try viewContext.save()
            print("[SollecitiPill] ✅ Sollecito rimosso")
        } catch {
            print("[SollecitiPill] ❌ Errore rimozione: \(error)")
        }
    }
}

// MARK: - Expandable Stato Pill

struct ExpandableStatoPill: View {
    @ObservedObject var sinistro: Sinistro
    let viewModel: SinistriViewModel
    
    @State private var showPopover = false
    @State private var isHovering = false
    
    private var info: StatoPopoverInfo {
        viewModel.getStatoInfo(for: sinistro)
    }
    
    var body: some View {
        if let stato = info.stato {
            pillView(stato: stato, descrizione: info.descrizione)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        isHovering = hovering
                    }
                }
                .onTapGesture { showPopover = true }
                .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                    popoverContent(stato: stato)
                }
        } else {
            Text(sinistro.stato ?? "N/D")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
    
    private func pillView(stato: StatoManager.StatoSinistro, descrizione: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: stato.icon)
                .font(.system(size: 10))
            Text(descrizione)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(LinearGradient(colors: [info.statoColor, info.statoColor.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: info.statoColor.opacity(isHovering ? 0.5 : 0.2), radius: isHovering ? 8 : 3, y: 2)
        )
        .overlay(Capsule().stroke(Color.white.opacity(isHovering ? 0.5 : 0), lineWidth: 1.5))
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
    }
    
    private func popoverContent(stato: StatoManager.StatoSinistro) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header con stato attuale
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stato Sinistro")
                        .font(.system(size: 14, weight: .semibold))
                    Text(sinistro.riferimento ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Badge stato attuale
                HStack(spacing: 4) {
                    Image(systemName: stato.icon)
                        .font(.system(size: 10))
                    Text(info.descrizione)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(info.statoColor)
                        .shadow(color: info.statoColor.opacity(0.4), radius: 4, y: 2)
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [info.statoColor.opacity(0.15), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            Divider()
            
            // Dettagli temporali
            VStack(alignment: .leading, spacing: 10) {
                Text("DETTAGLI TEMPORALI")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                if info.hasData, let data = info.dataStato {
                    infoRow(
                        icon: "calendar",
                        label: "In questo stato dal",
                        value: formatDate(data),
                        highlight: false
                    )
                    
                    infoRow(
                        icon: "clock",
                        label: "Giorni totali",
                        value: "\(info.giorniTotali)",
                        highlight: info.giorniTotali > 30
                    )
                    
                    infoRow(
                        icon: "briefcase",
                        label: "Giorni lavorativi",
                        value: "\(info.giorniLavorativi)",
                        highlight: info.giorniLavorativi > 20
                    )
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Data cambio stato non disponibile")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            
            // Sezione Cicli di Controllo
            if info.hasCicliControllo {
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("CICLI DI CONTROLLO")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(info.cicliControllo.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.mint)
                    }
                    .padding(.bottom, 4)
                    
                    ForEach(info.cicliControllo.prefix(3)) { ciclo in
                        cicloControlloRow(ciclo)
                    }
                    
                    if info.cicliControllo.count > 1 {
                        let stats = info.statisticheControllo
                        HStack(spacing: 8) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("Totale: \(stats.giorniLavorativiTotali) gg lav in \(stats.numeroCicli) cicli")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            
            // Info categoria stato
            if stato.category != .sistema {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("CATEGORIA")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Image(systemName: stato.stateGroup.icon)
                            .font(.system(size: 12))
                            .foregroundColor(stato.stateGroup.color)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stato.stateGroup.shortLabel)
                                .font(.system(size: 12, weight: .medium))
                            
                            Text(viewModel.categoriaDescrizione(stato.category))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 300)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func infoRow(icon: String, label: String, value: String, highlight: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(highlight ? .orange : .secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(highlight ? .orange : .primary)
        }
    }
    
    @ViewBuilder
    private func cicloControlloRow(_ ciclo: CicloControllo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(ciclo.isAperto ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                
                Text(ciclo.tipoEntrata.rawValue)
                    .font(.system(size: 11, weight: .medium))
                
                Spacer()
                
                if ciclo.isAperto {
                    let giorniLav = ItalianCalendarService.shared.getWorkingDaysSince(ciclo.dataEntrata)
                    Text("\(giorniLav) gg lav")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                } else if let durata = ciclo.durataGiorniLavorativi {
                    Text("\(durata) gg lav")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                }
            }
            
            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                
                Text(formatDateShort(ciclo.dataEntrata))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                if let uscita = ciclo.dataUscita {
                    Text("→")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(formatDateShort(uscita))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    if let tipoUscita = ciclo.tipoUscita {
                        Text("(\(tipoUscita.rawValue))")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("→ in corso")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(ciclo.isAperto ? Color.orange.opacity(0.1) : Color.green.opacity(0.05))
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        DateUtils.formatMediumWithTime(date)
    }
    
    private func formatDateShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy"
        return formatter.string(from: date)
    }
}

// MARK: - Expandable Task Pill

struct ExpandableTaskPill: View {
    let tasks: [DailyTask]
    
    @State private var showPopover = false
    @State private var isHovering = false
    
    var body: some View {
        if tasks.isEmpty {
            Text("-")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        } else {
            pillView
                .onHover { hovering in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        isHovering = hovering
                    }
                }
                .onTapGesture { showPopover = true }
                .popover(isPresented: $showPopover, arrowEdge: .bottom) { popoverContent }
        }
    }
    
    private var pillView: some View {
        HStack(spacing: 4) {
            Image(systemName: "checklist")
                .font(.system(size: 9))
            Text("\(tasks.count)")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.gray.opacity(0.12))
                .shadow(color: Color.gray.opacity(isHovering ? 0.2 : 0.08), radius: isHovering ? 4 : 2, y: 1)
        )
        .overlay(Capsule().stroke(Color.gray.opacity(isHovering ? 0.25 : 0.12), lineWidth: 1))
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
    }
    
    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Task Attive")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.purple)
            }
            .padding(14)
            .background(LinearGradient(colors: [Color.purple.opacity(0.1), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            
            Divider()
            
            // Lista task
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tasks) { task in
                        TaskRowView(task: task)
                        if task.id != tasks.last?.id { Divider().padding(.leading, 36) }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 320)
    }
}

// MARK: - Task Row View

struct TaskRowView: View {
    let task: DailyTask
    @State private var isHovering = false
    
    private var sourceIcon: String {
        // Determina icona in base al tipo o metadata
        if let _ = task.metadata["emailId"] { return "envelope.fill" }
        if let _ = task.metadata["whatsappChatId"] { return "message.fill" }
        if task.type == .aiGenerated { return "sparkles" }
        if task.type == .reminder { return "bell.fill" }
        if task.type == .manual { return "hand.raised.fill" }
        return "gearshape.fill"
    }
    
    private var sourceColor: Color {
        if let _ = task.metadata["emailId"] { return .blue }
        if let _ = task.metadata["whatsappChatId"] { return .green }
        if task.type == .aiGenerated { return .purple }
        if task.type == .reminder { return .orange }
        return .secondary
    }
    
    private var statusColor: Color {
        switch task.status {
        case .pending: return .orange
        case .inProgress: return .blue
        case .completed: return .green
        case .cancelled: return .red
        case .expired: return .gray
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Icona fonte
            Image(systemName: sourceIcon)
                .font(.system(size: 12))
                .foregroundColor(sourceColor)
                .frame(width: 24, height: 24)
                .background(Circle().fill(sourceColor.opacity(0.15)))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Status e deadline
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(task.status == .inProgress ? "In corso" : "In attesa")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    
                    if let deadline = task.deadline {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text(formatDeadline(deadline))
                                .font(.system(size: 9))
                        }
                        .foregroundColor(deadline < Date() ? .red : .secondary)
                    }
                }
            }
            
            Spacer()
            
            // Azioni
            HStack(spacing: 4) {
                Button {
                    completeTask()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .help("Completa")
                
                Button {
                    cancelTask()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Annulla")
            }
            .opacity(isHovering ? 1 : 0.5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isHovering ? Color.secondary.opacity(0.05) : Color.clear)
        .onHover { isHovering = $0 }
    }
    
    private func formatDeadline(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func completeTask() {
        TaskManager.shared.markTaskCompleted(taskID: task.id, manually: true)
    }
    
    private func cancelTask() {
        TaskManager.shared.deleteTask(taskID: task.id)
    }
}

// Legacy components (kept for compatibility)

struct GradoBubble: View {
    let grado: Sinistro.GradoComplessita
    
    var body: some View {
        if grado == .unknown {
            Text("-")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        } else {
            Text(grado.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(
                            red: grado.color.red,
                            green: grado.color.green,
                            blue: grado.color.blue
                        ))
                )
        }
    }
}

/// Bubbles per i beni coinvolti (legacy)
struct BeniCoinvoltiBubbles: View {
    let beni: [PerxiaBene]
    
    /// Tooltip con elenco completo dei beni
    private var tooltipText: String {
        if beni.isEmpty { return "Nessun bene" }
        return beni.enumerated().map { index, bene in
            let base = "\(index + 1). \(bene.tipologia)"
            if let modello = bene.modello, !modello.isEmpty {
                return "\(base) (\(modello))"
            }
            return base
        }.joined(separator: "\n")
    }
    
    var body: some View {
        if beni.isEmpty {
            Text("-")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        } else {
            Text("\(beni.count) \(beni.count == 1 ? "bene" : "beni")")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.7))
                )
                .help(tooltipText)
        }
    }
}

struct MainTabDropDelegate: DropDelegate {
    let tab: TabInfo
    let appState: AppState
    @Binding var draggedTab: TabInfo?
    @Binding var draggedTabSourceWindowId: String?
    @Binding var isDragging: Bool
    @Binding var showDetachIndicator: Bool
    @Binding var dragLocation: CGPoint
    let onDetach: () -> Void
    
    // Soglia per il magnete (in pixel)
    private let magnetThreshold: CGFloat = 30
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedTab = draggedTab else { return false }
        
        // Reset stati
        isDragging = false
        showDetachIndicator = false
        
        // Verifica se il drop è dentro la tab bar (con margine per il magnete)
        let isInTabBar = info.location.x >= -magnetThreshold && 
                        info.location.y >= -magnetThreshold &&
                        info.location.y <= 60 // Altezza tab bar + margine
        
        if isInTabBar {
            let sourceWindowId = draggedTabSourceWindowId
            
            // Se la tab proviene dalla stessa finestra (principale), spostala normalmente
            if sourceWindowId == nil {
                if let sourceIndex = appState.openTabs.firstIndex(where: { $0.id == draggedTab.id }),
                   let destinationIndex = appState.openTabs.firstIndex(where: { $0.id == tab.id }) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        appState.moveTab(from: sourceIndex, to: destinationIndex, windowId: nil)
                    }
                }
            } else {
                // Tab da una finestra detached: spostala nella finestra principale
                if let destinationIndex = appState.openTabs.firstIndex(where: { $0.id == tab.id }) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        appState.moveTabBetweenWindows(
                            tab: draggedTab,
                            fromWindowId: sourceWindowId,
                            toWindowId: nil,
                            atIndex: destinationIndex
                        )
                    }
                } else {
                    // Aggiungi alla fine
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        appState.moveTabBetweenWindows(
                            tab: draggedTab,
                            fromWindowId: sourceWindowId,
                            toWindowId: nil,
                            atIndex: nil
                        )
                    }
                }
            }
        } else {
            // Drop fuori dalla tab bar, detach
            onDetach()
        }
        
        self.draggedTab = nil
        self.draggedTabSourceWindowId = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedTab = draggedTab else { return }
        
        // Applica effetto magnete se siamo vicini alla tab bar
        let isNearTabBar = info.location.y >= -magnetThreshold && info.location.y <= 60
        let sourceWindowId = draggedTabSourceWindowId
        
        if isNearTabBar {
            // Se proviene dalla stessa finestra (principale)
            if sourceWindowId == nil {
                if let sourceIndex = appState.openTabs.firstIndex(where: { $0.id == draggedTab.id }),
                   let destinationIndex = appState.openTabs.firstIndex(where: { $0.id == tab.id }),
                   sourceIndex != destinationIndex {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        appState.moveTab(from: sourceIndex, to: destinationIndex, windowId: nil)
                    }
                }
            }
            // Se proviene da un'altra finestra, lo spostamento avviene solo al drop
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        dragLocation = info.location
        
        // Mostra indicatore detach se il mouse si allontana dalla tab bar
        let isFarFromTabBar = info.location.y < -50 || info.location.y > 100
        showDetachIndicator = isFarFromTabBar
        
        // Proposta di drop con effetto magnete
        let isInTabBar = info.location.x >= -magnetThreshold && 
                        info.location.y >= -magnetThreshold &&
                        info.location.y <= 60
        
        return DropProposal(operation: isInTabBar ? .move : .copy)
    }
    
    func dropExited(info: DropInfo) {
        // Mantieni l'indicatore se siamo ancora in drag
        if isDragging {
            let isFarFromTabBar = info.location.y < -50 || info.location.y > 100
            showDetachIndicator = isFarFromTabBar
        }
    }
}

// MARK: - Manual Priority Level

enum ManualPriorityLevel: String, CaseIterable {
    case automatica = "Automatica"
    case bassa = "Bassa"
    case media = "Media"
    case alta = "Alta"
    case moltoAlta = "Molto Alta"
    case critica = "Critica"
    
    var value: Double? {
        switch self {
        case .automatica: return nil
        case .bassa: return 0.15
        case .media: return 0.45
        case .alta: return 0.75
        case .moltoAlta: return 0.92
        case .critica: return 1.0
        }
    }
    
    var color: Color {
        switch self {
        case .automatica: return .secondary
        case .bassa: return .green
        case .media: return .yellow
        case .alta: return .orange
        case .moltoAlta: return Color(nsColor: .systemPurple)
        case .critica: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .automatica: return "wand.and.stars"
        case .bassa: return "arrow.down.circle"
        case .media: return "equal.circle"
        case .alta: return "arrow.up.circle"
        case .moltoAlta: return "exclamationmark.circle"
        case .critica: return "flame"
        }
    }
    
    static func from(value: Double?) -> ManualPriorityLevel {
        guard let v = value else { return .automatica }
        switch v {
        case ..<0.25: return .bassa       // Include valori negativi
        case 0.25..<0.60: return .media
        case 0.60..<0.90: return .alta
        case 0.90..<0.98: return .moltoAlta
        default: return .critica
        }
    }
}

// MARK: - Expandable Priority Pill

struct ExpandablePriorityPill: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var sinistro: Sinistro
    let priorityValue: Double
    let priorityLabel: String
    let priorityColor: Color
    let breakdown: PriorityBreakdown
    let hasManualPriority: Bool
    let isCompensated: Bool
    var onManualPriorityChange: ((ManualPriorityLevel) -> Void)?
    
    @State private var showPopover = false
    @State private var isHovering = false
    @State private var hoveringLevel: ManualPriorityLevel? = nil
    @State private var selectedLevel: ManualPriorityLevel = .automatica
    
    private var fontWeight: Font.Weight {
        switch priorityValue {
        case ..<0.25: return .regular
        case 0.25..<0.60: return .medium
        case 0.60..<0.80: return .semibold
        default: return .bold
        }
    }
    
    var body: some View {
        // Pillola con popover nativo
        pillView
            .frame(width: 80, alignment: .center)
            .onHover { hovering in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    isHovering = hovering
                }
            }
            .onTapGesture {
                showPopover = true
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                popoverContent
            }
            .onAppear {
                let currentManual = sinistro.value(forKey: "prioritaManuale") as? Double
                selectedLevel = ManualPriorityLevel.from(value: currentManual)
            }
    }
    
    // MARK: - Pillola
    
    private var pillView: some View {
        HStack(spacing: 4) {
            Text(priorityLabel)
                .font(.system(size: 11, weight: fontWeight))
                .foregroundColor(.primary)
            
            if hasManualPriority {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            
            if isCompensated {
                Text("?")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .help("Priorità compensata: indicatori contrastanti (es. urgenza ma atto inviato)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.gray.opacity(0.12))
                .shadow(color: Color.gray.opacity(isHovering ? 0.2 : 0.08), radius: isHovering ? 4 : 2, y: 1)
        )
        .overlay(Capsule().stroke(Color.gray.opacity(isHovering ? 0.25 : 0.12), lineWidth: 1))
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
    }
    
    // MARK: - Popover Content
    
    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(priorityColor.opacity(0.2))
                            .frame(width: 32, height: 32)
                        Circle()
                            .fill(priorityColor)
                            .frame(width: 12, height: 12)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Priorità")
                            .font(.system(size: 14, weight: .semibold))
                        Text(sinistro.riferimento ?? "")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Punteggio grande
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.2f", breakdown.finalPriority))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(priorityColor)
                    Text("su 1.00")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [priorityColor.opacity(0.1), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            Divider()
            
            // Breakdown
            VStack(alignment: .leading, spacing: 0) {
                Text("COMPOSIZIONE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
                
                VStack(alignment: .leading, spacing: 8) {
                    breakdownRow("Età sinistro", value: breakdown.etaComponent, icon: "calendar", maxVal: 1.0)
                    
                    if breakdown.obiettvoComponent > 0 {
                        breakdownRow("Obiettivo mensile", value: breakdown.obiettvoComponent, icon: "target", maxVal: 0.4)
                    }
                    if breakdown.accelerazioneComponent > 0 {
                        breakdownRow("Accelerazione", value: breakdown.accelerazioneComponent, icon: "hare", maxVal: 0.2)
                    }
                    if breakdown.complessitaComponent > 0 {
                        breakdownRow("Complessità", value: breakdown.complessitaComponent, icon: "square.stack.3d.up", maxVal: 0.3)
                    }
                    if breakdown.sollecitiRicevutiComponent > 0 {
                        breakdownRow("Solleciti ricevuti", value: breakdown.sollecitiRicevutiComponent, icon: "bell.badge.fill", maxVal: 1.0, highlight: true)
                    }
                    if breakdown.sollecitiInviatiDebuff < 0 {
                        breakdownRow("Solleciti inviati", value: breakdown.sollecitiInviatiDebuff, icon: "paperplane.fill", maxVal: 0.5, showSign: true)
                    }
                    if breakdown.backlogComponent > 0 {
                        breakdownRow("Backlog", value: breakdown.backlogComponent, icon: "clock.arrow.circlepath", maxVal: 0.8, highlight: true)
                    }
                    if breakdown.statoComponent != 0 {
                        breakdownRow("Impatto stato", value: breakdown.statoComponent, icon: "flag.fill", maxVal: 0.5, showSign: true)
                    }
                }
            }
            .padding(16)
            
            Divider()
            
            // Imposta priorità
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("IMPOSTA MANUALMENTE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(ManualPriorityLevel.allCases, id: \.rawValue) { level in
                        priorityButton(for: level)
                    }
                }
                
                if breakdown.isManual {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                        Text("Priorità impostata manualmente")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.orange)
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .frame(width: 320)
    }
    
    // MARK: - Breakdown Row
    
    @ViewBuilder
    private func breakdownRow(_ label: String, value: Double, icon: String, maxVal: Double, showSign: Bool = false, highlight: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(highlight ? .orange : .secondary)
                .frame(width: 16)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(highlight ? .primary : .secondary)
            
            Spacer()
            
            // Barra
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 60, height: 6)
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: value >= 0
                                ? [highlight ? Color.orange : Color.accentColor, (highlight ? Color.orange : Color.accentColor).opacity(0.6)]
                                : [Color.red, Color.red.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(3, 60 * CGFloat(min(abs(value) / maxVal, 1.0))), height: 6)
            }
            
            Text(showSign && value > 0 ? String(format: "+%.2f", value) : String(format: "%.2f", value))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(value < 0 ? .red : (highlight ? .orange : .primary))
                .frame(width: 42, alignment: .trailing)
        }
    }
    
    // MARK: - Priority Button
    
    @ViewBuilder
    private func priorityButton(for level: ManualPriorityLevel) -> some View {
        let isSelected = selectedLevel == level
        let isHovered = hoveringLevel == level
        
        Button {
            setManualPriority(level)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: level.icon)
                    .font(.system(size: 14, weight: .medium))
                Text(level == .automatica ? "Auto" : level.rawValue)
                    .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : (isHovered ? level.color : .primary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? level.color : (isHovered ? level.color.opacity(0.15) : Color(nsColor: .controlBackgroundColor)))
                    .shadow(color: isSelected ? level.color.opacity(0.4) : .clear, radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(level.color.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveringLevel = h ? level : nil
            }
        }
    }
    
    // MARK: - Actions
    
    private func setManualPriority(_ level: ManualPriorityLevel) {
        withAnimation(.spring(response: 0.2)) {
            selectedLevel = level
        }
        
        if let callback = onManualPriorityChange {
            callback(level)
        } else {
            if let value = level.value {
                sinistro.setValue(value, forKey: "prioritaManuale")
            } else {
                sinistro.setValue(nil, forKey: "prioritaManuale")
            }
            do {
                try viewContext.save()
            } catch {
                print("[ExpandablePriorityPill] ❌ Errore: \(error)")
            }
        }
    }
}

// MARK: - Priority Breakdown Popover (for context menu)

struct PriorityBreakdownPopover: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var sinistro: Sinistro
    let breakdown: PriorityBreakdown
    let onDismiss: () -> Void
    
    @State private var manualPriorityLevel: ManualPriorityLevel = .automatica
    @State private var isHovering: ManualPriorityLevel? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header con gradiente
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dettaglio Priorità")
                        .font(.system(size: 14, weight: .semibold))
                    Text(sinistro.riferimento ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Badge priorità attuale
                priorityBadge(for: breakdown.finalPriority, isManual: breakdown.isManual)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [colorForValue(breakdown.finalPriority).opacity(0.15), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            Divider()
            
            // Breakdown componenti
            VStack(alignment: .leading, spacing: 8) {
                Text("COMPOSIZIONE PUNTEGGIO")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                breakdownRow("Età sinistro", value: breakdown.etaComponent, maxValue: 1.0, icon: "calendar")
                
                if breakdown.obiettvoComponent > 0 {
                    breakdownRow("Obiettivo mensile", value: breakdown.obiettvoComponent, maxValue: 0.4, icon: "target")
                }
                
                if breakdown.accelerazioneComponent > 0 {
                    breakdownRow("Accelerazione", value: breakdown.accelerazioneComponent, maxValue: 0.2, icon: "hare")
                }
                
                if breakdown.complessitaComponent > 0 {
                    breakdownRow("Complessità", value: breakdown.complessitaComponent, maxValue: 0.3, icon: "square.stack.3d.up")
                }
                
                if breakdown.sollecitiRicevutiComponent > 0 {
                    breakdownRow("Solleciti ricevuti", value: breakdown.sollecitiRicevutiComponent, maxValue: 1.0, icon: "bell.badge", highlight: true)
                }
                
                if breakdown.sollecitiInviatiDebuff < 0 {
                    breakdownRow("Solleciti inviati", value: breakdown.sollecitiInviatiDebuff, maxValue: 0.5, icon: "paperplane", showSign: true)
                }
                
                if breakdown.backlogComponent > 0 {
                    breakdownRow("Backlog", value: breakdown.backlogComponent, maxValue: 0.8, icon: "clock.arrow.circlepath", highlight: true)
                }
                
                if breakdown.statoComponent != 0 {
                    breakdownRow("Impatto stato", value: breakdown.statoComponent, maxValue: 0.5, icon: "flag", showSign: true)
                }
            }
            .padding(16)
            
            // Totale con design prominente
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sum")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Punteggio totale")
                        .font(.system(size: 12, weight: .medium))
                }
                Spacer()
                
                HStack(spacing: 4) {
                    Text(String(format: "%.2f", breakdown.totalCalculated))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(colorForValue(breakdown.totalCalculated))
                    
                    Text("/ 1.00")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Override manuale
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("IMPOSTA MANUALMENTE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                // Griglia pulsanti priorità
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(ManualPriorityLevel.allCases, id: \.rawValue) { level in
                        priorityButton(for: level)
                    }
                }
                
                if breakdown.isManual {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text("Priorità impostata manualmente")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Spacer()
                        Button {
                            setManualPriority(.automatica)
                        } label: {
                            Text("Ripristina")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.orange.opacity(0.1))
                    )
                }
            }
            .padding(16)
        }
        .frame(width: 340)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            let currentManual = sinistro.value(forKey: "prioritaManuale") as? Double
            manualPriorityLevel = ManualPriorityLevel.from(value: currentManual)
        }
    }
    
    @ViewBuilder
    private func priorityBadge(for value: Double, isManual: Bool) -> some View {
        HStack(spacing: 4) {
            if isManual {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 9))
            }
            Text(priorityLabel(for: value))
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(colorForValue(value))
                .shadow(color: colorForValue(value).opacity(0.4), radius: 4, y: 2)
        )
    }
    
    private func priorityLabel(for value: Double) -> String {
        switch value {
        case ..<0.25: return "Bassa"       // Include valori negativi
        case 0.25..<0.60: return "Media"
        case 0.60..<0.90: return "Alta"
        case 0.90..<0.98: return "Molto Alta"
        default: return "Critica"
        }
    }
    
    @ViewBuilder
    private func priorityButton(for level: ManualPriorityLevel) -> some View {
        let isSelected = manualPriorityLevel == level
        let isHovered = isHovering == level
        
        Button {
            setManualPriority(level)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: level.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : level.color)
                
                Text(level == .automatica ? "Auto" : level.rawValue)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? level.color : (isHovered ? level.color.opacity(0.15) : Color(nsColor: .controlBackgroundColor)))
                    .shadow(color: isSelected ? level.color.opacity(0.3) : .clear, radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.clear : level.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering ? level : nil
        }
    }
    
    @ViewBuilder
    private func breakdownRow(_ label: String, value: Double, maxValue: Double, icon: String, showSign: Bool = false, highlight: Bool = false) -> some View {
        HStack(spacing: 10) {
            // Icona
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(highlight ? .orange : .secondary)
                .frame(width: 16)
            
            // Label
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(highlight ? .primary : .secondary)
            
            Spacer()
            
            // Barra progressiva con animazione
            ZStack(alignment: value >= 0 ? .leading : .trailing) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 70, height: 8)
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: value >= 0 
                                ? [highlight ? Color.orange : Color.accentColor, (highlight ? Color.orange : Color.accentColor).opacity(0.7)]
                                : [Color.red.opacity(0.7), Color.red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, 70 * CGFloat(min(abs(value) / maxValue, 1.0))), height: 8)
            }
            
            // Valore
            Text(showSign && value > 0 ? String(format: "+%.2f", value) : String(format: "%.2f", value))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(value < 0 ? .red : (highlight ? .orange : .primary))
                .frame(width: 42, alignment: .trailing)
        }
    }
    
    private func colorForValue(_ value: Double) -> Color {
        switch value {
        case ..<0.25: return .green       // Include valori negativi
        case 0.25..<0.60: return .yellow
        case 0.60..<0.90: return .orange
        case 0.90..<0.98: return Color(nsColor: .systemPurple)
        default: return .red
        }
    }
    
    private func setManualPriority(_ level: ManualPriorityLevel) {
        withAnimation(.spring(response: 0.3)) {
            manualPriorityLevel = level
        }
        
        if let value = level.value {
            sinistro.setValue(value, forKey: "prioritaManuale")
        } else {
            sinistro.setValue(nil, forKey: "prioritaManuale")
        }
        
        do {
            try viewContext.save()
            print("[PriorityBreakdown] ✅ Priorità manuale impostata: \(level.rawValue)")
        } catch {
            print("[PriorityBreakdown] ❌ Errore salvataggio: \(error)")
        }
    }
}
