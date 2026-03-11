import Foundation
import SwiftUI
import Combine
import CoreData

// ClaimSyncStatus e DownloadProgressInfo da Models/Sync 2/SyncAgentModels.swift

/// Entry di file nel manifest (per compatibilità con vecchio SyncAgent)
struct ManifestFileEntry: Hashable {
    let relativePath: String
    let size: Int64
    let md5: String
    let modifiedAt: Date?
}

// MARK: - Hub Sync Service

/// Gestisce sincronizzazione cartelle sinistri tramite Hub
/// Sostituisce ClaimSyncService (che usava SyncAgent)
@MainActor
final class HubSyncService: ObservableObject {
    static let shared = HubSyncService()
    
    // MARK: - Published Properties
    
    @Published private(set) var statuses: [String: ClaimSyncStatus] = [:] // riferimento -> stato
    @Published private(set) var hubReachable: Bool = false
    @Published private(set) var suspendedClaims: Set<String> = []
    @Published private(set) var lastBackgroundSync: Date?
    @Published private(set) var initialSyncCompleted = false
    
    // MARK: - Private Properties
    
    private let api = HubAPIClient.shared
    private let vault = VaultService.shared
    private let fileService = FileService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Background sync
    private var backgroundSyncTimer: Timer?
    private let backgroundSyncInterval: TimeInterval = 60 // 1 minuto
    
    // Persistence keys
    private let suspendedSyncKey = "hubSync.suspendedClaims"
    private let firstSyncCompletedKeyPrefix = "hubSync.firstSyncCompleted."
    
    // Deletion schedule
    private let cleanupKey = "hubSync.cleanupSchedule"
    private let revokedCleanupKey = "hubSync.revokedCleanupSchedule"
    static let deletionDaysClosed = 7
    static let deletionDaysRevoked = 0
    
    // Continuations for initial sync waiters
    private var initialSyncContinuations: [CheckedContinuation<Bool, Never>] = []
    
    // MARK: - Initialization
    
    private init() {
        // Carica sinistri con sync sospesa
        if let saved = UserDefaults.standard.array(forKey: suspendedSyncKey) as? [String] {
            suspendedClaims = Set(saved)
        }
        
        // Osserva cambio di stato sinistro
        NotificationCenter.default.publisher(for: .sinistroStatoChanged)
            .sink { [weak self] note in
                guard let self,
                      let sinistroID = note.userInfo?["sinistroID"] as? String,
                      let newState = note.userInfo?["newState"] as? StatoManager.StatoSinistro
                else { return }
                Task { @MainActor in
                    await self.handleStateChange(sinistroID: sinistroID, newState: newState)
                }
            }
            .store(in: &cancellables)
        
        // Avvia setup asincrono
        Task {
            await refreshHubStatus()
            if hubReachable {
                startBackgroundSync()
            }
            markInitialSyncCompleted()
        }
    }
    
    // MARK: - Public API (compatibile con ClaimSyncService)
    
    /// Proprietà alias per compatibilità con codice esistente che usa agentReachable
    var agentReachable: Bool { hubReachable }
    
