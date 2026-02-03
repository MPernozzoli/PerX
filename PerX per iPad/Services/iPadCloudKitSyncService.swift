//
//  iPadCloudKitSyncService.swift
//  PerX per iPad
//
//  Servizio di sincronizzazione per iPad.
//  Usa Hub come fonte primaria, CloudKit come fallback.
//

import Foundation
import CloudKit
import CoreData
import Combine

@MainActor
final class iPadCloudKitSyncService: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var sinistri: [SinistroMinimal] = []
    @Published private(set) var lastError: String?
    @Published private(set) var dataSource: DataSource = .none
    
    enum DataSource: String {
        case none = "Non connesso"
        case hub = "Hub"
        case cloudKit = "CloudKit"
    }
    
    // MARK: - Dependencies
    
    private let hubClient = HubAPIClient.shared
    private let container: CKContainer
    private let publicDB: CKDatabase
    private let userEmail: String
    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Record Types (CloudKit fallback)
    
    private enum RecordType {
        static let sinistroMinimal = "SinistroMinimal"
        static let sinistroFull = "SinistroFull"
        static let diarioEntry = "DiarioEntry"
        static let processedEmail = "ProcessedEmail"
        static let whatsAppMessage = "WhatsAppMessage"
    }
    
    // MARK: - Init
    
    init(userEmail: String, container: CKContainer = CKContainer(identifier: "iCloud.it.pernozzoli.PerX")) {
        self.userEmail = userEmail.lowercased()
        self.container = container
        self.publicDB = container.publicCloudDatabase
    }
    
    // MARK: - Lifecycle
    
    func start() async {
        print("[iPadSync] ▶️ Avvio sync per: \(userEmail)")
        
        // Prima sync immediata
        await syncNow()
        
        // Polling ogni 30 secondi
        startPolling()
    }
    
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        print("[iPadSync] ⏹️ Sync stoppato")
    }
    
    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncNow()
            }
        }
    }
    
    // MARK: - Sync
    
    func syncNow() async {
        guard !isSyncing else { return }
        
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncAt = Date()
        }
        
        // Prova prima Hub, poi CloudKit come fallback
        do {
            try await fetchSinistriFromHub()
            dataSource = .hub
            print("[iPadSync] ✅ Sync da Hub completato: \(sinistri.count) sinistri")
        } catch {
            print("[iPadSync] ⚠️ Hub non disponibile, provo CloudKit: \(error)")
            
            do {
                try await fetchSinistriFromCloudKit()
                dataSource = .cloudKit
                print("[iPadSync] ✅ Sync da CloudKit completato: \(sinistri.count) sinistri")
            } catch {
                lastError = error.localizedDescription
                dataSource = .none
                print("[iPadSync] ❌ Errore sync: \(error)")
            }
        }
    }
    
    // MARK: - Hub Fetch
    
    private func fetchSinistriFromHub() async throws {
        let dtos = try await hubClient.getSinistri()
        
        sinistri = dtos.map { dto in
            SinistroMinimal(
                id: dto.riferimento,
                riferimento: dto.riferimento,
                stato: dto.stato,
                nomeAssicurato: dto.nomeAssicurato,
                nomeCompagnia: dto.nomeCompagnia,
                dataAssegnazione: dto.dataAssegnazione,
                dataChiusura: dto.dataChiusura,
                stimaDanno: dto.stimaDanno,
                substate: dto.statoDetail,
                fulminazione: false // TODO: aggiungere campo in SinistroDTO
            )
        }
    }
    
    // MARK: - CloudKit Fetch (fallback)
    
    private func fetchSinistriFromCloudKit() async throws {
        let predicate = NSPredicate(format: "assignedToUserEmail == %@", userEmail)
        let query = CKQuery(recordType: RecordType.sinistroMinimal, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "dataAssegnazione", ascending: false)]
        
        let records = try await performQuery(query)
        sinistri = records.compactMap { SinistroMinimal(from: $0) }
    }
    
    // MARK: - Sinistro Full (on-demand)
    
    func fetchSinistroFull(riferimento: String) async throws -> SinistroFull? {
        // Prova Hub prima
        do {
            let dto = try await hubClient.getSinistro(riferimento: riferimento)
            return SinistroFull(from: dto)
        } catch {
            // Fallback CloudKit
            let predicate = NSPredicate(format: "riferimento == %@", riferimento)
            let query = CKQuery(recordType: RecordType.sinistroFull, predicate: predicate)
            
            let records = try await performQuery(query)
            guard let record = records.first else { return nil }
            
            return SinistroFull(from: record)
        }
    }
    
    // MARK: - Diario
    
    func fetchDiarioEntries(riferimento: String) async throws -> [DiarioEntryDTO] {
        // Prova Hub prima
        do {
            let hubEntries = try await hubClient.getDiarioEntries(riferimento: riferimento)
            return hubEntries.map { DiarioEntryDTO(from: $0) }
        } catch {
            // Fallback CloudKit
            let predicate = NSPredicate(format: "sinistroRiferimento == %@", riferimento)
            let query = CKQuery(recordType: RecordType.diarioEntry, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            
            let records = try await performQuery(query)
            return records.compactMap { DiarioEntryDTO(from: $0) }
        }
    }
    
    /// Aggiunge nota al diario tramite Hub
    func addDiarioEntry(riferimento: String, testo: String, tipo: String = "nota") async throws -> DiarioEntryDTO {
        let request = CreateDiarioEntryRequest(tipo: tipo, titolo: nil, testo: testo)
        let hubEntry = try await hubClient.addDiarioEntry(riferimento: riferimento, entry: request)
        return DiarioEntryDTO(from: hubEntry)
    }
    
    // MARK: - Email processate
    
    func fetchProcessedEmails(riferimento: String) async throws -> [ProcessedEmailDTO] {
        // Per ora solo CloudKit - Hub non ha endpoint email processate
        let predicate = NSPredicate(format: "sinistroRiferimento == %@", riferimento)
        let query = CKQuery(recordType: RecordType.processedEmail, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "processedAt", ascending: false)]
        
        let records = try await performQuery(query)
        return records.compactMap { ProcessedEmailDTO(from: $0) }
    }
    
    // MARK: - WhatsApp Messages
    
    func fetchWhatsAppMessages(riferimento: String) async throws -> [WhatsAppMessageDTO] {
        // Per ora solo CloudKit - Hub non ha endpoint WA
        let predicate = NSPredicate(format: "sinistroRiferimento == %@", riferimento)
        let query = CKQuery(recordType: RecordType.whatsAppMessage, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        let records = try await performQuery(query)
        return records.compactMap { WhatsAppMessageDTO(from: $0) }
    }
    
    /// Chiamato quando arriva una notifica push
    func handleRemoteNotification() async {
        await syncNow()
    }
    
    // MARK: - CloudKit Helpers
    
    private func performQuery(_ query: CKQuery) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            publicDB.perform(query, inZoneWith: nil) { records, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: records ?? [])
                }
            }
        }
    }
}

