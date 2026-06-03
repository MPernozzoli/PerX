#if canImport(CallKit) && !os(macOS)
import Foundation
import CallKit
import AVFAudio
#if canImport(UIKit)
import UIKit
#endif

/// iOS/iPadOS only. Bridges VoIP pushes to the native CallKit UI.
/// Mac uses `MacCallNotifier` instead.
@MainActor
public final class CallProviderShared: NSObject {
    public static let shared = CallProviderShared()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var activeSessions: [UUID: String] = [:]

    /// Called when the user answers from CallKit. Receiver should connect LiveKit
    /// and call `markActive` if needed.
    public var onAnswer: ((String) async -> Void)?
    /// Called when the user hangs up from CallKit.
    public var onEnd: ((String) async -> Void)?

    private override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.phoneNumber, .generic]
        config.includesCallsInRecents = true
#if canImport(UIKit)
        if let icon = UIImage(named: "AppIcon") {
            config.iconTemplateImageData = icon.pngData()
        }
#endif
        self.provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    public func reportIncomingCall(_ payload: IncomingCallPayload, completion: @escaping (Error?) -> Void) {
        let uuid = UUID()
        activeSessions[uuid] = payload.sessionId

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(
            type: payload.callerHandle.isEmpty ? .generic : .phoneNumber,
            value: payload.callerHandle.isEmpty ? payload.callerName : payload.callerHandle
        )
        update.localizedCallerName = payload.callerName
        update.hasVideo = payload.hasVideo
        update.supportsDTMF = false
        update.supportsHolding = true
        update.supportsGrouping = false
        update.supportsUngrouping = false

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if error != nil { self?.activeSessions.removeValue(forKey: uuid) }
            completion(error)
        }
    }

    public func endActive() {
        for uuid in activeSessions.keys {
            let transaction = CXTransaction(action: CXEndCallAction(call: uuid))
            callController.request(transaction) { _ in }
        }
    }
}

extension CallProviderShared: CXProviderDelegate {
    nonisolated public func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in self.activeSessions.removeAll() }
    }

    nonisolated public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in
            if let sid = self.activeSessions[action.callUUID], let cb = self.onAnswer {
                await cb(sid)
            }
            action.fulfill()
        }
    }

    nonisolated public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            let sid = self.activeSessions.removeValue(forKey: action.callUUID)
            if let sid = sid, let cb = self.onEnd { await cb(sid) }
            action.fulfill()
        }
    }

    nonisolated public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // LiveKit consumes the active AVAudioSession automatically.
    }

    nonisolated public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}
}
#endif
