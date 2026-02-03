import SwiftUI
import AppKit
import PDFKit

struct SignatureSheet: View {
    let url: URL
    let fileType: MediaViewer.FileType
    let pageIndex: Int
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var signatureService = SignatureService.shared
    @State private var selectedSignature: NSImage?
    @State private var signaturePosition: CGPoint = CGPoint(x: 50, y: 50)
    @State private var signatureSize: CGSize = CGSize(width: 150, height: 60)
    @State private var isApplying = false
    @State private var applyMessage = ""
    
    private let editorService = MediaEditorService.shared
    
    var availableSignatures: [NSImage] {
        signatureService.getAvailableSignatures()
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Firma/Timbro")
                .font(.headline)
            
            if availableSignatures.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Nessuna firma disponibile")
                        .font(.subheadline)
                    Text("Vai in Impostazioni > File e Cartelle per caricare una firma")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                
                Button("Chiudi") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            } else {
                VStack(spacing: 16) {
                    // Selezione firma
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Seleziona Firma")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                if let individual = signatureService.individualSignature {
                                    SignaturePreview(
                                        image: individual,
                                        label: "Individuale",
                                        isSelected: selectedSignature == individual
                                    ) {
                                        selectedSignature = individual
                                    }
                                }
                                
                                if let studio = signatureService.studioSignature {
                                    SignaturePreview(
                                        image: studio,
                                        label: "Studio",
                                        isSelected: selectedSignature == studio
                                    ) {
                                        selectedSignature = studio
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    Divider()
                    
                    // Posizione e dimensione
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Posizione e Dimensione")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 8) {
                            HStack {
                                Text("X:")
                                Slider(value: Binding(
                                    get: { signaturePosition.x },
                                    set: { signaturePosition.x = $0 }
                                ), in: 0...500)
                                Text("\(Int(signaturePosition.x))")
                                    .frame(width: 50)
                            }
                            
                            HStack {
                                Text("Y:")
                                Slider(value: Binding(
                                    get: { signaturePosition.y },
                                    set: { signaturePosition.y = $0 }
                                ), in: 0...500)
                                Text("\(Int(signaturePosition.y))")
                                    .frame(width: 50)
                            }
                            
                            HStack {
                                Text("Larghezza:")
                                Slider(value: Binding(
                                    get: { signatureSize.width },
                                    set: { signatureSize.width = $0 }
                                ), in: 50...300)
                                Text("\(Int(signatureSize.width))")
                                    .frame(width: 50)
                            }
                            
                            HStack {
                                Text("Altezza:")
                                Slider(value: Binding(
                                    get: { signatureSize.height },
                                    set: { signatureSize.height = $0 }
                                ), in: 20...150)
                                Text("\(Int(signatureSize.height))")
                                    .frame(width: 50)
                            }
                        }
                    }
                    
                    if !applyMessage.isEmpty {
                        Text(applyMessage)
                            .font(.caption)
                            .foregroundColor(applyMessage.contains("successo") ? .green : .red)
                    }
                    
                    HStack {
                        Button("Annulla") {
                            dismiss()
                        }
                        .disabled(isApplying)
                        
                        Button("Applica Firma") {
                            applySignature()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedSignature == nil || isApplying)
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: availableSignatures.isEmpty ? 300 : 500)
        .onAppear {
            // Seleziona la prima firma disponibile
            if selectedSignature == nil, let first = availableSignatures.first {
                selectedSignature = first
            }
        }
    }
    
    private func applySignature() {
        guard let signature = selectedSignature else { return }
        
        isApplying = true
        applyMessage = "Applicazione in corso..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            let success: Bool
            
            if fileType == .image {
                success = editorService.addSignatureToImage(
                    at: url,
                    signature: signature,
                    position: signaturePosition,
                    size: signatureSize
                )
            } else if fileType == .pdf {
                success = editorService.addSignatureToPDF(
                    at: url,
                    pageIndex: pageIndex,
                    signature: signature,
                    position: signaturePosition,
                    size: signatureSize
                )
            } else {
                success = false
            }
            
            DispatchQueue.main.async {
                isApplying = false
                if success {
                    applyMessage = "Firma applicata con successo"
                    NotificationCenter.default.post(name: NSNotification.Name("MediaViewerReloadFile"), object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                } else {
                    applyMessage = "Errore nell'applicazione della firma"
                }
            }
        }
    }
}

struct SignaturePreview: View {
    let image: NSImage
    let label: String
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 150, height: 60)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
            
            Text(label)
                .font(.caption)
                .foregroundColor(isSelected ? .accentColor : .secondary)
        }
        .onTapGesture {
            onSelect()
        }
    }
}
