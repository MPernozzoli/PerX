import SwiftUI
import CoreData
import Foundation
import Combine

struct StateCounterView: View {
    let sinistri: FetchedResults<Sinistro>
    @Binding var selectedStates: Set<String>
    @Binding var searchText: String
    @Binding var searchInFilteredOnly: Bool
    
    // MARK: - Nuovi filtri (compagnia, agenzia, polizza, recenti, ultimi, utente)
    @Binding var selectedCompanies: Set<String>
    @Binding var selectedAgenzie: Set<String>
    @Binding var selectedTipoPolizze: Set<String>
    @Binding var recentOnly: Bool
    @Binding var showUltimiOnly: Bool
    @Binding var filterAssigneeEnabled: Bool
    @Binding var selectedAssigneeEmail: String
    
    @State private var isRecentiExpanded = false  // Per espandere e mostrare "Ultimi"
    @State private var isUserExpanded = false
    @Binding var searchIsExpanded: Bool
    @State private var showingConfig = false
    @FocusState private var isSearchFocused: Bool
    @AppStorage("selectedStatesFilter") private var savedStatesData: Data = Data()
    @AppStorage("showFilterLabels") private var showFilterLabels: Bool = true
    
    // Visibilità filtri (configurabili dall'utente)
    @AppStorage("showUserFilter") private var showUserFilter: Bool = false  // Nascosto di default
    @AppStorage("showRecentFilter") private var showRecentFilter: Bool = true
    @AppStorage("showCompanyFilter") private var showCompanyFilter: Bool = true
    @AppStorage("showAgenziaFilter") private var showAgenziaFilter: Bool = true
    @AppStorage("showPolizzaFilter") private var showPolizzaFilter: Bool = true
    @AppStorage("recentFilterDefaultOn") private var recentFilterDefaultOn: Bool = true
    @AppStorage("visibleStates") private var visibleStatesData: Data = Data()
    @AppStorage("useGroupedView") private var useGroupedView: Bool = true
    /// Memorizza quali figli erano attivi per ogni gruppo (persiste la selezione interna)
    @AppStorage("groupChildrenSelection") private var groupChildrenData: Data = Data()
    
    // Persistenza nuovi filtri
    @AppStorage("selectedCompaniesFilter") private var savedCompaniesData: Data = Data()
    @AppStorage("selectedAgenzieFilter") private var savedAgenzieData: Data = Data()
    @AppStorage("selectedTipoPolizzeFilter") private var savedTipoPolizzeData: Data = Data()
    // Nota: recentOnly e showUltimiOnly sono gestiti via @AppStorage direttamente in SinistriView
    
    @StateObject private var statoManager = StatoManager.shared
    @StateObject private var userDirectory = CloudKitUserDirectoryService.shared
    @Environment(\.managedObjectContext) private var viewContext
    
    /// Mappa gruppo → set di stati figli attivi (per persistenza selezione interna)
    @State private var groupChildrenSelection: [String: Set<String>] = [:]
    @State private var countsCache: [String: Int] = [:]
    
    // UI state per filtri espandibili
    @State private var isCompagniaSectionExpanded = false
    @State private var expandedGruppi: Set<String> = []  // Gruppi espansi (per mostrare le compagnie figlie)
    @State private var isAgenziaExpanded = false
    @State private var isPolizzaExpanded = false
    @State private var agenziaSearchText = ""
    @State private var polizzaSearchText = ""
    @State private var userSearchText = ""
    
    // Filtro "Altri stati" (stati non mappati)
    @State private var isAltriStatiExpanded = false
    @State private var selectedAltriStati: Set<String> = []
    
    var visibleStates: [StatoManager.StatoSinistro] {
        let savedStatesSet: Set<String>
        if let data = try? JSONDecoder().decode([String].self, from: visibleStatesData) {
            savedStatesSet = Set(data)
        } else {
            savedStatesSet = Set(StatoManager.StatoSinistro.allCases.filter { $0.isVisible }.map { $0.id })
        }
        
        var allStates: [StatoManager.StatoSinistro] = []
        
        allStates += StatoManager.StatoSinistro.allCases.filter { 
            savedStatesSet.contains($0.id)
        }
        
        for customStato in statoManager.availableCustomStates {
            if savedStatesSet.contains(customStato.id),
               let stato = StatoManager.StatoSinistro(rawValue: customStato.id) {
                allStates.append(stato)
            }
        }
        
        return allStates
    }
    
    /// Gruppi visibili (basati sugli stati visibili)
    private var visibleGroups: [StateGroup] {
        var groups: [StateGroup] = []
        for group in StateGroup.allCases {
            if group.members.contains(where: { visibleStates.contains($0) }) {
                groups.append(group)
            }
        }
        return groups
    }
    
    /// Figli visibili di un gruppo
    private func visibleChildren(of group: StateGroup) -> [StatoManager.StatoSinistro] {
        group.members.filter { visibleStates.contains($0) }
    }
    
    /// Verifica se almeno un figlio del gruppo è selezionato (gruppo "attivo")
    private func isGroupActive(_ group: StateGroup) -> Bool {
        let children = visibleChildren(of: group)
        return children.contains { selectedStates.contains($0.descrizione) }
    }
    
    /// Verifica se TUTTI i figli visibili del gruppo sono selezionati
    private func isGroupFullySelected(_ group: StateGroup) -> Bool {
        let children = visibleChildren(of: group)
        guard !children.isEmpty else { return false }
        return children.allSatisfy { selectedStates.contains($0.descrizione) }
    }
    
