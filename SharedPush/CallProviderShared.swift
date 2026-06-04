#if canImport(CallKit) && !os(macOS)
import Foundation
import CallKit
import AVFAudio
import os.log
#if canImport(UIKit)
import UIKit
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "perx", category: "CallKit")

/// iOS/iPadOS only. Bridges VoIP pushes to the native CallKit UI.
/// Mac uses `MacCallNotifier` instead.
///
/// NOT @MainActor — CXProvider is thread-safe and PushKit callbacks arrive on
/// background queues. `activeSessions` is protected by `sessionsLock`.
public final class CallProviderShared: NSObject {
    public static let shared = CallProviderShared()

    private let provider: CXProvider
    private let callController = CXCallController()
    private let sessionsLock = NSLock()
    private var activeSessions: [UUID: String] = [:]

    /// Called when the user answers from CallKit. Invoked on @MainActor.
    public var onAnswer: ((String) async -> Void)?
    /// Called when the user hangs up from CallKit. Invoked on @MainActor.
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
        // nil queue → CXProvider uses its own internal serial queue
        provider.setDelegate(self, queue: nil)
    }

    /// Thread-safe. Safe to call directly from PushKit delegate (background queue).
    public func reportIncomingCall(_ payload: IncomingCallPayload, completion: @escaping (Error?) -> Void) {
        let uuid = UUID()
        sessionsLock.lock()
        activeSessions[uuid] = payload.sessionId
        sessionsLock.unlock()

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
            if let error {
                logger.error("reportNewIncomingCall failed: \(error.localizedDescription)")
                self?.sessionsLock.withLock { self?.activeSessions.removeValue(forKey: uuid) }
            } else {
                logger.info("CallKit incoming call reported, uuid=\(uuid), session=\(payload.sessionId)")
            }
            completion(error)
        }
    }

    public func endActive() {
        sessionsLock.lock()
        let keys = Array(activeSessions.keys)
        sessionsLock.unlock()
        for uuid in keys {
            let transaction = CXTransaction(action: CXEndCallAction(call: uuid))
            callController.request(transaction) { _ in }
        }
    }

    /// End the CallKit call associated with a specific session ID.
    /// Used to dismiss a stale incoming-call UI when the session has already ended on the backend.
    public func endCall(forSession sessionId: String) {
        sessionsLock.lock()
        let uuid = activeSessions.first(where: { $0.value == sessionId })?.key
        sessionsLock.unlock()
        guard let uuid else { return }
        let transaction = CXTransaction(action: CXEndCallAction(call: uuid))
        callController.request(transaction) { error in
            if let error {
                logger.warning("endCall(forSession:) failed: \(error.localizedDescription)")
            }
        }
    }
}

extension CallProviderShared: CXProviderDelegate {
    public func providerDidReset(_ provider: CXProvider) {
        sessionsLock.withLock { activeSessions.removeAll() }
    }

    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let sid: String? = sessionsLock.withLock { activeSessions[action.callUUID] }
        action.fulfill()
        guard let sid else { return }
        Task { @MainActor in await self.onAnswer?(sid) }
    }

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let sid: String? = sessionsLock.withLock { activeSessions.removeValue(forKey: action.callUUID) }
        action.fulfill()
        guard let sid else { return }
        Task { @MainActor in await self.onEnd?(sid) }
    }

    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // LiveKit consumes the active AVAudioSession automatically.
    }

    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}
}
#endif
