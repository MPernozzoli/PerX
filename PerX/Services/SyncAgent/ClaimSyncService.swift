import Foundation
import SwiftUI
import Combine
import CoreData
import CryptoKit

/// Gestisce registrazione, download, upload e cleanup cartelle sinistri.
@MainActor
final class ClaimSyncService: ObservableObject {
    static let shared = ClaimSyncService()

    @Published private(set) var statuses: [String: ClaimSyncStatus] = [:] // riferimento -> stato
    @Published private(set) var agentReachable: Bool = false

    private let apiClient = SyncAgentAPIClient.shared
    private let config = SyncAgentConfig.shared
    private let fileService = FileService.shared
    private let sleepManager = SyncSleepManager.shared
    private var cancellables = Set<AnyCancellable>()
    private let fallbackDownloadInterval: TimeInterval = 24 * 60 * 60
    private let manifestCacheFolder = "SyncManifests"

    // Countdown eliminazione sinistri chiusi / revocati (giorni fissi)
    private let cleanupKey = "syncAgent.cleanupSchedule" // riferimento -> ISODate (chiusi)
    private let revokedCleanupKey = "syncAgent.revokedCleanupSchedule" // riferimento -> ISODate (revocati)
    private let firstSyncCompletedKeyPrefix = "syncAgent.firstSyncCompleted." // + riferimento
    static let deletionDaysClosed = 7
    static let deletionDaysRevoked = 0

    // Giorni dopo i quali disiscrivere sinistri in stati terminali
    private let unregisterDelayDays = 7
    private let unregisterScheduleKey = "syncAgent.unregisterSchedule" // riferimento -> ISODate
    
    // Sinistri aggiunti manualmente (es. chiusi) - cancellazione dopo 3 giorni senza cambio stato
    private let manualClaimCleanupKey = "syncAgent.manualClaimCleanup" // riferimento -> { addedAt: ISODate, initialState: String }
    private let manualClaimCleanupDays = 3
    
    // Sinistri con sync sospesa (esclusi dalla sync automatica)
    private let suspendedSyncKey = "syncAgent.suspendedClaims" // Set<String> di riferimenti
    @Published private(set) var suspendedClaims: Set<String> = []
    
    // Sinistri aperti temporaneamente (non propri o in stati terminali)
    private let temporarySyncKey = "syncAgent.temporarySync" // riferimento -> { openedAt: ISODate, isNonOwner: Bool, isTerminalState: Bool }
    private var temporarySyncClaims: [String: TemporarySyncInfo] = [:]
    private let temporarySyncCleanupDays = 3
    
    struct TemporarySyncInfo: Codable {
        let openedAt: Date
        let isNonOwner: Bool
        let isTerminalState: Bool
    }
    
    // Sync in background
    private var backgroundSyncTimer: Timer?
    private let backgroundSyncInterval: TimeInterval = 60 // 1 minuto
    @Published private(set) var lastBackgroundSync: Date?
    
    // Flag per indicare che la prima sincronizzazione è completata
    // Usato da EmailQueueService per attendere prima di processare le email
    @Published private(set) var initialSyncCompleted = false
    
    // Continuation per notificare i listener che la sync iniziale è completata
    private var initialSyncContinuations: [CheckedContinuation<Void, Never>] = []
    
    /// True se i file sono gestiti dall'Hub (non usare Sync Agent per download/sync)
    private var isFileModeCloud: Bool {
        HubConfigService.shared.fileManagementMode == .cloud
    }
    
    private init() {
        // Carica sinistri con sync sospesa
        if let saved = UserDefaults.standard.array(forKey: suspendedSyncKey) as? [String] {
            suspendedClaims = Set(saved)
        }
        
        // Carica sinistri con sync temporanea
        loadTemporarySyncClaims()
        
        // Osserva cambio di stato per gestire registrazione/disiscrizione
        NotificationCenter.default.publisher(for: .sinistroStatoChanged)
            .sink { [weak self] note in
                guard
                    let self,
                    let sinistroID = note.userInfo?["sinistroID"] as? String,
                    let newState = note.userInfo?["newState"] as? StatoManager.StatoSinistro
                else { return }
                Task { @MainActor in
                    await self.handleStateChange(sinistroID: sinistroID, newState: newState)
                }
            }
            .store(in: &cancellables)
        
        // Osserva quando viene creato un nuovo sinistro (via mail o cartella)
        NotificationCenter.default.publisher(for: .sinistroCreated)
            .sink { [weak self] note in
                guard let self,
                      let riferimento = note.userInfo?["riferimento"] as? String else { return }
                Task { @MainActor in
                    if self.isFileModeCloud { return }
                    if let sinistro = self.fetchSinistro(by: riferimento) {
                        await self.registerAndSyncIfNeeded(sinistro: sinistro, forceDownload: false)
                    } else {
                        print("[ClaimSync] ⏭️ Sinistro \(riferimento) creato ma non ancora nel DB, skip registrazione automatica")
                    }
                }
            }
            .store(in: &cancellables)
        
        // Osserva quando vengono eliminati file o cartelle
        NotificationCenter.default.publisher(for: .fileOrFolderDeleted)
            .sink { [weak self] note in
                guard let self,
                      let sinistroPath = note.userInfo?["sinistroPath"] as? String,
                      let relativePath = note.userInfo?["relativePath"] as? String,
                      let isDirectory = note.userInfo?["isDirectory"] as? Bool else { return }
                
                // Trova il riferimento del sinistro dal path
                Task { @MainActor in
                    if let riferimento = self.getRiferimentoFromPath(sinistroPath) {
                        await self.handleFileOrFolderDeletion(
                            riferimento: riferimento,
                            relativePath: relativePath,
                            isDirectory: isDirectory
                        )
                    }
                }
            }
            .store(in: &cancellables)

        Task {
            await refreshAgentStatus()
            if isFileModeCloud {
                markInitialSyncCompleted()
                return
            }
            if agentReachable {
                await registerAllAssignedClaims()
                await performScheduledCleanup()
                await performScheduledUnregistration()
                await performTemporarySyncCleanup()
                
                // 3. Marca la sincronizzazione iniziale come completata
                // Questo sblocca EmailQueueService che attendeva
                markInitialSyncCompleted()
                
                startBackgroundSync()
            } else {
                print("[ClaimSync] ⏸️ Agent offline all'avvio, background sync non avviato")
                // Marca comunque come completata per non bloccare altri servizi
                markInitialSyncCompleted()
            }
        }
    }
    
    // MARK: - Initial Sync Coordination
    
    /// Marca la sincronizzazione iniziale come completata e notifica i listener
    private func markInitialSyncCompleted() {
        guard !initialSyncCompleted else { return }
        
        initialSyncCompleted = true
        print("[ClaimSync] ✅ Sincronizzazione iniziale completata - EmailQueueService può processare")
        
        // Notifica tutti i listener in attesa
        for continuation in initialSyncContinuations {
            continuation.resume()
        }
        initialSyncContinuations.removeAll()
    }
    
    /// Attende che la sincronizzazione iniziale sia completata
    /// Usato da EmailQueueService per attendere prima di processare le email
    /// - Parameter timeout: Timeout in secondi (default 30s)
    /// - Returns: true se la sync è completata, false se timeout
    func waitForInitialSync(timeout: TimeInterval = 30) async -> Bool {
        // Se già completata, ritorna subito
        if initialSyncCompleted {
            return true
        }
        
        print("[ClaimSync] ⏳ In attesa della sincronizzazione iniziale...")
        
        // Usa withTaskGroup per gestire timeout
        return await withTaskGroup(of: Bool.self) { group in
            // Task 1: Attende la sincronizzazione
            group.addTask { @MainActor [weak self] in
                guard let self = self else { return false }
                
                // Se già completata, ritorna subito
                if self.initialSyncCompleted {
                    return true
                }
                
                // Altrimenti attendi usando continuation
                await withCheckedContinuation { continuation in
                    self.initialSyncContinuations.append(continuation)
                }
                
                return true
            }
            
            // Task 2: Timeout
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            
            // Prendi il primo risultato
            if let result = await group.next() {
                group.cancelAll()
                
                if !result {
                    print("[ClaimSync] ⚠️ Timeout attesa sincronizzazione iniziale (\(Int(timeout))s)")
                }
                
                return result
            }
            
            return false
        }
    }
    
    // MARK: - Background Sync
    
    /// Avvia il sync periodico in background per tutti i sinistri registrati
    /// Il timer viene avviato solo se l'agent è online e modalità file = locale
    func startBackgroundSync() {
        stopBackgroundSync()
        guard !isFileModeCloud else {
            print("[ClaimSync] ⏸️ Background sync non avviato: file gestiti da Hub")
            return
        }
        guard agentReachable else {
            print("[ClaimSync] ⏸️ Background sync non avviato: agent offline")
            return
        }
        
        backgroundSyncTimer = Timer.scheduledTimer(withTimeInterval: backgroundSyncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await CPUThrottler.shared.runWithThrottle { await self?.performBackgroundSync() }
            }
        }
        
