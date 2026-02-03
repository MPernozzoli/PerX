import SwiftUI

// MARK: - Autocomplete Field View

struct AutocompleteFieldView: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let suggestions: [String]
    let usedInSinistro: [String]
    @Binding var showSuggestions: Bool
    @Binding var isEditing: Bool
    @FocusState var isFocused: Bool
    let onSave: () -> Void
    var onClear: (() -> Void)? = nil  // Callback opzionale per clear
    
    @State private var debounceTask: Task<Void, Never>?
    
    private var hasSuggestions: Bool { !suggestions.isEmpty }
    
    private var filteredSuggestions: [String] {
        if text.isEmpty {
            return Array(suggestions.prefix(8))
        }
        return suggestions.filter { $0.localizedCaseInsensitiveContains(text) }.prefix(8).map { $0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            HStack(spacing: 6) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .focused($isFocused)
                    .onChange(of: isFocused) { focused in
                        isEditing = focused
                        if focused && hasSuggestions {
                            showSuggestions = true
                        } else if !focused {
                            // Salva quando il focus esce
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                showSuggestions = false
                            }
                        }
                    }
                    .onChange(of: text) { _ in
                        // Salvataggio con debounce ad ogni modifica
                        saveDebounced()
                    }
                
                // Pulsante X per cancellare
                if !text.isEmpty {
                    Button {
                        text = ""
                        debounceTask?.cancel()
                        onSave()
                        onClear?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Rimuovi")
                }
                
                // Pulsante dropdown se ci sono suggerimenti
                if hasSuggestions {
                    Button {
                        showSuggestions.toggle()
                        if showSuggestions {
                            isFocused = true
                        }
                    } label: {
                        Image(systemName: showSuggestions ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                }
                
                // Indicatore salvataggio
                if !text.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green.opacity(0.7))
                }
            }
            
            // Dropdown suggerimenti
            if showSuggestions && !filteredSuggestions.isEmpty {
                SuggestionsListView(
                    suggestions: filteredSuggestions,
                    query: text,
                    usedInSinistro: usedInSinistro,
                    onSelect: { selected in
                        text = selected
                        showSuggestions = false
                        isFocused = false
                        debounceTask?.cancel()
                        onSave()
                    }
                )
            }
        }
        .onDisappear {
            // Salva quando la view scompare (cambio foto, ecc.)
            debounceTask?.cancel()
            onSave()
        }
    }
    
    private func saveDebounced() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 secondi
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onSave()
            }
        }
    }
}

// MARK: - Suggestions List View

struct SuggestionsListView: View {
    let suggestions: [String]
    let query: String
    let usedInSinistro: [String]
    let onSelect: (String) -> Void
    
    private var usedFiltered: [String] {
        suggestions.filter { suggestion in
            usedInSinistro.contains { $0.localizedCaseInsensitiveCompare(suggestion) == .orderedSame }
        }
    }
    
    private var othersFiltered: [String] {
        suggestions.filter { suggestion in
            !usedInSinistro.contains { $0.localizedCaseInsensitiveCompare(suggestion) == .orderedSame }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sezione "Usati in questo sinistro"
            if !usedFiltered.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9))
                    Text("Usati nel sinistro")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)
                
                ForEach(usedFiltered, id: \.self) { suggestion in
                    SuggestionRowView(
                        text: suggestion,
                        query: query,
                        isUsed: true,
                        onSelect: { onSelect(suggestion) }
                    )
                }
                
                if !othersFiltered.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                }
            }
            
            // Sezione altri suggerimenti
            if !othersFiltered.isEmpty {
                if !usedFiltered.isEmpty {
                    Text("Suggerimenti")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                }
                
                ForEach(othersFiltered, id: \.self) { suggestion in
                    SuggestionRowView(
                        text: suggestion,
                        query: query,
                        isUsed: false,
                        onSelect: { onSelect(suggestion) }
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .frame(maxHeight: 160)
    }
}

// MARK: - Suggestion Row View

struct SuggestionRowView: View {
    let text: String
    let query: String
    let isUsed: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                if isUsed {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
                
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
