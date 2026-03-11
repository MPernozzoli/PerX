import SwiftUI
import AppKit

@main
struct PerXHubMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var monitor: HubMonitor!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nascondi l'icona dal dock
        NSApp.setActivationPolicy(.accessory)
        
        // Crea monitor
        monitor = HubMonitor()
        
        // Crea status item nella menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "PerX Hub")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Crea popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: HubStatusView(monitor: monitor))
        
        // Avvia monitoring
        monitor.startMonitoring()
        
        // Aggiorna icona in base allo stato
        monitor.$isOnline.sink { [weak self] isOnline in
            DispatchQueue.main.async {
                self?.updateStatusIcon(isOnline: isOnline)
            }
        }.store(in: &monitor.cancellables)
    }
    
    func updateStatusIcon(isOnline: Bool) {
        let imageName = isOnline ? "server.rack" : "exclamationmark.triangle"
        let color: NSColor = isOnline ? .systemGreen : .systemRed
        
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            var image = NSImage(systemSymbolName: imageName, accessibilityDescription: "PerX Hub")
            image = image?.withSymbolConfiguration(config)
            
            // Tinta l'immagine
            if let tinted = image?.copy() as? NSImage {
                tinted.lockFocus()
                color.set()
                let rect = NSRect(origin: .zero, size: tinted.size)
                rect.fill(using: .sourceAtop)
                tinted.unlockFocus()
                button.image = tinted
            } else {
                button.image = image
            }
        }
    }
    
    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Aggiorna dati quando si apre
                Task {
                    await monitor.refresh()
                }
            }
        }
    }
}
