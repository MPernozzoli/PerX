import SwiftUI
import AppKit
import AVKit

// MARK: - Zoomable Content View

/// Componente unificato per zoom persistente su foto, video e PDF
/// Lo zoom è centrato sulla posizione del mouse
struct ZoomableContentView<Content: View>: View {
    let content: Content
    
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var zoomCenter: CGPoint = .zero
    @State private var isDragging = false
    @State private var mouseLocation: CGPoint = .zero
    
    let minScale: CGFloat
    let maxScale: CGFloat
    let onZoomChanged: ((CGFloat) -> Void)?
    let onOffsetChanged: ((CGSize) -> Void)?
    
    init(
        scale: Binding<CGFloat>,
        offset: Binding<CGSize>,
        minScale: CGFloat = 0.5,
        maxScale: CGFloat = 5.0,
        onZoomChanged: ((CGFloat) -> Void)? = nil,
        onOffsetChanged: ((CGSize) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self._scale = scale
        self._offset = offset
        self.minScale = minScale
        self.maxScale = maxScale
        self.onZoomChanged = onZoomChanged
        self.onOffsetChanged = onOffsetChanged
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geometry in
            content
                .scaleEffect(scale, anchor: .center)
                .offset(offset)
                .background(
                    // Traccia posizione mouse per zoom centrato
                    GeometryReader { contentGeometry in
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        // Aggiorna posizione mouse durante il drag
                                        mouseLocation = value.location
                                    }
                            )
                    }
                )
                .gesture(
                    // Zoom gesture centrato sul mouse
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            
                            // Calcola nuovo zoom incrementale
                            let newScale = max(minScale, min(maxScale, scale * delta))
                            
                            // Calcola offset per mantenere il punto focale (mouse) fisso
                            let scaleDelta = newScale / scale
                            let focalPoint = mouseLocation
                            let contentCenter = CGPoint(
                                x: geometry.size.width / 2,
                                y: geometry.size.height / 2
                            )
                            
                            // Vettore dal centro al punto focale
                            let focalVector = CGPoint(
                                x: focalPoint.x - contentCenter.x,
                                y: focalPoint.y - contentCenter.y
                            )
                            
                            // Aggiorna offset per mantenere il punto focale fisso
                            let newOffset = CGSize(
                                width: offset.width - focalVector.x * (scaleDelta - 1),
                                height: offset.height - focalVector.y * (scaleDelta - 1)
                            )
                            
                            scale = newScale
                            offset = constrainedOffset(newOffset, in: geometry.size)
                            onZoomChanged?(newScale)
                            onOffsetChanged?(offset)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                        }
                )
                .simultaneousGesture(
                    // Pan gesture
                    DragGesture()
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                lastOffset = offset
                            }
                            
                            // Aggiorna anche posizione mouse durante pan
                            mouseLocation = value.location
                            
                            let newOffset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                            
                            // Applica constraints per evitare pan oltre i bordi
                            offset = constrainedOffset(newOffset, in: geometry.size)
                            onOffsetChanged?(offset)
                        }
                        .onEnded { _ in
                            isDragging = false
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    // Doppio click per reset
                    withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                        scale = 1.0
                        offset = .zero
                        onZoomChanged?(1.0)
                        onOffsetChanged?(.zero)
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        mouseLocation = location
                    case .ended:
                        break
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    
    private func constrainedOffset(_ newOffset: CGSize, in containerSize: CGSize) -> CGSize {
        // Calcola limiti in base allo zoom
        let maxOffset = max(0, (containerSize.width * scale - containerSize.width) / 2)
        let maxOffsetY = max(0, (containerSize.height * scale - containerSize.height) / 2)
        
        return CGSize(
            width: max(-maxOffset, min(maxOffset, newOffset.width)),
            height: max(-maxOffsetY, min(maxOffsetY, newOffset.height))
        )
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let url: URL
    @Binding var showTagPopover: Bool
    
    @State private var image: NSImage?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var loadTask: Task<Void, Never>?
    
    private let fileService = FileService.shared
    
    var body: some View {
        GeometryReader { geometry in
            if let image = image {
                let containerSize = geometry.size
                let imageSize = image.size
                let scaleToFit = min(
                    containerSize.width / imageSize.width,
                    containerSize.height / imageSize.height,
                    1.0
                )
                let displayWidth = imageSize.width * scaleToFit * scale
                let displayHeight = imageSize.height * scaleToFit * scale
                
                ZoomableContentView(
                    scale: $scale,
                    offset: $offset,
                    minScale: 0.5,
                    maxScale: 5.0
                ) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: displayWidth, height: displayHeight)
                        .frame(width: containerSize.width, height: containerSize.height)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if isLoading {
                loadingView
            } else if let error = loadError {
                errorView(error)
            }
        }
        .onAppear {
            loadImage()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .onChange(of: url) { _ in
            scale = 1.0
            offset = .zero
            loadImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MediaViewerReloadFile"))) { _ in
            loadImage()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Caricamento...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Impossibile caricare l'immagine")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private func loadImage() {
        loadTask?.cancel()
        image = nil
        isLoading = true
        loadError = nil
        
        let fileURL = url
        let service = fileService
        
        loadTask = Task { @MainActor in
            let loadedImage = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                let filePath = fileURL.deletingLastPathComponent().path
                let result: NSImage? = service.performWithSecurityScopedAccess(to: filePath) {
                    if let img = NSImage(contentsOf: fileURL) {
                        return img
                    }
                    if let data = try? Data(contentsOf: fileURL), let img = NSImage(data: data) {
                        return img
                    }
                    return nil
                } ?? nil
                return result
            }.value
            
            guard !Task.isCancelled else { return }
            
            withAnimation(GlassmorphismDesignSystem.Animations.easeInOut) {
                if let loadedImage = loadedImage {
                    self.image = loadedImage
                    self.isLoading = false
                    self.loadError = nil
                } else {
                    self.image = nil
                    self.isLoading = false
                    self.loadError = "Il file potrebbe essere corrotto o in un formato non supportato"
                }
            }
        }
    }
}

// MARK: - Zoomable Video View

struct ZoomableVideoView: NSViewRepresentable {
    let url: URL
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    
    private let fileService = FileService.shared
    
    func makeNSView(context: Context) -> ZoomableVideoContainerView {
        let containerView = ZoomableVideoContainerView()
        containerView.coordinator = context.coordinator
        
        // Setup callback per sincronizzare con binding SwiftUI
        containerView.onScaleChanged = { newScale in
            DispatchQueue.main.async {
                scale = newScale
            }
        }
        containerView.onOffsetChanged = { newOffset in
            DispatchQueue.main.async {
                offset = newOffset
            }
        }
        
        loadVideo(into: containerView, context: context)
        
        return containerView
    }
    
    func updateNSView(_ nsView: ZoomableVideoContainerView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            loadVideo(into: nsView, context: context)
        }
        
        // Aggiorna zoom e offset solo se sono diversi (evita loop)
        if abs(nsView.currentScale - scale) > 0.001 {
            nsView.setZoom(scale, offset: offset)
        } else if abs(nsView.currentOffset.width - offset.width) > 0.1 || abs(nsView.currentOffset.height - offset.height) > 0.1 {
            nsView.setZoom(scale, offset: offset)
        }
    }
    
    static func dismantleNSView(_ nsView: ZoomableVideoContainerView, coordinator: Coordinator) {
        coordinator.cleanup()
    }
    
    private func loadVideo(into containerView: ZoomableVideoContainerView, context: Context) {
        context.coordinator.player?.pause()
        context.coordinator.stopSecurityAccess()
        
        let directoryPath = url.deletingLastPathComponent().path
        context.coordinator.startSecurityAccess(for: directoryPath, fileService: fileService)
        
        let player = AVPlayer(url: url)
        containerView.setPlayer(player)
        context.coordinator.player = player
        context.coordinator.url = url
        
        player.play()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }
    
    class Coordinator {
        var player: AVPlayer?
        var url: URL
        private var securityScopedURL: URL?
        
        init(url: URL) {
            self.url = url
        }
        
        func startSecurityAccess(for path: String, fileService: FileService) {
            if let folderScanBookmarks = UserDefaults.standard.data(forKey: "FolderScanBookmarks"),
               let bookmarksDict = try? PropertyListDecoder().decode([String: Data].self, from: folderScanBookmarks) {
                for (bookmarkPath, bookmarkData) in bookmarksDict.sorted(by: { $0.key.count > $1.key.count }) {
                    if path.hasPrefix(bookmarkPath) {
                        do {
                            var isStale = false
                            let url = try URL(resolvingBookmarkData: bookmarkData,
                                            options: [.withSecurityScope],
                                            relativeTo: nil,
                                            bookmarkDataIsStale: &isStale)
                            if !isStale && url.startAccessingSecurityScopedResource() {
                                securityScopedURL = url
                                return
                            }
                        } catch {
                            continue
                        }
                    }
                }
            }
            
            if let bookmarkData = UserDefaults.standard.data(forKey: "MainDirectoryBookmark") {
                do {
                    var isStale = false
                    let url = try URL(resolvingBookmarkData: bookmarkData,
                                    options: .withSecurityScope,
                                    relativeTo: nil,
                                    bookmarkDataIsStale: &isStale)
                    if !isStale {
                        let bookmarkPath = url.path
                        if path.hasPrefix(bookmarkPath) && url.startAccessingSecurityScopedResource() {
                            securityScopedURL = url
                        }
                    }
                } catch { }
            }
        }
        
        func stopSecurityAccess() {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
        }
        
        func cleanup() {
            player?.pause()
            player = nil
            stopSecurityAccess()
        }
        
        deinit {
            cleanup()
        }
    }
}

// MARK: - Zoomable Video Container View

class ZoomableVideoContainerView: NSView {
    private var playerView: AVPlayerView!
    var currentScale: CGFloat = 1.0
    var currentOffset: CGSize = .zero
    weak var coordinator: ZoomableVideoView.Coordinator?
    
    // Callback per aggiornare i binding SwiftUI
    var onScaleChanged: ((CGFloat) -> Void)?
    var onOffsetChanged: ((CGSize) -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        wantsLayer = true
        
        playerView = AVPlayerView()
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true
        addSubview(playerView)
        
        NSLayoutConstraint.activate([
            playerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            playerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            playerView.widthAnchor.constraint(equalTo: widthAnchor),
            playerView.heightAnchor.constraint(equalTo: heightAnchor)
        ])
        
        // Aggiungi gesture recognizer per zoom
        let magnifyGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        addGestureRecognizer(magnifyGesture)
        
        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)
    }
    
    func setPlayer(_ player: AVPlayer) {
        playerView.player = player
    }
    
    func setZoom(_ scale: CGFloat, offset: CGSize) {
        // Aggiorna solo se i valori sono diversi per evitare loop
        guard abs(currentScale - scale) > 0.001 || abs(currentOffset.width - offset.width) > 0.1 || abs(currentOffset.height - offset.height) > 0.1 else {
            return
        }
        
        currentScale = scale
        currentOffset = offset
        
        let transform = CATransform3DIdentity
        let scaledTransform = CATransform3DScale(transform, scale, scale, 1)
        let translatedTransform = CATransform3DTranslate(scaledTransform, offset.width, offset.height, 0)
        
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        playerView.layer?.transform = translatedTransform
        CATransaction.commit()
    }
    
    @objc private func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
        // Ottieni posizione mouse nel view
        let mouseLocation = gesture.location(in: self)
        let viewCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        
        // Vettore dal centro al punto mouse
        let focalVector = CGPoint(
            x: mouseLocation.x - viewCenter.x,
            y: mouseLocation.y - viewCenter.y
        )
        
        let delta = 1 + gesture.magnification
        gesture.magnification = 0
        
        let oldScale = currentScale
        let newScale = max(0.5, min(5.0, currentScale * delta))
        let scaleDelta = newScale / oldScale
        
        // Aggiorna offset per mantenere il punto focale (mouse) fisso
        let newOffset = CGSize(
            width: currentOffset.width - focalVector.x * (scaleDelta - 1),
            height: currentOffset.height - focalVector.y * (scaleDelta - 1)
        )
        
        setZoom(newScale, offset: newOffset)
        
        // Notifica i binding SwiftUI
        onScaleChanged?(newScale)
        onOffsetChanged?(newOffset)
    }
    
    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        
        let newOffset = CGSize(
            width: currentOffset.width + translation.x,
            height: currentOffset.height - translation.y
        )
        
        setZoom(currentScale, offset: newOffset)
        
        // Notifica i binding SwiftUI
        onOffsetChanged?(newOffset)
    }
    
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Reset on double click
            setZoom(1.0, offset: .zero)
            onScaleChanged?(1.0)
            onOffsetChanged?(.zero)
        } else {
            super.mouseDown(with: event)
        }
    }
}
