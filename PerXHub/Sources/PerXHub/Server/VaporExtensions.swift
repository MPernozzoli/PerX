import Vapor
import PerXCore

// MARK: - Vapor Content conformance

// Estendi i DTO di PerXCore per essere usati con Vapor

extension VaultFileDTO: @retroactive Content {}
extension SinistroFolderDTO: @retroactive Content {}
extension JobDTO: @retroactive Content {}
extension JobCompleteRequest: @retroactive Content {}
extension JobFailRequest: @retroactive Content {}
extension FileUploadRequest: @retroactive Content {}
extension HealthResponse: @retroactive Content {}
extension LegacyChangesDTO: @retroactive Content {}
extension LegacyScanResult: @retroactive Content {}
extension LegacyFileInfo: @retroactive Content {}
extension AttachmentDTO: @retroactive Content {}
extension ScheduledEmailDTO: @retroactive Content {}
extension HubStatsResponse: @retroactive Content {}
extension HubStatsResponse.JobStats: @retroactive Content {}
extension HubStatsResponse.EmailStats: @retroactive Content {}
extension HubStatsResponse.AttachmentStats: @retroactive Content {}
extension HubStatsResponse.WhatsAppStats: @retroactive Content {}
extension HubStatsResponse.SyncStats: @retroactive Content {}
extension HubStatsResponse.ChromeExtStats: @retroactive Content {}
extension TaskDTO: @retroactive Content {}
extension EmailDTO: @retroactive Content {}
extension PerXCore.EmailDetailDTO: @retroactive Content {}
extension EmailProcessedResponse: @retroactive Content {}
extension SinistroDTO: @retroactive Content {}
extension StateChangeResponse: @retroactive Content {}

extension AssignmentPlannerSettingsDTO: @retroactive Content {}
extension AssignmentMemberSettingsDTO: @retroactive Content {}
extension AssignmentPlanDTO: @retroactive Content {}
extension AssignmentPlanEntryDTO: @retroactive Content {}
extension AssignmentPlanRecomputeRequest: @retroactive Content {}

// MARK: - Mailbox DTO

public struct MailboxDTO: Content, Codable, Sendable {
    public let id: String
    public let name: String
    public let totalCount: Int
    public let unreadCount: Int
    
    public init(id: String, name: String, totalCount: Int, unreadCount: Int) {
        self.id = id
        self.name = name
        self.totalCount = totalCount
        self.unreadCount = unreadCount
    }
}

// MARK: - Chrome Extension DTOs

/// DTO per entry del diario (per Chrome Extension)
public struct DiarioEntryDTO: Content, Codable, Sendable {
    public let id: String
    public let timestamp: Date
    public let testo: String
    public let tipo: String?
    public let titolo: String?
    public let riassunto: String?
    public let contenutoCompleto: String?
    public let createdByEmail: String?
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        testo: String,
        tipo: String? = nil,
        titolo: String? = nil,
        riassunto: String? = nil,
        contenutoCompleto: String? = nil,
        createdByEmail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.testo = testo
        self.tipo = tipo
        self.titolo = titolo
        self.riassunto = riassunto
        self.contenutoCompleto = contenutoCompleto
        self.createdByEmail = createdByEmail
    }
}

/// Request per aggiornamento sinistro (per Chrome Extension)
public struct SinistroUpdateRequest: Content, Codable, Sendable {
    public let stato: String?
    public let dataApertura: Date?
    public let dataAssegnazione: Date?
    public let dataChiusura: Date?
    public let dataSopralluogo: Date?
    public let dataInvioAtto: Date?
    public let dataComunicazioneEsito: Date?
    public let richiesta: Double?
    public let liquidato: Double?
    public let dannoAccertato: Double?
    public let riserva: Double?
    public let assicurato: String?
    public let polizza: String?
    public let agenzia: String?
    public let complessita: String?
    public let definizione: String?
    public let tipoServizio: String?
    
    public init(
        stato: String? = nil,
        dataApertura: Date? = nil,
        dataAssegnazione: Date? = nil,
        dataChiusura: Date? = nil,
        dataSopralluogo: Date? = nil,
        dataInvioAtto: Date? = nil,
        dataComunicazioneEsito: Date? = nil,
        richiesta: Double? = nil,
        liquidato: Double? = nil,
        dannoAccertato: Double? = nil,
        riserva: Double? = nil,
        assicurato: String? = nil,
        polizza: String? = nil,
        agenzia: String? = nil,
        complessita: String? = nil,
        definizione: String? = nil,
        tipoServizio: String? = nil
    ) {
        self.stato = stato
        self.dataApertura = dataApertura
        self.dataAssegnazione = dataAssegnazione
        self.dataChiusura = dataChiusura
        self.dataSopralluogo = dataSopralluogo
        self.dataInvioAtto = dataInvioAtto
        self.dataComunicazioneEsito = dataComunicazioneEsito
        self.richiesta = richiesta
        self.liquidato = liquidato
        self.dannoAccertato = dannoAccertato
        self.riserva = riserva
        self.assicurato = assicurato
        self.polizza = polizza
        self.agenzia = agenzia
        self.complessita = complessita
        self.definizione = definizione
        self.tipoServizio = tipoServizio
    }
}
