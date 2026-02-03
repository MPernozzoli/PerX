import Foundation
import Combine

/// Traccia lo stato di download dei file
@MainActor
class FileDownloadTracker: ObservableObject {
    static let shared = FileDownloadTracker()
    
    /// Path relativo -> stato di download
    @Published private(set) var downloadingFiles: [String: DownloadState] = [:]
    
    private init() {}
    
    enum DownloadState: Equatable {
        case downloading(progress: Double)
        case completed
    }
    
    /// Registra l'inizio di un download
    func startDownload(relativePath: String) {
        downloadingFiles[relativePath] = .downloading(progress: 0.0)
    }
    
    /// Aggiorna il progresso di un download
    func updateProgress(relativePath: String, progress: Double) {
        downloadingFiles[relativePath] = .downloading(progress: progress)
    }
    
    /// Registra il completamento di un download
    func completeDownload(relativePath: String) {
        downloadingFiles[relativePath] = .completed
        // Rimuovi dopo un breve delay per permettere alla UI di aggiornarsi
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 secondi
            downloadingFiles.removeValue(forKey: relativePath)
        }
    }
    
    /// Verifica se un file è in download
    func isDownloading(relativePath: String) -> Bool {
        if case .downloading = downloadingFiles[relativePath] {
            return true
        }
        return false
    }
    
    /// Ottiene il progresso di download (0.0-1.0) o nil se non in download
    func getProgress(relativePath: String) -> Double? {
        if case .downloading(let progress) = downloadingFiles[relativePath] {
            return progress
        }
        return nil
    }
}
