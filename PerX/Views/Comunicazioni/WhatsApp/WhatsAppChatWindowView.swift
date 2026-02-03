import SwiftUI

/// View wrapper per aprire una chat WhatsApp in una finestra separata
struct WhatsAppChatWindowView: View {
    let chat: WhatsAppChat
    
    @ObservedObject private var viewModel = WhatsAppViewModel.shared
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        WhatsAppDetailView(viewModel: viewModel, chat: chat)
            .environment(\.managedObjectContext, viewContext)
            .onAppear {
                // Setta la chat attiva per le notifiche
                WhatsAppNotificationService.shared.activeChatId = chat.id
                
                // Seleziona la chat nel viewModel
                viewModel.selectChat(chat.id)
                
                // Carica messaggi
                Task {
                    await viewModel.fetchMessages(for: chat.id)
                }
            }
            .onDisappear {
                // Rimuovi chat attiva
                if WhatsAppNotificationService.shared.activeChatId == chat.id {
                    WhatsAppNotificationService.shared.activeChatId = nil
                }
            }
    }
}

/// View per aprire una nuova chat con un numero specifico (da SinistroDetailView)
struct WhatsAppNewChatWindowView: View {
    let phoneNumber: String
    let prefilledMessage: String
    let sinistroRiferimento: String?
    
    @ObservedObject private var viewModel = WhatsAppViewModel.shared
    @ObservedObject private var service = WhatsAppService.shared
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var messageText: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var messageSent = false
    @State private var isCheckingNumber = false
    @State private var isNumberRegistered: Bool? = nil
    
    init(phoneNumber: String, prefilledMessage: String = "", sinistroRiferimento: String? = nil) {
        self.phoneNumber = phoneNumber
        self.prefilledMessage = prefilledMessage
        self.sinistroRiferimento = sinistroRiferimento
        _messageText = State(initialValue: prefilledMessage)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            if !service.isConnected {
                notConnectedView
            } else if isCheckingNumber {
                checkingNumberView
            } else if isNumberRegistered == false {
                numberNotRegisteredView
            } else if messageSent {
                messageSentView
            } else {
                composeView
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .background(Color(.controlBackgroundColor))
        .onAppear {
            if service.isConnected && isNumberRegistered == nil {
                checkNumber()
            }
        }
        .onChange(of: service.isConnected) { _, newValue in
            if newValue && isNumberRegistered == nil {
                checkNumber()
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "message.fill")
                .font(.title2)
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Nuovo messaggio WhatsApp")
                    .font(.headline)
                Text(formattedPhoneNumber)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let ref = sinistroRiferimento {
                Text(ref)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor))
    }
    
    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("WhatsApp non connesso")
                .font(.headline)
            
            Text("Connettiti a WhatsApp dalle impostazioni per inviare messaggi")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var checkingNumberView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Verifica numero WhatsApp...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var numberNotRegisteredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Numero non su WhatsApp")
                .font(.headline)
            
            Text("Il numero \(formattedPhoneNumber) non è registrato su WhatsApp")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Button("Chiama") {
                    if let url = URL(string: "tel:\(phoneNumber)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                
                Button("Invia comunque") {
                    isNumberRegistered = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var messageSentView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("Messaggio inviato!")
                .font(.headline)
            
            Button("Invia un altro messaggio") {
                messageSent = false
                messageText = ""
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var composeView: some View {
        VStack(spacing: 0) {
            // Messaggio
            TextEditor(text: $messageText)
                .font(.body)
                .frame(minHeight: 200)
                .padding()
            
            Divider()
            
            // Footer con tasto invia
            HStack {
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                Button(action: sendMessage) {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Invia", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
        }
    }
    
    private var formattedPhoneNumber: String {
        var number = phoneNumber
        if number.hasPrefix("39") && number.count > 10 {
            let index = number.index(number.startIndex, offsetBy: 2)
            number = "+39 \(number[index...])"
        } else if !number.hasPrefix("+") {
            number = "+\(number)"
        }
        return number
    }
    
    private func checkNumber() {
        isCheckingNumber = true
        
        Task {
            do {
                let registered = try await WhatsAppService.shared.checkNumberRegistered(phoneNumber: phoneNumber)
                isNumberRegistered = registered
            } catch {
                // In caso di errore, permetti comunque l'invio
                isNumberRegistered = true
            }
            isCheckingNumber = false
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSending = true
        errorMessage = nil
        
        Task {
            do {
                // Normalizza numero per WhatsApp
                var normalizedNumber = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                if !normalizedNumber.contains("@") {
                    normalizedNumber = "\(normalizedNumber)@c.us"
                }
                
                _ = try await WhatsAppService.shared.sendMessage(
                    to: normalizedNumber,
                    body: messageText
                )
                
                messageSent = true
                
            } catch {
                errorMessage = error.localizedDescription
            }
            
            isSending = false
        }
    }
}
