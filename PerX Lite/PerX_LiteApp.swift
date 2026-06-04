import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "perx", category: "App")

@main
struct PerX_LiteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegateAdapter.self) var appDelegate
    @StateObject private var auth = AuthStore()

    init() {
        // Wire up CallKit handler BEFORE configure() so it is available
        // when the PKPushRegistry (created in AppDelegateAdapter) delivers
        // a pending cold-launch VoIP push.
        CallSessionShared.shared.api = LitePushAPI.shared
        PushDispatcher.shared.incomingCallHandler = { payload, completion in
            // Called on PushKit's serial queue — CallProviderShared is thread-safe.
            CallProviderShared.shared.reportIncomingCall(payload) { error in
                if let error {
                    logger.error("CallKit reportIncomingCall failed: \(error.localizedDescription)")
                }
                completion()
            }
            // Validate that the session is still active on the backend.
            // VoIP pushes can be queued by APNs while the device is offline and
            // delivered late — after the call has already ended. If that's the case,
            // immediately dismiss the CallKit UI we just reported.
            let sessionId = payload.sessionId
            Task { @MainActor in
                struct IncomingResp: Decodable {
                    struct Item: Decodable { let session_id: String }
                    let items: [Item]
                }
                let isActive: Bool
                do {
                    let resp: IncomingResp = try await APIClient.shared.get("/api/v1/communications/incoming")
                    isActive = resp.items.contains { $0.session_id == sessionId }
                } catch {
                    isActive = true // network error — be optimistic and let CallKit handle it
                }
                if !isActive {
                    logger.info("Stale VoIP push for session \(sessionId) — terminating CallKit call")
                    CallProviderShared.shared.endCall(forSession: sessionId)
                }
            }
        }
        CallProviderShared.shared.onAnswer = { sessionId in
            await CallSessionShared.shared.connect(toSessionId: sessionId)
        }
        CallProviderShared.shared.onEnd = { _ in
            await CallSessionShared.shared.endActive()
        }

        PushDispatcher.shared.configure(
            api: LitePushAPI.shared,
            bundleId: Bundle.main.bundleIdentifier,
            appIdentifier: "perx_lite",
            environment: "production"
        )

        RealtimeService.shared.onEvent = { event in
            switch event.type {
            case "task_updated":
                NotificationCenter.default.post(name: .perxRealtimeTaskUpdated, object: nil, userInfo: event.payload)
            case "claim_updated":
                NotificationCenter.default.post(name: .perxRealtimeClaimUpdated, object: nil, userInfo: event.payload)
            case "incoming_call":
                // SSE path — app is in foreground. Show the custom in-app banner
                // instead of CallKit (which would show a system modal/fullscreen).
                // VoIP push (background/locked) is handled separately via CallKit.
                let payload = IncomingCallPayload.parse(from: event.payload)
                IncomingCallBannerState.shared.show(payload)
                NotificationCenter.default.post(name: .perxRealtimeIncomingCall, object: nil, userInfo: event.payload)
            case "call_ended":
                // The caller ended the call (or the backend expired it).
                // Dismiss any in-app banner and close the CallKit UI if present.
                let endedSessionId = (event.payload["session_id"] as? String) ?? ""
                IncomingCallBannerState.shared.dismiss()
                if !endedSessionId.isEmpty {
                    CallProviderShared.shared.endCall(forSession: endedSessionId)
                }
                NotificationCenter.default.post(name: .perxRealtimeCallEnded, object: nil, userInfo: event.payload)
            case "chat_message":
                NotificationCenter.default.post(name: .perxRealtimeChatMessage, object: nil, userInfo: event.payload)
            default:
                break
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .onChange(of: auth.isAuthenticated, initial: true) { _, authed in
                    if authed {
                        RealtimeService.shared.start()
                        PushDispatcher.shared.start()
                    } else {
                        RealtimeService.shared.stop()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        if auth.isAuthenticated {
            MainTabView()
        } else {
            LoginView()
        }
    }
}
