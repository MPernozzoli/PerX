import Foundation
import CloudKit
import Combine
import CoreData

@MainActor
final class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()

    enum SyncStatus: Equatable {
        case idle
        case unavailable(String)
        case ready
        case syncing(String)
        case error(String)
    }

    @Published private(set) var status: SyncStatus = .idle
    @Published private(set) var lastSyncAt: Date?

    let container: CKContainer
    let publicDB: CKDatabase
    let privateDB: CKDatabase

    private let settings = CloudKitSettingsService.shared
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var currentUserEmail: String?

    private init(container: CKContainer = CKContainer(identifier: "iCloud.it.pernozzoli.PerX")) {
        self.container = container
        self.publicDB = container.publicCloudDatabase
        self.privateDB = container.privateCloudDatabase

        settings.$isEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.start()
                } else {
                    self.stop()
                }
            }
            .store(in: &cancellables)

        settings.$syncFrequencySeconds
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.restartTimerIfNeeded()
            }
            .store(in: &cancellables)
    }

    func configureCurrentUser(email: String?) {
        // Per CK usiamo username (da CurrentUserService) per assignedToUserEmail
        self.currentUserEmail = CurrentUserService.shared.currentUsername
            ?? email.flatMap { UserProfile.generateUsername(from: $0) }
            ?? email
    }

    func startIfEnabled(email: String?) {
        configureCurrentUser(email: email)
        guard settings.isEnabled else {
            status = .idle
            stopTimer()
            return
        }
        start()
    }

    func start() {
        stopTimer()

        Task { [weak self] in
            guard let self else { return }
            await self.refreshAccountStatus()
            self.restartTimerIfNeeded()
        }
    }

    func stop() {
        status = .idle
        stopTimer()
    }

    func syncNow(reason: String = "manual") async {
        guard settings.isEnabled else { return }

        await refreshAccountStatus()
        guard case .ready = status else { return }

        status = .syncing(reason)
        defer {
            status = .ready
            lastSyncAt = Date()
        }

        do {
            _ = try await fetchUserRecordID()
            
            // Shared settings/secrets (comuni per tutti) + user secrets (per-utente)
            await CloudKitSharedUserDefaultsSyncService.shared.sync(container: container)
            await CloudKitKeychainSyncService.shared.syncSharedSecrets(container: container)
            let context = PersistenceController.shared.container.viewContext
            try await syncSinistri(context: context)
            if let email = currentUserEmail?.lowercased(), !email.isEmpty {
                await CloudKitUserDefaultsSyncService.shared.sync(container: container, userEmail: email)
                await CloudKitKeychainSyncService.shared.syncUserSecrets(container: container, userEmail: email)
                await CloudKitProcessedEmailSyncService.shared.sync(container: container, userEmail: email, context: context)
                await CloudKitTasksSyncService.shared.sync(container: container, userEmail: email)
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - CloudKit primitives

    private enum RecordTypes {
        static let sinistro = "Sinistro"
        static let diarioEntry = "DiarioEntry"
    }

    private enum SinistroKeys {
        static let riferimento = "riferimento"
        static let stato = "stato"
        static let numeroSinistroCompagnia = "numeroSinistroCompagnia"
        static let nomeCompagnia = "nomeCompagnia"
        static let nomeAssicurato = "nomeAssicurato"
        static let dataAssegnazione = "dataAssegnazione"
        static let dataChiusura = "dataChiusura"
        static let richiesta = "richiesta"
        static let liquidato = "liquidato"
        static let dannoAccertato = "dannoAccertato"
        static let assignedToUserEmail = "assignedToUserEmail"
        static let assignedToUserName = "assignedToUserName"
        static let substate = "substate"
        static let lastModifiedBy = "lastModifiedBy"
        static let lastModifiedAt = "lastModifiedAt"
        static let version = "version"
    }

    private enum DiarioKeys {
        static let entryId = "entryId"
        static let sinistroRiferimento = "sinistroRiferimento"
        static let timestamp = "timestamp"
        static let tipo = "tipo"
        static let titolo = "titolo"
        static let riassunto = "riassunto"
        static let contenutoCompleto = "contenutoCompleto"
        static let createdBy = "createdBy"
    }

    func fetchUserRecordID() async throws -> CKRecord.ID {
        try await container.fetchUserRecordIDAsync()
    }

    // MARK: - CloudKit wrappers (using shared extensions)

    // MARK: - Sinistri sync

    private func syncSinistri(context: NSManagedObjectContext) async throws {
        guard let currentUser = currentUserEmail?.lowercased(), !currentUser.isEmpty else { return }
        let currentEmail = CurrentUserService.shared.currentEmail?.lowercased() ?? ""

        // 1) Pull: sinistri assegnati all'utente (username o email per retrocompat)
        let predicate: NSPredicate
        if !currentEmail.isEmpty && currentEmail != currentUser {
            predicate = NSPredicate(format: "%K == %@ OR %K == %@", SinistroKeys.assignedToUserEmail, currentUser, SinistroKeys.assignedToUserEmail, currentEmail)
        } else {
            predicate = NSPredicate(format: "%K == %@", SinistroKeys.assignedToUserEmail, currentUser)
        }
        let query = CKQuery(recordType: RecordTypes.sinistro, predicate: predicate)
        let remoteRecords = try await publicDB.performQueryAsync(query)
        try await applyRemoteSinistri(remoteRecords, context: context)

        // 2) Push: sinistri locali assegnati all'utente corrente (username o email)
        let local = try await fetchLocalSinistriAssigned(username: currentUser, email: currentEmail, context: context)
        for sinistro in local {
            try await upsertSinistroToCloud(sinistro, actorEmail: currentUser)
        }

        // 3) Diario: sync entry (baseline)
        try await syncDiarioEntries(for: local, context: context, actorEmail: currentUser)
    }

    private func syncDiarioEntries(for sinistri: [Sinistro], context: NSManagedObjectContext, actorEmail: String) async throws {
        // Pull in batch: tutte le entry per i sinistri assegnati
        let riferimenti = sinistri.compactMap { $0.riferimento }.filter { !$0.isEmpty }
        guard !riferimenti.isEmpty else { return }

        let predicate = NSPredicate(format: "%K IN %@", DiarioKeys.sinistroRiferimento, riferimenti)
        let query = CKQuery(recordType: RecordTypes.diarioEntry, predicate: predicate)
        let remote = try await publicDB.performQueryAsync(query)
        try await applyRemoteDiarioEntries(remote, context: context)

        // Push: tutte le entry locali (baseline). Salvataggio idempotente su recordID = entryId
        for sinistro in sinistri {
            guard let rif = sinistro.riferimento, !rif.isEmpty else { continue }
            let entries = sinistro.diarioArray
            for entry in entries {
                try await upsertDiarioEntryToCloud(entry, riferimento: rif, actorEmail: actorEmail)
            }
        }
    }

    private func upsertDiarioEntryToCloud(_ entry: DiarioEntry, riferimento: String, actorEmail: String) async throws {
        let recordID = CKRecord.ID(recordName: entry.id.uuidString)
        let record = CKRecord(recordType: RecordTypes.diarioEntry, recordID: recordID)

        record[DiarioKeys.entryId] = entry.id.uuidString as CKRecordValue
        record[DiarioKeys.sinistroRiferimento] = riferimento as CKRecordValue
        record[DiarioKeys.timestamp] = entry.timestamp as CKRecordValue
        record[DiarioKeys.tipo] = entry.tipo.rawValue as CKRecordValue
        record[DiarioKeys.titolo] = (entry.titolo ?? "") as CKRecordValue
        record[DiarioKeys.riassunto] = (entry.riassunto ?? entry.testo) as CKRecordValue
        record[DiarioKeys.contenutoCompleto] = (entry.contenutoCompleto ?? entry.testo) as CKRecordValue
        record[DiarioKeys.createdBy] = actorEmail as CKRecordValue

        _ = try await publicDB.saveRecordAsync(record)
    }
    
    // MARK: - Public API per push singola entry (usata da non-owner che scrivono nel Diario)
    
    /// Effettua push di una singola DiarioEntry su CloudKit (best-effort).
    /// Da chiamare quando un utente diverso dall'owner aggiunge una entry al Diario.
    /// - Parameters:
    ///   - entry: La DiarioEntry da sincronizzare
    ///   - sinistroRiferimento: Riferimento del sinistro a cui appartiene
    ///   - actorEmail: Email di chi ha creato la entry
    func pushDiarioEntry(_ entry: DiarioEntry, sinistroRiferimento: String, actorEmail: String) async {
        guard settings.isEnabled else {
            print("[CloudKitSync] ⚠️ Sync disabilitato, skip push DiarioEntry")
            return
        }
        do {
            try await upsertDiarioEntryToCloud(entry, riferimento: sinistroRiferimento, actorEmail: actorEmail)
            print("[CloudKitSync] ✅ DiarioEntry \(entry.id) pushata per sinistro \(sinistroRiferimento)")
        } catch {
            print("[CloudKitSync] ❌ Errore push DiarioEntry: \(error.localizedDescription)")
        }
    }

    private func applyRemoteDiarioEntries(_ records: [CKRecord], context: NSManagedObjectContext) async throws {
        try await context.perform {
            for record in records {
                guard
                    let rif = record[DiarioKeys.sinistroRiferimento] as? String,
                    !rif.isEmpty,
                    let entryIdString = record[DiarioKeys.entryId] as? String,
                    let entryId = UUID(uuidString: entryIdString),
                    let ts = record[DiarioKeys.timestamp] as? Date,
                    let tipoRaw = record[DiarioKeys.tipo] as? String,
                    let tipo = DiarioEntry.TipoEntry(rawValue: tipoRaw)
                else { continue }

                let titolo = record[DiarioKeys.titolo] as? String
                let riassunto = (record[DiarioKeys.riassunto] as? String) ?? ""
                let contenuto = (record[DiarioKeys.contenutoCompleto] as? String) ?? riassunto
                let createdBy = record[DiarioKeys.createdBy] as? String

                let fetchSin = NSFetchRequest<Sinistro>(entityName: "Sinistro")
                fetchSin.fetchLimit = 1
                fetchSin.predicate = NSPredicate(format: "riferimento == %@", rif)
                guard let sinistro = try? context.fetch(fetchSin).first else { continue }

                var localEntries = sinistro.diarioArray
                if localEntries.contains(where: { $0.id == entryId }) {
                    continue
                }

                let newEntry = DiarioEntry(
                    id: entryId,
                    timestamp: ts,
                    tipo: tipo,
                    titolo: titolo,
                    riassunto: riassunto,
                    contenutoCompleto: contenuto,
                    emailMessageId: nil,
                    processedEmailDate: nil,
                    whatsAppChatId: nil,
                    whatsAppMessageIds: nil,
                    processedWhatsAppDate: nil,
                    generatedTaskId: nil,
                    createdByEmail: createdBy
                )

                localEntries.append(newEntry)
                localEntries.sort { $0.timestamp < $1.timestamp }
                sinistro.diarioArray = localEntries
            }

            if context.hasChanges {
                try context.save()
            }
        }
    }

    private func fetchLocalSinistriAssigned(username: String, email: String, context: NSManagedObjectContext) async throws -> [Sinistro] {
        try await context.perform {
            let req = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            if !email.isEmpty && email != username {
                req.predicate = NSPredicate(format: "assignedToUserEmail == %@ OR assignedToUserEmail == %@", username, email)
            } else {
                req.predicate = NSPredicate(format: "assignedToUserEmail == %@", username)
            }
            return try context.fetch(req)
        }
    }

    private func upsertSinistroToCloud(_ sinistro: Sinistro, actorEmail: String) async throws {
        guard let riferimento = sinistro.riferimento, !riferimento.isEmpty else { return }

        let recordID = CKRecord.ID(recordName: riferimento)
        let record: CKRecord = (try? await publicDB.fetchRecordIfExists(recordID)) ?? CKRecord(recordType: RecordTypes.sinistro, recordID: recordID)

        record[SinistroKeys.riferimento] = riferimento as CKRecordValue
        if let v = sinistro.stato, !v.isEmpty { record[SinistroKeys.stato] = v as CKRecordValue } else { record[SinistroKeys.stato] = nil }
        if let v = sinistro.numeroSinistroCompagnia, !v.isEmpty { record[SinistroKeys.numeroSinistroCompagnia] = v as CKRecordValue } else { record[SinistroKeys.numeroSinistroCompagnia] = nil }
        if let v = sinistro.nomeCompagnia, !v.isEmpty { record[SinistroKeys.nomeCompagnia] = v as CKRecordValue } else { record[SinistroKeys.nomeCompagnia] = nil }
        if let v = sinistro.nomeAssicurato, !v.isEmpty { record[SinistroKeys.nomeAssicurato] = v as CKRecordValue } else { record[SinistroKeys.nomeAssicurato] = nil }
        if let d = sinistro.dataAssegnazione {
            record[SinistroKeys.dataAssegnazione] = d as CKRecordValue
        } else {
            // Non serializzare placeholder (es. 1/1/0001) per date opzionali
            record[SinistroKeys.dataAssegnazione] = nil
        }
        if let dataChiusura = sinistro.dataChiusura {
            record[SinistroKeys.dataChiusura] = dataChiusura as CKRecordValue
        }

        if let richiesta = sinistro.richiesta?.doubleValue {
            record[SinistroKeys.richiesta] = richiesta as CKRecordValue
        }
        if let liquidato = sinistro.liquidato?.doubleValue {
            record[SinistroKeys.liquidato] = liquidato as CKRecordValue
        }
        if let danno = sinistro.dannoAccertato?.doubleValue {
            record[SinistroKeys.dannoAccertato] = danno as CKRecordValue
        }

        if let v = sinistro.assignedToUserEmail, !v.isEmpty { record[SinistroKeys.assignedToUserEmail] = v as CKRecordValue } else { record[SinistroKeys.assignedToUserEmail] = nil }
        if let v = sinistro.assignedToUserName, !v.isEmpty { record[SinistroKeys.assignedToUserName] = v as CKRecordValue } else { record[SinistroKeys.assignedToUserName] = nil }
        if let v = sinistro.substate, !v.isEmpty { record[SinistroKeys.substate] = v as CKRecordValue } else { record[SinistroKeys.substate] = nil }

        record[SinistroKeys.lastModifiedBy] = actorEmail as CKRecordValue
        record[SinistroKeys.lastModifiedAt] = Date() as CKRecordValue
        let currentVersion = record[SinistroKeys.version] as? Int ?? 0
        record[SinistroKeys.version] = (currentVersion + 1) as CKRecordValue

        let saved: CKRecord
        do {
            saved = try await publicDB.saveRecordAsync(record)
        } catch {
            // Conflitto: risoluzione last-write-wins (locale vs server)
            if let ckError = error as? CKError,
               ckError.code == .serverRecordChanged,
               let serverRecord = ckError.serverRecord {
                let serverModified = (serverRecord[SinistroKeys.lastModifiedAt] as? Date) ?? serverRecord.modificationDate ?? .distantPast
                let localModified = sinistro.cloudKitLastModified ?? .distantPast

                if localModified >= serverModified {
                    // Locale vince: riprova salvando sul record server
                    serverRecord[SinistroKeys.stato] = record[SinistroKeys.stato]
                    serverRecord[SinistroKeys.numeroSinistroCompagnia] = record[SinistroKeys.numeroSinistroCompagnia]
                    serverRecord[SinistroKeys.nomeCompagnia] = record[SinistroKeys.nomeCompagnia]
                    serverRecord[SinistroKeys.nomeAssicurato] = record[SinistroKeys.nomeAssicurato]
                    serverRecord[SinistroKeys.dataAssegnazione] = record[SinistroKeys.dataAssegnazione]
                    serverRecord[SinistroKeys.dataChiusura] = record[SinistroKeys.dataChiusura]
                    serverRecord[SinistroKeys.richiesta] = record[SinistroKeys.richiesta]
                    serverRecord[SinistroKeys.liquidato] = record[SinistroKeys.liquidato]
                    serverRecord[SinistroKeys.dannoAccertato] = record[SinistroKeys.dannoAccertato]
                    serverRecord[SinistroKeys.assignedToUserEmail] = record[SinistroKeys.assignedToUserEmail]
                    serverRecord[SinistroKeys.assignedToUserName] = record[SinistroKeys.assignedToUserName]
                    serverRecord[SinistroKeys.substate] = record[SinistroKeys.substate]
                    serverRecord[SinistroKeys.lastModifiedBy] = actorEmail as CKRecordValue
                    serverRecord[SinistroKeys.lastModifiedAt] = Date() as CKRecordValue
                    let serverVersion = serverRecord[SinistroKeys.version] as? Int ?? 0
                    serverRecord[SinistroKeys.version] = (serverVersion + 1) as CKRecordValue

                    saved = try await publicDB.saveRecordAsync(serverRecord)
                } else {
                    // Server vince: applica a locale
                    let ctx = sinistro.managedObjectContext ?? PersistenceController.shared.container.viewContext
                    try await applyRemoteSinistri([serverRecord], context: ctx)
                    return
                }
            } else {
                throw error
            }
        }

        // Persist metadata locale
        let modifiedAt = saved[SinistroKeys.lastModifiedAt] as? Date
        let recordName = saved.recordID.recordName
        let ctx = sinistro.managedObjectContext ?? PersistenceController.shared.container.viewContext
        await ctx.perform {
            sinistro.cloudKitRecordID = recordName
            sinistro.cloudKitLastModified = modifiedAt
            try? ctx.save()
        }
    }

    private func applyRemoteSinistri(_ records: [CKRecord], context: NSManagedObjectContext) async throws {
        try await context.perform {
            for record in records {
                let riferimento = (record[SinistroKeys.riferimento] as? String) ?? record.recordID.recordName
                guard !riferimento.isEmpty else { continue }

                let fetch = NSFetchRequest<Sinistro>(entityName: "Sinistro")
                fetch.fetchLimit = 1
                fetch.predicate = NSPredicate(format: "riferimento == %@", riferimento)
                let local = (try? context.fetch(fetch).first)

                let remoteModified = (record[SinistroKeys.lastModifiedAt] as? Date) ?? record.modificationDate ?? Date.distantPast

                let target: Sinistro
                if let local {
                    // Se locale è più recente, non sovrascrivere
                    if let localModified = local.cloudKitLastModified, localModified > remoteModified {
                        continue
                    }
                    target = local
                } else {
                    target = Sinistro(context: context)
                    target.riferimento = riferimento
                }

                target.stato = record[SinistroKeys.stato] as? String
                target.numeroSinistroCompagnia = record[SinistroKeys.numeroSinistroCompagnia] as? String
                target.nomeCompagnia = record[SinistroKeys.nomeCompagnia] as? String
                target.nomeAssicurato = record[SinistroKeys.nomeAssicurato] as? String
                let remoteDataAssegnazione = record[SinistroKeys.dataAssegnazione] as? Date
                if let remoteDataAssegnazione, remoteDataAssegnazione == Date.distantPast {
                    // Ripulisci record legacy che usavano .distantPast come sentinel
                    target.dataAssegnazione = nil
                } else {
                    target.dataAssegnazione = remoteDataAssegnazione
                }
                target.dataChiusura = record[SinistroKeys.dataChiusura] as? Date

                if let richiesta = record[SinistroKeys.richiesta] as? Double {
                    target.richiesta = NSDecimalNumber(value: richiesta)
                }
                if let liquidato = record[SinistroKeys.liquidato] as? Double {
                    target.liquidato = NSDecimalNumber(value: liquidato)
                }
                if let danno = record[SinistroKeys.dannoAccertato] as? Double {
                    target.dannoAccertato = NSDecimalNumber(value: danno)
                }

                target.assignedToUserEmail = (record[SinistroKeys.assignedToUserEmail] as? String)
                target.assignedToUserName = (record[SinistroKeys.assignedToUserName] as? String)
                target.substate = (record[SinistroKeys.substate] as? String)

                target.cloudKitRecordID = record.recordID.recordName
                target.cloudKitLastModified = remoteModified
            }

            if context.hasChanges {
                try context.save()
            }
        }
    }

    private func refreshAccountStatus() async {
        do {
            let accountStatus = try await container.accountStatusAsync()
            switch accountStatus {
            case .available:
                status = .ready
            case .noAccount:
                status = .unavailable("Nessun account iCloud configurato")
            case .restricted:
                status = .unavailable("iCloud ristretto su questo dispositivo")
            case .couldNotDetermine:
                status = .unavailable("Impossibile determinare lo stato iCloud")
            @unknown default:
                status = .unavailable("Stato iCloud non supportato")
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - Timer

    private func restartTimerIfNeeded() {
        stopTimer()
        guard settings.isEnabled else { return }
        guard case .ready = status else { return }

        let interval = max(5.0, settings.syncFrequencySeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                await CPUThrottler.shared.runWithThrottle { await self.syncNow(reason: "timer") }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

