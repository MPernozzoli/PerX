import Foundation
import Combine
import SwiftUI

/// Servizio di sincronizzazione per iPad.
/// Usa Cloud API (Supabase backend) come fonte primaria, Hub locale come fallback.
/// CloudKit rimosso: tutti i dati passano per il backend.
@MainActor
final class iPadSyncService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var sinistri: [SinistroMinimal] = []
    @Published private(set) var lastError: String?
    @Published private(set) var dataSource: DataSource = .none

    enum DataSource: String {
        case none = "Non connesso"
        case cloudAPI = "Cloud API"
    }

    // MARK: - Dependencies

    let hubClient = HubAPIClient.shared
    private let userEmail: String
    private var pollTimer: Timer?

    // MARK: - Init

    init(userEmail: String) {
        self.userEmail = userEmail.lowercased()
    }

    // MARK: - Lifecycle

    func start() async {
        print("[iPadSync] ▶️ Avvio sync per: \(userEmail)")
        await syncNow()
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
            Task { @MainActor in await self?.syncNow() }
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

        do {
            try await fetchSinistriFromCloudAPI()
            dataSource = .cloudAPI
            print("[iPadSync] ✅ Cloud API: \(sinistri.count) sinistri")
        } catch {
            lastError = error.localizedDescription
            dataSource = .none
            print("[iPadSync] ❌ Sync fallita: \(error)")
        }
    }

    // MARK: - Sinistri

    private func fetchSinistriFromCloudAPI() async throws {
        let dtos = try await hubClient.getSinistriFromCloud()
        sinistri = dtos.map { SinistroMinimal(from: $0) }
    }

    // MARK: - Sinistro Full

    func fetchSinistroFull(riferimento: String) async throws -> SinistroFull? {
        let dto = try await hubClient.getSinistroFromCloud(riferimento: riferimento)
        return SinistroFull(from: dto)
    }

    // MARK: - Diario

    func fetchDiarioEntries(riferimento: String) async throws -> [DiarioEntryDTO] {
        try await hubClient.getDiarioEntriesFromCloud(riferimento: riferimento)
    }

    func addDiarioEntry(riferimento: String, testo: String, tipo: String = "nota") async throws -> DiarioEntryDTO {
        let request = CreateDiarioEntryRequest(tipo: tipo, titolo: nil, testo: testo)
        return try await hubClient.addDiarioEntryToCloud(riferimento: riferimento, entry: request)
    }

    // MARK: - Email processate

    func fetchProcessedEmails(riferimento: String) async throws -> [ProcessedEmailDTO] {
        try await hubClient.getProcessedEmailsFromCloud(riferimento: riferimento)
    }

    // MARK: - WhatsApp

    func fetchWhatsAppMessages(riferimento: String) async throws -> [WhatsAppMessageDTO] {
        try await hubClient.getWhatsAppMessagesFromCloud(riferimento: riferimento)
    }

    func handleRemoteNotification() async {
        await syncNow()
    }
}

// MARK: - DTOs (CloudKit inits rimossi)

struct SinistroMinimal: Identifiable, Codable, Hashable {
    let id: String
    let riferimento: String
    let stato: String
    let substate: String?
    let nomeAssicurato: String
    let nomeDanneggiato: String?
    let nomeCompagnia: String
    let gruppo: String?
    let agenzia: String?
    let dataAssegnazione: Date?
    let dataChiusura: Date?
    let dataSinistro: Date?
    let dataInvioAtto: Date?
    let stimaDanno: Double?
    let liquidato: Double?
    let richiesta: Double?
    let tipoPolizza: String?
    let sopralluogo: Bool
    let fulminazione: Bool
    let complessita: String?
    let prioritaManuale: Double?
    let prioritaCalcolata: Double
    let sollecitiRicevutiCount: Int
    let beniCount: Int
    let taskCount: Int
    let ownerEmail: String?
    let assignedToUserEmail: String?

    var prioritaEffettiva: Double { prioritaManuale ?? prioritaCalcolata }
    var hasManualPriority: Bool { prioritaManuale != nil }
    var isOpen: Bool { dataChiusura == nil }

    var riferimentoVisualizzato: String {
        let showSigla = UserDefaults.standard.bool(forKey: "includiCodiceCompagniaRiferimento")
        if showSigla {
            let c = Compagnia.detect(gruppo: gruppo, compagnia: nomeCompagnia)
            if c != .unknown, !c.sigla.isEmpty { return "\(c.sigla)-\(riferimento)" }
        }
        return riferimento
    }

    var annoSinistro: Int? {
        var digits = ""
        for char in riferimento where char.isNumber {
            digits.append(char)
            if digits.count == 2 { break }
        }
        guard digits.count == 2, let yy = Int(digits) else { return nil }
        return 2000 + yy
    }

