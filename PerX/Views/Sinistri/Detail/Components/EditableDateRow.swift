import SwiftUI

/// Componente per una riga di data che può essere visualizzata o editata
struct EditableDateRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    @Binding var date: Date?
    let isEditing: Bool
    let formatDate: (Date) -> String
    let onDelete: (() -> Void)?
    
    @State private var tempDate: Date = Date()
    @State private var hasValue: Bool = false
    
    init(
        icon: String,
        iconColor: Color,
        label: String,
        date: Binding<Date?>,
        isEditing: Bool,
        formatDate: @escaping (Date) -> String,
        onDelete: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self._date = date
        self.isEditing = isEditing
        self.formatDate = formatDate
        self.onDelete = onDelete
        self._tempDate = State(initialValue: date.wrappedValue ?? Date())
        self._hasValue = State(initialValue: date.wrappedValue != nil)
    }
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(label)
                    .foregroundColor(.secondary)
            }
            Spacer()
            
            if isEditing {
                editingView
            } else {
                displayView
            }
        }
        .onChange(of: date) { newValue in
            if let newDate = newValue {
                tempDate = newDate
                hasValue = true
            } else {
                hasValue = false
            }
        }
    }
    
    @ViewBuilder
    private var displayView: some View {
        if let date = date {
            Text(formatDate(date))
                .font(.system(.body, design: .rounded))
                .foregroundColor(iconColor)
        } else {
            Text("Data mancante")
                .italic()
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
    
    @ViewBuilder
    private var editingView: some View {
        HStack(spacing: 8) {
            if hasValue {
                DatePicker(
                    "",
                    selection: $tempDate,
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .onChange(of: tempDate) { newValue in
                    date = newValue
                }
                
                // Pulsante cancella
                if onDelete != nil {
                    Button {
                        date = nil
                        hasValue = false
                        onDelete?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Rimuovi data")
                }
            } else {
                // Pulsante per aggiungere data
                Button {
                    tempDate = Date()
                    date = tempDate
                    hasValue = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                        Text("Aggiungi")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