    /// Figli attualmente selezionati di un gruppo
    private func selectedChildren(of group: StateGroup) -> Set<String> {
        let children = visibleChildren(of: group)
        return Set(children.filter { selectedStates.contains($0.descrizione) }.map { $0.descrizione })
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            mainScrollView
            toolbarButtons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            loadSavedStates()
            loadGroupChildrenSelection()
            loadSavedFilters()
        }
        .onChange(of: searchIsExpanded) { expanded in
            if expanded { isSearchFocused = true }
        }
    }
    
    // MARK: - Main Scroll View
    
    @ViewBuilder
    private var mainScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            filtersAndStatesContent
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            Task { @MainActor in
                refreshCountsSnapshot()
            }
        }
        .onChange(of: visibleStatesData) { _ in
            Task { @MainActor in
                refreshCountsSnapshot()
            }
        }
        .onChange(of: groupChildrenData) { _ in
            Task { @MainActor in
                refreshCountsSnapshot()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)) { _ in
            Task { @MainActor in
                refreshCountsSnapshot()
            }
        }
        .onChange(of: recentOnly) { _ in
            Task { @MainActor in
                refreshCountsSnapshot()
            }
        }
        .onChange(of: showUltimiOnly) { _ in
            Task { @MainActor in
                refreshCountsSnapshot()
            }
        }
        .onChange(of: selectedCompanies) { _ in
            Task { @MainActor in
                refreshCountsSnapshot()
            }
        }
        .onChange(of: selectedAgenzie) { _ in
            Task { @MainActor in
                refreshCountsSnapshot()
            }
        }
        .onChange(of: selectedTipoPolizze) { _ in
            Task { @MainActor in
                refreshCountsSnapshot()
            }
        }
        .onChange(of: filterAssigneeEnabled) { _ in
            Task { @MainActor in
                refreshCountsSnapshot()
            }
        }
        .onChange(of: selectedAssigneeEmail) { _ in
            Task { @MainActor in
                refreshCountsSnapshot()
            }
        }
    }
    
    @ViewBuilder
    private var filtersAndStatesContent: some View {
        HStack(spacing: 10) {
            filtersSection
            statesSection
            
            if !unmappedStates.isEmpty {
                altriStatiFilterChip
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 140)
        .padding(.vertical, 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: selectedStates)
    }
    
    @ViewBuilder
    private var filtersSection: some View {
        Group {
            if showUserFilter {
                userFilterChip
                Divider().frame(height: 24)
            }
            
            if showRecentFilter {
                recentFilterChip
                Divider().frame(height: 24)
            }
            
            if showCompanyFilter {
                companyFilterSection
                Divider().frame(height: 24)
            }
            
            if showAgenziaFilter {
                agenziaFilterChip
            }
            
            if showPolizzaFilter {
                polizzaFilterChip
            }
            
            if showAgenziaFilter || showPolizzaFilter {
                Divider().frame(height: 24)
            }
        }
    }
    
    @ViewBuilder
    private var statesSection: some View {
        Group {
            if useGroupedView {
                ForEach(visibleGroups, id: \.self) { group in
                    groupView(for: group)
                        .id("\(group.rawValue)-\(isGroupActive(group))")
                }
            } else {
                ForEach(visibleStates, id: \.self) { stato in
                    classicStateItem(stato)
                }
            }
        }
    }
    
    @ViewBuilder
    private var toolbarButtons: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    useGroupedView.toggle()
                }
            } label: {
                Image(systemName: useGroupedView ? "square.grid.2x2" : "list.bullet")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 28)
            .help(useGroupedView ? "Vista singoli stati" : "Vista raggruppata")
            
            SearchCounter(
                searchText: $searchText,
                searchInFilteredOnly: $searchInFilteredOnly,
                isExpanded: $searchIsExpanded,
                isFocused: _isSearchFocused
            )
            
            Button {
                showingConfig = true
            } label: {
                Image(systemName: "gear")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 32)
            .popover(isPresented: $showingConfig, attachmentAnchor: .point(.topTrailing)) {
                StatiConfigView()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Group View
    
    @ViewBuilder
    private func groupView(for group: StateGroup) -> some View {
        let isActive = isGroupActive(group)
        let children = visibleChildren(of: group)
        let hasVariants = children.count > 1
        
        // Se il gruppo ha un solo membro, mostralo come stato singolo (no gerarchia)
        if children.count == 1, let singleState = children.first {
            singleStateView(singleState)
        } else {
            // Gruppo con varianti
            HStack(spacing: 6) {
                // Elemento "madre" del gruppo
                GroupCounterItem(
                    group: group,
                    count: groupCount(for: group),
                    isActive: isActive,
                    isFullySelected: isGroupFullySelected(group),
                    showLabels: showFilterLabels
                )
                .scaleEffect(isActive ? 1.0 : 0.95)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isActive)
                .onTapGesture(count: 3) {
                    handleTripleClick(group)
                }
                .onTapGesture(count: 2) {
                    handleDoubleClickOnGroup(group)
                }
                .onTapGesture(count: 1) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.65, blendDuration: 0.1)) {
                        handleSingleClickOnGroup(group)
                    }
                }
                
                // Figli (mostrati solo se gruppo attivo E ha varianti)
                if isActive && hasVariants {
                    ForEach(Array(children.enumerated()), id: \.element) { index, stato in
                        StateCounterItem(
                            stato: stato,
                            count: counts[stato.descrizione] ?? 0,
                            isSelected: selectedStates.contains(stato.descrizione),
                            showFilterLabels: showFilterLabels,
                            isSubState: true,
                            onTap: {}
                        )
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity).combined(with: .offset(x: -20)),
                                removal: .scale(scale: 0.8).combined(with: .opacity)
                            )
                        )
                        .animation(
                            .spring(response: 0.35, dampingFraction: 0.65)
                                .delay(Double(index) * 0.05),
                            value: isActive
                        )
                        .onTapGesture(count: 2) {
                            handleDoubleClickOnChild(stato)
                        }
                        .onTapGesture(count: 1) {
                            handleSingleClickOnChild(stato, inGroup: group)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Single State View (per gruppi con un solo membro)
    
    @ViewBuilder
    private func singleStateView(_ stato: StatoManager.StatoSinistro) -> some View {
        StateCounterItem(
            stato: stato,
            count: counts[stato.descrizione] ?? 0,
            isSelected: selectedStates.contains(stato.descrizione),
            showFilterLabels: showFilterLabels,
            onTap: {}
        )
        .scaleEffect(selectedStates.contains(stato.descrizione) ? 1.0 : 0.97)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedStates.contains(stato.descrizione))
        .onTapGesture(count: 2) {
            selectedStates = [stato.descrizione]
            saveSelectedStates()
        }
        .onTapGesture(count: 1) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                toggleState(stato.descrizione)
            }
        }
    }
    
    // MARK: - Classic State Item (vista non raggruppata)
    
    @ViewBuilder
    private func classicStateItem(_ stato: StatoManager.StatoSinistro) -> some View {
        StateCounterItem(
            stato: stato,
            count: counts[stato.descrizione] ?? 0,
            isSelected: selectedStates.contains(stato.descrizione),
            showFilterLabels: showFilterLabels,
            onTap: {}
        )
        .onTapGesture(count: 2) {
            // Doppio click: solo questo stato
            selectedStates = [stato.descrizione]
            saveSelectedStates()
        }
        .onTapGesture(count: 1) {
            toggleState(stato.descrizione)
        }
    }
    
    // MARK: - Click Handlers
    
    /// Click singolo su gruppo: toggle attivazione (mostra/nasconde figli)
    private func handleSingleClickOnGroup(_ group: StateGroup) {
        let children = visibleChildren(of: group)
        let childDescriptions = Set(children.map { $0.descrizione })
        
        if isGroupActive(group) {
            // Gruppo attivo → disattiva (salva quali erano attivi prima)
            let currentlySelected = selectedChildren(of: group)
            groupChildrenSelection[group.rawValue] = currentlySelected
            saveGroupChildrenSelection()
            
            // Rimuovi tutti i figli dalla selezione
            selectedStates.subtract(childDescriptions)
        } else {
            // Gruppo inattivo → attiva (ripristina selezione precedente o tutti)
            let previousSelection = groupChildrenSelection[group.rawValue]
            
            if let previous = previousSelection, !previous.isEmpty {
                // Ripristina selezione precedente
                selectedStates.formUnion(previous)
            } else {
                // Nessuna selezione precedente → attiva tutti
                selectedStates.formUnion(childDescriptions)
            }
        }
        
        saveSelectedStates()
    }
    
    /// Doppio click su gruppo: esclude tutto il resto, mantiene solo questo gruppo
    private func handleDoubleClickOnGroup(_ group: StateGroup) {
        let children = visibleChildren(of: group)
        let childDescriptions = Set(children.map { $0.descrizione })
        
        // Mantieni solo i figli che erano già selezionati (o tutti se nessuno)
        let currentlySelected = selectedChildren(of: group)
        
        if currentlySelected.isEmpty {
            // Nessun figlio selezionato → seleziona tutti
            selectedStates = childDescriptions
        } else {
            // Mantieni solo quelli già selezionati
            selectedStates = currentlySelected
        }
        
        saveSelectedStates()
    }
    
    /// Triplo click su gruppo: attiva TUTTI i figli
    private func handleTripleClick(_ group: StateGroup) {
        let children = visibleChildren(of: group)
        let childDescriptions = Set(children.map { $0.descrizione })
        
        // Attiva tutti i figli del gruppo
        selectedStates.formUnion(childDescriptions)
        
        // Aggiorna anche la selezione salvata
        groupChildrenSelection[group.rawValue] = childDescriptions
        saveGroupChildrenSelection()
        
        saveSelectedStates()
    }
    
    /// Click singolo su figlio: toggle singolo stato
    private func handleSingleClickOnChild(_ stato: StatoManager.StatoSinistro, inGroup group: StateGroup) {
        toggleState(stato.descrizione)
        
        // Aggiorna la selezione salvata del gruppo
        let currentlySelected = selectedChildren(of: group)
        groupChildrenSelection[group.rawValue] = currentlySelected
        saveGroupChildrenSelection()
    }
    
    /// Doppio click su figlio: solo questo stato, esclude tutto il resto (anche fratelli)
    private func handleDoubleClickOnChild(_ stato: StatoManager.StatoSinistro) {
        selectedStates = [stato.descrizione]
        saveSelectedStates()
    }
    
    // MARK: - Conteggi
    
    private var counts: [String: Int] {
        countsCache
    }
    
    /// Sinistri pre-filtrati per i nuovi filtri (utente, recenti, ultimi, compagnia, agenzia, polizza)
    /// Usati per calcolare i conteggi degli stati
    private var sinistriPerConteggiStati: [Sinistro] {
        var filtered = Array(sinistri)
        
        // Filtro utente (assegnatario) - se disattivato: mostra tutti i sinistri dello studio
        if filterAssigneeEnabled {
            let targetEmail: String? = {
                let stored = selectedAssigneeEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !stored.isEmpty { return stored }
                let current = GoogleAuthService.shared.userEmail?.lowercased()
                if let current, !current.isEmpty { return current }
                return nil
            }()
            
            if let targetEmail {
                filtered = filtered.filter { sinistro in
                    let assigned = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail ?? "").lowercased()
                    return assigned == targetEmail
                }
            }
        }
        
        // Filtro recenti
        if recentOnly {
            filtered = filtered.filter { $0.isRecente }
        }
        
        // Filtro ultimi 24h
        if showUltimiOnly {
            let recentInteractions = SinistroInteractionTracker.shared.getRecentInteractions(hoursAgo: 24)
            filtered = filtered.filter { recentInteractions.contains($0.id) }
        }
        
        // Filtro compagnia
        if !selectedCompanies.isEmpty {
            filtered = filtered.filter { sinistro in
                let detected = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
                return selectedCompanies.contains(detected.rawValue)
            }
        }
        
        // Filtro agenzia
        if !selectedAgenzie.isEmpty {
            let agenzieNormalized = Set(selectedAgenzie.map { $0.lowercased() })
            filtered = filtered.filter { sinistro in
                guard let agenzia = sinistro.agenzia?.lowercased() else { return false }
                return agenzieNormalized.contains(agenzia)
            }
        }
        
        // Filtro polizza
        if !selectedTipoPolizze.isEmpty {
            let polizzeNormalized = Set(selectedTipoPolizze.map { $0.lowercased() })
            filtered = filtered.filter { sinistro in
                guard let tipoPolizza = sinistro.tipoPolizza?.lowercased() else { return false }
                return polizzeNormalized.contains(tipoPolizza)
            }
        }
        
        return filtered
    }
    
    @MainActor
    private func refreshCountsSnapshot() {
        // Usa i sinistri pre-filtrati per calcolare i conteggi
        let states = sinistriPerConteggiStati.map { $0.stato ?? "" }
        
        var allCounts = Dictionary(grouping: states, by: { $0 }).mapValues { $0.count }
        for stato in visibleStates {
            if allCounts[stato.descrizione] == nil {
                allCounts[stato.descrizione] = 0
            }
        }
        
        countsCache = allCounts
    }
    
    private func groupCount(for group: StateGroup) -> Int {
        let visibleMembers = group.members.filter { visibleStates.contains($0) }
        return visibleMembers.reduce(0) { $0 + (counts[$1.descrizione] ?? 0) }
    }
    
    // MARK: - State Management
    
    private func toggleState(_ state: String) {
        let isStateVisible = visibleStates.contains { $0.descrizione == state }
        guard isStateVisible else { return }
        
        if selectedStates.contains(state) {
            selectedStates.remove(state)
        } else {
            selectedStates.insert(state)
        }
        
        selectedStates = selectedStates.filter { state in
            visibleStates.contains { $0.descrizione == state }
        }
        
        saveSelectedStates()
    }
    
    private func saveSelectedStates() {
        if let encoded = try? JSONEncoder().encode(selectedStates) {
            savedStatesData = encoded
        }
    }
    
    private func loadSavedStates() {
        if let data = try? JSONDecoder().decode(Set<String>.self, from: savedStatesData) {
            selectedStates = Set(data.filter { state in
                visibleStates.contains { $0.descrizione == state }
            })
        }
        // Migrazione: leggi vecchia chiave se esiste
        if UserDefaults.standard.object(forKey: "showFilterLabels") == nil,
           UserDefaults.standard.object(forKey: "showFilterLabels") != nil {
            showFilterLabels = UserDefaults.standard.bool(forKey: "showFilterLabels")
        }
    }
    
    private func saveGroupChildrenSelection() {
        if let encoded = try? JSONEncoder().encode(groupChildrenSelection) {
            groupChildrenData = encoded
        }
    }
    
    private func loadGroupChildrenSelection() {
        if let decoded = try? JSONDecoder().decode([String: Set<String>].self, from: groupChildrenData) {
            groupChildrenSelection = decoded
        }
    }
    
    private func loadSavedFilters() {
        // Carica selezione compagnie
        if let data = try? JSONDecoder().decode(Set<String>.self, from: savedCompaniesData) {
            selectedCompanies = data
        }
        // Carica selezione agenzie
        if let data = try? JSONDecoder().decode(Set<String>.self, from: savedAgenzieData) {
            selectedAgenzie = data
        }
        // Carica selezione tipo polizze
        if let data = try? JSONDecoder().decode(Set<String>.self, from: savedTipoPolizzeData) {
            selectedTipoPolizze = data
        }
        // Nota: recentOnly e showUltimiOnly sono ora gestiti direttamente da @AppStorage in SinistriView
        // Se il filtro è nascosto, forza il valore di default configurato
        if !showRecentFilter {
            recentOnly = recentFilterDefaultOn
            showUltimiOnly = false
        }
    }
    
    // MARK: - Filtro Utente
    
    /// Email effettiva selezionata per il filtro assegnatario
    private var effectiveAssigneeEmail: String? {
        let stored = selectedAssigneeEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !stored.isEmpty { return stored }
        let current = GoogleAuthService.shared.userEmail?.lowercased()
        if let current, !current.isEmpty { return current }
        return nil
    }
    
    private var assigneeDisplayName: String {
        guard let email = effectiveAssigneeEmail else { return "Utente" }
        if let u = userDirectory.user(email: email) { return u.displayName }
        return email.components(separatedBy: "@").first?.replacingOccurrences(of: ".", with: " ").capitalized ?? email
    }
    
    private var assigneeSuggestions: [String] {
        // Preferisci la directory pubblica CK; fallback minimo se vuota
        let users = userDirectory.users
        if users.isEmpty {
            if let email = GoogleAuthService.shared.userEmail?.lowercased(), !email.isEmpty {
                return ["\(assigneeDisplayName) <\(email)>"]
            }
            return []
        }
        return users
            .sorted { $0.displayName < $1.displayName }
            .map { "\($0.displayName) <\($0.email)>" }
    }
    
    private func applySelectedAssignee(from suggestion: String) {
        // Estrae l'email tra <...>
        if let start = suggestion.firstIndex(of: "<"),
           let end = suggestion.firstIndex(of: ">"),
           start < end {
            let email = String(suggestion[suggestion.index(after: start)..<end]).lowercased()
            if !email.isEmpty {
                selectedAssigneeEmail = email
                filterAssigneeEnabled = true
            }
        }
    }
    
    @ViewBuilder
    private var userFilterChip: some View {
        HStack(spacing: 6) {
            FilterChipView(
                label: assigneeDisplayName,
                icon: "person.fill",
                count: filterAssigneeEnabled ? sinistriPerConteggiStati.count : nil,
                isActive: filterAssigneeEnabled || isUserExpanded,
                color: Color.green,
                showLabel: showFilterLabels
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    filterAssigneeEnabled.toggle()
                    if filterAssigneeEnabled, (selectedAssigneeEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        if let email = GoogleAuthService.shared.userEmail?.lowercased(), !email.isEmpty {
                            selectedAssigneeEmail = email
                        }
                    }
                }
            }
            .onLongPressGesture(minimumDuration: 0.3) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isUserExpanded.toggle()
                }
            }
            .help(filterAssigneeEnabled ? "Clic: mostra tutti | Pressione lunga: scegli utente" : "Clic: filtra per assegnatario | Pressione lunga: scegli utente")
            
            if isUserExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    AutocompleteTextField(
                        text: $userSearchText,
                        placeholder: "Cerca utente…",
                        suggestions: assigneeSuggestions
                    ) { selected in
                        applySelectedAssignee(from: selected)
                        userSearchText = ""
                        isUserExpanded = false
                    }
                    .frame(width: 220)
                    
                    if let email = effectiveAssigneeEmail {
                        SelectedPillView(text: assigneeDisplayName) {
                            selectedAssigneeEmail = ""
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                )
            }
        }
    }
    
    // MARK: - Filtro Recenti (con figlio "Ultimi")
    
    /// Sinistri con cui l'utente ha interagito nelle ultime 24 ore
    private var ultimiSinistri: [Sinistro] {
        let recentInteractions = SinistroInteractionTracker.shared.getRecentInteractions(hoursAgo: 24)
        return sinistri.filter { sinistro in
            recentInteractions.contains(sinistro.id)
        }
    }
    
    @ViewBuilder
    private var recentFilterChip: some View {
        let recentCount = sinistri.filter { $0.isRecente }.count
        let ultimiCount = ultimiSinistri.count
        
        HStack(spacing: 4) {
            // Chip principale "Recenti"
            FilterChipView(
                label: "Recenti",
                icon: "calendar.badge.clock",
                count: recentCount,
                isActive: recentOnly || isRecentiExpanded,
                color: Color.blue,
                showLabel: showFilterLabels
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if isRecentiExpanded {
                        // Se espanso, toggle recenti (il valore viene salvato automaticamente via @AppStorage in SinistriView)
                        recentOnly.toggle()
                    } else {
                        // Se non espanso, espandi
                        isRecentiExpanded = true
                    }
                }
            }
            .onLongPressGesture(minimumDuration: 0.3) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isRecentiExpanded.toggle()
                }
            }
            .help("Clic: attiva/disattiva | Pressione lunga: espandi")
            
            // Chip figlio "Ultimi" (solo se espanso)
            if isRecentiExpanded {
                FilterChipView(
                    label: "Ultimi 24h",
                    icon: "clock.arrow.circlepath",
                    count: ultimiCount,
                    isActive: showUltimiOnly,
                    color: Color.cyan,
                    isSubItem: true,
                    showLabel: showFilterLabels
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        // Il valore viene salvato automaticamente via @AppStorage in SinistriView
                        showUltimiOnly.toggle()
                    }
                }
                .help("Mostra solo sinistri con cui hai interagito nelle ultime 24 ore")
            }
        }
    }
    
    // MARK: - Filtro Compagnia (gerarchia dinamica, sensibile a recenti)
    
    /// Sinistri base per i conteggi (filtrati per recenti se attivo)
    private var baseSinistriForCompanyFilter: [Sinistro] {
        if recentOnly {
            return sinistri.filter { $0.isRecente }
        }
        return Array(sinistri)
    }
    
    /// Verifica se c'è almeno una compagnia selezionata
    private var hasAnyCompanySelected: Bool {
        !selectedCompanies.isEmpty
    }
    
    /// Conteggio totale sinistri per tutte le compagnie mappate
    private var totalCompaniesCount: Int {
        baseSinistriForCompanyFilter.filter { sinistro in
            let detected = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
            return detected != .unknown
        }.count
    }
    
    /// Compagnie con almeno un sinistro (sensibile a recenti)
    private var activeCompanies: Set<Compagnia> {
        var companies = Set<Compagnia>()
        for sinistro in baseSinistriForCompanyFilter {
            let detected = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
            if detected != .unknown {
                companies.insert(detected)
            }
        }
        return companies
    }
    
    /// Gruppi con almeno una compagnia attiva
    private var activeGruppi: [GruppoAssicurativo] {
        GruppoAssicurativo.allCases.filter { gruppo in
            gruppo != .unknown && gruppo.compagnie.contains { activeCompanies.contains($0) }
        }
    }
    
    /// Compagnie attive per un gruppo
    private func activeCompaniesForGroup(_ gruppo: GruppoAssicurativo) -> [Compagnia] {
        gruppo.compagnie.filter { activeCompanies.contains($0) }
    }
    
    @ViewBuilder
    private var companyFilterSection: some View {
        // Mostra solo se ci sono compagnie con sinistri
        if !activeCompanies.isEmpty {
            HStack(spacing: 6) {
                // Chip "nonna" - Compagnia (apre/chiude tutta la sezione)
                FilterChipView(
                    label: "Compagnia",
                    icon: "building.columns",
                    count: totalCompaniesCount,
                    isActive: isCompagniaSectionExpanded || hasAnyCompanySelected,
                    color: .indigo,
                    showLabel: showFilterLabels
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isCompagniaSectionExpanded.toggle()
                        if !isCompagniaSectionExpanded {
                            // Chiudi anche i gruppi espansi
                            expandedGruppi.removeAll()
                        }
                    }
                }
                .onTapGesture(count: 2) {
                    // Doppio click: deseleziona tutte le compagnie
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedCompanies.removeAll()
                        saveCompaniesSelection()
                    }
                }
                
                // Figli (gruppi/compagnie) - mostrati solo se sezione espansa
                if isCompagniaSectionExpanded {
                    ForEach(activeGruppi, id: \.self) { gruppo in
                        companyGroupView(for: gruppo)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func companyGroupView(for gruppo: GruppoAssicurativo) -> some View {
        let compagnieAttive = activeCompaniesForGroup(gruppo)
        let isGruppoActive = compagnieAttive.contains { selectedCompanies.contains($0.rawValue) }
        let isGruppoExpanded = expandedGruppi.contains(gruppo.rawValue)
        let groupCount = countSinistriForGroup(gruppo)
        let groupColor = CompagniaSettingsService.shared.effectiveUiColor(gruppo)
        
        // Se il gruppo ha una sola compagnia attiva, mostra direttamente la compagnia (senza gerarchia)
        if compagnieAttive.count == 1, let singleCompany = compagnieAttive.first {
            let compColor = CompagniaSettingsService.shared.effectiveUiColor(singleCompany)
            let isCompSelected = selectedCompanies.contains(singleCompany.rawValue)
            
            FilterChipView(
                label: CompagniaSettingsService.shared.effectiveShortLabel(singleCompany),
                icon: singleCompany.uiIconSystemName,
                count: groupCount,
                isActive: isCompSelected,
                color: compColor,
                isSubItem: true,
                showLabel: showFilterLabels
            )
            .transition(.asymmetric(
                insertion: .scale(scale: 0.5).combined(with: .opacity),
                removal: .scale(scale: 0.8).combined(with: .opacity)
            ))
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    toggleCompany(singleCompany)
                }
            }
        } else if compagnieAttive.count > 1 {
            // Gruppo con più compagnie attive: mostra gerarchia
            HStack(spacing: 6) {
                // Chip gruppo (figlio della nonna)
                FilterChipView(
                    label: CompagniaSettingsService.shared.effectiveShortLabel(gruppo),
                    icon: gruppo.uiIconSystemName,
                    count: groupCount,
                    isActive: isGruppoActive || isGruppoExpanded,
                    color: groupColor,
                    isSubItem: true,
                    showLabel: showFilterLabels
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5).combined(with: .opacity),
                    removal: .scale(scale: 0.8).combined(with: .opacity)
                ))
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if expandedGruppi.contains(gruppo.rawValue) {
                            expandedGruppi.remove(gruppo.rawValue)
                        } else {
                            expandedGruppi.insert(gruppo.rawValue)
                        }
                    }
                }
                .onTapGesture(count: 2) {
                    // Doppio click: seleziona/deseleziona tutte le compagnie del gruppo
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        toggleCompanyGroup(gruppo)
                    }
                }
                
                // Compagnie figlie (nipoti) - mostrate solo se gruppo espanso
                if isGruppoExpanded {
                    ForEach(compagnieAttive, id: \.self) { compagnia in
                        let compColor = CompagniaSettingsService.shared.effectiveUiColor(compagnia)
                        let compCount = countSinistriForCompany(compagnia)
                        let isCompSelected = selectedCompanies.contains(compagnia.rawValue)
                        
                        FilterChipView(
                            label: CompagniaSettingsService.shared.effectiveShortLabel(compagnia),
                            icon: compagnia.uiIconSystemName,
                            count: compCount,
                            isActive: isCompSelected,
                            color: compColor,
                            isSubItem: true,
                            isGrandChild: true,
                            showLabel: showFilterLabels
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                toggleCompany(compagnia)
                            }
                        }
                    }
                }
            }
        }
        // Se compagnieAttive.count == 0, non mostriamo nulla
    }
    
    private func countSinistriForGroup(_ gruppo: GruppoAssicurativo) -> Int {
        baseSinistriForCompanyFilter.filter { sinistro in
            let detected = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
            return gruppo.compagnie.contains(detected)
        }.count
    }
    
    private func countSinistriForCompany(_ compagnia: Compagnia) -> Int {
        baseSinistriForCompanyFilter.filter { sinistro in
            let detected = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
            return detected == compagnia
        }.count
    }
    
    private func toggleCompanyGroup(_ gruppo: GruppoAssicurativo) {
        let compagnieRawValues = Set(gruppo.compagnie.map { $0.rawValue })
        let allSelected = compagnieRawValues.allSatisfy { selectedCompanies.contains($0) }
        
        if allSelected {
            // Deseleziona tutte
            selectedCompanies.subtract(compagnieRawValues)
        } else {
            // Seleziona tutte
            selectedCompanies.formUnion(compagnieRawValues)
        }
        saveCompaniesSelection()
    }
    
    private func toggleCompany(_ compagnia: Compagnia) {
        if selectedCompanies.contains(compagnia.rawValue) {
            selectedCompanies.remove(compagnia.rawValue)
        } else {
            selectedCompanies.insert(compagnia.rawValue)
        }
        saveCompaniesSelection()
    }
    
    private func saveCompaniesSelection() {
        if let encoded = try? JSONEncoder().encode(selectedCompanies) {
            savedCompaniesData = encoded
        }
    }
    
    // MARK: - Filtro Agenzia
    
    @ViewBuilder
    private var agenziaFilterChip: some View {
        let count = selectedAgenzie.count
        
        FilterChipView(
            label: "Agenzia",
            icon: "building.2",
            count: count > 0 ? count : nil,
            isActive: isAgenziaExpanded || count > 0,
            color: .orange,
            showBadge: count > 0,
            showLabel: showFilterLabels
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isAgenziaExpanded.toggle()
                if !isAgenziaExpanded {
                    agenziaSearchText = ""
                }
            }
        }
        
        if isAgenziaExpanded {
            agenziaExpandedView
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity),
                    removal: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity)
                ))
        }
    }
    
    @ViewBuilder
    private var agenziaExpandedView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Pills delle agenzie selezionate
            if !selectedAgenzie.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(selectedAgenzie).sorted(), id: \.self) { agenzia in
                        SelectedPillView(text: agenzia) {
                            selectedAgenzie.remove(agenzia)
                            saveAgenzieSelection()
                        }
                    }
                }
            }
            
            // Campo di ricerca con autocomplete
            AutocompleteTextField(
                text: $agenziaSearchText,
                placeholder: "Cerca agenzia...",
                suggestions: availableAgenzie,
                onSelect: { agenzia in
                    selectedAgenzie.insert(agenzia)
                    agenziaSearchText = ""
                    saveAgenzieSelection()
                }
            )
            .frame(width: 180)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 4)
        )
    }
    
    /// Agenzie disponibili (filtrate per recenti e compagnia)
    private var availableAgenzie: [String] {
        // TODO: Migrare a rubricazione agenzie quando sarà pronta
        var baseSinistri = baseSinistriForCompanyFilter  // Già filtrato per recenti
        
        // Filtra ulteriormente per compagnia se selezionata
        if !selectedCompanies.isEmpty {
            baseSinistri = baseSinistri.filter { sinistro in
                let detected = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
                return selectedCompanies.contains(detected.rawValue)
            }
        }
        
        let agenzie = Set(baseSinistri.compactMap { $0.agenzia }.filter { !$0.isEmpty })
        return agenzie.sorted()
    }
    
    private func saveAgenzieSelection() {
        if let encoded = try? JSONEncoder().encode(selectedAgenzie) {
            savedAgenzieData = encoded
        }
    }
    
    // MARK: - Filtro Polizza
    
    @ViewBuilder
    private var polizzaFilterChip: some View {
        let count = selectedTipoPolizze.count
        
        FilterChipView(
            label: "Polizza",
            icon: "doc.text",
            count: count > 0 ? count : nil,
            isActive: isPolizzaExpanded || count > 0,
            color: .purple,
            showBadge: count > 0,
            showLabel: showFilterLabels
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPolizzaExpanded.toggle()
                if !isPolizzaExpanded {
                    polizzaSearchText = ""
                }
            }
        }
        
        if isPolizzaExpanded {
            polizzaExpandedView
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity),
                    removal: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity)
                ))
        }
    }
    
    @ViewBuilder
    private var polizzaExpandedView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Pills dei tipi polizza selezionati
            if !selectedTipoPolizze.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(selectedTipoPolizze).sorted(), id: \.self) { tipo in
                        SelectedPillView(text: tipo) {
                            selectedTipoPolizze.remove(tipo)
                            saveTipoPolizzeSelection()
                        }
                    }
                }
            }
            
            // Campo di ricerca con autocomplete
            AutocompleteTextField(
                text: $polizzaSearchText,
                placeholder: "Cerca tipo polizza...",
                suggestions: availableTipoPolizze,
                onSelect: { tipo in
                    selectedTipoPolizze.insert(tipo)
                    polizzaSearchText = ""
                    saveTipoPolizzeSelection()
                }
            )
            .frame(width: 180)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 4)
        )
    }
    
    /// Tipi polizza disponibili (filtrati per recenti e compagnia)
    private var availableTipoPolizze: [String] {
        // TODO: Migrare a sistema polizze indicizzate quando sarà pronto
        var baseSinistri = baseSinistriForCompanyFilter  // Già filtrato per recenti
        
        // Filtra ulteriormente per compagnia se selezionata
        if !selectedCompanies.isEmpty {
            baseSinistri = baseSinistri.filter { sinistro in
                let detected = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
                return selectedCompanies.contains(detected.rawValue)
            }
        }
        
        let tipi = Set(baseSinistri.compactMap { $0.tipoPolizza }.filter { !$0.isEmpty })
        return tipi.sorted()
    }
    
    private func saveTipoPolizzeSelection() {
        if let encoded = try? JSONEncoder().encode(selectedTipoPolizze) {
            savedTipoPolizzeData = encoded
        }
    }
    
    // MARK: - Altri Stati (stati non mappati)
    
    /// Stati presenti nei sinistri (pre-filtrati) ma non mappati in StatoManager
    private var unmappedStates: [String] {
        let mappedDescriptions = Set(StatoManager.StatoSinistro.allCases.map { $0.descrizione })
        let allStatesInSinistri = Set(sinistriPerConteggiStati.compactMap { $0.stato }.filter { !$0.isEmpty })
        
        return allStatesInSinistri
            .filter { !mappedDescriptions.contains($0) }
            .sorted()
    }
    
    /// Conteggio sinistri per ogni stato non mappato (usa sinistri pre-filtrati)
    private func countForUnmappedState(_ stato: String) -> Int {
        sinistriPerConteggiStati.filter { $0.stato == stato }.count
    }
    
    /// Conteggio totale sinistri con stati non mappati (usa sinistri pre-filtrati)
    private var totalUnmappedCount: Int {
        sinistriPerConteggiStati.filter { sinistro in
            guard let stato = sinistro.stato, !stato.isEmpty else { return false }
            let mappedDescriptions = Set(StatoManager.StatoSinistro.allCases.map { $0.descrizione })
            return !mappedDescriptions.contains(stato)
        }.count
    }
    
    @ViewBuilder
    private var altriStatiFilterChip: some View {
        let hasSelection = !selectedAltriStati.isEmpty
        
        HStack(spacing: 6) {
            FilterChipView(
                label: "Altri stati",
                icon: "questionmark.circle",
                count: totalUnmappedCount,
                isActive: isAltriStatiExpanded || hasSelection,
                color: .gray,
                showLabel: showFilterLabels
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isAltriStatiExpanded.toggle()
                }
            }
            .onTapGesture(count: 2) {
                // Doppio click: seleziona/deseleziona tutti gli altri stati
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if selectedAltriStati.isEmpty {
                        selectedAltriStati = Set(unmappedStates)
                    } else {
                        selectedAltriStati.removeAll()
                    }
                    // Sincronizza con selectedStates
                    syncAltriStatiWithSelectedStates()
                }
            }
            
            // Figli: stati non mappati (mostrati solo se espanso)
            if isAltriStatiExpanded {
                ForEach(unmappedStates, id: \.self) { stato in
                    let isSelected = selectedAltriStati.contains(stato)
                    let count = countForUnmappedState(stato)
                    
                    FilterChipView(
                        label: stato,
                        icon: "circle",
                        count: count,
                        isActive: isSelected,
                        color: .gray,
                        isSubItem: true,
                        showLabel: showFilterLabels
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if selectedAltriStati.contains(stato) {
                                selectedAltriStati.remove(stato)
                            } else {
                                selectedAltriStati.insert(stato)
                            }
                            syncAltriStatiWithSelectedStates()
                        }
                    }
                }
            }
        }
    }
    
    /// Sincronizza gli "altri stati" selezionati con selectedStates per il filtro
    private func syncAltriStatiWithSelectedStates() {
        // Rimuovi prima tutti gli stati non mappati da selectedStates
        let mappedDescriptions = Set(StatoManager.StatoSinistro.allCases.map { $0.descrizione })
        selectedStates = selectedStates.filter { mappedDescriptions.contains($0) }
        
        // Aggiungi gli altri stati selezionati
        selectedStates.formUnion(selectedAltriStati)
        
        saveSelectedStates()
    }
}

