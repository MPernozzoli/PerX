import SwiftUI
import AppKit

@MainActor
class WindowManager: ObservableObject {
    static let shared = WindowManager()
    
    // Manteniamo riferimenti strong alle finestre e ai loro delegate
    private var windowInstances: [String: ManagedWindow] = [:]
    private var closingIdentifiers: Set<String> = []
    
    private init() {}
    
    func openWindow<Content: View>(
        identifier: String,
        content: Content,
        configuration: WindowConfiguration,
        tabId: String? = nil,
        tabTitle: String? = nil
    ) {
        // Se la finestra sta chiudendosi, aspetta e riprova
        if closingIdentifiers.contains(identifier) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.openWindow(identifier: identifier, content: content, configuration: configuration, tabId: tabId, tabTitle: tabTitle)
            }
            return
        }
        
        let resolvedTabTitle = tabTitle ?? configuration.title
        let resolvedTabId = tabId ?? resolvedTabTitle
        let newTab = WindowTab(id: resolvedTabId, title: resolvedTabTitle, content: AnyView(content))
        
        // Se la finestra esiste già, aggiungi/aggiorna la tab e porta in primo piano
        if let existingManaged = windowInstances[identifier] {
            existingManaged.tabState.addOrReplace(tab: newTab)
            
            existingManaged.window.title = existingManaged.tabState.currentTab?.title ?? configuration.title
            existingManaged.window.minSize = configuration.minSize
            existingManaged.window.level = configuration.isAlwaysOnTop ? .floating : .normal
            existingManaged.configuration = configuration
            
            if !existingManaged.window.isVisible {
                existingManaged.window.setFrame(
                    NSRect(origin: existingManaged.window.frame.origin, size: configuration.defaultSize),
                    display: true
                )
                existingManaged.window.center()
            }
            
            existingManaged.window.makeKeyAndOrderFront(nil)
            return
        }
        
        // Crea nuova finestra
        let tabState = WindowTabState()
        
        let tabsContainer = WindowTabsContainer(
            tabState: tabState,
            onSelect: { [weak self] tab in
                self?.windowInstances[identifier]?.window.title = tab.title
            },
            onClose: { tab in
                tabState.closeTab(id: tab.id)
            }
        )
        
        let hostingView = NSHostingView(rootView: AnyView(tabsContainer))
        hostingView.frame = NSRect(origin: .zero, size: configuration.defaultSize)
        
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: configuration.defaultSize),
            styleMask: configuration.styleMask,
            backing: .buffered,
            defer: false
        )
        
        // IMPORTANTE: Impedisce che la finestra venga rilasciata quando chiusa
        window.isReleasedWhenClosed = false
        
        window.contentView = hostingView
        window.title = resolvedTabTitle
        window.minSize = configuration.minSize
        window.level = configuration.isAlwaysOnTop ? .floating : .normal
        window.collectionBehavior = [.fullScreenAuxiliary]
        
        // Crea il managed window con riferimenti strong
        let managed = ManagedWindow(
            identifier: identifier,
            window: window,
            configuration: configuration,
            tabState: tabState,
            windowManager: self
        )
        
        // Setup callbacks
        tabState.onEmpty = { [weak self, weak managed] in
            guard let self = self, let managed = managed else { return }
            self.initiateWindowClose(identifier: managed.identifier)
        }
        
        tabState.onSelectionChanged = { [weak managed] tab in
            guard let managed = managed else { return }
            if let tab = tab {
                managed.window.title = "\(managed.configuration.title) - \(tab.title)"
            } else {
                managed.window.title = managed.configuration.title
            }
        }
        
        // Imposta il delegate
        window.delegate = managed
        
        // Aggiungi la prima tab
        tabState.addOrReplace(tab: newTab)
        
        // Salva nel dizionario
        windowInstances[identifier] = managed
        
        // Mostra la finestra
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    
    func closeWindow(identifier: String) {
        initiateWindowClose(identifier: identifier)
    }
    
    private func initiateWindowClose(identifier: String) {
        guard !closingIdentifiers.contains(identifier) else { return }
        guard let managed = windowInstances[identifier] else { return }
        
        closingIdentifiers.insert(identifier)
        managed.tabState.prepareForClosure()
        
        // Chiudi la finestra - questo triggerà windowWillClose
        managed.window.performClose(nil)
    }
    
    func handleWindowClosed(identifier: String) {
        guard let managed = windowInstances[identifier] else {
            closingIdentifiers.remove(identifier)
            return
        }
        
        // Esegui callback onClose se presente
        managed.configuration.onClose?()
        
        // Rimuovi il delegate
        managed.window.delegate = nil
        
        // Rimuovi dal dizionario
        windowInstances.removeValue(forKey: identifier)
        
        // Rimuovi dall'insieme delle finestre in chiusura
        DispatchQueue.main.async { [weak self] in
            self?.closingIdentifiers.remove(identifier)
        }
    }
    
    func updateConfiguration(identifier: String, configuration: WindowConfiguration) {
        guard !closingIdentifiers.contains(identifier),
              let managed = windowInstances[identifier] else { return }
        
        managed.window.title = configuration.title
        managed.window.minSize = configuration.minSize
        managed.window.level = configuration.isAlwaysOnTop ? .floating : .normal
        managed.configuration = configuration
    }
    
    func getWindow(identifier: String) -> NSWindow? {
        guard !closingIdentifiers.contains(identifier) else { return nil }
        return windowInstances[identifier]?.window
    }
    
    func isWindowOpen(identifier: String) -> Bool {
        guard !closingIdentifiers.contains(identifier) else { return false }
        return windowInstances[identifier]?.window.isVisible ?? false
    }
    
    func updateAlwaysOnTop(identifier: String, value: Bool) {
        guard !closingIdentifiers.contains(identifier),
              let managed = windowInstances[identifier] else { return }
        
        managed.window.level = value ? .floating : .normal
        managed.configuration.isAlwaysOnTop = value
    }

    func updateTabTitle(identifier: String, tabId: String, newTitle: String) {
        guard let managed = windowInstances[identifier] else { return }
        if let index = managed.tabState.tabs.firstIndex(where: { $0.id == tabId }) {
            let oldTab = managed.tabState.tabs[index]
            let newTab = WindowTab(id: oldTab.id, title: newTitle, content: oldTab.content)
            managed.tabState.tabs[index] = newTab
            
            if managed.tabState.selectedTabId == tabId {
                managed.window.title = "\(managed.configuration.title) - \(newTitle)"
            }
        }
    }

    func closeTab(identifier: String, tabId: String) {
        guard let managed = windowInstances[identifier] else { return }
        managed.tabState.closeTab(id: tabId)
    }
}

