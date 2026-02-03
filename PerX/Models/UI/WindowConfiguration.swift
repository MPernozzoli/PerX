import SwiftUI
import AppKit

struct WindowConfiguration {
    let identifier: String
    var title: String
    var minSize: CGSize
    var defaultSize: CGSize
    var isAlwaysOnTop: Bool
    var styleMask: NSWindow.StyleMask
    var toolbarItems: [WindowToolbarItem]
    var onClose: (() -> Void)?
    
    init(
        identifier: String,
        title: String,
        minSize: CGSize = CGSize(width: 400, height: 300),
        defaultSize: CGSize = CGSize(width: 800, height: 600),
        isAlwaysOnTop: Bool = false,
        styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable],
        toolbarItems: [WindowToolbarItem] = [],
        onClose: (() -> Void)? = nil
    ) {
        self.identifier = identifier
        self.title = title
        self.minSize = minSize
        self.defaultSize = defaultSize
        self.isAlwaysOnTop = isAlwaysOnTop
        self.styleMask = styleMask
        self.toolbarItems = toolbarItems
        self.onClose = onClose
    }
}

struct WindowToolbarItem: Identifiable {
    let id: String
    let icon: String
    let action: () -> Void
    let help: String
    
    init(id: String, icon: String, action: @escaping () -> Void, help: String = "") {
        self.id = id
        self.icon = icon
        self.action = action
        self.help = help
    }
}

