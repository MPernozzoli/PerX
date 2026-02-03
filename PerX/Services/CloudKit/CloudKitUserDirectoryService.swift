import Foundation
import CloudKit
import Combine
import AppKit

/// Directory utenti basata su CloudKit: contiene solo chi ha abilitato la sync iCloud.
@MainActor
final class CloudKitUserDirectoryService: ObservableObject {
    static let shared = CloudKitUserDirectoryService()
    
    /// Stato di connessione utente
    enum OnlineStatus: String, Codable {
        case online    // app aperta, computer attivo
        case recent    // online negli ultimi 15 min
        case offline   // più di 15 min senza attività
        
        var color: NSColor {
            switch self {
            case .online:  return .systemGreen
            case .recent:  return .systemYellow
            case .offline: return .systemRed
            }
        }
        
        var label: String {
            switch self {
            case .online:  return "Online"
            case .recent:  return "Visto di recente"
            case .offline: return "Offline"
            }
        }
    }
    
    /// Luogo di lavoro sincronizzato via CloudKit
    enum WorkLocation: String, Codable {
        case office  // ufficio
        case remote  // remoto
        case notWorking // non lavora oggi
        
        var icon: String {
            switch self {
            case .office: return "building.2.fill"
            case .remote: return "house.fill"
            case .notWorking: return "moon.zzz.fill"
            }
        }
        
        var label: String {
            switch self {
            case .office: return "In ufficio"
            case .remote: return "Da remoto"
            case .notWorking: return "Non lavora oggi"
            }
        }
    }
    
    struct CloudUser: Identifiable, Codable, Equatable {
        var id: String { email }
        let email: String
        let displayName: String
        let lastSeenAt: Date
        var workScheduleToday: String?     // es. "09:00-13:00, 14:00-18:00"
        var workLocation: WorkLocation?
        var isComputerActive: Bool         // computer non in standby
        
        init(email: String, displayName: String, lastSeenAt: Date,
             workScheduleToday: String? = nil, workLocation: WorkLocation? = nil,
             isComputerActive: Bool = false) {
            self.email = email
            self.displayName = displayName
            self.lastSeenAt = lastSeenAt
            self.workScheduleToday = workScheduleToday
            self.workLocation = workLocation
            self.isComputerActive = isComputerActive
        }
        
        /// Calcola lo stato online
        var onlineStatus: OnlineStatus {
            let now = Date()
            let diff = now.timeIntervalSince(lastSeenAt)
            
            // Online: visto negli ultimi 2 minuti (più permissivo per latenza CloudKit)
            if diff < 120 {
                return .online
            }
            // Recent: visto negli ultimi 15 min
            if diff < 15 * 60 {
                return .recent
            }
            return .offline
        }
    }
    
    @Published private(set) var users: [CloudUser] = []
    @Published private(set) var status: String = "idle"
    
    /// Indicatori di digitazione: [roomId: [userEmail: timestamp]]
    @Published private(set) var typingIndicators: [String: [String: Date]] = [:]
    
    private let container: CKContainer
    private let publicDB: CKDatabase
    private let settings = CloudKitSettingsService.shared
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var heartbeatTimer: Timer?
    private var screenSleepObserver: Any?
    private var screenWakeObserver: Any?
    private var isComputerSleeping = false
    
    private enum RecordType {
        static let perxUser = "PerXUser"
        static let typingIndicator = "TypingIndicator"
    }
    
    private enum Keys {
        static let email = "email"
        static let displayName = "displayName"
        static let lastSeenAt = "lastSeenAt"
        static let cloudSyncEnabled = "cloudSyncEnabled"
        static let workScheduleToday = "workScheduleToday"
        static let workLocation = "workLocation"
        static let isComputerActive = "isComputerActive"
        // Typing
        static let roomId = "roomId"
        static let typingAt = "typingAt"
    }
    
