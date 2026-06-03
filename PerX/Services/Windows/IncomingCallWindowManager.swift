import SwiftUI
import AppKit

/// Opens and manages the incoming-call floating window on macOS.
/// Called by IncomingCallPoller when a new session is detected.
@MainActor
final class IncomingCallWindowManager {
    static let shared = IncomingCallWindowManager()
    static let windowIdentifier = "IncomingCall"

    private init() {}

    func present(item: CommunicationIncomingCallItem) {
        // Don't stack two incoming windows
        guard !WindowManager.shared.isWindowOpen(identifier: Self.windowIdentifier) else { return }

        let config = WindowConfiguration(
            identifier: Self.windowIdentifier,
            title: "Chiamata in arrivo",
            minSize: CGSize(width: 280, height: 320),
            defaultSize: CGSize(width: 300, height: 340),
            isAlwaysOnTop: true,           // incoming always on top
            styleMask: [.titled, .closable],
            onClose: { RingbackPlayer.shared.stop() }
        )

        let content = IncomingCallWindowView(item: item) {
            IncomingCallWindowManager.shared.dismiss()
        }

        WindowManager.shared.openWindow(
            identifier: Self.windowIdentifier,
            content: content,
            configuration: config
        )
        positionTopRight()
    }

    func dismiss() {
        WindowManager.shared.closeWindow(identifier: Self.windowIdentifier)
    }

    private func positionTopRight() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let win = WindowManager.shared.getWindow(identifier: Self.windowIdentifier),
                  let screen = NSScreen.main else { return }
            let margin: CGFloat = 20
            let frame = screen.visibleFrame
            let winSize = win.frame.size
            win.setFrameOrigin(NSPoint(
                x: frame.maxX - winSize.width - margin,
                y: frame.maxY - winSize.height - margin
            ))
        }
    }
}

// MARK: - Incoming call view

struct IncomingCallWindowView: View {
    let item: CommunicationIncomingCallItem
    let onDismiss: () -> Void

    @State private var isAnswering = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "phone.arrow.down.left.fill")
                    .foregroundStyle(.green)
                Text("Chiamata in arrivo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Caller info
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                }
                .padding(.top, 16)

                Text(item.displayName ?? "Chiamata PerX")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                Text(item.transport == "livekit" ? "Interno PerX" : "Chiamata esterna")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let err = errorText {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 12)

            // Action buttons
            VStack(spacing: 8) {
                // TODO: pass claimId from session context when available
                // Button("Rispondi e apri sinistro") { answer(openClaim: true) }

                Button {
                    answer(openClaim: false)
                } label: {
                    Label("Rispondi", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isAnswering)

                Button(role: .destructive) {
                    RingbackPlayer.shared.stop()
                    Task {
                        _ = try? await CommunicationStartService.shared.performNotificationAction(
                            sessionId: item.sessionId,
                            actionType: .end
                        )
                    }
                    onDismiss()
                } label: {
                    Label("Rifiuta", systemImage: "phone.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isAnswering)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .onAppear { RingbackPlayer.shared.start(incoming: true) }
    }

    private func answer(openClaim: Bool) {
        isAnswering = true
        errorText = nil
        let actionType: CommunicationNotificationActionType = openClaim ? .answerAndOpenClaim : .answer
        Task {
            do {
                let result = try await CommunicationStartService.shared.performNotificationAction(
                    sessionId: item.sessionId,
                    actionType: actionType
                )
                await MainActor.run {
                    RingbackPlayer.shared.stop()
                    onDismiss()
                    if let token = result?.livekitToken {
                        CallWindowManager.shared.openCallWindow(
                            token: token,
                            displayName: item.displayName ?? "Chiamata PerX"
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    isAnswering = false
                    errorText = error.localizedDescription
                }
            }
        }
    }
}
