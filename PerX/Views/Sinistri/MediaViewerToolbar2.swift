import SwiftUI
import PDFKit

// MARK: - Media Viewer Toolbar 2.0

/// Toolbar glassmorphism per MediaViewer 2.0
struct MediaViewerToolbar2: View {
    let url: URL
    let fileType: MediaFileType
    let currentIndex: Int
    let totalFiles: Int
    let currentPageIndex: Int
    let totalPages: Int
    let zoomLevel: CGFloat
    let isPDF: Bool
    
    @Binding var showTagPopover: Bool
    @Binding var showQuickPhotoTagPanel: Bool
    @Binding var showNavigationSettings: Bool
    @Binding var navigationScope: NavigationScope
    @Binding var typeFilter: TypeFilter
    @Binding var tagFilter: TagFilter
    
    let onClose: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onRotate: () -> Void
    let onCrop: () -> Void
    let onOCR: () -> Void
    let onSignature: () -> Void
    let onCompress: () -> Void
    let onResetToTop: () -> Void
    let onResetZoom: () -> Void
    let onResetPan: () -> Void
    let onRemovePage: (() -> Void)?
    let onHighlight: (() -> Void)?
    let onToggleAlwaysOnTop: () -> Void
    let onAnnotationToggle: (() -> Void)?
    let onSearch: ((String) -> Void)?
    let onSearchNext: (() -> Void)?
    let onSearchPrevious: (() -> Void)?
    
    let isAlwaysOnTop: Bool
    let annotationMode: AnnotationMode?
    let searchText: String?
    let searchResultCount: Int?
    let currentSearchIndex: Int?
    
    @ObservedObject private var fileTagManager = FileTagManager.shared
    
    var body: some View {
        GlassmorphicToolbar {
            HStack(spacing: 12) {
                // Navigation group
                navigationGroup
                
                GlassmorphicDivider(isVertical: true)
                    .frame(height: 24)
                
                // Filters button
                filtersButton
                
                GlassmorphicDivider(isVertical: true)
                    .frame(height: 24)
                
                // Tag group
                tagGroup
                
                GlassmorphicDivider(isVertical: true)
                    .frame(height: 24)
                
                // Edit tools group
                editToolsGroup
                
                // PDF specific tools
                if isPDF {
                    GlassmorphicDivider(isVertical: true)
                        .frame(height: 24)
                    
                    pdfToolsGroup
                }
                
                Spacer()
                
                // Search group
                if let onSearch = onSearch {
                    GlassmorphicDivider(isVertical: true)
                        .frame(height: 24)
                    
                    searchGroup
                }
                
                Spacer()
                
                // Right side tools
                rightToolsGroup
            }
        }
    }
    
    // MARK: - Search Group
    
