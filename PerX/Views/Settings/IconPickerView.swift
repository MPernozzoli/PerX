import SwiftUI

struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIcon: String
    
    // Array di icone SF Symbols raggruppate per categoria
    private let iconCategories = [
        "Stati": [
            "circle", "circle.fill",
            "checkmark.circle", "checkmark.circle.fill",
            "exclamationmark.circle", "exclamationmark.circle.fill",
            "xmark.circle", "xmark.circle.fill",
            "questionmark.circle", "questionmark.circle.fill",
            "info.circle", "info.circle.fill"
        ],
        "Documenti": [
            "doc", "doc.fill",
            "doc.text", "doc.text.fill",
            "doc.plaintext", "doc.richtext",
            "doc.append", "doc.text.below.ecg",
            "doc.viewfinder", "doc.viewfinder.fill",
            "doc.badge.clock", "doc.badge.clock.fill",
            "doc.badge.plus", "doc.fill.badge.plus",
            "doc.badge.gearshape", "doc.badge.gearshape.fill"
        ],
        "Comunicazione": [
            "message", "message.fill",
            "envelope", "envelope.fill",
            "envelope.open", "envelope.open.fill",
            "paperplane", "paperplane.fill",
            "paperplane.circle", "paperplane.circle.fill",
            "bell", "bell.fill",
            "bell.badge", "bell.badge.fill"
        ],
        "Processo": [
            "gearshape", "gearshape.fill",
            "gearshape.2", "gearshape.2.fill",
            "clock", "clock.fill",
            "timer", "timer.square",
            "hourglass", "hourglass.circle",
            "hourglass.bottomhalf.filled", "hourglass.tophalf.filled"
        ],
        "Azioni": [
            "arrow.right.circle", "arrow.right.circle.fill",
            "arrow.left.circle", "arrow.left.circle.fill",
            "arrow.up.circle", "arrow.up.circle.fill",
            "arrow.down.circle", "arrow.down.circle.fill",
            "arrow.clockwise.circle", "arrow.clockwise.circle.fill",
            "arrow.triangle.2.circlepath", "arrow.triangle.2.circlepath.circle"
        ],
        "Cartelle": [
            "folder", "folder.fill",
            "folder.badge.plus", "folder.fill.badge.plus",
            "folder.badge.minus", "folder.fill.badge.minus",
            "folder.badge.questionmark", "folder.fill.badge.questionmark",
            "folder.badge.person.crop", "folder.fill.badge.person.crop"
        ],
        "Varie": [
            "lock", "lock.fill",
            "lock.open", "lock.open.fill",
            "shield", "shield.fill",
            "flag", "flag.fill",
            "tag", "tag.fill",
            "bookmark", "bookmark.fill",
            "star", "star.fill",
            "heart", "heart.fill"
        ]
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Seleziona Icona")
                .font(.headline)
            
            // Icona selezionata
            Image(systemName: selectedIcon)
                .font(.system(size: 32))
                .foregroundColor(.accentColor)
                .frame(height: 50)
            
            // Lista di icone raggruppate
            List {
                ForEach(Array(iconCategories.keys.sorted()), id: \.self) { category in
                    Section(header: Text(category)) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                            ForEach(iconCategories[category] ?? [], id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.system(size: 20))
                                        .foregroundColor(selectedIcon == icon ? .accentColor : .primary)
                                        .frame(width: 30, height: 30)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(selectedIcon == icon ? Color.accentColor.opacity(0.1) : Color.clear)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            
            // Pulsanti
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                
                Button("Conferma") {
                    dismiss()
                }
                .keyboardShortcut(.return)
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 500, height: 600)
    }
} 