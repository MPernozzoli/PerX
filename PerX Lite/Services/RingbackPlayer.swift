import AVFoundation

final class RingbackPlayer {
    static let shared = RingbackPlayer()

    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var isPlaying = false

    private init() {}

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

    private func makeOutgoingBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sr  = 44100.0
        let on  = Int(sr)
        let off = Int(sr * 4.0)
        return tone(freq: 425, onFrames: on, offFrames: off, sampleRate: sr, format: format, amp: 0.35)
    }

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
