import SwiftUI

/// Vista impostazioni Hub: stato per tutti; URL e impostazioni avanzate solo per admin.
struct HubSettingsView: View {
    @ObservedObject private var config = HubConfigService.shared
    @ObservedObject private var profileService = UserProfileService.shared
    @State private var showingURLEditor = false
    @State private var tempURL = ""
    
    private var isAdmin: Bool { profileService.isCurrentUserAdmin }
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                // Stato Hub (tutti)
                HStack {
                    Label(config.isHubReachable ? "Hub online" : "Hub offline", systemImage: config.isHubReachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(config.isHubReachable ? .green : .red)
                    Spacer()
                    Text(config.hubStatusDescription)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await config.checkHubHealth() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
                
                if let lastCheck = config.lastHealthCheck {
                    HStack {
                        Text("Ultimo controllo")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lastCheck, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                
                // Solo admin: URL Hub modificabile
                if isAdmin {
                    Divider()
                    HStack {
                        Text("URL Hub")
                        Spacer()
                        Text(config.hubBaseURL.isEmpty ? "Non configurato" : config.hubBaseURL)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Modifica") {
                            tempURL = config.hubBaseURL
                            showingURLEditor = true
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("Impostazioni condivise da tutti gli utenti.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if !config.hubBaseURL.isEmpty {
                    HStack {
                        Text("URL Hub")
                        Spacer()
                        Text(config.hubBaseURL)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .padding()
        } label: {
            Label("Hub", systemImage: "server.rack")
                .font(.headline)
        }
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
            
            Text("URL dell'Hub centralizzato (es. http://mac-mini.tailnet:8080). Le impostazioni sono condivise da tutti.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            TextField("URL Hub", text: $url)
                .textFieldStyle(.roundedBorder)
                .frame(width: 400)
            
            HStack {
                Button("Annulla") { dismiss() }
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
