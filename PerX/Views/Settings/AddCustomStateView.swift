import SwiftUI
import Foundation

struct AddCustomStateView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var statoManager = StatoManager.shared
    
    @State private var descrizione = ""
    @State private var selectedIcon = "circle"
    @State private var selectedColor = Color.blue
    @State private var showingIconPicker = false
    @State private var showingColorPicker = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Nuovo Stato Personalizzato")
                .font(.headline)
            
            // Form
            Form {
                // Descrizione
                Section {
                    TextField("Descrizione stato", text: $descrizione)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Descrizione")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Icona
                Section {
                    HStack {
                        Image(systemName: selectedIcon)
                            .font(.title2)
                            .foregroundColor(selectedColor)
                            .frame(width: 30)
                        
                        Button("Scegli Icona") {
                            showingIconPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Text("Icona")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Colore
                Section {
                    HStack {
                        Circle()
                            .fill(selectedColor)
                            .frame(width: 20, height: 20)
                        
                        Button("Scegli Colore") {
                            showingColorPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Text("Colore")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            
            // Error message
            if showError {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            // Buttons
            HStack(spacing: 20) {
                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("Salva") {
                    saveState()
                }
                .keyboardShortcut(.return)
                .disabled(descrizione.isEmpty)
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 400)
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon)
        }
        .sheet(isPresented: $showingColorPicker) {
            ColorPickerView(selectedColor: $selectedColor)
        }
    }
    
    private func saveState() {
        // Validazione
        if descrizione.isEmpty {
            showError = true
            errorMessage = "La descrizione è obbligatoria"
            return
        }
        
        // Verifica che non esista già uno stato con la stessa descrizione
        if statoManager.allStates.contains(where: { $0.descrizione.lowercased() == descrizione.lowercased() }) {
            showError = true
            errorMessage = "Esiste già uno stato con questa descrizione"
            return
        }
        
        // Salva il nuovo stato
        statoManager.addCustomState(
            descrizione: descrizione,
            icon: selectedIcon,
            color: selectedColor
        )
        
        dismiss()
    }
}

#Preview {
    AddCustomStateView()
} 