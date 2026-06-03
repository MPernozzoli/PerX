import Foundation
import AVFoundation
import Combine

/// Polls GET /api/v1/communications/incoming every 5s and:
/// - fires a local UserNotification (works when app is backgrounded)
/// - publishes on `incomingCall` so in-app UI can show a banner immediately
///
/// Used on both macOS (no VoIP push) and iPad/iOS until APNs VoIP certs are configured.
@MainActor
final class IncomingCallPoller: ObservableObject {
    static let shared = IncomingCallPoller()

    /// Published when a new incoming call session is detected.
    let incomingCall = PassthroughSubject<CommunicationIncomingCallItem, Never>()

    private var timer: Timer?
    private var seenSessions: Set<String> = []
    private let pollInterval: TimeInterval = 5

    private init() {}

    func start() {
        guard timer == nil else { return }
        // Fire immediately so the first check doesn't wait 5s
        Task { await poll() }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() async {
        do {
            let response = try await CommunicationStartService.shared.fetchIncomingCalls()
            for item in response.items where !seenSessions.contains(item.sessionId) {
                seenSessions.insert(item.sessionId)
                // In-app banner (works foregrounded)
                incomingCall.send(item)
                // System notification (works backgrounded)
                CommunicationNotificationService.shared.sendIncomingCallNotification(
                    sessionId: item.sessionId,
                    callId: item.callId,
                    callerName: item.displayName ?? "Chiamata in arrivo",
                    phoneNumber: nil,
                    claimContext: nil
                )
            }
            // Prune sessions no longer active
            seenSessions = seenSessions.intersection(Set(response.items.map(\.sessionId)))
        } catch {
            // Silently ignore — network errors or unconfigured transport are expected
        }
    }
}

// MARK: - Ringback tone (caller and callee side)

/// Plays a looping 425 Hz EU ringback tone (1 s on / 4 s off).
/// Call `start()` on outbound ringing or incoming call; `stop()` on connect/fail/dismiss.
final class RingbackPlayer {
    static let shared = RingbackPlayer()

    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var isPlaying = false

    private init() {}

    func start() {
        guard !isPlaying else { return }
        isPlaying = true

        let eng = AVAudioEngine()
        let src = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        eng.attach(src)
        eng.connect(src, to: eng.mainMixerNode, format: format)

        let sampleRate = 44100.0
        let onFrames  = Int(sampleRate)        // 1 s tone
        let offFrames = Int(sampleRate * 4.0)  // 4 s silence
        let total     = onFrames + offFrames
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)) else {
            isPlaying = false; return
        }
        buf.frameLength = AVAudioFrameCount(total)
        let data = buf.floatChannelData![0]
        for i in 0..<onFrames {
            data[i] = Float(0.35 * sin(2 * .pi * 425.0 * Double(i) / sampleRate))
        }
        for i in onFrames..<total { data[i] = 0 }

        do {
            try eng.start()
            src.play()
            src.scheduleBuffer(buf, at: nil, options: .loops)
            self.engine = eng
            self.node   = src
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        guard isPlaying else { return }
        node?.stop()
        engine?.stop()
        node    = nil
        engine  = nil
        isPlaying = false
    }
}
