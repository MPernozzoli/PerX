import Foundation
import UIKit
import PushKit
import UserNotifications

@MainActor
final class PushRegistrationService: NSObject {
    static let shared = PushRegistrationService()

    private var voipRegistry: PKPushRegistry?

    private override init() { super.init() }

    func start() {
        Task { await registerForAPNs() }
        registerForVoIPPushes()
    }

    // MARK: - APNs (standard)

    private func registerForAPNs() async {
        let center = UNUserNotificationCenter.current()
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            granted = false
        }
        guard granted else { return }
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func didRegisterAPNs(token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        Task { await sendTokenToServer(hex, type: "apns") }
    }

    // MARK: - PushKit (VoIP)

    private func registerForVoIPPushes() {
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.voipRegistry = registry
    }

    // MARK: - Backend registration

    private func sendTokenToServer(_ token: String, type: String) async {
        struct Body: Encodable {
            let token: String
            let token_type: String
            let platform: String
            let bundle_id: String?
            let environment: String
            let app: String
        }
        struct Response: Decodable { let id: String }

        let bundle = Bundle.main.bundleIdentifier
        let body = Body(
            token: token,
            token_type: type,
            platform: "ios",
            bundle_id: bundle,
            environment: "production",
            app: "perx_lite"
        )
        do {
            let _: Response = try await APIClient.shared.post("/api/v1/devices/register", body: body)
        } catch {
            print("Device token register failed (\(type)): \(error)")
        }
    }
}

extension PushRegistrationService: PKPushRegistryDelegate {
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let hex = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            await self.sendTokenToServer(hex, type: "voip")
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        // Token invalidated by system. Re-registration is automatic on next launch.
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        // MUST report a call to CallKit synchronously before this method returns,
        // otherwise iOS will terminate the app and may block future VoIP pushes.
        let dict = payload.dictionaryPayload
        let sessionId = (dict["session_id"] as? String) ?? UUID().uuidString
        let callerName = (dict["caller_name"] as? String) ?? "Chiamata in arrivo"
        let callerHandle = (dict["caller_handle"] as? String) ?? ""
        let hasVideo = (dict["has_video"] as? Bool) ?? false

        Task { @MainActor in
            CallProvider.shared.reportIncomingCall(
                sessionId: sessionId,
                callerName: callerName,
                callerHandle: callerHandle,
                hasVideo: hasVideo
            ) { _ in
                completion()
            }
        }
    }
}
