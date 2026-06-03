import SwiftUI

/// Schermata di videoperizia lato perito.
///
/// Stati UI:
///   - `loading`     → fetch iniziale sessione
///   - `lobby`       → assicurato in attesa, bottone "Avvia"
///   - `live`        → call in corso, bottoni Scatta / Termina
///   - `ended`       → sessione chiusa, ringraziamento
///   - `error`       → errore di rete/permission
///
/// **Setup richiesto in Xcode** prima del primo run:
///   1. Aggiungi il package https://github.com/livekit/client-sdk-swift come
///      Swift Package Dependency al target PerX (versione ≥ 2.0).
///   2. Sblocca le righe `#if canImport(LiveKit)` rimuovendo il marker quando
///      l'SDK è disponibile — vedi `LiveKitRoomStage` in fondo al file.
@MainActor
struct VideoperiziaCallView: View {
    let claimId: String
    let claimReferenceLabel: String

    @State private var session: VideoperiziaSessionDTO?
    @State private var token: VideoperiziaTokenDTO?
    @State private var phase: Phase = .loading
    @State private var errorMessage: String?
    @State private var isStarting = false
    @State private var isEnding = false

    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable {
        case loading, lobby, live, ended, error
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                content
            }
            .navigationTitle("Videoperizia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .task { await bootstrap() }
            .onChange(of: phase) { _, newValue in
                if newValue == .lobby || newValue == .live {
                    startPolling()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 20) {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            switch phase {
            case .loading:
                ProgressView("Caricamento sessione…")
            case .lobby:
                lobbyContent
            case .live:
                liveContent
            case .ended:
                endedContent
            case .error:
                Button("Riprova") { Task { await bootstrap() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Phases

    private var lobbyContent: some View {
        VStack(spacing: 16) {
            Image(systemName: session?.isLobbyOpen == true ? "person.crop.circle.badge.checkmark" : "hourglass")
                .resizable().scaledToFit().frame(width: 80, height: 80)
                .foregroundStyle(.tint)
            Text(session?.isLobbyOpen == true
                 ? "L'assicurato è in attesa nella sala."
                 : "Stiamo aspettando che l'assicurato apra la sala dal portale.")
                .multilineTextAlignment(.center)
            Text("Sinistro: \(claimReferenceLabel)")
                .font(.footnote).foregroundStyle(.secondary)
            Button {
                Task { await startCall() }
            } label: {
                if isStarting {
                    ProgressView()
                } else {
                    Label("Avvia videoperizia", systemImage: "video.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(session?.isLobbyOpen != true || isStarting)
        }
    }

    private var liveContent: some View {
        VStack(spacing: 12) {
            if let token {
                LiveKitRoomStage(token: token)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Preparazione videochiamata…")
            }
            HStack(spacing: 12) {
                Button(role: .destructive) {
                    Task { await endCall() }
                } label: {
                    if isEnding {
                        ProgressView()
                    } else {
                        Label("Termina", systemImage: "phone.down.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isEnding)
            }
        }
    }

    private var endedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .resizable().scaledToFit().frame(width: 80, height: 80)
                .foregroundStyle(.green)
            Text("Videoperizia terminata.")
                .font(.headline)
            Text("Il sinistro è passato in 'Da gestire (video)'.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Chiudi") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Networking

    private func bootstrap() async {
        phase = .loading
        errorMessage = nil
        do {
            let session = try await VideoperiziaService.shared.createOrFetchSession(claimId: claimId)
            self.session = session
            let token = try await VideoperiziaService.shared.mintPeritoToken(
                claimId: claimId, sessionId: session.id
            )
            self.token = token
            self.phase = mapPhase(from: session)
        } catch {
            errorMessage = error.localizedDescription
            phase = .error
        }
    }

    private func startCall() async {
        guard let session else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let updated = try await VideoperiziaService.shared.start(
                claimId: claimId, sessionId: session.id
            )
            self.session = updated
            self.phase = mapPhase(from: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func endCall() async {
        guard let session else { return }
        isEnding = true
        defer { isEnding = false }
        do {
            let updated = try await VideoperiziaService.shared.end(
                claimId: claimId, sessionId: session.id, reason: nil
            )
            self.session = updated
            self.phase = .ended
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() {
        // Polling leggero per intercettare lobby_open → live e ended dal server.
        Task {
            while !Task.isCancelled, phase == .lobby || phase == .live {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let session else { return }
                if let next = try? await VideoperiziaService.shared.fetchSession(
                    claimId: claimId, sessionId: session.id
                ) {
                    self.session = next
                    self.phase = mapPhase(from: next)
                    if next.isClosed { return }
                }
            }
        }
    }

    private func mapPhase(from session: VideoperiziaSessionDTO) -> Phase {
        if session.isClosed { return .ended }
        if session.isLive { return .live }
        return .lobby
    }
}

// MARK: - LiveKit room stage

/// Wrapper attorno alla LiveKit Room. Quando aggiungerai il package
/// `client-sdk-swift` al target, sblocca la sezione `#if canImport(LiveKit)`
/// e cancella il placeholder.
private struct LiveKitRoomStage: View {
    let token: VideoperiziaTokenDTO

    var body: some View {
        // Placeholder finché il package LiveKit non è linkato al target.
        // Quando il package è disponibile, sostituisci con un componente che
        // istanzia `Room()`, fa connect(url:token:), e renderizza i remote
        // video track in un VideoView. Vedi:
        //   https://docs.livekit.io/client-sdk-swift/
        VStack(spacing: 8) {
            Image(systemName: "video.circle.fill")
                .resizable().scaledToFit().frame(width: 64, height: 64)
                .foregroundStyle(.tint)
            Text("Videocall pronta")
                .font(.headline)
            Text("Aggiungi il pacchetto LiveKit Swift al target per renderizzare lo stream.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text(token.room_name)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}
