//
//  iPadSinistroDetailView.swift
//  PerX per iPad
//
//  Vista dettaglio sinistro completa con tutte le sezioni.
//

import SwiftUI

struct iPadSinistroDetailView: View {
    let sinistro: SinistroMinimal
    
    @EnvironmentObject var session: SessionCoordinator
    @State private var fullData: SinistroFull?
    @State private var diarioEntries: [DiarioEntryDTO] = []
    @State private var emails: [ProcessedEmailDTO] = []
    @State private var whatsappMessages: [WhatsAppMessageDTO] = []
    @State private var isLoading = false
    @State private var selectedTab: DetailTab = .dettaglio
    
    enum DetailTab: String, CaseIterable {
        case dettaglio = "Dettaglio"
        case diario = "Diario"
        case cartella = "Cartella"
        case comunicazioni = "Comunicazioni"
        case perizia = "Perizia"
        
        var icon: String {
            switch self {
            case .dettaglio: return "info.circle"
            case .diario: return "book"
            case .cartella: return "folder"
            case .comunicazioni: return "envelope"
            case .perizia: return "doc.text"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header con info sinistro
            headerSection
            
            Divider()
            
            // Tab bar
            tabBar
            
            Divider()
            
            // Content
            tabContent
        }
        .navigationTitle(sinistro.riferimento)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        // Chiama assicurato
                    } label: {
                        Label("Chiama", systemImage: "phone")
                    }
                    
                    Button {
                        // Invia email
                    } label: {
                        Label("Invia Email", systemImage: "envelope")
                    }
                    
                    Button {
                        // Invia WhatsApp
                    } label: {
                        Label("WhatsApp", systemImage: "message")
                    }
                    
                    Divider()
                    
                    Button {
                        Task { await loadAllData() }
                    } label: {
                        Label("Aggiorna", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await loadAllData()
        }
    }
    
    // MARK: - Header
    
    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Info principali
            VStack(alignment: .leading, spacing: 4) {
                Text(sinistro.nomeAssicurato)
                    .font(.title2.bold())
                
                Text(sinistro.nomeCompagnia)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Stato e importo
            VStack(alignment: .trailing, spacing: 8) {
                statusBadge
                
                if let stima = sinistro.stimaDanno, stima > 0 {
                    Text(formatCurrency(stima))
                        .font(.title3.bold())
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(sinistro.stato)
                .font(.caption.bold())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.15))
        .cornerRadius(16)
    }
    
    private var statusColor: Color {
        switch sinistro.stato.lowercased() {
        case "aperto", "in corso", "assegnato":
            return .green
        case "chiuso", "definito":
            return .gray
        case "revocato":
            return .red
        case "sospeso":
            return .orange
        default:
            return .blue
        }
    }
    
    // MARK: - Tab Bar
    
    @ViewBuilder
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.title3)
                            