    private init(container: CKContainer = CKContainer(identifier: "iCloud.it.pernozzoli.PerX")) {
        self.container = container
        self.publicDB = container.publicCloudDatabase
        
        settings.$isEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    Task { await self.start() }
                } else {
                    self.stop()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshNow(reason: "appActive") }
            }
            .store(in: &cancellables)
        
        // Aggiorna CloudKit quando cambia l'orario di lavoro
        NotificationCenter.default.publisher(for: .workScheduleChanged)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.registerCurrentUserIfPossible() }
            }
            .store(in: &cancellables)
        
        setupSleepWakeObservers()
    }
    
    private func setupSleepWakeObservers() {
        // Osserva quando il computer va in sleep/standby
        screenSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isComputerSleeping = true
            Task { await self?.updateComputerActiveStatus(active: false) }
        }
        
        screenWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isComputerSleeping = false
            Task { await self?.updateComputerActiveStatus(active: true) }
        }
    }
    
    func start() async {
        guard settings.isEnabled else {
            stop()
            return
        }
        
        await registerCurrentUserIfPossible()
        await refreshNow(reason: "start")
        startTimer()
        startHeartbeatTimer()
        await setupSubscription()
    }
    
    func stop() {
        status = "idle"
        users = []
        stopTimer()
        stopHeartbeatTimer()
        removeSleepWakeObservers()
    }
    
    private func removeSleepWakeObservers() {
        if let sleepObserver = screenSleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            screenSleepObserver = nil
        }
        if let wakeObserver = screenWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            screenWakeObserver = nil
        }
    }
    
    deinit {
        // Rimuovi observer senza chiamare stop() che è @MainActor
        if let sleepObserver = screenSleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        if let wakeObserver = screenWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        timer?.invalidate()
        heartbeatTimer?.invalidate()
    }
    
    // MARK: - Typing Indicator
    
    /// Segnala che l'utente sta scrivendo in una room
    func setTyping(in roomId: String) async {
        guard settings.isEnabled else { return }
        guard let email = GoogleAuthService.shared.userEmail?.lowercased() else { return }
        
        let recordID = CKRecord.ID(recordName: "\(roomId)_\(email)")
        
        for attempt in 1...Self.maxRetries {
            do {
                // Fetch esistente o crea nuovo
                let record = (try? await publicDB.fetchRecordAsync(recordID)) ?? CKRecord(recordType: RecordType.typingIndicator, recordID: recordID)
                record[Keys.roomId] = roomId as CKRecordValue
                record[Keys.email] = email as CKRecordValue
                record[Keys.typingAt] = Date() as CKRecordValue
                _ = try await saveRecordWithConflictHandling(record, db: publicDB)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                if attempt < Self.maxRetries {
                    let backoffMs = min(500, 50 * Int(pow(2.0, Double(attempt - 1))))
                    try? await Task.sleep(nanoseconds: UInt64(backoffMs * 1_000_000))
                    continue
                }
            } catch {
                return // Ignora errori typing
            }
        }
    }
    
    /// Ottieni chi sta scrivendo in una room (escluso utente corrente)
    func fetchTypingUsers(in roomId: String) async -> [CloudUser] {
        guard settings.isEnabled else { return [] }
        let currentEmail = GoogleAuthService.shared.userEmail?.lowercased() ?? ""
        
        // Typing valido: ultimi 15 secondi (margine per latenza CloudKit)
        let threshold = Date().addingTimeInterval(-15)
        let pred = NSPredicate(format: "%K == %@ AND %K > %@",
                               Keys.roomId, roomId, Keys.typingAt, threshold as NSDate)
        let query = CKQuery(recordType: RecordType.typingIndicator, predicate: pred)
        
        do {
            let records = try await publicDB.performQueryAsync(query)
            let emails = records.compactMap { $0[Keys.email] as? String }
                .filter { $0.lowercased() != currentEmail }
            return users.filter { emails.contains($0.email.lowercased()) }
        } catch {
            print("[CloudKitUserDirectory] ⚠️ fetchTypingUsers error in \(roomId)")
            return []
        }
    }
    
    /// Pulisce l'indicatore di digitazione (es. messaggio inviato)
    func clearTyping(in roomId: String) async {
        guard settings.isEnabled else { return }
        guard let email = GoogleAuthService.shared.userEmail?.lowercased() else { return }
        
        let recordID = CKRecord.ID(recordName: "\(roomId)_\(email)")
        do {
            try await publicDB.deleteRecordAsync(recordID)
        } catch {
            // Ignora
        }
    }
    
    func refreshNow(reason: String) async {
        guard settings.isEnabled else { return }
        status = "loading:\(reason)"
        defer { status = "ready" }
        
        do {
            let query = CKQuery(
                recordType: RecordType.perxUser,
                predicate: NSPredicate(format: "%K == 1", Keys.cloudSyncEnabled)
            )
            query.sortDescriptors = [NSSortDescriptor(key: Keys.lastSeenAt, ascending: false)]
            
            let records = try await publicDB.performQueryAsync(query)
            let mapped: [CloudUser] = records.compactMap { rec in
                guard
                    let email = (rec[Keys.email] as? String)?.lowercased(),
                    !email.isEmpty
                else { return nil }
                
                let name = (rec[Keys.displayName] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName = (name?.isEmpty == false) ? name! : email.components(separatedBy: "@").first?.replacingOccurrences(of: ".", with: " ").capitalized ?? email
                let lastSeen = (rec[Keys.lastSeenAt] as? Date) ?? rec.modificationDate ?? Date.distantPast
                let workSchedule = rec[Keys.workScheduleToday] as? String
                let workLocRaw = rec[Keys.workLocation] as? String
                let workLocation = workLocRaw.flatMap { WorkLocation(rawValue: $0) }
                let isActive = (rec[Keys.isComputerActive] as? Int ?? 0) == 1
                
                return CloudUser(
                    email: email,
                    displayName: displayName,
                    lastSeenAt: lastSeen,
                    workScheduleToday: workSchedule,
                    workLocation: workLocation,
                    isComputerActive: isActive
                )
            }
            
            // Dedup by email
            var unique: [String: CloudUser] = [:]
            for u in mapped { unique[u.email] = u }
            users = unique.values.sorted { $0.displayName < $1.displayName }
        } catch {
            status = "error:\(error.localizedDescription)"
            print("[CloudKitUserDirectory] ❌ \(error)")
        }
    }
    
    /// Ottiene un utente per email
    func user(email: String) -> CloudUser? {
        users.first { $0.email.lowercased() == email.lowercased() }
    }
    
    // MARK: - Registration
    
    /// Numero massimo di retry per conflitti CloudKit
    private static let maxRetries = 5
    
    private func registerCurrentUserIfPossible() async {
        guard settings.isEnabled else { return }
        guard let email = GoogleAuthService.shared.userEmail?.lowercased(), !email.isEmpty else { return }
        
        // Nome utente: preferisci impostazioni, fallback email
        let displayName: String = {
            let fromDefaults = UserDefaults.standard.string(forKey: "userName")?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let fromDefaults, !fromDefaults.isEmpty { return fromDefaults }
            return email.components(separatedBy: "@").first?.replacingOccurrences(of: ".", with: " ").capitalized ?? email
        }()
        
        // Calcola orario e luogo di lavoro per oggi
        let (workScheduleToday, workLocation) = getCurrentWorkScheduleInfo()
        
        let recordID = CKRecord.ID(recordName: email)
        
        for attempt in 1...Self.maxRetries {
            do {
                // Fetch fresh per evitare conflitti
                let record = (try? await publicDB.fetchRecordAsync(recordID)) ?? CKRecord(recordType: RecordType.perxUser, recordID: recordID)
                
                // Aggiorna solo i campi necessari (preserva altri campi modificati da altri)
                record[Keys.email] = email as CKRecordValue
                record[Keys.displayName] = displayName as CKRecordValue
                record[Keys.lastSeenAt] = Date() as CKRecordValue
                record[Keys.cloudSyncEnabled] = true as CKRecordValue
                record[Keys.workScheduleToday] = workScheduleToday as CKRecordValue?
                record[Keys.workLocation] = workLocation?.rawValue as CKRecordValue?
                record[Keys.isComputerActive] = (!isComputerSleeping ? 1 : 0) as CKRecordValue
                
                // Usa CKModifyRecordsOperation con savePolicy per gestire meglio i conflitti
                _ = try await saveRecordWithConflictHandling(record, db: publicDB)
                return // Successo
            } catch let error as CKError where error.code == .serverRecordChanged {
                // Conflitto: retry con backoff esponenziale
                if attempt < Self.maxRetries {
                    let backoffMs = min(1000, 100 * Int(pow(2.0, Double(attempt - 1)))) // 100ms, 200ms, 400ms, 800ms, max 1000ms
                    try? await Task.sleep(nanoseconds: UInt64(backoffMs * 1_000_000))
                    continue
                }
                // Dopo tutti i retry, usa il record server se disponibile
                if let serverRecord = error.serverRecord {
                    do {
                        serverRecord[Keys.lastSeenAt] = Date() as CKRecordValue
                        serverRecord[Keys.isComputerActive] = (!isComputerSleeping ? 1 : 0) as CKRecordValue
                        _ = try await saveRecordWithConflictHandling(serverRecord, db: publicDB)
                        return
                    } catch {
                        print("[CloudKitUserDirectory] ⚠️ registerCurrentUser conflict after \(attempt) attempts (server record merge failed)")
                    }
                } else {
                    print("[CloudKitUserDirectory] ⚠️ registerCurrentUser conflict after \(attempt) attempts")
                }
            } catch {
                print("[CloudKitUserDirectory] ⚠️ registerCurrentUser error: \(error)")
                return
            }
        }
    }
    
    /// Aggiorna solo lo stato attivo del computer (senza refreshare tutto)
    private func updateComputerActiveStatus(active: Bool) async {
        guard settings.isEnabled else { return }
        guard let email = GoogleAuthService.shared.userEmail?.lowercased() else { return }
        
        let recordID = CKRecord.ID(recordName: email)
        
        for attempt in 1...Self.maxRetries {
            do {
                let record = try await publicDB.fetchRecordAsync(recordID)
                record[Keys.isComputerActive] = (active ? 1 : 0) as CKRecordValue
                record[Keys.lastSeenAt] = Date() as CKRecordValue
                _ = try await saveRecordWithConflictHandling(record, db: publicDB)
                return // Successo
            } catch let error as CKError where error.code == .serverRecordChanged {
                // Conflitto: retry con backoff esponenziale
                if attempt < Self.maxRetries {
                    let backoffMs = min(1000, 100 * Int(pow(2.0, Double(attempt - 1))))
                    try? await Task.sleep(nanoseconds: UInt64(backoffMs * 1_000_000))
                    continue
                }
                // Usa server record se disponibile
                if let serverRecord = error.serverRecord {
                    serverRecord[Keys.isComputerActive] = (active ? 1 : 0) as CKRecordValue
                    serverRecord[Keys.lastSeenAt] = Date() as CKRecordValue
                    _ = try? await saveRecordWithConflictHandling(serverRecord, db: publicDB)
                }
            } catch {
                return // Altri errori: ignora
            }
        }
    }
    
    /// Calcola orario di lavoro e luogo per oggi in base a WorkScheduleManager
    private func getCurrentWorkScheduleInfo() -> (String?, WorkLocation?) {
        let manager = WorkScheduleManager.shared
        let today = Date()
        
        // Se non è giorno lavorativo
        if !manager.isWorkingDay(today) {
            return (nil, .notWorking)
        }
        
        let hours = manager.getWorkingHours(for: today)
        guard !hours.isEmpty else {
            return (nil, .notWorking)
        }
        
        // Formatta orario (es. "09:00-13:00, 14:00-18:00")
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        let scheduleStr = hours.map { wh in
            "\(formatter.string(from: wh.start))-\(formatter.string(from: wh.end))"
        }.joined(separator: ", ")
        
        // Luogo: preferisci il primo orario, oppure office se misto
        let locations = hours.map(\.place)
        let location: WorkLocation
        if locations.allSatisfy({ $0 == .remote }) {
            location = .remote
        } else if locations.allSatisfy({ $0 == .office }) {
            location = .office
        } else {
            // Misto: indica ufficio (prevalente)
            location = .office
        }
        
        return (scheduleStr, location)
    }
    
    // MARK: - Subscription (best-effort)
    
    private func setupSubscription() async {
        // Nota: la ricezione immediata dipende dalle push CloudKit; teniamo anche polling.
        let subscriptionID = "perx-users-changes"
        let subscription = CKQuerySubscription(
            recordType: RecordType.perxUser,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        
        do {
            _ = try await publicDB.save(subscription)
        } catch {
            // ok: polling
        }
    }
    
    // MARK: - Timer
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.registerCurrentUserIfPossible(); await self.refreshNow(reason: "timer") }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Heartbeat per lo stato online (ogni 15 secondi per sincronizzazione rapida)
    private func startHeartbeatTimer() {
        stopHeartbeatTimer()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.registerCurrentUserIfPossible() }
        }
    }
    
    private func stopHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    // MARK: - CloudKit wrappers (using shared extensions)
    
    /// Salva record con gestione conflitti migliorata usando CKModifyRecordsOperation
    private func saveRecordWithConflictHandling(_ record: CKRecord, db: CKDatabase) async throws -> CKRecord {
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys // Salva solo i campi modificati, evita sovrascritture
            operation.qualityOfService = .userInitiated
            operation.database = db
            
            operation.modifyRecordsCompletionBlock = { saved, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                // Restituisce il record salvato o quello originale se non disponibile
                continuation.resume(returning: saved?.first ?? record)
            }
            
            db.add(operation)
        }
    }
}

