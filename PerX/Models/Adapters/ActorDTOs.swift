import Foundation

// ============================================================================
// MARK: - Cloud Actor DTOs
//
// Mappano l'anagrafica unificata lato backend (contraente / assicurato /
// danneggiato). NON sono la stessa cosa di `Attore` Core Data, che è la
// rubrica interna dei team members / liquidatori / agenti / ecc.
//
// Backend endpoint: /api/v1/actors
// Schema Pydantic: backend/app/schemas/actor.py
// ============================================================================

// MARK: - Address

struct CloudActorAddress: Codable, Identifiable, Hashable {
    let id: String
    let actor_id: String
    let label: String?
    let indirizzo: String
    let civico: String?
    let cap: String?
    let citta: String?
    let provincia: String?
    let nazione: String?
    let is_primary: Bool
    let note: String?
    let created_at: Date
    let updated_at: Date

    var inline: String {
        var parts: [String] = []
        if let civico, !civico.isEmpty {
            parts.append("\(indirizzo), \(civico)")
        } else {
            parts.append(indirizzo)
        }
        if let cap, !cap.isEmpty, let citta, !citta.isEmpty {
            parts.append("\(cap) \(citta)")
        } else if let citta, !citta.isEmpty {
            parts.append(citta)
        }
        if let provincia, !provincia.isEmpty {
            parts.append("(\(provincia))")
        }
        return parts.joined(separator: ", ")
    }
}

struct CloudActorAddressCreate: Codable {
    let label: String?
    let indirizzo: String
    let civico: String?
    let cap: String?
    let citta: String?
    let provincia: String?
    let nazione: String?
    let is_primary: Bool
    let note: String?
}

// MARK: - IBAN

struct CloudActorIban: Codable, Identifiable, Hashable {
    let id: String
    let actor_id: String
    let iban: String
    let intestatario: String?
    let banca: String?
    let bic_swift: String?
    let label: String?
    let is_primary: Bool
    let note: String?
    let created_at: Date
    let updated_at: Date
}

struct CloudActorIbanCreate: Codable {
    let iban: String
    let intestatario: String?
    let banca: String?
    let bic_swift: String?
    let label: String?
    let is_primary: Bool
    let note: String?
}

// MARK: - Relation

enum CloudActorRelationType: String, Codable, CaseIterable {
    case figlia, figlio, madre, padre, sorella, fratello, coniuge
    case amministratore, tutore, delegato, altro

    var localized: String {
        switch self {
        case .figlia: return "Figlia"
        case .figlio: return "Figlio"
        case .madre: return "Madre"
        case .padre: return "Padre"
        case .sorella: return "Sorella"
        case .fratello: return "Fratello"
        case .coniuge: return "Coniuge"
        case .amministratore: return "Amministratore"
        case .tutore: return "Tutore"
        case .delegato: return "Delegato"
        case .altro: return "Altro"
        }
    }
}

struct CloudActorRelation: Codable, Identifiable, Hashable {
    let id: String
    let from_actor_id: String
    let to_actor_id: String
    let relation_type: CloudActorRelationType
    let note: String?
    let created_at: Date
}

struct CloudActorRelationCreate: Codable {
    let from_actor_id: String
    let to_actor_id: String
    let relation_type: CloudActorRelationType
    let note: String?
}

// MARK: - Actor

enum CloudActorType: String, Codable, CaseIterable {
    case person, company, condo

    var localized: String {
        switch self {
        case .person: return "Persona fisica"
        case .company: return "Azienda"
        case .condo: return "Condominio"
        }
    }
}

struct CloudActorResponse: Codable, Identifiable, Hashable {
    let id: String
    let tenant_id: String
    let actor_type: CloudActorType
    let nome: String?
    let cognome: String?
    let data_nascita: Date?
    let luogo_nascita: String?
    let sesso: String?
    let denominazione: String?
    let codice_fiscale: String?
    let partita_iva: String?
    let email: String?
    let telefono: String?
    let pec: String?
    let note: String?
    let created_at: Date
    let updated_at: Date