                            Text(tab.rawValue)
                                .font(.caption)
                        }
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                        .frame(minWidth: 80)
                        .padding(.vertical, 12)
                        .background(
                            VStack {
                                Spacer()
                                if selectedTab == tab {
                                    Rectangle()
                                        .fill(Color.accentColor)
                                        .frame(height: 3)
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    // MARK: - Tab Content
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .dettaglio:
            dettaglioContent
        case .diario:
            diarioContent
        case .cartella:
            cartellaContent
        case .comunicazioni:
            comunicazioniContent
        case .perizia:
            periziaContent
        }
    }
    
    // MARK: - Dettaglio Tab
    
    @ViewBuilder
    private var dettaglioContent: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding(40)
            } else if let full = fullData {
                VStack(spacing: 20) {
                    // Anagrafica
                    DetailSection(title: "Anagrafica", icon: "person.2") {
                        VStack(spacing: 12) {
                            if let nome = full.nomeContraente {
                                DetailRow(label: "Contraente", value: nome)
                            }
                            if let tel = full.telefonoContraente {
                                DetailRow(label: "Telefono", value: tel, actionIcon: "phone.fill") {
                                    callPhone(tel)
                                }
                            }
                            if let email = full.emailContraente {
                                DetailRow(label: "Email", value: email, actionIcon: "envelope.fill") {
                                    // compose email
                                }
                            }
                            
                            if full.nomeAssicurato != nil || full.telefonoAssicurato != nil {
                                Divider()
                                    .padding(.vertical, 4)
                            }
                            
                            if let nome = full.nomeAssicurato {
                                DetailRow(label: "Assicurato", value: nome)
                            }
                            if let tel = full.telefonoAssicurato {
                                DetailRow(label: "Telefono", value: tel, actionIcon: "phone.fill") {
                                    callPhone(tel)
                                }
                            }
                            if let email = full.emailAssicurato {
                                DetailRow(label: "Email", value: email, actionIcon: "envelope.fill") {
                                    // compose email
                                }
                            }
                        }
                    }
                    
                    // Polizza
                    DetailSection(title: "Polizza", icon: "doc.text") {
                        VStack(spacing: 12) {
                            if let num = full.numeroPolizza {
                                DetailRow(label: "N. Polizza", value: num)
                            }
                            if let tipo = full.tipoPolizza {
                                DetailRow(label: "Tipo", value: tipo)
                            }
                            if let numSin = full.numeroSinistroCompagnia {
                                DetailRow(label: "N. Sinistro", value: numSin)
                            }
                            if let agenzia = full.agenzia {
                                DetailRow(label: "Agenzia", value: agenzia)
                            }
                        }
                    }
                    
                    // Importi
                    DetailSection(title: "Importi", icon: "eurosign.circle") {
                        VStack(spacing: 12) {
                            if let richiesta = full.richiesta {
                                DetailRow(label: "Richiesta", value: formatCurrency(richiesta))
                            }
                            if let danno = full.dannoAccertato {
                                DetailRow(label: "Danno accertato", value: formatCurrency(danno))
                            }
                            if let liquidato = full.liquidato {
                                DetailRow(label: "Liquidato", value: formatCurrency(liquidato))
                            }
                        }
                    }
                    
                    // Date
                    DetailSection(title: "Date", icon: "calendar") {
                        VStack(spacing: 12) {
                            if let data = sinistro.dataAssegnazione {
                                DetailRow(label: "Assegnazione", value: formatDate(data))
                            }
                            if let data = sinistro.dataChiusura {
                                DetailRow(label: "Chiusura", value: formatDate(data))
                            }
                        }
                    }
                }
                .padding()
            } else {
                ContentUnavailableView(
                    "Dati non disponibili",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Impossibile caricare i dettagli")
                )
            }
        }
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Diario Tab
    
    @ViewBuilder
    private var diarioContent: some View {
        iPadDiarioView(
            riferimento: sinistro.riferimento,
            entries: $diarioEntries
        )
    }
    
    // MARK: - Cartella Tab
    
    @ViewBuilder
    private var cartellaContent: some View {
        iPadCartellaView(sinistro: sinistro)
    }
    
    // MARK: - Comunicazioni Tab
    
    @ViewBuilder
    private var comunicazioniContent: some View {
        iPadSinistroComunicazioniView(
            riferimento: sinistro.riferimento,
            emails: emails,
            whatsappMessages: whatsappMessages
        )
    }
    
    // MARK: - Perizia Tab
    
    @ViewBuilder
    private var periziaContent: some View {
        iPadPeriziaView(sinistroRiferimento: sinistro.riferimento)
    }
    
    // MARK: - Actions
    
    private func loadAllData() async {
        isLoading = true
        defer { isLoading = false }
        
        async let fullDataTask = session.cloudKitSyncService?.fetchSinistroFull(riferimento: sinistro.riferimento)
        async let diarioTask = session.cloudKitSyncService?.fetchDiarioEntries(riferimento: sinistro.riferimento)
        async let emailsTask = session.cloudKitSyncService?.fetchProcessedEmails(riferimento: sinistro.riferimento)
        async let waTask = session.cloudKitSyncService?.fetchWhatsAppMessages(riferimento: sinistro.riferimento)
        
        do {
            fullData = try await fullDataTask
            diarioEntries = (try await diarioTask) ?? []
            emails = (try await emailsTask) ?? []
            whatsappMessages = (try await waTask) ?? []
        } catch {
            print("Errore caricamento dati: \(error)")
        }
    }
    
    private func callPhone(_ number: String) {
        guard let url = URL(string: "tel://\(number.replacingOccurrences(of: " ", with: ""))") else { return }
        UIApplication.shared.open(url)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        return formatter.string(from: NSNumber(value: value)) ?? "€\(value)"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: date)
    }
}

// MARK: - Detail Section

struct DetailSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var actionIcon: String?
    var action: (() -> Void)?
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            
            if let action = action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(value)
                            .foregroundColor(.accentColor)
                        
                        if let icon = actionIcon {
                            Image(systemName: icon)
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(value)
            }
            
            Spacer()
        }
        .font(.subheadline)
    }
}
