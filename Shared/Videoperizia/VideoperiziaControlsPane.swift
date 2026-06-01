import SwiftUI

/// Controlli operativi della videoperizia.
///   - locali perito: mic on/off, camera on/off
///   - remoti verso assicurato: switch camera frontale/posteriore, flash request
///   - cattura: scatta foto / registra clip (frame-grab arriva nel 5d)
@MainActor
struct VideoperiziaControlsPane: View {
    let claimId: String
    @ObservedObject var model: VideoperiziaTabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Controlli").font(.headline)

            Group {
                Text("Locale perito").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Toggle(isOn: $model.isLocalMicrophoneEnabled) {
                        Label("Microfono", systemImage: model.isLocalMicrophoneEnabled ? "mic.fill" : "mic.slash.fill")
                    }
                    .toggleStyle(.button)
                    Toggle(isOn: $model.isLocalCameraEnabled) {
                        Label("Camera", systemImage: model.isLocalCameraEnabled ? "video.fill" : "video.slash.fill")
                    }
                    .toggleStyle(.button)
                }
            }

            Divider()

            Group {
                Text("Remoto (assicurato)").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        Task { await model.requestCameraFlip() }
                    } label: {
                        Label("Inverti camera", systemImage: "arrow.triangle.2.circlepath.camera")
                    }
                    Button {
                        Task { await model.requestFlash(turnOn: true) }
                    } label: {
                        Label("Flash", systemImage: "bolt.fill")
                    }
                }
            }

            Divider()

            Group {
                Text("Cattura").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        Task { await model.captureAndUploadPhoto(claimId: claimId) }
                    } label: {
                        if model.isCapturingPhoto {
                            ProgressView()
                        } else {
                            Label("Scatta foto", systemImage: "camera.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isCapturingPhoto)
                    Button {
                        // Registrazione clip: arriva in un commit successivo con
                        // un VideoRecorder che salva H264 lato perito.
                    } label: {
                        Label("Registra clip", systemImage: "record.circle")
                    }
                    .disabled(true)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.windowBackgroundColorCompat))
    }
}

private extension Color {
    static var windowBackgroundColorCompat: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}
