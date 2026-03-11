//
//  LogoCropSheet.swift
//  PerX
//
//  Modale per ritagliare il logo in forma circolare con zoom e pan.
//

import SwiftUI
import AppKit

struct LogoCropSheet: View {
    let image: NSImage
    let compagnia: Compagnia
    let onConfirm: (NSImage) -> Void
    let onCancel: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    
    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 4.0
    private let cropSize: CGFloat = 400
    private let outputSize: CGFloat = 256
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Ritaglia logo circolare")
                    .font(.headline)
                Spacer()
                Button("Annulla") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Button("Conferma") {
                    confirmCrop()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // Area ritaglio con cerchio
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                // Immagine zoomabile e trascinabile
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(maxScale, max(minScale, lastScale * value))
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
                    .frame(width: cropSize, height: cropSize)
                    .clipped()
            }
            .frame(width: cropSize, height: cropSize)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.8), lineWidth: 2)
            )
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.3), lineWidth: 1)
                    .padding(1)
            )
            .shadow(color: .black.opacity(0.3), radius: 8)
            .padding(24)
            
            // Controlli zoom
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "minus.magnifyingglass")
                        .foregroundColor(.secondary)
                    Slider(value: $scale, in: minScale...maxScale)
                        .onChange(of: scale) { _ in
                            lastScale = scale
                        }
                    Image(systemName: "plus.magnifyingglass")
                        .foregroundColor(.secondary)
                }
                Text("Zoom: \(Int(scale * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 620)
    }
    
    private func confirmCrop() {
        guard let cropped = cropToCircle() else { return }
        onConfirm(cropped)
    }
    
    private func cropToCircle() -> NSImage? {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return nil }
        
        let radius = cropSize / 2
        let centerX = cropSize / 2
        let centerY = cropSize / 2
        
        // Aspect fit: immagine nel quadrato cropSize
        let scaleFit = min(cropSize / imgSize.width, cropSize / imgSize.height)
        let drawW = imgSize.width * scaleFit
        let drawH = imgSize.height * scaleFit
        let drawX = (cropSize - drawW) / 2
        let drawY = (cropSize - drawH) / 2
        
        // Dopo scaleEffect(scale) e offset(offset)
        let finalDrawW = drawW * scale
        let finalDrawH = drawH * scale
        let finalDrawX = (cropSize - finalDrawW) / 2 + offset.width
        let finalDrawY = (cropSize - finalDrawH) / 2 + offset.height
        
        // Mappa view -> immagine: (vx, vy) -> (ix, iy)
        // ix = (vx - finalDrawX) / finalDrawW * imgSize.width
        // iy = imgSize.height - (vy - finalDrawY) / finalDrawH * imgSize.height (y flip NSImage)
        
        let outSize = outputSize
        let outRect = NSRect(x: 0, y: 0, width: outSize, height: outSize)
        
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(outSize),
            pixelsHigh: Int(outSize),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        
        bitmap.size = NSSize(width: outSize, height: outSize)
        
        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = ctx
        
        // Clip al cerchio
        let circlePath = NSBezierPath(ovalIn: outRect)
        circlePath.addClip()
        
        // Per ogni pixel output (ox, oy), mappa a view (vx, vy) poi a immagine
        // ox, oy: 0..outSize, centro = outSize/2
        // vx = ox / outSize * cropSize (ma il cerchio ha centro cropSize/2, raggio radius)
        // Il nostro output è già il cerchio: ox,oy sono nel quadrato outSize, centro outSize/2
        // Mappiamo il cerchio output al cerchio view
        // vx = (ox - outSize/2) / (outSize/2) * radius + centerX = (ox - outSize/2) * cropSize/outSize + centerX
        // Semplice: vx = ox * cropSize / outSize, vy = oy * cropSize / outSize
        let scaleToView = cropSize / outSize
        
        let dstRect = NSRect(x: 0, y: 0, width: outSize, height: outSize)
        let srcRect = NSRect(x: 0, y: 0, width: imgSize.width, height: imgSize.height)
        
        // Disegna l'immagine con la trasformazione che mappa view->output
        // Dobbiamo disegnare la porzione di immagine visibile nel cerchio view
        // nel rect output. Usiamo draw(in:from:...) con il rect sorgente corretto.
        // Il rect sorgente: mappa i 4 angoli del cerchio output nell'immagine
        // Angoli del cerchio output: centro (outSize/2, outSize/2), raggio outSize/2
        // Bounding box view del cerchio: (0,0) a (cropSize, cropSize)
        // Mappa (0,0) view -> img: ix0 = (0 - finalDrawX)/finalDrawW * imgSize.width, etc
        let vx0: CGFloat = 0, vy0: CGFloat = 0
        let vx1 = cropSize, vy1 = cropSize
        
        let ix0 = (vx0 - finalDrawX) / finalDrawW * imgSize.width
        let iy0 = imgSize.height - (vy0 - finalDrawY) / finalDrawH * imgSize.height
        let ix1 = (vx1 - finalDrawX) / finalDrawW * imgSize.width
        let iy1 = imgSize.height - (vy1 - finalDrawY) / finalDrawH * imgSize.height
        
        let srcCrop = NSRect(
            x: min(ix0, ix1),
            y: min(iy0, iy1),
            width: abs(ix1 - ix0),
            height: abs(iy1 - iy0)
        )
        
        image.draw(in: dstRect, from: srcCrop, operation: .copy, fraction: 1.0)
        
        NSGraphicsContext.restoreGraphicsState()
        
        let result = NSImage(size: NSSize(width: outSize, height: outSize))
        result.addRepresentation(bitmap)
        return result
    }
}
