import Foundation

/// Abstraction over the authenticated HTTP client used by a target.
/// Each target (PerX Lite, PerX per iPad, PerX Mac) provides its own
/// implementation that talks to /api/v1/devices/*.
public protocol DevicePushAPI {
    func registerDeviceToken(
        token: String,
        tokenType: String,        // "apns" | "voip"
        platform: String,         // "ios" | "ipados" | "macos"
        bundleId: String?,
        environment: String,      // "production" | "sandbox"
        app: String               // e.g. "perx_lite", "perx_ipad", "perx_mac"
    ) async throws

    func unregisterDeviceToken(token: String) async throws

    /// Optional: request a LiveKit token for an incoming/outgoing session.
    /// Targets that don't support voice calling can return nil.
    func mintLiveKitToken(sessionId: String) async throws -> PushLiveKitToken?

    /// Acknowledge to backend that a call session was answered/ended/etc.
    func acknowledgeSessionAction(sessionId: String, actionType: String) async throws
}

public struct PushLiveKitToken {
    public let token: String
    public let url: String
    public let roomName: String

    public init(token: String, url: String, roomName: String) {
        self.token = token
        self.url = url
        self.roomName = roomName
    }
}

public struct IncomingCallPayload {
    public let sessionId: String
    public let callerName: String
    public let callerHandle: String
    public let hasVideo: Bool
    public let claimId: String?

    public init(sessionId: String, callerName: String, callerHandle: String, hasVideo: Bool, claimId: String? = nil) {
        self.sessionId = sessionId
        self.callerName = callerName
        self.callerHandle = callerHandle
        self.hasVideo = hasVideo
        self.claimId = claimId
    }

    public static func parse(from dict: [AnyHashable: Any]) -> IncomingCallPayload {
        IncomingCallPayload(
            sessionId: (dict["session_id"] as? String) ?? UUID().uuidString,
            callerName: (dict["caller_name"] as? String) ?? "Chiamata in arrivo",
            callerHandle: (dict["caller_handle"] as? String) ?? "",
            hasVideo: (dict["has_video"] as? Bool) ?? false,
            claimId: dict["claim_id"] as? String
        )
    }
}
