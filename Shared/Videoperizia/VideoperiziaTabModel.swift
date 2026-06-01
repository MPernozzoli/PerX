import Foundation
import Combine
import CoreLocation
import SwiftUI

/// Modello di stato della sub-tab Videoperizia.
/// Aggrega: sessione corrente, galleria, ultima posizione GPS dell'assicurato,
/// e flag di controllo locale (mic/camera) e remoto (richieste outbound).
@MainActor
final class VideoperiziaTabModel: ObservableObject {
    // Sessione
    @Published private(set) var session: VideoperiziaSessionDTO?
    @Published var errorMessage: String?

    // Media
    @Published private(set) var media: [VideoperiziaMediaDTO] = []

    // Posizione live (ultima GPS ricevuta dall'assicurato)
    @Published private(set) var lastInsuredCoordinate: CLLocationCoordinate2D?
    @Published private(set) var lastPingAccuracyMeters: Double?

    // Controlli locali perito (UI binding). I didSet propagano al Room
    // tramite le closure registrate da LiveKitRoomStage al connect.
    @Published var isLocalMicrophoneEnabled: Bool = true {
        didSet {
            guard oldValue != isLocalMicrophoneEnabled else { return }
            let target = isLocalMicrophoneEnabled
            Task { await liveKitSetMicrophone?(target) }
        }
    }
    @Published var isLocalCameraEnabled: Bool = true {
        didSet {
            guard oldValue != isLocalCameraEnabled else { return }
            let target = isLocalCameraEnabled
            Task { await liveKitSetCamera?(target) }
        }
    }

    // Bridge LiveKit. Riempite da `bindLiveKitRoom` quando la Room è connessa,
    // azzerate da `unbindLiveKitRoom` allo smontaggio della view.
    private var liveKitPublishData: ((Data) async -> Void)?
    private var liveKitSetCamera: ((Bool) async -> Void)?
    private var liveKitSetMicrophone: ((Bool) async -> Void)?
    /// Sync, eseguito sul main per coerenza con SwiftUI; il pixel buffer è
    /// piccolo e l'estrazione JPEG non blocca percettibilmente.
    private var liveKitCaptureFrameJPEG: (() -> Data?)?

    // Stato cattura corrente (mostrato dalla UI)
    @Published private(set) var isCapturingPhoto = false

    // Polling task
    private var pollingTask: Task<Void, Never>?

    func bootstrap(claimId: String) async {
        do {
            let session = try await VideoperiziaService.shared.createOrFetchSession(claimId: claimId)
            self.session = session
            await refreshSidePanel(claimId: claimId, sessionId: session.id)
            startPolling(claimId: claimId, sessionId: session.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func startPolling(claimId: String, sessionId: String) {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.refreshSidePanel(claimId: claimId, sessionId: sessionId)
            }
        }
    }

    func refreshSidePanel(claimId: String, sessionId: String) async {
        async let mediaTask = try? await VideoperiziaService.shared.listMedia(
            claimId: claimId, sessionId: sessionId
        )
        async let pingsTask = try? await VideoperiziaService.shared.listLocationPings(
            claimId: claimId, sessionId: sessionId
        )
        let (media, pings) = await (mediaTask, pingsTask)
        if let media { self.media = media }
        if let last = pings?.last {
            self.lastInsuredCoordinate = CLLocationCoordinate2D(
                latitude: last.latitude, longitude: last.longitude
            )
            self.lastPingAccuracyMeters = last.accuracy_m
        }
    }

    /// Distanza in metri fra l'ultima posizione GPS conosciuta e l'indirizzo
    /// del sinistro. Nil se manca uno dei due.
    func distanceFromAddress(_ coordinate: CLLocationCoordinate2D?) -> Double? {
        guard let coordinate, let insured = lastInsuredCoordinate else { return nil }
        let a = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let b = CLLocation(latitude: insured.latitude, longitude: insured.longitude)
        return a.distance(from: b)
    }

    // MARK: - Comandi remoti (data channel)
    //
    // Quando aggiungerai il pacchetto LiveKit Swift, sostituisci la stub con:
    //   try await room.localParticipant.publishData(data, reliable: true)

    func requestCameraFlip() async {
        await sendRemote(.cameraFlip)
    }

    func requestFlash(turnOn: Bool) async {
        await sendRemote(.flashRequest(turnOn: turnOn))
    }

    func notifyCaptureImminent() async {
        await sendRemote(.captureNotice)
    }

    private func sendRemote(_ command: VideoperiziaRemoteCommand) async {
        do {
            let data = try command.encode()
            if let publisher = liveKitPublishData {
                await publisher(data)
            } else {
                // Room non ancora connessa: niente da fare, l'utente vedrà il
                // bottone abilitato comunque ma il messaggio andrà perso. Il
                // log resta utile per il debug in dev.
                print("[Videoperizia] no LiveKit room bound; dropping command type=\(command.type)")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - LiveKit bridge

    /// Chiamato da `LiveKitRoomStage` quando la Room è pronta. Le closure
    /// catturano la Room ma il model non importa LiveKit direttamente,
    /// così resta neutrale rispetto al package.
    func bindLiveKitRoom(
        publishData: @escaping (Data) async -> Void,
        setCamera: @escaping (Bool) async -> Void,
        setMicrophone: @escaping (Bool) async -> Void,
        captureFrameJPEG: @escaping () -> Data?
    ) {
        self.liveKitPublishData = publishData
        self.liveKitSetCamera = setCamera
        self.liveKitSetMicrophone = setMicrophone
        self.liveKitCaptureFrameJPEG = captureFrameJPEG
    }

    func unbindLiveKitRoom() {
        self.liveKitPublishData = nil
        self.liveKitSetCamera = nil
        self.liveKitSetMicrophone = nil
        self.liveKitCaptureFrameJPEG = nil
    }

    // MARK: - Capture foto

    /// Cattura un frame del remote video, lo carica al backend (che salva su
    /// Supabase e accoda il job perxHUB), poi rinfresca la galleria.
    func captureAndUploadPhoto(claimId: String) async {
        guard let session, let capture = liveKitCaptureFrameJPEG else {
            errorMessage = "Videoperizia non attiva."
            return
        }
        isCapturingPhoto = true
        defer { isCapturingPhoto = false }

        // Preavviso peer-to-peer: l'assicurato vede "il perito sta scattando"
        await sendRemote(.captureNotice)

        guard let jpegData = capture(), !jpegData.isEmpty else {
            errorMessage = "Nessun frame video disponibile."
            return
        }

        let fileName = "frame-\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            _ = try await VideoperiziaService.shared.uploadMedia(
                claimId: claimId,
                sessionId: session.id,
                kind: "frame",
                data: jpegData,
                fileName: fileName,
                mimeType: "image/jpeg"
            )
            await refreshSidePanel(claimId: claimId, sessionId: session.id)
        } catch {
            errorMessage = "Upload foto fallito: \(error.localizedDescription)"
        }
    }
}