// MARK: - Filter Chip View

struct FilterChipView: View {
    let label: String
    let icon: String
    var count: Int? = nil
    let isActive: Bool
    let color: Color
    var isSubItem: Bool = false
    var isGrandChild: Bool = false  // Livello nipote (3° livello)
    var showBadge: Bool = false
    var showLabel: Bool = true  // Mostra/nasconde l'etichetta testuale
    
    @State private var isHovering = false
    
    /// Determina il livello di nidificazione
    private var nestingLevel: Int {
        if isGrandChild { return 2 }
        if isSubItem { return 1 }
        return 0
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Barra laterale per figli e nipoti
            if isSubItem || isGrandChild {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(isActive ? 0.6 : 0.3))
                    .frame(width: isGrandChild ? 1.5 : 2, height: isGrandChild ? 12 : 14)
            }
            
            Image(systemName: icon)
                .font(isGrandChild ? .system(size: 10) : (isSubItem ? .caption : .body))
                .foregroundColor(isActive ? color : color.opacity(0.7))
            
            if showLabel {
                Text(label)
                    .font(isGrandChild ? .system(size: 10) : (isSubItem ? .caption2 : .caption))
                    .lineLimit(1)
                    .foregroundColor(isActive ? .primary : .secondary)
            }
            
            if let count = count {
                Text("\(count)")
                    .font(isGrandChild ? .system(size: 10, weight: .bold) : (isSubItem ? .caption2.bold() : .caption.bold()))
                    .foregroundColor(isActive ? .primary : .secondary)
            }
            