// MARK: - DTOs

struct SinistroMinimal: Identifiable, Codable, Hashable {
    let id: String
    let riferimento: String
    let stato: String
    let nomeAssicurato: String
    let nomeCompagnia: String
    let dataAssegnazione: Date?
    let dataChiusura: Date?
    let stimaDanno: Double?
    let substate: String?
    let fulminazione: Bool
    
    var isOpen: Bool {
        dataChiusura == nil
    }
    
    // Init diretto
    init(id: String, riferimento: String, stato: String, nomeAssicurato: String, nomeCompagnia: String, dataAssegnazione: Date?, dataChiusura: Date?, stimaDanno: Double?, substate: String?, fulminazione: Bool) {
        self.id = id
        self.riferimento = riferimento
        self.stato = stato
        self.nomeAssicurato = nomeAssicurato
        self.nomeCompagnia = nomeCompagnia
        self.dataAssegnazione = dataAssegnazione
        self.dataChiusura = dataChiusura
        self.stimaDanno = stimaDanno
        self.substate = substate
        self.fulminazione = fulminazione
    }
    
    // Init da CloudKit
    init?(from record: CKRecord) {
        guard let rif = record["riferimento"] as? String else { return nil }
        
        self.id = rif
        self.riferimento = rif
        self.stato = record["stato"] as? String ?? ""
        self.nomeAssicurato = record["nomeAssicurato"] as? String ?? ""
        self.nomeCompagnia = record["nomeCompagnia"] as? String ?? ""
        self.dataAssegnazione = record["dataAssegnazione"] as? Date
        self.dataChiusura = record["dataChiusura"] as? Date
        self.stimaDanno = record["stimaDanno"] as? Double
        self.substate = record["substate"] as? String
        self.fulminazione = record["fulminazione"] as? Bool ?? false
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(riferimento)
    }
    
    static func == (lhs: SinistroMinimal, rhs: SinistroMinimal) -> Bool {
        lhs.riferimento == rhs.riferimento
    }
}

struct SinistroFull: Identifiable, Codable {
    let id: String
    let riferimento: String
    
    // Anagrafica
    let nomeContraente: String?
    let telefonoContraente: String?
    let emailContraente: String?
    let nomeAssicurato: String?
    let telefonoAssicurato: String?
    let emailAssicurato: String?
    let nomeDanneggiato: String?
    let telefonoDanneggiato: String?
    let emailDanneggiato: String?
    
    // Polizza
    let numeroPolizza: String?
    let tipoPolizza: String?
    let numeroSinistroCompagnia: String?
    let agenzia: String?
    let emailAgenzia: String?
    
    // Importi
    let richiesta: Double?
    let liquidato: Double?
    let dannoAccertato: Double?
    
