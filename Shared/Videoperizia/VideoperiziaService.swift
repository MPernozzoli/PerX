import Foundation

/// Protocollo astratto del transport HTTP usato dal `VideoperiziaService`.
/// Ogni piattaforma fornisce la sua implementazione conformandolo sul proprio
/// HTTP client esistente:
///   - macOS PerX:  `HubAPIAdapterClient`
///   - iPad PerX:   `HubAPIClient`
///
/// Questo evita di duplicare auth/refresh/encoding logic e lascia il service
/// neutrale rispetto alla piattaforma.
public protocol VideoperiziaTransport: Sendable {
    func videoperiziaGet<T: Decodable>(_ path: String) async throws -> T
    func videoperiziaPostEmpty<T: Decodable>(_ path: String) async throws -> T
    func videoperiziaPost<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T
    func videoperiziaPostMultipart<T: Decodable>(
        _ path: String,
        fileData: Data,
        fileFieldName: String,
        fileName: String,
        mimeType: String,
        fields: [String: String]
    ) async throws -> T
}

/// Wrapper sugli endpoint backend del flusso videoperizia perito-side.
/// Cross-platform: l'iniezione del `transport` permette di riusarlo sia su
/// macOS sia su iPad senza forkare il file.
@MainActor
final class VideoperiziaService {
    /// Singleton di default. Le piattaforme registrano il transport corretto
    /// allo startup tramite `VideoperiziaService.configure(transport:)`.
    static let shared = VideoperiziaService()

    /// Transport corrente. Nil se non ancora configurato — in quel caso ogni
    /// chiamata fallisce con `VideoperiziaServiceError.notConfigured`.
    private var transport: VideoperiziaTransport?

    private init() {}

    static func configure(transport: VideoperiziaTransport) {
        shared.transport = transport
    }

    private func requireTransport() throws -> VideoperiziaTransport {
        guard let transport else { throw VideoperiziaServiceError.notConfigured }
        return transport
    }

    /// Crea (o restituisce, idempotente) la sessione videoperizia per un sinistro
    /// già in stato `videoperizia`.
    func createOrFetchSession(claimId: String) async throws -> VideoperiziaSessionDTO {
        let response: VideoperiziaSessionCreateResponseDTO = try await requireTransport()
            .videoperiziaPostEmpty("/api/v1/claims/\(claimId)/videoperizia/session")
        return response.session
    }

    /// Snapshot della sessione (polling lato perito mentre aspetta che
    /// l'assicurato entri in lobby).
    func fetchSession(claimId: String, sessionId: String) async throws -> VideoperiziaSessionDTO {
        return try await requireTransport()
            .videoperiziaGet("/api/v1/claims/\(claimId)/videoperizia/session/\(sessionId)")
    }

    /// Perito preme "Avvia". Backend setta stato=live e abilita publish per l'assicurato.
    func start(claimId: String, sessionId: String) async throws -> VideoperiziaSessionDTO {
        return try await requireTransport()
            .videoperiziaPostEmpty("/api/v1/claims/\(claimId)/videoperizia/session/\(sessionId)/start")
    }

    /// Perito preme "Termina". Chiude la sessione LiveKit e restituisce la
    /// risposta completa con `needs_outcome_confirmation` e `frame_count`.
    /// Se `needs_outcome_confirmation == true` il caller deve presentare il
    /// dialog di scelta e poi chiamare `submitOutcome()`.
    func end(claimId: String, sessionId: String, reason: String? = nil) async throws -> VideoperiziaEndResponseDTO {
        return try await requireTransport().videoperiziaPost(
            "/api/v1/claims/\(claimId)/videoperizia/session/\(sessionId)/end",
            body: VideoperiziaSessionEndRequestDTO(reason: reason)
        )
    }

    /// Invia la scelta manuale del perito dopo una sessione con poche prove.
    /// Chiamato solo quando `end()` ha restituito `needs_outcome_confirmation = true`.
    func submitOutcome(
        claimId: String,
        sessionId: String,
        outcome: VideoperiziaOutcome
    ) async throws -> VideoperiziaSessionDTO {
        return try await requireTransport().videoperiziaPost(
            "/api/v1/claims/\(claimId)/videoperizia/session/\(sessionId)/outcome",
            body: VideoperiziaOutcomeRequestDTO(outcome: outcome.rawValue)
        )
    }

    /// Token LiveKit per il perito. Grant: subscribe + publish + data sempre.
    func mintPeritoToken(claimId: String, sessionId: String) async throws -> VideoperiziaTokenDTO {
        return try await requireTransport()
            .videoperiziaPostEmpty("/api/v1/claims/\(claimId)/videoperizia/session/\(sessionId)/token")
    }

    /// Galleria foto/clip per la sessione.
    func listMedia(claimId: String, sessionId: String) async throws -> [VideoperiziaMediaDTO] {
        let response: VideoperiziaMediaListDTO = try await requireTransport()
            .videoperiziaGet("/api/v1/claims/\(claimId)/videoperizia/session/\(sessionId)/media")
        return response.items
    }

    /// Upload di un frame catturato o di una clip alla sessione videoperizia.
    /// Il backend crea il record `videoperizia_media`, sale su Supabase Storage,
    /// e accoda il `ProcessJob` per il perxHUB. Ritorna il media appena creato.
    func uploadMedia(
        claimId: String,
        sessionId: String,
        kind: String,
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> VideoperiziaMediaDTO {
        return try await requireTransport().videoperiziaPostMultipart(
            "/api/v1/claims/\(claimId)/videoperizia/session/\(sessionId)/media",
            fileData: data,
            fileFieldName: "file",
            fileName: fileName,
            mimeType: mimeType,
            fields: ["kind": kind]
        )
    }

    /// Timeline GPS dell'assicurato durante la sessione.
    func listLocationPings(claimId: String, sessionId: String) async throws -> [VideoperiziaLocationPingDTO] {
        let response: VideoperiziaLocationPingListDTO = try await requireTransport()
            .videoperiziaGet("/api/v1/claims/\(claimId)/videoperizia/session/\(sessionId)/location-pings")
        return response.items
    }
}

enum VideoperiziaServiceError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Videoperizia: transport HTTP non configurato per questa build."
        }
    }
}
