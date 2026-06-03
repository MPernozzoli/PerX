import Foundation
import CallKit
import AVFAudio
import UIKit

@MainActor
final class CallProvider: NSObject {
    static let shared = CallProvider()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var activeSessions: [UUID: String] = [:]  // uuid → backend session_id

    private override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.phoneNumber, .generic]
        if let icon = UIImage(named: "AppIcon") {
            config.iconTemplateImageData = icon.pngData()
        }
        config.includesCallsInRecents = true
        self.provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    func reportIncomingCall(
        sessionId: String,
        callerName: String,
        callerHandle: String,
        hasVideo: Bool,
        completion: @escaping (Error?) -> Void
    ) {
        let uuid = UUID()
        activeSessions[uuid] = sessionId

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(
            type: callerHandle.isEmpty ? .generic : .phoneNumber,
            value: callerHandle.isEmpty ? callerName : callerHandle
        )
        update.localizedCallerName = callerName
        update.hasVideo = hasVideo
        update.supportsDTMF = false
        update.supportsHolding = true
        update.supportsGrouping = false
        update.supportsUngrouping = false

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error = error {
                self?.activeSessions.removeValue(forKey: uuid)
            }
            completion(error)
        }
    }

    func endCall(uuid: UUID) {
        let action = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: action)
        callController.request(transaction) { _ in }
    }
}

extension CallProvider: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in self.activeSessions.removeAll() }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in
            let sessionId = self.activeSessions[action.callUUID]
            NotificationCenter.default.post(
                name: .perxCallAnswered,
                object: nil,
                userInfo: ["session_id": sessionId ?? ""]
            )
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            let sessionId = self.activeSessions.removeValue(forKey: action.callUUID)
            NotificationCenter.default.post(
                name: .perxCallEnded,
                object: nil,
                userInfo: ["session_id": sessionId ?? ""]
            )
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // LiveKit audio engine should start here once wired in.
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}
}

extension Notification.Name {
    static let perxCallAnswered = Notification.Name("perxCallAnswered")
    static let perxCallEnded = Notification.Name("perxCallEnded")
}