    private var searchGroup: some View {
        HStack(spacing: 6) {
            // Search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                TextField("Cerca nel testo...", text: Binding(
                    get: { searchText ?? "" },
                    set: { onSearch?($0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 150)
                
                if let searchText = searchText, !searchText.isEmpty {
                    Button {
                        onSearch?("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(GlassmorphismDesignSystem.Colors.secondaryGlass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(GlassmorphismDesignSystem.Colors.borderLight, lineWidth: 0.5)
            )
            
            // Search navigation
            if let count = searchResultCount, count > 0, let currentIndex = currentSearchIndex {
                HStack(spacing: 4) {
                    Text("\(currentIndex + 1)/\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    GlassmorphicIconButton(icon: "chevron.up", size: 20) {
                        onSearchPrevious?()
                    }
                    .help("Risultato Precedente (⌘⇧G)")
                    
                    GlassmorphicIconButton(icon: "chevron.down", size: 20) {
                        onSearchNext?()
                    }
                    .help("Risultato Successivo (⌘G)")
                }
            }
        }
    }
    
    // MARK: - Navigation Group
    
    private var navigationGroup: some View {
        HStack(spacing: 6) {
            GlassmorphicIconButton(icon: "chevron.left", size: 26) {
                onPrevious()
            }
            .disabled(currentIndex <= 1)
            .help("File Precedente (←)")
            
            // Counter badge
            HStack(spacing: 4) {
                Text("\(currentIndex)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("/")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Text("\(totalFiles)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(GlassmorphismDesignSystem.Colors.secondaryGlass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(GlassmorphismDesignSystem.Colors.borderLight, lineWidth: 0.5)
            )
            
            GlassmorphicIconButton(icon: "chevron.right", size: 26) {
                onNext()
            }
            .disabled(currentIndex >= totalFiles)
            .help("File Successivo (→)")
            
            // PDF page indicator
            if isPDF && totalPages > 1 {
                HStack(spacing: 4) {
                    Text("P.\(currentPageIndex + 1)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("/\(totalPages)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange.opacity(0.15))
                )
            }
        }
    }
    
    // MARK: - Filters Button
    
    private var filtersButton: some View {
        GlassmorphicIconButton(
            icon: hasActiveFilters ? "slider.horizontal.3.circle.fill" : "slider.horizontal.3",
            isActive: hasActiveFilters,
            size: 26
        ) {
            showNavigationSettings.toggle()
        }
        .help("Impostazioni Navigazione (⌘N)")
    }
    
    private var hasActiveFilters: Bool {
        navigationScope != .currentFolder || typeFilter != .all || tagFilter != .all
    }
    
    // MARK: - Tag Group
    
    private var tagGroup: some View {
        HStack(spacing: 6) {
            // Tag button con indicatore
            Button {
                showTagPopover = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 12))
                    Text("Tag")
                        .font(.system(size: 12, weight: .medium))
                    
                    // Badge conteggio tag
                    let tagCount = getTagCount()
                    if tagCount > 0 {
                        GlassmorphicBadge(text: "\(tagCount)", color: .accentColor)
                    }
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(GlassmorphismDesignSystem.Colors.secondaryGlass)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(GlassmorphismDesignSystem.Colors.borderLight, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .help("Gestisci Tag")
            
            // Quick classify button (solo per immagini)
            if fileType == .image {
                GlassmorphicIconButton(
                    icon: "bolt.fill",
                    isActive: showQuickPhotoTagPanel,
                    size: 26
                ) {
                    withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                        showQuickPhotoTagPanel.toggle()
                    }
                }
                .help("Classifica Foto")
            }
        }
    }
    
    private func getTagCount() -> Int {
        if isPDF {
            return fileTagManager.getTagsForPDFPage(at: url.path, pageIndex: currentPageIndex).count
        } else {
            return fileTagManager.getTagsForFile(at: url.path).count
        }
    }
    
    // MARK: - Edit Tools Group
    
    private var editToolsGroup: some View {
        HStack(spacing: 4) {
            GlassmorphicIconButton(icon: "rotate.right", size: 26) {
                onRotate()
            }
            .help("Ruota")
            
            GlassmorphicIconButton(icon: "crop", size: 26) {
                onCrop()
            }
            .help("Ritaglia")
            
            GlassmorphicIconButton(icon: "text.viewfinder", size: 26) {
                onOCR()
            }
            .help("OCR - Copia Testo")
            
            GlassmorphicIconButton(icon: "signature", size: 26) {
                onSignature()
            }
            .help("Firma/Timbro")
        }
    }
    
    // MARK: - PDF Tools Group
    
    private var pdfToolsGroup: some View {
        HStack(spacing: 4) {
            // Reset controls
            GlassmorphicIconButton(icon: "arrow.up.to.line", size: 26) {
                onResetToTop()
            }
            .help("Torna in cima (⌘↑)")
            
            GlassmorphicIconButton(icon: "1.magnifyingglass", size: 26) {
                onResetZoom()
            }
            .help("Reset Zoom (⌘0)")
            
            // Zoom indicator
            Text("\(Int(zoomLevel * 100))%")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
            
            if let onRemovePage = onRemovePage {
                GlassmorphicDivider(isVertical: true)
                    .frame(height: 16)
                
                GlassmorphicIconButton(icon: "minus.circle", size: 26) {
                    onRemovePage()
                }
                .help("Rimuovi Pagina")
            }
            
            if let onAnnotationToggle = onAnnotationToggle {
                GlassmorphicDivider(isVertical: true)
                    .frame(height: 16)
                
                GlassmorphicIconButton(
                    icon: annotationMode != nil ? "pencil.circle.fill" : "pencil.circle",
                    isActive: annotationMode != nil,
                    size: 26
                ) {
                    onAnnotationToggle()
                }
                .help("Annotazioni PDF")
            }
        }
    }
    
    // MARK: - Right Tools Group
    
    private var rightToolsGroup: some View {
        HStack(spacing: 6) {
            GlassmorphicButton(title: "Comprimi", icon: "arrow.down.circle") {
                onCompress()
            }
            .help("Riduci Peso File")
            
            GlassmorphicIconButton(
                icon: isAlwaysOnTop ? "pin.fill" : "pin",
                isActive: isAlwaysOnTop,
                size: 26
            ) {
                onToggleAlwaysOnTop()
            }
            .help(isAlwaysOnTop ? "Disattiva Sempre in Primo Piano" : "Attiva Sempre in Primo Piano")
            
            GlassmorphicIconButton(icon: "xmark.circle.fill", size: 26) {
                onClose()
            }
            .help("Chiudi")
        }
    }
}

// MARK: - Media File Type

enum MediaFileType {
    case image
    case pdf
    case video
    case unknown
    
    init(from url: URL) {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"].contains(ext) {
            self = .image
        } else if ext == "pdf" {
            self = .pdf
        } else if ["mp4", "mov", "avi", "mkv", "m4v"].contains(ext) {
            self = .video
        } else {
            self = .unknown
        }
    }
}
