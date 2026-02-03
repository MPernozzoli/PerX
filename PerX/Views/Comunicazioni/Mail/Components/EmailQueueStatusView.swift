import SwiftUI

/// Vista compatta per mostrare lo stato della coda email
/// Da integrare nella toolbar o sidebar
struct EmailQueueStatusView: View {
    
    @StateObject private var queueService = EmailQueueService.shared
    @State private var showDetails = false
    
    var body: some View {
        if queueService.queueStats.pending > 0 || queueService.isProcessing {
            Button(action: { showDetails.toggle() }) {
                HStack(spacing: 6) {
                    // Indicatore animato
                    if queueService.isProcessing && !queueService.isPaused {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else if queueService.isPaused {
                        Image(systemName: "pause.circle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                    } else {
                        Image(systemName: "envelope.badge")
                            .foregroundColor(.blue)
                            .font(.system(size: 12))
                    }
                    
                    // Conteggio
                    Text("\(queueService.queueStats.pending)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                    
                    // Progress mini
                    if queueService.queueStats.total > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.2))
                                
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.green)
                                    .frame(width: geo.size.width * queueService.queueStats.progress)
                            }
                        }
                        .frame(width: 30, height: 4)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.controlBackgroundColor))
                )
            }
            .buttonStyle(.plain)
            .help("Coda email: \(queueService.queueStats.pending) in attesa")
            .popover(isPresented: $showDetails) {
                EmailQueueDetailView()
            }
        }
    }
}

/// Vista dettagliata della coda email
struct EmailQueueDetailView: View {
    
    @StateObject private var queueService = EmailQueueService.shared
    @State private var showSettings = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coda Email")
                        .font(.headline)
                    
