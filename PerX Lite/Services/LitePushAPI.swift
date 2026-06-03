import Foundation

/// PerX Lite-specific implementation of DevicePushAPI, wrapping APIClient.
final class LitePushAPI: DevicePushAPI {
    static let shared = LitePushAPI()

    private struct RegisterBody: Encodable {
        let token: String
        let token_type: String
        let platform: String
        let bundle_id: String?
        let environment: String
        let app: String
    }
    private struct RegisterResponse: Decodable { let id: String }
    private struct EmptyBody: Encodable {}

    @MainActor
    func registerDeviceToken(
        token: String, tokenType: String, platform: String,
        bundleId: String?, environment: String, app: String
    ) async throws {
        let body = RegisterBody(
            token: token, token_type: tokenType, platform: platform,
            bundle_id: bundleId, environment: environment, app: app
        )
        let _: RegisterResponse = try await APIClient.shared.post(
            "/api/v1/devices/register", body: body
        )
    }

    @MainActor
    func unregisterDeviceToken(token: String) async throws {
        try await APIClient.shared.delete("/api/v1/devices/\(token)")
    }

    @MainActor
    func mintLiveKitToken(sessionId: String) async throws -> PushLiveKitToken? {
        let resp: LiveKitTokenDTO = try await APIClient.shared.post(
            "/api/v1/communications/sessions/\(sessionId)/livekit-token",
            body: EmptyBody()
        )
        return PushLiveKitToken(token: resp.token, url: resp.livekit_url, roomName: resp.room_name)
    }

    @MainActor
    func acknowledgeSessionAction(sessionId: String, actionType: String) async throws {
        struct Resp: Decodable { let session_id: String? }
        let body = CallSessionAction(action_type: actionType)
        let _: Resp = try await APIClient.shared.post(
            "/api/v1/communications/sessions/\(sessionId)/actions",
            body: body
        )
    }
}
