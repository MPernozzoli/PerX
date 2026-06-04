import Foundation

/// Snapshot della sessione di videoperizia restituita dal backend.
/// Allineata a `VideoperiziaSessionResponse` (backend/app/schemas/videoperizia.py).
struct VideoperiziaSessionDTO: Codable, Identifiable {
    let id: String
    let claim_id: String
    let livekit_room_name: String
    let state: String          // scheduled | lobby_open | live | ended | aborted
    let lobby_joined_at: Date?
    let started_at: Date?
    let ended_at: Date?
    let perito_user_id: String?
    /// Non-nil when the insured has left mid-call (portal /leave or LiveKit event).
    let insured_disconnected_at: Date?
    let created_at: Date
    let updated_at: Date

    var isLive: Bool { state == "live" }
    var isLobbyOpen: Bool { state == "lobby_open" }
    var isClosed: Bool { state == "ended" || state == "aborted" }
    var insuredHasLeft: Bool { insured_disconnected_at != nil }
}

struct VideoperiziaSessionCreateResponseDTO: Codable {
    let session: VideoperiziaSessionDTO
}

/// Token LiveKit firmato dal backend. Il client iOS non firma mai i token in
/// locale: il secret non deve mai lasciare il server.
struct VideoperiziaTokenDTO: Codable {
    let token: String
    let livekit_url: String
    let room_name: String
    let identity: String
    let expires_at: Date
    let can_publish: Bool
    let can_subscribe: Bool
    let session: VideoperiziaSessionDTO
}

struct VideoperiziaSessionEndRequestDTO: Codable {
    let reason: String?
}

/// Risposta da POST …/session/{id}/end.
/// Quando `needs_outcome_confirmation` è true il claim NON è ancora transitato:
/// il perito deve scegliere un outcome tramite `submitOutcome()`.
struct VideoperiziaEndResponseDTO: Codable {
    let session: VideoperiziaSessionDTO
    let needs_outcome_confirmation: Bool
    let frame_count: Int
}

enum VideoperiziaOutcome: String, CaseIterable {
    case confirmed             = "confirmed"
    case rescheduleVideo       = "reschedule_video"
    case escalateSopralluogo   = "escalate_sopralluogo"

    var label: String {
        switch self {
        case .confirmed:           return "Sì, perizia completata"
        case .rescheduleVideo:     return "No, riprogramma videoperizia"
        case .escalateSopralluogo: return "No, sopralluogo fisico"
        }
    }
}

struct VideoperiziaOutcomeRequestDTO: Codable {
    let outcome: String
}

// MARK: - Media

struct VideoperiziaMediaDTO: Codable, Identifiable {
    let id: String
    let session_id: String
    let claim_id: String
    let kind: String            // "frame" | "clip"
    let storage_path: String
    let mime_type: String?
    let captured_at: Date
    let captured_by_user_id: String?
    let processing_status: String
    let hub_result_json: [String: AnyCodable]?
    let signed_url: String?

    var isClip: Bool { kind == "clip" }
}

struct VideoperiziaMediaListDTO: Codable {
    let items: [VideoperiziaMediaDTO]
}

// MARK: - Location pings

struct VideoperiziaLocationPingDTO: Codable, Identifiable {
    let id: String
    let session_id: String
    let recorded_at: Date
    let latitude: Double
    let longitude: Double
    let accuracy_m: Double?
    let altitude_m: Double?
    let speed_mps: Double?
    let heading_deg: Double?
    let source: String
}

struct VideoperiziaLocationPingListDTO: Codable {
    let items: [VideoperiziaLocationPingDTO]
}

// `AnyCodable` è definito in PerX/Utils/AnyCodable.swift — usato qui per
// decodificare `hub_result_json` la cui shape è opaca lato perxHUB.
