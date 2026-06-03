import Foundation

/// PerX (macOS) implementation of DevicePushAPI, wrapping HubAPIAdapterClient.
@MainActor
final class MacPushAPI: DevicePushAPI {
    static let shared = MacPushAPI()

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
    private struct LiveKitTokenResponseDTO: Decodable {
        let token: String
        let livekit_url: String
        let room_name: String
    }
    private struct ActionBody: Encodable { let action_type: String }
    private struct ActionResponse: Decodable { let session_id: String? }

    func registerDeviceToken(
        token: String, tokenType: String, platform: String,
        bundleId: String?, environment: String, app: String
    ) async throws {
        let body = RegisterBody(
            token: token, token_type: tokenType, platform: platform,
            bundle_id: bundleId, environment: environment, app: app
        )
        let _: RegisterResponse = try await HubAPIAdapterClient.shared.cloudPost(
            "/api/v1/devices/register", body: body
        )
    }

    func unregisterDeviceToken(token: String) async throws {
        try await HubAPIAdapterClient.shared.cloudDelete("/api/v1/devices/\(token)")
    }

    func mintLiveKitToken(sessionId: String) async throws -> PushLiveKitToken? {
        let resp: LiveKitTokenResponseDTO = try await HubAPIAdapterClient.shared.cloudPost(
            "/api/v1/communications/sessions/\(sessionId)/livekit-token",
            body: EmptyBody()
        )
        return PushLiveKitToken(token: resp.token, url: resp.livekit_url, roomName: resp.room_name)
    }

    func acknowledgeSessionAction(sessionId: String, actionType: String) async throws {
        let _: ActionResponse = try await HubAPIAdapterClient.shared.cloudPost(
            "/api/v1/communications/sessions/\(sessionId)/actions",
            body: ActionBody(action_type: actionType)
        )
    }
}
