import SwiftUI

struct ColumnMappingRowView: View {
    let header: String
    @Binding var selectedField: ImportService.DatabaseField?
    let suggestedField: ImportService.DatabaseField?
    
    @State private var searchText: String = ""
    @State private var isSearchFocused: Bool = false
    @FocusState private var isFocused: Bool
    
    private var filteredFields: [ImportService.DatabaseField] {
        if searchText.isEmpty {
            return ImportService.DatabaseField.allCases
        }
        
        let normalizedSearch = searchText.lowercased()
        return ImportService.DatabaseField.allCases.filter { field in
            field.displayName.lowercased().contains(normalizedSearch) ||
            field.rawValue.lowercased().contains(normalizedSearch)
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(header)
                .frame(width: 250, alignment: .leading)
                .font(.headline)
            
            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 4) {
                // Campo di ricerca
                TextField("Cerca campo...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onChange(of: searchText) { newValue in
                        if newValue.isEmpty && selectedField == nil {
                            // Se il campo è vuoto e non c'è selezione, mostra suggerimenti
                        }
                    }
                    .onChange(of: isFocused) { focused in
                        if focused && selectedField == nil && searchText.isEmpty {
                            // Pre-compila con il suggerimento se disponibile
                            if let suggested = suggestedField {
                                searchText = suggested.displayName
                            }
                        }
                    }
                
                // Lista suggerimenti
                if isFocused || !searchText.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            // Opzione "Ignora"
                            Button(action: {
                                selectedField = nil
                                searchText = ""
                                isFocused = false
                            }) {
                                HStack {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.secondary)
                                    Text("Ignora questa colonna")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                            
                            // Campi filtrati
                            ForEach(filteredFields.prefix(10), id: \.self) { field in
                                Button(action: {
                                    selectedField = field
                                    searchText = field.displayName
                                    isFocused = false
                                    // Salva immediatamente il mapping quando viene selezionato
                                    ImportService.shared.saveColumnMapping(columnName: header, targetField: field)
                                }) {
                                    HStack {
                                        if selectedField == field {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                        } else {
                                            Image(systemName: "circle")
                                                .foregroundColor(.secondary)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(field.displayName)
                                                .foregroundColor(.primary)
                                            Text(field.rawValue)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                }
                                .buttonStyle(.plain)
                                .background(selectedField == field ? Color.blue.opacity(0.1) : Color.clear)
                                .cornerRadius(4)
                            }
                            
                            if filteredFields.count > 10 {
                                Text("... e altri \(filteredFields.count - 10) campi")
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
                } else if let selected = selectedField {
                    // Mostra il campo selezionato quando non è in focus
                    HStack {
                        Text(selected.displayName)
                            .foregroundColor(.primary)
                        Spacer()
                            Button(action: {
                                selectedField = nil
                                searchText = ""
                                // Rimuovi il mapping salvato se esiste
                                ImportService.shared.savedColumnMappings.removeValue(forKey: header)
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
            .frame(width: 400)
        }
        .onAppear {
            if let selected = selectedField {
                searchText = selected.displayName
            } else if let suggested = suggestedField {
                searchText = suggested.displayName
            }
        }
    }
}