    var prioritaLabel: String {
        switch prioritaEffettiva {
        case 0..<20: return "Bassa"
        case 20..<40: return "Media"
        case 40..<60: return "Alta"
        case 60..<80: return "Molto Alta"
        default: return "Critica"
        }
    }

    var prioritaColor: Color {
        switch prioritaEffettiva {
        case 0..<20: return .green
        case 20..<40: return .yellow
        case 40..<60: return .orange
        case 60..<80: return .purple
        default: return .red
        }
    }

    init(id: String, riferimento: String, stato: String, nomeAssicurato: String, nomeCompagnia: String,
         dataAssegnazione: Date?, dataChiusura: Date?, stimaDanno: Double?, substate: String?,
         fulminazione: Bool, nomeDanneggiato: String? = nil, gruppo: String? = nil, agenzia: String? = nil,
         dataSinistro: Date? = nil, dataInvioAtto: Date? = nil, liquidato: Double? = nil,
         richiesta: Double? = nil, tipoPolizza: String? = nil, sopralluogo: Bool = false,
         complessita: String? = nil, prioritaManuale: Double? = nil, prioritaCalcolata: Double = 0,
         sollecitiRicevutiCount: Int = 0, beniCount: Int = 0, taskCount: Int = 0,
         ownerEmail: String? = nil, assignedToUserEmail: String? = nil) {
        self.id = id; self.riferimento = riferimento; self.stato = stato
        self.nomeAssicurato = nomeAssicurato; self.nomeCompagnia = nomeCompagnia
        self.dataAssegnazione = dataAssegnazione; self.dataChiusura = dataChiusura
        self.stimaDanno = stimaDanno; self.substate = substate; self.fulminazione = fulminazione
        self.nomeDanneggiato = nomeDanneggiato; self.gruppo = gruppo; self.agenzia = agenzia
        self.dataSinistro = dataSinistro; self.dataInvioAtto = dataInvioAtto
        self.liquidato = liquidato; self.richiesta = richiesta; self.tipoPolizza = tipoPolizza
        self.sopralluogo = sopralluogo; self.complessita = complessita
        self.prioritaManuale = prioritaManuale; self.prioritaCalcolata = prioritaCalcolata
        self.sollecitiRicevutiCount = sollecitiRicevutiCount; self.beniCount = beniCount
        self.taskCount = taskCount; self.ownerEmail = ownerEmail
        self.assignedToUserEmail = assignedToUserEmail
    }

    init(from dto: SinistroDTO) {
        self.init(
            id: dto.riferimento, riferimento: dto.riferimento, stato: dto.stato,
            nomeAssicurato: dto.nomeAssicurato, nomeCompagnia: dto.nomeCompagnia,
            dataAssegnazione: dto.dataAssegnazione, dataChiusura: dto.dataChiusura,
            stimaDanno: dto.stimaDanno, substate: dto.statoDetail,
            fulminazione: dto.garanzia == "Fenomeno Elettrico",
            liquidato: dto.liquidato, ownerEmail: dto.ownerEmail,
            assignedToUserEmail: dto.assignedToUserEmail
        )
    }

    func hash(into hasher: inout Hasher) { hasher.combine(riferimento) }
    static func == (lhs: SinistroMinimal, rhs: SinistroMinimal) -> Bool { lhs.riferimento == rhs.riferimento }
}

struct SinistroFull: Identifiable, Codable {
    let id: String
    let riferimento: String
    let stato: String
    let substate: String?
    let nomeCompagnia: String?
    let gruppo: String?
    let area: String?
    let divisioneCompagnia: String?
    let agenzia: String?
    let codiceAgenzia: String?
    let telefonoAgenzia: String?
    let emailAgenzia: String?
    let nomeContraente: String?
    let indirizzoContraente: String?
    let telefonoContraente: String?
    let emailContraente: String?
    let nomeAssicurato: String?
    let indirizzoAssicurato: String?
    let telefonoAssicurato: String?
    let emailAssicurato: String?
    let codiceFiscaleAssicurato: String?
    let partitaIVAAssicurato: String?
    let nomeDanneggiato: String?
    let indirizzoDanneggiato: String?
    let telefonoDanneggiato: String?
    let emailDanneggiato: String?
    let numeroPolizza: String?
    let tipoPolizza: String?
    let numeroSinistroCompagnia: String?
    let richiesta: Double?
    let liquidato: Double?
    let dannoAccertato: Double?
    let stimaDanno: Double?
    let definizione: String?
    let oltreDieciBeni: Bool
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
    let fulminazione: String?
    let sopralluogo: Bool
    let giustificativi: Bool
    let iban: Bool
    let regolaritaAmministrativa: Bool?
    let regolaritaAmministrativaOverride: Bool
    let ownerEmail: String?
    let assignedToUserEmail: String?
    let assignedToUserName: String?
    let collegamenti: [String]?

