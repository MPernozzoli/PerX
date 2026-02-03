//
//  iPadPeriziaView.swift
//  PerX per iPad
//
//  Vista perizia con partite, garanzie, beni e calcoli liquidazione.
//

import SwiftUI

struct iPadPeriziaView: View {
    let sinistroRiferimento: String
    
    @EnvironmentObject var session: SessionCoordinator
    @State private var perizia: PeriziaDTO?
    @State private var isLoading = false
    @State private var selectedTab: PeriziaTab = .riepilogo
    @State private var selectedPartita: PartitaDTO?
    
    enum PeriziaTab: String, CaseIterable {
        case riepilogo = "Riepilogo"
        case partite = "Partite"
        case liquidazione = "Liquidazione"
        case descrizione = "Descrizione"
        
        var icon: String {
            switch self {
            case .riepilogo: return "doc.text"
            case .partite: return "list.bullet.rectangle"
            case .liquidazione: return "eurosign.circle"
            case .descrizione: return "text.alignleft"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar
            
            Divider()
            
            // Content
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let perizia = perizia {
                tabContent(perizia)
            } else {
                ContentUnavailableView(
                    "Nessuna perizia",
                    systemImage: "doc.text",
                    description: Text("La perizia non è ancora stata creata")
                )
            }
        }
        .task {
            await loadPerizia()
        }
    }
    
    // MARK: - Tab Bar
    
