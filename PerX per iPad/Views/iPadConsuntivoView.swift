//
//  iPadConsuntivoView.swift
//  PerX per iPad
//
//  Vista consuntivo mensile con statistiche e report.
//

import SwiftUI
import Charts

struct iPadConsuntivoView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var selectedMonth = Date()
    @State private var stats: ConsuntivoStats = .empty
    @State private var dailyStats: [StatisticheGiorno] = []
    @State private var companyStats: [StatisticheCompagnia] = []
    @State private var isLoading = false
    @State private var dataSource: String = "locale"
    
    private var monthFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "it_IT")
        return f
    }
    
    private var anno: Int { Calendar.current.component(.year, from: selectedMonth) }
    private var mese: Int { Calendar.current.component(.month, from: selectedMonth) }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Month picker
                monthPickerSection
                
                // Stats cards
                statsSection
                
                // Charts
                if !dailyStats.isEmpty {
                    chartsSection
                }
                
                // Per compagnia
                if !companyStats.isEmpty {
                    companySection
                }
                
                // Lista sinistri del mese
                sinistriSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Consuntivo")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                    }
                    
                    Text(dataSource)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
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
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            ConsuntivoStatCard(
                title: "Assegnati",
                value: "\(stats.sinistriAssegnati)",
                subtitle: "nel mese",
                icon: "folder.badge.plus",
                color: .blue
            )
            
            ConsuntivoStatCard(
                title: "Chiusi",
                value: "\(stats.sinistriChiusi)",
                subtitle: "nel mese",
                icon: "checkmark.circle.fill",
                color: .green
            )
            
            ConsuntivoStatCard(
                title: "Atti Inviati",
                value: "\(stats.attiInviati)",
                subtitle: "nel mese",
                icon: "paperplane.fill",
                color: .purple
            )
            
            ConsuntivoStatCard(
                title: "Media/gg",
                value: String(format: "%.1f", stats.mediaGiornaliera),
                subtitle: "chiusure",
                icon: "chart.bar.fill",
                color: .teal
            )
        }
        
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            ConsuntivoStatCard(
                title: "Liquidato",
                value: formatCurrency(stats.totLiquidato),
                subtitle: "totale",
                icon: "eurosign.circle.fill",
                color: .orange
            )
            
            ConsuntivoStatCard(
                title: "Danno Accertato",
                value: formatCurrency(stats.totDanno),
                subtitle: "totale",
                icon: "chart.line.uptrend.xyaxis",
                color: .indigo
            )
            
            ConsuntivoStatCard(
                title: "Compensi",
                value: formatCurrency(stats.totCompensi),
                subtitle: "maturati",
                icon: "banknote.fill",
                color: .mint
            )
        }
    }
    
    // MARK: - Charts
    
    @ViewBuilder
    private var chartsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("Andamento Giornaliero")
                    .font(.headline)
                
                Chart {
                    ForEach(dailyStats) { stat in
                        BarMark(
                            x: .value("Giorno", stat.giorno),
                            y: .value("Chiusure", stat.chiusure)
                        )
                        .foregroundStyle(.green.gradient)
                    }
                    
                    ForEach(dailyStats) { stat in
                        LineMark(
                            x: .value("Giorno", stat.giorno),
                            y: .value("Assegnazioni", stat.assegnazioni)
                        )
                        .foregroundStyle(.blue)
                        .symbol(.circle)
                    }
                }
                .frame(height: 200)
                .chartXAxisLabel("Giorno del mese")
                .chartYAxisLabel("Pratiche")
                .chartLegend(position: .bottom)
                
                HStack(spacing: 20) {
                    LegendItem(color: .green, label: "Chiusure")
                    LegendItem(color: .blue, label: "Assegnazioni")
                }
            }
            .padding()
        }
    }
    
    // MARK: - Company Stats
    
    @ViewBuilder
    private var companySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("Per Compagnia")
                    .font(.headline)
                
                ForEach(companyStats.sorted { $0.chiusure > $1.chiusure }.prefix(10)) { company in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(company.nomeCompagnia)
                                .font(.subheadline.bold())
                            
                            if let gruppo = company.gruppoCompagnia {
                                Text(gruppo)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 16) {
                            StatBadge(value: company.assegnazioni, label: "Ass.", color: .blue)
                            StatBadge(value: company.chiusure, label: "Chi.", color: .green)
                            
                            Text(formatCurrency(company.liquidatoTotale))
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if company.id != companyStats.sorted(by: { $0.chiusure > $1.chiusure }).prefix(10).last?.id {
                        Divider()
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
        
        // Dati da CloudKit (tramite sync service)
        await loadStatsFromCloudKit()
    }
    
    private func loadStatsFromCloudKit() async {
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
        
        // Calcola statistiche giornaliere
        var dailyMap: [Int: (ass: Int, chi: Int, atti: Int)] = [:]
        for sinistro in sinistriDelMese {
            if let data = sinistro.dataAssegnazione {
                let giorno = calendar.component(.day, from: data)
                var entry = dailyMap[giorno] ?? (0, 0, 0)
                entry.ass += 1
                dailyMap[giorno] = entry
            }
        }
        for sinistro in chiusiNelMese {
            if let data = sinistro.dataChiusura {
                let giorno = calendar.component(.day, from: data)
                var entry = dailyMap[giorno] ?? (0, 0, 0)
                entry.chi += 1
                dailyMap[giorno] = entry
            }
        }
        
        dailyStats = dailyMap.map { giorno, counts in
            StatisticheGiorno(
                anno: anno,
                mese: mese,
                giorno: giorno,
                assegnazioni: counts.ass,
                chiusure: counts.chi,
                attiInviati: counts.atti
            )
        }.sorted { $0.giorno < $1.giorno }
        
        // Statistiche per compagnia
        var companyMap: [String: (nome: String, ass: Int, chi: Int, liq: Double)] = [:]
        for sinistro in sinistriDelMese {
            var entry = companyMap[sinistro.nomeCompagnia] ?? (sinistro.nomeCompagnia, 0, 0, 0)
            entry.ass += 1
            companyMap[sinistro.nomeCompagnia] = entry
        }
        for sinistro in chiusiNelMese {
            var entry = companyMap[sinistro.nomeCompagnia] ?? (sinistro.nomeCompagnia, 0, 0, 0)
            entry.chi += 1
            entry.liq += sinistro.stimaDanno ?? 0
            companyMap[sinistro.nomeCompagnia] = entry
        }
        
        companyStats = companyMap.map { code, data in
            StatisticheCompagnia(
                codiceCompagnia: code,
                nomeCompagnia: data.nome,
                gruppoCompagnia: nil,
                assegnazioni: data.ass,
                chiusure: data.chi,
                attiInviati: 0,
                liquidatoTotale: data.liq
            )
        }
        
        let totLiq = chiusiNelMese.compactMap { $0.stimaDanno }.reduce(0, +)
        
        stats = ConsuntivoStats(
            sinistriAssegnati: sinistriDelMese.count,
            sinistriChiusi: chiusiNelMese.count,
            totLiquidato: totLiq,
            totCompensi: 0,
            totDanno: sinistriDelMese.compactMap { $0.stimaDanno }.reduce(0, +),
            attiInviati: 0,
            mediaGiornaliera: chiusiNelMese.isEmpty ? 0 : Double(chiusiNelMese.count) / 22.0,
            sinistriDelMese: sinistriDelMese
        )
        
        dataSource = "CloudKit"
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

struct StatisticheGiorno: Codable, Identifiable {
    var id: String { "\(anno)-\(mese)-\(giorno)" }
    let anno: Int
    let mese: Int
    let giorno: Int
    let assegnazioni: Int
    let chiusure: Int
    let attiInviati: Int
}

struct StatisticheCompagnia: Codable, Identifiable {
    var id: String { codiceCompagnia }
    let codiceCompagnia: String
    let nomeCompagnia: String
    let gruppoCompagnia: String?
    let assegnazioni: Int
    let chiusure: Int
    let attiInviati: Int
    let liquidatoTotale: Double
}

struct ConsuntivoStats {
    let sinistriAssegnati: Int
    let sinistriChiusi: Int
    let totLiquidato: Double
    let totCompensi: Double
    let totDanno: Double
    let attiInviati: Int
    let mediaGiornaliera: Double
    let sinistriDelMese: [SinistroMinimal]
    
    static let empty = ConsuntivoStats(
        sinistriAssegnati: 0,
        sinistriChiusi: 0,
        totLiquidato: 0,
        totCompensi: 0,
        totDanno: 0,
        attiInviati: 0,
        mediaGiornaliera: 0,
        sinistriDelMese: []
    )
}

struct StatBadge: View {
    let value: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.caption.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct ConsuntivoLegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
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