    /// Attende il completamento della sincronizzazione iniziale
    func waitForInitialSync(timeout: TimeInterval = 30) async -> Bool {
        if initialSyncCompleted { return true }
        
        return await withCheckedContinuation { continuation in
            initialSyncContinuations.append(continuation)
            
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                // Se ancora in attesa, rimuovi e restituisci false
                if let index = initialSyncContinuations.firstIndex(where: { $0 as AnyObject === continuation as AnyObject }) {
                    initialSyncContinuations.remove(at: index)
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    /// Avvia sync in background
    func startBackgroundSync() {
        stopBackgroundSync()
        
        backgroundSyncTimer = Timer.scheduledTimer(withTimeInterval: backgroundSyncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performBackgroundSync()
            }
        }
        
        print("[HubSync] ✅ Background sync avviato (intervallo: \(Int(backgroundSyncInterval))s)")
    }
    
    /// Ferma sync in background
    func stopBackgroundSync() {
        backgroundSyncTimer?.invalidate()
        backgroundSyncTimer = nil
    }
    
    /// Pausa tutte le sync temporanee (app in background)
    func pauseAllTemporarySyncs() async {
        stopBackgroundSync()
    }
    
    /// Riprende le sync quando l'app torna in foreground
    func resumeTemporarySyncsIfNeeded() async {
        await refreshHubStatus()
        if hubReachable && backgroundSyncTimer == nil {
            startBackgroundSync()
        }
    }
    
    /// Verifica raggiungibilità Hub
    func refreshHubStatus() async {
        do {
            _ = try await api.checkHealth()
            let wasReachable = hubReachable
            hubReachable = true
            
            if !wasReachable && backgroundSyncTimer == nil {
                print("[HubSync] ✅ Hub tornato online, riavvio background sync")
                startBackgroundSync()
            }
        } catch {
            let wasReachable = hubReachable
            hubReachable = false
            
            if wasReachable {
                print("[HubSync] ⚠️ Hub andato offline, fermo background sync")
                stopBackgroundSync()
            }
        }
    }
    
    /// Alias per compatibilità
    func refreshAgentStatus() async {
        await refreshHubStatus()
    }
    
    /// Stato sync per un sinistro
    func status(for sinistro: Sinistro) -> ClaimSyncStatus {
        guard let riferimento = sinistro.riferimento else { return .notDownloaded }
        
        if let trackedStatus = statuses[riferimento] {
            return trackedStatus
        }
        
        // Se la cartella esiste localmente
        if fileService.getSinistroPath(riferimento: riferimento) != nil {
            if isFirstSyncCompleted(for: riferimento) {
                return .upToDate
            } else {
                return .notDownloaded
            }
        }
        
        return .notDownloaded
    }
    
    /// Verifica se la sync è sospesa per un sinistro
    func isSyncSuspended(for sinistro: Sinistro) -> Bool {
        guard let rif = sinistro.riferimento else { return false }
        return suspendedClaims.contains(rif)
    }
    
    /// Sospende la sync per un sinistro
    func suspendSync(for riferimento: String) {
        suspendedClaims.insert(riferimento)
        UserDefaults.standard.set(Array(suspendedClaims), forKey: suspendedSyncKey)
        print("[HubSync] ⏸️ Sync sospesa per \(riferimento)")
    }
    
    /// Riprende la sync per un sinistro
    func resumeSync(for riferimento: String) async {
        suspendedClaims.remove(riferimento)
        UserDefaults.standard.set(Array(suspendedClaims), forKey: suspendedSyncKey)
        print("[HubSync] ▶️ Sync ripresa per \(riferimento)")
        
        // Avvia download se necessario
        if let sinistro = fetchSinistro(by: riferimento) {
            await manualDownload(for: sinistro)
        }
    }
    
    /// Download manuale della cartella sinistro
    func manualDownload(for sinistro: Sinistro) async {
        guard let riferimento = sinistro.riferimento else { return }
        
        // Rimuovi dalla lista sospesi se presente
        if suspendedClaims.contains(riferimento) {
            suspendedClaims.remove(riferimento)
            UserDefaults.standard.set(Array(suspendedClaims), forKey: suspendedSyncKey)
        }
        
        await downloadFromHub(riferimento: riferimento)
    }
    
    /// Ferma sync e programma eliminazione
    func stopSyncAndScheduleDeletion(riferimento: String) async {
        suspendSync(for: riferimento)
        scheduleDeletion(for: riferimento)
    }
    
    /// Ferma sync e rimuove cartella locale
    func stopSyncAndRemoveFolder(riferimento: String) async {
        suspendSync(for: riferimento)
        
        guard let path = fileService.getSinistroPath(riferimento: riferimento) else { return }
        
        do {
            try FileManager.default.removeItem(atPath: path)
            statuses[riferimento] = .notDownloaded
            clearFirstSyncCompleted(for: riferimento)
            print("[HubSync] 🗑️ Cartella locale eliminata per \(riferimento)")
            
            NotificationCenter.default.post(
                name: .claimFolderChanged,
                object: nil,
                userInfo: ["riferimento": riferimento]
            )
        } catch {
            print("[HubSync] ❌ Errore eliminazione cartella: \(error)")
        }
    }
    
    /// Elimina solo la cartella locale (senza modificare Hub)
    func deleteLocalFolderOnly(for sinistro: Sinistro) async {
        guard let riferimento = sinistro.riferimento,
              let path = fileService.getSinistroPath(riferimento: riferimento) else { return }
        
        do {
            try FileManager.default.removeItem(atPath: path)
            statuses[riferimento] = .notDownloaded
            clearFirstSyncCompleted(for: riferimento)
            
            NotificationCenter.default.post(
                name: .claimFolderChanged,
                object: nil,
                userInfo: ["riferimento": riferimento]
            )
        } catch {
            print("[HubSync] ❌ Errore eliminazione locale: \(error)")
        }
    }
    
    /// Rimuove la cartella locale di un sinistro
    func removeLocal(for sinistro: Sinistro) async {
        await deleteLocalFolderOnly(for: sinistro)
    }
    
    /// Upload file modificati
    func uploadChangedFiles(for sinistro: Sinistro, skipHealthCheck: Bool = false, isBackgroundSync: Bool = false, alreadyUploadedPaths: Set<String> = []) async {
        guard let riferimento = sinistro.riferimento else { return }
        guard !suspendedClaims.contains(riferimento) else { return }
        
        if !skipHealthCheck {
            await refreshHubStatus()
        }
        
        guard hubReachable else {
            if !isBackgroundSync {
                setStatus(.error("Hub non raggiungibile"), for: riferimento)
            }
            return
        }
        
        guard let localPath = fileService.getSinistroPath(riferimento: riferimento) else { return }
        
        setStatus(.uploading(progress: 0), for: riferimento)
        
        do {
            // Lista file già presenti sul Vault per non ricrearli (evita duplicati)
            let existingOnVault: Set<String> = (try? await vault.listFiles(sinistroRef: riferimento, forceRefresh: true))
                .map { vaultFiles in
                    Set(vaultFiles.map { f in vaultRelativePath(folder: f.folder, filename: f.filename) })
                } ?? []
            
            // Lista file locali e filtra quelli già sul Vault (stesso path)
            let localFiles = fileService.listFilesRecursive(inDirectory: localPath)
            let filesToUpload = localFiles.filter { fileURL in
                guard !alreadyUploadedPaths.contains(fileURL.path) else { return false }
                let relativePath = fileURL.path.replacingOccurrences(of: localPath + "/", with: "")
                let pathKey = (relativePath as NSString).deletingLastPathComponent
                let filename = fileURL.lastPathComponent
                let vaultPath = vaultRelativePath(folder: pathKey, filename: filename)
                return !existingOnVault.contains(vaultPath)
            }
            
            guard !filesToUpload.isEmpty else {
                setStatus(.upToDate, for: riferimento)
                return
            }
            
            var uploaded = 0
            for fileURL in filesToUpload {
                let relativePath = fileURL.path.replacingOccurrences(of: localPath + "/", with: "")
                let folder = (relativePath as NSString).deletingLastPathComponent
                
                setStatus(.uploadingFile(name: fileURL.lastPathComponent, current: uploaded + 1, total: filesToUpload.count), for: riferimento)
                
                _ = try await vault.uploadFile(sinistroRef: riferimento, localURL: fileURL, folder: folder)
                uploaded += 1
            }
            
            setStatus(.upToDate, for: riferimento)
            print("[HubSync] ✅ Upload completato per \(riferimento): \(uploaded) file")
            
        } catch {
            setStatus(.error("Errore upload: \(error.localizedDescription)"), for: riferimento)
            print("[HubSync] ❌ Errore upload per \(riferimento): \(error)")
        }
    }
    
    /// Upload file di chiusura immediatamente
    func uploadClosureFilesImmediately(riferimento: String, fileURLs: [URL]) async {
        guard !fileURLs.isEmpty else { return }
        
        await refreshHubStatus()
        guard hubReachable else {
            setStatus(.error("Hub non raggiungibile"), for: riferimento)
            return
        }
        
        do {
            for fileURL in fileURLs {
                _ = try await vault.uploadFile(sinistroRef: riferimento, localURL: fileURL, folder: "_chiusura")
            }
            print("[HubSync] ✅ File chiusura uploadati per \(riferimento)")
        } catch {
            print("[HubSync] ❌ Errore upload file chiusura: \(error)")
        }
    }
    
    /// Registra nuovo sinistro
    func registerNewClaim(riferimento: String) async {
        guard hubReachable else { return }
        
        do {
            _ = try await api.ensureFolderAvailable(sinistroRef: riferimento)
            print("[HubSync] ✅ Sinistro \(riferimento) registrato su Hub")
        } catch {
            print("[HubSync] ❌ Errore registrazione sinistro: \(error)")
        }
    }
    
    /// Registra tutti i sinistri assegnati
    func registerAllAssignedClaims() async {
        guard hubReachable else { return }
        // In modalità Hub, non serve registrazione esplicita
        // I sinistri vengono creati on-demand
    }
    
    /// Assicura monitoring per task attivo
    func ensureMonitoringForActiveTask(sinistroID: String) async {
        guard let sinistro = fetchSinistro(by: sinistroID) else { return }
        await manualDownload(for: sinistro)
    }
    
    /// Finalizza dopo completamento task
    func finalizeAfterTasks(sinistroID: String) async {
        guard let sinistro = fetchSinistro(by: sinistroID) else { return }
        await uploadChangedFiles(for: sinistro)
    }
    
    /// Scarica cartella sinistro
    func downloadClaimFolder(riferimento: String) async {
        await downloadFromHub(riferimento: riferimento)
    }
    
    /// Ottiene la lista dei file dal manifest (per compatibilità con vecchio SyncAgent)
    /// In modalità Hub restituisce nil - i file sono gestiti localmente
    func getManifestFiles(for riferimento: String) -> [ManifestFileEntry]? {
        // In modalità Hub non manteniamo un manifest locale
        // I file vengono gestiti direttamente dal filesystem locale
        return nil
    }
    
    // MARK: - Temporary Sync (per sinistri non propri o chiusi)
    
    func startTemporarySync(for sinistro: Sinistro) async {
        guard let riferimento = sinistro.riferimento else { return }
        await manualDownload(for: sinistro)
    }
    
    func stopTemporarySync(for riferimento: String) async {
        // In modalità Hub, non c'è distinzione tra sync temporanea e permanente
        suspendSync(for: riferimento)
    }
    
    func hasTemporarySync(for riferimento: String) -> Bool {
        return !suspendedClaims.contains(riferimento)
    }
    
    // MARK: - Manual Claim Tracking
    
    func trackManuallyAddedClaim(riferimento: String, currentState: String) {
        // In modalità Hub, non serve tracking manuale
    }
    
    func untrackManuallyAddedClaim(riferimento: String) {
        // In modalità Hub, non serve tracking manuale
    }
    
    func checkManualClaimStateChange(riferimento: String, newState: String) {
        // In modalità Hub, non serve tracking manuale
    }
    
    // MARK: - Deletion Management
    
    struct PendingDeletionInfo: Identifiable {
        let id: String // riferimento
        let scheduledDate: Date
        let daysRemaining: Int
        let reason: DeletionReason
        
        /// Alias per compatibilità
        var riferimento: String { id }
        var expirationDate: Date { scheduledDate }
    }
    
    enum DeletionReason: String {
        case closed = "Sinistro chiuso"
        case revoked = "Sinistro revocato"
        case manual = "Eliminazione manuale"
    }
    
    var isAutoDeleteEnabled: Bool {
        UserDefaults.standard.bool(forKey: "enableAutoDeleteClosed")
    }
    
    func getPendingDeletions() -> [PendingDeletionInfo] {
        var result: [PendingDeletionInfo] = []
        
        if let schedule = UserDefaults.standard.dictionary(forKey: cleanupKey) as? [String: String] {
            let formatter = ISO8601DateFormatter()
            for (rif, dateStr) in schedule {
                if let date = formatter.date(from: dateStr) {
                    let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
                    result.append(PendingDeletionInfo(id: rif, scheduledDate: date, daysRemaining: max(0, days), reason: .closed))
                }
            }
        }
        
        return result.sorted { $0.daysRemaining < $1.daysRemaining }
    }
    
    func isPendingDeletion(riferimento: String) -> Bool {
        guard let schedule = UserDefaults.standard.dictionary(forKey: cleanupKey) as? [String: String] else {
            return false
        }
        return schedule[riferimento] != nil
    }
    
    func cancelPendingDeletion(riferimento: String) {
        var schedule = UserDefaults.standard.dictionary(forKey: cleanupKey) as? [String: String] ?? [:]
        schedule.removeValue(forKey: riferimento)
        UserDefaults.standard.set(schedule, forKey: cleanupKey)
    }
    
    func deleteImmediately(riferimento: String) async {
        cancelPendingDeletion(riferimento: riferimento)
        await stopSyncAndRemoveFolder(riferimento: riferimento)
    }
    
    // MARK: - Private Methods
    
    private func setStatus(_ status: ClaimSyncStatus, for riferimento: String) {
        statuses[riferimento] = status
    }
    
    private func markInitialSyncCompleted() {
        guard !initialSyncCompleted else { return }
        initialSyncCompleted = true
        
        for continuation in initialSyncContinuations {
            continuation.resume(returning: true)
        }
        initialSyncContinuations.removeAll()
        
        print("[HubSync] ✅ Sync iniziale completata")
    }
    
    private func downloadFromHub(riferimento: String) async {
        await refreshHubStatus()
        
        guard hubReachable else {
            setStatus(.error("Hub non raggiungibile"), for: riferimento)
            return
        }
        
        setStatus(.registering, for: riferimento)
        
        do {
            // Assicura che la cartella esista sull'Hub
            _ = try await api.ensureFolderAvailable(sinistroRef: riferimento)
            
            setStatus(.fetchingMetadata, for: riferimento)
            
            // Lista file dal Vault e deduplica per path (folder+filename) per evitare duplicati
            let rawFiles = try await vault.listFiles(sinistroRef: riferimento, forceRefresh: true)
            let files = deduplicateVaultFiles(rawFiles)
            
            guard !files.isEmpty else {
                // Cartella vuota ma esistente
                _ = fileService.getSinistroPath(riferimento: riferimento, create: true)
                markFirstSyncCompleted(for: riferimento)
                setStatus(.upToDate, for: riferimento)
                
                NotificationCenter.default.post(
                    name: .claimFolderChanged,
                    object: nil,
                    userInfo: ["riferimento": riferimento]
                )
                return
            }
            
            setStatus(.comparing, for: riferimento)
            
            // Crea cartella locale
            guard let localPath = fileService.getSinistroPath(riferimento: riferimento, create: true) else {
                setStatus(.error("Impossibile creare cartella locale"), for: riferimento)
                return
            }
            
            // Download tutti i file
            let totalBytes = files.reduce(0) { $0 + $1.size }
            var downloadedBytes: Int64 = 0
            var downloadedCount = 0
            
            for file in files {
                setStatus(.downloadingFile(name: file.filename, current: downloadedCount + 1, total: files.count), for: riferimento)
                
                // Download file
                let data = try await api.downloadFile(fileId: file.id)
                
                // Salva localmente
                let localFileURL = URL(fileURLWithPath: localPath)
                    .appendingPathComponent(file.folder)
                    .appendingPathComponent(file.filename)
                
                // Crea sottocartella se necessario
                try FileManager.default.createDirectory(
                    at: localFileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                
                try data.write(to: localFileURL)
                
                downloadedBytes += file.size
                downloadedCount += 1
                
                let progress = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : Double(downloadedCount) / Double(files.count)
                setStatus(.downloading(info: DownloadProgressInfo(
                    progress: progress,
                    overallProgress: progress,
                    bytesDownloaded: downloadedBytes,
                    bytesTotal: totalBytes,
                    bytesPerSecond: 0
                )), for: riferimento)
            }
            
            markFirstSyncCompleted(for: riferimento)
            setStatus(.upToDate, for: riferimento)
            
            NotificationCenter.default.post(
                name: .claimFolderChanged,
                object: nil,
                userInfo: ["riferimento": riferimento]
            )
            
            print("[HubSync] ✅ Download completato per \(riferimento): \(files.count) file")
            
        } catch {
            setStatus(.error("Errore download: \(error.localizedDescription)"), for: riferimento)
            print("[HubSync] ❌ Errore download per \(riferimento): \(error)")
        }
    }
    
    private func performBackgroundSync() async {
        await refreshHubStatus()
        guard hubReachable else { return }
        
        lastBackgroundSync = Date()
        
        // Upload modifiche per sinistri attivi
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "stato != %@ AND stato != %@",
                                         StatoManager.StatoSinistro.chiusa.descrizione,
                                         StatoManager.StatoSinistro.revocata.descrizione)
        
        guard let sinistri = try? context.fetch(request) else { return }
        
        for sinistro in sinistri {
            guard let rif = sinistro.riferimento,
                  !suspendedClaims.contains(rif),
                  fileService.getSinistroPath(riferimento: rif) != nil else { continue }
            
            await uploadChangedFiles(for: sinistro, skipHealthCheck: true, isBackgroundSync: true)
        }
        
        // Esegui cleanup programmato
        await performScheduledCleanup()
    }
    
    private func handleStateChange(sinistroID: String, newState: StatoManager.StatoSinistro) async {
        // Gestisci transizione a stati terminali
        if newState == .chiusa || newState == .revocata {
            scheduleDeletion(for: sinistroID)
        } else {
            // Rimuovi da schedule se torna attivo
            cancelPendingDeletion(riferimento: sinistroID)
        }
    }
    
    private func scheduleDeletion(for riferimento: String) {
        guard isAutoDeleteEnabled else { return }
        
        var schedule = UserDefaults.standard.dictionary(forKey: cleanupKey) as? [String: String] ?? [:]
        let deleteDate = Calendar.current.date(byAdding: .day, value: Self.deletionDaysClosed, to: Date()) ?? Date()
        schedule[riferimento] = ISO8601DateFormatter().string(from: deleteDate)
        UserDefaults.standard.set(schedule, forKey: cleanupKey)
        
        print("[HubSync] 📅 Programmata eliminazione per \(riferimento) il \(deleteDate)")
    }
    
    private func performScheduledCleanup() async {
        guard isAutoDeleteEnabled else { return }
        
        guard var schedule = UserDefaults.standard.dictionary(forKey: cleanupKey) as? [String: String] else {
            return
        }
        
        let formatter = ISO8601DateFormatter()
        let now = Date()
        var toDelete: [String] = []
        
        for (rif, dateStr) in schedule {
            if let date = formatter.date(from: dateStr), date <= now {
                toDelete.append(rif)
            }
        }
        
        for rif in toDelete {
            await stopSyncAndRemoveFolder(riferimento: rif)
            schedule.removeValue(forKey: rif)
        }
        
        UserDefaults.standard.set(schedule, forKey: cleanupKey)
    }
    
    // MARK: - First Sync Tracking
    
    private func isFirstSyncCompleted(for riferimento: String) -> Bool {
        UserDefaults.standard.bool(forKey: firstSyncCompletedKeyPrefix + riferimento)
    }
    
    private func markFirstSyncCompleted(for riferimento: String) {
        UserDefaults.standard.set(true, forKey: firstSyncCompletedKeyPrefix + riferimento)
    }
    
    private func clearFirstSyncCompleted(for riferimento: String) {
        UserDefaults.standard.removeObject(forKey: firstSyncCompletedKeyPrefix + riferimento)
    }
    
    // MARK: - Helpers (anti-duplicati sync)
    
    /// Path logico univoco Vault (folder + filename) per confronti
    private func vaultRelativePath(folder: String, filename: String) -> String {
        let f = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        if f.isEmpty { return filename }
        return (f as NSString).appendingPathComponent(filename)
    }
    
    /// Deduplica lista Vault per (folder, filename) tenendo la versione più recente
    private func deduplicateVaultFiles(_ files: [VaultFileDTO]) -> [VaultFileDTO] {
        let keyed = Dictionary(grouping: files) { vaultRelativePath(folder: $0.folder, filename: $0.filename) }
        return keyed.compactMapValues { group in
            group.max(by: { a, b in
                let dateA = a.modifiedAt ?? a.createdAt
                let dateB = b.modifiedAt ?? b.createdAt
                return dateA < dateB
            })
        }.values.map { $0 }
    }
    
    private func fetchSinistro(by riferimento: String) -> Sinistro? {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}

// MARK: - Type Aliases for Compatibility

/// Sincronizzazione sinistri: solo via Hub (Sync Agent locale rimosso)
typealias ClaimSyncService = HubSyncService