            if showBadge {
                Circle()
                    .fill(color)
                    .frame(width: isGrandChild ? 5 : 6, height: isGrandChild ? 5 : 6)
            }
        }
        .padding(.horizontal, isGrandChild ? 6 : (isSubItem ? 8 : 10))
        .padding(.vertical, isGrandChild ? 4 : (isSubItem ? 5 : 6))
        .background(
            RoundedRectangle(cornerRadius: isGrandChild ? 5 : (isSubItem ? 6 : 8))
                .fill(isActive ? color.opacity(isGrandChild ? 0.2 : 0.15) : (isHovering ? color.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(isGrandChild ? 0.8 : 1)))
                .overlay(
                    RoundedRectangle(cornerRadius: isGrandChild ? 5 : (isSubItem ? 6 : 8))
                        .strokeBorder(isActive ? color : .clear, lineWidth: isGrandChild ? 0.8 : (isSubItem ? 1 : 1.5))
                )
        )
        .scaleEffect(isActive ? 1.0 : (isHovering ? 0.98 : (isGrandChild ? 0.94 : 0.96)))
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isActive)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: isGrandChild ? 5 : (isSubItem ? 6 : 8)))
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Selected Pill View

struct SelectedPillView: View {
    let text: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption2)
                .lineLimit(1)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.15))
        )
    }
}