    init(from dto: SinistroDTO) {
        self.id = dto.riferimento
        self.riferimento = dto.riferimento
        self.stato = dto.stato
        self.substate = dto.statoDetail
        self.nomeCompagnia = dto.nomeCompagnia
        self.gruppo = nil; self.area = nil; self.divisioneCompagnia = nil
        self.agenzia = nil; self.codiceAgenzia = nil; self.telefonoAgenzia = nil; self.emailAgenzia = nil
        self.nomeContraente = dto.nomeContraente
        self.indirizzoContraente = nil
        self.telefonoContraente = dto.telefonoContraente
        self.emailContraente = dto.emailContraente
        self.nomeAssicurato = dto.nomeAssicurato
        self.indirizzoAssicurato = nil
        self.telefonoAssicurato = dto.telefonoAssicurato
        self.emailAssicurato = dto.emailAssicurato
        self.codiceFiscaleAssicurato = nil; self.partitaIVAAssicurato = nil
        self.nomeDanneggiato = nil; self.indirizzoDanneggiato = nil
        self.telefonoDanneggiato = nil; self.emailDanneggiato = nil
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
        self.dataDenuncia = nil; self.dataIncarico = nil; self.dataSopralluogo = nil
        self.dataAssegnazione = dto.dataAssegnazione
        self.dataInvioAtto = nil
        self.dataChiusura = dto.dataChiusura
        self.dataAperturaGestione = nil; self.dataRitornoAtto = nil
        self.dataComunicazioneEsito = nil; self.dataRicezioneAttoSottoscritto = nil
        self.dataAccettazioneVerbale = nil; self.dataRevoca = nil; self.dataPagamentoPremio = nil
        self.fulminazione = dto.garanzia
        self.sopralluogo = false; self.giustificativi = false; self.iban = false
        self.regolaritaAmministrativa = nil; self.regolaritaAmministrativaOverride = false
        self.ownerEmail = dto.ownerEmail
        self.assignedToUserEmail = dto.assignedToUserEmail
        self.assignedToUserName = nil
        self.collegamenti = nil
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

    init(from hubDTO: DiarioEntryHubDTO) {
        self.id = hubDTO.id; self.timestamp = hubDTO.timestamp; self.tipo = hubDTO.tipo
        self.titolo = hubDTO.titolo; self.riassunto = hubDTO.riassunto
        self.contenutoCompleto = hubDTO.contenutoCompleto; self.createdBy = hubDTO.createdBy
    }

    init(from dto: CloudDiaryEntryDTO) {
        self.id = dto.id; self.timestamp = dto.happened_at; self.tipo = dto.entry_type
        self.titolo = dto.title; self.riassunto = dto.body_text ?? ""
        self.contenutoCompleto = dto.body_text; self.createdBy = dto.created_by_user_id
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

    init(from dto: CloudEmailDTO, sinistroRiferimento: String?) {
        self.id = dto.id; self.messageId = dto.message_id
        self.subject = dto.subject ?? ""; self.from = dto.from_address
        self.to = []; self.cc = []; self.date = dto.received_at
        self.category = dto.status; self.sinistroRiferimento = sinistroRiferimento
        self.sinistroAssicurato = nil; self.bodyText = dto.body_text
        self.bodyHtml = dto.body_html; self.folder = dto.mailbox_id
        self.isRead = true; self.hasAttachments = false; self.attachments = []
    }

    init(id: String, messageId: String, subject: String, from: String, to: [String] = [],
         cc: [String] = [], date: Date? = nil, category: String? = nil,
         sinistroRiferimento: String? = nil, sinistroAssicurato: String? = nil,
         bodyText: String? = nil, bodyHtml: String? = nil, folder: String? = nil,
         isRead: Bool = true, hasAttachments: Bool = false, attachments: [String] = []) {
        self.id = id; self.messageId = messageId; self.subject = subject; self.from = from
        self.to = to; self.cc = cc; self.date = date; self.category = category
        self.sinistroRiferimento = sinistroRiferimento; self.sinistroAssicurato = sinistroAssicurato
        self.bodyText = bodyText; self.bodyHtml = bodyHtml; self.folder = folder
        self.isRead = isRead; self.hasAttachments = hasAttachments; self.attachments = attachments
    }

    func hash(into hasher: inout Hasher) { hasher.combine(messageId) }
    static func == (lhs: ProcessedEmailDTO, rhs: ProcessedEmailDTO) -> Bool { lhs.messageId == rhs.messageId }
}

struct WhatsAppMessageDTO: Identifiable, Codable {
    let id: String
    let chatId: String
    let from: String
    let body: String
    let timestamp: Date
    let direction: String
    let mediaType: String?
}
