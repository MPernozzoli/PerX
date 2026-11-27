import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var capabilities: [String: Bool] = [:]

    private var showCalls: Bool { capabilities.isEmpty || capabilities["chiamate_perx"] == true }
    private var showSchedule: Bool { capabilities.isEmpty || capabilities["programmazione_rete"] == true }
    private var showCatRoutes: Bool { auth.isCATUser && (capabilities.isEmpty || capabilities["cat_dispatcher"] == true) }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ActiveCallBanner()
                TabView {
                    if showCalls {
                        CommunicationsView()
                            .tabItem { Label("Comunicazioni", systemImage: "phone.fill") }
                    }

                    CalendarView()
                        .tabItem { Label("Calendario", systemImage: "calendar") }

                    if showSchedule {
                        ScheduleView()
                            .tabItem { Label("Programmazione", systemImage: "clock.fill") }
                    }

                    if showCatRoutes {
                        CATRoutesView()
                            .tabItem { Label("Route CAT", systemImage: "map.fill") }
                    }

                    ProfileView()
                        .tabItem { Label("Profilo", systemImage: "person.crop.circle") }
                }
            }

            // Incoming call banner — slides in from top over any tab, never modal
            IncomingCallBanner()
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: IncomingCallBannerState.shared.pendingCall?.sessionId)
                .zIndex(100)
        }
        .task {
            struct Payload: Decodable { let capabilities: [String: Bool] }
            if let payload: Payload = try? await APIClient.shared.get("/api/v1/regia/profilo") {
                capabilities = payload.capabilities
            }
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var realtime = RealtimeService.shared
    @AppStorage("liteNavigationApp") private var navAppRaw: String = NavigationApp.apple.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Email", value: auth.email ?? "—")
                    if let name = auth.displayName, !name.isEmpty {
                        LabeledContent("Nome", value: name)
                    }
                    if let ext = auth.myExtension, !ext.isEmpty {
                        LabeledContent("Interno PerX") {
                            HStack(spacing: 6) {
                                Text(ext)
                                    .font(.body.monospaced().weight(.semibold))
                                if !auth.myExtensionEnabled {
                                    Text("non attivo")
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.18), in: Capsule())
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    LabeledContent("Server", value: APIClient.shared.baseURL)
                }

                if auth.isCATUser {
                    Section {
                        Picker("App di navigazione", selection: $navAppRaw) {
                            ForEach(NavigationApp.allCases, id: \.rawValue) { app in
                                Text(app.displayName).tag(app.rawValue)
                            }
                        }
                    } header: {
                        Text("Navigazione")
                    } footer: {
                        Text("L'app scelta si apre quando premi \"Avvia navigazione\" nel navigatore route.")
                    }
                }

                Section("Stato realtime") {
                    HStack {
                        Circle()
                            .fill(realtime.isConnected ? .green : .gray)
                            .frame(width: 10, height: 10)
                        Text(realtime.isConnected ? "Connesso" : "Disconnesso")
                    }
                }
                Section {
                    Button(role: .destructive) {
                        Task { await auth.logout() }
                    } label: {
                        Label("Esci", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profilo")
        }
    }
}