// MARK: - Fuzzy Search Helper

/// Calcola un punteggio di matching fuzzy tra query e target
/// Più alto = migliore corrispondenza
private func fuzzyScore(query: String, target: String) -> Int {
    let queryLower = query.lowercased()
    let targetLower = target.lowercased()
    
    // Match esatto iniziale = punteggio massimo
    if targetLower.hasPrefix(queryLower) {
        return 1000 + (100 - target.count)  // Preferisci stringhe più corte
    }
    
    // Match parola intera
    if targetLower.contains(" \(queryLower)") {
        return 800 + (100 - target.count)
    }
    
    // Contiene la query
    if targetLower.contains(queryLower) {
        return 600 + (100 - target.count)
    }
    
    // Fuzzy: verifica se tutti i caratteri della query appaiono in ordine nel target
    var queryIndex = queryLower.startIndex
    var score = 0
    var consecutiveBonus = 0
    
    for char in targetLower {
        if queryIndex < queryLower.endIndex && char == queryLower[queryIndex] {
            score += 10 + consecutiveBonus
            consecutiveBonus += 5  // Bonus per caratteri consecutivi
            queryIndex = queryLower.index(after: queryIndex)
        } else {
            consecutiveBonus = 0
        }
    }
    
    // Tutti i caratteri della query sono stati trovati?
    if queryIndex == queryLower.endIndex {
        return score
    }
    
    return 0  // Nessun match
}

