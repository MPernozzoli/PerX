import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif
#if canImport(PushKit)
import PushKit
#endif
import UserNotifications

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "perx", category: "PushDispatcher")

/// Cross-platform dispatcher that:
///  * requests permissions
///  * registers APNs (all platforms)
///  * registers VoIP push via PushKit (iOS/iPadOS only)
///  * forwards incoming-call payloads to the platform-specific handler
///  * sends tokens to backend via the injected `DevicePushAPI`
///
/// `incomingCallHandler` is accessed from both @MainActor callers and the
/// nonisolated PushKit delegate; it is protected by `handlerLock` so it is safe
/// to read without an async hop.
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

    // nonisolated(unsafe) + handlerLock: the nonisolated PushKit delegate reads
    // this synchronously; NSLock ensures thread safety without an async hop.
    private let handlerLock = NSLock()
    nonisolated(unsafe) private var _incomingCallHandler: ((IncomingCallPayload, @escaping () -> Void) -> Void)?

    /// Handler invoked when an incoming-call push arrives. The platform layer
    /// decides whether to drive CallKit or show a custom notification.
    public var incomingCallHandler: ((IncomingCallPayload, @escaping () -> Void) -> Void)? {
        get { handlerLock.withLock { _incomingCallHandler } }
        set { handlerLock.withLock { _incomingCallHandler = newValue } }
    }

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

    /// Call once on launch (before auth) to set up the PKPushRegistry so that
    /// cold-launch VoIP pushes can be delivered immediately.
    public func setupVoIPRegistry() {
#if canImport(PushKit) && !os(macOS)
        guard voipRegistry == nil else { return }
        registerForVoIPPushes()
#endif
    }

    /// Call after authentication to register APNs and send VoIP token to backend.
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
            catch { logger.warning("Device token unregister failed: \(error)") }
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
            logger.info("Registered \(type) token with backend (platform=\(self.platform))")
        } catch {
            logger.error("Device token register failed (\(type)): \(error)")
        }
    }

#if canImport(PushKit) && !os(macOS)
    private func registerForVoIPPushes() {
        guard voipRegistry == nil else { return }
        let registry = PKPushRegistry(queue: DispatchQueue(label: "com.perx.pushkit", qos: .userInteractive))
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.voipRegistry = registry
        logger.info("PKPushRegistry created for VoIP pushes")
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
        // Log token + bundle so we can cross-check against the APNs topic used by the backend.
        // bundle_id stored in DB must match the bundle ID this token was generated for.
        Task { @MainActor in
            logger.info("VoIP token: \(hex.prefix(8))… bundle=\(self.bundleId ?? "nil") env=\(self.environment)")
            await self.send(hex, type: "voip")
        }
    }

    nonisolated public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        logger.info("VoIP push token invalidated")
    }

    /// Apple requires reportNewIncomingCall to be called synchronously (before the
    /// completion handler is invoked) or iOS will terminate the app. We call the
    /// handler directly on the PushKit queue — no async @MainActor hop.
    nonisolated public func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        logger.info("VoIP push received, type=\(type.rawValue)")
        let call = IncomingCallPayload.parse(from: payload.dictionaryPayload)
        // Read handler without async hop — protected by handlerLock.
        if let handler = handlerLock.withLock({ _incomingCallHandler }) {
            handler(call, completion)
        } else {
            logger.warning("No incomingCallHandler set — reporting to CallKit skipped")
            completion()
        }
    }
}
#endif
