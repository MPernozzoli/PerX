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
import SwiftUI

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
        case cloudAPI = "Cloud API"
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
        
        // Prova prima Cloud API, poi Hub, poi CloudKit come fallback finale
        do {
            if hubClient.isCloudConfigured {
                try await fetchSinistriFromCloudAPI()
                dataSource = .cloudAPI
                print("[iPadSync] ✅ Sync da Cloud API completato: \(sinistri.count) sinistri")
                return
            }
        } catch {
            print("[iPadSync] ⚠️ Cloud API non disponibile, provo Hub: \(error)")
        }

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

    private func fetchSinistriFromCloudAPI() async throws {
        let dtos = try await hubClient.getSinistriFromCloud()

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
                fulminazione: dto.garanzia == "Fenomeno Elettrico"
            )
        }
    }

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
                fulminazione: dto.garanzia == "Fenomeno Elettrico"
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
        if hubClient.isCloudConfigured {
            do {
                let dto = try await hubClient.getSinistroFromCloud(riferimento: riferimento)
                return SinistroFull(from: dto)
            } catch {
                print("[iPadSync] ⚠️ Cloud API dettaglio fallita, provo Hub: \(error)")
            }
        }

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
        if hubClient.isCloudConfigured {
            do {
                return try await hubClient.getDiarioEntriesFromCloud(riferimento: riferimento)
            } catch {
                print("[iPadSync] ⚠️ Cloud API diario fallita, provo Hub: \(error)")
            }
        }

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
        if hubClient.isCloudConfigured {
            do {
                return try await hubClient.addDiarioEntryToCloud(riferimento: riferimento, entry: request)
            } catch {
                print("[iPadSync] ⚠️ Cloud API add diario fallita, provo Hub: \(error)")
            }
        }
        let hubEntry = try await hubClient.addDiarioEntry(riferimento: riferimento, entry: request)
        return DiarioEntryDTO(from: hubEntry)
    }
    
    // MARK: - Email processate
    
    func fetchProcessedEmails(riferimento: String) async throws -> [ProcessedEmailDTO] {
        if hubClient.isCloudConfigured {
            do {
                return try await hubClient.getProcessedEmailsFromCloud(riferimento: riferimento)
            } catch {
                print("[iPadSync] ⚠️ Cloud API email fallita, provo CloudKit: \(error)")
            }
        }

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
    let substate: String?
    
    // Attori
    let nomeAssicurato: String
    let nomeDanneggiato: String?
    
    // Compagnia/Agenzia
    let nomeCompagnia: String
    let gruppo: String?
    let agenzia: String?
    
    // Date
    let dataAssegnazione: Date?
    let dataChiusura: Date?
    let dataSinistro: Date?
    let dataInvioAtto: Date?
    
    // Importi
    let stimaDanno: Double?
    let liquidato: Double?
    let richiesta: Double?
    
    // Tipo
    let tipoPolizza: String?
    let sopralluogo: Bool
    let fulminazione: Bool
    
    // Indicatori
    let complessita: String?
    let prioritaManuale: Double?      // Override manuale (nil = usa calcolata)
    let prioritaCalcolata: Double     // Priorità calcolata dal sistema (0-100)
    let sollecitiRicevutiCount: Int
    let beniCount: Int
    let taskCount: Int
    let ownerEmail: String?
    let assignedToUserEmail: String?
    
    /// Priorità effettiva: manuale se impostata, altrimenti calcolata
    var prioritaEffettiva: Double {
        prioritaManuale ?? prioritaCalcolata
    }
    
    /// True se la priorità è stata impostata manualmente
    var hasManualPriority: Bool {
        prioritaManuale != nil
    }
    
    var isOpen: Bool {
        dataChiusura == nil
    }
    
    /// Riferimento formattato per visualizzazione (con sigla compagnia se abilitato)
    /// Esempio: "ZUR-2500123" se abilitato, "2500123" se disabilitato
    var riferimentoVisualizzato: String {
        let showSigla = UserDefaults.standard.bool(forKey: "includiCodiceCompagniaRiferimento")
        
        if showSigla {
            let compagniaDetected = Compagnia.detect(gruppo: gruppo, compagnia: nomeCompagnia)
            if compagniaDetected != .unknown, !compagniaDetected.sigla.isEmpty {
                return "\(compagniaDetected.sigla)-\(riferimento)"
            }
        }
        return riferimento
    }
    
    /// Estrae l'anno del sinistro dalle prime 2 cifre numeriche del riferimento
    var annoSinistro: Int? {
        var digits = ""
        for char in riferimento {
            if char.isNumber {
                digits.append(char)
                if digits.count == 2 {
                    break
                }
            }
        }
        guard digits.count == 2, let yy = Int(digits) else { return nil }
        return 2000 + yy
    }
    
    var prioritaLabel: String {
        let p = prioritaEffettiva
        switch p {
        case 0..<20: return "Bassa"
        case 20..<40: return "Media"
        case 40..<60: return "Alta"
        case 60..<80: return "Molto Alta"
        default: return "Critica"
        }
    }
    
    var prioritaColor: Color {
        let p = prioritaEffettiva
        switch p {
        case 0..<20: return .green
        case 20..<40: return .yellow
        case 40..<60: return .orange
        case 60..<80: return .purple
        default: return .red
        }
    }
    
    // Init diretto
    init(id: String, riferimento: String, stato: String, nomeAssicurato: String, nomeCompagnia: String, dataAssegnazione: Date?, dataChiusura: Date?, stimaDanno: Double?, substate: String?, fulminazione: Bool, nomeDanneggiato: String? = nil, gruppo: String? = nil, agenzia: String? = nil, dataSinistro: Date? = nil, dataInvioAtto: Date? = nil, liquidato: Double? = nil, richiesta: Double? = nil, tipoPolizza: String? = nil, sopralluogo: Bool = false, complessita: String? = nil, prioritaManuale: Double? = nil, prioritaCalcolata: Double = 0, sollecitiRicevutiCount: Int = 0, beniCount: Int = 0, taskCount: Int = 0, ownerEmail: String? = nil, assignedToUserEmail: String? = nil) {
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
        self.nomeDanneggiato = nomeDanneggiato
        self.gruppo = gruppo
        self.agenzia = agenzia
        self.dataSinistro = dataSinistro
        self.dataInvioAtto = dataInvioAtto
        self.liquidato = liquidato
        self.richiesta = richiesta
        self.tipoPolizza = tipoPolizza
        self.sopralluogo = sopralluogo
        self.complessita = complessita
        self.prioritaManuale = prioritaManuale
        self.prioritaCalcolata = prioritaCalcolata
        self.sollecitiRicevutiCount = sollecitiRicevutiCount
        self.beniCount = beniCount
        self.taskCount = taskCount
        self.ownerEmail = ownerEmail
        self.assignedToUserEmail = assignedToUserEmail
    }
    
    // Init da CloudKit
    init?(from record: CKRecord) {
        guard let rif = record["riferimento"] as? String else { return nil }
        
        self.id = rif
        self.riferimento = rif
        self.stato = record["stato"] as? String ?? ""
        self.substate = record["substate"] as? String
        self.nomeAssicurato = record["nomeAssicurato"] as? String ?? ""
        self.nomeDanneggiato = record["nomeDanneggiato"] as? String
        self.nomeCompagnia = record["nomeCompagnia"] as? String ?? ""
        self.gruppo = record["gruppo"] as? String
        self.agenzia = record["agenzia"] as? String
        self.dataAssegnazione = record["dataAssegnazione"] as? Date
        self.dataChiusura = record["dataChiusura"] as? Date
        self.dataSinistro = record["dataSinistro"] as? Date
        self.dataInvioAtto = record["dataInvioAtto"] as? Date
        self.stimaDanno = record["stimaDanno"] as? Double
        self.liquidato = record["liquidato"] as? Double
        self.richiesta = record["richiesta"] as? Double
        self.tipoPolizza = record["tipoPolizza"] as? String
        self.sopralluogo = record["sopralluogo"] as? Bool ?? false
        self.fulminazione = (record["fulminazione"] as? String) != nil && (record["fulminazione"] as? String) != "Non effettuata"
        self.complessita = record["complessita"] as? String
        self.prioritaManuale = record["prioritaManuale"] as? Double
        self.prioritaCalcolata = record["prioritaCalcolata"] as? Double ?? 0
        self.sollecitiRicevutiCount = (record["sollecitiRicevutiCount"] as? Int) ?? 0
        self.beniCount = (record["beniCount"] as? Int) ?? 0
        self.taskCount = (record["taskCount"] as? Int) ?? 0
        self.ownerEmail = record["ownerEmail"] as? String
        self.assignedToUserEmail = record["assignedToUserEmail"] as? String
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
    let stato: String
    let substate: String?
    
    // Compagnia/Agenzia
    let nomeCompagnia: String?
    let gruppo: String?
    let area: String?
    let divisioneCompagnia: String?
    let agenzia: String?
    let codiceAgenzia: String?
    let telefonoAgenzia: String?
    let emailAgenzia: String?
    
    // Contraente
    let nomeContraente: String?
    let indirizzoContraente: String?
    let telefonoContraente: String?
    let emailContraente: String?
    
    // Assicurato
    let nomeAssicurato: String?
    let indirizzoAssicurato: String?
    let telefonoAssicurato: String?
    let emailAssicurato: String?
    let codiceFiscaleAssicurato: String?
    let partitaIVAAssicurato: String?
    
    // Danneggiato
    let nomeDanneggiato: String?
    let indirizzoDanneggiato: String?
    let telefonoDanneggiato: String?
    let emailDanneggiato: String?
    
    // Polizza
    let numeroPolizza: String?
    let tipoPolizza: String?
    let numeroSinistroCompagnia: String?
    
    // Importi
    let richiesta: Double?
    let liquidato: Double?
    let dannoAccertato: Double?
    let stimaDanno: Double?
    let definizione: String?
    let oltreDieciBeni: Bool
    
    // Date
    let dataSinistro: Date?
    let dataDenuncia: Date?
    let dataIncarico: Date?
    let dataSopralluogo: Date?
    let dataAssegnazione: Date?
    let dataInvioAtto: Date?
    let dataChiusura: Date?
    let dataAperturaGestione: Date?
    let dataRitornoAtto: Date?
    let dataComunicazioneEsito: Date?
    let dataRicezioneAttoSottoscritto: Date?
    let dataAccettazioneVerbale: Date?
    let dataRevoca: Date?
    let dataPagamentoPremio: Date?
    
    // Verifiche
    let fulminazione: String?
    let sopralluogo: Bool
    let giustificativi: Bool
    let iban: Bool
    let regolaritaAmministrativa: Bool?
    let regolaritaAmministrativaOverride: Bool
    
    // Assegnazione
    let ownerEmail: String?
    let assignedToUserEmail: String?
    let assignedToUserName: String?
    
    // Sinistri collegati
    let collegamenti: [String]?
    
    // Init da Hub SinistroDTO
    init(from dto: SinistroDTO) {
        self.id = dto.riferimento
        self.riferimento = dto.riferimento
        self.stato = dto.stato
        self.substate = dto.statoDetail
        self.nomeCompagnia = dto.nomeCompagnia
        self.gruppo = nil
        self.area = nil
        self.divisioneCompagnia = nil
        self.agenzia = nil
        self.codiceAgenzia = nil
        self.telefonoAgenzia = nil
        self.emailAgenzia = nil
        self.nomeContraente = dto.nomeContraente
        self.indirizzoContraente = nil
        self.telefonoContraente = dto.telefonoContraente
        self.emailContraente = dto.emailContraente
        self.nomeAssicurato = dto.nomeAssicurato
        self.indirizzoAssicurato = nil
        self.telefonoAssicurato = dto.telefonoAssicurato
        self.emailAssicurato = dto.emailAssicurato
        self.codiceFiscaleAssicurato = nil
        self.partitaIVAAssicurato = nil
        self.nomeDanneggiato = nil
        self.indirizzoDanneggiato = nil
        self.telefonoDanneggiato = nil
        self.emailDanneggiato = nil
        self.numeroPolizza = dto.numeroPolizza
        self.tipoPolizza = dto.tipoPolizza
        self.numeroSinistroCompagnia = nil
        self.richiesta = dto.stimaDanno
        self.liquidato = dto.liquidato
        self.dannoAccertato = nil
        self.stimaDanno = dto.stimaDanno
        self.definizione = nil
        self.oltreDieciBeni = false
        self.dataSinistro = dto.dataSinistro
        self.dataDenuncia = nil
        self.dataIncarico = nil
        self.dataSopralluogo = nil
        self.dataAssegnazione = dto.dataAssegnazione
        self.dataInvioAtto = nil
        self.dataChiusura = dto.dataChiusura
        self.dataAperturaGestione = nil
        self.dataRitornoAtto = nil
        self.dataComunicazioneEsito = nil
        self.dataRicezioneAttoSottoscritto = nil
        self.dataAccettazioneVerbale = nil
        self.dataRevoca = nil
        self.dataPagamentoPremio = nil
        self.fulminazione = dto.garanzia
        self.sopralluogo = false
        self.giustificativi = false
        self.iban = false
        self.regolaritaAmministrativa = nil
        self.regolaritaAmministrativaOverride = false
        self.ownerEmail = dto.ownerEmail
        self.assignedToUserEmail = dto.assignedToUserEmail
        self.assignedToUserName = nil
        self.collegamenti = nil
    }
    
    // Init da CloudKit
    init?(from record: CKRecord) {
        guard let rif = record["riferimento"] as? String else { return nil }
        
        self.id = rif
        self.riferimento = rif
        self.stato = record["stato"] as? String ?? ""
        self.substate = record["substate"] as? String
        self.nomeCompagnia = record["nomeCompagnia"] as? String
        self.gruppo = record["gruppo"] as? String
        self.area = record["area"] as? String
        self.divisioneCompagnia = record["divisioneCompagnia"] as? String
        self.agenzia = record["agenzia"] as? String
        self.codiceAgenzia = record["codiceAgenzia"] as? String
        self.telefonoAgenzia = record["telefonoAgenzia"] as? String
        self.emailAgenzia = record["emailAgenzia"] as? String
        self.nomeContraente = record["nomeContraente"] as? String
        self.indirizzoContraente = record["indirizzoContraente"] as? String
        self.telefonoContraente = record["telefonoContraente"] as? String
        self.emailContraente = record["emailContraente"] as? String
        self.nomeAssicurato = record["nomeAssicurato"] as? String
        self.indirizzoAssicurato = record["indirizzoAssicurato"] as? String
        self.telefonoAssicurato = record["telefonoAssicurato"] as? String
        self.emailAssicurato = record["emailAssicurato"] as? String
        self.codiceFiscaleAssicurato = record["codiceFiscaleAssicurato"] as? String
        self.partitaIVAAssicurato = record["partitaIVAAssicurato"] as? String
        self.nomeDanneggiato = record["nomeDanneggiato"] as? String
        self.indirizzoDanneggiato = record["indirizzoDanneggiato"] as? String
        self.telefonoDanneggiato = record["telefonoDanneggiato"] as? String
        self.emailDanneggiato = record["emailDanneggiato"] as? String
        self.numeroPolizza = record["numeroPolizza"] as? String
        self.tipoPolizza = record["tipoPolizza"] as? String
        self.numeroSinistroCompagnia = record["numeroSinistroCompagnia"] as? String
        self.richiesta = record["richiesta"] as? Double
        self.liquidato = record["liquidato"] as? Double
        self.dannoAccertato = record["dannoAccertato"] as? Double
        self.stimaDanno = record["stimaDanno"] as? Double
        self.definizione = record["definizione"] as? String
        self.oltreDieciBeni = record["oltreDieciBeni"] as? Bool ?? false
        self.dataSinistro = record["dataSinistro"] as? Date
        self.dataDenuncia = record["dataDenuncia"] as? Date
        self.dataIncarico = record["dataIncarico"] as? Date
        self.dataSopralluogo = record["dataSopralluogo"] as? Date
        self.dataAssegnazione = record["dataAssegnazione"] as? Date
        self.dataInvioAtto = record["dataInvioAtto"] as? Date
        self.dataChiusura = record["dataChiusura"] as? Date
        self.dataAperturaGestione = record["dataAperturaGestione"] as? Date
        self.dataRitornoAtto = record["dataRitornoAtto"] as? Date
        self.dataComunicazioneEsito = record["dataComunicazioneEsito"] as? Date
        self.dataRicezioneAttoSottoscritto = record["dataRicezioneAttoSottoscritto"] as? Date
        self.dataAccettazioneVerbale = record["dataAccettazioneVerbale"] as? Date
        self.dataRevoca = record["dataRevoca"] as? Date
        self.dataPagamentoPremio = record["dataPagamentoPremio"] as? Date
        self.fulminazione = record["fulminazione"] as? String
        self.sopralluogo = record["sopralluogo"] as? Bool ?? false
        self.giustificativi = record["giustificativi"] as? Bool ?? false
        self.iban = record["iban"] as? Bool ?? false
        self.regolaritaAmministrativa = record["regolaritaAmministrativa"] as? Bool
        self.regolaritaAmministrativaOverride = record["regolaritaAmministrativaOverride"] as? Bool ?? false
        self.ownerEmail = record["ownerEmail"] as? String
        self.assignedToUserEmail = record["assignedToUserEmail"] as? String
        self.assignedToUserName = record["assignedToUserName"] as? String
        self.collegamenti = record["collegamenti"] as? [String]
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

    init(from dto: CloudDiaryEntryDTO) {
        self.id = dto.id
        self.timestamp = dto.happened_at
        self.tipo = dto.entry_type
        self.titolo = dto.title
        self.riassunto = dto.body_text ?? ""
        self.contenutoCompleto = dto.body_text
        self.createdBy = dto.created_by_user_id
    }
}

struct ProcessedEmailDTO: Identifiable, Codable, Hashable {
    let id: String
    let messageId: String
    let subject: String
    let from: String
    let to: [String]
    let cc: [String]
    let date: Date?
    let category: String?
    let sinistroRiferimento: String?
    let sinistroAssicurato: String?
    let bodyText: String?
    let bodyHtml: String?
    let folder: String?
    let isRead: Bool
    let hasAttachments: Bool
    let attachments: [String]
    
    init?(from record: CKRecord) {
        guard let msgId = record["messageId"] as? String else { return nil }
        
        self.id = msgId
        self.messageId = msgId
        self.subject = record["subject"] as? String ?? ""
        self.from = record["from"] as? String ?? ""
        self.to = (record["to"] as? [String]) ?? []
        self.cc = (record["cc"] as? [String]) ?? []
        self.date = record["date"] as? Date
        self.category = record["category"] as? String
        self.sinistroRiferimento = record["sinistroRiferimento"] as? String
        self.sinistroAssicurato = record["sinistroAssicurato"] as? String
        self.bodyText = record["bodyText"] as? String
        self.bodyHtml = record["bodyHtml"] as? String
        self.folder = record["folder"] as? String
        self.isRead = record["isRead"] as? Bool ?? true
        self.hasAttachments = record["hasAttachments"] as? Bool ?? false
        self.attachments = (record["attachments"] as? [String]) ?? []
    }

    init(from dto: CloudEmailDTO, sinistroRiferimento: String?) {
        self.id = dto.id
        self.messageId = dto.message_id
        self.subject = dto.subject ?? ""
        self.from = dto.from_address
        self.to = []
        self.cc = []
        self.date = dto.received_at
        self.category = dto.status
        self.sinistroRiferimento = sinistroRiferimento
        self.sinistroAssicurato = nil
        self.bodyText = dto.body_text
        self.bodyHtml = dto.body_html
        self.folder = dto.mailbox_id
        self.isRead = true
        self.hasAttachments = false
        self.attachments = []
    }
    
    // Convenience initializer for local creation
    init(id: String, messageId: String, subject: String, from: String, to: [String] = [], cc: [String] = [],
         date: Date? = nil, category: String? = nil, sinistroRiferimento: String? = nil,
         sinistroAssicurato: String? = nil, bodyText: String? = nil, bodyHtml: String? = nil,
         folder: String? = nil, isRead: Bool = true, hasAttachments: Bool = false, attachments: [String] = []) {
        self.id = id
        self.messageId = messageId
        self.subject = subject
        self.from = from
        self.to = to
        self.cc = cc
        self.date = date
        self.category = category
        self.sinistroRiferimento = sinistroRiferimento
        self.sinistroAssicurato = sinistroAssicurato
        self.bodyText = bodyText
        self.bodyHtml = bodyHtml
        self.folder = folder
        self.isRead = isRead
        self.hasAttachments = hasAttachments
        self.attachments = attachments
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
