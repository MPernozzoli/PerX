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
                NotificationCenter.default.post(name: .perxRealtimeIncomingCall, object: nil, userInfo: event.payload)
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
                        PushRegistrationService.shared.start()
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
