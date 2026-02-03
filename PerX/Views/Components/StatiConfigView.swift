import SwiftUI
import CoreData

struct StatiConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var statoManager = StatoManager.shared
    @AppStorage("showFilterLabels") private var showFilterLabels = true
    @State private var visibleStates: Set<String>
    @State private var showingStatiSettings = false
    
    // Visibilità filtri
    @AppStorage("showUserFilter") private var showUserFilter = false  // Nascosto di default
    @AppStorage("showRecentFilter") private var showRecentFilter = true
    @AppStorage("showCompanyFilter") private var showCompanyFilter = true
    @AppStorage("showAgenziaFilter") private var showAgenziaFilter = true
    @AppStorage("showPolizzaFilter") private var showPolizzaFilter = true
    @AppStorage("recentFilterDefaultOn") private var recentFilterDefaultOn = true
    
    init() {
        let defaultStates = Set(StatoManager.StatoSinistro.allCases
            .filter { $0.isVisible }
            .map { $0.id })
        
        if let savedStatesData = UserDefaults.standard.data(forKey: "visibleStates"),
           let savedStates = try? JSONDecoder().decode([String].self, from: savedStatesData) {
            _visibleStates = State(initialValue: Set(savedStates))
        } else {
            _visibleStates = State(initialValue: defaultStates)
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Configura Visualizzazione Filtri")
                .font(.title2)
                .padding(.top)
            
            // MARK: - Opzione etichette (senza titolo)
            Toggle("Mostra etichette filtri", isOn: $showFilterLabels)
                .padding(.horizontal)
            
            Divider()
            
            // MARK: - Filtri visibili (stile coerente con stati)
            VStack(alignment: .leading) {
                Text("Filtri Visibili")
                    .font(.headline)
                    .padding(.horizontal)
                
                List {
                    // Utente (nascosto di default)
                    filterRow(
                        icon: "person.fill",
                        label: "Utente",
                        color: .green,
                        isVisible: showUserFilter,
                        onToggle: { showUserFilter.toggle() }
                    )
                    
                    // Recenti
                    filterRow(
                        icon: "calendar.badge.clock",
                        label: "Recenti",
                        color: .blue,
                        isVisible: showRecentFilter,
                        onToggle: { showRecentFilter.toggle() }
                    )
                    
                    // Opzione default (solo se Recenti è disattivato)
                    if !showRecentFilter {
                        HStack {
                            Rectangle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 2, height: 16)
                            
                            Text("Quando nascosto:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Picker("", selection: $recentFilterDefaultOn) {
                                Text("Attivo").tag(true)
                                Text("Disattivo").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 130)
                        }
                        .padding(.leading, 8)
                        .padding(.vertical, 2)
                    }
                    
                    // Compagnia
                    filterRow(
                        icon: "building.columns",
                        label: "Compagnia",
                        color: .indigo,
                        isVisible: showCompanyFilter,
                        onToggle: { showCompanyFilter.toggle() }
                    )
                    
                    // Agenzia
                    filterRow(
                        icon: "building.2",
                        label: "Agenzia",
                        color: .orange,
                        isVisible: showAgenziaFilter,
                        onToggle: { showAgenziaFilter.toggle() }
                    )
                    
                    // Polizza
                    filterRow(
                        icon: "doc.text",
                        label: "Polizza",
                        color: .purple,
                        isVisible: showPolizzaFilter,
                        onToggle: { showPolizzaFilter.toggle() }
                    )
                }
                .listStyle(.inset)
                .frame(height: 160)
            }
            
            Divider()
            
            VStack(alignment: .leading) {
                HStack {
                    Text("Stati Visibili")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button {
                        showingStatiSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                
                List {
                    // Gruppi di stati (vista gerarchica)
                    ForEach(StateGroup.allCases.filter { $0 != .sistema }, id: \.self) { group in
                        Section {
                            // Header del gruppo con toggle per selezionare/deselezionare tutto
                            HStack {
                                Image(systemName: group.icon)
                                    .foregroundColor(group.color)
                                Text(group.shortLabel)
                                    .font(.subheadline.bold())
                                Spacer()
                                
                                // Conta quanti stati del gruppo sono visibili
                                let groupMembers = group.members
                                let visibleCount = groupMembers.filter { visibleStates.contains($0.id) }.count
                                
                                Button {
                                    // Toggle tutti gli stati del gruppo
                                    if visibleCount == groupMembers.count {
                                        // Tutti visibili → nascondi tutti
                                        for member in groupMembers {
                                            visibleStates.remove(member.id)
                                        }
                                    } else {
                                        // Non tutti visibili → mostra tutti
                                        for member in groupMembers {
                                            visibleStates.insert(member.id)
                                        }
                                    }
                                    saveVisibleStates()
                                } label: {
                                    Image(systemName: visibleCount == groupMembers.count ? "checkmark.circle.fill" : 
                                          visibleCount > 0 ? "minus.circle.fill" : "circle")
                                        .foregroundColor(visibleCount > 0 ? group.color : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                            
                            // Stati singoli del gruppo
                            ForEach(group.members, id: \.self) { stato in
                                Button {
                                    toggleVisibility(stato.id)
                                } label: {
                                    HStack {
                                        // Indentazione
                                        Rectangle()
                                            .fill(group.color.opacity(0.3))
                                            .frame(width: 2, height: 16)
                                        
                                        Image(systemName: stato.icon)
                                            .foregroundColor(visibleStates.contains(stato.id) ? stato.color : .gray)
                                            .font(.caption)
                                        
                                        // Mostra la variante se semantica, altrimenti la descrizione completa
                                        Text(displayLabelForState(stato, inGroup: group))
                                            .font(.caption)
                                            .foregroundColor(visibleStates.contains(stato.id) ? .primary : .gray)
                                        
                                        Spacer()
                                        
                                        Image(systemName: visibleStates.contains(stato.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(visibleStates.contains(stato.id) ? stato.color : .secondary)
                                            .font(.caption)
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 2)
                                .padding(.leading, 8)
                            }
                        }
                    }
                    
                    Section("Stati di Sistema") {
                        ForEach(StatoManager.StatoSinistro.allCases.filter { $0.isSystem }, id: \.self) { stato in
                            Button {
                                toggleVisibility(stato.id)
                            } label: {
                                HStack {
                                    Image(systemName: stato.icon)
                                        .foregroundColor(visibleStates.contains(stato.id) ? stato.color : .gray)
                                    Text(stato.descrizione)
                                        .foregroundColor(visibleStates.contains(stato.id) ? .primary : .gray)
                                    Spacer()
                                    Image(systemName: visibleStates.contains(stato.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(visibleStates.contains(stato.id) ? stato.color : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }
                    }
                    
                    if !statoManager.availableCustomStates.isEmpty {
                        Section("Stati Personalizzati") {
                            ForEach(statoManager.availableCustomStates) { stato in
                                Button {
                                    toggleVisibility(stato.id)
                                } label: {
                                    HStack {
                                        Image(systemName: stato.icon)
                                            .foregroundColor(visibleStates.contains(stato.id) ? 
                                                           (Color(hex: stato.color) ?? .gray) : 
                                                           .gray)
                                        Text(stato.descrizione)
                                            .foregroundColor(visibleStates.contains(stato.id) ? .primary : .gray)
                                        Spacer()
                                        Image(systemName: visibleStates.contains(stato.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(visibleStates.contains(stato.id) ? (Color(hex: stato.color) ?? .gray) : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            
            HStack {
                Button("Seleziona Tutti") {
                    visibleStates = Set(StatoManager.StatoSinistro.allCases.map { $0.id })
                    visibleStates.formUnion(statoManager.availableCustomStates.map { $0.id })
                    UserDefaults.standard.set(Array(visibleStates), forKey: "visibleStates")
                }
                
                Button("Deseleziona Tutti") {
                    visibleStates.removeAll()
                    UserDefaults.standard.set(Array(visibleStates), forKey: "visibleStates")
                }
                
                Spacer()
                
                Button("Chiudi") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400, height: 600)
        .sheet(isPresented: $showingStatiSettings) {
            StatiSettingsView()
        }
        .onDisappear {
            saveVisibleStates()
        }
    }
    
    // MARK: - Helpers
    
    private func toggleVisibility(_ stateId: String) {
        if visibleStates.contains(stateId) {
            visibleStates.remove(stateId)
        } else {
            visibleStates.insert(stateId)
        }
        saveVisibleStates()
    }
    
    private func saveVisibleStates() {
        if let encoded = try? JSONEncoder().encode(Array(visibleStates)) {
            UserDefaults.standard.set(encoded, forKey: "visibleStates")
        }
    }
    
    /// Determina l'etichetta da mostrare per uno stato in un gruppo
    private func displayLabelForState(_ stato: StatoManager.StatoSinistro, inGroup group: StateGroup) -> String {
        // Se lo stato ha una variante semantica (documentale, videoperizia, ecc.), mostrala
        if !stato.variant.isBase {
            return stato.variant.rawValue
        }
        
        // Se il gruppo ha varianti semantiche (almeno un membro con variant non-base)
        // e questo stato è "tradizionale", mostra "tradizionale"
        let hasSemanticVariants = group.members.contains { !$0.variant.isBase }
        if hasSemanticVariants {
            return "tradizionale"
        }
        
        // Altrimenti mostra la descrizione completa dello stato
        return stato.descrizione
    }
    
    /// Riga filtro con stile coerente agli stati
    @ViewBuilder
    private func filterRow(icon: String, label: String, color: Color, isVisible: Bool, onToggle: @escaping () -> Void) -> some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(isVisible ? color : .gray)
                
                Text(label)
                    .foregroundColor(isVisible ? .primary : .gray)
                
                Spacer()
                
                Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isVisible ? color : .secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
} 