// MARK: - Autocomplete TextField

struct AutocompleteTextField: View {
    @Binding var text: String
    let placeholder: String
    let suggestions: [String]
    let onSelect: (String) -> Void
    
    @State private var showSuggestions = false
    @FocusState private var isFocused: Bool
    
    private var filteredSuggestions: [String] {
        if text.isEmpty {
            return Array(suggestions.prefix(8))
        }
        
        // Fuzzy search: calcola punteggio per ogni suggerimento e ordina
        let scored = suggestions.compactMap { suggestion -> (String, Int)? in
            let score = fuzzyScore(query: text, target: suggestion)
            return score > 0 ? (suggestion, score) : nil
        }
        
        return scored
            .sorted { $0.1 > $1.1 }  // Ordina per punteggio decrescente
            .prefix(8)
            .map { $0.0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .focused($isFocused)
                    .onChange(of: isFocused) { focused in
                        showSuggestions = focused
                    }
                
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            
            if showSuggestions && !filteredSuggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredSuggestions, id: \.self) { suggestion in
                            Button {
                                onSelect(suggestion)
                                showSuggestions = false
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 11))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .background(Color.clear)
                            .contentShape(Rectangle())
                            
                            if suggestion != filteredSuggestions.last {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: .black.opacity(0.1), radius: 4)
                )
            }
        }
    }
}