        print("[ClaimSync] 🔄 Background sync avviato (ogni \(Int(backgroundSyncInterval))s)")
    }
    
    func stopBackgroundSync() {
        backgroundSyncTimer?.invalidate()
        backgroundSyncTimer = nil
    }
    
    /// Pausa tutte le sync temporanee quando l'app va in background
    func pauseAllTemporarySyncs() async {
        print("[ClaimSync] ⏸️ Pausa sync temporanee per background")
        stopBackgroundSync()
    }
    
    /// Ripristina le sync temporanee quando l'app torna in foreground
    func resumeTemporarySyncsIfNeeded() async {
        print("[ClaimSync] ▶️ Ripristino sync temporanee per foreground")
        await refreshAgentStatus()
        if agentReachable && backgroundSyncTimer == nil {
            startBackgroundSync()
        }
    }
    
    /// Esegue sync differenziale per tutti i sinistri registrati
    private func performBackgroundSync() async {
        if isFileModeCloud { return }
        await refreshAgentStatus()
        guard agentReachable else { return }
        
        // 0) Nuovi sinistri "Da scaricare" → avvia download automatico in background
        await scanAndStartPendingDownloads()
        
        // 0.5) Esegui cleanup periodico (ogni 6 ore circa, basato su backgroundSyncInterval)
        // Controlla se è passato abbastanza tempo dall'ultimo cleanup
        let lastCleanupKey = "syncAgent.lastCleanupScan"
        let lastCleanup = UserDefaults.standard.object(forKey: lastCleanupKey) as? Date ?? Date.distantPast
        let hoursSinceLastCleanup = Date().timeIntervalSince(lastCleanup) / 3600
        
        if hoursSinceLastCleanup >= 6 {
            await performTemporarySyncCleanup()
            UserDefaults.standard.set(Date(), forKey: lastCleanupKey)
        }

        let riferimenti = Array(statuses.keys)
        guard !riferimenti.isEmpty else { return }
        
        // Filtra sinistri sospesi e aggiungi quelli con sync temporanea
        let activeRiferimenti = riferimenti.filter { !suspendedClaims.contains($0) }
        let temporaryRiferimenti = Array(temporarySyncClaims.keys)
        let allActiveRiferimenti = Set(activeRiferimenti + temporaryRiferimenti)
        guard !allActiveRiferimenti.isEmpty else { return }
        
        // Filtra sinistri chiusi dal background sync (per loro facciamo solo upload, no download automatico)
        let closedRiferimenti = Set(allActiveRiferimenti.filter { riferimento in
            guard let sinistro = fetchSinistro(by: riferimento) else { return false }
            return isSinistroInTerminalState(sinistro)
        })
        
        let riferimentiForBackgroundSync = allActiveRiferimenti.filter { !closedRiferimenti.contains($0) }
        
        print("[ClaimSync] 🔄 Background sync per \(riferimentiForBackgroundSync.count) sinistri attivi (upload per \(closedRiferimenti.count) sinistri chiusi)...")
        
        // Sync completo (upload + download) per sinistri attivi
        for riferimento in riferimentiForBackgroundSync {
            // Skip se già in sync attivo
            if statuses[riferimento]?.isActive == true { continue }
            
            // Sync silenzioso (non mostra stati intermedi)
            await backgroundSyncSinistro(riferimento: riferimento)
        }
        
        // Solo upload per sinistri chiusi (no download automatico)
        for riferimento in closedRiferimenti {
            // Skip se già in sync attivo
            if statuses[riferimento]?.isActive == true { continue }
            
            // Solo upload, no download
            if let sinistro = fetchSinistro(by: riferimento),
               fileService.getSinistroPath(riferimento: riferimento) != nil {
                await uploadChangedFiles(for: sinistro, skipHealthCheck: true, isBackgroundSync: true)
            }
        }
        
        lastBackgroundSync = Date()
    }
    
    /// Sync silenzioso di un singolo sinistro (usato per background)
    private func backgroundSyncSinistro(riferimento: String) async {
        do {
            let metadata = try await apiClient.fetchMetadata(claimId: riferimento, userId: currentUserId())
            
            guard let sinistro = fetchSinistro(by: riferimento) else { return }
            let isClosed = isSinistroInTerminalState(sinistro)
            let isPending = isPendingDeletion(riferimento: riferimento)
            
            // 1) Upload modifiche locali (locale → server) - sempre, anche per sinistri chiusi o in lista eliminazione
            if fileService.getSinistroPath(riferimento: riferimento) != nil {
                await uploadChangedFiles(for: sinistro, skipHealthCheck: true, isBackgroundSync: true)
            }
            
            // 2) Download automatico: solo se il sinistro NON è chiuso e NON è in lista eliminazione
            // Per sinistri chiusi o in attesa di eliminazione, facciamo solo push (upload)
            if isClosed || isPending {
                print("[ClaimSync] ⏭️ Sinistro \(riferimento) in modalità push-only (chiuso: \(isClosed), in eliminazione: \(isPending))")
                return
            }
            
            // Se ci sono file nel manifest, verifica differenze
            if let remoteFiles = metadata.files, !remoteFiles.isEmpty {
                let localPath = fileService.getSinistroPath(riferimento: riferimento) ?? buildLocalPath(for: riferimento)
                let baseForAccess = securityScopedBase(for: localPath)
                let localHashes = computeLocalFileHashes(in: localPath, activeDirectory: baseForAccess)
                
                // Trova file nuovi dal server
                var newFilesFromServer: [ClaimFileEntry] = []
                for remoteFile in remoteFiles {
                    // Escludi file di sistema dalla sincronizzazione
                    if shouldExcludeFile(remoteFile.relativePath) {
                        continue
                    }
                    
                    let localFilePath = (localPath as NSString).appendingPathComponent(remoteFile.relativePath)
                    if localHashes[remoteFile.relativePath] == nil && !FileManager.default.fileExists(atPath: localFilePath) {
                        newFilesFromServer.append(remoteFile)
                    }
                }
                
                if !newFilesFromServer.isEmpty {
                    print("[ClaimSync] 📥 \(riferimento): rilevati \(newFilesFromServer.count) nuovi file dal server")
                    
                    // Scarica i file (le notifiche verranno inviate automaticamente alla fine del download)
                    try await downloadDifferential(metadata: metadata, riferimento: riferimento, isNewDownload: false, isBackgroundSync: true)
                }
            }
        } catch let error as URLError where error.code == .timedOut {
            // Timeout: log dettagliato ma non blocca (il retry è già gestito in APIClient)
            let failingURL = (error as NSError).userInfo["NSErrorFailingURLKey"] as? URL
            print("[ClaimSync] ⚠️ Background sync \(riferimento) timeout: \(error.localizedDescription)")
            if let url = failingURL {
                print("[ClaimSync]   URL: \(url.absoluteString)")
            }
        } catch {
            // Altri errori: log e ignora nel background sync
            print("[ClaimSync] ⚠️ Background sync \(riferimento) fallito: \(error.localizedDescription)")
        }
    }

    /// Scansiona periodicamente i sinistri in stato "Da scaricare" e avvia download automatico (anche senza aprire la UI).
    private func scanAndStartPendingDownloads() async {
        guard agentReachable else { return }

        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "stato == %@", StatoManager.StatoSinistro.daScaricare.descrizione)

        guard let sinistri = try? context.fetch(request), !sinistri.isEmpty else { return }

        for sinistro in sinistri {
            guard let rif = sinistro.riferimento else { continue }
            if suspendedClaims.contains(rif) { continue }
            if statuses[rif]?.isActive == true { continue }
            if fileService.getSinistroPath(riferimento: rif) != nil { continue } // già presente

            await registerAndSyncIfNeeded(sinistro: sinistro, forceDownload: true)
        }
    }
    
    /// Invia notifica finale dopo il completamento del download
    private func sendFinalDownloadNotification(riferimento: String, newFiles: [String], modifiedFiles: [String]) async {
        guard let sinistro = fetchSinistro(by: riferimento) else { return }
        
        // Filtra i file per escludere quelli generati o caricati dall'utente dalle notifiche/badge
        let filteredNewFiles = newFiles.filter { !isNotificationExcluded($0) }
        let filteredModifiedFiles = modifiedFiles.filter { !isNotificationExcluded($0) }
        
        // Verifica se il sinistro è assegnato all'utente corrente prima di inviare notifiche
        guard shouldMonitorSinistro(sinistro) else {
            print("[ClaimSync] ⏭️ Sinistro \(riferimento) non assegnato all'utente, skip notifiche")
            return
        }
        
        // Registra comunque tutti i file nel tracker (per evidenziarli in UI se l'utente apre la cartella)
        Task { @MainActor in
            if !newFiles.isEmpty {
                NewFilesTracker.shared.markAsNew(riferimento: riferimento, relativePaths: newFiles)
            }
            if !modifiedFiles.isEmpty {
                NewFilesTracker.shared.markAsModified(riferimento: riferimento, relativePaths: modifiedFiles)
            }
        }
        
        // Se non ci sono file rilevanti dopo il filtraggio, non inviare notifiche né badge
        guard !filteredNewFiles.isEmpty || !filteredModifiedFiles.isEmpty else {
            print("[ClaimSync] ⏭️ Solo file esclusi (generati/utente), skip notifiche/badge per \(riferimento)")
            return
        }
        
        // Prepara messaggio notifica usando i file filtrati
        var notificationBody: String = ""
        var totalCount = 0
        
        if !filteredNewFiles.isEmpty {
            totalCount += filteredNewFiles.count
            if filteredNewFiles.count <= 2 {
                // Mostra i nomi se sono 1-2 file
                let fileNames = filteredNewFiles.map { URL(fileURLWithPath: $0).lastPathComponent }
                notificationBody = "Scaricato: \(fileNames.joined(separator: ", "))"
            } else {
                // Mostra conteggio se sono tanti
                notificationBody = "Scaricati \(filteredNewFiles.count) nuovi elementi"
            }
        }
        
        if !filteredModifiedFiles.isEmpty {
            if !notificationBody.isEmpty {
                notificationBody += "\n"
            }
            if filteredModifiedFiles.count <= 2 {
                let fileNames = filteredModifiedFiles.map { URL(fileURLWithPath: $0).lastPathComponent }
                notificationBody += "Aggiornato: \(fileNames.joined(separator: ", "))"
            } else {
                notificationBody += "Aggiornati \(filteredModifiedFiles.count) elementi"
            }
        }
        
        // Invia notifica push
        NotificationService.shared.sendNotification(
            title: "Sincronizzazione completata - \(sinistro.riferimento ?? "Sinistro")",
            body: notificationBody,
            userInfo: [
                "riferimento": riferimento,
                "type": "sync_completed",
                "newCount": filteredNewFiles.count,
                "modifiedCount": filteredModifiedFiles.count
            ]
        )
        
        // Aggiungi notifica per la sezione Cartella
        NotificationCenter.default.post(
            name: .newFilesDownloaded,
            object: nil,
            userInfo: [
                "riferimento": riferimento,
                "count": filteredNewFiles.count,
                "files": filteredNewFiles
            ]
        )
        
        // Crea task "Verificare nuova documentazione" solo se ci sono file nuovi rilevanti
        if !filteredNewFiles.isEmpty {
            let fileNames = filteredNewFiles.prefix(3).map { URL(fileURLWithPath: $0).lastPathComponent }
            let fileList = fileNames.joined(separator: ", ")
            let suffix = filteredNewFiles.count > 3 ? " e altri \(filteredNewFiles.count - 3)" : ""
            
            TaskManager.shared.createDocumentationVerificationTask(
                sinistro: sinistro,
                description: "Nuovi file ricevuti: \(fileList)\(suffix)"
            )
            
            print("[ClaimSync] 📋 Creato task 'Verificare nuova documentazione' per \(riferimento)")
        }
    }
    
    /// Gestisce l'arrivo di nuovi file dal server: notifica + task
    /// DEPRECATO: ora le notifiche vengono inviate alla fine del download in sendFinalDownloadNotification
    private func handleNewFilesFromServer(riferimento: String, newFiles: [ClaimFileEntry], sinistro: Sinistro) async {
        // Questa funzione non viene più usata per le notifiche, ma manteniamo per compatibilità
        // Le notifiche vengono ora inviate alla fine del download
        guard !newFiles.isEmpty else { return }
        
        // Verifica se il sinistro è assegnato all'utente corrente
        guard shouldMonitorSinistro(sinistro) else {
            print("[ClaimSync] ⏭️ Sinistro \(riferimento) non assegnato all'utente, skip")
            return
        }
        
        let relativePaths = newFiles.map { $0.relativePath }
        
        // Registra i file nuovi nel tracker (le notifiche verranno inviate alla fine del download)
        Task { @MainActor in
            NewFilesTracker.shared.markAsNew(riferimento: riferimento, relativePaths: relativePaths)
        }
    }
    
    // MARK: - Registrazione Automatica
    
    /// Registra tutti i sinistri assegnati all'utente corrente presso l'agent
    func registerAllAssignedClaims() async {
        guard agentReachable else {
            print("[ClaimSync] ⚠️ Agent non raggiungibile, skip registrazione automatica")
            return
        }
        
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        
        // Filtra: sinistri assegnati all'utente, NON in stati terminali
        let terminalStates = [
            StatoManager.StatoSinistro.chiusa.descrizione,
            StatoManager.StatoSinistro.revocata.descrizione,
            StatoManager.StatoSinistro.annullata.descrizione
        ]
        request.predicate = NSPredicate(format: "NOT (stato IN %@)", terminalStates)
        
        guard let allSinistri = try? context.fetch(request) else { return }
        
        // Filtra solo quelli assegnati all'utente corrente
        let sinistri = allSinistri.filter { shouldMonitorSinistro($0) }
        
        print("[ClaimSync] 📋 Registrazione automatica di \(sinistri.count) sinistri assegnati all'utente...")
        
        for sinistro in sinistri {
            guard let riferimento = sinistro.riferimento else { continue }
            
            // Registra solo se non già registrato
            if statuses[riferimento] == nil || statuses[riferimento] == .notDownloaded {
                do {
                    // path_hint = nil → il server determina il path dal claim_id
                    // NON passare mai il path locale!
                    let req = RegisterMonitoringRequest(
                        user_id: currentUserId(),
                        claim_id: riferimento,
                        path_hint: nil
                    )
                    let _: GenericAPIResponse = try await apiClient.post("/api/monitoring/register", body: req)
                    
                    // Determina lo stato iniziale
                    if fileService.getSinistroPath(riferimento: riferimento) != nil {
                        setStatus(.upToDate, for: riferimento)
                    } else {
                        setStatus(.notDownloaded, for: riferimento)
                    }
                } catch {
                    // Non bloccare per errori singoli
                    print("[ClaimSync] ⚠️ Errore registrazione \(riferimento): \(error.localizedDescription)")
                }
            }
        }
        
        print("[ClaimSync] ✅ Registrazione automatica completata")
    }
    
    /// Registra un nuovo sinistro appena creato
    func registerNewClaim(riferimento: String) async {
        guard agentReachable else { return }
        
        print("[ClaimSync] 📝 Registrazione nuovo sinistro: \(riferimento)")
        
        do {
            // path_hint = nil → il server determina il path dal claim_id
            let req = RegisterMonitoringRequest(
                user_id: currentUserId(),
                claim_id: riferimento,
                path_hint: nil
            )
            let _: GenericAPIResponse = try await apiClient.post("/api/monitoring/register", body: req)
            setStatus(.notDownloaded, for: riferimento)
            print("[ClaimSync] ✅ Sinistro \(riferimento) registrato con successo")
        } catch {
            print("[ClaimSync] ⚠️ Errore registrazione nuovo sinistro \(riferimento): \(error.localizedDescription)")
        }
    }

    // MARK: - Upload immediato file di chiusura
    
    /// Upload immediato dei file generati in "Da Chiudere" (priorità alta).
    /// Mantiene struttura 1:1 usando filename=relativePath nel multipart.
    func uploadClosureFilesImmediately(riferimento: String, fileURLs: [URL]) async {
        guard !fileURLs.isEmpty else { return }
        
        await refreshAgentStatus()
        guard agentReachable else {
            setStatus(.error("Agent non raggiungibile"), for: riferimento)
            return
        }
        
        guard let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) else { return }
        
        // Assicura monitoring (idempotente)
        do {
            let req = RegisterMonitoringRequest(user_id: currentUserId(), claim_id: riferimento, path_hint: nil)
            let _: GenericAPIResponse = try await apiClient.post("/api/monitoring/register", body: req)
        } catch {
            logNetworkError(error, context: "uploadClosureFilesImmediately register")
        }
        
        // Prepara tuple (url, relativePath) e directory da creare
        let tuples: [(url: URL, relativePath: String)] = fileURLs.map { url in
            let rel = url.path.replacingOccurrences(of: sinistroPath + "/", with: "")
            return (url: url, relativePath: rel)
        }
        
        let dirs: [String] = Array(
            Set(
                tuples
                    .map { $0.relativePath }
                    .map { ( $0 as NSString).deletingLastPathComponent }
                    .filter { !$0.isEmpty && $0 != "." }
            )
        )
        if !dirs.isEmpty {
            await syncDirectoriesToServer(claimId: riferimento, directories: dirs)
        }
        
        // Leggi i file dentro security-scoped access
        let baseForAccess = securityScopedBase(for: sinistroPath)
        typealias UploadItem = (data: Data, relativePath: String)
        
        func readFiles() -> [UploadItem] {
            var items: [UploadItem] = []
            for (url, relativePath) in tuples {
                guard let data = try? Data(contentsOf: url) else {
                    print("[ClaimSync] ⚠️ Impossibile leggere file: \(url.path)")
                    continue
                }
                items.append((data: data, relativePath: relativePath))
            }
            return items
        }
        
        let filesToUpload: [UploadItem] = !baseForAccess.isEmpty
            ? fileService.performWithSecurityScopedAccess(to: baseForAccess, operation: readFiles) ?? []
            : readFiles()
        
        guard !filesToUpload.isEmpty else {
            setStatus(.error("Impossibile leggere i file per l'upload"), for: riferimento)
            return
        }
        
        setStatus(.uploadingFile(name: "", current: 0, total: filesToUpload.count), for: riferimento)
        
        do {
            let resp = try await apiClient.uploadFiles(
                claimId: riferimento,
                userId: currentUserId(),
                filesData: filesToUpload,
                progress: { [weak self] p in
                    MainActor.assumeIsolated { self?.setStatus(.uploading(progress: p), for: riferimento) }
                }
            )
            if resp.success {
                do { try await refreshManifest(for: riferimento) } catch { }
                setStatus(.upToDate, for: riferimento)
            } else {
                setStatus(.error(resp.message), for: riferimento)
            }
        } catch {
            logNetworkError(error, context: "uploadClosureFilesImmediately upload")
            setStatus(.error(error.localizedDescription), for: riferimento)
        }
    }

    private func logNetworkError(_ error: Error, context: String) {
        let ns = error as NSError
        var parts: [String] = []
        parts.append("[SyncAgent] ❌ \(context)")
        parts.append("domain=\(ns.domain) code=\(ns.code)")
        if let failingURL = ns.userInfo["NSErrorFailingURLKey"] as? URL {
            parts.append("url=\(failingURL.absoluteString)")
        }
        if let failingStr = ns.userInfo["NSErrorFailingURLStringKey"] as? String {
            parts.append("urlStr=\(failingStr)")
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain) \(underlying.code)")
        }
        print(parts.joined(separator: " | "))
    }

    // MARK: - Health Check
    
    /// Verifica raggiungibilità agent - GET /health
    func refreshAgentStatus() async {
        let (reachable, _) = await apiClient.checkHealth()
        let wasReachable = agentReachable
        agentReachable = reachable
        
        // Se l'agent è tornato online e il timer non è attivo, riavvia il background sync
        if reachable && !wasReachable && backgroundSyncTimer == nil {
            print("[ClaimSync] ✅ Agent tornato online, riavvio background sync")
            startBackgroundSync()
        }
        
        // Se l'agent è andato offline, ferma il timer
        if !reachable && wasReachable {
            print("[ClaimSync] ⚠️ Agent andato offline, fermo background sync")
            stopBackgroundSync()
        }
    }

    // MARK: - Public API

    func status(for sinistro: Sinistro) -> ClaimSyncStatus {
        guard let riferimento = sinistro.riferimento else { return .notDownloaded }
        
        // Se abbiamo uno status tracciato, restituiscilo
        if let trackedStatus = statuses[riferimento] {
            return trackedStatus
        }
        
        // Se la cartella esiste localmente ma non abbiamo status tracciato
        if fileService.getSinistroPath(riferimento: riferimento) != nil {
            // Verifica se è stata mai sincronizzata
            if isFirstSyncCompleted(for: riferimento) {
                return .upToDate
            } else {
                return .notSynced
            }
        }
        
        return .notDownloaded
    }
    
    /// Verifica se la prima sincronizzazione è stata completata per un sinistro
    private func isFirstSyncCompleted(for riferimento: String) -> Bool {
        UserDefaults.standard.bool(forKey: firstSyncCompletedKeyPrefix + riferimento)
    }
    
    /// Marca la prima sincronizzazione come completata
    private func markFirstSyncCompleted(for riferimento: String) {
        UserDefaults.standard.set(true, forKey: firstSyncCompletedKeyPrefix + riferimento)
    }

    func ensureMonitoringForActiveTask(sinistroID: String) async {
        if isFileModeCloud { return }
        guard let sinistro = fetchSinistro(by: sinistroID) else { return }
        await registerAndSyncIfNeeded(sinistro: sinistro, forceDownload: true)
    }

    func finalizeAfterTasks(sinistroID: String) async {
        if isFileModeCloud { return }
        guard let sinistro = fetchSinistro(by: sinistroID) else { return }
        await uploadChangedFiles(for: sinistro)
        await performScheduledCleanup()
    }

    func removeLocal(for sinistro: Sinistro) async {
        guard let rif = sinistro.riferimento else { return }
        await removeLocalFolderAndUnregister(sinistroID: rif)
    }
    
    /// Elimina SOLO la cartella locale, senza toccare il server
    func deleteLocalFolderOnly(for sinistro: Sinistro) async {
        guard let rif = sinistro.riferimento else { return }
        
        // Elimina solo la cartella locale (non tocca il server)
        if let path = fileService.getSinistroPath(riferimento: rif) {
            let baseForAccess = securityScopedBase(for: path)
            if !baseForAccess.isEmpty {
                _ = fileService.performWithSecurityScopedAccess(to: baseForAccess) { () -> Bool in
                    try? FileManager.default.removeItem(atPath: path)
                    print("[ClaimSync] 🗑️ Cartella locale eliminata (server non toccato): \(path)")
                    return true
                }
            } else {
                try? FileManager.default.removeItem(atPath: path)
                print("[ClaimSync] 🗑️ Cartella locale eliminata (server non toccato): \(path)")
            }
        }
        
        // Rimuovi dallo stato
        statuses.removeValue(forKey: rif)
        let hasActive = statuses.values.contains { $0.isActive }
        sleepManager.update(shouldPreventSleep: hasActive)
        
        // Notifica la UI
        NotificationCenter.default.post(name: .claimFolderChanged, object: nil, userInfo: ["riferimento": rif])
    }

    func manualDownload(for sinistro: Sinistro) async {
        await registerAndSyncIfNeeded(sinistro: sinistro, forceDownload: true)
        
        // Se il sinistro è in stato terminale, traccialo come "manuale"
        // per la cancellazione automatica dopo 3 giorni se lo stato non cambia
        if let riferimento = sinistro.riferimento,
           let stato = sinistro.stato {
            let terminalStates = [
                StatoManager.StatoSinistro.chiusa.descrizione,
                StatoManager.StatoSinistro.revocata.descrizione,
                StatoManager.StatoSinistro.annullata.descrizione
            ]
            if terminalStates.contains(stato) {
                trackManuallyAddedClaim(riferimento: riferimento, currentState: stato)
            }
        }
    }
    
    /// Interrompe la sincronizzazione e schedula la cancellazione della cartella
    func stopSyncAndScheduleDeletion(riferimento: String) async {
        print("[ClaimSync] ⏹️ Interruzione sincronizzazione per \(riferimento)")
        
        // Cancella eventuale download ZIP in corso (altrimenti i callback continuano e la UI resta "in download")
        apiClient.cancelDownload(claimId: riferimento)
        
        // 1. Imposta stato error per interrompere eventuali download in corso
        setStatus(.error("Sincronizzazione interrotta"), for: riferimento)
        
        // 2. Disiscrivi dal monitoring
        do {
            let req = RegisterMonitoringRequest(user_id: currentUserId(), claim_id: riferimento, path_hint: nil)
            let _: GenericAPIResponse = try await apiClient.post("/api/monitoring/unregister", body: req)
            print("[ClaimSync] ✅ Sinistro \(riferimento) rimosso dal monitoring")
        } catch {
            print("[ClaimSync] ⚠️ Errore rimozione dal monitoring: \(error.localizedDescription)")
        }
        
        // 3. Traccia come manuale per cancellazione dopo 3 giorni
        if let sinistro = fetchSinistro(by: riferimento) {
            trackManuallyAddedClaim(riferimento: riferimento, currentState: sinistro.stato ?? "")
        } else {
            // Se il sinistro non esiste nel DB, schedula comunque la cancellazione
            trackManuallyAddedClaim(riferimento: riferimento, currentState: "Sconosciuto")
        }
        
        // 4. Rimuovi dalla lista degli stati attivi
        statuses.removeValue(forKey: riferimento)
        let hasActive = statuses.values.contains { $0.isActive }
        sleepManager.update(shouldPreventSleep: hasActive)
    }
    
    // MARK: - Sync Suspension
    
    /// Verifica se la sincronizzazione è sospesa per un sinistro
    func isSyncSuspended(for sinistro: Sinistro) -> Bool {
        guard let rif = sinistro.riferimento else { return false }
        return suspendedClaims.contains(rif)
    }
    
    /// Sospende la sincronizzazione automatica per un sinistro (mantiene la cartella locale)
    func suspendSync(for riferimento: String) {
        suspendedClaims.insert(riferimento)
        saveSuspendedClaims()
        
        // Rimuovi dal monitoring ma non eliminare nulla
        Task {
            do {
                let req = RegisterMonitoringRequest(user_id: currentUserId(), claim_id: riferimento, path_hint: nil)
                let _: GenericAPIResponse = try await apiClient.post("/api/monitoring/unregister", body: req)
                print("[ClaimSync] ⏸️ Sync sospesa per \(riferimento)")
            } catch {
                print("[ClaimSync] ⚠️ Errore sospensione sync \(riferimento): \(error.localizedDescription)")
            }
        }
        
        statuses.removeValue(forKey: riferimento)
    }
    
    /// Riattiva la sincronizzazione automatica per un sinistro
    func resumeSync(for riferimento: String) async {
        suspendedClaims.remove(riferimento)
        saveSuspendedClaims()
        
        print("[ClaimSync] ▶️ Sync riattivata per \(riferimento)")
        
        cancelPendingDeletion(riferimento: riferimento)
        
        if let sinistro = fetchSinistro(by: riferimento) {
            await registerAndSyncIfNeeded(sinistro: sinistro, forceDownload: false)
        }
    }
    
    /// Interrompe la sincronizzazione e rimuove la cartella locale
    func stopSyncAndRemoveFolder(riferimento: String) async {
        print("[ClaimSync] 🗑️ Interruzione sync e rimozione cartella per \(riferimento)")
        
        // Rimuovi dalla lista sospesi se presente
        suspendedClaims.remove(riferimento)
        saveSuspendedClaims()
        
        // Rimuovi cartella e disiscrivi
        await removeLocalFolderAndUnregister(sinistroID: riferimento)
    }
    
    /// Sincronizza e poi sospende (usato quando sinistro passa a chiuso)
    func syncThenSuspendAndScheduleDeletion(riferimento: String) async {
        print("[ClaimSync] 🔄 Sync finale prima di sospensione per \(riferimento)")
        
        // 1. Esegui sync per caricare eventuali modifiche locali
        if let sinistro = fetchSinistro(by: riferimento) {
            await registerAndSyncIfNeeded(sinistro: sinistro, forceDownload: false)
        }
        
        // 2. Sospendi la sync
        suspendSync(for: riferimento)
        
        // 3. Schedula per la rimozione normale (usa il sistema esistente per sinistri chiusi)
        trackManuallyAddedClaim(riferimento: riferimento, currentState: StatoManager.StatoSinistro.chiusa.descrizione)
    }
    
    private func saveSuspendedClaims() {
        UserDefaults.standard.set(Array(suspendedClaims), forKey: suspendedSyncKey)
    }

    // MARK: - Core Flow

    /// Avvia il download immediato della cartella di un sinistro (no-op se file gestiti da Hub)
    func downloadClaimFolder(riferimento: String) async {
        if isFileModeCloud { return }
        guard let sinistro = fetchSinistro(by: riferimento) else {
            print("[ClaimSync] ⚠️ Impossibile avviare download: sinistro \(riferimento) non trovato in DB")
            return
        }
        await registerAndSyncIfNeeded(sinistro: sinistro, forceDownload: true)
    }

    private func registerAndSyncIfNeeded(sinistro: Sinistro, forceDownload: Bool) async {
        guard let riferimento = sinistro.riferimento else { return }
        if isFileModeCloud { return }
        
        // Annulla la cancellazione programmata solo in caso di riscaricamento manuale esplicito
        if forceDownload {
            cancelPendingDeletion(riferimento: riferimento)
        }
        
        // Health check prima di procedere
        await refreshAgentStatus()
        guard agentReachable else {
            setStatus(.error("Agent non raggiungibile"), for: riferimento)
            return
        }
        
        // Se la sync è sospesa per questo sinistro, non fare nulla
        if suspendedClaims.contains(riferimento) {
            statuses.removeValue(forKey: riferimento)
            return
        }
        
        setStatus(.registering, for: riferimento)
        do {
            // path_hint = nil → il server determina il path dal claim_id
            let req = RegisterMonitoringRequest(user_id: currentUserId(), claim_id: riferimento, path_hint: nil)
            let _: GenericAPIResponse = try await apiClient.post("/api/monitoring/register", body: req)

            // GET /api/claims/{claim_id}/metadata
            setStatus(.fetchingMetadata, for: riferimento)
            let metadata = try await apiClient.fetchMetadata(claimId: riferimento, userId: currentUserId())

            let localFolderExists = fileService.getSinistroPath(riferimento: riferimento) != nil
            let isNewDownload = !localFolderExists || !isFirstSyncCompleted(for: riferimento)
            
            detectRemoteChanges(metadata: metadata, isNewDownload: isNewDownload)

            // Determina strategia di sync
            let path = fileService.getSinistroPath(riferimento: riferimento)
            var deletedPaths: Set<String> = []
            var alreadyUploadedPaths: Set<String> = []
            if let folderPath = path, localFolderExists, let remoteFiles = metadata.files, !remoteFiles.isEmpty {
                let (del, moved) = await syncDeletionsAndMoves(metadata: metadata, destinationPath: folderPath, riferimento: riferimento)
                deletedPaths = del
                alreadyUploadedPaths = moved
            }
            if let remoteFiles = metadata.files, !remoteFiles.isEmpty {
                // Download differenziale: scarica solo file mancanti, preserva file locali
                // (funziona sia per cartelle nuove che esistenti - es. scaricate manualmente)
                try await downloadDifferential(metadata: metadata, riferimento: riferimento, isNewDownload: isNewDownload, deletedPaths: deletedPaths)
            } else if localFolderExists {
                // Cartella esiste già e server non ha manifest dettagliato → già sincronizzata
                print("[ClaimSync] ✅ Cartella \(riferimento) già presente, nessun manifest dettagliato → up-to-date")
                setStatus(.upToDate, for: riferimento)
                if !isFirstSyncCompleted(for: riferimento) {
                    markFirstSyncCompleted(for: riferimento)
                }
            } else if forceDownload || !localFolderExists {
                // Fallback: download pacchetto ZIP SOLO se cartella non esiste
                try await downloadPackage(metadata: metadata, riferimento: riferimento, isNewDownload: isNewDownload)
            }
            
            // Upload modifiche locali (se la cartella esiste)
            // Nota: prima sistemiamo la parte download/manifest, poi carichiamo eventuali file nuovi/modificati.
            if fileService.getSinistroPath(riferimento: riferimento) != nil {
                await uploadChangedFiles(for: sinistro, alreadyUploadedPaths: alreadyUploadedPaths)
            }
            
            scheduleFallbackDownloadCheck(riferimento: riferimento)
        } catch {
            logNetworkError(error, context: "registerAndSyncIfNeeded")
            setStatus(.error(error.localizedDescription), for: riferimento)
        }
    }

    // MARK: - Delete / Move (prima del download)
    
    /// Eliminazioni locali → DELETE su server; spostamenti → DELETE vecchio + upload nuovo.
    /// Ritorna (path eliminati, path già caricati come move target) per evitare re-download e re-upload.
    private func syncDeletionsAndMoves(metadata: ClaimMetadata, destinationPath: String, riferimento: String) async -> (deletedPaths: Set<String>, moveTargetPaths: Set<String>) {
        let cache = loadLocalManifest(for: riferimento)
        let lastList = cache?.localSnapshot ?? []
        guard !lastList.isEmpty else { return ([], []) }
        let baseForAccess = securityScopedBase(for: destinationPath)
        let lastMap = Dictionary(uniqueKeysWithValues: lastList.map { ($0.relativePath, $0.md5) })
        let currentHashes = computeLocalFileHashes(in: destinationPath, activeDirectory: baseForAccess)
        var deleted = Set(lastMap.keys.filter { !currentHashes.keys.contains($0) })
        var newLocal = Set(currentHashes.keys.filter { !lastMap.keys.contains($0) })
        var moves: [(String, String)] = []
        for old in deleted {
            guard let h = lastMap[old] else { continue }
            guard let match = newLocal.first(where: { currentHashes[$0] == h }) else { continue }
            moves.append((old, match))
            newLocal.remove(match)
        }
        let moveSources = Set(moves.map(\.0))
        var pureDeletes = deleted
        pureDeletes.subtract(moveSources)
        let toDelete = pureDeletes.union(moveSources)
        for rel in toDelete {
            if shouldExcludeFile(rel) { continue }
            do {
                _ = try await apiClient.deleteFile(claimId: riferimento, userId: currentUserId(), relativePath: rel)
                print("[ClaimSync] 🗑 Eliminato su server (sync): \(rel)")
            } catch {
                print("[ClaimSync] ⚠️ DELETE \(rel) fallito: \(error.localizedDescription)")
            }
        }
        var moveTargetPaths = Set<String>()
        for (_, newPath) in moves {
            if shouldExcludeFile(newPath) { continue }
            let full = (destinationPath as NSString).appendingPathComponent(newPath)
            let url = URL(fileURLWithPath: full)
            guard FileManager.default.fileExists(atPath: full) else { continue }
            do {
                let res = try await apiClient.uploadFiles(claimId: riferimento, userId: currentUserId(), files: [(url: url, relativePath: newPath)]) { _ in }
                if res.success {
                    moveTargetPaths.insert(newPath)
                    print("[ClaimSync] 📁 Spostamento sincronizzato: → \(newPath)")
                }
            } catch {
                print("[ClaimSync] ⚠️ Upload move target \(newPath) fallito: \(error.localizedDescription)")
            }
        }
        return (toDelete, moveTargetPaths)
    }

    // MARK: - Download Differenziale (file per file)
    
    /// Download differenziale che:
    /// - Conflitto: vince la versione con data modifica più recente; la precedente va in versioning
    /// - NON elimina file locali che non esistono sul server
    /// - Crea cartelle vuote dal server
    private func downloadDifferential(metadata: ClaimMetadata, riferimento: String, isNewDownload: Bool, isBackgroundSync: Bool = false, deletedPaths: Set<String> = []) async throws {
        guard let remoteFiles = metadata.files else { return }
        
        // In background sync non mostriamo stati intermedi
        if !isBackgroundSync {
            setStatus(.comparing, for: riferimento)
        }
        
        let destinationPath = fileService.getSinistroPath(riferimento: riferimento) ?? buildLocalPath(for: riferimento)
        print("[ClaimSync] 📂 Download differenziale in: \(destinationPath)")
        
        let baseForAccess = securityScopedBase(for: destinationPath)
        
        // Crea directory principale con security-scoped access se necessario
        createDirectoryWithAccess(at: destinationPath, activeDirectory: baseForAccess)
        
        // Inizializza cache interna (versioning/cestino) del sinistro
        FileVersioningService.shared.ensureCacheStructure(for: destinationPath)
        
        // Crea anche le sottocartelle vuote dal server (se presenti nel metadata)
        if let directories = metadata.directories {
            for dir in directories {
                let dirPath = (destinationPath as NSString).appendingPathComponent(dir)
                createDirectoryWithAccess(at: dirPath, activeDirectory: baseForAccess)
            }
        }
        
        // Calcola hash dei file locali esistenti fisicamente
        let localFileHashes = computeLocalFileHashes(in: destinationPath, activeDirectory: baseForAccess)
        
        // Determina quali file scaricare:
        // - File che non esistono localmente
        // - NON scarichiamo file che esistono localmente anche se hash diverso (gestione conflitto)
        var filesToDownload: [ClaimFileEntry] = []
        var conflictFiles: [ClaimFileEntry] = []
        
        for remoteFile in remoteFiles {
            // Escludi file di sistema dalla sincronizzazione
            if shouldExcludeFile(remoteFile.relativePath) {
                continue
            }
            if deletedPaths.contains(remoteFile.relativePath) {
                continue
            }
            
            let localPath = (destinationPath as NSString).appendingPathComponent(remoteFile.relativePath)
            
            if let localHash = localFileHashes[remoteFile.relativePath] {
                // File esiste localmente
                if localHash != remoteFile.md5 {
                    // Conflitto: hash diversi - NON sovrascriviamo, segniamo per gestione speciale
                    conflictFiles.append(remoteFile)
                    print("[ClaimSync] ⚠️ Conflitto rilevato: \(remoteFile.relativePath) (locale diverso da server)")
                }
                // Se hash uguale, file già sincronizzato - skip
            } else if !FileManager.default.fileExists(atPath: localPath) {
                // File non esiste localmente - da scaricare
                filesToDownload.append(remoteFile)
            }
        }
        
        print("[ClaimSync] 📊 File da scaricare: \(filesToDownload.count), conflitti: \(conflictFiles.count)")
        
        var keptLocalOverrides: [String: ClaimFileEntry] = [:]
        
        // Traccia quali file sono modificati (da conflitti) vs nuovi
        var modifiedFiles: Set<String> = []
        
        // Gestisci conflitti: data più recente vince, la precedente va in versioning (niente _local)
        for conflictFile in conflictFiles {
            let localPath = (destinationPath as NSString).appendingPathComponent(conflictFile.relativePath)
            let localURL = URL(fileURLWithPath: localPath)
            guard let localEntry = localFileEntry(relativePath: conflictFile.relativePath, basePath: destinationPath, activeDirectory: baseForAccess) else {
                print("[ClaimSync] ⚠️ Impossibile leggere file locale per conflitto, uso server: \(conflictFile.relativePath)")
                filesToDownload.append(conflictFile)
                modifiedFiles.insert(conflictFile.relativePath)
                _ = FileVersioningService.shared.createVersion(of: localURL, in: destinationPath, description: "Conflitto sincronizzazione")
                continue
            }
            let localMod = localEntry.modifiedAt
            let serverMod = conflictFile.modifiedAt
            let localWins: Bool
            if let l = localMod, let s = serverMod {
                localWins = l > s
            } else if localMod != nil {
                localWins = true
            } else if serverMod != nil {
                localWins = false
            } else {
                localWins = false
            }
            
            if localWins {
                // Mantieni locale; salva versione server in versioning (se disponibile)
                do {
                    let data = try await apiClient.downloadFile(claimId: riferimento, userId: currentUserId(), relativePath: conflictFile.relativePath)
                    let base = FileManager.default.temporaryDirectory.appendingPathComponent("perx_sync_conflict", isDirectory: true)
                    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                    let name = (conflictFile.relativePath as NSString).lastPathComponent
                    let tempURL = base.appendingPathComponent(name)
                    try? FileManager.default.removeItem(at: tempURL)
                    try data.write(to: tempURL)
                    _ = FileVersioningService.shared.createVersion(of: tempURL, in: destinationPath, description: "Conflitto sincronizzazione (server)")
                    try? FileManager.default.removeItem(at: tempURL)
                    keptLocalOverrides[conflictFile.relativePath] = localEntry
                    print("[ClaimSync] 📦 Conflitto \(conflictFile.relativePath): locale più recente, server in versioning")
                } catch {
                    // 404 o altro: server non ha il file (es. *_local, file rimosso). Mantieni locale, NON riscaricare.
                    _ = FileVersioningService.shared.createVersion(of: localURL, in: destinationPath, description: "Conflitto sincronizzazione")
                    keptLocalOverrides[conflictFile.relativePath] = localEntry
                    print("[ClaimSync] 📦 Conflitto \(conflictFile.relativePath): locale mantenuto (download server fallito, es. 404)")
                }
            } else {
                // Server vince: segna come modificato solo se la modifica è effettivamente sul server
                // (data server più recente di quella locale)
                let isServerModified: Bool
                if let localMod = localMod, let serverMod = serverMod {
                    isServerModified = serverMod > localMod
                } else {
                    isServerModified = serverMod != nil // Se abbiamo solo la data server, assumiamo che sia modificato
                }
                
                _ = FileVersioningService.shared.createVersion(of: localURL, in: destinationPath, description: "Conflitto sincronizzazione")
                print("[ClaimSync] 📦 Conflitto \(conflictFile.relativePath): server più recente, locale in versioning")
                filesToDownload.append(conflictFile)
                
                // Segna come modificato solo se la modifica è sul server (non locale)
                if isServerModified {
                    modifiedFiles.insert(conflictFile.relativePath)
                    print("[ClaimSync] 📝 File \(conflictFile.relativePath) segnato come modificato (server più recente)")
                } else {
                    print("[ClaimSync] ⚠️ File \(conflictFile.relativePath) ha hash diverso ma data locale più recente, non segnato come modificato")
                }
            }
        }
        
        if filesToDownload.isEmpty {
            if !isBackgroundSync {
                setStatus(.upToDate, for: riferimento)
            }
            markFirstSyncCompleted(for: riferimento)
            saveLocalManifest(metadata: metadata, for: riferimento, overrides: keptLocalOverrides, localPath: destinationPath)
            return
        }
        
        // Separa file nuovi da file modificati
        let newFiles = filesToDownload.filter { !modifiedFiles.contains($0.relativePath) }
        let modifiedFilesList = filesToDownload.filter { modifiedFiles.contains($0.relativePath) }
        
        // Accumula i file nuovi per la notifica finale (non inviare notifiche durante il download)
        var downloadedNewFiles: [String] = []
        var downloadedModifiedFiles: [String] = []
        
        // Download file mancanti uno alla volta
        let total = filesToDownload.count
        
        for (index, file) in filesToDownload.enumerated() {
            if !isBackgroundSync {
                setStatus(.downloadingFile(name: file.relativePath, current: index + 1, total: total), for: riferimento)
            }
            
            // Notifica inizio download
            await FileDownloadTracker.shared.startDownload(relativePath: file.relativePath)
            
            let data: Data
            do {
                print("[ClaimSync] 📥 Download file: \(file.relativePath) (atteso: \(file.size) bytes, MD5: \(file.md5))")
                data = try await apiClient.downloadFile(
                    claimId: riferimento,
                    userId: currentUserId(),
                    relativePath: file.relativePath
                )
                print("[ClaimSync] ✅ Ricevuti \(data.count) bytes per \(file.relativePath)")
                
                // Accumula i file scaricati per la notifica finale
                if modifiedFiles.contains(file.relativePath) {
                    downloadedModifiedFiles.append(file.relativePath)
                } else {
                    downloadedNewFiles.append(file.relativePath)
                }
                
                // Aggiorna progresso (100%)
                await FileDownloadTracker.shared.updateProgress(relativePath: file.relativePath, progress: 1.0)
                
                // Verifica preliminare: dimensione deve corrispondere (con tolleranza)
                if file.size > 0 && abs(Int64(data.count) - file.size) > 1024 {
                    print("[ClaimSync] ⚠️ Dimensione file non corrisponde: atteso \(file.size), ricevuto \(data.count)")
                }
            } catch {
                // Notifica errore download
                await FileDownloadTracker.shared.completeDownload(relativePath: file.relativePath)
                logNetworkError(error, context: "downloadFile \(file.relativePath)")
                throw error
            }
            
            // Validazione MD5 PRIMA di scrivere (evita di scrivere file corrotti)
            let dataMD5 = md5Hash(data: data)
            if dataMD5.lowercased() != file.md5.lowercased() {
                print("[ClaimSync] ❌ File corrotto PRIMA della scrittura: \(file.relativePath)")
                print("[ClaimSync]   MD5 atteso: \(file.md5)")
                print("[ClaimSync]   MD5 ricevuto: \(dataMD5)")
                throw SyncAgentError.httpError("File corrotto durante download: \(file.relativePath) (MD5 non corrisponde)")
            }
            
            // Scrittura atomica: scrivi su temp e poi rename
            let localPath = (destinationPath as NSString).appendingPathComponent(file.relativePath)
            let parentDir = (localPath as NSString).deletingLastPathComponent
            let tempPath = localPath + ".partial"
            
            // Crea directory parent
            createDirectoryWithAccess(at: parentDir, activeDirectory: baseForAccess)
            
            // Scrittura atomica con security-scoped access
            let writeSuccess = writeFileAtomically(
                data: data,
                tempPath: tempPath,
                finalPath: localPath,
                activeDirectory: baseForAccess
            )
            
            guard writeSuccess else {
                print("[ClaimSync] ❌ Errore scrittura atomica file: \(file.relativePath)")
                throw SyncAgentError.unzipFailed
            }
            
            // Verifica size scritto
            let writtenSize = getFileSize(at: localPath, activeDirectory: baseForAccess) ?? 0
            if file.size > 0 && abs(Int64(writtenSize) - file.size) > 0 {
                print("[ClaimSync] ❌ Size mismatch dopo scrittura: atteso \(file.size), scritto \(writtenSize)")
                deleteFileWithAccess(at: localPath, activeDirectory: baseForAccess)
                // Notifica errore download
                await FileDownloadTracker.shared.completeDownload(relativePath: file.relativePath)
                throw SyncAgentError.httpError("Size mismatch dopo scrittura: \(file.relativePath)")
            }
            
            // Notifica completamento download
            await FileDownloadTracker.shared.completeDownload(relativePath: file.relativePath)
            
            // Validazione integrità POST-scrittura (doppio controllo)
            if !validateFileIntegrity(filePath: localPath, expectedMD5: file.md5, activeDirectory: baseForAccess) {
                // File corrotto dopo scrittura: cancella e lancia errore
                deleteFileWithAccess(at: localPath, activeDirectory: baseForAccess)
                print("[ClaimSync] ❌ File corrotto DOPO scrittura: \(file.relativePath) (MD5 non corrisponde)")
                throw SyncAgentError.httpError("File corrotto dopo scrittura: \(file.relativePath)")
            }
            
            print("[ClaimSync] ✅ File salvato e validato: \(file.relativePath) (\(writtenSize) bytes)")
            
            // Recupera i tag persistenti se presenti (basati su SHA256)
            Task { @MainActor in
                FileTagManager.shared.loadTagsFromVersioning(for: localPath)
            }
            
            // Notifica UI: un nuovo file è stato scritto su disco
            NotificationCenter.default.post(
                name: .claimFolderChanged,
                object: nil,
                userInfo: [
                    "riferimento": riferimento,
                    "relativePath": file.relativePath
                ]
            )
        }
        
        // Salva manifest aggiornato (override per path "keep local") e localSnapshot
        saveLocalManifest(metadata: metadata, for: riferimento, overrides: keptLocalOverrides, localPath: destinationPath)
        setStatus(.upToDate, for: riferimento)
        markFirstSyncCompleted(for: riferimento)
        
        // Invia notifica finale solo dopo che tutti i file sono stati scaricati
        if !downloadedNewFiles.isEmpty || !downloadedModifiedFiles.isEmpty {
            await sendFinalDownloadNotification(
                riferimento: riferimento,
                newFiles: downloadedNewFiles,
                modifiedFiles: downloadedModifiedFiles
            )
        }
        
        await postDownloadActions(riferimento: riferimento)
    }

    // MARK: - Download Pacchetto (fallback)
    
    private func downloadPackage(metadata: ClaimMetadata, riferimento: String, isNewDownload: Bool) async throws {
        // Progresso: 0-10% registering (già fatto), 10-90% download, 90-100% extracting
        let initialProgress = DownloadProgressInfo(
            progress: 0,
            overallProgress: 0.10, // 10% completato (registering)
            bytesDownloaded: 0,
            bytesTotal: Int64(metadata.totalBytes),
            bytesPerSecond: 0
        )
        setStatus(.downloading(info: initialProgress), for: riferimento)
        
        let tempURL: URL
        do {
            tempURL = try await apiClient.downloadPackage(
                claimId: riferimento,
                userId: currentUserId(),
                expectedTotalBytes: Int64(metadata.totalBytes)
            ) { [weak self] progress, bytesDownloaded, bytesTotal, speed in
                // Il callback è già sul main thread (DispatchQueue.main.async nel delegate)
                // Usiamo assumeIsolated per evitare latenza del Task
                MainActor.assumeIsolated {
                    // Mappa il progresso download (0-1) su range 10-90% del totale
                    let overallProgress = 0.10 + (progress * 0.80)
                    let info = DownloadProgressInfo(
                        progress: progress,
                        overallProgress: overallProgress,
                        bytesDownloaded: bytesDownloaded,
                        bytesTotal: bytesTotal,
                        bytesPerSecond: speed
                    )
                    self?.setStatus(.downloading(info: info), for: riferimento)
                }
            }
        } catch {
            logNetworkError(error, context: "downloadPackage")
            throw error
        }

        // Fase decompressione: 90-100%
        setStatus(.extracting(progress: 0.90), for: riferimento)
        
        // Destinazione finale
        let destinationPath = buildLocalPath(for: riferimento)
        print("[ClaimSync] 📂 Estrazione ZIP in: \(destinationPath)")
        
        // Verifica che il ZIP sia completo prima di estrarre
        let zipSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
        if metadata.totalBytes > 0 {
            // Tolleranza 1% per differenze di compressione
            let tolerance = Int64(Double(metadata.totalBytes) * 0.01)
            if abs(zipSize - Int64(metadata.totalBytes)) > tolerance {
                print("[ClaimSync] ❌ ZIP incompleto: atteso ~\(metadata.totalBytes) bytes, scaricato \(zipSize) bytes")
                try? FileManager.default.removeItem(at: tempURL)
                throw SyncAgentError.httpError("ZIP incompleto: atteso ~\(metadata.totalBytes) bytes, scaricato \(zipSize) bytes")
            }
        }
        
        print("[ClaimSync] ✅ ZIP completo: \(zipSize) bytes, procedo con estrazione")
        
        // Estrai usando security-scoped access se necessario
        let extractionSuccess = extractZipWithSecurityAccess(
            zipURL: tempURL,
            destinationPath: destinationPath
        )
        
        guard extractionSuccess else {
            print("[ClaimSync] ❌ Estrazione ZIP fallita")
            try? FileManager.default.removeItem(at: tempURL)
            throw SyncAgentError.unzipFailed
        }
        
        // Aggiorna progresso: estrazione quasi completata
        setStatus(.extracting(progress: 0.98), for: riferimento)

        try? FileManager.default.removeItem(at: tempURL)
        
        // Inizializza cache interna (versioning/cestino) del sinistro
        FileVersioningService.shared.ensureCacheStructure(for: destinationPath)
        
        // Estrazione completata
        setStatus(.extracting(progress: 1.0), for: riferimento)
        
        // Verifica che la cartella sia stata creata correttamente
        let verifiedPath = fileService.getSinistroPath(riferimento: riferimento)
        if let path = verifiedPath {
            let contents = try? FileManager.default.contentsOfDirectory(atPath: path)
            print("[ClaimSync] ✅ Cartella verificata: \(path)")
            print("[ClaimSync] 📋 Elementi nella cartella: \(contents?.count ?? 0)")
        } else {
            print("[ClaimSync] ⚠️ Cartella NON trovata dopo estrazione! Destinazione era: \(destinationPath)")
            // Non lanciamo errore perché potrebbe essere un problema di security-scoped access nella verifica
        }
        
        // Notifica UI: decompressione completata (cartella aggiornata)
        NotificationCenter.default.post(
            name: .claimFolderChanged,
            object: nil,
            userInfo: [
                "riferimento": riferimento,
                "relativePath": ""
            ]
        )
        
        // Salva manifest e localSnapshot
        saveLocalManifest(metadata: metadata, for: riferimento, localPath: destinationPath)
        setStatus(.upToDate, for: riferimento)
        markFirstSyncCompleted(for: riferimento)
        
        await postDownloadActions(riferimento: riferimento)
    }
    
    /// Catena di automazioni post-download: questo è il primo tassello del domino
    private func postDownloadActions(riferimento: String) async {
        print("[ClaimSync] 🎬 Avvio catena automazioni post-download per \(riferimento)")
        
        // 1. Notifica TaskManager del download completato (gestisce task "scarica cartella")
        TaskManager.shared.handleFolderDownloaded(sinistroID: riferimento)
        
        guard let sinistro = fetchSinistro(by: riferimento) else {
            // Se non esiste il sinistro, prova a crearlo/processarlo come nuova cartella
            if let path = fileService.getSinistroPath(riferimento: riferimento) {
                await AutoCheckService.shared.checkAndProcessNewFolder(path: path, riferimento: riferimento)
            }
            return
        }
        
        let context = sinistro.managedObjectContext ?? PersistenceController.shared.container.viewContext
        
        // 2. Cambio stato: da "Da scaricare" → stato appropriato
        await updateStateAfterDownload(sinistro: sinistro, context: context)
        
        // 3. AutoCheck: lettura Excel, parsing incarico, tagging file
        await AutoCheckService.shared.performAutoChecks(for: sinistro, context: context)
        
        // 4. AutoTagging IA: NON deve partire da qui.
        // Viene gestito solo da AutoCheckService (se abilitato).
        
        // 5. Notifica UI che il sinistro è stato aggiornato
        NotificationCenter.default.post(
            name: .sinistroUpdated,
            object: nil,
            userInfo: ["riferimento": riferimento]
        )
        
        print("[ClaimSync] ✅ Catena automazioni completata per \(riferimento)")
    }
    
    /// Aggiorna lo stato del sinistro dopo il download della cartella
    private func updateStateAfterDownload(sinistro: Sinistro, context: NSManagedObjectContext) async {
        guard let currentStateDesc = sinistro.stato else { return }
        
        // Se lo stato è "Da scaricare", cambia in base ai dati disponibili
        if currentStateDesc == StatoManager.StatoSinistro.daScaricare.descrizione {
            // Determina il nuovo stato in base alle caratteristiche del sinistro
            let newState = determineInitialState(for: sinistro)
            
            do {
                try await StatoManager.shared.changeState(
                    for: sinistro,
                    to: newState,
                    context: context,
                    skipValidation: true // Skip perché viene da automazione
                )
                print("[ClaimSync] 📊 Stato cambiato da 'Da scaricare' a '\(newState.descrizione)'")
            } catch {
                print("[ClaimSync] ⚠️ Errore cambio stato: \(error.localizedDescription)")
            }
        }
    }
    
    /// Determina lo stato iniziale appropriato in base alle caratteristiche del sinistro
    /// Logica:
    /// - Se c'è cartella "Sopralluogo" → Tradizionale → Perizia da eseguire
    /// - Se NON c'è cartella "Sopralluogo" → Documentale:
    ///   - Se mancano le foto → In attesa (documentale)
    ///   - Se ci sono le foto → Perizia da eseguire (documentale)
    private func determineInitialState(for sinistro: Sinistro) -> StatoManager.StatoSinistro {
        // Se ha data sopralluogo già fissato, è un sopralluogo confermato
        if sinistro.dataSopralluogo != nil {
            return .sopralluogoFissato
        }
        
        // Verifica tipo di perizia dalla presenza della cartella "Sopralluogo"
        guard let riferimento = sinistro.riferimento,
              let path = fileService.getSinistroPath(riferimento: riferimento) else {
            // Fallback: usa il flag sopralluogo esistente
            return sinistro.sopralluogo ? .periziaDaEseguire : .inAttesaDocumentale
        }
        
        // Verifica presenza cartella "Sopralluogo"
        let hasSopralluogoFolder = checkHasSopralluogoFolder(inPath: path)
        
        if hasSopralluogoFolder {
            // Sinistro TRADIZIONALE (con sopralluogo)
            sinistro.sopralluogo = true
            print("[ClaimSync] 📁 Rilevata cartella 'Sopralluogo' → Sinistro TRADIZIONALE")
            return .periziaDaEseguire
        } else {
            // Sinistro DOCUMENTALE (senza sopralluogo)
            sinistro.sopralluogo = false
            print("[ClaimSync] 📁 Cartella 'Sopralluogo' assente → Sinistro DOCUMENTALE")
            
            // Verifica presenza foto per determinare lo stato
            let hasFoto = checkHasFoto(inPath: path)
            
            if hasFoto {
                print("[ClaimSync] 📷 Foto presenti → Perizia da eseguire (documentale)")
                return .periziaDaEseguireDocumentale
            } else {
                print("[ClaimSync] 📷 Foto mancanti → In attesa (documentale)")
                return .inAttesaDocumentale
            }
        }
    }
    
    /// Verifica se esiste la sottocartella "Sopralluogo" nel path specificato
    private func checkHasSopralluogoFolder(inPath path: String) -> Bool {
        let sopralluogoPath = (path as NSString).appendingPathComponent("Sopralluogo")
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: sopralluogoPath, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
    
    /// Verifica se esistono foto nella cartella del sinistro
    /// Cerca nelle sottocartelle tipiche: "Sopralluogo", "Foto", "Documentazione", o nella root
    private func checkHasFoto(inPath path: String) -> Bool {
        let photoExtensions = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif"]
        
        // Cartelle da controllare per le foto
        let foldersToCheck = [
            path,
            (path as NSString).appendingPathComponent("Foto"),
            (path as NSString).appendingPathComponent("Documentazione"),
            (path as NSString).appendingPathComponent("Documentazione Fotografica")
        ]
        
        for folder in foldersToCheck {
            guard FileManager.default.fileExists(atPath: folder) else { continue }
            
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: folder) {
                for file in contents {
                    let ext = (file as NSString).pathExtension.lowercased()
                    if photoExtensions.contains(ext) {
                        return true
                    }
                }
            }
        }
        
        return false
    }

    // MARK: - Upload Modifiche
    
    /// POST /api/claims/{claim_id}/upload - Carica file nuovi/modificati
    /// Upload file modificati E struttura cartelle (incluse quelle vuote)
    func uploadChangedFiles(for sinistro: Sinistro, skipHealthCheck: Bool = false, isBackgroundSync: Bool = false, alreadyUploadedPaths: Set<String> = []) async {
        guard let riferimento = sinistro.riferimento,
              let path = fileService.getSinistroPath(riferimento: riferimento) else { return }

        // Prima normalizza la cartella: sposta i file spazzatura nel cestino PerX (che viene sincronizzato)
        AutoCheckService.shared.moveJunkFilesToCestino(inPath: path)

        // Health check
        if !skipHealthCheck {
            await refreshAgentStatus()
        }
        guard agentReachable else {
            if !isBackgroundSync {
                setStatus(.error("Agent non raggiungibile"), for: riferimento)
            }
            return
        }

        // 1. Recupera manifest remoto (fuori da security-scoped, è rete)
        var remoteHashes: [String: String] = [:]
        var hasRemoteManifest = false
        do {
            let metadata = try await apiClient.fetchMetadata(claimId: riferimento, userId: currentUserId())
            remoteHashes = (metadata.files ?? []).reduce(into: [String: String]()) { $0[$1.relativePath] = $1.md5 }
            hasRemoteManifest = true
        } catch {
            print("[ClaimSync] ⚠️ Impossibile recuperare manifest remoto per confronto: \(error.localizedDescription)")
        }

        let cachedManifest = loadLocalManifest(for: riferimento)
        let cachedHashes = cachedManifest?.files.reduce(into: [String: String]()) { $0[$1.relativePath] = $1.md5 } ?? [:]
        let baseForAccess = securityScopedBase(for: path)

        typealias UploadItem = (data: Data, relativePath: String)

        func collectAndBuild() -> (directories: [String], filesToUpload: [UploadItem]) {
            let dirs = self.collectDirectoriesRelativePaths(in: path)
            let allFiles = self.collectFilesWithRelativePaths(in: path)
            var toUpload: [UploadItem] = []
            if cachedManifest == nil {
                toUpload = allFiles
                    .filter { !alreadyUploadedPaths.contains($0.1) }
                    .compactMap { url, rel -> UploadItem? in
                        guard let d = try? Data(contentsOf: url) else { return nil }
                        _ = FileVersioningService.shared.createVersion(of: url, in: path, description: "Pre-upload sincronizzazione")
                        return (data: d, relativePath: rel)
                    }
            } else {
                for (url, relativePath) in allFiles {
                    if alreadyUploadedPaths.contains(relativePath) { continue }
                    guard let data = try? Data(contentsOf: url) else { continue }
                    let currentMd5 = self.md5Hash(data: data)
                    let isNew = cachedHashes[relativePath] == nil
                    let isModified = !isNew && cachedHashes[relativePath] != currentMd5
                    
                    // Controlla se il file non esiste sul server o differisce
                    let notOnServer = hasRemoteManifest && remoteHashes[relativePath] == nil
                    let differsFromServer = hasRemoteManifest && remoteHashes[relativePath] != nil && remoteHashes[relativePath] != currentMd5
                    
                    // Se il manifest remoto non è disponibile, affidiamoci al manifest locale
                    // ma se un file è nuovo localmente, lo carichiamo sempre
                    let shouldUpload: Bool
                    let reason: String
                    if hasRemoteManifest {
                        // Con manifest remoto: carica se nuovo, modificato, non sul server, o diverso
                        shouldUpload = isNew || isModified || notOnServer || differsFromServer
                        if isNew {
                            reason = "nuovo localmente"
                        } else if isModified {
                            reason = "modificato localmente"
                        } else if notOnServer {
                            reason = "non presente sul server"
                        } else if differsFromServer {
                            reason = "differisce dal server"
                        } else {
                            reason = "nessuna ragione"
                        }
                    } else {
                        // Senza manifest remoto: carica se nuovo o modificato localmente
                        shouldUpload = isNew || isModified
                        reason = isNew ? "nuovo localmente (no manifest remoto)" : "modificato localmente (no manifest remoto)"
                    }
                    
                    guard shouldUpload else { continue }
                    print("[ClaimSync] 📤 File da caricare: \(relativePath) - \(reason)")
                    _ = FileVersioningService.shared.createVersion(of: url, in: path, description: "Pre-upload sincronizzazione")
                    toUpload.append((data: data, relativePath: relativePath))
                }
            }
            return (directories: dirs, filesToUpload: toUpload)
        }

        let result: (directories: [String], filesToUpload: [UploadItem])? = !baseForAccess.isEmpty
            ? fileService.performWithSecurityScopedAccess(to: baseForAccess, operation: collectAndBuild)
            : collectAndBuild()

        guard let (allDirectories, filesToUpload) = result, !filesToUpload.isEmpty else {
            if !isBackgroundSync {
                setStatus(.upToDate, for: riferimento)
            }
            
            // Se il sinistro è revocato e non ci sono più file da caricare, elimina subito la cartella locale
            if sinistro.stato == StatoManager.StatoSinistro.revocata.descrizione {
                print("[ClaimSync] 🗑️ Sinistro revocato e sincronizzato (upload), eliminazione immediata cartella locale")
                Task {
                    await removeLocalFolderAndUnregister(sinistroID: riferimento)
                }
            }
            return
        }

        // 3. Crea directory sul server poi upload
        if !allDirectories.isEmpty {
            await syncDirectoriesToServer(claimId: riferimento, directories: allDirectories)
        }

        let total = filesToUpload.count
        if !isBackgroundSync {
            setStatus(.uploadingFile(name: "", current: 0, total: total), for: riferimento)
        }
        print("[ClaimSync] 📤 \(total) file da caricare (versioning salvato)")
        
        do {
        let response = try await apiClient.uploadFiles(
            claimId: riferimento,
            userId: currentUserId(),
            filesData: filesToUpload
        ) { [weak self] progress in
                // Il callback è già sul main thread
                guard !isBackgroundSync else { return }
                MainActor.assumeIsolated { self?.setStatus(.uploading(progress: progress), for: riferimento) }
            }
            
            if response.success {
                // Aggiorna manifest locale dopo upload:
                // - prova a leggere dal server
                // - fallback: salva snapshot locale (utile se il server non espone subito tutte le voci, es. PerX-cache)
                do {
                    try await refreshManifest(for: riferimento, localPath: path)
                } catch {
                    saveLocalManifestSnapshot(fromLocalPath: path, for: riferimento)
                }
                if !isBackgroundSync {
                    setStatus(.upToDate, for: riferimento)
                }
                
                // Se il sinistro è revocato, elimina subito la cartella locale dopo l'upload completato
                if sinistro.stato == StatoManager.StatoSinistro.revocata.descrizione {
                    print("[ClaimSync] 🗑️ Sinistro revocato: upload finale completato, eliminazione immediata cartella locale")
                    await removeLocalFolderAndUnregister(sinistroID: riferimento)
                }
            } else {
                if !isBackgroundSync {
                    setStatus(.error(response.message), for: riferimento)
                }
            }
        } catch {
            logNetworkError(error, context: "uploadChangedFiles")
            if !isBackgroundSync {
                setStatus(.error(error.localizedDescription), for: riferimento)
            }
        }
    }
    
    private func refreshManifest(for riferimento: String, localPath: String? = nil) async throws {
        let metadata = try await apiClient.fetchMetadata(claimId: riferimento, userId: currentUserId())
        saveLocalManifest(metadata: metadata, for: riferimento, localPath: localPath)
    }

    // MARK: - Countdown cleanup

    private func handleStateChange(sinistroID: String, newState: StatoManager.StatoSinistro) async {
        guard let sinistro = fetchSinistro(by: sinistroID) else { return }
        
        // Stato "Da scaricare" → registra e avvia subito la sincronizzazione (trigger download automatico)
        if newState == .daScaricare {
            await registerAndSyncIfNeeded(sinistro: sinistro, forceDownload: true)
        }
        
        // Stati terminali: programma disiscrizione dopo 7 giorni
        if newState == .chiusa || newState == .revocata || newState == .annullata {
            await scheduleUnregistration(for: sinistroID)
            
            // Se chiuso e sync attiva (non sospesa), sospendi automaticamente la sync
            // (silente, senza dialog - per sinistri chiusi facciamo solo upload, no download automatico)
            if newState == .chiusa && !suspendedClaims.contains(sinistroID) {
                print("[ClaimSync] 🔇 Sinistro \(sinistroID) chiuso, sospensione automatica sync (solo upload)")
                suspendSync(for: sinistroID)
            }
            
            // Se chiuso, programma anche cleanup cartella (se abilitato)
            if newState == .chiusa, let chiusura = sinistro.dataChiusura {
                await scheduleCleanup(for: sinistroID, closedAt: chiusura)
            }
            
            await performScheduledCleanup()
        } else {
            // Se torna in uno stato attivo, rimuovi dalla coda di disiscrizione
            cancelScheduledUnregistration(for: sinistroID)
        }
        
        // Verifica se lo stato è cambiato per sinistri aggiunti manualmente
        checkManualClaimStateChange(riferimento: sinistroID, newState: newState.descrizione)
    }
    
    // MARK: - Disiscrizione Automatica (7 giorni)
    
    private func scheduleUnregistration(for sinistroID: String) async {
        let limit = Calendar.current.date(byAdding: .day, value: unregisterDelayDays, to: Date()) ?? Date()
        var schedule = UserDefaults.standard.dictionary(forKey: unregisterScheduleKey) as? [String: String] ?? [:]
        schedule[sinistroID] = ISO8601DateFormatter().string(from: limit)
        UserDefaults.standard.set(schedule, forKey: unregisterScheduleKey)
        print("[ClaimSync] ⏰ Disiscrizione programmata per \(sinistroID) tra \(unregisterDelayDays) giorni")
        
        // Disiscrivi immediatamente dal monitoring quando viene schedulato
        do {
            let req = RegisterMonitoringRequest(user_id: currentUserId(), claim_id: sinistroID, path_hint: nil)
            let _: GenericAPIResponse = try await apiClient.post("/api/monitoring/unregister", body: req)
            print("[ClaimSync] ✅ Sinistro \(sinistroID) disiscritto dal monitoring (schedulato per disiscrizione)")
        } catch {
            print("[ClaimSync] ⚠️ Errore disiscrizione \(sinistroID) durante scheduling: \(error.localizedDescription)")
        }
    }
    
    private func cancelScheduledUnregistration(for sinistroID: String) {
        var schedule = UserDefaults.standard.dictionary(forKey: unregisterScheduleKey) as? [String: String] ?? [:]
        if schedule.removeValue(forKey: sinistroID) != nil {
            UserDefaults.standard.set(schedule, forKey: unregisterScheduleKey)
            print("[ClaimSync] ↩️ Disiscrizione annullata per \(sinistroID)")
        }
    }
    
    private func performScheduledUnregistration() async {
        let formatter = ISO8601DateFormatter()
        var schedule = UserDefaults.standard.dictionary(forKey: unregisterScheduleKey) as? [String: String] ?? [:]
        var toRemove: [String] = []
        
        for (sinistroID, isoDate) in schedule {
            guard let limit = formatter.date(from: isoDate) else { continue }
            if Date() >= limit {
                // Disiscrivi dall'agent
                do {
                    let req = RegisterMonitoringRequest(user_id: currentUserId(), claim_id: sinistroID, path_hint: nil)
                    let _: GenericAPIResponse? = try await apiClient.post("/api/monitoring/unregister", body: req)
                    print("[ClaimSync] 🗑️ Sinistro \(sinistroID) disiscritto dall'agent")
                } catch {
                    print("[ClaimSync] ⚠️ Errore disiscrizione \(sinistroID): \(error.localizedDescription)")
                }
                
                statuses.removeValue(forKey: sinistroID)
                toRemove.append(sinistroID)
            }
        }
        
        // Aggiorna lo schedule
        for id in toRemove {
            schedule.removeValue(forKey: id)
        }
        UserDefaults.standard.set(schedule, forKey: unregisterScheduleKey)
    }

    private func scheduleCleanup(for sinistroID: String, closedAt: Date) async {
        // Non serve più schedule esplicita: usiamo scan-based con giorni fissi
        // Ma manteniamo la disiscrizione immediata dal monitoring
        guard isAutoDeleteEnabled else { return }
        
        // Disiscrivi immediatamente dal monitoring quando entra in stato terminale
        do {
            let req = RegisterMonitoringRequest(user_id: currentUserId(), claim_id: sinistroID, path_hint: nil)
            let _: GenericAPIResponse = try await apiClient.post("/api/monitoring/unregister", body: req)
            print("[ClaimSync] ✅ Sinistro \(sinistroID) disiscritto dal monitoring (in stato terminale)")
        } catch {
            print("[ClaimSync] ⚠️ Errore disiscrizione \(sinistroID): \(error.localizedDescription)")
        }
    }

    /// Esegue il cleanup automatico delle cartelle scadute (scan-based).
    /// Usa dataChiusura/dataRevoca + giorni fissi per determinare la scadenza.
    private func performScheduledCleanup() async {
        guard isAutoDeleteEnabled else { return }
        
        let now = Date()
        let pendingDeletions = getPendingDeletions()
        
        for info in pendingDeletions {
            // Elimina solo se scaduto (daysRemaining <= 0)
            if info.daysRemaining <= 0 {
                print("[ClaimSync] ⏰ Sinistro \(info.riferimento) scaduto (\(info.reason.rawValue)), eliminazione...")
                
                // Push-only sync prima dell'eliminazione: carica eventuali file locali non presenti sul server
                await pushOnlySync(for: info.riferimento)
                
                // Elimina la cartella
                await removeLocalFolderAndUnregister(sinistroID: info.riferimento)
            }
        }
        
        // Gestisci anche sinistri aggiunti manualmente (legacy)
        await performManualClaimCleanup()
    }
    
    /// Sync unidirezionale push-only: carica solo i file locali che non esistono sul server, senza scaricare nulla.
    /// Usato prima dell'eliminazione programmata per non perdere file creati solo localmente.
    private func pushOnlySync(for riferimento: String) async {
        guard let sinistro = fetchSinistro(by: riferimento),
              let path = fileService.getSinistroPath(riferimento: riferimento) else { return }
        
        print("[ClaimSync] ⬆️ Push-only sync per \(riferimento) prima dell'eliminazione...")
        
        do {
            // Ottieni metadata dal server
            let metadata = try await apiClient.fetchMetadata(claimId: riferimento, userId: currentUserId())
            let remoteFiles = Set((metadata.files ?? []).map { $0.relativePath })
            
            // Calcola hash locali
            let baseForAccess = securityScopedBase(for: path)
            let localHashes = computeLocalFileHashes(in: path, activeDirectory: baseForAccess)
            
            // Trova file locali che non esistono sul server
            var filesToUpload: [(url: URL, relativePath: String)] = []
            for (relativePath, _) in localHashes {
                if shouldExcludeFile(relativePath) { continue }
                if !remoteFiles.contains(relativePath) {
                    let fullPath = (path as NSString).appendingPathComponent(relativePath)
                    filesToUpload.append((url: URL(fileURLWithPath: fullPath), relativePath: relativePath))
                }
            }
            
            if !filesToUpload.isEmpty {
                print("[ClaimSync] ⬆️ Caricamento \(filesToUpload.count) file locali esclusivi prima dell'eliminazione...")
                let _ = try await apiClient.uploadFiles(
                    claimId: riferimento,
                    userId: currentUserId(),
                    files: filesToUpload
                ) { _ in }
                print("[ClaimSync] ✅ Push-only sync completato per \(riferimento)")
            } else {
                print("[ClaimSync] ℹ️ Nessun file locale esclusivo da caricare per \(riferimento)")
            }
        } catch {
            print("[ClaimSync] ⚠️ Push-only sync fallito per \(riferimento): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Manual Claim Cleanup (sinistri aggiunti manualmente)
    
    /// Struttura per tracciare sinistri aggiunti manualmente
    struct ManualClaimInfo: Codable {
        let addedAt: Date
        let initialState: String
    }
    
    /// Registra un sinistro come "aggiunto manualmente" (es. sinistro chiuso scaricato su richiesta)
    /// Verrà cancellato dopo 3 giorni se lo stato non cambia
    func trackManuallyAddedClaim(riferimento: String, currentState: String) {
        let info = ManualClaimInfo(addedAt: Date(), initialState: currentState)
        var schedule = loadManualClaimSchedule()
        
        guard let data = try? JSONEncoder().encode(info) else { return }
        schedule[riferimento] = String(data: data, encoding: .utf8) ?? ""
        
        saveManualClaimSchedule(schedule)
        print("[ClaimSync] 📌 Sinistro \(riferimento) tracciato come manuale (stato: \(currentState)), cancellazione in \(manualClaimCleanupDays) giorni se invariato")
    }
    
    /// Rimuove un sinistro dal tracking manuale (es. se lo stato cambia)
    func untrackManuallyAddedClaim(riferimento: String) {
        var schedule = loadManualClaimSchedule()
        if schedule.removeValue(forKey: riferimento) != nil {
            saveManualClaimSchedule(schedule)
            print("[ClaimSync] ↩️ Sinistro \(riferimento) rimosso dal tracking manuale")
        }
    }
    
    /// Verifica se lo stato è cambiato e aggiorna il tracking
    func checkManualClaimStateChange(riferimento: String, newState: String) {
        let schedule = loadManualClaimSchedule()
        guard let jsonString = schedule[riferimento],
              let data = jsonString.data(using: .utf8),
              let info = try? JSONDecoder().decode(ManualClaimInfo.self, from: data) else { return }
        
        if info.initialState != newState {
            // Stato cambiato → rimuovi dal tracking manuale
            untrackManuallyAddedClaim(riferimento: riferimento)
        }
    }
    
    private func loadManualClaimSchedule() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: manualClaimCleanupKey) as? [String: String] ?? [:]
    }
    
    private func saveManualClaimSchedule(_ schedule: [String: String]) {
        UserDefaults.standard.set(schedule, forKey: manualClaimCleanupKey)
    }
    
    private func performManualClaimCleanup() async {
        let schedule = loadManualClaimSchedule()
        var toRemove: [String] = []
        
        for (riferimento, jsonString) in schedule {
            guard let data = jsonString.data(using: .utf8),
                  let info = try? JSONDecoder().decode(ManualClaimInfo.self, from: data) else { continue }
            
            let expirationDate = Calendar.current.date(byAdding: .day, value: manualClaimCleanupDays, to: info.addedAt) ?? info.addedAt
            
            if Date() >= expirationDate {
                // Verifica se lo stato è ancora lo stesso
                if let sinistro = fetchSinistro(by: riferimento),
                   (sinistro.stato ?? "") == info.initialState {
                    // Stato non cambiato → elimina cartella
                    print("[ClaimSync] ⏰ Sinistro manuale \(riferimento) in scadenza (stato invariato: \(info.initialState))")
                    await removeLocalFolderAndUnregister(sinistroID: riferimento)
                    toRemove.append(riferimento)
                } else {
                    // Stato cambiato o sinistro non trovato → rimuovi solo dal tracking
                    toRemove.append(riferimento)
                }
            }
        }
        
        if !toRemove.isEmpty {
            var updated = schedule
            for id in toRemove {
                updated.removeValue(forKey: id)
            }
            saveManualClaimSchedule(updated)
        }
    }
    
    // MARK: - Public API per UI (ClaimsSettingsView)
    
    /// Informazioni su una cartella in attesa di cancellazione
    struct PendingDeletionInfo: Identifiable {
        let id: String  // riferimento
        let riferimento: String
        let expirationDate: Date
        let reason: DeletionReason
        let daysRemaining: Int
        
        enum DeletionReason: String {
            case closedClaim = "Sinistro chiuso"
            case revokedClaim = "Sinistro revocato"
            case manualDownload = "Download manuale"
            case terminalState = "Stato terminale"
        }
    }
    
    /// Verifica se la cancellazione automatica è abilitata
    var isAutoDeleteEnabled: Bool {
        UserDefaults.standard.bool(forKey: "enableAutoDeleteClosed")
    }
    
    /// Ottiene la lista di TUTTE le cartelle locali che soddisfano i requisiti per l'eliminazione.
    /// Scansiona le directory e calcola la scadenza in base a dataChiusura / dataRevoca.
    func getPendingDeletions() -> [PendingDeletionInfo] {
        guard isAutoDeleteEnabled else { return [] }
        
        var result: [PendingDeletionInfo] = []
        let now = Date()
        let calendar = Calendar.current
        
        // Scansiona tutte le cartelle locali
        let claimsPath = fileService.getInternalClaimsPath()
        guard let folderContents = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: claimsPath),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return result
        }
        
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        
        for folderURL in folderContents {
            guard let isDirectory = try? folderURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDirectory == true else {
                continue
            }
            
            let riferimento = folderURL.lastPathComponent
            
            // Verifica se è un riferimento valido (7 caratteri)
            guard riferimento.count == 7 else { continue }
            
            // Cerca il sinistro nel database
            request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
            guard let sinistro = try? context.fetch(request).first else { continue }
            
            let stato = sinistro.stato ?? ""
            
            // Sinistro chiuso
            if stato == StatoManager.StatoSinistro.chiusa.descrizione,
               let dataChiusura = sinistro.dataChiusura {
                let expirationDate = calendar.date(byAdding: .day, value: Self.deletionDaysClosed, to: dataChiusura) ?? dataChiusura
                let daysRemaining = calendar.dateComponents([.day], from: now, to: expirationDate).day ?? 0
                result.append(PendingDeletionInfo(
                    id: "\(riferimento)-closedClaim",
                    riferimento: riferimento,
                    expirationDate: expirationDate,
                    reason: .closedClaim,
                    daysRemaining: max(0, daysRemaining)
                ))
            }
            // Sinistro revocato
            else if stato == StatoManager.StatoSinistro.revocata.descrizione,
                    let dataRevoca = sinistro.dataRevoca {
                let expirationDate = calendar.date(byAdding: .day, value: Self.deletionDaysRevoked, to: dataRevoca) ?? dataRevoca
                let daysRemaining = calendar.dateComponents([.day], from: now, to: expirationDate).day ?? 0
                result.append(PendingDeletionInfo(
                    id: "\(riferimento)-revokedClaim",
                    riferimento: riferimento,
                    expirationDate: expirationDate,
                    reason: .revokedClaim,
                    daysRemaining: max(0, daysRemaining)
                ))
            }
            // Sinistro annullato (usa dataChiusura se presente, altrimenti skip)
            else if stato == StatoManager.StatoSinistro.annullata.descrizione,
                    let dataChiusura = sinistro.dataChiusura {
                let expirationDate = calendar.date(byAdding: .day, value: Self.deletionDaysRevoked, to: dataChiusura) ?? dataChiusura
                let daysRemaining = calendar.dateComponents([.day], from: now, to: expirationDate).day ?? 0
                result.append(PendingDeletionInfo(
                    id: "\(riferimento)-terminalState",
                    riferimento: riferimento,
                    expirationDate: expirationDate,
                    reason: .terminalState,
                    daysRemaining: max(0, daysRemaining)
                ))
            }
        }
        
        // Ordina per data scadenza (più vicino prima)
        return result.sorted { $0.expirationDate < $1.expirationDate }
    }
    
    /// Verifica se un sinistro è in lista per l'eliminazione
    func isPendingDeletion(riferimento: String) -> Bool {
        return getPendingDeletions().contains { $0.riferimento == riferimento }
    }
    
    /// Annulla la cancellazione programmata di una cartella (non applicabile con scan-based)
    /// Ora rimuove solo dalle schedule legacy, la UI mostra sempre le cartelle che matchano i criteri
    func cancelPendingDeletion(riferimento: String) {
        var closed = UserDefaults.standard.dictionary(forKey: cleanupKey) as? [String: String] ?? [:]
        var revoked = UserDefaults.standard.dictionary(forKey: revokedCleanupKey) as? [String: String] ?? [:]
        var terminal = UserDefaults.standard.dictionary(forKey: unregisterScheduleKey) as? [String: String] ?? [:]
        var manual = loadManualClaimSchedule()
        
        let hadClosed = closed.removeValue(forKey: riferimento) != nil
        let hadRevoked = revoked.removeValue(forKey: riferimento) != nil
        let hadTerminal = terminal.removeValue(forKey: riferimento) != nil
        let hadManual = manual.removeValue(forKey: riferimento) != nil
        
        guard hadClosed || hadRevoked || hadTerminal || hadManual else { return }
        
        UserDefaults.standard.set(closed, forKey: cleanupKey)
        UserDefaults.standard.set(revoked, forKey: revokedCleanupKey)
        UserDefaults.standard.set(terminal, forKey: unregisterScheduleKey)
        saveManualClaimSchedule(manual)
        
        print("[ClaimSync] ↩️ Cancellazione annullata per \(riferimento)")
    }
    
    /// Cancella immediatamente una cartella dalla lista di eliminazione
    func deleteImmediately(riferimento: String) async {
        print("[ClaimSync] 🗑️ Eliminazione immediata richiesta per \(riferimento)")
        await removeLocalFolderAndUnregister(sinistroID: riferimento)
        
        // Rimuovi anche da schedule legacy
        var closed = UserDefaults.standard.dictionary(forKey: cleanupKey) as? [String: String] ?? [:]
        var revoked = UserDefaults.standard.dictionary(forKey: revokedCleanupKey) as? [String: String] ?? [:]
        var terminal = UserDefaults.standard.dictionary(forKey: unregisterScheduleKey) as? [String: String] ?? [:]
        var manual = loadManualClaimSchedule()
        
        closed.removeValue(forKey: riferimento)
        revoked.removeValue(forKey: riferimento)
        terminal.removeValue(forKey: riferimento)
        manual.removeValue(forKey: riferimento)
        
        UserDefaults.standard.set(closed, forKey: cleanupKey)
        UserDefaults.standard.set(revoked, forKey: revokedCleanupKey)
        UserDefaults.standard.set(terminal, forKey: unregisterScheduleKey)
        saveManualClaimSchedule(manual)
    }

    /// Rimuove la cartella locale SOLO DOPO aver verificato la disiscrizione dal monitoring.
    /// Questo evita che il server elimini i file se la cartella locale viene rimossa prima.
    private func removeLocalFolderAndUnregister(sinistroID: String) async {
        // 1. Prima disiscrivi dal monitoring (IMPORTANTE: prima di eliminare locale!)
        let req = RegisterMonitoringRequest(user_id: currentUserId(), claim_id: sinistroID, path_hint: nil)
        do {
            let response: GenericAPIResponse = try await apiClient.post("/api/monitoring/unregister", body: req)
            print("[ClaimSync] ✅ Sinistro \(sinistroID) disiscritto dal monitoring: \(response.message ?? "ok")")
            
            // 2. Solo dopo conferma disiscrizione, elimina la cartella locale
            // I file sono in Application Support, accesso diretto senza security-scoped
            if let path = fileService.getSinistroPath(riferimento: sinistroID) {
                try? FileManager.default.removeItem(atPath: path)
                print("[ClaimSync] 🗑️ Cartella locale eliminata: \(path)")
            }
            
            statuses[sinistroID] = .notDownloaded
            
        } catch {
            // Se la disiscrizione fallisce, NON eliminare la cartella locale!
            print("[ClaimSync] ⚠️ Disiscrizione fallita per \(sinistroID), cartella locale NON eliminata: \(error.localizedDescription)")
            setStatus(.error("Disiscrizione fallita - cartella preservata"), for: sinistroID)
        }
    }

    // MARK: - Helpers
    
    // MARK: - Deletion Handling
    
    /// Gestisce l'eliminazione di un file o cartella e notifica il server
    private func handleFileOrFolderDeletion(riferimento: String, relativePath: String, isDirectory: Bool) async {
        if isFileModeCloud { return }
        guard let sinistro = fetchSinistro(by: riferimento) else {
            print("[ClaimSync] ⚠️ Sinistro \(riferimento) non trovato, eliminazione non notificata")
            return
        }
        
        // Verifica che il sinistro sia sincronizzato
        guard status(for: sinistro) != .notDownloaded else {
            print("[ClaimSync] ⚠️ Sinistro \(riferimento) non sincronizzato, eliminazione non notificata")
            return
        }
        
        // Verifica che non sia sospeso
        guard !isSyncSuspended(for: sinistro) else {
            print("[ClaimSync] ⚠️ Sync sospesa per \(riferimento), eliminazione non notificata")
            return
        }
        
        // Escludi file di sistema
        if shouldExcludeFile(relativePath) {
            print("[ClaimSync] ⚠️ File escluso dalla sync: \(relativePath)")
            return
        }
        
        do {
            // Elimina sul server
            _ = try await apiClient.deleteFile(claimId: riferimento, userId: currentUserId(), relativePath: relativePath)
            print("[ClaimSync] 🗑️ Eliminato su server: \(relativePath) (\(isDirectory ? "cartella" : "file"))")
        } catch {
            print("[ClaimSync] ⚠️ Errore eliminazione su server per \(relativePath): \(error.localizedDescription)")
        }
    }
    
    /// Estrae il riferimento del sinistro dal path della cartella
    private func getRiferimentoFromPath(_ path: String) -> String? {
        // Il path è la cartella del sinistro, quindi l'ultimo componente è il riferimento
        let url = URL(fileURLWithPath: path)
        let riferimento = url.lastPathComponent
        
        // Verifica che il path corrisponda a quello che FileService restituirebbe per questo riferimento
        if let expectedPath = fileService.getSinistroPath(riferimento: riferimento),
           expectedPath == path {
            return riferimento
        }
        
        return nil
    }
    
    // MARK: File System Helpers
    
    /// Verifica se un path è interno (Application Support) - non richiede security-scoped access
    private func isInternalPath(_ path: String) -> Bool {
        let claimsPath = fileService.getInternalClaimsPath()
        return path.hasPrefix(claimsPath)
    }

    /// Restituisce la base per security-scoped access (solo per path esterni durante migrazione).
    /// Per path interni (Application Support) restituisce stringa vuota.
    private func securityScopedBase(for path: String) -> String {
        // Path interni non richiedono security-scoped access
        if isInternalPath(path) { return "" }
        
        // Legacy: per path esterni durante migrazione
        let active = UserDefaults.standard.string(forKey: "activeDirectory") ?? ""
        let closed = UserDefaults.standard.string(forKey: "closedDirectory") ?? ""
        if !active.isEmpty && path.hasPrefix(active) { return active }
        if !closed.isEmpty && path.hasPrefix(closed) { return closed }
        return ""
    }

    private func currentUserId() -> String {
        CurrentUserService.shared.currentUsernameOrDefault("perito")
    }
    
    /// Crea una directory (accesso diretto per path interni)
    private func createDirectoryWithAccess(at path: String, activeDirectory: String) {
        // Per path interni, accesso diretto
        if isInternalPath(path) || activeDirectory.isEmpty {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            return
        }
        
        // Legacy: per path esterni durante migrazione
        if path.hasPrefix(activeDirectory) {
            _ = fileService.performWithSecurityScopedAccess(to: activeDirectory) { () -> Bool in
                try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
                return true
            }
        } else {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }
    
    /// Calcola gli hash MD5 di tutti i file locali in una directory
    private func computeLocalFileHashes(in basePath: String, activeDirectory: String) -> [String: String] {
        let operation: () -> [String: String] = {
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(atPath: basePath) else { return [:] }
            
            var result: [String: String] = [:]
            while let relativePath = enumerator.nextObject() as? String {
                if self.isInVersioningFolder(relativePath) { continue }
                if self.shouldExcludeFile(relativePath) { continue }
                let fullPath = (basePath as NSString).appendingPathComponent(relativePath)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) {
                        result[relativePath] = self.md5Hash(data: data)
                    }
                }
            }
            return result
        }
        
        // Per path interni, accesso diretto
        if isInternalPath(basePath) || activeDirectory.isEmpty {
            return operation()
        }
        
        // Legacy: per path esterni
        if basePath.hasPrefix(activeDirectory) {
            return fileService.performWithSecurityScopedAccess(to: activeDirectory, operation: operation) ?? [:]
        }
        return operation()
    }
    
    /// Costruisce ClaimFileEntry per un file locale (relativePath, size, md5, modifiedAt)
    private func localFileEntry(relativePath: String, basePath: String, activeDirectory: String) -> ClaimFileEntry? {
        let fullPath = (basePath as NSString).appendingPathComponent(relativePath)
        let url = URL(fileURLWithPath: fullPath)
        let operation: () -> ClaimFileEntry? = {
            guard let data = try? Data(contentsOf: url) else { return nil }
            let md5 = self.md5Hash(data: data)
            let size = (try? FileManager.default.attributesOfItem(atPath: fullPath)[.size] as? NSNumber).map { $0.int64Value } ?? Int64(data.count)
            let modDate = (try? FileManager.default.attributesOfItem(atPath: fullPath)[.modificationDate] as? Date)
            return ClaimFileEntry(relativePath: relativePath, size: size, md5: md5, modifiedAt: modDate)
        }
        
        // Per path interni, accesso diretto
        if isInternalPath(basePath) || activeDirectory.isEmpty {
            return operation()
        }
        
        // Legacy: per path esterni
        if basePath.hasPrefix(activeDirectory) {
            return fileService.performWithSecurityScopedAccess(to: activeDirectory, operation: operation) ?? nil
        }
        return operation()
    }
    
    /// Scrittura atomica: scrive su temp e poi rename (evita file corrotti parziali)
    private func writeFileAtomically(data: Data, tempPath: String, finalPath: String, activeDirectory: String) -> Bool {
        let operation: () -> Bool = {
            do {
                // Rimuovi temp esistente se presente
                try? FileManager.default.removeItem(atPath: tempPath)
                
                // Scrivi su temp con opzione atomica
                try data.write(to: URL(fileURLWithPath: tempPath), options: .atomic)
                
                // Verifica che il file sia stato scritto correttamente
                let writtenSize = (try? FileManager.default.attributesOfItem(atPath: tempPath)[.size] as? Int64) ?? 0
                guard writtenSize == Int64(data.count) else {
                    try? FileManager.default.removeItem(atPath: tempPath)
                    print("[ClaimSync] ❌ Scrittura atomica fallita: size mismatch (atteso \(data.count), scritto \(writtenSize))")
                    return false
                }
                
                // Rimuovi file finale se esiste
                try? FileManager.default.removeItem(atPath: finalPath)
                
                // Rename temp -> finale
                try FileManager.default.moveItem(atPath: tempPath, toPath: finalPath)
                
                return true
            } catch {
                print("[ClaimSync] ❌ Errore scrittura atomica: \(error.localizedDescription)")
                try? FileManager.default.removeItem(atPath: tempPath)
                return false
            }
        }
        
        // Per path interni, accesso diretto
        if isInternalPath(finalPath) || activeDirectory.isEmpty {
            return operation()
        }
        
        // Legacy: per path esterni
        if finalPath.hasPrefix(activeDirectory) {
            return fileService.performWithSecurityScopedAccess(to: activeDirectory, operation: operation) ?? false
        }
        return operation()
    }
    
    /// Scrive un file con security-scoped access (legacy, mantenuto per compatibilità)
    private func writeFileWithAccess(data: Data, to path: String, parentDir: String, activeDirectory: String) -> Bool {
        let tempPath = path + ".partial"
        return writeFileAtomically(data: data, tempPath: tempPath, finalPath: path, activeDirectory: activeDirectory)
    }
    
    /// Ottiene la size di un file
    private func getFileSize(at path: String, activeDirectory: String) -> Int64? {
        let operation: () -> Int64? = {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            return attrs?[.size] as? Int64
        }
        
        // Per path interni, accesso diretto
        if isInternalPath(path) || activeDirectory.isEmpty {
            return operation()
        }
        
        // Legacy: per path esterni
        if path.hasPrefix(activeDirectory) {
            if let result: Int64? = fileService.performWithSecurityScopedAccess(to: activeDirectory, operation: operation) {
                return result
            }
            return nil
        }
        return operation()
    }

    /// Costruisce il path locale per un sinistro usando Application Support
    private func buildLocalPath(for riferimento: String) -> String {
        // Usa Application Support interno (gestito da FileService)
        let claimsPath = fileService.getInternalClaimsPath()
        let sinistroPath = (claimsPath as NSString).appendingPathComponent(riferimento)
        
        // Crea la directory se non esiste
        try? FileManager.default.createDirectory(atPath: sinistroPath, withIntermediateDirectories: true)
        
        print("[ClaimSync] 📁 Destinazione interna: \(sinistroPath)")
        return sinistroPath
    }

    /// Estrae un ZIP con security-scoped access per la directory di destinazione
    private func extractZipWithSecurityAccess(zipURL: URL, destinationPath: String) -> Bool {
        let baseForAccess = securityScopedBase(for: destinationPath)
        if !baseForAccess.isEmpty {
            let success = fileService.performWithSecurityScopedAccess(to: baseForAccess) { () -> Bool in
                return self.performZipExtraction(zipURL: zipURL, destinationPath: destinationPath)
            }
            return success ?? false
        }
        return performZipExtraction(zipURL: zipURL, destinationPath: destinationPath)
    }
    
    private func performZipExtraction(zipURL: URL, destinationPath: String) -> Bool {
        // Verifica che il ZIP esista e sia leggibile PRIMA di estrarre
        let zipSize = (try? FileManager.default.attributesOfItem(atPath: zipURL.path)[.size] as? Int64) ?? 0
        guard zipSize > 0 else {
            print("[ClaimSync] ❌ ZIP non valido o vuoto: \(zipURL.path)")
            return false
        }
        
        // Verifica che il ZIP sia un file valido (non una directory)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: zipURL.path, isDirectory: &isDir), !isDir.boolValue else {
            print("[ClaimSync] ❌ ZIP path non è un file: \(zipURL.path)")
            return false
        }
        
        print("[ClaimSync] 📦 Estrazione ZIP: \(zipSize) bytes da \(zipURL.lastPathComponent)")
        
        do {
            // Crea la directory se non esiste
            try FileManager.default.createDirectory(atPath: destinationPath, withIntermediateDirectories: true)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", zipURL.path, destinationPath]
            
            let pipe = Pipe()
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                print("[ClaimSync] ✅ Estrazione completata in: \(destinationPath)")
                
                // Verifica che i file esistano e siano leggibili (validazione base)
                let contents = try? FileManager.default.contentsOfDirectory(atPath: destinationPath)
                print("[ClaimSync] 📋 Contenuto estratto: \(contents?.count ?? 0) elementi")
                
                // Validazione base: verifica che i file siano leggibili (non completamente corrotti)
                if let contents = contents {
                    let fm = FileManager.default
                    var corruptedFiles: [String] = []
                    
                    for item in contents {
                        let itemPath = (destinationPath as NSString).appendingPathComponent(item)
                        var isDir: ObjCBool = false
                        
                        if fm.fileExists(atPath: itemPath, isDirectory: &isDir), !isDir.boolValue {
                            // Verifica che il file sia leggibile e non vuoto
                            if let data = try? Data(contentsOf: URL(fileURLWithPath: itemPath)) {
                                if data.isEmpty {
                                    corruptedFiles.append(item)
                                }
                            } else {
                                // File non leggibile = corrotto
                                corruptedFiles.append(item)
                            }
                        }
                    }
                    
                    if !corruptedFiles.isEmpty {
                        print("[ClaimSync] ⚠️ File corrotti dopo estrazione ZIP: \(corruptedFiles.joined(separator: ", "))")
                        // Cancella i file corrotti
                        for corrupted in corruptedFiles {
                            let corruptedPath = (destinationPath as NSString).appendingPathComponent(corrupted)
                            try? fm.removeItem(atPath: corruptedPath)
                        }
                        // Non falliamo completamente: alcuni file potrebbero essere OK
                    }
                }
                
                return true
            } else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? "errore sconosciuto"
                print("[ClaimSync] ❌ ditto fallito (\(process.terminationStatus)): \(errorString)")
                return false
            }
        } catch {
            print("[ClaimSync] ❌ Errore estrazione: \(error.localizedDescription)")
            return false
        }
    }

    private func collectFiles(in path: String) -> [URL] {
        collectFilesWithRelativePaths(in: path).map { $0.0 }
    }
    
    private func collectFilesWithRelativePaths(in path: String) -> [(URL, String)] {
        let root = URL(fileURLWithPath: path)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var files: [(URL, String)] = []
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDir {
                let relativePath = url.path.replacingOccurrences(of: path + "/", with: "")
                if isInVersioningFolder(relativePath) { continue }
                if shouldExcludeFile(relativePath) { continue }
                files.append((url, relativePath))
            }
        }
        return files
    }
    
    /// PerX-cache/versioning resta locale: non sincronizziamo né includiamo in manifest.
    private func isInVersioningFolder(_ relativePath: String) -> Bool {
        let p = relativePath.lowercased().replacingOccurrences(of: "\\", with: "/")
        return p.contains("perx-cache/versioning")
    }
    
    /// File di sistema da escludere dalla sincronizzazione
    private func shouldExcludeFile(_ relativePath: String) -> Bool {
        let filename = (relativePath as NSString).lastPathComponent.lowercased()
        // Escludi file di sistema macOS/Windows
        if filename == ".ds_store" || filename == "thumbs.db" || filename == "messaggi.txt" {
            return true
        }
        // Escludi residui _local (vecchia logica conflitto rimossa)
        if filename.contains("_local") {
            return true
        }
        // Escludi file temporanei Windows (Excel, Word, ecc.)
        if filename.hasPrefix("~$") || filename.hasPrefix("-$") {
            return true
        }
        // Escludi file temporanei generici
        if filename.hasPrefix(".~") || filename.hasPrefix(".tmp") || filename.hasPrefix("tmp") {
            return true
        }
        // Escludi file con estensioni temporanee
        if filename.hasSuffix(".tmp") || filename.hasSuffix(".temp") || filename.hasSuffix(".partial") {
            return true
        }
        return false
    }
    
    /// Determina se un file è "generato" o "caricato dall'utente" e quindi non deve generare notifiche/badge
    private func isNotificationExcluded(_ relativePath: String) -> Bool {
        let filename = (relativePath as NSString).lastPathComponent.lowercased()
        let path = relativePath.lowercased().replacingOccurrences(of: "\\", with: "/")
        
        // 1. Cartella "Da Chiudere" (file di chiusura generati)
        if path.contains("/da chiudere/") || path.hasPrefix("da chiudere/") {
            return true
        }
        
        // 2. Pattern nomi file generati (Atto, Perizia, Verbale)
        let generatedPatterns = [
            "atto da firmare", "atto_da_firmare",
            "atto da inviare", "atto_da_inviare",
            "atto firmato", "atto_firmato",
            "chiusura", "perizia_", "verbale_",
            "file_unificati_", "messaggi.txt"
        ]
        
        for pattern in generatedPatterns {
            if filename.contains(pattern) {
                return true
            }
        }
        
        // 3. File di sistema o temporanei (già esclusi da sync ma per sicurezza)
        if shouldExcludeFile(relativePath) {
            return true
        }
        
        return false
    }

    /// Raccoglie tutti i path relativi delle directory (incluse quelle vuote). Esclude PerX-cache/versioning.
    private func collectDirectoriesRelativePaths(in basePath: String) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: basePath) else { return [] }
        var directories: [String] = []
        
        while let relativePath = enumerator.nextObject() as? String {
            let p = relativePath.lowercased().replacingOccurrences(of: "\\", with: "/")
            if p == "perx-cache/versioning" || p.hasPrefix("perx-cache/versioning/") {
                continue
            }
            let fullPath = (basePath as NSString).appendingPathComponent(relativePath)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                directories.append(relativePath)
            }
        }
        
        return directories
    }
    
    /// Sincronizza la struttura delle directory sul server (incluse quelle vuote)
    private func syncDirectoriesToServer(claimId: String, directories: [String]) async {
        guard !directories.isEmpty else { return }
        
        print("[ClaimSync] 📁 Sincronizzazione \(directories.count) directory sul server...")
        
        do {
            let request = CreateDirectoriesRequest(
                user_id: currentUserId(),
                claim_id: claimId,
                directories: directories
            )
            let _: GenericAPIResponse = try await apiClient.post("/api/claims/\(claimId)/mkdir", body: request)
            print("[ClaimSync] ✅ Directory sincronizzate sul server")
        } catch {
            // Non bloccare l'upload se la creazione directory fallisce
            print("[ClaimSync] ⚠️ Errore sincronizzazione directory: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Manifest Cache
    
    private func manifestCachePath(for riferimento: String) -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(manifestCacheFolder)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir.appendingPathComponent("\(riferimento).json")
    }
    
    /// Ottiene i file dal manifest locale (pubblico per FileService)
    func getManifestFiles(for riferimento: String) -> [ClaimFileEntry]? {
        return loadLocalManifest(for: riferimento)?.files
    }
    
    private func loadLocalManifest(for riferimento: String) -> LocalManifestCache? {
        let path = manifestCachePath(for: riferimento)
        guard let data = try? Data(contentsOf: path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LocalManifestCache.self, from: data)
    }
    
    private func saveLocalManifest(metadata: ClaimMetadata, for riferimento: String, overrides: [String: ClaimFileEntry]? = nil, localPath: String? = nil) {
        guard let files = metadata.files else { return }
        let resolved: [ClaimFileEntry]
        if let ov = overrides, !ov.isEmpty {
            resolved = files.map { ov[$0.relativePath] ?? $0 }
        } else {
            resolved = files
        }
        let localSnapshot = localPath.map { buildLocalSnapshotEntries(in: $0) }
        let cache = LocalManifestCache(
            claimId: metadata.claimId,
            lastSync: Date(),
            files: resolved,
            localSnapshot: localSnapshot
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(cache) {
            try? data.write(to: manifestCachePath(for: riferimento))
        }
    }
    
    /// Costruisce [ClaimFileEntry] dallo stato attuale della cartella (per localSnapshot / snapshot).
    private func buildLocalSnapshotEntries(in path: String) -> [ClaimFileEntry] {
        let allFiles = collectFilesWithRelativePaths(in: path)
        var entries: [ClaimFileEntry] = []
        entries.reserveCapacity(allFiles.count)
        for (url, relativePath) in allFiles {
            guard let data = try? Data(contentsOf: url) else { continue }
            let md5 = md5Hash(data: data)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? Int64(data.count)
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            entries.append(ClaimFileEntry(relativePath: relativePath, size: size, md5: md5, modifiedAt: modDate))
        }
        return entries
    }
    
    /// Fallback: salva uno snapshot basato sui file locali (incl. PerX-cache) per evitare re-upload ripetuti.
    private func saveLocalManifestSnapshot(fromLocalPath path: String, for riferimento: String) {
        let entries = buildLocalSnapshotEntries(in: path)
        let cache = LocalManifestCache(
            claimId: riferimento,
            lastSync: Date(),
            files: entries,
            localSnapshot: entries
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(cache) {
            try? data.write(to: manifestCachePath(for: riferimento))
        }
    }
    
    private func md5Hash(data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Debug Diagnostics
    
    /// Funzione diagnostica per test isolati: scarica un file singolo e stampa tutte le info
    func diagnosticDownloadFile(claimId: String, relativePath: String) async {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 DIAGNOSTIC DOWNLOAD FILE")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Claim ID: \(claimId)")
        print("File: \(relativePath)")
        
        do {
            let startTime = Date()
            let data = try await apiClient.downloadFile(
                claimId: claimId,
                userId: currentUserId(),
                relativePath: relativePath
            )
            let duration = Date().timeIntervalSince(startTime)
            
            print("✅ Download completato")
            print("Bytes ricevuti: \(data.count)")
            print("Durata: \(String(format: "%.2f", duration))s")
            print("Velocità: \(String(format: "%.2f", Double(data.count) / duration / 1024 / 1024)) MB/s")
            
            // SHA256
            let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            print("SHA256: \(sha256)")
            
            // MD5
            let md5 = md5Hash(data: data)
            print("MD5: \(md5)")
            
        } catch {
            print("❌ Errore: \(error.localizedDescription)")
        }
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    /// Funzione diagnostica per test isolati: scarica ZIP e stampa tutte le info
    func diagnosticDownloadZIP(claimId: String) async {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 DIAGNOSTIC DOWNLOAD ZIP")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Claim ID: \(claimId)")
        
        do {
            let startTime = Date()
            let tempURL = try await apiClient.downloadPackage(
                claimId: claimId,
                userId: currentUserId(),
                expectedTotalBytes: nil
            ) { progress, bytesDownloaded, bytesTotal, speed in
                print("Progress: \(Int(progress * 100))% - \(bytesDownloaded)/\(bytesTotal) bytes - \(String(format: "%.2f", speed / 1024 / 1024)) MB/s")
            }
            let duration = Date().timeIntervalSince(startTime)
            
            let zipSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
            
            print("✅ Download ZIP completato")
            print("ZIP size: \(zipSize) bytes")
            print("Durata: \(String(format: "%.2f", duration))s")
            print("Velocità: \(String(format: "%.2f", Double(zipSize) / duration / 1024 / 1024)) MB/s")
            
            // SHA256
            if let sha256 = sha256Hash(fileURL: tempURL) {
                print("SHA256: \(sha256)")
            }
            
            // Cleanup
            try? FileManager.default.removeItem(at: tempURL)
            
        } catch {
            print("❌ Errore: \(error.localizedDescription)")
        }
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    private func sha256Hash(fileURL: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? fileHandle.close() }
        
        var hasher = SHA256()
        let chunkSize = 1024 * 1024 // 1MB chunks
        
        fileHandle.seek(toFileOffset: 0)
        while true {
            let data = fileHandle.readData(ofLength: chunkSize)
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Valida l'integrità di un file scaricato confrontando l'MD5 con quello atteso
    private func validateFileIntegrity(filePath: String, expectedMD5: String, activeDirectory: String) -> Bool {
        let operation: () -> Bool = { [weak self] in
            guard let self = self else { return false }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
                print("[ClaimSync] ⚠️ Impossibile leggere file per validazione: \(filePath)")
                return false
            }
            
            let actualMD5 = self.md5Hash(data: data)
            let isValid = actualMD5.lowercased() == expectedMD5.lowercased()
            
            if !isValid {
                print("[ClaimSync] ❌ Validazione MD5 fallita per \(filePath)")
                print("[ClaimSync]   Atteso: \(expectedMD5)")
                print("[ClaimSync]   Ottenuto: \(actualMD5)")
            }
            
            return isValid
        }
        
        if !activeDirectory.isEmpty && filePath.hasPrefix(activeDirectory) {
            return self.fileService.performWithSecurityScopedAccess(to: activeDirectory, operation: operation) ?? false
        } else {
            return operation()
        }
    }
    
    /// Cancella un file con security-scoped access se necessario
    private func deleteFileWithAccess(at path: String, activeDirectory: String) {
        let operation: () -> Void = {
            try? FileManager.default.removeItem(atPath: path)
        }
        
        if !activeDirectory.isEmpty && path.hasPrefix(activeDirectory) {
            self.fileService.performWithSecurityScopedAccess(to: activeDirectory, operation: { operation(); return true })
        } else {
            operation()
        }
    }

    private func detectRemoteChanges(metadata: ClaimMetadata, isNewDownload: Bool) {
        // Non generare task per download da zero o prima connessione
        guard !isNewDownload else { return }
        guard isFirstSyncCompleted(for: metadata.claimId) else { return }
        
        guard let localPath = fileService.getSinistroPath(riferimento: metadata.claimId) else { return }
        let localCount = collectFiles(in: localPath).count
        if metadata.totalFiles > localCount {
            TaskManager.shared.createNewDocumentationTask(sinistroID: metadata.claimId)
        }
    }
    
    private func scheduleFallbackDownloadCheck(riferimento: String) {
        guard !isFileModeCloud else { return }
        Task.detached { [weak self] in
            guard let self else { return }
            let nanos = UInt64(self.fallbackDownloadInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            
            await MainActor.run {
                let hasFolder = self.fileService.getSinistroPath(riferimento: riferimento) != nil
                let status = self.statuses[riferimento] ?? .notDownloaded
                let isOk: Bool
                switch status {
                case .upToDate, .uploading:
                    isOk = true
                default:
                    isOk = false
                }
                
                if !hasFolder && !isOk {
                    TaskManager.shared.createManualDownloadFallbackTask(sinistroID: riferimento)
                }
            }
        }
    }

    private func fetchSinistro(by riferimento: String) -> Sinistro? {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        return try? context.fetch(request).first
    }
    
    // MARK: - Assignment Helpers
    
    /// Verifica se un sinistro è assegnato all'utente corrente
    private func isSinistroAssignedToCurrentUser(_ sinistro: Sinistro) -> Bool {
        guard let currentUserEmail = AppState.shared.googleAuthService.userEmail?.lowercased(),
              !currentUserEmail.isEmpty else {
            return false
        }
        
        let assignedEmail = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail ?? "").lowercased()
        return assignedEmail == currentUserEmail && !assignedEmail.isEmpty
    }
    
    /// Verifica se un sinistro è in uno stato terminale (chiusa, revocata, annullata)
    private func isSinistroInTerminalState(_ sinistro: Sinistro) -> Bool {
        let terminalStates = [
            StatoManager.StatoSinistro.chiusa.descrizione,
            StatoManager.StatoSinistro.revocata.descrizione,
            StatoManager.StatoSinistro.annullata.descrizione
        ]
        guard let stato = sinistro.stato else { return false }
        return terminalStates.contains(stato)
    }
    
    /// Verifica se un sinistro dovrebbe essere monitorato (assegnato all'utente e non in stato terminale)
    private func shouldMonitorSinistro(_ sinistro: Sinistro) -> Bool {
        return isSinistroAssignedToCurrentUser(sinistro) && !isSinistroInTerminalState(sinistro)
    }
    
    // MARK: - Temporary Sync Management
    
    /// Avvia sync temporaneo per un sinistro non proprio o in stato terminale
    func startTemporarySync(for sinistro: Sinistro) async {
        guard let riferimento = sinistro.riferimento else { return }
        
        let isNonOwner = !isSinistroAssignedToCurrentUser(sinistro)
        let isTerminalState = isSinistroInTerminalState(sinistro)
        
        // Solo se non è assegnato all'utente o è in stato terminale
        guard isNonOwner || isTerminalState else {
            // Se è assegnato e non terminale, usa il sync normale
            return
        }
        
        print("[ClaimSync] 🔄 Avvio sync temporaneo per sinistro \(riferimento) (non-owner: \(isNonOwner), terminale: \(isTerminalState))")
        
        // Registra il sinistro per il sync temporaneo
        temporarySyncClaims[riferimento] = TemporarySyncInfo(
            openedAt: Date(),
            isNonOwner: isNonOwner,
            isTerminalState: isTerminalState
        )
        saveTemporarySyncClaims()
        
        // Registra presso l'agent per il monitoring
        guard agentReachable else { return }
        
        do {
            let req = RegisterMonitoringRequest(
                user_id: currentUserId(),
                claim_id: riferimento,
                path_hint: nil
            )
            let _: GenericAPIResponse = try await apiClient.post("/api/monitoring/register", body: req)
            print("[ClaimSync] ✅ Sinistro \(riferimento) registrato per sync temporaneo")
        } catch {
            print("[ClaimSync] ⚠️ Errore registrazione sync temporaneo \(riferimento): \(error.localizedDescription)")
        }
        
        // Avvia sync immediato
        if let sinistro = fetchSinistro(by: riferimento) {
            await registerAndSyncIfNeeded(sinistro: sinistro, forceDownload: true)
        }
    }
    
    /// Ferma sync temporaneo quando il sinistro viene chiuso
    func stopTemporarySync(for riferimento: String) async {
        guard temporarySyncClaims[riferimento] != nil else { return }
        
        print("[ClaimSync] ⏹️ Fermo sync temporaneo per sinistro \(riferimento)")
        
        // Disiscrivi dal monitoring
        guard agentReachable else {
            // Rimuovi comunque dalla lista locale
            temporarySyncClaims.removeValue(forKey: riferimento)
            saveTemporarySyncClaims()
            return
        }
        
        do {
            let req = RegisterMonitoringRequest(
                user_id: currentUserId(),
                claim_id: riferimento,
                path_hint: nil
            )
            let _: GenericAPIResponse = try await apiClient.post("/api/monitoring/unregister", body: req)
            print("[ClaimSync] ✅ Sinistro \(riferimento) disiscritto dal monitoring (sync temporaneo)")
        } catch {
            print("[ClaimSync] ⚠️ Errore disiscrizione sync temporaneo \(riferimento): \(error.localizedDescription)")
        }
        
        // Rimuovi dalla lista locale e schedula cleanup dopo 3 giorni
        if let info = temporarySyncClaims[riferimento] {
            temporarySyncClaims.removeValue(forKey: riferimento)
            saveTemporarySyncClaims()
            
            // Schedula rimozione file dopo 3 giorni
            scheduleTemporarySyncCleanup(riferimento: riferimento, openedAt: info.openedAt)
        }
    }
    
    /// Schedula la rimozione dei file dopo 3 giorni
    private func scheduleTemporarySyncCleanup(riferimento: String, openedAt: Date) {
        let cleanupDate = openedAt.addingTimeInterval(TimeInterval(temporarySyncCleanupDays * 24 * 60 * 60))
        
        var cleanupSchedule: [String: String] = [:]
        if let existing = UserDefaults.standard.dictionary(forKey: temporarySyncKey + ".cleanup") as? [String: String] {
            cleanupSchedule = existing
        }
        
        let formatter = ISO8601DateFormatter()
        cleanupSchedule[riferimento] = formatter.string(from: cleanupDate)
        UserDefaults.standard.set(cleanupSchedule, forKey: temporarySyncKey + ".cleanup")
        
        print("[ClaimSync] 📅 Rimozione file per \(riferimento) schedulata per \(formatter.string(from: cleanupDate))")
    }
    
    /// Esegue cleanup dei file per sinistri temporanei scaduti e scansiona cartelle locali per trovare sinistri da rimuovere
    func performTemporarySyncCleanup() async {
        // 1. Scansiona tutte le cartelle locali e metti in lista quelle che non rispettano i requisiti
        await scanAndScheduleInvalidLocalFolders()
        
        // 2. Esegui cleanup dei file scaduti
        guard let cleanupSchedule = UserDefaults.standard.dictionary(forKey: temporarySyncKey + ".cleanup") as? [String: String] else {
            return
        }
        
        let now = Date()
        let formatter = ISO8601DateFormatter()
        var updatedSchedule = cleanupSchedule
        
        for (riferimento, dateString) in cleanupSchedule {
            guard let cleanupDate = formatter.date(from: dateString),
                  now >= cleanupDate else {
                continue
            }
            
            // Rimuovi i file locali
            if let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) {
                print("[ClaimSync] 🗑️ Rimozione file per sinistro temporaneo \(riferimento)")
                
                do {
                    try FileManager.default.removeItem(atPath: sinistroPath)
                    print("[ClaimSync] ✅ File rimossi per \(riferimento)")
                } catch {
                    print("[ClaimSync] ⚠️ Errore rimozione file \(riferimento): \(error.localizedDescription)")
                }
            }
            
            // Rimuovi dallo stato
            statuses.removeValue(forKey: riferimento)
            
            // Rimuovi dalla schedule
            updatedSchedule.removeValue(forKey: riferimento)
        }
        
        if updatedSchedule.count != cleanupSchedule.count {
            UserDefaults.standard.set(updatedSchedule, forKey: temporarySyncKey + ".cleanup")
        }
    }
    
    /// Scansiona tutte le cartelle locali e mette in lista per l'eliminazione quelle che non rispettano i requisiti
    private func scanAndScheduleInvalidLocalFolders() async {
        print("[ClaimSync] 🔍 Scansione cartelle locali per trovare sinistri da rimuovere...")
        
        // Usa la cartella interna Application Support
        let claimsPath = fileService.getInternalClaimsPath()
        let validDirectories = [claimsPath]
        
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        
        var foundInvalidFolders: [String] = []
        
        for baseDirectory in validDirectories {
            guard let folderContents = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: baseDirectory),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            
            for folderURL in folderContents {
                guard let isDirectory = try? folderURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                      isDirectory == true else {
                    continue
                }
                
                let riferimento = folderURL.lastPathComponent
                
                // Verifica se è un riferimento valido (7 caratteri)
                guard riferimento.count == 7 else {
                    continue
                }
                
                // Cerca il sinistro nel database
                request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
                guard let sinistro = try? context.fetch(request).first else {
                    // Sinistro non trovato nel database, metti in lista per rimozione
                    print("[ClaimSync] 📋 Sinistro \(riferimento) trovato localmente ma non nel database, schedulato per rimozione")
                    foundInvalidFolders.append(riferimento)
                    continue
                }
                
                // Verifica se il sinistro dovrebbe essere monitorato
                if !shouldMonitorSinistro(sinistro) {
                    // Verifica se è già in lista per l'eliminazione
                    var cleanupSchedule: [String: String] = [:]
                    if let existing = UserDefaults.standard.dictionary(forKey: temporarySyncKey + ".cleanup") as? [String: String] {
                        cleanupSchedule = existing
                    }
                    
                    // Se non è già in lista, aggiungilo
                    if cleanupSchedule[riferimento] == nil {
                        print("[ClaimSync] 📋 Sinistro \(riferimento) non assegnato all'utente o in stato terminale, schedulato per rimozione")
                        foundInvalidFolders.append(riferimento)
                    }
                }
            }
        }
        
        // Metti in lista per l'eliminazione tutti i sinistri trovati
        if !foundInvalidFolders.isEmpty {
            let now = Date()
            let cleanupDate = now.addingTimeInterval(TimeInterval(temporarySyncCleanupDays * 24 * 60 * 60))
            let formatter = ISO8601DateFormatter()
            
            var cleanupSchedule: [String: String] = [:]
            if let existing = UserDefaults.standard.dictionary(forKey: temporarySyncKey + ".cleanup") as? [String: String] {
                cleanupSchedule = existing
            }
            
            for riferimento in foundInvalidFolders {
                // Aggiungi solo se non è già presente
                if cleanupSchedule[riferimento] == nil {
                    cleanupSchedule[riferimento] = formatter.string(from: cleanupDate)
                    print("[ClaimSync] 📅 Sinistro \(riferimento) aggiunto alla lista di rimozione (scadenza: \(formatter.string(from: cleanupDate)))")
                }
            }
            
            UserDefaults.standard.set(cleanupSchedule, forKey: temporarySyncKey + ".cleanup")
            print("[ClaimSync] ✅ Scansione completata: \(foundInvalidFolders.count) sinistri aggiunti alla lista di rimozione")
        } else {
            print("[ClaimSync] ✅ Scansione completata: nessun sinistro da rimuovere")
        }
    }
    
    /// Carica sinistri con sync temporanea da UserDefaults
    private func loadTemporarySyncClaims() {
        guard let data = UserDefaults.standard.data(forKey: temporarySyncKey),
              let decoded = try? JSONDecoder().decode([String: TemporarySyncInfo].self, from: data) else {
            return
        }
        temporarySyncClaims = decoded
    }
    
    /// Salva sinistri con sync temporanea in UserDefaults
    private func saveTemporarySyncClaims() {
        guard let data = try? JSONEncoder().encode(temporarySyncClaims) else { return }
        UserDefaults.standard.set(data, forKey: temporarySyncKey)
    }
    
    /// Verifica se un sinistro ha sync temporanea attiva
    func hasTemporarySync(for riferimento: String) -> Bool {
        return temporarySyncClaims[riferimento] != nil
    }

    private func setStatus(_ status: ClaimSyncStatus, for riferimento: String) {
        statuses[riferimento] = status
        // Mantieni il Mac sveglio durante trasferimenti lunghi (solo su alimentazione)
        let hasActive = statuses.values.contains { $0.isActive }
        sleepManager.update(shouldPreventSleep: hasActive)
    }
}

// MARK: - DTO helper

private struct RegisterMonitoringRequest: Codable {
    let user_id: String
    let claim_id: String
    let path_hint: String?
}

/// Request per creare directory sul server (incluse quelle vuote)
private struct CreateDirectoriesRequest: Codable {
    let user_id: String
    let claim_id: String
    let directories: [String]
}

// Nota: Notification.Name.claimFolderChanged è definito in StatoManager.swift

