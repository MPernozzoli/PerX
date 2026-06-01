import Foundation

// ============================================================================
// MARK: - Rubrica DTOs (Backend)
//
// DTO leggeri che mappano /api/v1/rubrica/{agenzie,compagnie} del backend.
// Convivono con `RubricaAgenzia` (CloudKit sync, più ricco) e con l'enum
// hardcoded `Compagnia`: questi servono solo al RubricaPickerView per
// permettere all'utente di selezionare un'agenzia o compagnia dalla
// rubrica server e collegarla al sinistro tramite agency_id/compagnia_id.
// ============================================================================

// MARK: - Compagnia

struct CloudCompagniaResponse: Codable, Identifiable, Hashable {
    let id: String
    let tenant_id: String
    let nome: String
    let gruppo: String?
    let codice: String?
    let partita_iva: String?
    let pec: String?
    let email: String?
    let telefono: String?
    let sito_web: String?
    let note: String?
    let is_active: Bool
    let created_at: Date
    let updated_at: Date
}

struct CloudCompagniaCreate: Codable {
    let nome: String
    let gruppo: String?
    let codice: String?
    let partita_iva: String?
    let pec: String?
    let email: String?
    let telefono: String?
    let sito_web: String?
    let note: String?
    let is_active: Bool

    init(nome: String, gruppo: String? = nil, codice: String? = nil) {
        self.nome = nome
        self.gruppo = gruppo
        self.codice = codice
        self.partita_iva = nil
        self.pec = nil
        self.email = nil
        self.telefono = nil
        self.sito_web = nil
        self.note = nil
        self.is_active = true
    }
}

struct CloudCompagniaListResponse: Codable {
    let items: [CloudCompagniaResponse]
    let total: Int
}

// MARK: - Agenzia (backend-side, semplice)

struct CloudAgenziaResponse: Codable, Identifiable, Hashable {
    let id: String
    let tenant_id: String
    let nome: String
    let codice: String?
    let indirizzo: String?
    let citta: String?
    let provincia: String?
    let telefono: String?
    let email: String?
    let compagnia: String?
    let gruppo: String?
    let note: String?
    let is_active: Bool
    let created_at: Date
    let updated_at: Date
}

struct CloudAgenziaCreate: Codable {
    let nome: String
    let codice: String?
    let indirizzo: String?
    let citta: String?
    let provincia: String?
    let telefono: String?
    let email: String?
    let compagnia: String?
    let gruppo: String?
    let note: String?
    let is_active: Bool

    init(nome: String, codice: String? = nil) {
        self.nome = nome
        self.codice = codice
        self.indirizzo = nil
        self.citta = nil
        self.provincia = nil
        self.telefono = nil
        self.email = nil
        self.compagnia = nil
        self.gruppo = nil
        self.note = nil
        self.is_active = true
    }
}

struct CloudAgenziaListResponse: Codable {
    let items: [CloudAgenziaResponse]
    let total: Int
}
