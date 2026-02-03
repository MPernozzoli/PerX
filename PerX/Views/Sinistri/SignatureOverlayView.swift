import SwiftUI
import AppKit

struct SignatureOverlayData {
    let image: NSImage
    let signatureType: String
    var position: CGPoint
    var size: CGSize
}

struct SignatureOverlayView: View {
    @Binding var overlay: SignatureOverlayData
    let onRemove: () -> Void
    
    @State private var isDragging = false
    @State private var isResizing = false
    @State private var dragOffset: CGSize = .zero
    @State private var resizeStartSize: CGSize = .zero
    @State private var resizeStartPosition: CGPoint = .zero
    
    private let minSize: CGSize = CGSize(width: 50, height: 20)
    private let maxSize: CGSize = CGSize(width: 400, height: 200)
    
    var body: some View {
        GeometryReader { geometry in
            let aspectRatio = overlay.image.size.width / overlay.image.size.height
            let constrainedSize = CGSize(
                width: overlay.size.width,
                height: overlay.size.width / aspectRatio
            )
            
            ZStack {
                // Firma
                Image(nsImage: overlay.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: constrainedSize.width, height: constrainedSize.height)
                    .position(
                        x: overlay.position.x + constrainedSize.width / 2,
                        y: overlay.position.y + constrainedSize.height / 2
                    )
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    dragOffset = .zero
                                }
                                
                                let newX = max(0, min(geometry.size.width - constrainedSize.width, overlay.position.x + value.translation.width - dragOffset.width))
                                let newY = max(0, min(geometry.size.height - constrainedSize.height, overlay.position.y + value.translation.height - dragOffset.height))
                                
                                let newPosition = CGPoint(x: newX, y: newY)
                                
                                dragOffset = value.translation
                                
                                var updated = overlay
                                updated.position = newPosition
                                overlay = updated
                            }
                            .onEnded { _ in
                                isDragging = false
                                dragOffset = .zero
                            }
                    )
                
                // Handle di ridimensionamento (angolo in basso a destra)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                    .position(
                        x: overlay.position.x + constrainedSize.width,
                        y: overlay.position.y + constrainedSize.height
                    )
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                if !isResizing {
                                    isResizing = true
                                    resizeStartSize = overlay.size
                                    resizeStartPosition = overlay.position
                                }
                                
                                let delta = value.translation
                                let newWidth = max(minSize.width, min(maxSize.width, resizeStartSize.width + delta.width))
                                let newHeight = newWidth / aspectRatio
                                
                                var updated = overlay
                                updated.size = CGSize(width: newWidth, height: newHeight)
                                
                                // Mantieni l'angolo in basso a destra fisso durante il ridimensionamento
                                let sizeDelta = CGSize(
                                    width: newWidth - resizeStartSize.width,
                                    height: newHeight - resizeStartSize.height
                                )
                                updated.position = CGPoint(
                                    x: max(0, min(geometry.size.width - newWidth, resizeStartPosition.x - sizeDelta.width / 2)),
                                    y: max(0, min(geometry.size.height - newHeight, resizeStartPosition.y - sizeDelta.height / 2))
                                )
                                
                                overlay = updated
                            }
                            .onEnded { _ in
                                isResizing = false
                            }
                    )
                    .help("Ridimensiona")
                
                // Pulsante rimuovi (in alto a destra)
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .background(Circle().fill(.white))
                }
                .buttonStyle(.plain)
                .position(
                    x: overlay.position.x + constrainedSize.width,
                    y: overlay.position.y
                )
            }
        }
    }
}

struct SignatureSelectionPopover: View {
    @StateObject private var signatureService = SignatureService.shared
    let onSelect: (String) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Seleziona Firma")
                .font(.headline)
            
            if let individual = signatureService.individualSignature {
                Button {
                    onSelect("individual")
                } label: {
                    VStack(spacing: 8) {
                        Image(nsImage: individual)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 200, height: 80)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                        Text("Firma Individuale")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }
            
            if let studio = signatureService.studioSignature {
                Button {
                    onSelect("studio")
                } label: {
                    VStack(spacing: 8) {
                        Image(nsImage: studio)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 200, height: 80)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                        Text("Firma Studio")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 250)
    }
}
