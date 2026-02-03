import SwiftUI

struct ColorPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedColor: Color
    @State private var customColor = Color.blue
    
    // Colori predefiniti
    private let presetColors: [(name: String, colors: [Color])] = [
        ("Base", [.red, .orange, .yellow, .green, .blue, .purple, .gray]),
        ("Pastello", [
            Color(red: 1.0, green: 0.8, blue: 0.8),  // Rosa pastello
            Color(red: 1.0, green: 0.9, blue: 0.8),  // Pesca
            Color(red: 0.9, green: 1.0, blue: 0.8),  // Verde chiaro
            Color(red: 0.8, green: 0.9, blue: 1.0),  // Azzurro chiaro
            Color(red: 0.9, green: 0.8, blue: 1.0)   // Lavanda
        ]),
        ("Intensi", [
            Color(red: 0.8, green: 0.2, blue: 0.2),  // Rosso scuro
            Color(red: 0.2, green: 0.6, blue: 0.2),  // Verde scuro
            Color(red: 0.2, green: 0.2, blue: 0.8),  // Blu scuro
            Color(red: 0.6, green: 0.2, blue: 0.6),  // Viola scuro
            Color(red: 0.8, green: 0.4, blue: 0.0)   // Arancione scuro
        ])
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Seleziona Colore")
                .font(.headline)
            
            // Anteprima colore selezionato
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedColor)
                .frame(width: 100, height: 50)
                .shadow(radius: 2)
            
            // Colori predefiniti
            List {
                ForEach(presetColors, id: \.name) { category in
                    Section(header: Text(category.name)) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                            ForEach(category.colors, id: \.self) { color in
                                Button {
                                    selectedColor = color
                                } label: {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                                        )
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white, lineWidth: selectedColor == color ? 2 : 0)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                Section(header: Text("Personalizzato")) {
                    ColorPicker("Colore personalizzato", selection: $customColor)
                        .onChange(of: customColor) { newValue in
                            selectedColor = newValue
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