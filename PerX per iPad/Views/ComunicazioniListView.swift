//
//  ComunicazioniListView.swift
//  PerX per iPad
//
//  Vista comunicazioni: email e WhatsApp tramite Hub.
//

import SwiftUI
import Combine

struct ComunicazioniListView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var selectedTab: ComunicazioniTab = .outbox
    @State private var incomingCall: CommunicationIncomingCallItem?
    @State private var showIncomingCallAlert = false
    
    enum ComunicazioniTab: String, CaseIterable, Hashable {
        case outbox = "In Uscita"
        case telefono = "Telefono"
        case email = "Email"
        case whatsapp = "WhatsApp"
        case messaggi = "Messaggi interni"

        var icon: String {
            switch self {
            case .outbox: return "tray.and.arrow.up.fill"
            case .telefono: return "phone.fill"
            case .email: return "envelope.fill"
            case .whatsapp: return "message.fill"
            case .messaggi: return "bubble.left.and.bubble.right.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ComunicazioniTabBar(selected: $selectedTab)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Comunicazioni")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(IncomingCallPoller.shared.incomingCall) { item in
            incomingCall = item
            showIncomingCallAlert = true
            RingbackPlayer.shared.start()
        }
        .alert(
            "Chiamata in arrivo",
            isPresented: $showIncomingCallAlert,
            presenting: incomingCall
        ) { item in
            Button("Rispondi") {
                RingbackPlayer.shared.stop()
                selectedTab = .telefono
            }
            Button("Rifiuta", role: .destructive) {
                RingbackPlayer.shared.stop()
            }
        } message: { item in
            Text(item.displayName ?? "Comunicazione PerX")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .outbox:
            OutboxListView()
        case .telefono:
            TelefonoCommunicationView()
        case .email:
            iPadMailView()
        case .whatsapp:
            iPadWhatsAppView()
        case .messaggi:
            ChatListView()
        }
    }
}

// MARK: - Top Tab Bar

private struct ComunicazioniTabBar: View {
    @Binding var selected: ComunicazioniListView.ComunicazioniTab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ComunicazioniListView.ComunicazioniTab.allCases, id: \.self) { tab in
                    Button {
                        selected = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.callout)
                            Text(tab.rawValue)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(
                                selected == tab
                                    ? Color.accentColor.opacity(0.18)
                                    : Color(.tertiarySystemFill)
                            )
                        )
                        .foregroundStyle(selected == tab ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
    }
}

// MARK: - Outbox List

struct OutboxListView: View {
    @EnvironmentObject var session: SessionCoordinator
    @StateObject private var outboxService = HubOutboxService.shared
    @State private var showingComposeEmail = false
    @State private var showingComposeWA = false
    
    var body: some View {
        List {
            if outboxService.pendingRequests.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Nessuna richiesta in coda",
                        systemImage: "tray",
                        description: Text("Le richieste in uscita appariranno qui")
                    )
                }
            } else {
                Section("Richieste in corso") {
                    ForEach(outboxService.pendingRequests) { request in
                        OutboxRequestRow(request: request)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingComposeEmail = true
                    } label: {
                        Label("Nuova email", systemImage: "envelope")
                    }
                    
                    Button {
                        showingComposeWA = true
                    } label: {
                        Label("Nuovo WhatsApp", systemImage: "message")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingComposeEmail) {
            ComposeEmailView()
        }
        .sheet(isPresented: $showingComposeWA) {
            ComposeWhatsAppView()
        }
    }
}

// MARK: - Outbox Request Row

