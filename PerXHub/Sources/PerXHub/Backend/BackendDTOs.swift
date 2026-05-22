import Foundation
import PerXCore

// ============================================================================
// MARK: - BackendDTOs
// DTOs che mappano le response del backend FastAPI PerX.
// Usati internamente da BackendAPIClient per decode + conversione verso i
// tipi condivisi di PerXCore (SinistroDTO, DiarioEntryDTO, HubTask, etc.)
// ============================================================================

// MARK: - Auth

/// Response di POST /api/v1/auth/login
struct BackendLoginResponse: Decodable {
    let access_token: String
    let token_type: String
    let expires_in: Int?       // secondi, opzionale se non restituito
}

// MARK: - Claims (Sinistri)

/// Claim in formato lista dal backend
struct BackendClaimMinimal: Codable {
    let id: String
    let external_ref: String?
    let stato_corrente: String?
    let nome_assicurato: String?
    let compagnia: String?
    let agenzia: String?
    let numero_polizza: String?
    let data_assegnazione: String?   // ISO8601
    let data_evento: String?         // ISO8601
    let data_chiusura: String?       // ISO8601
    let assegnatario_email: String?
    let assegnatario_nome: String?
    let complessita: String?
    let definizione: String?
    let importo_liquidato: Double?
    let updated_at: String?          // ISO8601
    let created_at: String?          // ISO8601
}

/// Claim full (usato anche per la lista, il backend può restituire lo stesso schema)
typealias BackendClaimFull = BackendClaimMinimal

/// Response paginata per GET /api/v1/claims
struct BackendClaimsPage: Decodable {
    let items: [BackendClaimMinimal]?
    let total: Int?
    let page: Int?
    let page_size: Int?
    // Alcuni backend restituiscono direttamente un array
}

/// Body per POST /api/v1/claims
struct BackendCreateClaimBody: Encodable {
    let external_ref: String?
    let stato_corrente: String?
    let nome_assicurato: String?
    let compagnia: String?
    let agenzia: String?
    let numero_polizza: String?
    let data_assegnazione: String?
    let data_evento: String?
    let data_chiusura: String?
    let assegnatario_email: String?
    let assegnatario_nome: String?
    let complessita: String?
    let definizione: String?
    let importo_liquidato: Double?
    let last_modified_by: String?
}

/// Body per PUT /api/v1/claims/{id}
struct BackendUpdateClaimBody: Encodable {
    let stato_corrente: String?
    let data_assegnazione: String?
    let data_evento: String?
    let data_chiusura: String?
    let data_sopralluogo: String?
    let data_invio_atto: String?
    let data_comunicazione_esito: String?
    let richiesta: Double?
    let importo_liquidato: Double?
    let danno_accertato: Double?
    let riserva: Double?
    let nome_assicurato: String?
    let numero_polizza: String?
    let agenzia: String?
    let complessita: String?
    let definizione: String?
    let tipo_servizio: String?
}

// MARK: - Diary

/// Entry diario dal backend
struct BackendDiaryEntry: Codable {
    let id: String
    let claim_id: String?
    let timestamp: String?       // ISO8601
    let testo: String?
    let tipo: String?
    let titolo: String?
    let riassunto: String?
    let contenuto_completo: String?
    let created_by_email: String?
    let created_at: String?
}

/// Body per POST /api/v1/diary (o /api/v1/claims/{id}/diary)
struct BackendCreateDiaryEntryBody: Encodable {
    let claim_id: String
    let timestamp: String         // ISO8601
    let testo: String
    let tipo: String?
    let titolo: String?
    let riassunto: String?
    let contenuto_completo: String?
    let created_by_email: String?
    let external_entry_id: String?  // = DiarioEntryDTO.id (per idempotenza)
}

// MARK: - Tasks

/// Task dal backend
struct BackendTask: Codable {
    let id: String
    let title: String
    let description: String?
    let task_type: String?
    let priority: String?
    let sinistro_ref: String?
    let due_date: String?
    let reminder_date: String?
    let status: String?
    let assigned_to: String?
    let created_by: String?
    let created_at: String?
    let completed_at: String?
}

/// Body per POST /api/v1/tasks
struct BackendCreateTaskBody: Encodable {
    let external_id: String
    let title: String
    let description: String?
    let task_type: String?
    let priority: String?
    let sinistro_ref: String?
    let due_date: String?
    let reminder_date: String?
    let status: String?
    let assigned_to: String?
    let created_by: String?
    let created_at: String?
}

// MARK: - Email events / processed emails

/// Body per POST /api/v1/processed-emails
struct BackendProcessedEmailBody: Encodable {
    let message_id: String
    let user_email: String?
    let sinistro_ref: String?
    let category: String?
    let processed_at: String    // ISO8601
}

/// Body per POST /api/v1/email-events
struct BackendEmailEventBody: Encodable {
    let event_id: String
    let email_id: String
    let event_type: String
    let direction: String
    let sinistro_id: String?
    let timestamp: String       // ISO8601
}

// MARK: - Generic wrapper responses

/// Risposta generica {id: ...}
struct BackendCreatedResponse: Decodable {
    let id: String?
}

