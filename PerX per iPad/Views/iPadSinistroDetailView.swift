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
        .navigationTitle(sinistro.riferimentoVisualizzato)
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
        let color = StatoSinistro.colorFor(descrizione: sinistro.stato)
        let icon = StatoSinistro.iconFor(descrizione: sinistro.stato)
        
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            
            Text(sinistro.stato)
                .font(.caption.bold())
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
    
    private var statusColor: Color {
        StatoSinistro.colorFor(descrizione: sinistro.stato)
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
                VStack(spacing: 16) {
                    // Banner assegnazione
                    if let assigned = full.assignedToUserEmail,
                       let owner = full.ownerEmail,
                       assigned != owner {
                        assignedBanner(assignedTo: full.assignedToUserName ?? assigned)
                    }
                    
                    // Layout a due colonne su iPad
                    HStack(alignment: .top, spacing: 16) {
                        // Colonna sinistra
                        VStack(spacing: 16) {
                            // Compagnia/Agenzia
                            compagniaSection(full)
                            
                            // Attori (Contraente, Assicurato, Danneggiato)
                            attoriSection(full)
                            
                            // Polizza
                            polizzaSection(full)
                        }
                        .frame(maxWidth: .infinity)
                        
                        // Colonna destra
                        VStack(spacing: 16) {
                            // Stato
                            statoSection(full)
                            
                            // Verifiche
                            verificheSection(full)
                            
                            // Importi
                            importiSection(full)
                            
                            // Date
                            dateSection(full)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Sinistri collegati (full width)
                    if let collegamenti = full.collegamenti, !collegamenti.isEmpty {
                        collegamentiSection(collegamenti)
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
    
    // MARK: - Detail Sections
    
    @ViewBuilder
    private func assignedBanner(assignedTo: String) -> some View {
        HStack {
            Image(systemName: "person.badge.clock")
                .foregroundColor(.orange)
            
            Text("Sinistro assegnato a \(assignedTo)")
                .font(.subheadline)
            
            Spacer()
            
            Button("Reclama") {
                // TODO: Implementare reclamo
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func compagniaSection(_ full: SinistroFull) -> some View {
        DetailSection(title: "Compagnia e Agenzia", icon: "building.columns") {
            VStack(spacing: 10) {
                if let gruppo = full.gruppo {
                    DetailRow(label: "Gruppo", value: gruppo)
                }
                if let comp = full.nomeCompagnia {
                    DetailRow(label: "Compagnia", value: comp)
                }
                if let area = full.area {
                    DetailRow(label: "Area", value: area)
                }
                if let div = full.divisioneCompagnia {
                    DetailRow(label: "Divisione", value: div)
                }
                if let numSin = full.numeroSinistroCompagnia {
                    DetailRow(label: "N. Sinistro", value: numSin)
                }
                
                if full.agenzia != nil {
                    Divider()
                    
                    if let agenzia = full.agenzia {
                        DetailRow(label: "Agenzia", value: agenzia)
                    }
                    if let codice = full.codiceAgenzia {
                        DetailRow(label: "Codice", value: codice)
                    }
                    if let tel = full.telefonoAgenzia {
                        DetailRow(label: "Telefono", value: tel, actionIcon: "phone.fill") {
                            callPhone(tel)
                        }
                    }
                    if let email = full.emailAgenzia {
                        DetailRow(label: "Email", value: email, actionIcon: "envelope.fill") {
                            openMail(email)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func attoriSection(_ full: SinistroFull) -> some View {
        DetailSection(title: "Attori", icon: "person.2") {
            VStack(spacing: 10) {
                // Contraente/Assicurato
                Group {
                    Text("Contraente/Assicurato")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if let nome = full.nomeContraente ?? full.nomeAssicurato {
                        DetailRow(label: "Nome", value: nome)
                    }
                    if let indirizzo = full.indirizzoContraente ?? full.indirizzoAssicurato {
                        DetailRow(label: "Indirizzo", value: indirizzo)
                    }
                    if let tel = full.telefonoContraente ?? full.telefonoAssicurato {
                        HStack {
                            DetailRow(label: "Telefono", value: tel, actionIcon: "phone.fill") {
                                callPhone(tel)
                            }
                            
                            Button {
                                openWhatsApp(tel)
                            } label: {
                                Image(systemName: "message.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    if let email = full.emailContraente ?? full.emailAssicurato {
                        DetailRow(label: "Email", value: email, actionIcon: "envelope.fill") {
                            openMail(email)
                        }
                    }
                }
                
                // Danneggiato (se diverso)
                if let danneggiato = full.nomeDanneggiato,
                   !danneggiato.isEmpty,
                   danneggiato != full.nomeAssicurato {
                    Divider()
                    
                    Text("Danneggiato")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    DetailRow(label: "Nome", value: danneggiato)
                    
                    if let indirizzo = full.indirizzoDanneggiato {
                        DetailRow(label: "Indirizzo", value: indirizzo)
                    }
                    if let tel = full.telefonoDanneggiato {
                        HStack {
                            DetailRow(label: "Telefono", value: tel, actionIcon: "phone.fill") {
                                callPhone(tel)
                            }
                            
                            Button {
                                openWhatsApp(tel)
                            } label: {
                                Image(systemName: "message.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    if let email = full.emailDanneggiato {
                        DetailRow(label: "Email", value: email, actionIcon: "envelope.fill") {
                            openMail(email)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func polizzaSection(_ full: SinistroFull) -> some View {
        DetailSection(title: "Polizza", icon: "doc.text") {
            VStack(spacing: 10) {
                if let num = full.numeroPolizza {
                    DetailRow(label: "N. Polizza", value: num)
                }
                if let tipo = full.tipoPolizza {
                    DetailRow(label: "Tipo", value: tipo)
                }
                if let cf = full.codiceFiscaleAssicurato, !cf.isEmpty {
                    DetailRow(label: "Cod. Fiscale", value: cf)
                }
                if let piva = full.partitaIVAAssicurato, !piva.isEmpty {
                    DetailRow(label: "P. IVA", value: piva)
                }
            }
        }
    }
    
    @ViewBuilder
    private func statoSection(_ full: SinistroFull) -> some View {
        let currentStato = StatoSinistro.from(descrizione: full.stato)
        let statoColor = StatoSinistro.colorFor(descrizione: full.stato)
        let statoIcon = StatoSinistro.iconFor(descrizione: full.stato)
        let validTransitions = currentStato?.validTransitions ?? []
        
        return DetailSection(title: "Stato", icon: "flag") {
            VStack(spacing: 12) {
                // Stato attuale
                HStack(spacing: 8) {
                    Image(systemName: statoIcon)
                        .foregroundColor(.white)
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(statoColor)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(full.stato)
                            .font(.headline)
                        
                        if let sub = full.substate, !sub.isEmpty {
                            Text(sub)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                
                // Menu cambio stato con transizioni valide
                if !validTransitions.isEmpty {
                    Menu {
                        Section("Transizioni Valide") {
                            ForEach(validTransitions) { stato in
                                Button {
                                    // TODO: Implementare cambio stato
                                } label: {
                                    Label(stato.descrizione, systemImage: stato.icon)
                                }
                            }
                        }
                        
                        Divider()
                        
                        Section("Altri Stati") {
                            ForEach(StatoSinistro.allCases.filter { !validTransitions.contains($0) && $0 != currentStato }) { stato in
                                Button {
                                    // TODO: Implementare cambio stato
                                } label: {
                                    Label(stato.descrizione, systemImage: stato.icon)
                                }
                            }
                        }
                    } label: {
                        Label("Cambia stato", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    @ViewBuilder
    private func verificheSection(_ full: SinistroFull) -> some View {
        DetailSection(title: "Verifiche", icon: "checkmark.shield") {
            VStack(spacing: 10) {
                // Fulminazione
                HStack {
                    Text("Fulminazione")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(full.fulminazione ?? "Non effettuata")
                        .foregroundColor(full.fulminazione != nil && full.fulminazione != "Non effettuata" ? .orange : .secondary)
                }
                .font(.subheadline)
                
                // Tipo perizia
                HStack {
                    Text("Tipo perizia")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(full.sopralluogo ? "Tradizionale" : "Documentale")
                        .foregroundColor(full.sopralluogo ? .purple : .blue)
                }
                .font(.subheadline)
                
                // Giustificativi
                HStack {
                    Text("Giustificativi")
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: full.giustificativi ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(full.giustificativi ? .green : .gray)
                }
                .font(.subheadline)
                
                // IBAN
                HStack {
                    Text("IBAN")
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: full.iban ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(full.iban ? .green : .gray)
                }
                .font(.subheadline)
                
                // Regolarità (solo Generali)
                if full.gruppo == "Generali" {
                    HStack {
                        Text("Regolarità amm.")
                            .foregroundColor(.secondary)
                        Spacer()
                        if let reg = full.regolaritaAmministrativa {
                            Image(systemName: reg ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(reg ? .green : .red)
                        } else {
                            Text("N/D")
                                .foregroundColor(.gray)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
    }
    
    @ViewBuilder
    private func importiSection(_ full: SinistroFull) -> some View {
        DetailSection(title: "Importi", icon: "eurosign.circle") {
            VStack(spacing: 10) {
                if let richiesta = full.richiesta, richiesta > 0 {
                    DetailRow(label: "Richiesta", value: formatCurrency(richiesta))
                }
                if let danno = full.dannoAccertato, danno > 0 {
                    DetailRow(label: "Danno accertato", value: formatCurrency(danno))
                }
                if let stima = full.stimaDanno, stima > 0 {
                    DetailRow(label: "Stima danno", value: formatCurrency(stima))
                }
                if let liquidato = full.liquidato, liquidato > 0 {
                    HStack {
                        Text("Liquidato")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatCurrency(liquidato))
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    .font(.subheadline)
                }
                
                if let definizione = full.definizione, !definizione.isEmpty {
                    DetailRow(label: "Definizione", value: definizione)
                }
                
                if full.oltreDieciBeni {
                    HStack {
                        Text("Oltre 10 beni")
                            .foregroundColor(.secondary)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .font(.subheadline)
                }
            }
        }
    }
    
    @ViewBuilder
    private func dateSection(_ full: SinistroFull) -> some View {
        DetailSection(title: "Date", icon: "calendar") {
            VStack(spacing: 10) {
                // Date principali
                Group {
                    if let data = full.dataSinistro {
                        DetailRow(label: "Data sinistro", value: formatDate(data))
                    }
                    if let data = full.dataDenuncia {
                        DetailRow(label: "Denuncia", value: formatDate(data))
                    }
                    if let data = full.dataIncarico {
                        DetailRow(label: "Incarico", value: formatDate(data))
                    }
                    if full.sopralluogo, let data = full.dataSopralluogo {
                        DetailRow(label: "Sopralluogo", value: formatDate(data))
                    }
                    if let data = full.dataAssegnazione {
                        DetailRow(label: "Assegnazione", value: formatDate(data))
                    }
                    if let data = full.dataInvioAtto {
                        DetailRow(label: "Invio atto", value: formatDate(data))
                    }
                    if let data = full.dataChiusura {
                        DetailRow(label: "Chiusura", value: formatDate(data))
                    }
                }
                
                // Date secondarie (collassabili)
                DisclosureGroup("Altre date") {
                    VStack(spacing: 8) {
                        if let data = full.dataAperturaGestione {
                            DetailRow(label: "Apertura gestione", value: formatDate(data))
                        }
                        if let data = full.dataRitornoAtto {
                            DetailRow(label: "Ritorno atto", value: formatDate(data))
                        }
                        if let data = full.dataComunicazioneEsito {
                            DetailRow(label: "Comunicazione esito", value: formatDate(data))
                        }
                        if let data = full.dataRicezioneAttoSottoscritto {
                            DetailRow(label: "Ricezione atto", value: formatDate(data))
                        }
                        if let data = full.dataAccettazioneVerbale {
                            DetailRow(label: "Accettazione verbale", value: formatDate(data))
                        }
                        if let data = full.dataRevoca {
                            DetailRow(label: "Revoca", value: formatDate(data))
                        }
                        if let data = full.dataPagamentoPremio {
                            DetailRow(label: "Pagamento premio", value: formatDate(data))
                        }
                    }
                }
                .font(.subheadline)
            }
        }
    }
    
    @ViewBuilder
    private func collegamentiSection(_ collegamenti: [String]) -> some View {
        DetailSection(title: "Sinistri Collegati", icon: "link") {
            VStack(spacing: 8) {
                ForEach(collegamenti, id: \.self) { rif in
                    HStack {
                        Text(rif)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Button {
                            // TODO: Navigare al sinistro collegato
                        } label: {
                            Image(systemName: "arrow.right.circle")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func openMail(_ email: String) {
        guard let url = URL(string: "mailto:\(email)") else { return }
        UIApplication.shared.open(url)
    }
    
    private func openWhatsApp(_ number: String) {
        let cleaned = number.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "+", with: "")
        guard let url = URL(string: "https://wa.me/\(cleaned)") else { return }
        UIApplication.shared.open(url)
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
