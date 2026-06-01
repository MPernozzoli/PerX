import Foundation
import CoreVideo
import CoreImage

#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if canImport(LiveKit)
import LiveKit

/// Renderer LiveKit silenzioso che memorizza l'ultimo frame ricevuto sotto
/// forma di `CVPixelBuffer`. Allegato al `RemoteVideoTrack` dell'assicurato,
/// permette di estrarre uno snapshot ad alta risoluzione on-demand quando il
/// perito preme "Scatta foto" — senza fermare lo stream video in corso.
final class VideoperiziaFrameGrabber: NSObject, VideoRenderer {
    private let lock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?

    /// `VideoRenderer` richiede questi due getter; per l'estrazione frame
    /// non ci serve adaptive streaming ed evitiamo richieste di resize.
    @MainActor var isAdaptiveStreamEnabled: Bool { false }
    @MainActor var adaptiveStreamSize: CGSize { .zero }

    func set(size _: CGSize) { /* no-op */ }

    func render(frame: VideoFrame) {
        guard let buffer = frame.toCVPixelBuffer() else { return }
        lock.lock()
        latestPixelBuffer = buffer
        lock.unlock()
    }

    /// JPEG dell'ultimo frame ricevuto, oppure `nil` se non sono ancora
    /// arrivati frame dal remote track.
    /// - Parameter quality: 0.0 - 1.0, default 0.85 (buon compromesso per
    ///   ispezioni: l'utente vede dettaglio senza sprecare banda).
    func snapshotJPEG(quality: CGFloat = 0.85) -> Data? {
        lock.lock()
        let buffer = latestPixelBuffer
        lock.unlock()
        guard let buffer else { return nil }

        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        #if os(macOS)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #else
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
        #endif
    }
}
#endif