                    if queueService.isProcessing {
                        Text(queueService.isPaused ? "In pausa" : "In elaborazione...")
                            .font(.caption)
                            .foregroundColor(queueService.isPaused ? .orange : .green)
                    }
                }
                
                Spacer()
                
                // Controlli
                HStack(spacing: 8) {
                    if queueService.isProcessing {
                        if queueService.isPaused {
                            Button(action: { queueService.resumeProcessing() }) {
                                Image(systemName: "play.fill")
                            }
                            .help("Riprendi")
                        } else {
                            Button(action: { queueService.pauseProcessing() }) {
                                Image(systemName: "pause.fill")
                            }
                            .help("Pausa")
                        }
                        
                        Button(action: { queueService.stopProcessing() }) {
                            Image(systemName: "stop.fill")
                        }
                        .foregroundColor(.red)
                        .help("Ferma")
                    } else if queueService.queueStats.pending > 0 {
                        Button(action: {
                            Task { await queueService.startProcessing() }
                        }) {
                            Image(systemName: "play.fill")
                        }
                        .help("Avvia")
                    }
                    
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gear")
                    }
                    .help("Impostazioni")
                }
                .buttonStyle(.borderless)
            }
            
            Divider()
            
            // Statistiche
            VStack(spacing: 12) {
                // Progress bar grande
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .green],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * queueService.queueStats.progress)
                        }
                    }
                    .frame(height: 8)
                    
                    HStack {
                        Text("\(Int(queueService.queueStats.progress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if let eta = queueService.estimatedTimeRemaining {
                            Text("~\(formatDuration(eta)) rimanenti")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Stats grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    statCell(
                        value: queueService.queueStats.pending,
                        label: "In coda",
                        color: .blue
                    )
                    statCell(
                        value: queueService.queueStats.processing,
                        label: "Attive",
                        color: .orange
                    )
                    statCell(
                        value: queueService.queueStats.completed,
                        label: "Complete",
                        color: .green
                    )
                    statCell(
                        value: queueService.queueStats.failed,
                        label: "Fallite",
                        color: .red
                    )
                }
                
                // Metriche
                if queueService.queueStats.processedPerMinute > 0 {
                    HStack {
                        Label(
                            "\(String(format: "%.1f", queueService.queueStats.processedPerMinute))/min",
                            systemImage: "speedometer"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if queueService.queueStats.averageProcessingTime > 0 {
                            Label(
                                "\(String(format: "%.1f", queueService.queueStats.averageProcessingTime))s/email",
                                systemImage: "clock"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Email corrente
                if let current = queueService.currentEmail {
                    HStack {
                        Image(systemName: "envelope.open")
                            .foregroundColor(.blue)
                            .font(.caption)
                        
                        Text(current)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                }
            }
            
            // Azioni
            if queueService.queueStats.failed > 0 {
                Divider()
                
                Button(action: {
                    Task { await queueService.retryAllFailed() }
                }) {
                    Label("Riprova \(queueService.queueStats.failed) fallite", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.orange)
            }
        }
        .padding()
        .frame(width: 320)
        .sheet(isPresented: $showSettings) {
            EmailQueueSettingsView()
        }
    }
    
    @ViewBuilder
    private func statCell(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(color)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))min"
        } else {
            let hours = Int(seconds / 3600)
            let mins = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(mins)min"
        }
    }
}

/// Vista impostazioni coda
struct EmailQueueSettingsView: View {
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var queueService = EmailQueueService.shared
    
    @State private var batchSize: Double = 3
    @State private var batchDelay: Double = 2.0
    @State private var emailDelay: Double = 0.5
    @State private var maxRetries: Double = 3
    @State private var enableCPUThrottling = true
    @State private var maxCPUUsage: Double = 0.3
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Impostazioni Coda")
                .font(.headline)
            
            Form {
                Section("Processamento") {
                    HStack {
                        Text("Email per batch")
                        Spacer()
                        Slider(value: $batchSize, in: 1...10, step: 1)
                            .frame(width: 120)
                        Text("\(Int(batchSize))")
                            .frame(width: 30)
                    }
                    
                    HStack {
                        Text("Pausa tra batch (s)")
                        Spacer()
                        Slider(value: $batchDelay, in: 0.5...10, step: 0.5)
                            .frame(width: 120)
                        Text(String(format: "%.1f", batchDelay))
                            .frame(width: 30)
                    }
                    
                    HStack {
                        Text("Pausa tra email (s)")
                        Spacer()
                        Slider(value: $emailDelay, in: 0.1...2, step: 0.1)
                            .frame(width: 120)
                        Text(String(format: "%.1f", emailDelay))
                            .frame(width: 30)
                    }
                }
                
                Section("Retry") {
                    HStack {
                        Text("Max tentativi")
                        Spacer()
                        Slider(value: $maxRetries, in: 1...5, step: 1)
                            .frame(width: 120)
                        Text("\(Int(maxRetries))")
                            .frame(width: 30)
                    }
                }
                
                Section("CPU") {
                    Toggle("Throttling automatico", isOn: $enableCPUThrottling)
                    
                    if enableCPUThrottling {
                        HStack {
                            Text("Target CPU max")
                            Spacer()
                            Slider(value: $maxCPUUsage, in: 0.1...0.8, step: 0.1)
                                .frame(width: 120)
                            Text("\(Int(maxCPUUsage * 100))%")
                                .frame(width: 40)
                        }
                    }
                }
                
                Section {
                    Button("Pulisci completate (>7gg)") {
                        Task {
                            await queueService.cleanupCompleted(olderThan: 7)
                        }
                    }
                    
                    Button("Svuota coda", role: .destructive) {
                        Task {
                            await queueService.clearQueue()
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Applica") {
                    applySettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 450)
    }
    
    private func applySettings() {
        var config = EmailQueueService.ProcessingConfig()
        config.batchSize = Int(batchSize)
        config.batchDelay = batchDelay
        config.emailDelay = emailDelay
        config.maxRetries = Int(maxRetries)
        config.enableCPUThrottling = enableCPUThrottling
        config.maxCPUUsage = maxCPUUsage
        
        queueService.updateConfig(config)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        EmailQueueStatusView()
        EmailQueueDetailView()
    }
    .padding()
}
