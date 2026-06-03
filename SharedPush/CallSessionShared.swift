import Foundation
import LiveKit
import Combine

/// Cross-platform call session that drives a LiveKit Room. Works on iOS,
/// iPadOS and macOS — the audio/video routing is handled by LiveKit.
@MainActor
public final class CallSessionShared: ObservableObject {
    public static let shared = CallSessionShared()

    @Published public private(set) var activeSessionId: String?
    @Published public private(set) var roomState: String = "disconnected"
    @Published public private(set) var participants: [String] = []
    @Published public private(set) var errorMessage: String?

    /// Provided by the target so the shared session can talk to the right backend.
    public var api: DevicePushAPI?

    private var room: Room?

    public func connect(toSessionId sessionId: String) async {
        await disconnectInternal()
        guard let api else {
            errorMessage = "Push API non configurata"
            return
        }
        do {
            guard let lk = try await api.mintLiveKitToken(sessionId: sessionId) else {
                throw NSError(domain: "perx.push", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "LiveKit token non disponibile"])
            }
            try? await api.acknowledgeSessionAction(sessionId: sessionId, actionType: "answer")

            let room = Room()
            self.room = room
            self.activeSessionId = sessionId
            self.roomState = "connecting"

            try await room.connect(
                url: lk.url,
                token: lk.token,
                roomOptions: RoomOptions(adaptiveStream: true, dynacast: true)
            )
            self.roomState = "connected"
            try await room.localParticipant.setMicrophone(enabled: true)
            refreshParticipants()

            // Watch for the other party leaving the room
            var hadRemote = false
            while self.activeSessionId != nil && room.connectionState != .disconnected {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let hasRemote = !room.remoteParticipants.isEmpty
                if hasRemote { hadRemote = true }
                if hadRemote && !hasRemote {
                    await endActive()
                    return
                }
                refreshParticipants()
            }
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await disconnectInternal()
        }
    }

    public func endActive() async {
        if let sid = activeSessionId, let api {
            _ = try? await api.acknowledgeSessionAction(sessionId: sid, actionType: "end")
        }
        await disconnectInternal()
    }

    private func disconnectInternal() async {
        if let room = room {
            await room.disconnect()
        }
        room = nil
        activeSessionId = nil
        roomState = "disconnected"
        participants = []
    }

    private func refreshParticipants() {
        guard let room = room else { participants = []; return }
        participants = room.remoteParticipants.values.map { rp in
            rp.name ?? rp.identity?.stringValue ?? "Partecipante"
        }
    }
}
