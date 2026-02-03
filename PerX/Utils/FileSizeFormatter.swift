import Foundation

/// Utility centralizzata per la formattazione delle dimensioni dei file.
/// Sostituisce le 5 implementazioni duplicate nel codebase.
enum FileSizeFormatter {
    
    /// ByteCountFormatter condiviso
    private static let formatter: ByteCountFormatter = {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf
    }()
    
    /// ByteCountFormatter per KB/MB
    private static let kbMbFormatter: ByteCountFormatter = {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useKB, .useMB]
        bcf.countStyle = .file
        return bcf
    }()
    
    /// Formatta la dimensione del file in modo leggibile (auto-seleziona unità).
    /// - Parameter bytes: Dimensione in bytes (Int)
    /// - Returns: Stringa formattata (es. "1.2 MB")
    static func format(_ bytes: Int) -> String {
        formatter.string(fromByteCount: Int64(bytes))
    }
    
    /// Formatta la dimensione del file in modo leggibile (auto-seleziona unità).
    /// - Parameter bytes: Dimensione in bytes (Int64)
    /// - Returns: Stringa formattata (es. "1.2 MB")
    static func format(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
    
    /// Formatta la dimensione del file usando solo KB o MB.
    /// - Parameter bytes: Dimensione in bytes (Int)
    /// - Returns: Stringa formattata (es. "1.2 MB")
    static func formatKBMB(_ bytes: Int) -> String {
        kbMbFormatter.string(fromByteCount: Int64(bytes))
    }
    
    /// Formatta la dimensione del file usando solo KB o MB.
    /// - Parameter bytes: Dimensione in bytes (Int64)
    /// - Returns: Stringa formattata (es. "1.2 MB")
    static func formatKBMB(_ bytes: Int64) -> String {
        kbMbFormatter.string(fromByteCount: bytes)
    }
    
    /// Formatta la dimensione di un file dato il suo URL.
    /// - Parameter url: URL del file
    /// - Returns: Stringa formattata o "—" se non disponibile
    static func format(fileAt url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            return "—"
        }
        return format(fileSize)
    }
}

// MARK: - Aliases per backward compatibility

/// Alias per EmailHelpers compatibility
func formattedFileSize(_ size: Int) -> String {
    FileSizeFormatter.format(size)
}
