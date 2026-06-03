import Foundation
import LiveKit
import AVFAudio
import Combine

@MainActor
final class CallSessionService: ObservableObject {
    static let shared = CallSessionService()

    @Published private(set) var activeSessionId: String?
    @Published private(set) var roomState: String = "disconnected"
    @Published private(set) var participants: [String] = []
    @Published private(set) var errorMessage: String?

    private var room: Room?

    func connect(toSessionId sessionId: String) async {
        await disconnectInternal()
        do {
            // 1) Mint LiveKit token from backend for this session
            let body = EmptyEncodable()
            let token: LiveKitTokenDTO = try await APIClient.shared.post(
                "/api/v1/communications/sessions/\(sessionId)/livekit-token",
                body: body
            )

            // 2) Confirm answer to backend (lifecycle bookkeeping)
            _ = try? await acknowledge(sessionId: sessionId, action: "answer")

            // 3) Connect to LiveKit room
            let room = Room()
            self.room = room
            self.activeSessionId = sessionId
            self.roomState = "connecting"

            let roomOptions = RoomOptions(
                adaptiveStream: true,
                dynacast: true
            )
            try await room.connect(
                url: token.livekit_url,
                token: token.token,
                roomOptions: roomOptions
            )
            self.roomState = "connected"

            // 4) Publish microphone — CallKit has already activated AVAudioSession
            try await room.localParticipant.setMicrophone(enabled: true)

            refreshParticipants()
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await disconnectInternal()
        }
    }

    func endActive() async {
        if let sid = activeSessionId {
            _ = try? await acknowledge(sessionId: sid, action: "end")
        }
        await disconnectInternal()
    }

    private func disconnectInternal() async {
        if let room = room {
            await room.disconnect()
        }
        self.room = nil
        self.activeSessionId = nil
        self.roomState = "disconnected"
        self.participants = []
    }

    private func refreshParticipants() {
        guard let room = room else { participants = []; return }
        participants = room.remoteParticipants.values.map { rp in
            rp.name ?? rp.identity?.stringValue ?? "Partecipante"
        }
    }

    // MARK: - Session lifecycle ack to backend

    private struct EmptyEncodable: Encodable {}
    private struct SessionActionResponse: Decodable {
        let session_id: String?
        let state: String?
    }

    private func acknowledge(sessionId: String, action: String) async throws -> SessionActionResponse {
        let payload = CallSessionAction(action_type: action)
        return try await APIClient.shared.post(
            "/api/v1/communications/sessions/\(sessionId)/actions",
            body: payload
        )
    }
}
