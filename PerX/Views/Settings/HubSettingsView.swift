import SwiftUI

/// Vista impostazioni Hub: stato per tutti; URL e impostazioni avanzate solo per admin.
struct HubSettingsView: View {
    @ObservedObject private var config = HubConfigService.shared
    @ObservedObject private var profileService = UserProfileService.shared
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
                            .disabled(cloudEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cloudPassword.isEmpty)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Endpoint backend")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(config.cloudAPIBaseURL)
                            .textSelection(.enabled)
                    }

                    if isAdmin {
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
                    }

                    if let cloudStatusMessage {
                        Text(cloudStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hub legacy")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(config.hubBaseURL.isEmpty ? "Non configurato" : config.hubBaseURL)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let override = config.tenantOverride()?.baseURL, !override.isEmpty {
                        Text("Override tenant \(config.currentTenantSlug): \(override)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
                Text("La modifica manuale degli endpoint e stata disabilitata in UI.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        } label: {
            Label("Hub", systemImage: "server.rack")
                .font(.headline)
        }
    }

    private func testCloudLogin() async {
        isTestingCloud = true
        defer { isTestingCloud = false }
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

#Preview {
    HubSettingsView()
}
