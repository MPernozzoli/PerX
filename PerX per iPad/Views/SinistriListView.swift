//
//  SinistriListView.swift
//  PerX per iPad
//
//  Lista sinistri con NavigationSplitView ottimizzata per iPad.
//

import SwiftUI

struct SinistriListView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var selectedSinistro: SinistroMinimal?
    @State private var searchText = ""
    @State private var filterOpen = true
    @State private var sortOrder: SortOrder = .dataDesc
    @State private var selectedStato: String?
    
    enum SortOrder: String, CaseIterable {
        case dataDesc = "Più recenti"
        case dataAsc = "Meno recenti"
        case rifAsc = "Riferimento A-Z"
        case rifDesc = "Riferimento Z-A"
        case assicurato = "Assicurato"
    }
    
    private var syncService: iPadCloudKitSyncService? {
        session.cloudKitSyncService
    }
    
    private var allStati: [String] {
        let stati = Set((syncService?.sinistri ?? []).map { $0.stato })
        return Array(stati).sorted()
    }
    
    private var filteredSinistri: [SinistroMinimal] {
        var result = syncService?.sinistri ?? []
        
        // Filter by open/closed
        if filterOpen {
            result = result.filter { $0.isOpen }
        }
        
        // Filter by stato
        if let stato = selectedStato {
            result = result.filter { $0.stato == stato }
        }
        
        // Search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.riferimento.lowercased().contains(query) ||
                $0.nomeAssicurato.lowercased().contains(query) ||
                $0.nomeCompagnia.lowercased().contains(query)
            }
        }
        
        // Sort
        switch sortOrder {
        case .dataDesc:
            result.sort { ($0.dataAssegnazione ?? .distantPast) > ($1.dataAssegnazione ?? .distantPast) }
        case .dataAsc:
            result.sort { ($0.dataAssegnazione ?? .distantPast) < ($1.dataAssegnazione ?? .distantPast) }
        case .rifAsc:
            result.sort { $0.riferimento < $1.riferimento }
        case .rifDesc:
            result.sort { $0.riferimento > $1.riferimento }
        case .assicurato:
            result.sort { $0.nomeAssicurato < $1.nomeAssicurato }
        }
        
        return result
    }
    
    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            if let sinistro = selectedSinistro {
                iPadSinistroDetailView(sinistro: sinistro)
            } else {
                ContentUnavailableView(
                    "Seleziona un sinistro",
                    systemImage: "folder",
                    description: Text("Scegli un sinistro dalla lista per visualizzarne i dettagli")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar
            
            Divider()
            
            // List
            List(selection: $selectedSinistro) {
                ForEach(filteredSinistri) { sinistro in
                    SinistroRowView(sinistro: sinistro)
                        .tag(sinistro)
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $searchText, prompt: "Cerca sinistro...")
        .navigationTitle("Sinistri (\(filteredSinistri.count))")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Solo aperti", isOn: $filterOpen)
                    
                    Divider()
                    
                    Menu("Ordina per") {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Button {
                                sortOrder = order
                            } label: {
                                HStack {
                                    Text(order.rawValue)
                                    if sortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button {
                        Task {
                            await syncService?.syncNow()
                        }
                    } label: {
                        Label("Aggiorna", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .refreshable {
            await syncService?.syncNow()
        }
        .overlay {
            if syncService?.isSyncing == true {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }
    
    @ViewBuilder
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Tutti
                FilterChip(
                    title: "Tutti",
                    isSelected: selectedStato == nil,
                    action: { selectedStato = nil }
                )
                
                ForEach(allStati, id: \.self) { stato in
                    FilterChip(
                        title: stato,
                        isSelected: selectedStato == stato,
                        action: { selectedStato = stato }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sinistro Row

struct SinistroRowView: View {
    let sinistro: SinistroMinimal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(sinistro.riferimento)
                    .font(.headline)
                
                Spacer()
                
                if sinistro.fulminazione {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
                
                statusBadge
            }
            
            Text(sinistro.nomeAssicurato)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            HStack {
                Text(sinistro.nomeCompagnia)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let data = sinistro.dataAssegnazione {
                    Text(data, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if let stima = sinistro.stimaDanno, stima > 0 {
                Text("Stima: €\(stima, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        let color = statusColor
        Text(sinistro.stato)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
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
}
