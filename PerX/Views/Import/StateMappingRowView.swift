import SwiftUI

struct StateMappingRowView: View {
    let sourceState: String
    @Binding var selectedState: String
    let suggestedState: String?
    
    @StateObject private var statoManager = StatoManager.shared
    @State private var searchText: String = ""
    @State private var isSearchFocused: Bool = false
    @FocusState private var isFocused: Bool
    
    private var filteredStates: [StatoManager.StatoInfo] {
        if searchText.isEmpty {
            return statoManager.availableStates
        }
        
        let normalizedSearch = searchText.lowercased()
        return statoManager.availableStates.filter { state in
            state.descrizione.lowercased().contains(normalizedSearch) ||
            state.id.lowercased().contains(normalizedSearch)
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(sourceState)
                .frame(width: 250, alignment: .leading)
                .font(.headline)
            
            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 4) {
                // Campo di ricerca
                TextField("Cerca stato...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onChange(of: searchText) { newValue in
                        if newValue.isEmpty && selectedState.isEmpty {
                            // Se il campo è vuoto e non c'è selezione, mostra suggerimenti
                        }
                    }
                    .onChange(of: isFocused) { focused in
                        if focused && selectedState.isEmpty && searchText.isEmpty {
                            // Pre-compila con il suggerimento se disponibile
                            if let suggested = suggestedState {
                                searchText = suggested
                            }
                        }
                    }
                
                // Lista suggerimenti
                if isFocused || !searchText.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            // Opzione "Ignora"
                            Button(action: {
                                selectedState = ""
                                searchText = ""
                                isFocused = false
                                // Rimuovi il mapping salvato se esiste
                                ImportService.shared.savedStateMappings.removeValue(forKey: sourceState)
                            }) {
                                HStack {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.secondary)
                                    Text("Non importare questo stato")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                            
                            // Stati filtrati
                            ForEach(filteredStates.prefix(10), id: \.id) { state in
                                Button(action: {
                                    selectedState = state.descrizione
                                    searchText = state.descrizione
                                    isFocused = false
                                    // Salva immediatamente il mapping quando viene selezionato
                                    ImportService.shared.saveStateMapping(sourceState: sourceState, targetState: state.descrizione)
                                }) {
                                    HStack {
                                        if selectedState == state.descrizione {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                        } else {
                                            Image(systemName: "circle")
                                                .foregroundColor(.secondary)
                                        }
                                        HStack(spacing: 8) {
                                            Image(systemName: state.icon)
                                                .foregroundColor(state.color)
                                                .frame(width: 20)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(state.descrizione)
                                                    .foregroundColor(.primary)
                                                Text(state.id)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                }
                                .buttonStyle(.plain)
                                .background(selectedState == state.descrizione ? Color.blue.opacity(0.1) : Color.clear)
                                .cornerRadius(4)
                            }
                            
                            if filteredStates.count > 10 {
                                Text("... e altri \(filteredStates.count - 10) stati")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .padding(4)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                } else if !selectedState.isEmpty {
                    // Mostra lo stato selezionato quando non è in focus
                    if let selectedStateInfo = statoManager.availableStates.first(where: { $0.descrizione == selectedState }) {
                        HStack {
                            Image(systemName: selectedStateInfo.icon)
                                .foregroundColor(selectedStateInfo.color)
                            Text(selectedStateInfo.descrizione)
                                .foregroundColor(.primary)
                            Spacer()
                            Button(action: {
                                selectedState = ""
                                searchText = ""
                                // Rimuovi il mapping salvato se esiste
                                ImportService.shared.savedStateMappings.removeValue(forKey: sourceState)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            .frame(width: 400)
        }
        .onAppear {
            if !selectedState.isEmpty {
                searchText = selectedState
            } else if let suggested = suggestedState {
                searchText = suggested
            }
        }
    }
}

