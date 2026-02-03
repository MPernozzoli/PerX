import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Empty Folder View

struct EmptyFolderView: View {
    let sinistro: Sinistro
    let status: ClaimSyncStatus
    let agentReachable: Bool
    let onDownload: () -> Void
    var onStopSync: (() -> Void)? = nil
    var onForceSync: (() -> Void)? = nil
    var onFilesImported: (() -> Void)? = nil
    
    // Stato per drag-in
    @State private var isDragOver = false
    @State private var isImporting = false
    @State private var importMessage = ""
    
    private let fileService = FileService.shared
    
    // Osserva direttamente ClaimSyncService per aggiornamenti in tempo reale
    @ObservedObject private var claimSync = ClaimSyncService.shared
    
    // Timer per refresh periodico durante sync attivo
    @State private var refreshTimer: Timer?
    @State private var refreshTrigger = UUID()
    
    // UX: messaggi “in attesa” prima dei primi byte
    @State private var waitingMessageIndex: Int = 0
    @State private var waitingMessageTask: Task<Void, Never>?
    
    // Memorizza lo status corrente per evitare calcoli multipli per frame
    @State private var cachedStatus: ClaimSyncStatus
    
    /// Stato corrente (letto in tempo reale da ClaimSyncService)
    private var currentStatus: ClaimSyncStatus {
        cachedStatus
    }
    
    init(sinistro: Sinistro, status: ClaimSyncStatus, agentReachable: Bool, onDownload: @escaping () -> Void, onStopSync: (() -> Void)? = nil, onForceSync: (() -> Void)? = nil, onFilesImported: (() -> Void)? = nil) {
        self.sinistro = sinistro
        self.status = status
        self.agentReachable = agentReachable
        self.onDownload = onDownload
        self.onStopSync = onStopSync
        self.onForceSync = onForceSync
        self.onFilesImported = onFilesImported
        self._cachedStatus = State(initialValue: status)
    }

    private var isDownloading: Bool {
        switch currentStatus {
        case .registering, .fetchingMetadata, .comparing, .downloading, .downloadingFile, .extracting:
            return true
        default:
            return false
        }
    }
    
    private var isUploading: Bool {
        switch currentStatus {
        case .uploading, .uploadingFile:
            return true
        default:
            return false
        }
    }
    
    private var isSyncing: Bool {
        isDownloading || isUploading
    }
    
    private var isError: Bool {
        if case .error = currentStatus { return true }
        return false
    }
    
    private var isWaitingForFirstBytes: Bool {
        guard isDownloading else { return false }
        let bytes = downloadInfo?.bytesDownloaded ?? 0
        return bytes == 0
    }
    
