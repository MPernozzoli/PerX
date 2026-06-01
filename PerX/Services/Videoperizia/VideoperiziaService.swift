import Foundation

/// Wrapper sui 4 endpoint backend del flusso videoperizia perito-side.
/// Tutte le chiamate passano dal cloud Hub client, che gestisce auth bearer,
/// refresh token e baseURL.
@MainActor
final class VideoperiziaService {
    static let shared = VideoperiziaService()

    private let hub: HubAPIAdapterClient

    private init(hub: HubAPIAdapterClient = .shared) {
        self.hub = hub
    }

    /// Crea (o restituisce, idempotente) la sessione videoperizia per un sinistro
    /// già in stato `videoperizia`.
    func createOrFetchSession(claimId: String) async throws -> VideoperiziaSessionDTO {
        let response: VideoperiziaSessionCreateResponseDTO = try await hub.cloudPost(
            "/api/v1/claims/\(claimId)/videoperizia/session",
            body: EmptyBody()
        )
        return response.session
    }

    /// Snapshot della sessione (polling lato perito mentre aspetta che
    /// l'assicurato entri in lobby).
    func fetchSession(claimId: String, sessionId: String) async throws -> VideoperiziaSessionDTO {
        return try await hub.cloudGet("/api/v1/claims/\(claimId)/videoperizia/session/\(sessionId)")
    }

    /// Perito preme "Avvia". Backend setta stato=live e abilita publish per l'assicurato.
    func start(claimId: String, sessionId: String) async throws -> VideoperiziaSessionDTO {
        return try await hub.cloudPost(
            "/api/v1/claims/\(claimId)/videoperizia/session/\(sessionId)/start",
            body: EmptyBody()
        )
    }

    /// Perito preme "Termina". Backend chiude sessione e transiziona il claim
    /// a DA_GESTIRE_VIDEO.
    func end(claimId: String, sessionId: String, reason: String? = nil) async throws -> VideoperiziaSessionDTO {
        return try await hub.cloudPost(
            "/api/v1/claims/\(claimId)/videoperizia/session/\(sessionId)/end",
            body: VideoperiziaSessionEndRequestDTO(reason: reason)
        )
    }

    /// Token LiveKit per il perito. Grant: subscribe + publish + data sempre.
    func mintPeritoToken(claimId: String, sessionId: String) async throws -> VideoperiziaTokenDTO {
        return try await hub.cloudPost(
            "/api/v1/claims/\(claimId)/videoperizia/session/\(sessionId)/token",
            body: EmptyBody()
        )
    }

    /// Galleria foto/clip per la sessione.
    func listMedia(claimId: String, sessionId: String) async throws -> [VideoperiziaMediaDTO] {
        let response: VideoperiziaMediaListDTO = try await hub.cloudGet(
            "/api/v1/claims/\(claimId)/videoperizia/session/\(sessionId)/media"
        )
        return response.items
    }

    /// Timeline GPS dell'assicurato durante la sessione.
    func listLocationPings(claimId: String, sessionId: String) async throws -> [VideoperiziaLocationPingDTO] {
        let response: VideoperiziaLocationPingListDTO = try await hub.cloudGet(
            "/api/v1/claims/\(claimId)/videoperizia/session/\(sessionId)/location-pings"
        )
        return response.items
    }
}

/// Body vuoto codable per POST che non hanno payload.
private struct EmptyBody: Encodable {}
