//
//  iPadMailView.swift
//  PerX per iPad
//
//  Vista email con thread raggruppati per sinistro (come Mac PrincipaleView)
//

import SwiftUI
import WebKit

// MARK: - Thread View Mode

enum ThreadViewMode: String, CaseIterable {
    case sinistro = "Per Sinistro"
    case oggetto = "Per Oggetto"
}

// MARK: - Email Thread DTO

struct EmailThreadDTO: Identifiable, Hashable {
    let id: String
    let sinistroRiferimento: String?
    let sinistroAssicurato: String?
    let emails: [ProcessedEmailDTO]
    let unreadCount: Int
    let latestDate: Date?
    
    var displayTitle: String {
        if let rif = sinistroRiferimento {
            return rif
        }
        return "Email non associate"
    }
    
    var displaySubtitle: String {
        sinistroAssicurato ?? "\(emails.count) email"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: EmailThreadDTO, rhs: EmailThreadDTO) -> Bool {
        lhs.id == rhs.id
    }
}

struct SubjectThreadDTO: Identifiable, Hashable {
    let id: String
    let subject: String
    let emails: [ProcessedEmailDTO]
    let latestDate: Date?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SubjectThreadDTO, rhs: SubjectThreadDTO) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - iPad Mail View

struct iPadMailView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var viewMode: ThreadViewMode = .sinistro
    @State private var selectedThread: EmailThreadDTO?
    @State private var selectedSubjectThread: SubjectThreadDTO?
    @State private var selectedEmail: ProcessedEmailDTO?
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var showingCompose = false
    
    // Data
    @State private var allEmails: [ProcessedEmailDTO] = []
    @State private var sinistroThreads: [EmailThreadDTO] = []
    @State private var subjectThreads: [SubjectThreadDTO] = []
    
    var body: some View {
        NavigationSplitView {
            threadListSidebar
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingCompose) {
            ComposeEmailView()
        }
        .task {
            await loadEmails()
        }
        .onChange(of: viewMode) { _ in
            selectedThread = nil
            selectedSubjectThread = nil
            selectedEmail = nil
        }
    }
    
    // MARK: - Thread List Sidebar
    
    @ViewBuilder
    private var threadListSidebar: some View {
        VStack(spacing: 0) {
            // View mode picker
            Picker("Modalità", selection: $viewMode) {
                ForEach(ThreadViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Thread list
            if viewMode == .sinistro {
                sinistroThreadList
            } else {
                subjectThreadList
            }
        }
        .navigationTitle("Email")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Cerca...")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showingCompose = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    
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
        }
        .refreshable {
            await loadEmails()
        }
    }
    
    // MARK: - Sinistro Thread List
    
    @ViewBuilder
    private var sinistroThreadList: some View {
        let filtered = filteredSinistroThreads
        
        if isLoading && sinistroThreads.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            ContentUnavailableView {
                Label("Nessun thread", systemImage: "tray")
            } description: {
                Text("I thread verranno creati quando le email sono associate ai sinistri")
            }
        } else {
            List(selection: $selectedThread) {
                ForEach(filtered) { thread in
                    ThreadRowView(thread: thread, isSelected: selectedThread?.id == thread.id)
                        .tag(thread)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
            }
            .listStyle(.plain)
        }
    }
    
    private var filteredSinistroThreads: [EmailThreadDTO] {
        guard !searchText.isEmpty else { return sinistroThreads }
        let query = searchText.lowercased()
        return sinistroThreads.filter { thread in
            thread.displayTitle.lowercased().contains(query) ||
            thread.displaySubtitle.lowercased().contains(query) ||
            thread.emails.contains { $0.subject.lowercased().contains(query) || $0.from.lowercased().contains(query) }
        }
    }
    
    // MARK: - Subject Thread List
    
    @ViewBuilder
    private var subjectThreadList: some View {
        let filtered = filteredSubjectThreads
        
        if isLoading && subjectThreads.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            ContentUnavailableView {
                Label("Nessun thread", systemImage: "tray")
            } description: {
                Text("Le email raggruppate per oggetto appariranno qui")
            }
        } else {
            List(selection: $selectedSubjectThread) {
                ForEach(filtered) { thread in
                    SubjectThreadRowView(thread: thread, isSelected: selectedSubjectThread?.id == thread.id)
                        .tag(thread)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
            }
            .listStyle(.plain)
        }
    }
    
    private var filteredSubjectThreads: [SubjectThreadDTO] {
        guard !searchText.isEmpty else { return subjectThreads }
        let query = searchText.lowercased()
        return subjectThreads.filter { thread in
            thread.subject.lowercased().contains(query) ||
            thread.emails.contains { $0.from.lowercased().contains(query) }
        }
    }
    
    // MARK: - Detail Content
    
    @ViewBuilder
    private var detailContent: some View {
        if viewMode == .sinistro {
            if let thread = selectedThread {
                ThreadDetailView(
                    thread: thread,
                    selectedEmail: $selectedEmail,
                    onOpenSinistro: { riferimento in
                        // TODO: Navigate to sinistro
                        print("Open sinistro: \(riferimento)")
                    }
                )
            } else {
                ContentUnavailableView(
                    "Seleziona un thread",
                    systemImage: "envelope.open",
                    description: Text("Scegli un thread dalla lista per visualizzare le email")
                )
            }
        } else {
            if let thread = selectedSubjectThread {
                SubjectDetailView(
                    thread: thread,
                    selectedEmail: $selectedEmail
                )
            } else {
                ContentUnavailableView(
                    "Seleziona un thread",
                    systemImage: "envelope.open",
                    description: Text("Scegli un thread dalla lista per visualizzare le email")
                )
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadEmails() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let syncService = session.cloudKitSyncService else { return }
        
        // Load all processed emails
        allEmails = await syncService.fetchAllProcessedEmails()
        
        // Group by sinistro
        buildSinistroThreads()
        
        // Group by subject
        buildSubjectThreads()
    }
    
    private func buildSinistroThreads() {
        var threadMap: [String: [ProcessedEmailDTO]] = [:]
        var unassociatedEmails: [ProcessedEmailDTO] = []
        
        for email in allEmails {
            if let riferimento = email.sinistroRiferimento, !riferimento.isEmpty {
                threadMap[riferimento, default: []].append(email)
            } else {
                unassociatedEmails.append(email)
            }
        }
        
        var threads: [EmailThreadDTO] = []
        
        // Create threads for each sinistro
        for (riferimento, emails) in threadMap {
            let sortedEmails = emails.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            let unread = sortedEmails.filter { !$0.isRead }.count
            let latest = sortedEmails.first?.date
            let assicurato = sortedEmails.first?.sinistroAssicurato
            
            threads.append(EmailThreadDTO(
                id: riferimento,
                sinistroRiferimento: riferimento,
                sinistroAssicurato: assicurato,
                emails: sortedEmails,
                unreadCount: unread,
                latestDate: latest
            ))
        }
        
        // Add unassociated emails as a special thread
        if !unassociatedEmails.isEmpty {
            let sorted = unassociatedEmails.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            threads.append(EmailThreadDTO(
                id: "_unassociated_",
                sinistroRiferimento: nil,
                sinistroAssicurato: nil,
                emails: sorted,
                unreadCount: sorted.filter { !$0.isRead }.count,
                latestDate: sorted.first?.date
            ))
        }
        
        // Sort by latest date
        sinistroThreads = threads.sorted { ($0.latestDate ?? .distantPast) > ($1.latestDate ?? .distantPast) }
    }
    
    private func buildSubjectThreads() {
        // Normalize subjects for grouping
        func normalizeSubject(_ subject: String) -> String {
            var normalized = subject.lowercased()
            // Remove Re:, Fwd:, etc.
            let prefixes = ["re:", "r:", "fwd:", "fw:", "i:"]
            for prefix in prefixes {
                while normalized.hasPrefix(prefix) {
                    normalized = String(normalized.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                }
            }
            return normalized.trimmingCharacters(in: .whitespaces)
        }
        
        var threadMap: [String: [ProcessedEmailDTO]] = [:]
        
        for email in allEmails {
            let key = normalizeSubject(email.subject)
            threadMap[key, default: []].append(email)
        }
        
        var threads: [SubjectThreadDTO] = []
        
        for (normalizedSubject, emails) in threadMap {
            let sortedEmails = emails.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            let originalSubject = sortedEmails.first?.subject ?? normalizedSubject
            
            threads.append(SubjectThreadDTO(
                id: normalizedSubject,
                subject: originalSubject,
                emails: sortedEmails,
                latestDate: sortedEmails.first?.date
            ))
        }
        
        subjectThreads = threads.sorted { ($0.latestDate ?? .distantPast) > ($1.latestDate ?? .distantPast) }
    }
}

// MARK: - Thread Row View

struct ThreadRowView: View {
    let thread: EmailThreadDTO
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Unread indicator
            Circle()
                .fill(thread.unreadCount > 0 ? Color.blue : Color.clear)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let date = thread.latestDate {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text(thread.displaySubtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Email count badge
                    Text("\(thread.emails.count)")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.gray))
                    
                    // Unread count badge
                    if thread.unreadCount > 0 {
                        Text("\(thread.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue))
                    }
                }
                
                // Preview of latest email subject
                if let latest = thread.emails.first {
                    Text(latest.subject)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
    }
}

// MARK: - Subject Thread Row View

struct SubjectThreadRowView: View {
    let thread: SubjectThreadDTO
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.subject.isEmpty ? "(Nessun oggetto)" : thread.subject)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    if let date = thread.latestDate {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text("\(thread.emails.count) email")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
    }
}

// MARK: - Thread Detail View

struct ThreadDetailView: View {
    let thread: EmailThreadDTO
    @Binding var selectedEmail: ProcessedEmailDTO?
    var onOpenSinistro: ((String) -> Void)?
    
    private var sortedEmails: [ProcessedEmailDTO] {
        thread.emails.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            threadHeader
            
            Divider()
            
            // Split: email list and detail
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Email list
                    emailList
                        .frame(width: geometry.size.width * 0.4)
                    
                    Divider()
                    
                    // Email detail
                    emailDetail
                        .frame(width: geometry.size.width * 0.6)
                }
            }
        }
    }
    
    @ViewBuilder
    private var threadHeader: some View {
        HStack {
            if let riferimento = thread.sinistroRiferimento {
                VStack(alignment: .leading, spacing: 2) {
                    Text(riferimento)
                        .font(.headline)
                    
                    if let assicurato = thread.sinistroAssicurato {
                        Text(assicurato)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    onOpenSinistro?(riferimento)
                } label: {
                    Label("Apri Sinistro", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Text("Email non associate")
                    .font(.headline)
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
    
    @ViewBuilder
    private var emailList: some View {
        List(selection: $selectedEmail) {
            ForEach(sortedEmails, id: \.id) { email in
                EmailRowCompact(email: email, isSelected: selectedEmail?.id == email.id)
                    .tag(email)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            }
        }
        .listStyle(.plain)
    }
    
    @ViewBuilder
    private var emailDetail: some View {
        if let email = selectedEmail {
            ScrollView {
                EmailContentView(email: email)
            }
        } else {
            ContentUnavailableView(
                "Seleziona un'email",
                systemImage: "envelope",
                description: Text("Scegli un'email dalla lista")
            )
        }
    }
}

// MARK: - Subject Detail View

struct SubjectDetailView: View {
    let thread: SubjectThreadDTO
    @Binding var selectedEmail: ProcessedEmailDTO?
    
    private var sortedEmails: [ProcessedEmailDTO] {
        thread.emails.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(thread.subject.isEmpty ? "(Nessun oggetto)" : thread.subject)
                    .font(.headline)
                
                Spacer()
                
                Text("\(thread.emails.count) email")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            
            Divider()
            
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Email list
                    List(selection: $selectedEmail) {
                        ForEach(sortedEmails, id: \.id) { email in
                            EmailRowCompact(email: email, isSelected: selectedEmail?.id == email.id)
                                .tag(email)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        }
                    }
                    .listStyle(.plain)
                    .frame(width: geometry.size.width * 0.4)
                    
                    Divider()
                    
                    // Email detail
                    if let email = selectedEmail {
                        ScrollView {
                            EmailContentView(email: email)
                        }
                        .frame(width: geometry.size.width * 0.6)
                    } else {
                        ContentUnavailableView(
                            "Seleziona un'email",
                            systemImage: "envelope",
                            description: Text("Scegli un'email dalla lista")
                        )
                        .frame(width: geometry.size.width * 0.6)
                    }
                }
            }
        }
    }
}

// MARK: - Email Row Compact

struct EmailRowCompact: View {
    let email: ProcessedEmailDTO
    let isSelected: Bool
    
    private var isSent: Bool {
        email.folder?.lowercased().contains("sent") ?? false
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Direction indicator
            Image(systemName: isSent ? "arrow.up.right" : "arrow.down.left")
                .font(.caption)
                .foregroundColor(isSent ? .green : .blue)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(isSent ? (email.to.first ?? "Destinatario") : email.from)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let date = email.date {
                        Text(date, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(email.subject)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // Read indicator
            if !email.isRead {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            }
            
            // Attachments
            if email.hasAttachments {
                Image(systemName: "paperclip")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
    }
}

// MARK: - Email Content View

struct EmailContentView: View {
    let email: ProcessedEmailDTO
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text(email.subject)
                    .font(.title2.bold())
                
                HStack {
                    Text("Da: \(email.from)")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    if let date = email.date {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(date, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !email.to.isEmpty {
                    Text("A: \(email.to.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if !email.cc.isEmpty {
                    Text("Cc: \(email.cc.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            
            // Body
            if let html = email.bodyHtml, !html.isEmpty {
                HTMLContentView(html: html)
                    .frame(minHeight: 300)
            } else {
                Text(email.bodyText ?? "Nessun contenuto")
                    .font(.body)
                    .padding()
            }
            
            // Attachments
            if email.hasAttachments, !email.attachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allegati")
                        .font(.headline)
                    
                    ForEach(email.attachments, id: \.self) { attachment in
                        HStack {
                            Image(systemName: "doc")
                            Text(attachment)
                            Spacer()
                        }
                        .padding(8)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(6)
                    }
                }
                .padding()
            }
        }
        .padding()
    }
}

// MARK: - HTML Content View

struct HTMLContentView: UIViewRepresentable {
    let html: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let styledHtml = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: 16px;
                    line-height: 1.5;
                    color: #333;
                    padding: 0;
                    margin: 0;
                }
                img { max-width: 100%; height: auto; }
                a { color: #007AFF; }
                @media (prefers-color-scheme: dark) {
                    body { color: #f0f0f0; }
                }
            </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(styledHtml, baseURL: nil)
    }
}

// MARK: - Compose Email View (Placeholder)

struct ComposeEmailView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Componi Email")
                    .font(.title)
                Text("In sviluppo...")
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Nuova Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
    }
}

// MARK: - iPadCloudKitSyncService Extension

extension iPadCloudKitSyncService {
    func fetchAllProcessedEmails() async -> [ProcessedEmailDTO] {
        // TODO: Implementare fetch da CloudKit
        // Per ora ritorna array vuoto
        return []
    }
}