    var displayName: String {
        switch actor_type {
        case .person:
            let n = [nome, cognome].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            return n.isEmpty ? (denominazione ?? "—") : n
        case .company, .condo:
            return denominazione ?? "—"
        }
    }

    var identifyingCode: String? {
        partita_iva ?? codice_fiscale
    }
}

struct CloudActorDetail: Codable, Identifiable {
    let id: String
    let tenant_id: String
    let actor_type: CloudActorType
    let nome: String?
    let cognome: String?
    let data_nascita: Date?
    let luogo_nascita: String?
    let sesso: String?
    let denominazione: String?
    let codice_fiscale: String?
    let partita_iva: String?
    let email: String?
    let telefono: String?
    let pec: String?
    let note: String?
    let created_at: Date
    let updated_at: Date
    let addresses: [CloudActorAddress]
    let ibans: [CloudActorIban]
    let relations_out: [CloudActorRelation]
    let relations_in: [CloudActorRelation]
}

struct CloudActorCreate: Codable {
    let actor_type: CloudActorType
    let nome: String?
    let cognome: String?
    let data_nascita: Date?
    let luogo_nascita: String?
    let sesso: String?
    let denominazione: String?
    let codice_fiscale: String?
    let partita_iva: String?
    let email: String?
    let telefono: String?
    let pec: String?
    let note: String?
    let addresses: [CloudActorAddressCreate]?
    let ibans: [CloudActorIbanCreate]?
}

struct CloudActorUpdate: Codable {
    let actor_type: CloudActorType?
    let nome: String?
    let cognome: String?
    let data_nascita: Date?
    let luogo_nascita: String?
    let sesso: String?
    let denominazione: String?
    let codice_fiscale: String?
    let partita_iva: String?
    let email: String?
    let telefono: String?
    let pec: String?
    let note: String?
}

struct CloudActorListResponse: Codable {
    let items: [CloudActorResponse]
    let total: Int
}

// MARK: - Snapshots embedded in claim

struct CloudActorAddressSnapshot: Codable, Hashable {
    let indirizzo: String?
    let civico: String?
    let cap: String?
    let citta: String?
    let provincia: String?
    let nazione: String?

    var inline: String {
        var parts: [String] = []
        if let indirizzo, !indirizzo.isEmpty {
            if let civico, !civico.isEmpty {
                parts.append("\(indirizzo), \(civico)")
            } else {
                parts.append(indirizzo)
            }
        }
        if let cap, !cap.isEmpty, let citta, !citta.isEmpty {
            parts.append("\(cap) \(citta)")
        } else if let citta, !citta.isEmpty {
            parts.append(citta)
        }
        if let provincia, !provincia.isEmpty {
            parts.append("(\(provincia))")
        }
        return parts.joined(separator: ", ")
    }
}

struct CloudActorIbanSnapshot: Codable, Hashable {
    let iban: String?
    let intestatario: String?
    let banca: String?
}

// MARK: - Claim actor input (sent on create/update)

struct CloudClaimActorInput: Codable {
    let actor_id: String?
    let actor_data: CloudActorCreate?
    let address_id: String?
    let iban_id: String?
}

// MARK: - Cross-claim indices

struct CloudActorAgencyLink: Codable, Identifiable, Hashable {
    let actor_id: String
    let agency_id: String
    let first_seen_claim_id: String?
    let last_seen_claim_id: String?
    let last_seen_at: Date
    let claim_count: Int

    var id: String { "\(actor_id)-\(agency_id)" }
}

struct CloudActorCompanyLink: Codable, Identifiable, Hashable {
    let actor_id: String
    let compagnia_id: String
    let first_seen_claim_id: String?
    let last_seen_claim_id: String?
    let last_seen_at: Date
    let claim_count: Int

    var id: String { "\(actor_id)-\(compagnia_id)" }
}
