import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @ObservedObject private var workSchedule = WorkScheduleManager.shared
    @State private var selection: String? = "dashboard"
    @State private var isSidebarVisible = true
    
    var body: some View {
        NavigationView {
            // Sidebar
            VStack(spacing: 0) {
                // Menu principale
                List(selection: $selection) {
                    NavigationLink(
                        destination: LazyView(DashboardView()),
                        tag: "dashboard",
                        selection: $selection
                    ) {
                        Label("Dashboard", systemImage: "gauge")
                    }
                    
                    NavigationLink(
                        destination: LazyView(SinistriView()),
                        tag: "sinistri",
                        selection: $selection
                    ) {
                        Label("Sinistri", systemImage: "folder")
                    }
                    
                    NavigationLink(
                        destination: LazyView(ComunicazioniView()),
                        tag: "comunicazioni",
                        selection: $selection
                    ) {
                        Label("Comunicazioni", systemImage: "envelope")
                    }

                    NavigationLink(
                        destination: LazyView(TeamMonitorView()),
                        tag: "team",
                        selection: $selection
                    ) {
                        Label("Team", systemImage: "person.3")
                    }

                    NavigationLink(
                        destination: LazyView(StudioMonitorView()),
                        tag: "studio",
                        selection: $selection
                    ) {
                        Label("Studio", systemImage: "building.2")
                    }
                    
                    NavigationLink(
                        destination: LazyView(
                            ConsuntivoView { sinistro in
                                appState.openSinistro(sinistro)
                                selection = "sinistri"  // Forza la navigazione a Sinistri
                            }
                            .environmentObject(workSchedule)
                        ),
                        tag: "consuntivo",
                        selection: $selection
                    ) {
                        Label("Consuntivo", systemImage: "chart.bar")
                    }
                    
                    NavigationLink(
                        destination: LazyView(WorkScheduleView()),
                        tag: "programmazione",
                        selection: $selection
                    ) {
                        Label("Programmazione", systemImage: "calendar.badge.clock")
                    }
                }
                .listStyle(SidebarListStyle())
                
                Spacer()
                
                // Lista separata per Impostazioni
                List {
                    NavigationLink(
                        destination: LazyView(SettingsView().environmentObject(appState)),
                        tag: "impostazioni",
                        selection: $selection
                    ) {
                        Label("Impostazioni", systemImage: "gear")
                    }
                }
                .listStyle(SidebarListStyle())
                .frame(height: 45)
            }
            .frame(minWidth: 200)
            
            // Vista principale - mostra la dashboard come default
            SinistriView()
                .toolbarBackground(.visible, for: .windowToolbar)
                .toolbarBackgroundVisibility(.automatic, for: .windowToolbar)
        }
        .toolbar {
            // Pulsante fisso: deve essere visibile anche quando la detail view cambia (Dashboard/Comunicazioni/etc.)
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: isSidebarVisible ? "sidebar.leading" : "sidebar.trailing")
                }
                .help(isSidebarVisible ? "Nascondi sidebar" : "Mostra sidebar")
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .onChange(of: appState.selectedView) { newView in
            selection = newView
        }
        .onAppear {
            // Allinea lo state allo stato reale della sidebar (es. se l'utente l'ha chiusa dal menu di sistema)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                syncSidebarVisibilityFromSystem()
            }
        }
        .background(SidebarVisibilityMonitor(isVisible: $isSidebarVisible))
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
    
    private func toggleSidebar() {
        // Metodo più affidabile su macOS: usa l'azione di sistema sulla responder chain
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        
        // Riallinea lo state dopo l'animazione
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            syncSidebarVisibilityFromSystem()
        }
    }
    
    private func syncSidebarVisibilityFromSystem() {
        if let collapsed = isSidebarCollapsed() {
            isSidebarVisible = !collapsed
        }
    }
    
    private func currentWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible })
    }
    
    private func isSidebarCollapsed() -> Bool? {
        guard let window = currentWindow() else { return nil }
        
        func findSplitViewController(in viewController: NSViewController?) -> NSSplitViewController? {
            guard let vc = viewController else { return nil }
            if let splitVC = vc as? NSSplitViewController { return splitVC }
            for child in vc.children {
                if let splitVC = findSplitViewController(in: child) { return splitVC }
            }
            return nil
        }
        
        guard
            let splitViewController = findSplitViewController(in: window.contentViewController),
            let sidebar = splitViewController.splitViewItems.first
        else { return nil }
        
        return sidebar.isCollapsed
    }
    
    private var isCartellaTabActive: Bool {
        guard let selectedTabId = appState.selectedTabId,
              let tab = appState.openTabs.first(where: { $0.id == selectedTabId }) else {
            return false
        }
        return tab.selectedTab == "Cartella"
    }
}

// ViewModifier per monitorare la visibilità della sidebar
struct SidebarVisibilityMonitor: NSViewRepresentable {
    @Binding var isVisible: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Non modificare state durante updateNSView - causa loop infiniti
        // La visibilità viene gestita solo tramite toggleSidebar()
    }
}

// Wrapper lazy per evitare pre-rendering delle view non visibili
struct LazyView<Content: View>: View {
    let build: () -> Content
    
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    
    var body: Content {
        build()
    }
}

#Preview {
    ContentView()
} 
