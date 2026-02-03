import SwiftUI
import AppKit

@MainActor
class ComposeEmailWindowManager: ObservableObject {
    static let shared = ComposeEmailWindowManager()
    
    private static let windowIdentifier = "ComposeEmail"
    
    @Published var isAlwaysOnTop: Bool = false
    
    var window: NSWindow? {
        WindowManager.shared.getWindow(identifier: Self.windowIdentifier)
    }
    
    private init() {}
    
    func openComposeEmail(mode: ComposeEmailMode) {
        // Se la finestra esiste già, portala in primo piano
        if WindowManager.shared.isWindowOpen(identifier: Self.windowIdentifier) {
            window?.makeKeyAndOrderFront(nil)
            return
        }
        
        // Crea la configurazione della finestra
        let configuration = WindowConfiguration(
            identifier: Self.windowIdentifier,
            title: windowTitle(for: mode),
            minSize: CGSize(width: 700, height: 600),
            defaultSize: CGSize(width: 800, height: 700),
            isAlwaysOnTop: isAlwaysOnTop
        )
        
        // Crea il contenuto della finestra
        let contentView = ComposeEmailWindowContent(mode: mode)
            .frame(minWidth: 700, minHeight: 600)
        
        // Apri la finestra usando il WindowManager centralizzato
        WindowManager.shared.openWindow(
            identifier: Self.windowIdentifier,
            content: contentView,
            configuration: configuration
        )
    }
    
    func closeComposeEmail() {
        WindowManager.shared.closeWindow(identifier: Self.windowIdentifier)
    }
    
    func updateAlwaysOnTop(_ value: Bool) {
        isAlwaysOnTop = value
        WindowManager.shared.updateAlwaysOnTop(identifier: Self.windowIdentifier, value: value)
    }
    
    func isWindowVisible() -> Bool {
        return WindowManager.shared.isWindowOpen(identifier: Self.windowIdentifier)
    }
    
    private func windowTitle(for mode: ComposeEmailMode) -> String {
        switch mode {
        case .reply:
            return "Rispondi"
        case .replyAll:
            return "Rispondi a tutti"
        case .forward:
            return "Inoltra"
        case .new:
            return "Nuova email"
        }
    }
}

struct ComposeEmailWindowContent: View {
    let mode: ComposeEmailMode
    @ObservedObject var windowManager = ComposeEmailWindowManager.shared
    
    var body: some View {
        ComposeEmailView(mode: mode)
            .environmentObject(windowManager)
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}