struct OutboxRequestRow: View {
    let request: OutboxRequest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: request.type.icon)
                    .foregroundColor(statusColor)
                
                Text(request.type.label)
                    .font(.headline)
                
                Spacer()
                
                Text(request.status.label)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
            
            Text(request.details)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            Text(request.createdAt, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if let error = request.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch request.status {
        case .sending: return .orange
        case .sent: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Email List (Read-only from CK/Hub)

struct EmailListView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var emails: [ProcessedEmailDTO] = []
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if emails.isEmpty {
                ContentUnavailableView(
                    "Nessuna email",
                    systemImage: "envelope",
                    description: Text("Le email processate appariranno qui")
                )
            } else {
                List(emails) { email in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(email.subject)
                            .font(.headline)
                            .lineLimit(1)
                        
                        Text(email.from)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            if let category = email.category {
                                Text(category)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            
                            Spacer()

                            if let date = email.date {
                                Text(date, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.insetGrouped)
            }
        }
        .task {
            // TODO: Fetch emails from Hub/CloudKit
        }
    }
}

// MARK: - WhatsApp List (Read-only from CK/Hub)

struct WhatsAppListView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var messages: [WhatsAppMessageDTO] = []
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if messages.isEmpty {
                ContentUnavailableView(
                    "Nessun messaggio",
                    systemImage: "message",
                    description: Text("I messaggi WhatsApp appariranno qui")
                )
            } else {
                List(messages) { msg in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: msg.direction == "outbound" ? "arrow.up.right" : "arrow.down.left")
                                .foregroundColor(msg.direction == "outbound" ? .blue : .green)
                            
                            Text(msg.from)
                                .font(.headline)
                            
                            Spacer()
                            
                            Text(msg.timestamp, style: .time)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(msg.body)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.insetGrouped)
            }
        }
        .task {
            // TODO: Fetch WA messages from Hub/CloudKit
        }
    }
}

// MARK: - Compose Email View

struct ComposeEmailView: View {
    let prefilledRiferimento: String?

    @EnvironmentObject var session: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    
    @State private var toRecipients: String
    @State private var subject: String
    @State private var bodyText: String
    @State private var isSending = false
    @State private var errorMessage: String?

    init(prefilledRiferimento: String? = nil) {
        self.prefilledRiferimento = prefilledRiferimento
        _toRecipients = State(initialValue: "")
        _subject = State(initialValue: prefilledRiferimento.map { "Rif. \($0) - " } ?? "")
        _bodyText = State(initialValue: "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Destinatari") {
                    TextField("A (separati da virgola)", text: $toRecipients)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                
                Section("Messaggio") {
                    TextField("Oggetto", text: $subject)
                    
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 200)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Nuova Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invia") {
                        Task { await sendEmail() }
                    }
                    .disabled(toRecipients.isEmpty || subject.isEmpty || isSending)
                }
            }
        }
    }
    
    private func sendEmail() async {
        isSending = true
        errorMessage = nil
        
        let recipients = toRecipients
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        do {
            _ = try await HubOutboxService.shared.sendEmail(
                to: recipients,
                subject: subject,
                body: bodyText,
                sinistroRiferimento: prefilledRiferimento
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isSending = false
    }
}

// MARK: - Compose WhatsApp View

struct ComposeWhatsAppView: View {
    let prefilledRiferimento: String?

    @EnvironmentObject var session: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    
    @State private var phoneNumber: String
    @State private var message: String
    @State private var isSending = false
    @State private var errorMessage: String?

    init(prefilledRiferimento: String? = nil) {
        self.prefilledRiferimento = prefilledRiferimento
        _phoneNumber = State(initialValue: "")
        _message = State(initialValue: prefilledRiferimento.map { "Rif. \($0)\n" } ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Destinatario") {
                    TextField("Numero di telefono", text: $phoneNumber)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }
                
                Section("Messaggio") {
                    TextEditor(text: $message)
                        .frame(minHeight: 150)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Nuovo WhatsApp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invia") {
                        Task { await sendWhatsApp() }
                    }
                    .disabled(phoneNumber.isEmpty || message.isEmpty || isSending)
                }
            }
        }
    }
    
    private func sendWhatsApp() async {
        isSending = true
        errorMessage = nil
        
        do {
            _ = try await HubOutboxService.shared.sendWhatsApp(
                phoneNumber: phoneNumber,
                message: message,
                sinistroRiferimento: prefilledRiferimento
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isSending = false
    }
}
