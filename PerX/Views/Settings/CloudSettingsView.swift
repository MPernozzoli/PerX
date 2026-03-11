import SwiftUI

struct CloudSettingsView: View {
    @StateObject private var cloudSettings = CloudKitSettingsService.shared
    @StateObject private var cloudSync = CloudKitSyncService.shared
    @StateObject private var sinistriSync = CloudKitSinistroSyncService.shared
    @StateObject private var profileService = UserProfileService.shared
    @StateObject private var authService = GoogleAuthService.shared
    @State private var showErrorsPopover = false

    private let formattingOptions: [String] = ["default", "strict", "legacy"]
    private var isAdmin: Bool { profileService.isCurrentUserAdmin }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                // Stato sincronizzazione (tutti)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Sincronizzazione CloudKit:")
                                .font(.subheadline.weight(.medium))
                            Text(cloudSettings.isEnabled ? "Attiva" : "Disattiva")
                                .foregroundStyle(cloudSettings.isEnabled ? .green : .secondary)
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text("Stato: \(statusText)")
                                .font(.caption)
                                .foregroundStyle(statusColor)
                        }
                        if let last = cloudSync.lastSyncAt {
                            Text("Ultimo sync: \(last.formatted(date: .abbreviated, time: .standard))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Sincronizza ora") {
                        Task { await cloudSync.syncNow(reason: "manual_button") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!cloudSettings.isEnabled)
                }

                // Sinistri CK – pill e azione (tutti)
                HStack(spacing: 10) {
                    metricPill(
                        title: "Download",
                        value: sinistriSync.downloadsInProgress > 0 ? "In corso (\(sinistriSync.downloadsInProgress))" : "Idle",
                        isActive: sinistriSync.downloadsInProgress > 0
                    )
                    metricPill(
                        title: "Upload",
                        value: sinistriSync.uploadsInProgress > 0 ? "In corso (\(sinistriSync.uploadsInProgress))" : "Idle",
                        isActive: sinistriSync.uploadsInProgress > 0
                    )
                    metricPill(
                        title: "Coda locale",
                        value: "\(sinistriSync.pendingChanges)",
                        isActive: sinistriSync.pendingChanges > 0
                    )
                    Spacer()
                    Button("Sync sinistri ora") {
                        Task { await sinistriSync.syncNow(reason: "cloud_settings") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!cloudSettings.isEnabled)
                }

                if !sinistriSync.errors.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            showErrorsPopover = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text("Errori (\(sinistriSync.errors.count))")
                                    .font(.caption)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showErrorsPopover) {
                            errorsPopoverContent
                        }
                        Button("Pulisci") {
                            sinistriSync.clearErrors()
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                }

                // Impostazioni avanzate (solo admin)
                if isAdmin {
                    Divider()
                    Text("Impostazioni avanzate (condivise)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Toggle("Abilita sincronizzazione CloudKit", isOn: $cloudSettings.isEnabled)

                    HStack(spacing: 12) {
                        Text("Frequenza sync")
                            .frame(width: 140, alignment: .leading)
                        Slider(value: $cloudSettings.syncFrequencySeconds, in: 5...180, step: 5)
                        Text("\(Int(cloudSettings.syncFrequencySeconds))s")
                            .frame(width: 50, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(!cloudSettings.isEnabled)

                    HStack(spacing: 12) {
                        Text("Formattazione dati")
                            .frame(width: 140, alignment: .leading)
                        Picker("", selection: $cloudSettings.dataFormatting) {
                            ForEach(formattingOptions, id: \.self) { opt in
                                Text(opt).tag(opt)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .disabled(!cloudSettings.isEnabled)

                    Toggle("Log debug CloudKit", isOn: $cloudSettings.debugLoggingEnabled)
                        .disabled(!cloudSettings.isEnabled)

                    Divider()

                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow {
                            metricLabel("Ultimo pull minimal")
                            metricValue("\(sinistriSync.lastMinimalSyncCount)")
                            metricLabel("Totale minimal processati")
                            metricValue("\(sinistriSync.totalMinimalProcessed)")
                        }
                        GridRow {
                            metricLabel("Upload minimal")
                            metricValue("\(sinistriSync.totalMinimalUploaded)")
                            metricLabel("Upload full")
                            metricValue("\(sinistriSync.totalFullUploaded)")
                        }
                        GridRow {
                            metricLabel("Ultimo batch full (owned)")
                            metricValue("\(sinistriSync.lastOwnedFullUploadCount)")
                            metricLabel("Ultimo sync")
                            metricValue(sinistriSync.lastSyncAt.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .medium) } ?? "—")
                        }
                    }
                }
            }
            .padding()
            .onAppear {
                cloudSync.startIfEnabled(email: authService.userEmail)
            }
            .onChange(of: authService.userEmail) { _, newValue in
                cloudSync.configureCurrentUser(email: newValue)
            }
        } label: {
            Label("CloudKit", systemImage: "cloud")
                .font(.headline)
        }
    }

    private var statusText: String {
        switch cloudSync.status {
        case .idle: return "idle"
        case .ready: return "ready"
        case .syncing(let why): return "syncing (\(why))"
        case .unavailable(let msg): return "unavailable (\(msg))"
        case .error(let msg): return "error (\(msg))"
        }
    }

    private var statusColor: Color {
        switch cloudSync.status {
        case .idle: return .secondary
        case .ready: return .green
        case .syncing: return .blue
        case .unavailable: return .orange
        case .error: return .red
        }
    }

    private func metricPill(title: String, value: String, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(isActive ? .blue : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((isActive ? Color.blue : Color.secondary).opacity(0.08))
        )
    }

    private func metricLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func metricValue(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .monospacedDigit()
    }

    private var errorsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Errori CloudKit Sinistri")
                    .font(.headline)
                Spacer()
                Button {
                    copyAllErrors()
                } label: {
                    Label("Copia tutti", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sinistriSync.errors.reversed()) { error in
                        errorRow(error)
                    }
                }
                .padding()
            }
            .frame(width: 600, height: 400)
        }
    }

    private func errorRow(_ error: CloudKitSinistroSyncService.SyncError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(error.type.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                Spacer()
                Text(error.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    copyError(error)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Copia errore")
            }
            Text(error.message)
                .font(.caption)
                .foregroundStyle(.primary)
            if let details = error.details, !details.isEmpty {
                Text("Dettagli: \(details)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let context = error.context, !context.isEmpty {
                Text("Contesto: \(context)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.05))
        )
    }

    private func copyError(_ error: CloudKitSinistroSyncService.SyncError) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(error.fullDescription, forType: .string)
    }

    private func copyAllErrors() {
        let allText = sinistriSync.errors.reversed().map { $0.fullDescription }.joined(separator: "\n\n---\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allText, forType: .string)
    }
}
