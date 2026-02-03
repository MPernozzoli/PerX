import SwiftUI
import AppKit

struct SignatureSettingsView: View {
    @StateObject private var signatureService = SignatureService.shared
    @State private var showingIndividualPicker = false
    @State private var showingStudioPicker = false
    @State private var isUploadingStudio = false
    @State private var uploadMessage = ""
    
    var body: some View {
        GroupBox {
            VStack(spacing: 16) {
                HStack {
                    Text("Firme e Timbri")
                        .font(.headline)
                    Spacer()
                }
                
                // Firma Individuale
                VStack(alignment: .leading, spacing: 12) {
                    Text("Firma Individuale")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 12) {
                        if let signature = signatureService.individualSignature {
                            Image(nsImage: signature)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 200, height: 80)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .frame(width: 200, height: 80)
                                .overlay(
                                    Text("Nessuna firma")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Carica Firma") {
                                showingIndividualPicker = true
                            }
                            .buttonStyle(.bordered)
                            
                            if signatureService.individualSignature != nil {
                                Button("Rimuovi") {
                                    signatureService.setIndividualSignature(nil)
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            Text("Firma personale salvata localmente")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Divider()
                
                // Firma Studio
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Firma di Studio")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        if signatureService.isLoadingStudioSignature {
                            ProgressView()
                                .scaleEffect(0.7)
                                .padding(.leading, 8)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        if let signature = signatureService.studioSignature {
                            Image(nsImage: signature)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 200, height: 80)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .frame(width: 200, height: 80)
                                .overlay(
                                    Text("Nessuna firma")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Carica Firma") {
                                showingStudioPicker = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(isUploadingStudio)
                            
                            if signatureService.studioSignature != nil {
                                Button("Rimuovi") {
                                    Task {
                                        await signatureService.setStudioSignature(nil)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isUploadingStudio)
                            }
                            
                            Text("Firma condivisa con tutti gli utenti (CloudKit)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if !uploadMessage.isEmpty {
                                Text(uploadMessage)
                                    .font(.caption)
                                    .foregroundColor(uploadMessage.contains("successo") ? .green : .red)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .fileImporter(
            isPresented: $showingIndividualPicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleIndividualSignatureSelection(result: result)
        }
        .fileImporter(
            isPresented: $showingStudioPicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleStudioSignatureSelection(result: result)
        }
    }
    
    private func handleIndividualSignatureSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                print("[SignatureSettings] ⚠️ Nessun URL selezionato")
                return
            }
            
            print("[SignatureSettings] 📁 URL selezionato: \(url.path)")
            
            // Ottieni accesso security-scoped se necessario
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            guard let image = NSImage(contentsOf: url) else {
                print("[SignatureSettings] ❌ Impossibile caricare immagine da: \(url.path)")
                return
            }
            
            print("[SignatureSettings] ✅ Immagine caricata: \(image.size)")
            signatureService.setIndividualSignature(image)
            print("[SignatureSettings] ✅ Firma individuale salvata")
            
        case .failure(let error):
            print("[SignatureSettings] ❌ Errore selezione file: \(error.localizedDescription)")
        }
    }
    
    private func handleStudioSignatureSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                print("[SignatureSettings] ⚠️ Nessun URL selezionato")
                uploadMessage = "Errore: nessun file selezionato"
                return
            }
            
            print("[SignatureSettings] 📁 URL selezionato: \(url.path)")
            
            // Ottieni accesso security-scoped se necessario
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            guard let image = NSImage(contentsOf: url) else {
                print("[SignatureSettings] ❌ Impossibile caricare immagine da: \(url.path)")
                uploadMessage = "Errore: impossibile caricare l'immagine"
                return
            }
            
            print("[SignatureSettings] ✅ Immagine caricata: \(image.size)")
            
            isUploadingStudio = true
            uploadMessage = "Caricamento in corso..."
            
            Task {
                await signatureService.setStudioSignature(image)
                await MainActor.run {
                    isUploadingStudio = false
                    if signatureService.studioSignature != nil {
                        uploadMessage = "Firma caricata con successo"
                        print("[SignatureSettings] ✅ Firma studio caricata su CloudKit")
                    } else {
                        uploadMessage = "Errore nel caricamento su CloudKit"
                        print("[SignatureSettings] ❌ Firma studio non caricata")
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        uploadMessage = ""
                    }
                }
            }
        case .failure(let error):
            print("[SignatureSettings] ❌ Errore selezione file: \(error.localizedDescription)")
            isUploadingStudio = false
            uploadMessage = "Errore nel caricamento: \(error.localizedDescription)"
        }
    }
}
