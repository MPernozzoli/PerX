import SwiftUI

/// Campo di testo con supporto per suggerimenti visualizzati con bordo tratteggiato
struct SuggestedTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let suggestions: [String]
    let isSuggested: Bool
    let onConfirm: () -> Void
    
    @State private var showSuggestions: Bool = false
    @FocusState private var isFocused: Bool
    
    init(
        label: String,
        text: Binding<String>,
        placeholder: String = "",
        suggestions: [String] = [],
        isSuggested: Bool = false,
        onConfirm: @escaping () -> Void = {}
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.suggestions = suggestions
        self.isSuggested = isSuggested
        self.onConfirm = onConfirm
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ZStack(alignment: .leading) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .focused($isFocused)
                    .onChange(of: text) { _ in
                        if isSuggested {
                            onConfirm()
                        }
                    }
                    .onSubmit {
                        onConfirm()
                        showSuggestions = false
                    }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSuggested ? Color.orange.opacity(0.5) : Color(NSColor.separatorColor).opacity(0.4),
                        style: isSuggested ? StrokeStyle(lineWidth: 1, dash: [4, 3]) : StrokeStyle(lineWidth: 0.5)
                    )
            )
            .onTapGesture {
                if !suggestions.isEmpty {
                    showSuggestions = true
                }
            }
            
            if showSuggestions && !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(filteredSuggestions, id: \.self) { suggestion in
                        Button {
                            text = suggestion
                            showSuggestions = false
                            onConfirm()
                        } label: {
                            HStack {
                                Text(suggestion)
                                    .font(.system(size: 12))
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(NSColor.controlBackgroundColor))
                        }
                        .buttonStyle(.plain)
                        
                        if suggestion != filteredSuggestions.last {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 0.5)
                )
            }
        }
    }
    
    private var filteredSuggestions: [String] {
        if text.isEmpty {
            return Array(suggestions.prefix(5))
        }
        return suggestions.filter { $0.localizedCaseInsensitiveContains(text) }.prefix(5).map { $0 }
    }
}

/// Card per bene o componente suggerito
struct SuggestedItemCard: View {
    let title: String
    let subtitle: String?
    let isSuggested: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: (() -> Void)?
    
    init(
        title: String,
        subtitle: String? = nil,
        isSuggested: Bool = true,
        isSelected: Bool = false,
        onSelect: @escaping () -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSuggested = isSuggested
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onRemove = onRemove
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isSuggested ? .secondary : .primary)
                    
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if let onRemove = onRemove {
                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSuggested ? Color(NSColor.secondaryLabelColor).opacity(0.3) : (isSelected ? Color.accentColor : Color.clear),
                        style: isSuggested ? StrokeStyle(lineWidth: 0.5, dash: [3, 2]) : StrokeStyle(lineWidth: isSelected ? 1.5 : 0)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// Riga voce di costo suggerita con bordo tratteggiato
struct SuggestedVoceCostoRow: View {
    let descrizione: String
    let quantita: Double
    let valoreUnitario: Double
    var unitaMisura: String = "pz"
    var isSuggested: Bool = true
    let onConfirm: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Text(descrizione)
                .font(.system(size: 12))
                .foregroundColor(isSuggested ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("\(CurrencyFormatter.shared.format(quantita)) \(unitaMisura)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
            
            Text(CurrencyFormatter.shared.formatWithSymbol(valoreUnitario))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            
            Text(CurrencyFormatter.shared.formatWithSymbol(quantita * valoreUnitario))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSuggested ? .secondary : .primary)
                .frame(width: 100, alignment: .trailing)
            
            HStack(spacing: 4) {
                Button {
                    onConfirm()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 50)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    Color(NSColor.secondaryLabelColor).opacity(0.3),
                    style: StrokeStyle(lineWidth: 0.5, dash: [3, 2])
                )
        )
    }
}