    // Init da Hub SinistroDTO
    init(from dto: SinistroDTO) {
        self.id = dto.riferimento
        self.riferimento = dto.riferimento
        self.nomeContraente = dto.nomeContraente
        self.telefonoContraente = dto.telefonoContraente
        self.emailContraente = dto.emailContraente
        self.nomeAssicurato = dto.nomeAssicurato
        self.telefonoAssicurato = dto.telefonoAssicurato
        self.emailAssicurato = dto.emailAssicurato
        self.nomeDanneggiato = nil // Non in DTO
        self.telefonoDanneggiato = nil
        self.emailDanneggiato = nil
        self.numeroPolizza = dto.numeroPolizza
        self.tipoPolizza = dto.tipoPolizza
        self.numeroSinistroCompagnia = nil // Non in DTO
        self.agenzia = nil // Non in DTO
        self.emailAgenzia = nil
        self.richiesta = dto.stimaDanno
        self.liquidato = dto.liquidato
        self.dannoAccertato = nil // Non in DTO
    }
    
    // Init da CloudKit
    init?(from record: CKRecord) {
        guard let rif = record["riferimento"] as? String else { return nil }
        
        self.id = rif
        self.riferimento = rif
        self.nomeContraente = record["nomeContraente"] as? String
        self.telefonoContraente = record["telefonoContraente"] as? String
        self.emailContraente = record["emailContraente"] as? String
        self.nomeAssicurato = record["nomeAssicurato"] as? String
        self.telefonoAssicurato = record["telefonoAssicurato"] as? String
        self.emailAssicurato = record["emailAssicurato"] as? String
        self.nomeDanneggiato = record["nomeDanneggiato"] as? String
        self.telefonoDanneggiato = record["telefonoDanneggiato"] as? String
        self.emailDanneggiato = record["emailDanneggiato"] as? String
        self.numeroPolizza = record["numeroPolizza"] as? String
        self.tipoPolizza = record["tipoPolizza"] as? String
        self.numeroSinistroCompagnia = record["numeroSinistroCompagnia"] as? String
        self.agenzia = record["agenzia"] as? String
        self.emailAgenzia = record["emailAgenzia"] as? String
        self.richiesta = record["richiesta"] as? Double
        self.liquidato = record["liquidato"] as? Double
        self.dannoAccertato = record["dannoAccertato"] as? Double
    }
}

struct DiarioEntryDTO: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let tipo: String
    let titolo: String?
    let riassunto: String
    let contenutoCompleto: String?
    let createdBy: String?
    
    // Init da Hub DTO
    init(from hubDTO: DiarioEntryHubDTO) {
        self.id = hubDTO.id
        self.timestamp = hubDTO.timestamp
        self.tipo = hubDTO.tipo
        self.titolo = hubDTO.titolo
        self.riassunto = hubDTO.riassunto
        self.contenutoCompleto = hubDTO.contenutoCompleto
        self.createdBy = hubDTO.createdBy
    }
    
    // Init da CloudKit
    init?(from record: CKRecord) {
        guard let entryId = record["entryId"] as? String else { return nil }
        
        self.id = entryId
        self.timestamp = record["timestamp"] as? Date ?? Date()
        self.tipo = record["tipo"] as? String ?? "nota"
        self.titolo = record["titolo"] as? String
        self.riassunto = record["riassunto"] as? String ?? ""
        self.contenutoCompleto = record["contenutoCompleto"] as? String
        self.createdBy = record["createdBy"] as? String
    }
}

struct ProcessedEmailDTO: Identifiable, Codable, Hashable {
    let id: String
    let messageId: String
    let subject: String
    let from: String
    let date: Date
    let category: String?
    let sinistroRiferimento: String?
    
    init?(from record: CKRecord) {
        guard let msgId = record["messageId"] as? String else { return nil }
        
        self.id = msgId
        self.messageId = msgId
        self.subject = record["subject"] as? String ?? ""
        self.from = record["from"] as? String ?? ""
        self.date = record["date"] as? Date ?? Date()
        self.category = record["category"] as? String
        self.sinistroRiferimento = record["sinistroRiferimento"] as? String
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(messageId)
    }
    
    static func == (lhs: ProcessedEmailDTO, rhs: ProcessedEmailDTO) -> Bool {
        lhs.messageId == rhs.messageId
    }
}

struct WhatsAppMessageDTO: Identifiable, Codable {
    let id: String
    let chatId: String
    let from: String
    let body: String
    let timestamp: Date
    let direction: String
    let mediaType: String?
    
    init?(from record: CKRecord) {
        guard let msgId = record["messageId"] as? String else { return nil }
        
        self.id = msgId
        self.chatId = record["chatId"] as? String ?? ""
        self.from = record["from"] as? String ?? ""
        self.body = record["body"] as? String ?? ""
        self.timestamp = record["timestamp"] as? Date ?? Date()
        self.direction = record["direction"] as? String ?? "inbound"
        self.mediaType = record["mediaType"] as? String
    }
}
