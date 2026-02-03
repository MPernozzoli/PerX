import SwiftUI

// MARK: - Closure Result Sheet

struct ClosureResultSheet: View {
    let result: ClosureFilesService.ClosureResult
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: result.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(result.errors.isEmpty ? .green : .orange)
                    .font(.title)
                
                Text(result.errors.isEmpty ? "File generati con successo" : "Generazione completata con avvisi")
                    .font(.headline)
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !result.generatedFiles.isEmpty {
                        Text("File generati:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        ForEach(result.generatedFiles, id: \.path) { url in
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.blue)
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                Spacer()
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                } label: {
                                    Image(systemName: "arrow.right.circle")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    
                    if !result.errors.isEmpty {
                        Text("Errori:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        
                        ForEach(result.errors, id: \.self) { error in
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    if !result.skippedFiles.isEmpty {
                        Text("File saltati:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        
                        ForEach(result.skippedFiles, id: \.self) { file in
                            Text("• \(file)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Button("Chiudi") {
                dismiss()
            }
            .keyboardShortcut(.return)
        }
        .padding()
        .frame(width: 400, height: 400)
    }
}
