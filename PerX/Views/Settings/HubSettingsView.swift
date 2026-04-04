import SwiftUI

/// Vista impostazioni Hub: stato per tutti; URL e impostazioni avanzate solo per admin.
struct HubSettingsView: View {
    @ObservedObject private var config = HubConfigService.shared
    @ObservedObject private var profileService = UserProfileService.shared
    @State private var showingURLEditor = false
    @State private var tempURL = ""
    @State private var tempTenantURL = ""
    @State private var cloudURL = HubConfigService.shared.cloudAPIBaseURL
    @State private var cloudEmail = HubConfigService.shared.cloudAPIEmail
    @State private var cloudPassword = ""
    @State private var cloudStatusMessage: String?
    @State private var isTestingCloud = false
    
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

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(config.isCloudAPIConfigured ? "Cloud API configurata" : "Cloud API non configurata", systemImage: config.isCloudAPIConfigured ? "checkmark.icloud.fill" : "icloud.slash")
                            .foregroundStyle(config.isCloudAPIConfigured ? .green : .secondary)
                        Spacer()
                        if isTestingCloud {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Testa login") {
                                Task { await testCloudLogin() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(cloudURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cloudEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cloudPassword.isEmpty)
                        }
                    }

                    if isAdmin {
                        TextField("URL Backend Cloud", text: $cloudURL)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: cloudURL) { _, newValue in
                                config.cloudAPIBaseURL = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            }

                        TextField("Email backend", text: $cloudEmail)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: cloudEmail) { _, newValue in
                                config.cloudAPIEmail = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            }

                        SecureField("Password backend", text: $cloudPassword)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("Salva credenziali") {
                                HubAPIAdapterClient.shared.saveCloudPassword(cloudPassword)
                                cloudStatusMessage = "Credenziali backend salvate"
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Pulisci sessione") {
                                HubAPIAdapterClient.shared.clearCloudSession()
                                cloudStatusMessage = "Sessione backend rimossa"
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Text(config.cloudAPIBaseURL.isEmpty ? "Backend cloud non impostato" : config.cloudAPIBaseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let cloudStatusMessage {
                        Text(cloudStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Solo admin: URL Hub modificabile
                if isAdmin {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("URL Hub di default")
                            Spacer()
                            Text(config.hubBaseURL.isEmpty ? "Non configurato" : config.hubBaseURL)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Button("Modifica") {
                                tempURL = config.hubBaseURL
                                tempTenantURL = config.tenantOverride()?.baseURL ?? ""
                                showingURLEditor = true
                            }
                            .buttonStyle(.bordered)
                        }
                        HStack {
                            Text("Override tenant \(config.currentTenantSlug)")
                            Spacer()
                            Text(config.tenantOverride()?.baseURL ?? "Usa hub di default")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Puoi usare un HUB condiviso per più tenant o definire un override dedicato per il tenant corrente.")
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
            URLEditorSheet(url: $tempURL, tenantURL: $tempTenantURL, tenantSlug: config.currentTenantSlug) { newURL, tenantOverride in
                config.hubBaseURL = newURL
                config.setTenantOverride(baseURL: tenantOverride, for: config.currentTenantSlug)
                config.startHealthCheckTimer()
            }
        }
    }

    private func testCloudLogin() async {
        isTestingCloud = true
        defer { isTestingCloud = false }
        config.cloudAPIBaseURL = cloudURL.trimmingCharacters(in: .whitespacesAndNewlines)
        config.cloudAPIEmail = cloudEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        HubAPIAdapterClient.shared.saveCloudPassword(cloudPassword)

        do {
            let token = try await HubAPIAdapterClient.shared.loginToCloud(forceRefresh: true)
            cloudStatusMessage = "Login backend riuscito (\(min(token.count, 12)) caratteri token)"
        } catch {
            cloudStatusMessage = "Login backend fallito: \(error.localizedDescription)"
        }
    }
}

// MARK: - URL Editor Sheet

private struct URLEditorSheet: View {
    @Binding var url: String
    @Binding var tenantURL: String
    let tenantSlug: String
    var onSave: (String, String) -> Void
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

            TextField("Override tenant \(tenantSlug)", text: $tenantURL)
                .textFieldStyle(.roundedBorder)
                .frame(width: 400)
            
            HStack {
                Button("Annulla") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Salva") {
                    onSave(
                        url.trimmingCharacters(in: .whitespacesAndNewlines),
                        tenantURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
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
