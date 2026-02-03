import SwiftUI
import UniformTypeIdentifiers

struct ComposeEmailAttachment: Identifiable {
    let id: UUID
    let url: URL
    let filename: String
    let size: Int64
    
    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.filename = url.lastPathComponent
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            self.size = fileSize
        } else {
            self.size = 0
        }
    }
}

class EmailAttachmentManager: ObservableObject {
    @Published var attachments: [ComposeEmailAttachment] = []
    
    func addAttachment(_ url: URL) {
        attachments.append(ComposeEmailAttachment(url: url))
    }
    
    func removeAttachment(_ id: UUID) {
        attachments.removeAll { $0.id == id }
    }
    
    func clearAttachments() {
        attachments.removeAll()
    }
}

struct AttachmentDropZone: View {
    @ObservedObject var attachmentManager: EmailAttachmentManager
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 12) {
            if attachmentManager.attachments.isEmpty {
                if isDragging {
                    Text("Rilascia qui per allegare")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "paperclip")
                            .foregroundColor(.secondary)
                        Text("Trascina file qui per allegare")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachmentManager.attachments) { attachment in
                            AttachmentChip(attachment: attachment) {
                                attachmentManager.removeAttachment(attachment.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(height: attachmentManager.attachments.isEmpty ? 60 : 50)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDragging ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDragging ? Color.accentColor : Color(.separatorColor), style: StrokeStyle(lineWidth: 2, dash: [5]))
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            attachmentManager.addAttachment(url)
                        }
                    }
                }
            }
            return true
        }
    }
}

struct AttachmentChip: View {
    let attachment: ComposeEmailAttachment
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconForFile(url: attachment.url))
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(attachment.filename)
                .font(.caption)
                .lineLimit(1)
            
            Text(ByteCountFormatter.string(fromByteCount: attachment.size, countStyle: .file))
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.controlColor))
        .cornerRadius(12)
    }
    
    private func iconForFile(url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "jpg", "jpeg", "png", "gif": return "photo.fill"
        case "zip", "rar": return "archivebox.fill"
        default: return "doc.fill"
        }
    }
}

