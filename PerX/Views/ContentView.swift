import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @ObservedObject private var activity = UIActivity.shared
    @ObservedObject private var workSchedule = WorkScheduleManager.shared
    @State private var selection: String? = "dashboard"
    @State private var displayed: String? = "dashboard"
    @State private var isSidebarVisible = true
    @State private var studio = TenantMailSettingsService.shared.settings.studioAccess
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebar
                    .frame(width: 220)
                Divider()
            }
            selectedPage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .environment(\.managedObjectContext, viewContext)
        }
        .overlay(alignment: .topTrailing) {
            if let label = activity.label {
                GearCaption(text: label)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: isSidebarVisible ? "sidebar.leading" : "sidebar.trailing")
                }
                .help(isSidebarVisible ? "Nascondi sidebar" : "Mostra sidebar")
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .onChange(of: selection) { newValue in
            guard let newValue else { return }
            if appState.selectedView != newValue {
                appState.selectedView = newValue
            }
            guard displayed != newValue else { return }
            displayed = nil
            Task { @MainActor in
                await Task.yield()
                guard selection == newValue else { return }
                displayed = newValue
            }
        }
        .onChange(of: appState.selectedView) { newView in
            if selection != newView {
                selection = newView
            }
        }
        .onAppear {
            studio = TenantMailSettingsService.shared.settings.studioAccess
        }
        .onReceive(NotificationCenter.default.publisher(for: .tenantSettingsChanged)) { _ in
            studio = TenantMailSettingsService.shared.settings.studioAccess
            if selection == "sala-regia" && !studio.salaRegia { selection = "dashboard" }
            if selection == "comunicazioni" && !studio.posta { selection = "dashboard" }
            if (selection == "team" || selection == "studio") && !studio.studioCondiviso { selection = "dashboard" }
            if selection == "consuntivo" && !studio.consuntivo { selection = "dashboard" }
        }
        // Intercetta i tasti freccia quando la tab Cartella è attiva per bloccare la sidebar
        .onKeyPress(.leftArrow) {
            if isCartellaTabActive {
                NotificationCenter.default.post(name: NSNotification.Name("CartellaViewKeyPress"), object: nil, userInfo: ["key": "leftArrow"])
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if isCartellaTabActive {
                NotificationCenter.default.post(name: NSNotification.Name("CartellaViewKeyPress"), object: nil, userInfo: ["key": "rightArrow"])
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.upArrow) {
            if isCartellaTabActive {
                NotificationCenter.default.post(name: NSNotification.Name("CartellaViewKeyPress"), object: nil, userInfo: ["key": "upArrow"])
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.downArrow) {
            if isCartellaTabActive {
                NotificationCenter.default.post(name: NSNotification.Name("CartellaViewKeyPress"), object: nil, userInfo: ["key": "downArrow"])
                return .handled
            }
            return .ignored
        }
        .environmentObject(appState)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Label("Dashboard", systemImage: "gauge")
                    .tag("dashboard")

                if studio.salaRegia {
                    Label("Sala regia", systemImage: "sparkles.rectangle.stack")
                        .tag("sala-regia")
                }

                Label("Sinistri", systemImage: "folder")
                    .tag("sinistri")

                if studio.posta {
                    Label("Comunicazioni", systemImage: "envelope")
                        .tag("comunicazioni")
                }

                if studio.studioCondiviso {
                    Label("Team", systemImage: "person.3")
                        .tag("team")

                    Label("Studio", systemImage: "building.2")
                        .tag("studio")
                }

                if studio.consuntivo {
                    Label("Consuntivo", systemImage: "chart.bar")
                        .tag("consuntivo")
                }

                Label("Programmazione", systemImage: "calendar.badge.clock")
                    .tag("programmazione")
            }
            .listStyle(.sidebar)

            Spacer()

            List(selection: $selection) {
                Label("Impostazioni", systemImage: "gear")
                    .tag("impostazioni")
            }
            .listStyle(.sidebar)
            .frame(height: 45)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch displayed {
        case nil:
            VStack(alignment: .leading, spacing: 14) {
                GearCaption(text: "Apro la sezione")
                SkeletonBlock(height: 28)
                SkeletonCard()
                SkeletonBlock()
                SkeletonBlock()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        default:
            mountedPage
        }
    }

    @ViewBuilder
    private var mountedPage: some View {
        switch displayed {
        case "sala-regia":
            SalaRegiaView()
        case "sinistri":
            SinistriView()
        case "comunicazioni":
            ComunicazioniView()
        case "team":
            TeamMonitorView()
        case "studio":
            StudioMonitorView()
        case "consuntivo":
            ConsuntivoView { sinistro in
                appState.openSinistro(sinistro)
                selection = "sinistri"
            }
            .environmentObject(workSchedule)
        case "programmazione":
            WorkScheduleView()
        case "impostazioni":
            SettingsView()
                .environmentObject(appState)
        default:
            DashboardView()
        }
    }
    
    private func toggleSidebar() {
        isSidebarVisible.toggle()
    }
    
    private var isCartellaTabActive: Bool {
        guard let selectedTabId = appState.selectedTabId,
              let tab = appState.openTabs.first(where: { $0.id == selectedTabId }) else {
            return false
        }
        return tab.selectedTab == "Cartella"
    }
}

#Preview {
    ContentView()
} 