// MARK: - Group Counter Item

struct GroupCounterItem: View {
    let group: StateGroup
    let count: Int
    let isActive: Bool
    let isFullySelected: Bool
    let showLabels: Bool
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 6) {
            // Barra laterale solo per le "madri" (gruppi)
            RoundedRectangle(cornerRadius: 1)
                .fill(group.color.opacity(isActive ? 0.6 : (isHovering ? 0.5 : 0.3)))
                .frame(width: 2, height: 16)
            
            Image(systemName: group.icon)
                .foregroundColor(iconColor)
                .font(.body)
            
            if showLabels {
                Text(group.shortLabel)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(textColor)
            }
            
            Text("\(count)")
                .font(.system(.body, design: .rounded).bold())
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 44, minHeight: 32)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )
        )
        .scaleEffect(scaleValue)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    // MARK: - Computed Colors
    
    private var backgroundColor: Color {
        if isFullySelected {
            return group.color.opacity(0.15)
        } else if isActive {
            return group.color.opacity(0.12)
        } else if isHovering {
            return group.color.opacity(0.075)
        }
        return Color(NSColor.controlBackgroundColor)
    }
    
    private var borderColor: Color {
        if isActive && !isFullySelected {
            return group.color.opacity(0.5)
        } else if isHovering && !isActive {
            return group.color.opacity(0.3)
        }
        return .clear
    }
    
    private var borderWidth: CGFloat {
        if isActive && !isFullySelected {
            return 1.5
        } else if isHovering && !isActive {
            return 1
        }
        return 0
    }
    
    private var iconColor: Color {
        if isActive {
            return group.color
        } else if isHovering {
            return group.color.opacity(0.7)
        }
        return group.color.opacity(0.7)
    }
    
    private var textColor: Color {
        if isActive {
            return .primary
        } else if isHovering {
            return .primary.opacity(0.7)
        }
        return .secondary
    }
    
    private var scaleValue: CGFloat {
        if isActive {
            return 1.0
        } else if isHovering {
            return 0.98
        }
        return 0.96
    }
}

