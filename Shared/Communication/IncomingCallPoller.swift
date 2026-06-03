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
                // Publish for iPad/iOS in-app alert
                incomingCall.send(item)
                #if os(macOS)
                // macOS: dedicated floating window with Answer/Reject buttons
                IncomingCallWindowManager.shared.present(item: item)
                #endif
                // System notification (works backgrounded on all platforms)
                CommunicationNotificationService.shared.sendIncomingCallNotification(
                    sessionId: item.sessionId,
                    callId: item.callId,
                    callerName: item.displayName ?? "Chiamata in arrivo",
                    phoneNumber: nil,
                    claimContext: nil
                )
            }
            // Prune sessions no longer active
            let activeIds = Set(response.items.map(\.sessionId))
            if !seenSessions.subtracting(activeIds).isEmpty {
                // Sessions that disappeared — dismiss incoming window if still showing
                #if os(macOS)
                if !activeIds.contains(where: { seenSessions.contains($0) }) {
                    IncomingCallWindowManager.shared.dismiss()
                }
                #endif
                RingbackPlayer.shared.stop()
            }
            seenSessions = seenSessions.intersection(activeIds)
        } catch {
            // Silently ignore — network errors or unconfigured transport are expected
        }
    }
}

// MARK: - Ringback tone (caller and callee side)

/// Plays ringback tones for outbound calls (EU 425 Hz, 1 s on / 4 s off)
/// and incoming calls (double-ring: 0.4 s + 0.2 s gap + 0.4 s, then 2 s silence).
final class RingbackPlayer {
    static let shared = RingbackPlayer()

    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var isPlaying = false

    private init() {}

    /// - Parameter incoming: `true` for double-ring (callee side), `false` for outgoing ringback.
    func start(incoming: Bool = false) {
        guard !isPlaying else { return }
        isPlaying = true

        let eng = AVAudioEngine()
        let src = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        eng.attach(src)
        eng.connect(src, to: eng.mainMixerNode, format: format)

        guard let buf = incoming ? makeIncomingBuffer(format: format)
                                 : makeOutgoingBuffer(format: format) else {
            isPlaying = false; return
        }

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

    // MARK: - Buffer factories

    /// Outgoing ringback: 425 Hz, 1 s on / 4 s off
    private func makeOutgoingBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sr  = 44100.0
        let on  = Int(sr)
        let off = Int(sr * 4.0)
        return tone(freq: 425, onFrames: on, offFrames: off, sampleRate: sr, format: format, amp: 0.35)
    }

    /// Incoming double-ring: 0.4 s + 0.2 s gap + 0.4 s tone, then 2 s silence — 480 Hz
    private func makeIncomingBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sr      = 44100.0
        let ring    = Int(sr * 0.4)
        let gap     = Int(sr * 0.2)
        let silence = Int(sr * 2.0)
        let total   = ring + gap + ring + silence
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)) else { return nil }
        buf.frameLength = AVAudioFrameCount(total)
        let data = buf.floatChannelData![0]
        let freq = 480.0
        for i in 0..<ring {
            data[i] = Float(0.35 * sin(2 * .pi * freq * Double(i) / sr))
        }
        for i in ring..<(ring + gap) { data[i] = 0 }
        let offset = ring + gap
        for i in 0..<ring {
            data[offset + i] = Float(0.35 * sin(2 * .pi * freq * Double(i) / sr))
        }
        for i in (offset + ring)..<total { data[i] = 0 }
        return buf
    }

    private func tone(freq: Double, onFrames: Int, offFrames: Int,
                      sampleRate: Double, format: AVAudioFormat, amp: Double) -> AVAudioPCMBuffer? {
        let total = onFrames + offFrames
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)) else { return nil }
        buf.frameLength = AVAudioFrameCount(total)
        let data = buf.floatChannelData![0]
        for i in 0..<onFrames {
            data[i] = Float(amp * sin(2 * .pi * freq * Double(i) / sampleRate))
        }
        for i in onFrames..<total { data[i] = 0 }
        return buf
    }
}
