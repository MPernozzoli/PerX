import Foundation
import AVFoundation

/// Polls GET /api/v1/communications/incoming on a timer and fires local
/// UserNotifications when a new session arrives. Used on macOS where VoIP
/// push (APNs voip) is not available. On iOS the VoIP push handles this.
@MainActor
final class IncomingCallPoller: ObservableObject {
    static let shared = IncomingCallPoller()

    private var timer: Timer?
    private var seenSessions: Set<String> = []
    private let pollInterval: TimeInterval = 5

    private init() {}

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.poll()
            }
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
                CommunicationNotificationService.shared.sendIncomingCallNotification(
                    sessionId: item.sessionId,
                    callId: item.callId,
                    callerName: item.displayName ?? "Chiamata in arrivo",
                    phoneNumber: nil,
                    claimContext: nil
                )
            }
            // Prune sessions that are no longer active
            let activeIds = Set(response.items.map(\.sessionId))
            seenSessions = seenSessions.intersection(activeIds)
        } catch {
            // Silently ignore — network errors or not-configured transport are expected
        }
    }
}

// MARK: - Ringback tone (caller side)

/// Plays a looping ringback tone while the call is in the ringing state.
/// Call `start()` when the call transitions to .ringing, `stop()` on answer/fail.
final class RingbackPlayer {
    static let shared = RingbackPlayer()

    private var player: AVAudioPlayer?

    private init() {}

    func start() {
        guard player == nil else { return }
        // Use the system ringback tone if available, otherwise synthesise a simple beep sequence
        if let url = Bundle.main.url(forResource: "ringback", withExtension: "mp3")
            ?? Bundle.main.url(forResource: "ringback", withExtension: "caf") {
            play(url: url)
        } else {
            playSystemRingback()
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private func play(url: URL) {
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.6
            p.play()
            player = p
        } catch {
            playSystemRingback()
        }
    }

    private func playSystemRingback() {
        // Generate a 425 Hz European dial-tone pattern: 1s on / 4s off, looped
        // Uses AVAudioEngine to synthesise the tone without requiring a bundled file
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let src = AVAudioPlayerNode()
        engine.attach(src)
        engine.connect(src, to: engine.mainMixerNode, format: format)

        let sampleRate = 44100.0
        let onSamples = Int(sampleRate)       // 1 s tone
        let offSamples = Int(sampleRate * 4)  // 4 s silence
        let totalSamples = onSamples + offSamples
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalSamples)) else { return }
        buffer.frameLength = AVAudioFrameCount(totalSamples)
        let data = buffer.floatChannelData![0]
        let freq = 425.0
        for i in 0..<onSamples {
            let t = Double(i) / sampleRate
            data[i] = Float(0.4 * sin(2 * .pi * freq * t))
        }
        for i in onSamples..<totalSamples {
            data[i] = 0
        }

        do {
            try engine.start()
            src.play()
            src.scheduleBuffer(buffer, at: nil, options: .loops)
            // Hold references so they aren't deallocated
            objc_setAssociatedObject(self, &AssociatedKeys.engine, engine, .OBJC_ASSOCIATION_RETAIN)
            objc_setAssociatedObject(self, &AssociatedKeys.node, src, .OBJC_ASSOCIATION_RETAIN)
        } catch {
            // Fail silently — ringtone is cosmetic
        }
    }
}

private enum AssociatedKeys {
    static var engine = "engine"
    static var node = "node"
}
