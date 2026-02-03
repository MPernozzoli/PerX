import SwiftUI

// MARK: - File Item Row

struct FileItemRow: View {
    let item: FileService.FileItem
    let isSelected: Bool
    let tags: Set<FileTagManager.FileTag>
    let fileStatus: FileStatus?
    let onTagButtonTapped: () -> Void
    @StateObject private var fileTagManager = FileTagManager.shared
    @State private var showDetails = false
    @State private var showTagPopover = false
    
    private var isNew: Bool {
        fileStatus == .new
    }
    
    private var isModified: Bool {
        fileStatus == .modified
    }
    
    private var primaryTag: FileTagManager.FileTag? {
        tags.first
    }
    
    private var primaryTagAdditionalText: String? {
        guard let tag = primaryTag else { return nil }
        return fileTagManager.getAdditionalText(forFile: item.url.path, tagId: tag.id)
    }
    
    private var primaryTagBeneRiferimento: String? {
        guard let tag = primaryTag else { return nil }
        return fileTagManager.getBeneRiferimento(forFile: item.url.path, tagId: tag.id)
    }
    
    /// Costruisce il testo dei dettagli con bene e componente
    private var tagDetailsText: String? {
        guard let tag = primaryTag else { return nil }
        
        var parts: [String] = []
        
        // Per foto_bene, additionalText è il bene
        if tag.id == "foto_bene" {
            if let text = primaryTagAdditionalText, !text.isEmpty {
                parts.append(text)
            }
        } else {
            // Per altri tag, beneRiferimento è il bene
            if let bene = primaryTagBeneRiferimento, !bene.isEmpty {
                parts.append(bene)
            }
            // additionalText è il componente/descrizione
            if let text = primaryTagAdditionalText, !text.isEmpty {
                parts.append(text)
            }
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Icona del file o cartella
            ZStack {
                Image(nsImage: item.icon ?? NSImage())
                    .resizable()
                    .frame(width: 24, height: 24)
                    .opacity(item.isDownloading || item.isNotDownloaded ? 0.5 : 1.0)
                
                // Icona download in corso
                if item.isDownloading {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                        .offset(x: 8, y: 8)
                } else if item.isNotDownloaded {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                        .offset(x: 8, y: 8)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                // Nome file sempre fisso in alto
                HStack(spacing: 4) {
                    Text(item.url.lastPathComponent)
                        .lineLimit(1)
                        .font(.system(size: 13))
                        .foregroundColor(item.isDownloading || item.isNotDownloaded ? .secondary : .primary)
                    
                    if isNew {
                        Text("NEW")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue)
                            .cornerRadius(3)
                    } else if isModified {
                        Text("MOD")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .cornerRadius(3)
                    }
                }
                
                // Dettagli che compaiono sotto senza spostare il nome
                if !item.isDirectory {
                    if showDetails {
                        HStack(spacing: 8) {
                            Text(item.formattedSize)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(item.formattedDate)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if let tag = primaryTag {
                        HStack(spacing: 4) {
                            Text(tag.name)
                                .font(.caption)
                                .foregroundColor(tag.tagColor)
                            
                            // Mostra bene + componente
                            if let details = tagDetailsText {
                                Text("• \(details)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            // Indicatore "da allegare"
                            if fileTagManager.getDaAllegareInChiusura(forFile: item.url.path, tagId: tag.id) {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                        .transition(.opacity)
                    } else {
                        // Spazio riservato per mantenere l'altezza costante
                        Text(" ")
                            .font(.caption)
                            .opacity(0)
                    }
                } else {
                    // Per le cartelle, spazio riservato
                    Text(" ")
                        .font(.caption)
                        .opacity(0)
                }
            }
            
            Spacer()
            
            // Tag button solo per i file
            if !item.isDirectory {
                Button(action: {
                    showTagPopover = true
                    onTagButtonTapped()
                }) {
                    Image(systemName: tags.isEmpty ? "tag" : "tag.fill")
                        .foregroundColor(tags.isEmpty ? .secondary : primaryTag?.tagColor)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showTagPopover, attachmentAnchor: .point(.bottom), arrowEdge: .bottom) {
                    UnifiedTagView(context: .file(item.url), sinistroPath: nil)
                }
            }
            
            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            Group {
                if isSelected {
                    Color.accentColor.opacity(0.2)
                } else if isNew {
                    Color.blue.opacity(0.1)
                } else if isModified {
                    Color.orange.opacity(0.1)
                } else {
                    Color.clear
                }
            }
        )
        .overlay(
            Group {
                if isNew && !isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                } else if isModified && !isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                }
            }
        )
        .cornerRadius(4)
        .opacity(item.isDownloading || item.isNotDownloaded ? 0.6 : 1.0)
        .disabled(item.isDownloading || item.isNotDownloaded)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                showDetails = hovering
            }
        }
    }
}