    private let waitingMessages: [String] = [
        "In attesa di dati…",
        "Sto recuperando i file del sinistro…",
        "Questa operazione può richiedere alcuni minuti…",
        "Sto preparando il download…"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 24) {
                // Icona principale con anello di progresso attorno
                ZStack {
                    // Sfondo cerchio
                    Circle()
                        .fill(isSyncing ? Color.blue.opacity(0.1) : (isError ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1)))
                        .frame(width: 100, height: 100)
                    
                    // Anello di progresso (solo durante sync)
                    if isSyncing {
                        SyncProgressCircle(progress: currentProgress, color: isUploading ? .orange : .blue)
                            .frame(width: 100, height: 100)
                    }
                    
                    // Icona centrale (sempre visibile)
                    Image(systemName: iconName)
                        .font(.system(size: 36))
                        .foregroundColor(iconColor)
                        .scaleEffect(isWaitingForFirstBytes ? 1.06 : 1.0)
                        .offset(y: isWaitingForFirstBytes ? -1 : 0)
                        .animation(
                            isWaitingForFirstBytes
                                ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                : .default,
                            value: isWaitingForFirstBytes
                        )
                }
                .contextMenu {
                    if isSyncing {
                        if let stopSync = onStopSync {
                            Button(role: .destructive) {
                                stopSync()
                            } label: {
                                Label("Interrompi sincronizzazione", systemImage: "stop.circle")
                            }
                        }
                    } else if agentReachable {
                        if let forceSync = onForceSync {
                            Button {
                                forceSync()
                            } label: {
                                Label("Sincronizza adesso", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        
                        Button {
                            onDownload()
                        } label: {
                            Label("Scarica cartella", systemImage: "arrow.down.circle")
                        }
                    }
                }
                
                // Testo principale
                VStack(spacing: 8) {
                    Text(titleText)
                        .font(.title3.weight(.semibold))
                    
                    if isWaitingForFirstBytes {
                        Text(waitingMessages[waitingMessageIndex % max(waitingMessages.count, 1)])
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.85))
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.25), value: waitingMessageIndex)
                        
                        Text("Questa operazione può richiedere alcuni minuti.")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    } else {
                        // Statistiche download (velocità e dimensioni)
                        if let stats = downloadStatsText {
                            Text(stats)
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.8))
                                .monospacedDigit()
                        }
                        
                        // Tempo stimato rimanente (ETA)
                        if let eta = downloadEtaText {
                            Text(eta)
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.8))
                                .monospacedDigit()
                        }
                    }
                    
                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Pulsante download (solo se non in sync)
                if !isSyncing {
                    Button {
                        onDownload()
                    } label: {
                        Label("Scarica Cartella", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!agentReachable)
                    .padding(.top, 8)
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
            )
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDragOver ? Color.accentColor.opacity(0.1) : Color(NSColor.windowBackgroundColor))
        .overlay(
            // Overlay per feedback drag-in
            Group {
                if isDragOver {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
                        .padding(20)
                }
                
                if isImporting {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(importMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .shadow(radius: 5)
                    )
                }
            }
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
            return true
        }
        .id(refreshTrigger) // Forza re-render quando cambia
        .onAppear {
            startRefreshTimerIfNeeded()
            startWaitingMessagesIfNeeded()
        }
        .onDisappear {
            stopRefreshTimer()
            stopWaitingMessages()
        }
        .onChange(of: isSyncing) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if newValue {
                startRefreshTimerIfNeeded()
            } else {
                stopRefreshTimer()
            }
        }
        .onChange(of: isWaitingForFirstBytes) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if newValue {
                startWaitingMessagesIfNeeded()
            }
        }
        .onChange(of: claimSync.statuses) { _ in
            // Aggiorna cachedStatus solo se effettivamente cambiato
            let newStatus = claimSync.status(for: sinistro)
            if newStatus != cachedStatus {
                cachedStatus = newStatus
                refreshTrigger = UUID()
            }
        }
    }
    
    // MARK: - Timer Management
    
    private func startRefreshTimerIfNeeded() {
        guard isSyncing, refreshTimer == nil else { return }
        
        // Aggiorna la UI ogni 250ms per un feedback fluido
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            refreshTrigger = UUID()
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func startWaitingMessagesIfNeeded() {
        guard isWaitingForFirstBytes else {
            stopWaitingMessages()
            return
        }
        guard waitingMessageTask == nil else { return }
        
        waitingMessageTask = Task { @MainActor in
            while !Task.isCancelled, isWaitingForFirstBytes {
                try? await Task.sleep(nanoseconds: 2_800_000_000) // ~2.8s
                if Task.isCancelled || !isWaitingForFirstBytes { break }
                waitingMessageIndex += 1
            }
        }
    }
    
    private func stopWaitingMessages() {
        waitingMessageTask?.cancel()
        waitingMessageTask = nil
        waitingMessageIndex = 0
    }
    
    private var currentProgress: Double? {
        switch currentStatus {
        case .registering:
            return 0.05 // 5% durante registrazione
        case .fetchingMetadata:
            return 0.08 // 8% durante fetch metadata
        case .comparing:
            return 0.10 // 10% durante comparazione
        case .downloading(let info):
            return info.overallProgress
        case .downloadingFile(_, let current, let total):
            // Mappa su range 10-90%
            let fileProgress = total > 0 ? Double(current) / Double(total) : 0
            return 0.10 + (fileProgress * 0.80)
        case .extracting(let progress):
            return progress
        case .uploading(let progress):
            return progress
        case .uploadingFile(_, let current, let total):
            return total > 0 ? Double(current) / Double(total) : nil
        default:
            return nil
        }
    }
    
    /// Informazioni dettagliate sul download (velocità, byte)
    private var downloadInfo: DownloadProgressInfo? {
        if case .downloading(let info) = currentStatus {
            return info
        }
        return nil
    }
    
    private var iconName: String {
        if isError {
            return "exclamationmark.triangle.fill"
        } else if isUploading {
            return "arrow.up.doc.fill"
        } else if isDownloading {
            return "arrow.down.doc.fill"
        } else {
            return "folder.badge.plus"
        }
    }
    
    private var iconColor: Color {
        if isError {
            return .red
        } else if isSyncing {
            return isUploading ? .orange : .blue
        } else {
            return .accentColor
        }
    }
    
    private var titleText: String {
        switch currentStatus {
        case .registering:
            return "Connessione al server... 5%"
        case .fetchingMetadata:
            return "Richiedo i dati... 8%"
        case .comparing:
            return "Analizzo i file... 10%"
        case .downloading(let info):
            return "Scarico la cartella \(Int(info.overallProgress * 100))%"
        case .downloadingFile(_, let c, let t):
            let fileProgress = t > 0 ? Double(c) / Double(t) : 0
            let overallProgress = 0.10 + (fileProgress * 0.80)
            return "Scarico i file (\(c)/\(t)) - \(Int(overallProgress * 100))%"
        case .extracting(let p):
            return "Decompressione... \(Int(p * 100))%"
        case .uploading(let p):
            return "Invio modifiche \(Int(p * 100))%"
        case .uploadingFile(_, let c, let t):
            return "Invio file (\(c)/\(t))"
        case .error(let msg):
            return msg
        default:
            return "Cartella non presente"
        }
    }
    
    private var subtitleText: String {
        if !agentReachable && !isSyncing {
            return "Il server non è raggiungibile.\nVerifica la connessione nelle impostazioni."
        } else if isSyncing {
            return "Tasto destro per interrompere"
        } else if isError {
            return "Riprova a scaricare la cartella"
        } else {
            return "Scarica la cartella per visualizzare i documenti."
        }
    }
    
    /// Testo con statistiche download (velocità e dimensioni)
    private var downloadStatsText: String? {
        guard let info = downloadInfo else { return nil }

        var parts: [String] = []
        
        // Se non abbiamo ancora ricevuto byte, evita il "Zero KB" (fuorviante quando il download sta partendo)
        if info.bytesDownloaded == 0, isDownloading {
            return info.bytesTotal > 0 ? "In attesa dati • \(info.totalFormatted)" : "In attesa dati"
        }
        
        // Dimensioni:
        // - se totale noto: "15.2 MB / 234.5 MB"
        // - se totale ignoto: "15.2 MB"
        if info.bytesTotal > 0 {
            parts.append("\(info.downloadedFormatted) / \(info.totalFormatted)")
        } else {
            parts.append("\(info.downloadedFormatted)")
        }
        
        // Velocità: "2.5 MB/s" (solo se > 0)
        if info.bytesPerSecond > 0 {
            parts.append(info.speedFormatted)
        }
        
        return parts.joined(separator: " • ")
    }
    
    /// Tempo stimato rimanente (richiede totale noto + velocità)
    private var downloadEtaText: String? {
        guard isDownloading, let info = downloadInfo else { return nil }
        guard info.bytesTotal > 0, info.bytesDownloaded > 0, info.bytesPerSecond > 0 else { return nil }
        
        let remainingBytes = max(Int64(0), info.bytesTotal - info.bytesDownloaded)
        let seconds = Double(remainingBytes) / info.bytesPerSecond
        guard seconds.isFinite, seconds > 1 else { return nil }
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        
        guard let formatted = formatter.string(from: seconds) else { return nil }
        return "Tempo stimato: \(formatted)"
    }
    
    // MARK: - Drag & Drop
    
    private func handleDrop(providers: [NSItemProvider]) {
        guard let riferimento = sinistro.riferimento,
              let targetPath = fileService.getSinistroPath(riferimento: riferimento) else {
            return
        }
        
        isImporting = true
        importMessage = "Importazione in corso..."
        
        let targetURL = URL(fileURLWithPath: targetPath)
        let fm = FileManager.default
        var processedCount = 0
        var successCount = 0
        let totalCount = providers.count
        
        for provider in providers {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { tempURL, error in
                defer {
                    processedCount += 1
                    if processedCount == totalCount {
                        DispatchQueue.main.async {
                            self.isImporting = false
                            self.importMessage = ""
                            if successCount > 0 {
                                self.onFilesImported?()
                            }
                        }
                    }
                }
                
                guard let tempURL = tempURL else { return }
                
                // Verifica se è una directory
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: tempURL.path, isDirectory: &isDirectory) else { return }
                
                if isDirectory.boolValue {
                    // È una cartella - verifica se è una "cartella sinistro" o "Files"
                    let folderName = tempURL.lastPathComponent.lowercased()
                    let isRootFolder = folderName == riferimento.lowercased() || folderName == "files"
                    
                    if isRootFolder {
                        // Importa il CONTENUTO della cartella, non la cartella stessa
                        DispatchQueue.main.async {
                            self.importMessage = "Importazione contenuto cartella..."
                        }
                        
                        do {
                            let contents = try fm.contentsOfDirectory(at: tempURL, includingPropertiesForKeys: nil)
                            for item in contents {
                                let destURL = self.uniqueDestinationURL(in: targetURL, desiredName: item.lastPathComponent)
                                try? fm.copyItem(at: item, to: destURL)
                            }
                            successCount += 1
                        } catch {
                            print("[EmptyFolderView] Errore importazione contenuto cartella: \(error)")
                        }
                    } else {
                        // Cartella normale - importa la cartella intera
                        let destURL = self.uniqueDestinationURL(in: targetURL, desiredName: tempURL.lastPathComponent)
                        do {
                            try fm.copyItem(at: tempURL, to: destURL)
                            successCount += 1
                        } catch {
                            print("[EmptyFolderView] Errore copia cartella: \(error)")
                        }
                    }
                } else {
                    // È un file - importa normalmente
                    let destURL = self.uniqueDestinationURL(in: targetURL, desiredName: tempURL.lastPathComponent)
                    do {
                        try fm.copyItem(at: tempURL, to: destURL)
                        successCount += 1
                    } catch {
                        print("[EmptyFolderView] Errore copia file: \(error)")
                    }
                }
            }
        }
    }
    
    /// Genera un URL univoco nella directory di destinazione (evita sovrascritture)
    private func uniqueDestinationURL(in directory: URL, desiredName: String) -> URL {
        let fm = FileManager.default
        let baseName = (desiredName as NSString).deletingPathExtension
        let ext = (desiredName as NSString).pathExtension
        
        var candidate = directory.appendingPathComponent(desiredName)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        
        var i = 2
        while true {
            let name = ext.isEmpty ? "\(baseName) \(i)" : "\(baseName) \(i).\(ext)"
            candidate = directory.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}
