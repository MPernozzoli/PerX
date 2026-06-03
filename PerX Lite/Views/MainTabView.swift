import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        VStack(spacing: 0) {
            ActiveCallBanner()
            TabView {
                CommunicationsView()
                    .tabItem { Label("Comunicazioni", systemImage: "phone.fill") }

                CalendarView()
                    .tabItem { Label("Calendario", systemImage: "calendar") }

                ScheduleView()
                    .tabItem { Label("Programmazione", systemImage: "clock.fill") }

                ProfileView()
                    .tabItem { Label("Profilo", systemImage: "person.crop.circle") }
            }
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var realtime = RealtimeService.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Email", value: auth.email ?? "—")
                    LabeledContent("Server", value: APIClient.shared.baseURL)
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
