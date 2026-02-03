import SwiftUI
import CoreImage.CIFilterBuiltins

struct WhatsAppContainerView: View {
    @ObservedObject var viewModel: WhatsAppViewModel
    @Binding var selectedChatId: String?
    
    @State private var searchText = ""
    @State private var filterByUnread = false
    @State private var hasTriedConnect = false
    
    // Hub config per verificare connessione
    @ObservedObject private var hubConfig = HubConfigService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerToolbar
            
            // Lista chat, QR code, o messaggio setup
            if viewModel.isConnected {
                chatListView
            } else if let qrCode = viewModel.qrCode, !qrCode.isEmpty {
                qrCodeView(qrCode: qrCode)
            } else {
                setupRequiredView
            }
        }
        .background(Color(.controlBackgroundColor))
        .onAppear {
            // Avvia connessione automatica se Hub è raggiungibile
            if hubConfig.isHubReachable && !viewModel.isConnected && !viewModel.isLoading && !hasTriedConnect {
                hasTriedConnect = true
                Task {
                    await viewModel.connect()
                }
            }
        }
        .alert("Errore WhatsApp", isPresented: .init(
            get: { viewModel.errorMessage != nil && !viewModel.isLoading },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
            Button("Riprova") {
                Task { await viewModel.connect() }
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
    
    // MARK: - QR Code View
    private func qrCodeView(qrCode: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "qrcode")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("Scansiona il QR Code")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Apri WhatsApp sul tuo telefono, vai su Impostazioni > Dispositivi collegati > Collega un dispositivo e scansiona il codice.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // Genera immagine QR
            if let qrImage = generateQRCode(from: qrCode) {
                Image(nsImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 250, height: 250)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 4)
            } else {
                // Fallback: mostra il QR come testo (per debug)
                Text(qrCode)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
            }
            
            Button("Riprova") {
                Task {
                    await viewModel.restartConnection()
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// Genera immagine QR da stringa
    private func generateQRCode(from string: String) -> NSImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let ciImage = filter.outputImage else { return nil }
        
        // Scala l'immagine
        let scale = 10.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = ciImage.transformed(by: transform)
        
        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        
        return nsImage
    }
    
    // MARK: - Setup Required View
    private var setupRequiredView: some View {
        VStack(spacing: 16) {
            if viewModel.isLoading {
                // In attesa di connessione
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                
                Text("Connessione in corso...")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Inizializzazione WhatsApp tramite Hub. Attendi...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                ProgressView()
                    .padding(.top, 8)
                
            } else if !hubConfig.isHubReachable {
                // Hub non raggiungibile
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("Hub non raggiungibile")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Verifica che l'Hub sia attivo e connesso. WhatsApp richiede l'Hub per funzionare.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                if !hubConfig.hubBaseURL.isEmpty {
                    Text("Hub URL: \(hubConfig.hubBaseURL)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button("Riprova") {
                    Task {
                        await hubConfig.checkHubHealth()
                        if hubConfig.isHubReachable {
                            await viewModel.connect()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
                
            } else {
                // Hub raggiungibile, pronto per connessione
                Image(systemName: "message.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                
                Text("Connetti WhatsApp")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Premi il pulsante per collegare WhatsApp. Dovrai scansionare un QR code dal tuo telefono.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Button("Connetti") {
                    Task {
                        await viewModel.connect()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 12)
                
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                    
                    Button("Riprova") {
                        Task {
                            await viewModel.connect()
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Header Toolbar
    private var headerToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Chat")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Contatore chat
                if !viewModel.chats.isEmpty {
                    Text("\(viewModel.chats.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Pulsante refresh
                Button(action: {
                    Task {
                        await viewModel.fetchChats()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Aggiorna")
                
                // Menu impostazioni
                Menu {
                    Button {
                        Task {
                            await viewModel.disconnect()
                        }
                    } label: {
                        Label("Disconnetti WhatsApp", systemImage: "xmark.circle")
                    }
                    .help("Disconnette WhatsApp (sessione lato bridge)")
                    
                    Divider()
                    
                    Button {
                        Task {
                            await viewModel.restartConnection()
                        }
                    } label: {
                        Label("Riconnetti", systemImage: "arrow.clockwise")
                    }
                    .help("Forza una riconnessione al bridge")
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Impostazioni WhatsApp")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.controlBackgroundColor))
            
            // Barra ricerca
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                
                TextField("Cerca chat...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            
            Divider()
        }
    }
    
    // MARK: - Chat List View
    private var chatListView: some View {
        Group {
            if viewModel.isLoading && viewModel.chats.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("Caricamento chat...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
            } else if filteredChats.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "message.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Nessuna chat")
                        .font(.headline)
                        .padding(.top, 8)
                    Text("Le chat appariranno qui quando invii o ricevi messaggi")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Nota informativa
                    GroupBox {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sincronizzazione messaggi")
                                    .font(.caption.bold())
                                Text("Vengono sincronizzati solo i nuovi messaggi inviati e ricevuti dopo la connessione. I messaggi precedenti non vengono importati.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxWidth: 350)
                    .padding(.top, 16)
                    
                    Spacer()
                }
            } else {
                List(selection: $selectedChatId) {
                    ForEach(filteredChats) { chat in
                        WhatsAppChatRow(chat: chat)
                            .tag(chat.id)
                            .listRowBackground(
                                selectedChatId == chat.id ?
                                Color.accentColor.opacity(0.2) :
                                Color(.controlBackgroundColor)
                            )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
    
    // MARK: - Computed Properties
    private var filteredChats: [WhatsAppChat] {
        var filtered = viewModel.chats
        
        if filterByUnread {
            filtered = filtered.filter { $0.unreadCount > 0 }
        }
        
                if !searchText.isEmpty {
            filtered = filtered.filter { chat in
                chat.name.localizedCaseInsensitiveContains(searchText) ||
                (chat.phoneNumber ?? "").localizedCaseInsensitiveContains(searchText) ||
                (chat.lastMessage ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered
    }
}

// MARK: - Chat Row
struct WhatsAppChatRow: View {
    let chat: WhatsAppChat
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                if let profilePicture = chat.profilePicture, !profilePicture.isEmpty {
                    AsyncImage(url: URL(string: profilePicture)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: chat.isGroup ? "person.2.circle.fill" : "person.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    Image(systemName: chat.isGroup ? "person.2.circle.fill" : "person.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.accentColor)
                }
            }
            
            // Contenuto
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.name)
                        .font(.subheadline)
                        .fontWeight(chat.unreadCount > 0 ? .semibold : .medium)
                        .lineLimit(1)
                    
                    // Badge sinistro associato
                    if let sinistro = chat.sinistroRiferimento, !sinistro.isEmpty {
                        Text(sinistro)
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    if let lastMessageDate = chat.lastMessageDate {
                        Text(lastMessageDate.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    if let lastMessage = chat.lastMessage, !lastMessage.isEmpty {
                        Text(lastMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Nessun messaggio")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    
                    Spacer()
                    
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .cornerRadius(10)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

