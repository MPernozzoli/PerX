import SwiftUI

struct HubStatusView: View {
    @ObservedObject var monitor: HubMonitor
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 16) {
                    // Services Section
                    servicesSection
                    
                    // Status Card
                    statusCard
                    
                    // Jobs Section
                    if !monitor.pendingJobs.isEmpty {
                        jobsSection
                    }
                    
                    // Stats Section
                    statsSection
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 320, height: 400)
        .sheet(isPresented: $showSettings) {
            SettingsView(monitor: monitor)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundColor(monitor.isOnline ? .green : .red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("PerX Hub")
                    .font(.headline)
                Text(monitor.isOnline ? "Online" : "Offline")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if monitor.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
            
            Button(action: { showSettings = true }) {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Services Section
    
    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "server.rack")
                Text("Servizi")
                    .font(.headline)
                Spacer()
                
                if monitor.connectedUsers > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                        Text("\(monitor.connectedUsers)")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(10)
                }
            }
            
            ForEach(monitor.services) { service in
                ServiceRow(
                    service: service,
                    hasUpdate: monitor.hasUpdate(for: service.id),
                    onRestart: {
                        Task {
                            _ = await monitor.restartService(service)
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await monitor.refresh()
                        }
                    },
                    onUpdate: {
                        Task {
                            // Per servizi locali: riavvia dopo ack
                            // Per sync agent: i file sono già stati sincronizzati
                            if let componentName = monitor.componentName(for: service.id) {
                                await monitor.acknowledgeUpdate(for: componentName)
                            }
                            // Riavvia il servizio per applicare l'aggiornamento
                            _ = await monitor.restartService(service)
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            await monitor.refresh()
                        }
                    }
                )
            }
            
            // Pulsante riavvia monitor
            Button(action: { monitor.restartMonitor() }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Riavvia Monitor")
                    Spacer()
                }
                .font(.caption)
                .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack {
                StatusIndicator(
                    icon: "circle.fill",
                    color: monitor.isOnline ? .green : .red,
                    title: "Stato",
                    value: monitor.isOnline ? "Attivo" : "Non raggiungibile"
                )
                
                Spacer()
                
                if let health = monitor.health {
                    StatusIndicator(
                        icon: "clock",
                        color: .blue,
                        title: "Uptime",
                        value: health.uptimeFormatted
                    )
                }
            }
            
            if let health = monitor.health {
                HStack {
                    StatusIndicator(
                        icon: "tag",
                        color: .purple,
                        title: "Versione",
                        value: health.version
                    )
                    
                    Spacer()
                    
                    if let lastCheck = monitor.lastCheck {
                        StatusIndicator(
                            icon: "arrow.clockwise",
                            color: .gray,
                            title: "Ultimo check",
                            value: lastCheck.formatted(date: .omitted, time: .shortened)
                        )
                    }
                }
            }
            
            if let error = monitor.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
    
    // MARK: - Jobs Section
    
    private var jobsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                Text("Job in coda")
                    .font(.headline)
                Spacer()
                Text("\(monitor.pendingJobs.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            ForEach(monitor.pendingJobs.prefix(5)) { job in
                JobRow(job: job)
            }
            
            if monitor.pendingJobs.count > 5 {
                Text("+ \(monitor.pendingJobs.count - 5) altri")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.bar")
                Text("Statistiche")
                    .font(.headline)
            }
            
            HStack(spacing: 16) {
                StatBox(
                    icon: "envelope",
                    title: "Email",
                    value: "\(monitor.emailStats?.todayProcessed ?? 0)",
                    subtitle: "oggi"
                )
                
                StatBox(
                    icon: "paperclip",
                    title: "Allegati",
                    value: "\(monitor.pendingAttachments)",
                    subtitle: "in attesa"
                )
                
                StatBox(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Job",
                    value: "\(monitor.pendingJobs.count)",
                    subtitle: "pending"
                )
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Button("Aggiorna") {
                Task {
                    await monitor.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            
            Spacer()
            
            Button("Esci") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Components

struct StatusIndicator: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
    }
}

struct JobRow: View {
    let job: JobInfo
    
    var body: some View {
        HStack {
            Image(systemName: job.typeIcon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(job.typeDisplayName)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(job.id.prefix(8) + "...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(job.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct StatBox: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }
}

struct ServiceRow: View {
    let service: ServiceStatus
    let hasUpdate: Bool
    let onRestart: () -> Void
    let onUpdate: () -> Void
    @State private var isRestarting = false
    @State private var isUpdating = false
    
    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(service.isOnline ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            // Service info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(service.name)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    if hasUpdate {
                        Text("UPDATE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .cornerRadius(3)
                    }
                }
                
                if let version = service.version {
                    Text("v\(version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if let error = service.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Uptime
            if let uptime = service.uptimeFormatted {
                Text(uptime)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Update button (se disponibile)
            if hasUpdate {
                Button(action: {
                    isUpdating = true
                    onUpdate()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        isUpdating = false
                    }
                }) {
                    if isUpdating {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)
                .help("Aggiorna \(service.name)")
            }
            
            // Restart button
            Button(action: {
                isRestarting = true
                onRestart()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    isRestarting = false
                }
            }) {
                if isRestarting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .disabled(isRestarting)
            .help("Riavvia \(service.name)")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var monitor: HubMonitor
    @Environment(\.dismiss) var dismiss
    
    @State private var hubURL: String = ""
    @State private var mailWorkerURL: String = ""
    @State private var waBridgeURL: String = ""
    @State private var syncAgentURL: String = ""
    @State private var autoUpdaterURL: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Impostazioni Hub Monitor")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                URLField(label: "PerX Hub", placeholder: "http://localhost:8080", text: $hubURL)
                URLField(label: "Mail Worker", placeholder: "http://localhost:5001", text: $mailWorkerURL)
                URLField(label: "WA Bridge", placeholder: "http://localhost:5002", text: $waBridgeURL)
                URLField(label: "SyncAgent Windows", placeholder: "http://192.168.x.x:8000", text: $syncAgentURL)
                URLField(label: "AutoUpdater", placeholder: "http://localhost:8084", text: $autoUpdaterURL)
            }
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Salva") {
                    monitor.hubURL = hubURL
                    monitor.mailWorkerURL = mailWorkerURL
                    monitor.waBridgeURL = waBridgeURL
                    monitor.syncAgentURL = syncAgentURL
                    monitor.autoUpdaterURL = autoUpdaterURL
                    Task {
                        await monitor.refresh()
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            hubURL = monitor.hubURL
            mailWorkerURL = monitor.mailWorkerURL
            waBridgeURL = monitor.waBridgeURL
            syncAgentURL = monitor.syncAgentURL
            autoUpdaterURL = monitor.autoUpdaterURL
        }
    }
}

struct URLField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
    }
}

#Preview {
    HubStatusView(monitor: HubMonitor())
}
