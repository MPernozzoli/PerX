//
//  iPadEmailListView.swift
//  PerX per iPad
//
//  Vista email completa con lista e dettaglio.
//

import SwiftUI
import WebKit

struct iPadEmailListView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var emails: [ProcessedEmailDTO] = []
    @State private var selectedEmail: ProcessedEmailDTO?
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var showingCompose = false
    
    private var filteredEmails: [ProcessedEmailDTO] {
        if searchText.isEmpty {
            return emails
        }
        let query = searchText.lowercased()
        return emails.filter {
            $0.subject.lowercased().contains(query) ||
            $0.from.lowercased().contains(query)
        }
    }
    
    var body: some View {
        NavigationSplitView {
            emailListSidebar
        } detail: {
            if let email = selectedEmail {
                EmailDetailContentView(email: email)
            } else {
                ContentUnavailableView(
                    "Seleziona un'email",
                    systemImage: "envelope",
                    description: Text("Scegli un'email dalla lista")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingCompose) {
            ComposeEmailView()
        }
        .task {
            await loadEmails()
        }
    }
    
    @ViewBuilder
    private var emailListSidebar: some View {
        List {
            ForEach(filteredEmails, id: \.id) { email in
                Button {
                    selectedEmail = email
                } label: {
                    EmailListRow(email: email)
                }
                .buttonStyle(.plain)
                .listRowBackground(selectedEmail?.id == email.id ? Color.accentColor.opacity(0.2) : Color.clear)
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Cerca email...")
        .navigationTitle("Email")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCompose = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadEmails() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .refreshable {
            await loadEmails()
        }
        .overlay {
            if isLoading && emails.isEmpty {
                ProgressView()
            } else if emails.isEmpty {
                ContentUnavailableView(
                    "Nessuna email",
                    systemImage: "envelope",
                    description: Text("Le email processate appariranno qui")
                )
            }
        }
    }
    
    private func loadEmails() async {
        isLoading = true
        defer { isLoading = false }
        
        // Carica email da CloudKit
        // Per ora placeholder - da implementare con fetchProcessedEmails generico
    }
}

// MARK: - Email List Row

struct EmailListRow: View {
    let email: ProcessedEmailDTO
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(email.from.components(separatedBy: "<").first?.trimmingCharacters(in: .whitespaces) ?? email.from)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                
                Spacer()

                if let date = email.date {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(email.subject)
                .font(.subheadline)
                .lineLimit(2)
            
            HStack {
                if let category = email.category {
                    Text(category)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(categoryColor(category).opacity(0.15))
                        .foregroundColor(categoryColor(category))
                        .cornerRadius(4)
                }
                
                if let rif = email.sinistroRiferimento {
                    Text(rif)
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func categoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "compagnia": return .purple
        case "agenzia": return .orange
        case "assicurato": return .green
        case "liquidatore": return .blue
        default: return .gray
        }
    }
}

// MARK: - Email Detail Content View

struct EmailDetailContentView: View {
    let email: ProcessedEmailDTO
    
    @EnvironmentObject var session: SessionCoordinator
    @State private var showingReply = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    Text(email.subject)
                        .font(.title2.bold())
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Da: \(email.from)")
                                .font(.subheadline)

                            if let date = email.date {
                                Text(date, format: .dateTime.day().month().year().hour().minute())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if let category = email.category {
                            Text(category)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(16)
                        }
                    }
                    
                    if let rif = email.sinistroRiferimento {
                        Label(rif, systemImage: "folder")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                
                Divider()
                
                // Body placeholder (email body non disponibile in ProcessedEmailDTO)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Contenuto email non disponibile in questa vista.")
                        .foregroundColor(.secondary)
                    
                    Text("L'email è stata processata e catalogata. Per vedere il contenuto completo, accedi dall'app Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingReply = true
                } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                }
                
                Menu {
                    Button {
                        showingReply = true
                    } label: {
                        Label("Rispondi", systemImage: "arrowshape.turn.up.left")
                    }
                    
                    Button {
                        // Forward
                    } label: {
                        Label("Inoltra", systemImage: "arrowshape.turn.up.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingReply) {
            ReplyEmailView(originalEmail: email)
        }
    }
}

// MARK: - Reply Email View

struct ReplyEmailView: View {
    let originalEmail: ProcessedEmailDTO
    
    @EnvironmentObject var session: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var toRecipients = ""
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var isSending = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Destinatari") {
                    TextField("A", text: $toRecipients)
                        .textContentType(.emailAddress)
                }
                
                Section("Messaggio") {
                    TextField("Oggetto", text: $subject)
                    
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 200)
                }
            }
            .navigationTitle("Rispondi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invia") {
                        Task { await sendReply() }
                    }
                    .disabled(toRecipients.isEmpty || isSending)
                }
            }
            .onAppear {
                toRecipients = originalEmail.from
                subject = "Re: \(originalEmail.subject)"
            }
        }
    }
    
    private func sendReply() async {
        isSending = true
        
        let recipients = toRecipients.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        do {
            _ = try await HubOutboxService.shared.sendEmail(
                to: recipients,
                subject: subject,
                body: bodyText,
                sinistroRiferimento: originalEmail.sinistroRiferimento
            )
            dismiss()
        } catch {
            print("Errore invio: \(error)")
        }
        
        isSending = false
    }
}
