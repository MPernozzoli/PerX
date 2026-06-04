#if os(macOS)
import SwiftUI
import AVFoundation
#if canImport(LiveKit)
import LiveKit
#endif

// MARK: - Floating call window

/// Standalone call window used on macOS. Opened via CallWindowManager.
/// On iOS/iPadOS the TelefonoCommunicationView drives the sheet/banner instead.
struct CallFloatingWindowView: View {
    let token: CommunicationLiveKitToken
    let displayName: String
    /// Called when the user taps Termina or call ends — close the host window.
    var onClose: (() -> Void)?

    @EnvironmentObject private var windowManager: CallWindowManager
    @StateObject private var vm = CallFloatingViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            callBody
        }
        .background(Color(.windowBackgroundColor))
        .onAppear { vm.connect(token: token) }
        .onDisappear { vm.hangup() }
        .onChange(of: vm.phase) { _, phase in
            if phase == .ended || phase == .failed {
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    await MainActor.run { onClose?() }
                }
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Always-on-top pin
            Button {
                windowManager.updateAlwaysOnTop(!windowManager.isAlwaysOnTop)
            } label: {
                Image(systemName: windowManager.isAlwaysOnTop ? "pin.fill" : "pin")
                    .foregroundStyle(windowManager.isAlwaysOnTop ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(windowManager.isAlwaysOnTop ? "Disattiva Sempre in primo piano" : "Tieni sempre in primo piano")

            Spacer()

            Text(displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer()

            // Duration
            Text(vm.durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 42, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Body

    private var callBody: some View {
        VStack(spacing: 20) {
            // Avatar / state icon
            ZStack {
                Circle()
                    .fill(phaseColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: phaseIcon)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(phaseColor)
            }
            .padding(.top, 20)

            // Status text
            Text(vm.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)

            // Controls grid
            controlsGrid

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Controls

    private var controlsGrid: some View {
        VStack(spacing: 12) {
            // Row 1: secondary actions
            HStack(spacing: 12) {
                callControlButton(
                    icon: vm.isVideoEnabled ? "video.fill" : "video.slash",
                    label: "Video",
                    active: vm.isVideoEnabled,
                    disabled: vm.phase != .active
                ) { vm.toggleVideo() }

                callControlButton(
                    icon: "rectangle.on.rectangle",
                    label: "Condividi",
                    active: false,
                    disabled: true   // screen share: future feature, placeholder
                ) {}

                callControlButton(
                    icon: "person.badge.plus",
                    label: "Aggiungi",
                    active: false,
                    disabled: true   // add participant: future feature, placeholder
                ) {}

                callControlButton(
                    icon: "arrow.triangle.2.circlepath.phone",
                    label: "Inoltra",
                    active: false,
                    disabled: true   // call transfer: future feature, placeholder
                ) {}
            }

            // Row 2: primary actions
            HStack(spacing: 24) {
                // Mute
                Button {
                    vm.toggleMute()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: vm.isMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 22))
                            .frame(width: 52, height: 52)
                            .background(vm.isMuted ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                            .foregroundStyle(vm.isMuted ? .orange : .primary)
                        Text(vm.isMuted ? "Riattiva" : "Mute")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(vm.phase != .active)

                // Hang up
                Button {
                    vm.hangup()
                    onClose?()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 22))
                            .frame(width: 64, height: 64)
                            .background(Color.red)
                            .clipShape(Circle())
                            .foregroundStyle(.white)
                        Text("Termina")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func callControlButton(
        icon: String,
        label: String,
        active: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44)
                    .background(active ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    .clipShape(Circle())
                    .foregroundStyle(active ? Color.accentColor : (disabled ? Color.secondary.opacity(0.4) : .secondary))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(disabled ? Color.secondary.opacity(0.4) : .secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(disabled ? "\(label): disponibile prossimamente" : label)
    }

    // MARK: Helpers

    private var phaseColor: Color {
        switch vm.phase {
        case .connecting: return .yellow
        case .ringing:    return .orange
        case .active:     return .green
        case .ended:      return .secondary
        case .failed:     return .red
        }
    }

    private var phaseIcon: String {
        switch vm.phase {
        case .connecting: return "phone.arrow.up.right"
        case .ringing:    return "phone.arrow.up.right.fill"
        case .active:     return "phone.connection.fill"
        case .ended:      return "phone.down"
        case .failed:     return "exclamationmark.triangle"
        }
    }
}

// MARK: - ViewModel

enum CallPhase { case connecting, ringing, active, ended, failed }

@MainActor
final class CallFloatingViewModel: ObservableObject {
    @Published private(set) var phase: CallPhase = .connecting
    @Published private(set) var statusText = "Connessione..."
    @Published private(set) var durationText = "00:00"
    @Published private(set) var isMuted = false
    @Published private(set) var isVideoEnabled = false

#if canImport(LiveKit)
    private var room: Room?
#endif
    private var sessionId: String?
    private var startDate: Date?
    private var timer: Timer?

    func connect(token: CommunicationLiveKitToken) {
        sessionId = token.sessionId
        RingbackPlayer.shared.stop()
        #if canImport(LiveKit)
        let r = Room()
        self.room = r
        Task {
            do {
                try await r.connect(url: token.livekitUrl, token: token.token)
                try? await r.localParticipant.setMicrophone(enabled: true)
                await MainActor.run {
                    self.phase = .ringing
                    self.statusText = "In chiamata..."
                    RingbackPlayer.shared.start(incoming: false)
                }
                // Wait for a remote participant to join (callee answers)
                // Poll up to 90 s before giving up
                let deadline = Date().addingTimeInterval(90)
                while Date() < deadline {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    if !r.remoteParticipants.isEmpty {
                        await MainActor.run {
                            RingbackPlayer.shared.stop()
                            self.phase = .active
                            self.statusText = "In chiamata"
                            self.startDate = Date()
                            self.startTimer()
                        }
                        return
                    }
                    // If room disconnected, bail
                    if r.connectionState == .disconnected {
                        await MainActor.run {
                            RingbackPlayer.shared.stop()
                            self.phase = .ended
                            self.statusText = "Chiamata terminata"
                        }
                        return
                    }
                }
                // Timeout — no answer
                await MainActor.run {
                    RingbackPlayer.shared.stop()
                    self.phase = .failed
                    self.statusText = "Nessuna risposta"
                }
                await r.disconnect()
            } catch {
                await MainActor.run {
                    RingbackPlayer.shared.stop()
                    self.phase = .failed
                    self.statusText = "Connessione non riuscita"
                }
            }
        }
        #else
        phase = .failed
        statusText = "LiveKit non disponibile"
        #endif
    }

    func hangup() {
        #if canImport(LiveKit)
        Task { await room?.disconnect() }
        room = nil
        #endif
        stopTimer()
        RingbackPlayer.shared.stop()
        phase = .ended
        statusText = "Chiamata terminata"
        // Notify backend so the session moves to "ended" and disappears from
        // incoming polls on other devices (prevents ghost ringing after hangup)
        if let sid = sessionId {
            Task {
                _ = try? await CommunicationStartService.shared.performNotificationAction(
                    sessionId: sid,
                    actionType: .end
                )
            }
        }
    }

    func toggleMute() {
        #if canImport(LiveKit)
        isMuted.toggle()
        Task { try? await room?.localParticipant.setMicrophone(enabled: !isMuted) }
        #endif
    }

    func toggleVideo() {
        #if canImport(LiveKit)
        isVideoEnabled.toggle()
        Task { try? await room?.localParticipant.setCamera(enabled: isVideoEnabled) }
        #endif
    }

    // MARK: Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if let start = startDate {
            let elapsed = Int(Date().timeIntervalSince(start))
            durationText = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
        }
        // Detect remote hangup: active call but no remote participants → other party left
        #if canImport(LiveKit)
        if phase == .active, let r = room, r.remoteParticipants.isEmpty {
            hangup()
        }
        #endif
    }
}
#endif
