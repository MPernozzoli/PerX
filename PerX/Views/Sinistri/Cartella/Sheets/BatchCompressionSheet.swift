import SwiftUI

// MARK: - Batch Compression Sheet

struct BatchCompressionSheet: View {
    let files: [FileService.FileItem]
    @Environment(\.dismiss) private var dismiss
    @State private var compressionQuality: Double = 0.7
    @State private var isCompressing = false
    @State private var compressionMessage: String = ""
    @State private var compressedCount = 0
    
    private let editorService = MediaEditorService.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Comprimi File")
                .font(.headline)
            
            Text("\(files.count) file selezionato\(files.count == 1 ? "" : "i")")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Qualità: \(Int(compressionQuality * 100))%")
                    .font(.subheadline)
                
                Slider(value: $compressionQuality, in: 0.1...1.0)
                
                Text("Qualità più bassa = file più piccolo")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if isCompressing {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Compressione in corso... \(compressedCount)/\(files.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if !compressionMessage.isEmpty {
                Text(compressionMessage)
                    .font(.caption)
                    .foregroundColor(compressionMessage.contains("successo") ? .green : .red)
            }
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                .disabled(isCompressing)
                
                Button("Comprimi") {
                    compressFiles()
                }
                .disabled(isCompressing)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    private func compressFiles() {
        isCompressing = true
        compressedCount = 0
        compressionMessage = ""
        
        let quality = CGFloat(compressionQuality)
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
        
        for file in files {
            let ext = file.url.pathExtension.lowercased()
            
            if imageExtensions.contains(ext) {
                editorService.compressImage(at: file.url, quality: quality) { success in
                    DispatchQueue.main.async {
                        compressedCount += 1
                        if compressedCount == files.count {
                            isCompressing = false
                            compressionMessage = "Compressione completata: \(compressedCount)/\(files.count) file"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                dismiss()
                            }
                        }
                    }
                }
            } else if ext == "pdf" {
                editorService.compressPDF(at: file.url, quality: quality) { success in
                    DispatchQueue.main.async {
                        compressedCount += 1
                        if compressedCount == files.count {
                            isCompressing = false
                            compressionMessage = "Compressione completata: \(compressedCount)/\(files.count) file"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                dismiss()
                            }
                        }
                    }
                }
            } else {
                compressedCount += 1
                if compressedCount == files.count {
                    isCompressing = false
                    compressionMessage = "Alcuni file non supportano la compressione"
                }
            }
        }
    }
}