    @ViewBuilder
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(PeriziaTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation { selectedTab = tab }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                            Text(tab.rawValue)
                        }
                        .font(.subheadline)
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            VStack {
                                Spacer()
                                if selectedTab == tab {
                                    Rectangle()
                                        .fill(Color.accentColor)
                                        .frame(height: 2)
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    // MARK: - Tab Content
    
    @ViewBuilder
    private func tabContent(_ perizia: PeriziaDTO) -> some View {
        switch selectedTab {
        case .riepilogo:
            riepilogoView(perizia)
        case .partite:
            partiteView(perizia)
        case .liquidazione:
            liquidazioneView(perizia)
        case .descrizione:
            descrizioneView(perizia)
        }
    }
    
    // MARK: - Riepilogo
    
    @ViewBuilder
    private func riepilogoView(_ perizia: PeriziaDTO) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Importi principali
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ImportoCard(
                        title: "Richiesta",
                        value: perizia.richiestaIniziale,
                        icon: "arrow.up.circle",
                        color: .blue
                    )
                    
                    ImportoCard(
                        title: "Danno Accertato",
                        value: perizia.dannoAccertato,
                        icon: "checkmark.circle",
                        color: .green
                    )
                    
                    ImportoCard(
                        title: "Liquidato",
                        value: perizia.liquidato,
                        icon: "eurosign.circle",
                        color: .orange
                    )
                    
                    ImportoCard(
                        title: "Residuo",
                        value: perizia.residuo,
                        icon: "minus.circle",
                        color: .purple
                    )
                }
                
                // Riepilogo partite
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Riepilogo Partite", systemImage: "list.bullet")
                            .font(.headline)
                        
                        ForEach(perizia.partite) { partita in
                            HStack {
                                Text(partita.nome)
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                Text(formatCurrency(partita.totale))
                                    .font(.subheadline.bold())
                            }
                            
                            if partita.id != perizia.partite.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding()
                }
                
                // Stato perizia
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Stato Perizia", systemImage: "flag")
                            .font(.headline)
                        
                        HStack {
                            Text("Stato:")
                            Spacer()
                            Text(perizia.stato)
                                .foregroundColor(.accentColor)
                        }
                        
                        if let dataCompletamento = perizia.dataCompletamento {
                            HStack {
                                Text("Completata:")
                                Spacer()
                                Text(dataCompletamento, style: .date)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Partite
    
    @ViewBuilder
    private func partiteView(_ perizia: PeriziaDTO) -> some View {
        NavigationSplitView {
            List {
                ForEach(perizia.partite) { partita in
                    Button {
                        selectedPartita = partita
                    } label: {
                        PartitaRow(partita: partita)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedPartita?.id == partita.id ? Color.accentColor.opacity(0.2) : Color.clear)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Partite")
        } detail: {
            if let partita = selectedPartita {
                PartitaDetailView(partita: partita)
            } else {
                ContentUnavailableView(
                    "Seleziona una partita",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Scegli una partita per vedere i dettagli")
                )
            }
        }
    }
    
    // MARK: - Liquidazione
    
    @ViewBuilder
    private func liquidazioneView(_ perizia: PeriziaDTO) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Parametri calcolo
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Parametri Calcolo", systemImage: "function")
                            .font(.headline)
                        
                        ParametroRow(label: "Franchigia", value: "\(perizia.franchigiaPercentuale)%")
                        ParametroRow(label: "Scoperto", value: "\(perizia.scopertoPercentuale)%")
                        ParametroRow(label: "Minimo Scoperto", value: formatCurrency(perizia.minimoScoperto))
                        ParametroRow(label: "Massimale", value: formatCurrency(perizia.massimale))
                    }
                    .padding()
                }
                
                // Calcolo liquidazione
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Calcolo Liquidazione", systemImage: "calculator")
                            .font(.headline)
                        
                        CalcoloRow(label: "Danno Accertato", value: perizia.dannoAccertato, isTotal: false)
                        CalcoloRow(label: "- Franchigia", value: -perizia.franchigia, isTotal: false, isNegative: true)
                        CalcoloRow(label: "- Scoperto", value: -perizia.scoperto, isTotal: false, isNegative: true)
                        
                        Divider()
                        
                        CalcoloRow(label: "Indennizzo", value: perizia.liquidato, isTotal: true)
                    }
                    .padding()
                }
                
                // Coassicurazioni (se presenti)
                if !perizia.coassicurazioni.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Coassicurazioni", systemImage: "person.2")
                                .font(.headline)
                            
                            ForEach(perizia.coassicurazioni) { coass in
                                HStack {
                                    Text(coass.compagnia)
                                    Text("(\(coass.quotaPercentuale)%)")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatCurrency(coass.quotaImporto))
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Descrizione
    
    @ViewBuilder
    private func descrizioneView(_ perizia: PeriziaDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Descrizione Rischio", systemImage: "text.alignleft")
                            .font(.headline)
                        
                        Text(perizia.descrizioneRischio ?? "Nessuna descrizione")
                            .font(.subheadline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Dinamica Sinistro", systemImage: "text.quote")
                            .font(.headline)
                        
                        Text(perizia.dinamicaSinistro ?? "Nessuna descrizione")
                            .font(.subheadline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Note", systemImage: "note.text")
                            .font(.headline)
                        
                        Text(perizia.note ?? "Nessuna nota")
                            .font(.subheadline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Actions
    
    private func loadPerizia() async {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Implementare caricamento perizia da CloudKit
        // Per ora usa dati di esempio
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        return formatter.string(from: NSNumber(value: value)) ?? "€\(value)"
    }
}

// MARK: - DTOs

struct PeriziaDTO: Identifiable {
    let id: String
    let sinistroRiferimento: String
    let stato: String
    let dataCompletamento: Date?
    
    // Importi
    let richiestaIniziale: Double
    let dannoAccertato: Double
    let liquidato: Double
    let residuo: Double
    
    // Parametri
    let franchigiaPercentuale: Double
    let franchigia: Double
    let scopertoPercentuale: Double
    let scoperto: Double
    let minimoScoperto: Double
    let massimale: Double
    
    // Descrizioni
    let descrizioneRischio: String?
    let dinamicaSinistro: String?
    let note: String?
    
    // Relazioni
    let partite: [PartitaDTO]
    let coassicurazioni: [CoassicurazioneDTO]
}

struct PartitaDTO: Identifiable, Hashable {
    let id: String
    let nome: String
    let totale: Double
    let garanzie: [GaranziaDTO]
    let beni: [BeneDTO]
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: PartitaDTO, rhs: PartitaDTO) -> Bool {
        lhs.id == rhs.id
    }
}

struct GaranziaDTO: Identifiable {
    let id: String
    let nome: String
    let massimale: Double
    let franchigia: Double
}

struct BeneDTO: Identifiable {
    let id: String
    let descrizione: String
    let valoreNuovo: Double
    let vetusta: Double
    let valoreAttuale: Double
    let danno: Double
}

struct CoassicurazioneDTO: Identifiable {
    let id: String
    let compagnia: String
    let quotaPercentuale: Double
    let quotaImporto: Double
}

// MARK: - Subviews

struct ImportoCard: View {
    let title: String
    let value: Double
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(formatCurrency(value))
                .font(.title2.bold())
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "€\(value)"
    }
}

struct PartitaRow: View {
    let partita: PartitaDTO
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(partita.nome)
                .font(.subheadline.bold())
            
            HStack {
                Text("\(partita.beni.count) beni • \(partita.garanzie.count) garanzie")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formatCurrency(partita.totale))
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        return formatter.string(from: NSNumber(value: value)) ?? "€\(value)"
    }
}

struct PartitaDetailView: View {
    let partita: PartitaDTO
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Garanzie
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Garanzie", systemImage: "shield")
                            .font(.headline)
                        
                        ForEach(partita.garanzie) { garanzia in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(garanzia.nome)
                                    .font(.subheadline.bold())
                                
                                HStack {
                                    Text("Massimale: \(formatCurrency(garanzia.massimale))")
                                    Spacer()
                                    Text("Franchigia: \(formatCurrency(garanzia.franchigia))")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            
                            if garanzia.id != partita.garanzie.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding()
                }
                
                // Beni
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Beni", systemImage: "cube.box")
                            .font(.headline)
                        
                        ForEach(partita.beni) { bene in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bene.descrizione)
                                    .font(.subheadline.bold())
                                
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("V. Nuovo: \(formatCurrency(bene.valoreNuovo))")
                                        Text("Vetustà: \(Int(bene.vetusta))%")
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing) {
                                        Text("V. Attuale: \(formatCurrency(bene.valoreAttuale))")
                                        Text("Danno: \(formatCurrency(bene.danno))")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            
                            if bene.id != partita.beni.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(partita.nome)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        return formatter.string(from: NSNumber(value: value)) ?? "€\(value)"
    }
}

struct ParametroRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}

struct CalcoloRow: View {
    let label: String
    let value: Double
    let isTotal: Bool
    var isNegative: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(isTotal ? .headline : .subheadline)
                .foregroundColor(isNegative ? .red : .primary)
            
            Spacer()
            
            Text(formatCurrency(value))
                .font(isTotal ? .headline.bold() : .subheadline)
                .foregroundColor(isTotal ? .accentColor : (isNegative ? .red : .primary))
        }
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        return formatter.string(from: NSNumber(value: value)) ?? "€\(value)"
    }
}