// MARK: - Conversioni verso tipi PerXCore

extension BackendClaimMinimal {

    /// Converte verso SinistroDTO condiviso
    func toSinistroDTO() -> SinistroDTO {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parseDate(_ str: String?) -> Date? {
            guard let s = str, !s.isEmpty else { return nil }
            if let d = iso.date(from: s) { return d }
            // Prova senza frazioni
            let iso2 = ISO8601DateFormatter()
            iso2.formatOptions = [.withInternetDateTime]
            return iso2.date(from: s)
        }

        // Ricava statoId cercando corrispondenza in StatoSinistro
        let statoDesc = stato_corrente ?? "Da scaricare"
        let statoId: String
        if let s = StatoSinistro.fromDescrizione(statoDesc) {
            statoId = s.rawValue
        } else {
            statoId = "SV001"
        }

        return SinistroDTO(
            id: id,
            riferimento: external_ref ?? id,
            stato: statoDesc,
            statoId: statoId,
            assicurato: nome_assicurato,
            polizza: numero_polizza,
            agenzia: agenzia ?? compagnia,
            dataAssegnazione: parseDate(data_assegnazione),
            dataEvento: parseDate(data_evento),
            dataChiusura: parseDate(data_chiusura),
            ownerEmail: assegnatario_email,
            ownerName: assegnatario_nome,
            complessita: complessita,
            definizione: definizione,
            importoLiquidato: importo_liquidato,
            lastModified: parseDate(updated_at) ?? parseDate(created_at) ?? Date()
        )
    }
}

extension BackendDiaryEntry {

    func toDiarioEntryDTO() -> DiarioEntryDTO {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parseDate(_ str: String?) -> Date? {
            guard let s = str, !s.isEmpty else { return nil }
            if let d = iso.date(from: s) { return d }
            let iso2 = ISO8601DateFormatter()
            iso2.formatOptions = [.withInternetDateTime]
            return iso2.date(from: s)
        }

        return DiarioEntryDTO(
            id: id,
            timestamp: parseDate(timestamp) ?? parseDate(created_at) ?? Date(),
            testo: testo ?? "",
            tipo: tipo,
            titolo: titolo,
            riassunto: riassunto,
            contenutoCompleto: contenuto_completo,
            createdByEmail: created_by_email
        )
    }
}

extension BackendTask {

    func toHubTask() -> HubTask {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parseDate(_ str: String?) -> Date? {
            guard let s = str, !s.isEmpty else { return nil }
            if let d = iso.date(from: s) { return d }
            let iso2 = ISO8601DateFormatter()
            iso2.formatOptions = [.withInternetDateTime]
            return iso2.date(from: s)
        }

        return HubTask(
            id: id,
            title: title,
            description: description,
            type: TaskType(rawValue: task_type ?? "") ?? .action,
            priority: TaskPriority(rawValue: priority ?? "") ?? .normal,
            sinistroRef: sinistro_ref,
            dueDate: parseDate(due_date),
            reminderDate: parseDate(reminder_date),
            status: TaskStatus(rawValue: status ?? "") ?? .pending,
            assignedTo: assigned_to,
            createdBy: created_by,
            createdAt: parseDate(created_at) ?? Date(),
            completedAt: parseDate(completed_at),
            syncedToCK: true
        )
    }
}

// MARK: - Helpers per conversione SinistroDTO → BackendCreateClaimBody

extension SinistroDTO {

    func toBackendCreateBody(modifiedBy: String) -> BackendCreateClaimBody {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        func fmt(_ d: Date?) -> String? { d.map { iso.string(from: $0) } }

        return BackendCreateClaimBody(
            external_ref: riferimento,
            stato_corrente: stato,
            nome_assicurato: assicurato,
            compagnia: agenzia,
            agenzia: agenzia,
            numero_polizza: polizza,
            data_assegnazione: fmt(dataAssegnazione),
            data_evento: fmt(dataEvento),
            data_chiusura: fmt(dataChiusura),
            assegnatario_email: ownerEmail,
            assegnatario_nome: ownerName,
            complessita: complessita,
            definizione: definizione,
            importo_liquidato: importoLiquidato,
            last_modified_by: modifiedBy
        )
    }
}

extension SinistroUpdateRequest {

    func toBackendUpdateBody() -> BackendUpdateClaimBody {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        func fmt(_ d: Date?) -> String? { d.map { iso.string(from: $0) } }

        return BackendUpdateClaimBody(
            stato_corrente: stato,
            data_assegnazione: fmt(dataAssegnazione),
            data_evento: fmt(dataApertura),
            data_chiusura: fmt(dataChiusura),
            data_sopralluogo: fmt(dataSopralluogo),
            data_invio_atto: fmt(dataInvioAtto),
            data_comunicazione_esito: fmt(dataComunicazioneEsito),
            richiesta: richiesta,
            importo_liquidato: liquidato,
            danno_accertato: dannoAccertato,
            riserva: riserva,
            nome_assicurato: assicurato,
            numero_polizza: polizza,
            agenzia: agenzia,
            complessita: complessita,
            definizione: definizione,
            tipo_servizio: tipoServizio
        )
    }
}
