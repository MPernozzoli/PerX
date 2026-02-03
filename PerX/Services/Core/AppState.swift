import SwiftUI
import CoreData

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var selectedTabId: UUID?
    @Published var openTabs: [TabInfo] = []
    @Published var selectedView: String = "dashboard"
    @Published var searchText = ""
    @Published var isSearching = false
    
    // Gestione finestre separate
    @Published var detachedWindows: [String: DetachedWindowState] = [:]
    
    private let userDefaults = UserDefaults.standard
    private let openTabsKey = "OpenTabs"
    let googleAuthService: GoogleAuthService
    
    private init() {
        self.googleAuthService = GoogleAuthService()
        // Ritarda il caricamento delle tab per evitare modifiche @Published durante la costruzione della view
        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms delay
            await self?.loadSavedTabs()
        }
    }
    
    func openSinistro(_ sinistro: Sinistro, windowId: String? = nil, openInNewWindow: Bool = false) {
        if openInNewWindow {
            openSinistroInDetachedWindow(sinistro)
            // L'associazione email-sinistro avviene automaticamente quando le email vengono processate
            // Non serve fare ricerche su Gmail - le email già scaricate vengono associate tramite pattern matching
            return
        }
        
        // Cerca in tutte le finestre (principale e separate)
        if let windowId = windowId, var windowState = detachedWindows[windowId] {
            // Cerca nella finestra specificata
            if let existingTab = windowState.tabs.first(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
                windowState.selectedTabId = existingTab.id
                detachedWindows[windowId] = windowState
                // Porta la finestra in primo piano
                if let window = WindowManager.shared.getWindow(identifier: windowId) {
                    window.makeKeyAndOrderFront(nil)
                }
                return
            }
            // Aggiungi nuova tab alla finestra specificata
            // Cerca se esiste già in un'altra finestra per preservare lo stato
            var existingTabState: TabInfo?
            if let existingTab = openTabs.first(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
                existingTabState = existingTab
            } else {
                for otherWindowState in detachedWindows.values {
                    if otherWindowState.id != windowId,
                       let tab = otherWindowState.tabs.first(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
                        existingTabState = tab
                        break
                    }
                }
            }
            
            let newTab: TabInfo
            if let existing = existingTabState {
                // Preserva lo stato esistente
                newTab = TabInfo(
                    id: UUID(),
                    sinistro: sinistro,
                    selectedTab: existing.selectedTab,
                    selectedSubTab: existing.selectedSubTab
                )
            } else {
                newTab = TabInfo(id: UUID(), sinistro: sinistro)
            }
            
            windowState.tabs.append(newTab)
            windowState.selectedTabId = newTab.id
            detachedWindows[windowId] = windowState
        } else {
            // Cerca prima nella finestra principale
            if let existingTab = openTabs.first(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
                selectedTabId = existingTab.id
                selectedView = "sinistri"
                return
            }
            
            // Cerca in tutte le finestre separate
            for (windowId, var windowState) in detachedWindows {
                if let existingTab = windowState.tabs.first(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
                    windowState.selectedTabId = existingTab.id
                    detachedWindows[windowId] = windowState
                    if let window = WindowManager.shared.getWindow(identifier: windowId) {
                        window.makeKeyAndOrderFront(nil)
                    }
                    return
                }
            }
            
            // Apri nella finestra principale
            // Cerca se esiste già in un'altra finestra per preservare lo stato
            var existingTabState: TabInfo?
            for windowState in detachedWindows.values {
                if let tab = windowState.tabs.first(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
                    existingTabState = tab
                    break
                }
            }
            
            let newTab: TabInfo
            if let existing = existingTabState {
                // Preserva lo stato esistente
                newTab = TabInfo(
                    id: UUID(),
                    sinistro: sinistro,
                    selectedTab: existing.selectedTab,
                    selectedSubTab: existing.selectedSubTab
                )
            } else {
                newTab = TabInfo(id: UUID(), sinistro: sinistro)
            }
            
            openTabs.append(newTab)
            selectedTabId = newTab.id
            selectedView = "sinistri"
            saveTabs()
        }
        
        // L'associazione email-sinistro avviene automaticamente quando le email vengono processate
        // Non serve fare ricerche su Gmail - le email già scaricate vengono associate tramite pattern matching
    }
    
    private func openSinistroInDetachedWindow(_ sinistro: Sinistro) {
        // Se già presente in una finestra detached, portala in primo piano
        for (windowId, var windowState) in detachedWindows {
            if let existingTab = windowState.tabs.first(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
                windowState.selectedTabId = existingTab.id
                detachedWindows[windowId] = windowState
                if let window = WindowManager.shared.getWindow(identifier: windowId) {
                    window.makeKeyAndOrderFront(nil)
                }
                return
            }
        }
        
        // Cerca se esiste già in un'altra finestra per preservare lo stato
        var existingTabState: TabInfo?
        if let existingTab = openTabs.first(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
            existingTabState = existingTab
        } else {
            for windowState in detachedWindows.values {
                if let tab = windowState.tabs.first(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
                    existingTabState = tab
                    break
                }
            }
        }
        
        let newTab: TabInfo
        if let existing = existingTabState {
            // Preserva lo stato esistente
            newTab = TabInfo(
                id: UUID(),
                sinistro: sinistro,
                selectedTab: existing.selectedTab,
                selectedSubTab: existing.selectedSubTab
            )
        } else {
            newTab = TabInfo(id: UUID(), sinistro: sinistro)
        }
        
        let newWindowId = UUID().uuidString
        let newWindowState = DetachedWindowState(
            id: newWindowId,
            tabs: [newTab],
            selectedTabId: newTab.id,
            isAlwaysOnTop: false
        )
        detachedWindows[newWindowId] = newWindowState
        
        // Apri la finestra con context e environment objects corretti
        let context = PersistenceController.shared.container.viewContext
        let detachedView = DetachedSinistriWindowView(windowId: newWindowId)
            .environment(\.managedObjectContext, context)
            .environmentObject(self)
        
        WindowManager.shared.openWindow(
            identifier: newWindowId,
            content: detachedView,
            configuration: WindowConfiguration(
                identifier: newWindowId,
                title: sinistro.riferimento ?? "Sinistro",
                minSize: CGSize(width: 800, height: 600),
                defaultSize: CGSize(width: 1200, height: 800),
                isAlwaysOnTop: false,
                onClose: {
                    AppState.shared.detachedWindows.removeValue(forKey: newWindowId)
                }
            )
        )
    }
    
    func closeTab(id: UUID, windowId: String? = nil) {
        if let windowId = windowId, var windowState = detachedWindows[windowId] {
            windowState.tabs.removeAll { $0.id == id }
            if windowState.selectedTabId == id {
                windowState.selectedTabId = windowState.tabs.last?.id
            }
            detachedWindows[windowId] = windowState
        } else {
            openTabs.removeAll { $0.id == id }
            if selectedTabId == id {
                selectedTabId = openTabs.last?.id
            }
            saveTabs()
        }
    }
    
    func moveTab(from sourceIndex: Int, to destinationIndex: Int, windowId: String? = nil) {
        if let windowId = windowId, var windowState = detachedWindows[windowId] {
            guard sourceIndex < windowState.tabs.count && destinationIndex < windowState.tabs.count else { return }
            let tab = windowState.tabs.remove(at: sourceIndex)
            windowState.tabs.insert(tab, at: destinationIndex)
            detachedWindows[windowId] = windowState
        } else {
            guard sourceIndex < openTabs.count && destinationIndex < openTabs.count else { return }
            let tab = openTabs.remove(at: sourceIndex)
            openTabs.insert(tab, at: destinationIndex)
            saveTabs()
        }
    }
    
    func moveTabBetweenWindows(tab: TabInfo, fromWindowId: String?, toWindowId: String?, atIndex: Int? = nil) {
        // Rimuovi dalla finestra sorgente
        if let fromWindowId = fromWindowId, var sourceWindow = detachedWindows[fromWindowId] {
            sourceWindow.tabs.removeAll { $0.id == tab.id }
            if sourceWindow.selectedTabId == tab.id {
                sourceWindow.selectedTabId = sourceWindow.tabs.last?.id
            }
            detachedWindows[fromWindowId] = sourceWindow
        } else if fromWindowId == nil {
            // Rimuovi dalla finestra principale
            openTabs.removeAll { $0.id == tab.id }
            if selectedTabId == tab.id {
                selectedTabId = openTabs.last?.id
            }
            saveTabs()
        }
        
        // Aggiungi alla finestra destinazione
        if let toWindowId = toWindowId, var destWindow = detachedWindows[toWindowId] {
            if let atIndex = atIndex, atIndex <= destWindow.tabs.count {
                destWindow.tabs.insert(tab, at: atIndex)
            } else {
                destWindow.tabs.append(tab)
            }
            destWindow.selectedTabId = tab.id
            detachedWindows[toWindowId] = destWindow
        } else if toWindowId == nil {
            // Aggiungi alla finestra principale
            if let atIndex = atIndex, atIndex <= openTabs.count {
                openTabs.insert(tab, at: atIndex)
            } else {
                openTabs.append(tab)
            }
            selectedTabId = tab.id
            saveTabs()
        }
    }
    
    func detachTab(_ tab: TabInfo, fromWindowId: String?) {
        // Rimuovi dalla finestra originale
        if let fromWindowId = fromWindowId, var windowState = detachedWindows[fromWindowId] {
            windowState.tabs.removeAll { $0.id == tab.id }
            if windowState.selectedTabId == tab.id {
                windowState.selectedTabId = windowState.tabs.last?.id
            }
            detachedWindows[fromWindowId] = windowState
        } else {
            openTabs.removeAll { $0.id == tab.id }
            if selectedTabId == tab.id {
                selectedTabId = openTabs.last?.id
            }
            saveTabs()
        }
        
        // Crea nuova finestra
        let newWindowId = UUID().uuidString
        let newWindowState = DetachedWindowState(
            id: newWindowId,
            tabs: [tab],
            selectedTabId: tab.id,
            isAlwaysOnTop: false
        )
        detachedWindows[newWindowId] = newWindowState
        
        // Apri la finestra con context e environment objects corretti
        let context = PersistenceController.shared.container.viewContext
        let detachedView = DetachedSinistriWindowView(windowId: newWindowId)
            .environment(\.managedObjectContext, context)
            .environmentObject(self)
        
        WindowManager.shared.openWindow(
            identifier: newWindowId,
            content: detachedView,
            configuration: WindowConfiguration(
                identifier: newWindowId,
                title: tab.sinistro.riferimento ?? "Sinistro",
                minSize: CGSize(width: 800, height: 600),
                defaultSize: CGSize(width: 1200, height: 800),
                isAlwaysOnTop: false,
                onClose: {
                    // Rimuovi la finestra quando viene chiusa in modo sicuro
                    AppState.shared.detachedWindows.removeValue(forKey: newWindowId)
                }
            )
        )
    }
    
    func closeDetachedWindow(windowId: String) {
        detachedWindows.removeValue(forKey: windowId)
        WindowManager.shared.closeWindow(identifier: windowId)
    }
    
    /// Chiude tutte le tab e finestre (usato al logout)
    func closeAllTabs() {
        // Chiudi tutte le finestre detached
        for windowId in detachedWindows.keys {
            WindowManager.shared.closeWindow(identifier: windowId)
        }
        detachedWindows.removeAll()
        
        // Chiudi tutte le tab nella finestra principale
        openTabs.removeAll()
        selectedTabId = nil
        
        // Rimuovi tab salvate
        userDefaults.removeObject(forKey: openTabsKey)
        
        print("[AppState] 🧹 Tutte le tab e finestre chiuse")
    }
    
    func saveTabs() {
        let tabData = openTabs.map { tab -> [String: String] in
            ["id": tab.id.uuidString, "riferimento": tab.sinistro.riferimento ?? ""]
        }
        userDefaults.set(tabData, forKey: openTabsKey)
    }
    
    private func loadSavedTabs() {
        guard let savedData = userDefaults.array(forKey: openTabsKey) as? [[String: String]] else { return }
        
        // Recupera i sinistri dal Core Data
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        
        for tabInfo in savedData {
            guard let idString = tabInfo["id"],
                  let id = UUID(uuidString: idString),
                  let riferimento = tabInfo["riferimento"] else { continue }
            
            fetchRequest.predicate = NSPredicate(format: "riferimento == %@", riferimento)
            
            if let sinistro = try? context.fetch(fetchRequest).first {
                let tab = TabInfo(id: id, sinistro: sinistro)
                openTabs.append(tab)
            }
        }
        
        // Seleziona l'ultima tab se ce ne sono
        selectedTabId = openTabs.last?.id
    }
}

struct TabInfo: Identifiable, Equatable {
    let id: UUID
    let sinistro: Sinistro
    var selectedTab: String = "Dettagli"
    var selectedSubTab: String? = nil
    
    static func == (lhs: TabInfo, rhs: TabInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.selectedTab == rhs.selectedTab &&
        lhs.selectedSubTab == rhs.selectedSubTab
    }
}

struct DetachedWindowState: Equatable {
    let id: String
    var tabs: [TabInfo]
    var selectedTabId: UUID?
    var isAlwaysOnTop: Bool
    
    static func == (lhs: DetachedWindowState, rhs: DetachedWindowState) -> Bool {
        lhs.id == rhs.id &&
        lhs.tabs == rhs.tabs &&
        lhs.selectedTabId == rhs.selectedTabId &&
        lhs.isAlwaysOnTop == rhs.isAlwaysOnTop
    }
}
