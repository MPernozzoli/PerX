import SwiftUI

@main
struct PerX_LiteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegateAdapter.self) var appDelegate
    @StateObject private var auth = AuthStore()

    init() {
        RealtimeService.shared.onEvent = { event in
            switch event.type {
            case "task_updated":
                NotificationCenter.default.post(name: .perxRealtimeTaskUpdated, object: nil, userInfo: event.payload)
            case "claim_updated":
                NotificationCenter.default.post(name: .perxRealtimeClaimUpdated, object: nil, userInfo: event.payload)
            case "incoming_call":
                // Trigger the CallKit UI via CallProvider, then also reload the list
                let payload = IncomingCallPayload.parse(from: event.payload)
                CallProviderShared.shared.reportIncomingCall(payload) { _ in }
                NotificationCenter.default.post(name: .perxRealtimeIncomingCall, object: nil, userInfo: event.payload)
            case "chat_message":
                NotificationCenter.default.post(name: .perxRealtimeChatMessage, object: nil, userInfo: event.payload)
            default:
                break
            }
        }

        PushDispatcher.shared.configure(
            api: LitePushAPI.shared,
            bundleId: Bundle.main.bundleIdentifier,
            appIdentifier: "perx_lite",
            environment: "production"
        )
        CallSessionShared.shared.api = LitePushAPI.shared
        PushDispatcher.shared.incomingCallHandler = { payload, completion in
            CallProviderShared.shared.reportIncomingCall(payload) { _ in completion() }
        }
        CallProviderShared.shared.onAnswer = { sessionId in
            await CallSessionShared.shared.connect(toSessionId: sessionId)
        }
        CallProviderShared.shared.onEnd = { _ in
            await CallSessionShared.shared.endActive()
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
