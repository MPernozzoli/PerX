import SwiftUI

struct SyncAgentSettingsView: View {
    @StateObject private var config = SyncAgentConfig.shared
    @StateObject private var syncService = ClaimSyncService.shared
    @ObservedObject private var googleAuth = AppState.shared.googleAuthService
    @State private var apiKey: String = SyncAgentConfig.shared.apiKey
    @State private var isCheckingHealth = false
    @State private var healthVersion: String?
    @State private var autoCheckTask: Task<Void, Never>?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("PerX Sync Agent")
                        .font(.headline)
                    
                    Spacer()
                    
                    // Indicatore stato
                    agentStatusBadge
                }

                Text("Configura il PerX Sync Agent.")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                HStack(spacing: 8) {
                    Text("Utente:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(currentUserIdDisplay)
                        .font(.caption)
                        .foregroundColor(currentUserIdDisplay.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                }

                TextField("URL Remoto (opzionale, es. https://perx.example.com:8000)", text: $config.remoteURL)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { _ in
                        persistAPIKey()
                        scheduleAutoCheckConnection()
                    }

                monitoringStatsView

                HStack {
                    Spacer()
                    Button {
                        testConnection()
                    } label: {
                        if isCheckingHealth {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Test connessione")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCheckingHealth)
                }
            }
            .padding()
        }
        .task { await initialSetup() }
        .onChange(of: config.remoteURL) { _ in
            normalizeRemoteURLIfNeeded()
            scheduleAutoCheckConnection()
        }
        .onChange(of: googleAuth.userEmail) { _ in
            // Se l'utente si disconnette, rimuovi anche l'utente dalla UI (e resetta la versione)
            if googleAuth.userEmail == nil {
                healthVersion = nil
            }
        }
    }
    
    @ViewBuilder
    private var agentStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(syncService.agentReachable ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(syncService.agentReachable ? "Online" : "Offline")
                .font(.caption)
                .foregroundColor(syncService.agentReachable ? .green : .red)
            
            if let version = healthVersion {
                Text("v\(version)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill((syncService.agentReachable ? Color.green : Color.red).opacity(0.1))
        )
    }

    // MARK: - Monitoring Stats

    private var monitoringStatsView: some View {
        // `statuses` è @Published → aggiornamento in tempo reale
        let monitoredCount = syncService.statuses.count
        let syncingCount = syncService.statuses.values.filter { $0.isActive }.count
        let suspendedCount = syncService.suspendedClaims.count
        let pendingDeletionCount = syncService.getPendingDeletions().count

        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Stato monitoraggio")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let last = syncService.lastBackgroundSync {
                        Text("Ultimo sync: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 14) {
                    statChip(title: "Monitorati", value: "\(monitoredCount)", color: .blue, systemImage: "eye")
                    statChip(title: "In sync", value: "\(syncingCount)", color: .orange, systemImage: "arrow.triangle.2.circlepath")
                    statChip(title: "Sospesi", value: "\(suspendedCount)", color: .orange.opacity(0.9), systemImage: "pause.circle")
                    statChip(title: "In scadenza", value: "\(pendingDeletionCount)", color: .secondary, systemImage: "clock")
                }
            }
            .padding(10)
        }
    }

    private func statChip(title: String, value: String, color: Color, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundColor(.primary)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.10))
        )
    }
    
    private func testConnection() {
        isCheckingHealth = true
        Task {
            let (reachable, response) = await SyncAgentAPIClient.shared.checkHealth()
            await MainActor.run {
                isCheckingHealth = false
                healthVersion = response?.version
                
                if reachable {
                    NotificationService.shared.sendNotification(
                        title: "Sync Agent",
                        body: "Agente raggiungibile" + (response?.version.map { " (v\($0))" } ?? "")
                    )
                } else {
                    NotificationService.shared.sendNotification(
                        title: "Sync Agent",
                        body: "Agente non raggiungibile"
                    )
                }
            }
            await syncService.refreshAgentStatus()
        }
    }
    
    // MARK: - Auto-check onChange
    
    private func initialSetup() async {
        migrateRemoteURLIfNeeded()
        normalizeRemoteURLIfNeeded()
        await syncService.refreshAgentStatus()
        scheduleAutoCheckConnection()
    }
    
    private func scheduleAutoCheckConnection() {
        autoCheckTask?.cancel()
        autoCheckTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000) // debounce ~450ms
            await performSilentHealthCheck()
        }
    }
    
    private func performSilentHealthCheck() async {
        await MainActor.run { isCheckingHealth = true }
        let (reachable, response) = await SyncAgentAPIClient.shared.checkHealth()
        await MainActor.run {
            isCheckingHealth = false
            healthVersion = response?.version
        }
        await syncService.refreshAgentStatus()
        
        // Se l'agent è offline e l'utente sta editando, non sparare notifiche: il badge basta.
        // Le notifiche le lasciamo al bottone "Test connessione".
        _ = reachable
    }
    
    private func persistAPIKey() {
        SyncAgentConfig.shared.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func normalizeRemoteURLIfNeeded() {
        let normalized = normalizedRemoteURLString(config.remoteURL)
        if normalized != config.remoteURL {
            config.remoteURL = normalized
        }
    }
    
    private func normalizedRemoteURLString(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        // Remoto: default HTTPS
        return "https://\(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }
    
    private func migrateRemoteURLIfNeeded() {
        let current = config.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // Migra IP vecchi o URL vuoti al default Tailscale
        if current.isEmpty ||
            current.contains("100.79.200.95") ||
            current.contains("10.0.0.197") ||
            current.hasPrefix("http://100.79.200.95") ||
            current.hasPrefix("http://10.0.0.197") {
            // Pulisci anche UserDefaults per evitare che venga ripristinato
            UserDefaults.standard.removeObject(forKey: "syncAgentRemoteURL")
            config.remoteURL = "https://perx-sync-agent.tailca58be.ts.net:8000"
        }
    }
    
    private var currentUserIdDisplay: String {
        guard let email = googleAuth.userEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty
        else { return "" }
        
        let localPart = email.lowercased().components(separatedBy: "@").first ?? email.lowercased()
        return localPart
    }
}

