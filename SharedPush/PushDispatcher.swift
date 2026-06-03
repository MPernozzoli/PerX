import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(PushKit)
import PushKit
#endif
import UserNotifications

/// Cross-platform dispatcher that:
///  * requests permissions
///  * registers APNs (all platforms)
///  * registers VoIP push via PushKit (iOS/iPadOS only)
///  * forwards incoming-call payloads to the platform-specific handler
///  * sends tokens to backend via the injected `DevicePushAPI`
@MainActor
public final class PushDispatcher: NSObject {
    public static let shared = PushDispatcher()

    public var api: DevicePushAPI?
    public var bundleId: String?
    public var platform: String = {
#if os(macOS)
        return "macos"
#elseif targetEnvironment(macCatalyst)
        return "macos"
#else
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios"
#endif
    }()
    public var appIdentifier: String = "perx"
    public var environment: String = "production"

    /// Handler invoked when an incoming-call push arrives. The platform layer
    /// decides whether to drive CallKit or show a custom notification.
    public var incomingCallHandler: ((IncomingCallPayload, @escaping () -> Void) -> Void)?

    private lazy var store: PushTokenStore = PushTokenStore(appIdentifier: appIdentifier)

#if canImport(PushKit)
    private var voipRegistry: PKPushRegistry?
#endif

    private override init() { super.init() }

    public func configure(api: DevicePushAPI, bundleId: String?, appIdentifier: String, environment: String = "production") {
        self.api = api
        self.bundleId = bundleId
        self.appIdentifier = appIdentifier
        self.environment = environment
        self.store = PushTokenStore(appIdentifier: appIdentifier)
    }

    public func start() {
        Task { await requestAndRegisterAPNs() }
#if canImport(PushKit) && !os(macOS)
        registerForVoIPPushes()
#endif
    }

    public func didRegisterAPNs(token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        Task { await self.send(hex, type: "apns") }
    }

    public func unregisterAll() async {
        for token in store.allTokens() {
            do { try await api?.unregisterDeviceToken(token: token) }
            catch { print("Device token unregister failed: \(error)") }
        }
        store.clearAll()
    }

    // MARK: - APNs

    private func requestAndRegisterAPNs() async {
        let center = UNUserNotificationCenter.current()
        let opts: UNAuthorizationOptions = [.alert, .sound, .badge]
        let granted = (try? await center.requestAuthorization(options: opts)) ?? false
        guard granted else { return }
#if canImport(UIKit)
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
#elseif canImport(AppKit)
        await MainActor.run {
            NSApplication.shared.registerForRemoteNotifications()
        }
#endif
    }

    private func send(_ token: String, type: String) async {
        guard let api else { return }
        do {
            try await api.registerDeviceToken(
                token: token,
                tokenType: type,
                platform: platform,
                bundleId: bundleId,
                environment: environment,
                app: appIdentifier
            )
            store.save(token, type: type)
        } catch {
            print("Device token register failed (\(type)): \(error)")
        }
    }

#if canImport(PushKit) && !os(macOS)
    private func registerForVoIPPushes() {
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.voipRegistry = registry
    }
#endif
}

#if canImport(AppKit)
import AppKit
#endif

#if canImport(PushKit) && !os(macOS)
extension PushDispatcher: PKPushRegistryDelegate {
    nonisolated public func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let hex = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await self.send(hex, type: "voip") }
    }

    nonisolated public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {}

    nonisolated public func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        let call = IncomingCallPayload.parse(from: payload.dictionaryPayload)
        Task { @MainActor in
            if let handler = self.incomingCallHandler {
                handler(call, completion)
            } else {
                completion()
            }
        }
    }
}
#endif
