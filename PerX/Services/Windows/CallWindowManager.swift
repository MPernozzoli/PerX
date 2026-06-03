import SwiftUI
import AppKit

@MainActor
final class CallWindowManager: ObservableObject {
    static let shared = CallWindowManager()

    static let windowIdentifier = "ActiveCall"

    @Published var isAlwaysOnTop: Bool = false

    var window: NSWindow? {
        WindowManager.shared.getWindow(identifier: Self.windowIdentifier)
    }

    private init() {}

    func openCallWindow(token: CommunicationLiveKitToken, displayName: String) {
        let configuration = WindowConfiguration(
            identifier: Self.windowIdentifier,
            title: "Chiamata - \(displayName)",
            minSize: CGSize(width: 300, height: 360),
            defaultSize: CGSize(width: 340, height: 400),
            isAlwaysOnTop: isAlwaysOnTop,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            onClose: {
                Task { @MainActor in RingbackPlayer.shared.stop() }
            }
        )

        let content = CallFloatingWindowView(token: token, displayName: displayName) {
            CallWindowManager.shared.closeCallWindow()
        }
        .environmentObject(self)

        WindowManager.shared.openWindow(
            identifier: Self.windowIdentifier,
            content: content,
            configuration: configuration
        )

        // Position top-right of main screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.positionTopRight()
        }
    }

    func closeCallWindow() {
        WindowManager.shared.closeWindow(identifier: Self.windowIdentifier)
    }

    func updateAlwaysOnTop(_ value: Bool) {
        isAlwaysOnTop = value
        WindowManager.shared.updateAlwaysOnTop(identifier: Self.windowIdentifier, value: value)
    }

    private func positionTopRight() {
        guard let win = window,
              let screen = NSScreen.main else { return }
        let margin: CGFloat = 20
        let frame = screen.visibleFrame
        let winSize = win.frame.size
        let x = frame.maxX - winSize.width - margin
        let y = frame.maxY - winSize.height - margin
        win.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
