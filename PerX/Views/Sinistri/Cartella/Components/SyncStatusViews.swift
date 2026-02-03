import SwiftUI

// MARK: - Sync Status Views

struct SyncStatusView: View {
    let status: ClaimSyncStatus
    var showCompact: Bool = true

    var body: some View {
        if showCompact {
            compactView
        } else {
            fullView
        }
    }
    
    @ViewBuilder
    private var compactView: some View {
        switch status {
        case .notDownloaded:
            Label("Non scaricata", systemImage: "icloud.slash")
                .foregroundColor(.secondary)
                .font(.caption)
        case .notSynced:
            Label("Non sincronizzata", systemImage: "icloud.slash")
                .foregroundColor(.orange)
                .font(.caption)
        case .registering:
            HStack(spacing: 6) {
                SyncProgressCircle(progress: nil, color: .blue)
                Text("Connessione...")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        case .fetchingMetadata:
            HStack(spacing: 6) {
                SyncProgressCircle(progress: nil, color: .blue)
                Text("Richiesta dati...")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        case .comparing:
            HStack(spacing: 6) {
                SyncProgressCircle(progress: nil, color: .blue)
                Text("Analisi...")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        case .downloading(let info):
            HStack(spacing: 6) {
                SyncProgressCircle(progress: info.overallProgress, color: .blue)
                Text("\(Int(info.overallProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        case .downloadingFile(_, let current, let total):
            HStack(spacing: 6) {
                SyncProgressCircle(progress: total > 0 ? Double(current) / Double(total) : nil, color: .blue)
                Text("Scarico \(current)/\(total)")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        case .extracting(let progress):
            HStack(spacing: 6) {
                SyncProgressCircle(progress: progress, color: .blue)
                Text("Estrazione \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        case .uploading(let progress):
            HStack(spacing: 6) {
                SyncProgressCircle(progress: progress, color: .orange)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        case .uploadingFile(_, let current, let total):
            HStack(spacing: 6) {
                SyncProgressCircle(progress: total > 0 ? Double(current) / Double(total) : nil, color: .orange)
                Text("Invio \(current)/\(total)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        case .upToDate:
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Sincronizzata")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.caption)
        }
    }
    
    @ViewBuilder
    private var fullView: some View {
        switch status {
        case .notDownloaded:
            statusRow(icon: "icloud.slash", text: "Cartella non presente", color: .secondary)
        case .notSynced:
            statusRow(icon: "arrow.triangle.2.circlepath", text: "Da sincronizzare", color: .orange)
        case .registering:
            statusRow(icon: "antenna.radiowaves.left.and.right", text: "Contatto il server...", color: .blue, animated: true)
        case .fetchingMetadata:
            statusRow(icon: "doc.text.magnifyingglass", text: "Richiedo i dati del sinistro...", color: .blue, animated: true)
        case .comparing:
            statusRow(icon: "list.bullet.clipboard", text: "Analizzo i file...", color: .blue, animated: true)
        case .downloading(let info):
            downloadProgressRow(progress: info.overallProgress, text: "Scarico la cartella...")
        case .downloadingFile(let name, let current, let total):
            let progress = total > 0 ? Double(current) / Double(total) : 0
            downloadProgressRow(progress: progress, text: "Scarico i file (\(current)/\(total))", detail: shortFileName(name))
        case .extracting(let progress):
            downloadProgressRow(progress: progress, text: "Estrazione file...")
        case .uploading(let progress):
            uploadProgressRow(progress: progress, text: "Invio le modifiche...")
        case .uploadingFile(let name, let current, let total):
            let progress = total > 0 ? Double(current) / Double(total) : 0
            uploadProgressRow(progress: progress, text: "Invio i file (\(current)/\(total))", detail: shortFileName(name))
        case .upToDate:
            statusRow(icon: "checkmark.circle.fill", text: "Cartella sincronizzata", color: .green)
        case .error(let message):
            statusRow(icon: "exclamationmark.triangle.fill", text: message, color: .red)
        }
    }
    
    private func statusRow(icon: String, text: String, color: Color, animated: Bool = false) -> some View {
        HStack(spacing: 12) {
            if animated {
                SyncProgressCircle(progress: nil, color: color)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 24, height: 24)
            }
            Text(text)
                .font(.subheadline)
                .foregroundColor(color)
        }
    }
    
    private func downloadProgressRow(progress: Double, text: String, detail: String? = nil) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                SyncProgressCircle(progress: progress, color: .blue)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    if let detail = detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.blue)
            }
            ProgressView(value: progress)
                .tint(.blue)
        }
    }
    
    private func uploadProgressRow(progress: Double, text: String, detail: String? = nil) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                SyncProgressCircle(progress: progress, color: .orange)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text)
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    if let detail = detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.orange)
            }
            ProgressView(value: progress)
                .tint(.orange)
        }
    }
    
    private func shortFileName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

struct SyncProgressCircle: View {
    let progress: Double?
    let color: Color
    
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 2)
            
            if let progress = progress {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            }
        }
    }
}

