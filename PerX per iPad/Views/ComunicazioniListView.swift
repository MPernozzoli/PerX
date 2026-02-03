//
//  ComunicazioniListView.swift
//  PerX per iPad
//
//  Vista comunicazioni: email e WhatsApp in sola lettura + composer per outbox.
//

import SwiftUI

struct ComunicazioniListView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var selectedTab: ComunicazioniTab = .outbox
    
    enum ComunicazioniTab: String, CaseIterable {
        case outbox = "In Uscita"
        case email = "Email"
        case whatsapp = "WhatsApp"
        
        var icon: String {
            switch self {
            case .outbox: return "tray.and.arrow.up.fill"
            case .email: return "envelope.fill"
            case .whatsapp: return "message.fill"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar con tabs
            List(selection: $selectedTab) {
                ForEach(ComunicazioniTab.allCases, id: \.self) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.rawValue, systemImage: tab.icon)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Comunicazioni")
        } detail: {
            switch selectedTab {
            case .outbox:
                OutboxListView()
            case .email:
                iPadEmailListView()
            case .whatsapp:
                iPadWhatsAppListView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Outbox List

struct OutboxListView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var showingComposeEmail = false
    @State private var showingComposeWA = false
    
    private var outboxService: CloudKitOutboxService? {
        session.outboxService
    }
    
    var body: some View {
        List {
            Section("Email in uscita") {
                if outboxService?.pendingEmailRequests.isEmpty == true {
                    Text("Nessuna email in coda")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(outboxService?.pendingEmailRequests ?? []) { request in
                        OutgoingEmailRow(request: request)
                    }
                }
            }
            
            Section("WhatsApp in uscita") {
                if outboxService?.pendingWhatsAppRequests.isEmpty == true {
                    Text("Nessun messaggio in coda")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(outboxService?.pendingWhatsAppRequests ?? []) { request in
                        OutgoingWhatsAppRow(request: request)
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
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await outboxService?.fetchPendingRequests()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .refreshable {
            await outboxService?.fetchPendingRequests()
        }
        .sheet(isPresented: $showingComposeEmail) {
            ComposeEmailView()
        }
        .sheet(isPresented: $showingComposeWA) {
            ComposeWhatsAppView()
        }
    }
}

// MARK: - Outgoing Email Row

struct OutgoingEmailRow: View {
    let request: OutgoingEmailRequest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: request.status.iconName)
                    .foregroundColor(statusColor)
                
                Text(request.subject)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Text(request.status.displayName)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
            
            Text("A: \(request.toRecipients.joined(separator: ", "))")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            Text(request.createdAt, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if let error = request.statusMessage, request.status == .failed {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch request.status {
        case .queued: return .blue
        case .processing: return .orange
        case .sent: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

// MARK: - Outgoing WhatsApp Row

struct OutgoingWhatsAppRow: View {
    let request: OutgoingWhatsAppRequest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: request.status.iconName)
                    .foregroundColor(statusColor)
                
                Text(request.targetPhoneNumber ?? request.targetChatId ?? "Destinatario")
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Text(request.status.displayName)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
            
            Text(request.message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            Text(request.createdAt, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch request.status {
        case .queued: return .blue
        case .processing: return .orange
        case .sent: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

// MARK: - Email List (Read-only from CK)

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
                            
                            Text(email.date, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.insetGrouped)
            }
        }
        .task {
            // TODO: Fetch emails from CloudKit
            // Per ora mostra solo placeholder
        }
    }
}

// MARK: - WhatsApp List (Read-only from CK)

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
            // TODO: Fetch WA messages from CloudKit
        }
    }
}

// MARK: - Compose Email View

struct ComposeEmailView: View {
    @EnvironmentObject var session: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    
    @State private var toRecipients = ""
    @State private var subject = ""
    @State private var body = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    
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
                    
                    TextEditor(text: $body)
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
        
        let recipients = toRecipients.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        do {
            _ = try await session.outboxService?.createEmailRequest(
                to: recipients,
                subject: subject,
                body: body
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
    @EnvironmentObject var session: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    
    @State private var phoneNumber = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    
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
            _ = try await session.outboxService?.createWhatsAppRequest(
                phoneNumber: phoneNumber,
                message: message
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isSending = false
    }
}