// MARK: - Sinistro Interaction Tracker

/// Traccia le interazioni dell'utente con i sinistri (apertura, modifica, visualizzazione)
/// Usa UserDefaults per persistere i timestamp delle ultime interazioni
/// Usa il riferimento (String) come identificatore univoco
class SinistroInteractionTracker: ObservableObject {
    static let shared = SinistroInteractionTracker()
    
    private let storageKey = "sinistroInteractions"
    private let maxStoredInteractions = 500  // Limita per evitare crescita illimitata
    
    @Published private(set) var interactions: [String: Date] = [:]
    
    private init() {
        loadInteractions()
    }
    
    /// Registra un'interazione con un sinistro (usa il riferimento come ID)
    func recordInteraction(sinistroId: String) {
        guard !sinistroId.isEmpty else { return }
        interactions[sinistroId] = Date()
        cleanupOldInteractions()
        saveInteractions()
    }
    
    /// Restituisce gli ID (riferimenti) dei sinistri con cui si è interagito nelle ultime N ore
    func getRecentInteractions(hoursAgo: Int) -> Set<String> {
        let cutoff = Date().addingTimeInterval(-Double(hoursAgo) * 3600)
        return Set(interactions.filter { $0.value > cutoff }.keys)
    }
    
    /// Verifica se un sinistro è stato visitato nelle ultime N ore
    func wasRecentlyAccessed(sinistroId: String, hoursAgo: Int = 24) -> Bool {
        guard let lastAccess = interactions[sinistroId] else { return false }
        let cutoff = Date().addingTimeInterval(-Double(hoursAgo) * 3600)
        return lastAccess > cutoff
    }
    
    // MARK: - Private
    
    private func loadInteractions() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return
        }
        interactions = decoded
    }
    
    private func saveInteractions() {
        if let data = try? JSONEncoder().encode(interactions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func cleanupOldInteractions() {
        // Rimuovi interazioni più vecchie di 7 giorni
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        interactions = interactions.filter { $0.value > weekAgo }
        
        // Se ancora troppi, mantieni solo i più recenti
        if interactions.count > maxStoredInteractions {
            let sorted = interactions.sorted { $0.value > $1.value }
            interactions = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(maxStoredInteractions)).map { ($0.key, $0.value) })
        }
    }
}
