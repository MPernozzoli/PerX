import Foundation
import CloudKit
import PerXCore

// ============================================================================
// MARK: - CloudKitSyncManager (Hub version)
// Gestisce la sincronizzazione CloudKit dall'Hub centrale
// ============================================================================

public actor CloudKitSyncManager {
    public static let shared = CloudKitSyncManager()
    
    // Container CloudKit
    private let container: CKContainer
    private let publicDB: CKDatabase
    private let privateDB: CKDatabase
    
    // Stato
    private var isInitialized = false
    private var lastSyncDate: Date?
    
    // Configurazione
    private let containerIdentifier = "iCloud.it.pernozzoli.PerX"
    
    // Record types
    private enum RecordTypes {
        static let sinistro = "Sinistro"
        static let diarioEntry = "DiarioEntry"
        static let processedEmail = "ProcessedEmail"
        static let task = "Task"
        static let emailEvent = "EmailEvent"
    }
    
    private init() {
        container = CKContainer(identifier: containerIdentifier)
        publicDB = container.publicCloudDatabase
        privateDB = container.privateCloudDatabase
        
        print("[CloudKitSyncManager] ✅ Inizializzato con container: \(containerIdentifier)")
    }
    
    // MARK: - Initialization
    
    public func initialize() async throws {
        guard !isInitialized else { return }
        
        // Verifica stato account
        let status = try await checkAccountStatus()
        guard status == .available else {
            throw CloudKitError.accountNotAvailable(status.description)
        }
        
        isInitialized = true
        print("[CloudKitSyncManager] ✅ Account iCloud disponibile")
    }
    
    private func checkAccountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: status)
            }
        }
    }
    
    // MARK: - Sinistri Sync
    
    /// Salva/aggiorna un sinistro su CloudKit
    public func saveSinistro(_ dto: SinistroDTO, modifiedBy userEmail: String) async throws {
        let recordID = CKRecord.ID(recordName: dto.riferimento)
        
        // Fetch o crea record
        let record: CKRecord
        do {
            record = try await fetchRecord(recordID, db: publicDB)
        } catch {
            record = CKRecord(recordType: RecordTypes.sinistro, recordID: recordID)
        }
        
        // Popola campi
        record["riferimento"] = dto.riferimento as CKRecordValue
        record["stato"] = dto.stato as CKRecordValue
        record["statoId"] = dto.statoId as CKRecordValue
        if let assicurato = dto.assicurato {
            record["assicurato"] = assicurato as CKRecordValue
        }
        if let polizza = dto.polizza {
            record["polizza"] = polizza as CKRecordValue
        }
        if let agenzia = dto.agenzia {
            record["agenzia"] = agenzia as CKRecordValue
        }
        if let da = dto.dataAssegnazione {
            record["dataAssegnazione"] = da as CKRecordValue
        }
        if let dc = dto.dataChiusura {
            record["dataChiusura"] = dc as CKRecordValue
        }
        if let ownerEmail = dto.ownerEmail {
            record["ownerEmail"] = ownerEmail as CKRecordValue
        }
        
        record["lastModifiedBy"] = userEmail as CKRecordValue
        record["lastModifiedAt"] = Date() as CKRecordValue
        
        // Incrementa versione
        let currentVersion = record["version"] as? Int ?? 0
        record["version"] = (currentVersion + 1) as CKRecordValue
        
        _ = try await saveRecord(record, db: publicDB)
        print("[CloudKitSync] ✅ Sinistro salvato: \(dto.riferimento)")
    }
    
    /// Recupera sinistri per un utente (user = username, fallbackEmail per retrocompat)
    public func fetchSinistri(forUser user: String, fallbackEmail: String? = nil) async throws -> [SinistroDTO] {
        let predicate: NSPredicate
        if let email = fallbackEmail, !email.isEmpty, email.lowercased() != user.lowercased() {
            predicate = NSPredicate(format: "assignedToUserEmail == %@ OR assignedToUserEmail == %@", user.lowercased(), email.lowercased())
        } else {
            predicate = NSPredicate(format: "assignedToUserEmail == %@", user.lowercased())
        }
        let query = CKQuery(recordType: RecordTypes.sinistro, predicate: predicate)
        
        let records = try await performQuery(query, db: publicDB)
        
        return records.compactMap { record -> SinistroDTO? in
            guard let riferimento = record["riferimento"] as? String else { return nil }
            
            return SinistroDTO(
                id: record.recordID.recordName,
                riferimento: riferimento,
                stato: record["stato"] as? String ?? "Da scaricare",
                statoId: record["statoId"] as? String ?? "SV001",
                assicurato: record["assicurato"] as? String,
                polizza: record["polizza"] as? String,
                agenzia: record["agenzia"] as? String,
                dataAssegnazione: record["dataAssegnazione"] as? Date,
                dataChiusura: record["dataChiusura"] as? Date,
                ownerEmail: record["ownerEmail"] as? String,
                lastModified: (record["lastModifiedAt"] as? Date) ?? Date()
            )
        }
    }
    
    /// Recupera un sinistro per riferimento (dettaglio)
    public func fetchSinistro(riferimento: String) async throws -> SinistroDTO? {
        let predicate = NSPredicate(format: "riferimento == %@", riferimento)
        let query = CKQuery(recordType: RecordTypes.sinistro, predicate: predicate)
        let records = try await performQuery(query, db: publicDB)
        guard let record = records.first,
              let rif = record["riferimento"] as? String else { return nil }
        return SinistroDTO(
            id: record.recordID.recordName,
            riferimento: rif,
            stato: record["stato"] as? String ?? "Da scaricare",
            statoId: record["statoId"] as? String ?? "SV001",
            assicurato: record["assicurato"] as? String,
            polizza: record["polizza"] as? String,
            agenzia: record["agenzia"] as? String,
            dataAssegnazione: record["dataAssegnazione"] as? Date,
            dataEvento: nil,
            dataChiusura: record["dataChiusura"] as? Date,
            ownerEmail: record["ownerEmail"] as? String,
            ownerName: nil,
            complessita: nil,
            definizione: nil,
            importoLiquidato: nil,
            lastModified: (record["lastModifiedAt"] as? Date) ?? Date()
        )
    }
    
    /// Sincronizza un sinistro specifico (usato da ClaimEngine)
    public func syncSinistro(riferimento: String) async throws {
        // Per ora, questo metodo è un placeholder
        // La sincronizzazione completa richiede il fetch del sinistro dal DB locale
        // e poi il salvataggio su CloudKit
        print("[CloudKitSync] ⚠️ syncSinistro placeholder chiamato per: \(riferimento)")
        
        // TODO: Implementare fetch da DB locale e salvataggio su CloudKit
        // let dto = try await ClaimEngine.shared.getSinistroDTO(riferimento: riferimento)
        // try await saveSinistro(dto, modifiedBy: "system@perx.it")
    }
    
    // MARK: - Email Sync
    
    /// Salva email processata su CloudKit
    public func saveProcessedEmail(
        messageId: String,
        userEmail: String,
        sinistroRef: String?,
        category: String
    ) async throws {
        let recordID = CKRecord.ID(recordName: messageId)
        let record = CKRecord(recordType: RecordTypes.processedEmail, recordID: recordID)
        
        record["messageId"] = messageId as CKRecordValue
        record["userEmail"] = userEmail.lowercased() as CKRecordValue
        record["processedAt"] = Date() as CKRecordValue
        record["category"] = category as CKRecordValue
        
        if let ref = sinistroRef {
            record["sinistroRef"] = ref as CKRecordValue
        }
        
        _ = try await saveRecord(record, db: publicDB)
        print("[CloudKitSync] ✅ Email processata salvata: \(messageId)")
    }
    
    /// Salva evento email su CloudKit
    public func saveEmailEvent(_ event: HubEmailEvent) async throws {
        let recordID = CKRecord.ID(recordName: event.eventId.uuidString)
        let record = CKRecord(recordType: RecordTypes.emailEvent, recordID: recordID)
        
        record["eventId"] = event.eventId.uuidString as CKRecordValue
        record["emailId"] = event.emailId as CKRecordValue
        record["eventType"] = event.eventType.rawValue as CKRecordValue
        record["timestamp"] = event.timestamp as CKRecordValue
        record["direction"] = event.direction.rawValue as CKRecordValue
        
        if let sinistroId = event.sinistroId {
            record["sinistroId"] = sinistroId as CKRecordValue
        }
        
        _ = try await saveRecord(record, db: publicDB)
        print("[CloudKitSync] ✅ EmailEvent salvato: \(event.eventId)")
    }
    
    // MARK: - Task Sync
    
    /// Salva task su CloudKit
    public func saveTask(_ task: HubTask) async throws {
        let recordID = CKRecord.ID(recordName: task.id)
        let record = CKRecord(recordType: RecordTypes.task, recordID: recordID)
        
        record["taskId"] = task.id as CKRecordValue
        record["title"] = task.title as CKRecordValue
        record["type"] = task.type.rawValue as CKRecordValue
        record["priority"] = task.priority.rawValue as CKRecordValue
        record["status"] = task.status.rawValue as CKRecordValue
        record["createdAt"] = task.createdAt as CKRecordValue
        
        if let desc = task.description {
            record["description"] = desc as CKRecordValue
        }
        if let ref = task.sinistroRef {
            record["sinistroRef"] = ref as CKRecordValue
        }
        if let due = task.dueDate {
            record["dueDate"] = due as CKRecordValue
        }
        if let assignedTo = task.assignedTo {
            record["assignedTo"] = assignedTo as CKRecordValue
        }
        if let createdBy = task.createdBy {
            record["createdBy"] = createdBy as CKRecordValue
        }
        if let completedAt = task.completedAt {
            record["completedAt"] = completedAt as CKRecordValue
        }
        
        _ = try await saveRecord(record, db: publicDB)
        print("[CloudKitSync] ✅ Task salvato: \(task.id)")
    }
    
    /// Recupera task per un utente (user = username, fallbackEmail per retrocompat)
    public func fetchTasks(forUser user: String, fallbackEmail: String? = nil) async throws -> [HubTask] {
        let predicate: NSPredicate
        if let email = fallbackEmail, !email.isEmpty, email.lowercased() != user.lowercased() {
            predicate = NSPredicate(format: "assignedTo == %@ OR assignedTo == %@", user.lowercased(), email.lowercased())
        } else {
            predicate = NSPredicate(format: "assignedTo == %@", user.lowercased())
        }
        let query = CKQuery(recordType: RecordTypes.task, predicate: predicate)
        
        let records = try await performQuery(query, db: publicDB)
        
        return records.compactMap { record -> HubTask? in
            guard let taskId = record["taskId"] as? String,
                  let title = record["title"] as? String,
                  let typeRaw = record["type"] as? String,
                  let type = TaskType(rawValue: typeRaw),
                  let priorityRaw = record["priority"] as? String,
                  let priority = TaskPriority(rawValue: priorityRaw),
                  let statusRaw = record["status"] as? String,
                  let status = TaskStatus(rawValue: statusRaw),
                  let createdAt = record["createdAt"] as? Date
            else { return nil }
            
            return HubTask(
                id: taskId,
                title: title,
                description: record["description"] as? String,
                type: type,
                priority: priority,
                sinistroRef: record["sinistroRef"] as? String,
                dueDate: record["dueDate"] as? Date,
                status: status,
                assignedTo: record["assignedTo"] as? String,
                createdBy: record["createdBy"] as? String,
                createdAt: createdAt,
                completedAt: record["completedAt"] as? Date,
                syncedToCK: true
            )
        }
    }
    
    // MARK: - Diario Sync
    
    /// Salva entry diario su CloudKit
    public func saveDiarioEntry(
        entryId: UUID,
        sinistroRef: String,
        timestamp: Date,
        tipo: String,
        titolo: String?,
        riassunto: String,
        contenutoCompleto: String?,
        createdBy: String
    ) async throws {
        let recordID = CKRecord.ID(recordName: entryId.uuidString)
        let record = CKRecord(recordType: RecordTypes.diarioEntry, recordID: recordID)
        
        record["entryId"] = entryId.uuidString as CKRecordValue
        record["sinistroRiferimento"] = sinistroRef as CKRecordValue
        record["timestamp"] = timestamp as CKRecordValue
        record["tipo"] = tipo as CKRecordValue
        record["riassunto"] = riassunto as CKRecordValue
        record["createdBy"] = createdBy as CKRecordValue
        
        if let t = titolo {
            record["titolo"] = t as CKRecordValue
        }
        if let c = contenutoCompleto {
            record["contenutoCompleto"] = c as CKRecordValue
        }
        
        _ = try await saveRecord(record, db: publicDB)
        print("[CloudKitSync] ✅ DiarioEntry salvata: \(entryId)")
    }
    
    // MARK: - CloudKit Primitives
    
    private func saveRecord(_ record: CKRecord, db: CKDatabase) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            db.save(record) { saved, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: saved ?? record)
            }
        }
    }
    
    private func fetchRecord(_ recordID: CKRecord.ID, db: CKDatabase) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            db.fetch(withRecordID: recordID) { record, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let record = record else {
                    continuation.resume(throwing: CloudKitError.recordNotFound)
                    return
                }
                continuation.resume(returning: record)
            }
        }
    }
    
    private func performQuery(_ query: CKQuery, db: CKDatabase) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            db.perform(query, inZoneWith: nil) { records, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: records ?? [])
            }
        }
    }
    
    // MARK: - Batch Operations
    
    /// Esegue sync completo per un utente
    public func fullSync(forUser user: String, fallbackEmail: String? = nil) async throws {
        print("[CloudKitSync] 🔄 Full sync per utente: \(user)")
        
        let sinistri = try await fetchSinistri(forUser: user, fallbackEmail: fallbackEmail)
        print("[CloudKitSync] 📥 Scaricati \(sinistri.count) sinistri")
        
        let tasks = try await fetchTasks(forUser: user, fallbackEmail: fallbackEmail)
        print("[CloudKitSync] 📥 Scaricati \(tasks.count) task")
        
        lastSyncDate = Date()
        print("[CloudKitSync] ✅ Full sync completato")
    }
}

// MARK: - Errors

public enum CloudKitError: Error, LocalizedError {
    case accountNotAvailable(String)
    case recordNotFound
    case saveError(String)
    case queryError(String)
    
    public var errorDescription: String? {
        switch self {
        case .accountNotAvailable(let status):
            return "Account CloudKit non disponibile: \(status)"
        case .recordNotFound:
            return "Record non trovato"
        case .saveError(let msg):
            return "Errore salvataggio: \(msg)"
        case .queryError(let msg):
            return "Errore query: \(msg)"
        }
    }
}

// MARK: - Extensions

extension CKAccountStatus {
    var description: String {
        switch self {
        case .available: return "available"
        case .noAccount: return "noAccount"
        case .restricted: return "restricted"
        case .couldNotDetermine: return "couldNotDetermine"
        case .temporarilyUnavailable: return "temporarilyUnavailable"
        @unknown default: return "unknown"
        }
    }
}
