import SwiftUI

// MARK: - Version Recovery View

struct VersionRecoveryView: View {
    let fileURL: URL
    let sinistroPath: String
    let onRecover: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var versioningService = FileVersioningService.shared
    @State private var versions: [FileVersion] = []
    @State private var selectedVersion: FileVersion?
    @State private var isRecovering = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recupera Versione")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(versions) { version in
                        VersionRow(
                            version: version,
                            isSelected: selectedVersion?.id == version.id,
                            onSelect: {
                                selectedVersion = version
                            }
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                Text("Seleziona una versione da recuperare")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Annulla") {
                    dismiss()
                }
                
                Button("Recupera") {
                    recoverVersion()
                }
                .disabled(selectedVersion == nil || isRecovering)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .onAppear {
            loadVersions()
        }
    }
    
    private func loadVersions() {
        versions = versioningService.getVersions(for: fileURL, in: sinistroPath)
    }
    
    private func recoverVersion() {
        guard let version = selectedVersion else { return }
        isRecovering = true
        
        let success = versioningService.restoreVersion(version, to: fileURL)
        if success {
            onRecover()
            dismiss()
        }
        isRecovering = false
    }
}

// MARK: - Version Row

struct VersionRow: View {
    let version: FileVersion
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(version.formattedDate)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Text(version.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
