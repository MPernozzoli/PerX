import SwiftUI

/// Vista impostazioni Hub centralizzato
struct HubSettingsView: View {
    @ObservedObject private var config = HubConfigService.shared
    @State private var showingURLEditor = false
    @State private var tempURL = ""
    
    var body: some View {
        Form {
            // MARK: - Stato Hub
            Section {
                HStack {
                    Label("Stato Hub", systemImage: config.isHubReachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(config.isHubReachable ? .green : .red)
                    
                    Spacer()
                    
                    Text(config.hubStatusDescription)
                        .foregroundColor(.secondary)
                    
                    Button {
                        Task {
                            await config.checkHubHealth()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
                
                HStack {
                    Text("URL Hub")
                    Spacer()
                    Text(config.hubBaseURL.isEmpty ? "Non configurato" : config.hubBaseURL)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Button("Modifica") {
                        tempURL = config.hubBaseURL
                        showingURLEditor = true
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                
                if let lastCheck = config.lastHealthCheck {
                    HStack {
                        Text("Ultimo controllo")
                        Spacer()
                        Text(lastCheck, style: .relative)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Connessione Hub")
            } footer: {
                Text("L'Hub centralizzato gestisce file, email e WhatsApp per tutti i dispositivi. Configurare l'URL prima di attivare la gestione cloud.")
            }
            
            // MARK: - Modalità Gestione
            Section {
                // File
                HStack {
                    Label("Gestione File", systemImage: "folder")
                    Spacer()
                    Picker("", selection: $config.fileManagementMode) {
                        ForEach(ManagementMode.allCases, id: \.self) { mode in
                            Label(mode.displayName, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .disabled(!config.isHubReady && config.fileManagementMode == .local)
                }
                
                // Email
                HStack {
                    Label("Gestione Email", systemImage: "envelope")
                    Spacer()
                    Picker("", selection: $config.emailManagementMode) {
                        ForEach(ManagementMode.allCases, id: \.self) { mode in
                            Label(mode.displayName, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .disabled(!config.isHubReady && config.emailManagementMode == .local)
                }
                
                // WhatsApp (solo Hub)
                HStack {
                    Label("Gestione WhatsApp", systemImage: "message")
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "cloud.fill")
                            .foregroundColor(.accentColor)
                        Text("Solo Hub")
                            .foregroundColor(.secondary)
                    }
                }
                .help("WhatsApp funziona esclusivamente tramite Hub")
                
            } header: {
                Text("Modalità Gestione")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("**Locale**: elaborazione sul dispositivo (comportamento attuale)")
                    Text("**Cloud (Hub)**: elaborazione centralizzata, dati sincronizzati via Hub")
                    if !config.isHubReady {
                        Text("Configura e verifica la connessione all'Hub per attivare la modalità Cloud.")
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // MARK: - Info
            if config.isUsingHub {
                Section {
                    if config.fileManagementMode == .cloud {
                        Label("File gestiti dal Vault su Hub", systemImage: "checkmark")
                            .foregroundColor(.green)
                    }
                    if config.emailManagementMode == .cloud {
                        Label("Email elaborate dall'Hub", systemImage: "checkmark")
                            .foregroundColor(.green)
                    }
                    if config.whatsappManagementMode == .cloud {
                        Label("WhatsApp gestito dall'Hub", systemImage: "checkmark")
                            .foregroundColor(.green)
                    }
                } header: {
                    Text("Funzionalità Cloud Attive")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Hub Centralizzato")
        .sheet(isPresented: $showingURLEditor) {
            URLEditorSheet(url: $tempURL) { newURL in
                config.hubBaseURL = newURL
                config.startHealthCheckTimer()
            }
        }
    }
}

// MARK: - URL Editor Sheet

private struct URLEditorSheet: View {
    @Binding var url: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Configura URL Hub")
                .font(.headline)
            
            Text("Inserisci l'URL dell'Hub centralizzato (es. http://mac-mini.tailnet:8080)")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            TextField("URL Hub", text: $url)
                .textFieldStyle(.roundedBorder)
                .frame(width: 400)
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Salva") {
                    onSave(url.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(30)
        .frame(width: 500)
    }
}

#Preview {
    HubSettingsView()
}
