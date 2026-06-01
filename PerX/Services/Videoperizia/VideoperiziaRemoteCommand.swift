import Foundation

/// Protocollo dei messaggi peer-to-peer scambiati tra perito e assicurato sul
/// LiveKit data channel. Encoded come UTF-8 JSON così entrambi i client
/// (portale Web + app iOS) parlano la stessa lingua.
///
/// Convenzioni:
///   - `type`     stringa discriminator
///   - `payload`  opzionale, struttura tipo-specifica
///
/// Quando aggiungerai il package LiveKit, sostituisci lo `stub_send` con
/// `room.localParticipant.publishData(data:reliable:topic:)`.
enum VideoperiziaRemoteCommand: Equatable {
    /// Perito chiede all'assicurato di cambiare camera (frontale ↔ posteriore).
    case cameraFlip

    /// Perito chiede di accendere/spegnere la torcia/flash. Sui dispositivi
    /// dove il torch non è controllabile via API (iOS Safari), il portale
    /// mostra all'assicurato un alert "guida vocale" per farlo manualmente.
    case flashRequest(turnOn: Bool)

    /// Perito segnala "sto per scattare una foto", così l'assicurato sa di
    /// tenere fermo per un attimo.
    case captureNotice

    var type: String {
        switch self {
        case .cameraFlip:     return "camera_flip"
        case .flashRequest:   return "flash_request"
        case .captureNotice:  return "capture_notice"
        }
    }

    func encode() throws -> Data {
        var dict: [String: Any] = ["type": type, "v": 1]
        switch self {
        case .flashRequest(let on):
            dict["payload"] = ["turn_on": on]
        case .cameraFlip, .captureNotice:
            break
        }
        return try JSONSerialization.data(withJSONObject: dict, options: [])
    }
}