// MARK: - ManagedWindow

/// Classe che mantiene riferimenti strong alla finestra e agisce come delegate
private class ManagedWindow: NSObject, NSWindowDelegate {
    let identifier: String
    let window: NSWindow
    var configuration: WindowConfiguration
    let tabState: WindowTabState
    weak var windowManager: WindowManager?
    private var didClose = false
    
    init(identifier: String, window: NSWindow, configuration: WindowConfiguration, tabState: WindowTabState, windowManager: WindowManager) {
        self.identifier = identifier
        self.window = window
        self.configuration = configuration
        self.tabState = tabState
        self.windowManager = windowManager
        super.init()
    }
    
    // MARK: - NSWindowDelegate
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Verifica che sia la nostra finestra
        guard sender === window else { return true }
        return true
    }
    
    func windowWillClose(_ notification: Notification) {
        guard !didClose else { return }
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else { return }
        
        didClose = true
        
        // Pulisci callback per evitare riferimenti circolari
        tabState.prepareForClosure()
        
        // Notifica il manager con un piccolo delay per assicurarsi che tutto sia pulito
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.windowManager?.handleWindowClosed(identifier: self.identifier)
        }
    }
}

// MARK: - Tab Support

private struct WindowTab: Identifiable, Equatable {
    let id: String
    let title: String
    let content: AnyView
    
    static func == (lhs: WindowTab, rhs: WindowTab) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
private final class WindowTabState: ObservableObject {
    @Published var tabs: [WindowTab] = []
    @Published var selectedTabId: String?
    
    var onEmpty: (() -> Void)?
    var onSelectionChanged: ((WindowTab?) -> Void)?
    private var isClosing = false
    
    var currentTab: WindowTab? {
        guard let selectedTabId else { return nil }
        return tabs.first(where: { $0.id == selectedTabId })
    }
    
    func addOrReplace(tab: WindowTab) {
        guard !isClosing else { return }
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[index] = tab
        } else {
            tabs.append(tab)
        }
        selectedTabId = tab.id
        onSelectionChanged?(tab)
    }
    
    func selectTab(id: String) {
        guard !isClosing else { return }
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        selectedTabId = id
        onSelectionChanged?(tab)
    }
    
    func closeTab(id: String) {
        guard !tabs.isEmpty, !isClosing else { return }
        
        let wasSelected = selectedTabId == id
        tabs.removeAll { $0.id == id }
        
        if tabs.isEmpty {
            isClosing = true
            selectedTabId = nil
            let emptyCallback = onEmpty
            onEmpty = nil
            onSelectionChanged = nil
            emptyCallback?()
        } else {
            if wasSelected {
                selectedTabId = tabs.last?.id
                onSelectionChanged?(currentTab)
            }
        }
    }
    
    func prepareForClosure() {
        isClosing = true
        onEmpty = nil
        onSelectionChanged = nil
    }
}

private struct WindowTabsContainer: View {
    @ObservedObject var tabState: WindowTabState
    let onSelect: (WindowTab) -> Void
    let onClose: (WindowTab) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            if tabState.tabs.count > 1 {
                tabBar
                Divider()
            }
            
            if let selected = tabState.currentTab {
                selected.content
            } else {
                Text("Nessuna tab selezionata")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabState.tabs) { tab in
                    TabButton(
                        title: tab.title,
                        isSelected: tabState.selectedTabId == tab.id,
                        canClose: true,
                        onSelect: {
                            tabState.selectTab(id: tab.id)
                            onSelect(tab)
                        },
                        onClose: {
                            onClose(tab)
                        }
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(height: 42)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color(NSColor.windowBackgroundColor).opacity(0.95)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
