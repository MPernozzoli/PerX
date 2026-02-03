//
//  iPadConsuntivoView.swift
//  PerX per iPad
//
//  Vista consuntivo mensile con statistiche e report.
//

import SwiftUI

struct iPadConsuntivoView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var selectedMonth = Date()
    @State private var stats: ConsuntivoStats = .empty
    @State private var isLoading = false
    
    private var monthFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "it_IT")
        return f
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Month picker
                monthPickerSection
                
                // Stats cards
                statsSection
                
                // Charts placeholder
                chartsSection
                
                // Lista sinistri del mese
                sinistriSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Consuntivo")
        .task {
            await loadStats()
        }
        .onChange(of: selectedMonth) { _ in
            Task { await loadStats() }
        }
    }
    
    // MARK: - Month Picker
    
    @ViewBuilder
    private var monthPickerSection: some View {
        HStack {
            Button {
                selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
            }
            
            Spacer()
            
            Text(monthFormatter.string(from: selectedMonth).capitalized)
                .font(.title2.bold())
            
            Spacer()
            
            Button {
                selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title2)
            }
            .disabled(Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month))
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Stats
    
    @ViewBuilder
    private var statsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            ConsuntivoStatCard(
                title: "Sinistri Assegnati",
                value: "\(stats.sinistriAssegnati)",
                subtitle: "nel mese",
                icon: "folder.badge.plus",
                color: .blue
            )
            
            ConsuntivoStatCard(
                title: "Sinistri Chiusi",
                value: "\(stats.sinistriChiusi)",
                subtitle: "nel mese",
                icon: "checkmark.circle.fill",
                color: .green
            )
            
            ConsuntivoStatCard(
                title: "Liquidato",
                value: formatCurrency(stats.totLiquidato),
                subtitle: "totale",
                icon: "eurosign.circle.fill",
                color: .orange
            )
        }
        
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            ConsuntivoStatCard(
                title: "Compensi",
                value: formatCurrency(stats.totCompensi),
                subtitle: "maturati",
                icon: "banknote.fill",
                color: .purple
            )
            
            ConsuntivoStatCard(
                title: "Danno Accertato",
                value: formatCurrency(stats.totDanno),
                subtitle: "totale",
                icon: "chart.line.uptrend.xyaxis",
                color: .teal
            )
        }
    }
    
    // MARK: - Charts
    
    @ViewBuilder
    private var chartsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("Andamento Sinistri")
                    .font(.headline)
                
                // Placeholder per grafico
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 200)
                    .overlay {
                        VStack {
                            Image(systemName: "chart.bar.fill")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("Grafico in arrivo")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
            }
            .padding()
        }
    }
    
    // MARK: - Sinistri
    
    @ViewBuilder
    private var sinistriSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Sinistri del mese")
                        .font(.headline)
                    
                    Spacer()
                    
                    Text("\(stats.sinistriDelMese.count) sinistri")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if stats.sinistriDelMese.isEmpty {
                    ContentUnavailableView(
                        "Nessun sinistro",
                        systemImage: "folder",
                        description: Text("Nessun sinistro trovato per questo mese")
                    )
                    .frame(height: 150)
                } else {
                    ForEach(stats.sinistriDelMese.prefix(10)) { sinistro in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sinistro.riferimento)
                                    .font(.subheadline.bold())
                                
                                Text(sinistro.nomeAssicurato)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(sinistro.stato)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(8)
                        }
                        .padding(.vertical, 4)
                        
                        if sinistro.id != stats.sinistriDelMese.prefix(10).last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Actions
    
    private func loadStats() async {
        isLoading = true
        defer { isLoading = false }
        
        let sinistri = session.cloudKitSyncService?.sinistri ?? []
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        
        let sinistriDelMese = sinistri.filter { sinistro in
            guard let dataAssegnazione = sinistro.dataAssegnazione else { return false }
            return dataAssegnazione >= monthStart && dataAssegnazione < monthEnd
        }
        
        let chiusiNelMese = sinistri.filter { sinistro in
            guard let dataChiusura = sinistro.dataChiusura else { return false }
            return dataChiusura >= monthStart && dataChiusura < monthEnd
        }
        
        stats = ConsuntivoStats(
            sinistriAssegnati: sinistriDelMese.count,
            sinistriChiusi: chiusiNelMese.count,
            totLiquidato: chiusiNelMese.compactMap { $0.stimaDanno }.reduce(0, +),
            totCompensi: 0, // TODO: implementare
            totDanno: sinistriDelMese.compactMap { $0.stimaDanno }.reduce(0, +),
            sinistriDelMese: sinistriDelMese
        )
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "€0"
    }
}

// MARK: - Models

struct ConsuntivoStats {
    let sinistriAssegnati: Int
    let sinistriChiusi: Int
    let totLiquidato: Double
    let totCompensi: Double
    let totDanno: Double
    let sinistriDelMese: [SinistroMinimal]
    
    static let empty = ConsuntivoStats(
        sinistriAssegnati: 0,
        sinistriChiusi: 0,
        totLiquidato: 0,
        totCompensi: 0,
        totDanno: 0,
        sinistriDelMese: []
    )
}

// MARK: - Subviews

struct ConsuntivoStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}
