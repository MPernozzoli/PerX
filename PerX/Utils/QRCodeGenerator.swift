import Foundation
import AppKit
import CoreImage
import SwiftUI

struct QRCodeGenerator {
    static func generateQRCode(from string: String, size: CGSize = CGSize(width: 300, height: 300)) -> NSImage? {
        let data = string.data(using: .utf8)
        
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel") // High error correction
        
        guard let ciImage = filter.outputImage else {
            return nil
        }
        
        // Scala l'immagine alla dimensione desiderata
        let scaleX = size.width / ciImage.extent.size.width
        let scaleY = size.height / ciImage.extent.size.height
        let transformedImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Converti CIImage in NSImage
        let rep = NSCIImageRep(ciImage: transformedImage)
        let nsImage = NSImage(size: size)
        nsImage.addRepresentation(rep)
        
        return nsImage
    }
}

struct QRCodeImageView: View {
    let qrCodeString: String
    let size: CGFloat
    
    init(qrCodeString: String, size: CGFloat = 300) {
        self.qrCodeString = qrCodeString
        self.size = size
    }
    
    var body: some View {
        Group {
            if let qrImage = QRCodeGenerator.generateQRCode(from: qrCodeString, size: CGSize(width: size, height: size)) {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Errore generazione QR Code")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: size, height: size)
            }
        }
    }
}

