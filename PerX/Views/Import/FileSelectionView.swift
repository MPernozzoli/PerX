import SwiftUI
import UniformTypeIdentifiers

struct FileSelectionView: View {
    @Binding var selectedFileURL: URL?
    let onFileSelected: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("Seleziona il file da importare")
                .font(.title3)
            
            Text("Puoi importare dati da file CSV o Excel (.xlsx).")
                .foregroundColor(.secondary)
            
            if let url = selectedFileURL {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.blue)
                    Text(url.lastPathComponent)
                    
                    Button {
                        selectedFileURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            
            HStack(spacing: 16) {
                Button("Sfoglia...") {
                    openFilePicker()
                }
                
                if selectedFileURL != nil {
                    Button("Avanti") {
                        onFileSelected()
                    }
                    .keyboardShortcut(.return)
                }
            }
        }
        .padding(40)
    }
    
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType.commaSeparatedText,
            UTType(filenameExtension: "xlsx")!
        ]
        
        if panel.runModal() == .OK {
            selectedFileURL = panel.url
        }
    }
} 