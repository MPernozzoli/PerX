import SwiftUI

struct CommunicationLiveKitCallView: View {
    let token: CommunicationLiveKitToken
    let displayName: String
    var onHangup: () -> Void

    var body: some View {
        CommunicationLiveKitStage(token: token, displayName: displayName, onHangup: onHangup)
            .frame(minWidth: 360, minHeight: 280)
    }
}

#if canImport(LiveKit)
import LiveKit

private struct CommunicationLiveKitStage: View {
    let token: CommunicationLiveKitToken
    let displayName: String
    var onHangup: () -> Void

    @StateObject private var room = Room()
    @State private var connectionState = "Connessione..."
    @State private var muted = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "phone.connection.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            VStack(spacing: 4) {
                Text(displayName)
                    .font(.title2.bold())
                Text(connectionState)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(token.roomName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 14) {
                Button {
                    muted.toggle()
                    Task { try? await room.localParticipant.setMicrophone(enabled: !muted) }
                } label: {
                    Label(muted ? "Riattiva" : "Mute", systemImage: muted ? "mic.slash.fill" : "mic.fill")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    Task { await room.disconnect() }
                    onHangup()
                } label: {
                    Label("Termina", systemImage: "phone.down.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .task {
            do {
                try await room.connect(url: token.livekitUrl, token: token.token)
                try? await room.localParticipant.setMicrophone(enabled: true)
                connectionState = "In chiamata PerX"
                // Wait for at least one remote participant to confirm the call is live,
                // then watch for them leaving (other party hung up).
                var hadRemote = false
                while room.connectionState != .disconnected {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    let hasRemote = !room.remoteParticipants.isEmpty
                    if hasRemote { hadRemote = true }
                    if hadRemote && !hasRemote {
                        // Remote participant was present and just left → hang up our side
                        Task { await room.disconnect() }
                        onHangup()
                        return
                    }
                }
                // Room disconnected externally
                onHangup()
            } catch {
                connectionState = "Connessione LiveKit non riuscita"
                print("[Communication] LiveKit connect failed: \(error)")
            }
        }
        .onDisappear {
            Task { await room.disconnect() }
        }
    }
}
#else
private struct CommunicationLiveKitStage: View {
    let token: CommunicationLiveKitToken
    let displayName: String
    var onHangup: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "phone.connection")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("LiveKit non disponibile per questo target")
                .font(.headline)
            Text(token.roomName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Chiudi", action: onHangup)
        }
        .padding()
    }
}
#endif