// MARK: - Sync Indicator (per toolbar CartellaView)

/// Indicatore sync compatto per la toolbar con menu contestuale
struct SyncIndicatorView: View {
    let sinistro: Sinistro
    let status: ClaimSyncStatus
    let isSuspended: Bool
    let agentReachable: Bool
    let onForceSync: () -> Void
    let onSuspendSync: () -> Void
    let onResumeSync: () -> Void
    let onStopAndRemove: () -> Void
    
    @State private var lastStatus: ClaimSyncStatus?
    @State private var lastSummaryText: String?
    @State private var summaryTask: Task<Void, Never>?
    
    private var isSyncing: Bool {
        status.isActive
    }
    
    private var isDownloading: Bool {
        switch status {
        case .registering, .fetchingMetadata, .comparing, .downloading, .downloadingFile, .extracting:
            return true
        default:
            return false
        }
    }
    
    private var isUploading: Bool {
        switch status {
        case .uploading, .uploadingFile:
            return true
        default:
            return false
        }
    }
    
    private var isError: Bool {
        if case .error = status { return true }
        return false
    }
    
    private var errorMessage: String? {
        if case .error(let message) = status {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
    
    private var currentProgress: Double? {
        switch status {
        case .downloading(let info): return info.overallProgress
        case .downloadingFile(_, let c, let t): return t > 0 ? Double(c) / Double(t) : nil
        case .extracting(let p): return p
        case .uploading(let p): return p
        case .uploadingFile(_, let c, let t): return t > 0 ? Double(c) / Double(t) : nil
        default: return nil
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Icona/Indicatore
            ZStack {
                if isSyncing {
                    // Anello di progresso
                    SyncProgressCircle(progress: currentProgress, color: isUploading ? .orange : .blue)
                        .frame(width: 16, height: 16)
                } else if isSuspended {
                    Image(systemName: "pause.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if isError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if case .upToDate = status {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(agentReachable ? .secondary : .orange)
                }
            }
            
            // Testo stato
            if isSyncing {
                Text(syncText)
                    .font(.caption)
                    .foregroundColor(isUploading ? .orange : .blue)
            } else if let summary = lastSummaryText {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if isSuspended {
                // Distingui tra sospeso manualmente e chiuso (solo upload)
                let isClosed = sinistro.stato == StatoManager.StatoSinistro.chiusa.descrizione
                Text(isClosed ? "Solo upload" : "Sospesa")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .contextMenu {
            if isSyncing {
                // Durante sync attivo
                Button(role: .destructive) {
                    onSuspendSync()
                } label: {
                    Label("Sospendi sincronizzazione", systemImage: "pause.circle")
                }
                
                // Info velocità e progresso durante download
                if isDownloading, case .downloading(let info) = status {
                    Divider()
                    
                    Label("Velocità: \(info.speedFormatted)", systemImage: "speedometer")
                        .foregroundColor(.secondary)
                    
                    Label("\(info.downloadedFormatted) di \(info.totalFormatted)", systemImage: "arrow.down.circle")
                        .foregroundColor(.secondary)
                }
            } else if isSuspended {
                // Sync sospesa - distingui tra chiuso e sospeso manualmente
                let isClosed = sinistro.stato == StatoManager.StatoSinistro.chiusa.descrizione
                
                if !isClosed {
                    // Solo per sinistri sospesi manualmente, permettere di riattivare
                    Button {
                        onResumeSync()
                    } label: {
                        Label("Attiva sincronizzazione", systemImage: "play.circle")
                    }
                    
                    Divider()
                }
                
                Button(role: .destructive) {
                    onStopAndRemove()
                } label: {
                    Label("Rimuovi cartella locale", systemImage: "trash")
                }
            } else {
                // Sync normale
                Button {
                    onForceSync()
                } label: {
                    Label("Sincronizza adesso", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!agentReachable)
                
                Divider()
                
                Button {
                    onSuspendSync()
                } label: {
                    Label("Sospendi sincronizzazione", systemImage: "pause.circle")
                }
                
                Button(role: .destructive) {
                    onStopAndRemove()
                } label: {
                    Label("Interrompi e rimuovi cartella", systemImage: "trash")
                }
            }
            
            Divider()
            
            // Info stato
            if !agentReachable {
                Label("Server non raggiungibile", systemImage: "wifi.slash")
                    .foregroundColor(.secondary)
            } else if isSuspended {
                Label("Sincronizzazione sospesa", systemImage: "pause.circle")
                    .foregroundColor(.secondary)
            } else if case .upToDate = status {
                Label("Cartella sincronizzata", systemImage: "checkmark.circle")
                    .foregroundColor(.secondary)
            } else if let msg = errorMessage {
                Divider()
                Text(msg)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
        }
        .help(helpText)
        .onAppear {
            lastStatus = status
        }
        .onChange(of: status) { oldValue, newValue in
            // Evita aggiornamenti multipli per frame: aggiorna solo se effettivamente cambiato
            guard oldValue != newValue else { return }
            handleStatusChange(from: lastStatus, to: newValue)
            lastStatus = newValue
        }
    }
    
    private func handleStatusChange(from old: ClaimSyncStatus?, to new: ClaimSyncStatus) {
        // Quando finisce una sync file-per-file, mostra un riassunto per qualche secondo.
        guard let old else { return }
        guard old.isActive, !new.isActive else { return }
        guard case .upToDate = new else { return }
        
        let summary: String? = {
            switch old {
            case .downloadingFile(_, _, let total):
                return total > 0 ? "Scaricati \(total) file" : nil
            case .uploadingFile(_, _, let total):
                return total > 0 ? "Caricati \(total) file" : nil
            default:
                return nil
            }
        }()
        
        guard let summary else { return }
        
        lastSummaryText = summary
        summaryTask?.cancel()
        summaryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            lastSummaryText = nil
        }
    }
    
    private var syncText: String {
        switch status {
        case .registering: return "Connessione..."
        case .fetchingMetadata: return "Richiesta dati..."
        case .comparing: return "Analisi..."
        case .downloading(let info): return "Scarico \(Int(info.overallProgress * 100))%"
        case .downloadingFile(_, _, let t):
            return t == 1 ? "Scarico 1 file" : "Scarico \(t) file"
        case .extracting(let p): return "Estrazione \(Int(p * 100))%"
        case .uploading(let p): return "Invio \(Int(p * 100))%"
        case .uploadingFile(_, _, let t):
            return t == 1 ? "Carico 1 file" : "Carico \(t) file"
        default: return ""
        }
    }
    
    private var backgroundColor: Color {
        if isSyncing {
            return (isUploading ? Color.orange : Color.blue).opacity(0.1)
        } else if isSuspended {
            return Color.orange.opacity(0.1)
        } else if isError {
            return Color.red.opacity(0.1)
        } else {
            return Color.clear
        }
    }
    
    private var helpText: String {
        if isSuspended {
            return "Sincronizzazione sospesa - tasto destro per riattivare"
        } else if !agentReachable {
            return "Server non raggiungibile"
        } else if isSyncing {
            return "Sincronizzazione in corso - tasto destro per opzioni"
        } else if isError {
            if let msg = errorMessage {
                return "Errore sincronizzazione: \(msg)"
            }
            return "Errore sincronizzazione - tasto destro per riprovare"
        } else if lastSummaryText != nil {
            return "Sincronizzazione completata"
        } else {
            return "Cartella sincronizzata - tasto destro per opzioni"
        }
    }
}
