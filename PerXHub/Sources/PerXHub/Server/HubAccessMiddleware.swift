import Foundation
import Vapor

/// Controllo di accesso globale dell'Hub.
///
/// Regole:
/// - `GET /health` resta pubblico (health check di Monitor, AutoUpdater, launchd);
/// - `/internal/storage/*` è gestito dal controllo dedicato `X-PerX-Storage-Token`
///   (backend cloud → Mac mini) dentro le route;
/// - le richieste dirette da loopback (`127.0.0.1`/`::1`) senza header di proxy sono
///   ammesse: servizi locali come WA Bridge e AutoUpdater continuano a funzionare
///   senza configurazione aggiuntiva;
/// - ogni altra richiesta (LAN, VPN, tunnel/reverse proxy) deve presentare il token
///   `PERX_HUB_API_TOKEN` in `X-PerX-Hub-Token` o `Authorization: Bearer`, oppure il
///   token del bridge WhatsApp in `X-PerX-WA-Bridge-Token`.
///
/// Senza token configurato l'Hub accetta quindi solo traffico locale diretto.
struct HubAccessMiddleware: AsyncMiddleware {
    /// Header impostati da reverse proxy e tunnel: se presenti la richiesta non è
    /// davvero locale anche quando arriva da 127.0.0.1 (cloudflared, ngrok, tailscale serve).
    private static let proxyHeaders = [
        "X-Forwarded-For", "X-Forwarded-Host", "X-Real-IP", "Forwarded",
        "CF-Connecting-IP", "True-Client-IP", "Tailscale-User-Login",
    ]

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let path = request.url.path
        if path == "/health" || path.hasPrefix("/internal/storage/") {
            return try await next.respond(to: request)
        }
        if Self.isDirectLoopback(request) || Self.hasValidToken(request) {
            return try await next.respond(to: request)
        }
        request.logger.warning("[Hub] Accesso negato a \(request.method) \(path) da \(request.remoteAddress?.ipAddress ?? "sconosciuto")")
        throw Abort(.unauthorized, reason: "Hub token mancante o non valido")
    }

    static func isDirectLoopback(_ request: Request) -> Bool {
        guard let ip = request.remoteAddress?.ipAddress else { return false }
        let loopback = ip == "127.0.0.1" || ip == "::1" || ip == "::ffff:127.0.0.1"
        guard loopback else { return false }
        return !proxyHeaders.contains { request.headers.first(name: $0) != nil }
    }

    static func hasValidToken(_ request: Request) -> Bool {
        if let expected = HubConfiguration.hubAPIToken {
            let bearer = request.headers.bearerAuthorization?.token
            let header = request.headers.first(name: "X-PerX-Hub-Token")
            for candidate in [header, bearer].compactMap({ $0 }) where constantTimeEquals(candidate, expected) {
                return true
            }
        }
        if let bridgeToken = HubConfiguration.waBridgeInternalToken,
           let provided = request.headers.first(name: "X-PerX-WA-Bridge-Token"),
           constantTimeEquals(provided, bridgeToken) {
            return true
        }
        return false
    }
}

/// Confronto a tempo costante per token condivisi (evita timing attack).
func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
    let a = Array(lhs.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    let b = Array(rhs.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    var diff: UInt8 = a.count == b.count ? 0 : 1
    for index in 0..<max(a.count, b.count) {
        let x = index < a.count ? a[index] : 0
        let y = index < b.count ? b[index] : 0
        diff |= x ^ y
    }
    return diff == 0
}
