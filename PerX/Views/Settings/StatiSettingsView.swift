import SwiftUI

struct StatiSettingsView: View {
    @StateObject private var statoManager = StatoManager.shared
    @State private var showingAddState = false
    @State private var selectedState: StatoManager.StatoSinistro?
    @State private var selectedCustomState: StatoManager.CustomState?
    @State private var showingIconPicker = false
    @State private var showingColorPicker = false
    @State private var tempIcon = ""
    @State private var tempColor = Color.gray
    
    var body: some View {
        VStack(spacing: 24) {
            headerView
            statiListView
        }
        .padding()
        .sheet(isPresented: $showingAddState) {
            AddCustomStateView()
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedIcon: $tempIcon)
                .onDisappear {
                    updateIcon()
                }
        }
        .sheet(isPresented: $showingColorPicker) {
            ColorPickerView(selectedColor: $tempColor)
                .onDisappear {
                    updateColor()
                }
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("Gestione Stati")
                .font(.headline)
            Spacer()
            Button("Aggiungi Stato") {
                showingAddState = true
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var statiListView: some View {
        GroupBox {
            VStack(spacing: 16) {
                ScrollView {
                    VStack(spacing: 12) {
                        visibleStatesSection
                        if !statoManager.availableCustomStates.isEmpty {
                            Divider()
                            customStatesSection
                        }
                        Divider()
                        systemStatesSection
                    }
                }
            }
            .padding()
        }
    }
    
    private var visibleStatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stati di Default")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ForEach(StatoManager.StatoSinistro.allCases.filter { !$0.isSystem }) { stato in
                StatoRowView(
                    stato: stato,
                    onIconTap: {
                        selectedState = stato
                        tempIcon = stato.icon
                        showingIconPicker = true
                    },
                    onColorTap: {
                        selectedState = stato
                        tempColor = stato.color
                        showingColorPicker = true
                    }
                )
            }
        }
    }
    
    private var customStatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stati Personalizzati")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ForEach(statoManager.availableCustomStates) { stato in
                StatoRowView(
                    id: stato.id,
                    descrizione: stato.descrizione,
                    icon: stato.icon,
                    color: Color(hex: stato.color) ?? .gray,
                    isSystem: false,
                    onIconTap: {
                        selectedCustomState = stato
                        tempIcon = stato.icon
                        showingIconPicker = true
                    },
                    onColorTap: {
                        selectedCustomState = stato
                        tempColor = Color(hex: stato.color) ?? .gray
                        showingColorPicker = true
                    },
                    onDeactivate: {
                        statoManager.deactivateCustomState(stato.id)
                    }
                )
            }
        }
    }
    
    private var systemStatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stati di Sistema")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ForEach(StatoManager.StatoSinistro.allCases.filter { $0.isSystem }) { stato in
                StatoRowView(
                    stato: stato,
                    onIconTap: {
                        selectedState = stato
                        tempIcon = stato.icon
                        showingIconPicker = true
                    },
                    onColorTap: {
                        selectedState = stato
                        tempColor = stato.color
                        showingColorPicker = true
                    }
                )
            }
        }
    }
    
    private func updateIcon() {
        if let stato = selectedState {
            statoManager.updateStateIcon(for: stato, newIcon: tempIcon)
        } else if let stato = selectedCustomState {
            statoManager.updateCustomStateIcon(stato.id, newIcon: tempIcon)
        }
    }
    
    private func updateColor() {
        if let stato = selectedState {
            statoManager.updateStateColor(for: stato, newColor: tempColor)
        } else if let stato = selectedCustomState {
            statoManager.updateCustomStateColor(stato.id, newColor: tempColor)
        }
    }
}

struct StatoRowView: View {
    let id: String
    let descrizione: String
    let icon: String
    let color: Color
    let isSystem: Bool
    let isCustom: Bool
    let onIconTap: () -> Void
    let onColorTap: () -> Void
    let onDeactivate: (() -> Void)?
    
    // Inizializzatore per stati di sistema
    init(stato: StatoManager.StatoSinistro, onIconTap: @escaping () -> Void, onColorTap: @escaping () -> Void) {
        self.id = stato.id
        self.descrizione = stato.descrizione
        self.icon = stato.icon
        self.color = stato.color
        self.isSystem = stato.isSystem
        self.isCustom = false
        self.onIconTap = onIconTap
        self.onColorTap = onColorTap
        self.onDeactivate = nil
    }
    
    // Inizializzatore per stati personalizzati
    init(id: String, descrizione: String, icon: String, color: Color, isSystem: Bool, onIconTap: @escaping () -> Void, onColorTap: @escaping () -> Void, onDeactivate: @escaping () -> Void) {
        self.id = id
        self.descrizione = descrizione
        self.icon = icon
        self.color = color
        self.isSystem = isSystem
        self.isCustom = true
        self.onIconTap = onIconTap
        self.onColorTap = onColorTap
        self.onDeactivate = onDeactivate
    }
    
    var body: some View {
        HStack {
            Text(id)
                .frame(width: 80, alignment: .leading)
                .font(.system(.body, design: .monospaced))
            
            Text(descrizione)
                .frame(width: 150, alignment: .leading)
            
            Button(action: onIconTap) {
                HStack {
                    Image(systemName: icon)
                    if !isSystem {
                        Text("Modifica")
                            .font(.caption)
                    }
                }
            }
            .frame(width: 100, alignment: .leading)
            .buttonStyle(.borderless)
            .disabled(isSystem)
            
            Button(action: onColorTap) {
                HStack {
                    Circle()
                        .fill(color)
                        .frame(width: 16, height: 16)
                    if !isSystem {
                        Text("Modifica")
                            .font(.caption)
                    }
                }
            }
            .frame(width: 100, alignment: .leading)
            .buttonStyle(.borderless)
            .disabled(isSystem)
            
            if isCustom {
                Button(action: { onDeactivate?() }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Disattiva stato")
            }
        }
        .padding(.vertical, 4)
    }
} 