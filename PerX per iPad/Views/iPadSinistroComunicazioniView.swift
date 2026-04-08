//
//  iPadSinistroComunicazioniView.swift
//  PerX per iPad
//
//  Vista comunicazioni (email/WA) per un singolo sinistro.
//

import SwiftUI

struct iPadSinistroComunicazioniView: View {
    let riferimento: String
    let emails: [ProcessedEmailDTO]
    let whatsappMessages: [WhatsAppMessageDTO]
    
    @EnvironmentObject var session: SessionCoordinator
    @State private var selectedTab: ComunicazioneTab = .email
    @State private var selectedEmail: ProcessedEmailDTO?
    @State private var showingComposeEmail = false
    @State private var showingComposeWA = false
    
    enum ComunicazioneTab: String, CaseIterable {
        case email = "Email"
        case whatsapp = "WhatsApp"
        
        var icon: String {
            switch self {
            case .email: return "envelope.fill"
            case .whatsapp: return "message.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("Tipo", selection: $selectedTab) {
                ForEach(ComunicazioneTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            // Content
            switch selectedTab {
            case .email:
                emailListView
            case .whatsapp:
                whatsappListView
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingComposeEmail = true
                    } label: {
                        Label("Nuova Email", systemImage: "envelope")
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
            ComposeEmailView(prefilledRiferimento: riferimento)
        }
        .sheet(isPresented: $showingComposeWA) {
            ComposeWhatsAppView(prefilledRiferimento: riferimento)
        }
    }
    
    // MARK: - Email List
    
    @ViewBuilder
    private var emailListView: some View {
        if emails.isEmpty {
            ContentUnavailableView(
                "Nessuna email",
                systemImage: "envelope",
                description: Text("Le email associate appariranno qui")
            )
        } else {
            List(emails) { email in
                EmailRow(email: email)
                    .onTapGesture {
                        selectedEmail = email
                    }
            }
            .listStyle(.plain)
        }
    }
    
    // MARK: - WhatsApp List
    
    @ViewBuilder
    private var whatsappListView: some View {
        if whatsappMessages.isEmpty {
            ContentUnavailableView(
                "Nessun messaggio",
                systemImage: "message",
                description: Text("I messaggi WhatsApp appariranno qui")
            )
        } else {
            List(whatsappMessages) { message in
                WhatsAppRow(message: message)
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Email Row

struct EmailRow: View {
    let email: ProcessedEmailDTO
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(email.subject)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    
                    Text(email.from)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    if let date = email.date {
                        Text(date, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(date, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let category = email.category {
                Text(category)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - WhatsApp Row

struct WhatsAppRow: View {
    let message: WhatsAppMessageDTO
    
    var body: some View {
        HStack(spacing: 12) {
            // Direction indicator
            Image(systemName: message.direction == "outbound" ? "arrow.up.right" : "arrow.down.left")
                .foregroundColor(message.direction == "outbound" ? .blue : .green)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.from)
                        .font(.subheadline.bold())
                    
                    Spacer()
                    
                    Text(message.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(message.body)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                if let mediaType = message.mediaType {
                    Label(mediaType, systemImage: "paperclip")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
