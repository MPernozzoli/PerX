import SwiftUI

struct WhatsAppBridgeSettingsView: View {
    @ObservedObject private var whatsappService = WhatsAppService.shared
    
    @State private var isConnecting = false
    @State private var showingQRPopover = false
    @State private var errorMessage: String?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("WhatsApp Bridge")
                        .font(.headline)
                    
                    Spacer()
                    
                    bridgeStatusBadge
                }

                Text("La connessione WhatsApp è gestita tramite Hub.")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                // QR Code button (se serve scansione)
                if whatsappService.qrCode != nil {
                    HStack {
                        Image(systemName: "qrcode")
                            .foregroundColor(.orange)
                        Text("Scansione QR richiesta")
                            .font(.caption)
                            .foregroundColor(.orange)
                        
                        Spacer()
                        
                        Button("Mostra QR") {
                            showingQRPopover = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
                
                // Error message
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.1)))
                }

                // Connessione/Disconnessione
                HStack {
                    Spacer()
                    
                    if whatsappService.isConnected {
                        Button(role: .destructive) {
                            Task {
                                await whatsappService.disconnect()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle")
                                Text("Disconnetti")
                            }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            connect()
                        } label: {
                            if isConnecting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                    Text("Connetti WhatsApp")
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isConnecting)
                    }
                }
            }
            .padding()
        }
        .popover(isPresented: $showingQRPopover) {
            qrCodePopover
        }
    }
    
    // MARK: - Status Badge
    
    @ViewBuilder
    private var bridgeStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(statusColor.opacity(0.1))
        )
    }
    
    private var statusColor: Color {
        if whatsappService.isConnected { return .green }
        if whatsappService.qrCode != nil { return .orange }
        return .red
    }
    
    private var statusText: String {
        if whatsappService.isConnected { return "Online" }
        if whatsappService.qrCode != nil { return "QR Pronto" }
        return "Offline"
    }
    
    // MARK: - QR Code Popover
    
    @ViewBuilder
    private var qrCodePopover: some View {
        VStack(spacing: 16) {
            Text("Scansiona con WhatsApp")
                .font(.headline)
            
            if let qrCode = whatsappService.qrCode,
               let base64 = extractBase64(from: qrCode),
               let data = Data(base64Encoded: base64),
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 250, height: 250)
                    .background(Color.white)
                    .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Caricamento QR...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 250, height: 250)
            }
            
            Text("WhatsApp → Impostazioni → Dispositivi collegati")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Button("Chiudi") {
                showingQRPopover = false
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(width: 320)
    }
    
    private func extractBase64(from dataUrl: String) -> String? {
        if dataUrl.contains(",") {
            return String(dataUrl.split(separator: ",").last ?? "")
        }
        return dataUrl
    }
    
    // MARK: - Actions
    
    private func connect() {
        isConnecting = true
        errorMessage = nil
        
        Task {
            do {
                try await whatsappService.connect()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            
            await MainActor.run {
                isConnecting = false
            }
        }
    }
}
