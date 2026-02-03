//
//  SinistriListView.swift
//  PerX per iPad
//
//  Lista sinistri con StateCounterView identica al Mac
//

import SwiftUI

struct SinistriListView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var navigationPath = NavigationPath()
    
    // MARK: - Filter State (come StateCounterView Mac)
    @State private var selectedStates: Set<String> = []
    @State private var selectedCompanies: Set<String> = []
    @State private var selectedAgenzie: Set<String> = []
    @State private var selectedTipoPolizze: Set<String> = []
    @State private var searchText = ""
    
    // Persistenza filtri
    @AppStorage("iPad_selectedStatesFilter") private var savedStatesData: Data = Data()
    @AppStorage("iPad_selectedCompaniesFilter") private var savedCompaniesData: Data = Data()
    @AppStorage("iPad_selectedAgenzieFilter") private var savedAgenzieData: Data = Data()
    @AppStorage("iPad_selectedTipoPolizzeFilter") private var savedTipoPolizzeData: Data = Data()
    @AppStorage("iPad_recentOnly") private var recentOnly: Bool = true
    @AppStorage("iPad_showUltimiOnly") private var showUltimiOnly: Bool = false
    @AppStorage("iPad_useGroupedView") private var useGroupedView: Bool = true
    @AppStorage("iPad_showFilterLabels") private var showFilterLabels: Bool = true
    @AppStorage("iPad_groupChildrenSelection") private var groupChildrenData: Data = Data()
    
    // UI State
    @State private var isRecentiExpanded = false
    @State private var isCompagniaSectionExpanded = false
    @State private var expandedGruppi: Set<String> = []
    @State private var isAgenziaExpanded = false
    @State private var isPolizzaExpanded = false
    @State private var agenziaSearchText = ""
    @State private var polizzaSearchText = ""
    @State private var groupChildrenSelection: [String: Set<String>] = [:]
    @State private var countsCache: [String: Int] = [:]
    
    // Sinistri ultimi 24h
    @State private var recentInteractions: Set<String> = []
    
    private var syncService: iPadCloudKitSyncService? {
        session.cloudKitSyncService
    }
    
    private var allSinistri: [SinistroMinimal] {
        syncService?.sinistri ?? []
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                stateCounterBar
                Divider()
                listContent
            }
            .navigationDestination(for: SinistroMinimal.self) { sinistro in
                iPadSinistroDetailView(sinistro: sinistro)
            }
            .searchable(text: $searchText, prompt: "Cerca sinistro...")
            .navigationTitle("Sinistri (\(filteredSinistri.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // Toggle vista raggruppata
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                useGroupedView.toggle()
                            }
                        } label: {
                            Image(systemName: useGroupedView ? "square.grid.2x2" : "list.bullet")
                                .foregroundColor(.secondary)
                        }
                        
                        // Refresh
                        Button {
                            Task { await syncService?.syncNow() }
                        } label: {
                            if syncService?.isSyncing == true {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                }
            }
            .refreshable {
                await syncService?.syncNow()
            }
            .onAppear {
                loadSavedFilters()
                refreshCountsSnapshot()
            }
            .onChange(of: allSinistri.count) { _ in
                refreshCountsSnapshot()
            }
        }
    }
    
    // MARK: - State Counter Bar (identica al Mac)
    
    @ViewBuilder
    private var stateCounterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Filtro Recenti
                recentFilterChip
                
                verticalDivider
                
                // Filtro Compagnia
                companyFilterSection
                
                // Filtro Agenzia
                agenziaFilterChip
                
                // Filtro Polizza
                polizzaFilterChip
                
                verticalDivider
                
                // Stati
                statesSection
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: selectedStates)
        }
        .background(Color(.secondarySystemBackground).opacity(0.8))
    }
    
    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 1, height: 20)
    }
    
    // MARK: - Filtro Recenti (con figlio Ultimi 24h)
    
    @ViewBuilder
    private var recentFilterChip: some View {
        let recentCount = allSinistri.filter { isRecente($0) }.count
        let ultimiCount = recentInteractions.count
        
        HStack(spacing: 4) {
            FilterChipView(
                label: "Recenti",
                icon: "calendar.badge.clock",
                count: recentCount,
                isActive: recentOnly || isRecentiExpanded,
                color: .blue,
                showLabel: showFilterLabels
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if isRecentiExpanded {
                        recentOnly.toggle()
                        refreshCountsSnapshot()
                    } else {
                        isRecentiExpanded = true
                    }
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3).onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isRecentiExpanded.toggle()
                    }
                }
            )
            
            if isRecentiExpanded {
                FilterChipView(
                    label: "Ultimi 24h",
                    icon: "clock.arrow.circlepath",
                    count: ultimiCount,
                    isActive: showUltimiOnly,
                    color: .cyan,
                    isSubItem: true,
                    showLabel: showFilterLabels
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5).combined(with: .opacity),
                    removal: .scale(scale: 0.8).combined(with: .opacity)
                ))
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showUltimiOnly.toggle()
                        refreshCountsSnapshot()
                    }
                }
            }
        }
    }
    
    private func isRecente(_ sinistro: SinistroMinimal) -> Bool {
        guard let anno = sinistro.annoSinistro else { return true }
        let currentYear = Calendar.current.component(.year, from: Date())
        return anno == currentYear || anno == currentYear - 1
    }
    
    // MARK: - Filtro Compagnia (gerarchia dinamica)
    
    @ViewBuilder
    private var companyFilterSection: some View {
        let hasSelection = !selectedCompanies.isEmpty
        let totalCount = baseSinistriForCompanyFilter.filter { sinistro in
            let detected = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
            return detected != .unknown
        }.count
        
        if !activeCompanies.isEmpty {
            HStack(spacing: 6) {
                FilterChipView(
                    label: "Compagnia",
                    icon: "building.columns",
                    count: totalCount,
                    isActive: isCompagniaSectionExpanded || hasSelection,
                    color: .indigo,
                    showLabel: showFilterLabels
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isCompagniaSectionExpanded.toggle()
                        if !isCompagniaSectionExpanded {
                            expandedGruppi.removeAll()
                        }
                    }
                }
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedCompanies.removeAll()
                            saveCompaniesSelection()
                            refreshCountsSnapshot()
                        }
                    }
                )
                
                if isCompagniaSectionExpanded {
                    ForEach(activeGruppi, id: \.self) { gruppo in
                        companyGroupView(for: gruppo)
                    }
                }
            }
        }
    }
    
    private var baseSinistriForCompanyFilter: [SinistroMinimal] {
        recentOnly ? allSinistri.filter { isRecente($0) } : allSinistri
    }
    
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
    
    private var activeGruppi: [GruppoAssicurativo] {
        GruppoAssicurativo.allCases.filter { gruppo in
            gruppo != .unknown && gruppo.compagnie.contains { activeCompanies.contains($0) }
        }
    }
    
    @ViewBuilder
    private func companyGroupView(for gruppo: GruppoAssicurativo) -> some View {
        let compagnieAttive = gruppo.compagnie.filter { activeCompanies.contains($0) }
        let isGruppoActive = compagnieAttive.contains { selectedCompanies.contains($0.rawValue) }
        let isGruppoExpanded = expandedGruppi.contains(gruppo.rawValue)
        let groupCount = countSinistriForGroup(gruppo)
        
        if compagnieAttive.count == 1, let singleCompany = compagnieAttive.first {
            let isCompSelected = selectedCompanies.contains(singleCompany.rawValue)
            
            FilterChipView(
                label: singleCompany.sigla,
                icon: nil,
                count: groupCount,
                isActive: isCompSelected,
                color: singleCompany.color,
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
            HStack(spacing: 6) {
                FilterChipView(
                    label: gruppo.shortLabel,
                    icon: nil,
                    count: groupCount,
                    isActive: isGruppoActive || isGruppoExpanded,
                    color: gruppo.color,
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
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            toggleCompanyGroup(gruppo)
                        }
                    }
                )
                
                if isGruppoExpanded {
                    ForEach(compagnieAttive, id: \.self) { compagnia in
                        let compCount = countSinistriForCompany(compagnia)
                        let isCompSelected = selectedCompanies.contains(compagnia.rawValue)
                        
                        FilterChipView(
                            label: compagnia.sigla,
                            icon: nil,
                            count: compCount,
                            isActive: isCompSelected,
                            color: compagnia.color,
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
            selectedCompanies.subtract(compagnieRawValues)
        } else {
            selectedCompanies.formUnion(compagnieRawValues)
        }
        saveCompaniesSelection()
        refreshCountsSnapshot()
    }
    
    private func toggleCompany(_ compagnia: Compagnia) {
        if selectedCompanies.contains(compagnia.rawValue) {
            selectedCompanies.remove(compagnia.rawValue)
        } else {
            selectedCompanies.insert(compagnia.rawValue)
        }
        saveCompaniesSelection()
        refreshCountsSnapshot()
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
            if !selectedAgenzie.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(selectedAgenzie).sorted(), id: \.self) { agenzia in
                            SelectedPillView(text: agenzia) {
                                selectedAgenzie.remove(agenzia)
                                saveAgenzieSelection()
                                refreshCountsSnapshot()
                            }
                        }
                    }
                }
            }
            
            Menu {
                ForEach(availableAgenzie, id: \.self) { agenzia in
                    Button(agenzia) {
                        selectedAgenzie.insert(agenzia)
                        saveAgenzieSelection()
                        refreshCountsSnapshot()
                    }
                }
            } label: {
                Label("Aggiungi agenzia", systemImage: "plus.circle")
                    .font(.caption)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4)
        )
    }
    
    private var availableAgenzie: [String] {
        var baseSinistri = baseSinistriForCompanyFilter
        
        if !selectedCompanies.isEmpty {
            baseSinistri = baseSinistri.filter { sinistro in
                let detected = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
                return selectedCompanies.contains(detected.rawValue)
            }
        }
        
        let agenzie = Set(baseSinistri.compactMap { $0.agenzia }.filter { !$0.isEmpty })
        return agenzie.sorted()
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
            if !selectedTipoPolizze.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(selectedTipoPolizze).sorted(), id: \.self) { tipo in
                            SelectedPillView(text: tipo) {
                                selectedTipoPolizze.remove(tipo)
                                saveTipoPolizzeSelection()
                                refreshCountsSnapshot()
                            }
                        }
                    }
                }
            }
            
            Menu {
                ForEach(availableTipoPolizze, id: \.self) { tipo in
                    Button(tipo) {
                        selectedTipoPolizze.insert(tipo)
                        saveTipoPolizzeSelection()
                        refreshCountsSnapshot()
                    }
                }
            } label: {
                Label("Aggiungi polizza", systemImage: "plus.circle")
                    .font(.caption)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4)
        )
    }
    
    private var availableTipoPolizze: [String] {
        var baseSinistri = baseSinistriForCompanyFilter
        
        if !selectedCompanies.isEmpty {
            baseSinistri = baseSinistri.filter { sinistro in
                let detected = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
                return selectedCompanies.contains(detected.rawValue)
            }
        }
        
        let tipi = Set(baseSinistri.compactMap { $0.tipoPolizza }.filter { !$0.isEmpty })
        return tipi.sorted()
    }
    
    // MARK: - Stati Section
    
    @ViewBuilder
    private var statesSection: some View {
        if useGroupedView {
            ForEach(visibleGroups, id: \.self) { group in
                groupView(for: group)
            }
        } else {
            ForEach(StatoSinistro.allCases.filter { $0.isVisible }, id: \.self) { stato in
                classicStateItem(stato)
            }
        }
    }
    
    private var visibleGroups: [StateGroup] {
        StateGroup.allCases.filter { group in
            group.members.contains { $0.isVisible }
        }
    }
    
    private func visibleChildren(of group: StateGroup) -> [StatoSinistro] {
        group.members.filter { $0.isVisible }
    }
    
    private func isGroupActive(_ group: StateGroup) -> Bool {
        let children = visibleChildren(of: group)
        return children.contains { selectedStates.contains($0.descrizione) }
    }
    
    private func isGroupFullySelected(_ group: StateGroup) -> Bool {
        let children = visibleChildren(of: group)
        guard !children.isEmpty else { return false }
        return children.allSatisfy { selectedStates.contains($0.descrizione) }
    }
    
    private func selectedChildren(of group: StateGroup) -> Set<String> {
        let children = visibleChildren(of: group)
        return Set(children.filter { selectedStates.contains($0.descrizione) }.map { $0.descrizione })
    }
    
    @ViewBuilder
    private func groupView(for group: StateGroup) -> some View {
        let isActive = isGroupActive(group)
        let children = visibleChildren(of: group)
        let hasVariants = children.count > 1
        
        if children.count == 1, let singleState = children.first {
            singleStateView(singleState)
        } else {
            HStack(spacing: 6) {
                GroupCounterItem(
                    group: group,
                    count: groupCount(for: group),
                    isActive: isActive,
                    isFullySelected: isGroupFullySelected(group),
                    showLabels: showFilterLabels
                )
                .onTapGesture(count: 3) {
                    handleTripleClick(group)
                }
                .onTapGesture(count: 2) {
                    handleDoubleClickOnGroup(group)
                }
                .onTapGesture(count: 1) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                        handleSingleClickOnGroup(group)
                    }
                }
                
                if isActive && hasVariants {
                    ForEach(Array(children.enumerated()), id: \.element) { index, stato in
                        StateCounterItem(
                            stato: stato,
                            count: countsCache[stato.descrizione] ?? 0,
                            isSelected: selectedStates.contains(stato.descrizione),
                            showFilterLabels: showFilterLabels,
                            isSubState: true
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
    
    @ViewBuilder
    private func singleStateView(_ stato: StatoSinistro) -> some View {
        StateCounterItem(
            stato: stato,
            count: countsCache[stato.descrizione] ?? 0,
            isSelected: selectedStates.contains(stato.descrizione),
            showFilterLabels: showFilterLabels
        )
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
    
    @ViewBuilder
    private func classicStateItem(_ stato: StatoSinistro) -> some View {
        StateCounterItem(
            stato: stato,
            count: countsCache[stato.descrizione] ?? 0,
            isSelected: selectedStates.contains(stato.descrizione),
            showFilterLabels: showFilterLabels
        )
        .onTapGesture(count: 2) {
            selectedStates = [stato.descrizione]
            saveSelectedStates()
        }
        .onTapGesture(count: 1) {
            toggleState(stato.descrizione)
        }
    }
    
    // MARK: - Click Handlers (identici al Mac)
    
    private func handleSingleClickOnGroup(_ group: StateGroup) {
        let children = visibleChildren(of: group)
        let childDescriptions = Set(children.map { $0.descrizione })
        
        if isGroupActive(group) {
            let currentlySelected = selectedChildren(of: group)
            groupChildrenSelection[group.rawValue] = currentlySelected
            saveGroupChildrenSelection()
            selectedStates.subtract(childDescriptions)
        } else {
            let previousSelection = groupChildrenSelection[group.rawValue]
            if let previous = previousSelection, !previous.isEmpty {
                selectedStates.formUnion(previous)
            } else {
                selectedStates.formUnion(childDescriptions)
            }
        }
        saveSelectedStates()
    }
    
    private func handleDoubleClickOnGroup(_ group: StateGroup) {
        let children = visibleChildren(of: group)
        let childDescriptions = Set(children.map { $0.descrizione })
        let currentlySelected = selectedChildren(of: group)
        
        if currentlySelected.isEmpty {
            selectedStates = childDescriptions
        } else {
            selectedStates = currentlySelected
        }
        saveSelectedStates()
    }
    
    private func handleTripleClick(_ group: StateGroup) {
        let children = visibleChildren(of: group)
        let childDescriptions = Set(children.map { $0.descrizione })
        selectedStates.formUnion(childDescriptions)
        groupChildrenSelection[group.rawValue] = childDescriptions
        saveGroupChildrenSelection()
        saveSelectedStates()
    }
    
    private func handleSingleClickOnChild(_ stato: StatoSinistro, inGroup group: StateGroup) {
        toggleState(stato.descrizione)
        let currentlySelected = selectedChildren(of: group)
        groupChildrenSelection[group.rawValue] = currentlySelected
        saveGroupChildrenSelection()
    }
    
    private func handleDoubleClickOnChild(_ stato: StatoSinistro) {
        selectedStates = [stato.descrizione]
        saveSelectedStates()
    }
    
    private func toggleState(_ state: String) {
        if selectedStates.contains(state) {
            selectedStates.remove(state)
        } else {
            selectedStates.insert(state)
        }
        saveSelectedStates()
    }
    
    private func groupCount(for group: StateGroup) -> Int {
        let visibleMembers = group.members.filter { $0.isVisible }
        return visibleMembers.reduce(0) { $0 + (countsCache[$1.descrizione] ?? 0) }
    }
    
    // MARK: - Conteggi
    
    private var sinistriPerConteggiStati: [SinistroMinimal] {
        var filtered = allSinistri
        
        if recentOnly {
            filtered = filtered.filter { isRecente($0) }
        }
        
        if showUltimiOnly {
            filtered = filtered.filter { recentInteractions.contains($0.id) }
        }
        
        if !selectedCompanies.isEmpty {
            filtered = filtered.filter { sinistro in
                let detected = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
                return selectedCompanies.contains(detected.rawValue)
            }
        }
        
        if !selectedAgenzie.isEmpty {
            filtered = filtered.filter { sinistro in
                guard let agenzia = sinistro.agenzia?.lowercased() else { return false }
                return selectedAgenzie.map { $0.lowercased() }.contains(agenzia)
            }
        }
        
        if !selectedTipoPolizze.isEmpty {
            filtered = filtered.filter { sinistro in
                guard let tipoPolizza = sinistro.tipoPolizza?.lowercased() else { return false }
                return selectedTipoPolizze.map { $0.lowercased() }.contains(tipoPolizza)
            }
        }
        
        return filtered
    }
    
    private func refreshCountsSnapshot() {
        let states = sinistriPerConteggiStati.map { $0.stato }
        var allCounts = Dictionary(grouping: states, by: { $0 }).mapValues { $0.count }
        
        for stato in StatoSinistro.allCases where stato.isVisible {
            if allCounts[stato.descrizione] == nil {
                allCounts[stato.descrizione] = 0
            }
        }
        
        countsCache = allCounts
    }
    
    // MARK: - Filtro finale
    
    private var filteredSinistri: [SinistroMinimal] {
        var result = sinistriPerConteggiStati
        
        if !selectedStates.isEmpty {
            result = result.filter { selectedStates.contains($0.stato) }
        }
        
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.riferimento.lowercased().contains(query) ||
                $0.nomeAssicurato.lowercased().contains(query) ||
                ($0.nomeDanneggiato?.lowercased().contains(query) ?? false) ||
                $0.nomeCompagnia.lowercased().contains(query)
            }
        }
        
        result.sort { ($0.dataAssegnazione ?? .distantPast) > ($1.dataAssegnazione ?? .distantPast) }
        
        return result
    }
    
    // MARK: - Persistenza
    
    private func saveSelectedStates() {
        if let encoded = try? JSONEncoder().encode(selectedStates) {
            savedStatesData = encoded
        }
    }
    
    private func saveCompaniesSelection() {
        if let encoded = try? JSONEncoder().encode(selectedCompanies) {
            savedCompaniesData = encoded
        }
    }
    
    private func saveAgenzieSelection() {
        if let encoded = try? JSONEncoder().encode(selectedAgenzie) {
            savedAgenzieData = encoded
        }
    }
    
    private func saveTipoPolizzeSelection() {
        if let encoded = try? JSONEncoder().encode(selectedTipoPolizze) {
            savedTipoPolizzeData = encoded
        }
    }
    
    private func saveGroupChildrenSelection() {
        if let encoded = try? JSONEncoder().encode(groupChildrenSelection) {
            groupChildrenData = encoded
        }
    }
    
    private func loadSavedFilters() {
        if let data = try? JSONDecoder().decode(Set<String>.self, from: savedStatesData) {
            selectedStates = data
        }
        if let data = try? JSONDecoder().decode(Set<String>.self, from: savedCompaniesData) {
            selectedCompanies = data
        }
        if let data = try? JSONDecoder().decode(Set<String>.self, from: savedAgenzieData) {
            selectedAgenzie = data
        }
        if let data = try? JSONDecoder().decode(Set<String>.self, from: savedTipoPolizzeData) {
            selectedTipoPolizze = data
        }
        if let decoded = try? JSONDecoder().decode([String: Set<String>].self, from: groupChildrenData) {
            groupChildrenSelection = decoded
        }
    }
    
    // MARK: - List Content
    
    @ViewBuilder
    private var listContent: some View {
        if filteredSinistri.isEmpty {
            ContentUnavailableView {
                Label("Nessun sinistro", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Prova a modificare i filtri o la ricerca")
            }
        } else {
            List {
                ForEach(filteredSinistri) { sinistro in
                    SinistroRowView(
                        sinistro: sinistro,
                        onChangeStato: { newStato in
                            print("Cambio stato a: \(newStato.descrizione)")
                        },
                        onChangePriority: { newPriority in
                            print("Cambio priorità a: \(newPriority.rawValue)")
                        },
                        onChangeComplessita: { newGrado in
                            print("Cambio complessità a: \(newGrado.rawValue)")
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        navigationPath.append(sinistro)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Filter Chip View (identico al Mac)

struct FilterChipView: View {
    let label: String
    var icon: String? = nil
    var count: Int? = nil
    let isActive: Bool
    let color: Color
    var isSubItem: Bool = false
    var isGrandChild: Bool = false
    var showBadge: Bool = false
    var showLabel: Bool = true
    
    var body: some View {
        HStack(spacing: 6) {
            if isSubItem || isGrandChild {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(isActive ? 0.6 : 0.3))
                    .frame(width: isGrandChild ? 1.5 : 2, height: isGrandChild ? 12 : 14)
            }
            
            if let icon = icon {
                Image(systemName: icon)
                    .font(isGrandChild ? .system(size: 10) : (isSubItem ? .caption : .body))
                    .foregroundColor(isActive ? color : color.opacity(0.7))
            }
            
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
        .padding(.horizontal, isGrandChild ? 5 : (isSubItem ? 6 : 8))
        .padding(.vertical, isGrandChild ? 3 : (isSubItem ? 4 : 5))
        .background(
            RoundedRectangle(cornerRadius: isGrandChild ? 4 : (isSubItem ? 5 : 6))
                .fill(isActive ? color.opacity(isGrandChild ? 0.2 : 0.15) : Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: isGrandChild ? 4 : (isSubItem ? 5 : 6))
                        .strokeBorder(isActive ? color : .clear, lineWidth: isGrandChild ? 0.5 : (isSubItem ? 0.8 : 1))
                )
        )
        .scaleEffect(isActive ? 1.0 : (isGrandChild ? 0.94 : 0.96))
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isActive)
    }
}

// MARK: - State Counter Item (identico al Mac)

struct StateCounterItem: View {
    let stato: StatoSinistro
    let count: Int
    let isSelected: Bool
    let showFilterLabels: Bool
    var isSubState: Bool = false
    
    private var displayLabel: String {
        if isSubState {
            let variant = stato.variant
            let group = stato.stateGroup
            
            if !variant.isBase {
                return variant.rawValue
            }
            
            let hasSemanticVariants = group.members.contains { !$0.variant.isBase }
            if hasSemanticVariants {
                return "tradizionale"
            }
            
            return stato.descrizione
        }
        return stato.descrizione
    }
    
    private var cornerRadius: CGFloat { isSubState ? 6 : 8 }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: stato.icon)
                .foregroundColor(isSelected ? stato.color : stato.color.opacity(0.7))
                .font(isSubState ? .caption : .body)
            
            if showFilterLabels {
                Text(displayLabel)
                    .font(isSubState ? .caption2 : .caption)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            
            Text("\(count)")
                .font(isSubState ? .caption.bold() : .system(.body, design: .rounded).bold())
                .foregroundColor(isSelected ? .primary : .secondary)
        }
        .padding(.horizontal, isSubState ? 6 : 8)
        .padding(.vertical, isSubState ? 4 : 5)
        .frame(minWidth: 36, minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isSelected ? stato.color.opacity(isSubState ? 0.18 : 0.15) : Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(isSelected ? stato.color : .clear, lineWidth: isSubState ? 1.5 : 2)
                )
        )
        .scaleEffect(isSelected ? 1.0 : 0.96)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSelected)
    }
}

// MARK: - Group Counter Item (identico al Mac)

struct GroupCounterItem: View {
    let group: StateGroup
    let count: Int
    let isActive: Bool
    let isFullySelected: Bool
    let showLabels: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(group.color.opacity(isActive ? 0.6 : 0.3))
                .frame(width: 2, height: 16)
            
            Image(systemName: group.icon)
                .foregroundColor(isActive ? group.color : group.color.opacity(0.7))
                .font(.body)
            
            if showLabels {
                Text(group.shortLabel)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(isActive ? .primary : .secondary)
            }
            
            Text("\(count)")
                .font(.system(.body, design: .rounded).bold())
                .foregroundColor(isActive ? .primary : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minWidth: 36, minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isFullySelected ? group.color.opacity(0.15) : (isActive ? group.color.opacity(0.12) : Color(.systemGray6)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isActive && !isFullySelected ? group.color.opacity(0.5) : .clear, lineWidth: 1)
                )
        )
        .scaleEffect(isActive ? 1.0 : 0.96)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isActive)
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

// MARK: - Sinistro Row View

struct SinistroRowView: View {
    let sinistro: SinistroMinimal
    var onChangeStato: ((StatoSinistro) -> Void)?
    var onChangePriority: ((PriorityLevel) -> Void)?
    var onChangeComplessita: ((GradoComplessita) -> Void)?
    
    private var compagnia: Compagnia {
        Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Riga 1: Riferimento + Stato
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(compagnia.color)
                    .frame(width: 4, height: 36)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(sinistro.riferimentoVisualizzato)
                            .font(.headline)
                        
                        if sinistro.fulminazione {
                            Image(systemName: "bolt.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        
                        if sinistro.sopralluogo {
                            Text("T")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                    
                    Text(sinistro.nomeAssicurato)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                ExpandableStatoPill(
                    stato: sinistro.stato,
                    onChangeStato: onChangeStato
                )
            }
            
            // Riga 2: Info e indicatori
            HStack(spacing: 12) {
                Text(sinistro.nomeCompagnia)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let tipo = sinistro.tipoPolizza {
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(tipo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    ExpandablePriorityPill(
                        priorityValue: sinistro.prioritaEffettiva,
                        hasManualPriority: sinistro.hasManualPriority,
                        onChangePriority: onChangePriority
                    )
                    
                    ExpandableComplessitaPill(
                        complessita: sinistro.complessita,
                        onChangeComplessita: onChangeComplessita
                    )
                    
                    if sinistro.beniCount > 0 {
                        ExpandableBeniPill(beniCount: sinistro.beniCount, beniList: [])
                    }
                    
                    if sinistro.sollecitiRicevutiCount > 0 {
                        ExpandableSollecitiPill(sollecitiCount: sinistro.sollecitiRicevutiCount, sollecitiList: [])
                    }
                    
                    if sinistro.taskCount > 0 {
                        ExpandableTaskPill(taskCount: sinistro.taskCount, taskList: [])
                    }
                }
                
            }
        }
        .padding(.vertical, 8)
    }
}
