import SwiftUI
import Charts
import CoreData
import AppKit

// MARK: - Yearly Report Views

struct YearlyReportView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var workSchedule = WorkScheduleManager.shared
    @StateObject private var statoManager = StatoManager.shared
    
    let year: Int
    @State private var selectedYear: Int
    @State private var isExporting = false
    @State private var showExportSuccess = false
    @State private var selectedCompany: String? = nil
    
    init(year: Int) {
        self.year = year
        self._selectedYear = State(initialValue: year)
    }
    
    private var currentUserEmail: String? {
        AppState.shared.googleAuthService.userEmail?.lowercased()
    }
    
    // MARK: - Data Calculations
    
    private var yearlyClosedClaims: [Sinistro] {
        ConsuntivoStatsService.shared.getYearlyClosedClaims(for: selectedYear, in: viewContext, userEmail: currentUserEmail)
    }
    
    private var yearlySentReports: [Sinistro] {
        ConsuntivoStatsService.shared.getYearlySentReports(for: selectedYear, in: viewContext, userEmail: currentUserEmail)
    }
    
    private var yearlyAssignedClaims: [Sinistro] {
        ConsuntivoStatsService.shared.getYearlyAssignedClaims(for: selectedYear, in: viewContext, userEmail: currentUserEmail)
    }
    
    private var yearlyRevokedClaims: [Sinistro] {
        ConsuntivoStatsService.shared.getYearlyRevokedClaims(for: selectedYear, in: viewContext, userEmail: currentUserEmail)
    }
    
    private var monthlyBreakdown: [MonthlyBreakdownData] {
        ConsuntivoStatsService.shared.getMonthlyBreakdown(
            for: selectedYear,
            closedClaims: yearlyClosedClaims,
            sentReports: yearlySentReports
        )
    }
    
    private var companyBreakdown: [CompanyBreakdownData] {
        ConsuntivoStatsService.shared.getCompanyBreakdown(for: yearlyClosedClaims)
    }
    
    private var totalWorkingHours: Double {
        var total = 0.0
        for month in 1...12 {
            if let date = Calendar.current.date(from: DateComponents(year: selectedYear, month: month, day: 15)) {
                total += workSchedule.calculateTotalMonthHours(for: date)
            }
        }
        return total
    }
    
    private var averageLiquidation: Double {
        ConsuntivoStatsService.shared.calculateAverageLiquidation(for: yearlyClosedClaims)
    }
    
    private var negativePercentage: Double {
        ConsuntivoStatsService.shared.calculateNegativePercentage(for: yearlyClosedClaims)
    }
    
    private var dailyAverage: Double {
        ConsuntivoStatsService.shared.calculateDailyAverage(claims: yearlyClosedClaims, workingHours: totalWorkingHours)
    }
    
    private var monthlyAverage: Double {
        return Double(yearlyClosedClaims.count) / 12.0
    }
    
    private var dischargePercentage: Double {
        guard yearlyAssignedClaims.count > 0 else { return 0 }
        return (Double(yearlyClosedClaims.count) / Double(yearlyAssignedClaims.count)) * 100
    }
    
    private func previousYear() {
        selectedYear -= 1
    }
    
    private func nextYear() {
        selectedYear += 1
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Header elegante
            reportHeader
            
            Divider()
            
            // Contenuto scrollabile
            ScrollView {
                VStack(spacing: 24) {
                    // KPI Cards principali
                    kpiSection
                    
                    // Grafico trend mensile
                    monthlyTrendSection
                    
                    // Breakdown per compagnia
                    companySection
                    
                    // Footer con firma
                    reportFooter
                }
                .padding(24)
            }
            .background(
                LinearGradient(
                    colors: [Color(hex: "F8F9FA"), Color(hex: "E9ECEF")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(width: 900, height: 700)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    exportToPDF()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc.fill")
                        Text("Esporta PDF")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
            }
        }
        .alert("Report Esportato", isPresented: $showExportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Il report PDF è stato salvato con successo.")
        }
        .sheet(item: Binding(
            get: { selectedCompany.map { CompanyDetailItem(company: $0) } },
            set: { selectedCompany = $0?.company }
        )) { item in
            CompanyDetailView(
                company: item.company,
                year: selectedYear,
                yearlyClosedClaims: yearlyClosedClaims.filter { 
                    ($0.nomeCompagnia ?? "N/D").lowercased().trimmingCharacters(in: .whitespaces) == item.company.lowercased().trimmingCharacters(in: .whitespaces)
                },
                yearlySentReports: yearlySentReports.filter {
                    ($0.nomeCompagnia ?? "N/D").lowercased().trimmingCharacters(in: .whitespaces) == item.company.lowercased().trimmingCharacters(in: .whitespaces)
                },
                yearlyAssignedClaims: yearlyAssignedClaims.filter {
                    ($0.nomeCompagnia ?? "N/D").lowercased().trimmingCharacters(in: .whitespaces) == item.company.lowercased().trimmingCharacters(in: .whitespaces)
                }
            )
        }
    }
    
    // MARK: - Header
    
    private var reportHeader: some View {
        HStack(spacing: 16) {
            // Logo
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [.blue, Color(hex: "764BA2")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text("P")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Report Annuale")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Riepilogo attività peritale")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Navigazione anni
            HStack(spacing: 8) {
                Button(action: previousYear) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                
                Text(String(selectedYear))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                    .frame(width: 100)
                
                Button(action: nextYear) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .disabled(selectedYear >= Calendar.current.component(.year, from: Date()))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.blue.opacity(0.1))
            )
        }
        .padding(20)
        .background(Color.white)
    }
    
    // MARK: - KPI Section
    
    private var kpiSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Panoramica Anno")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                YearlyKPICard(
                    title: "Sinistri Chiusi",
                    value: "\(yearlyClosedClaims.count)",
                    subtitle: "Media \(String(format: "%.0f", monthlyAverage))/mese",
                    icon: "checkmark.seal.fill",
                    gradient: [Color(hex: "11998E"), Color(hex: "38EF7D")]
                )
                
                YearlyKPICard(
                    title: "Atti Inviati",
                    value: "\(yearlySentReports.count)",
                    subtitle: "Perizie completate",
                    icon: "paperplane.fill",
                    gradient: [.blue, Color(hex: "764BA2")]
                )
                
                YearlyKPICard(
                    title: "Media Liquidato",
                    value: CurrencyFormatter.shared.formatWithSymbol(averageLiquidation),
                    subtitle: "Su sinistri in PL",
                    icon: "eurosign.circle.fill",
                    gradient: [Color(hex: "F093FB"), Color(hex: "F5576C")]
                )
                
                YearlyKPICard(
                    title: "Negativi",
                    value: String(format: "%.1f%%", negativePercentage),
                    subtitle: "Senza liquidazione",
                    icon: "xmark.circle.fill",
                    gradient: negativePercentage > 20 ? [Color(hex: "FF416C"), Color(hex: "FF4B2B")] : [Color(hex: "56AB2F"), Color(hex: "A8E063")]
                )
            }
            
            // Seconda riga KPI
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                YearlyKPICard(
                    title: "Media Giornaliera",
                    value: String(format: "%.1f", dailyAverage),
                    subtitle: "Chiusure/giorno",
                    icon: "chart.bar.fill",
                    gradient: [Color(hex: "4776E6"), Color(hex: "8E54E9")]
                )
                
                YearlyKPICard(
                    title: "Ore Lavorate",
                    value: String(format: "%.0f", totalWorkingHours),
                    subtitle: "Totale anno",
                    icon: "clock.fill",
                    gradient: [Color(hex: "FF8008"), Color(hex: "FFC837")]
                )
                
                YearlyKPICard(
                    title: "Produttività",
                    value: String(format: "%.2f", totalWorkingHours > 0 ? Double(yearlyClosedClaims.count) / totalWorkingHours : 0),
                    subtitle: "Chiusure/ora",
                    icon: "speedometer",
                    gradient: [Color(hex: "00B4DB"), Color(hex: "0083B0")]
                )
                
                YearlyKPICard(
                    title: "% Scarico",
                    value: String(format: "%.1f%%", dischargePercentage),
                    subtitle: "\(yearlyClosedClaims.count) chiusi / \(yearlyAssignedClaims.count) assegnati",
                    icon: "checkmark.circle.fill",
                    gradient: dischargePercentage >= 80 ? [Color(hex: "56AB2F"), Color(hex: "A8E063")] : dischargePercentage >= 60 ? [Color(hex: "FFC837"), Color(hex: "FF8008")] : [Color(hex: "FF416C"), Color(hex: "FF4B2B")]
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Monthly Trend Section
    
    private var monthlyTrendSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Andamento Mensile")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: "11998E")).frame(width: 8, height: 8)
                        Text("Chiusure").font(.caption).foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(.blue).frame(width: 8, height: 8)
                        Text("Atti").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            
            Chart {
                ForEach(monthlyBreakdown, id: \.month) { data in
                    BarMark(
                        x: .value("Mese", data.monthName),
                        y: .value("Chiusure", data.closures)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "11998E"), Color(hex: "38EF7D")],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(4)
                    .position(by: .value("Tipo", "Chiusure"))
                    
                    BarMark(
                        x: .value("Mese", data.monthName),
                        y: .value("Atti", data.reports)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, Color(hex: "764BA2")],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(4)
                    .position(by: .value("Tipo", "Atti"))
                }
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Company Section
    
    private var companySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Breakdown per Compagnia")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            
            if companyBreakdown.isEmpty {
                Text("Nessun dato disponibile")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(companyBreakdown, id: \.company) { data in
                        Button {
                            selectedCompany = data.company
                        } label: {
                            CompanyBreakdownCard(data: data)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Footer
    
    private var reportFooter: some View {
        HStack {
            Spacer()
            
            VStack(spacing: 4) {
                Text("Generato da")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 6) {
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    Text("PerX")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, Color(hex: "764BA2")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                
                Text(DateUtils.formatDate(Date()))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.top, 16)
    }
    
    // MARK: - PDF Export
    
    private func exportToPDF() {
        isExporting = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.pdf]
            savePanel.nameFieldStringValue = "Report_Annuale_\(self.selectedYear).pdf"
            savePanel.title = "Salva Report PDF"
            
            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    self.generatePDF(to: url)
                    self.showExportSuccess = true
                }
                self.isExporting = false
            }
        }
    }
    
    private func generatePDF(to url: URL) {
        let pdfData = ConsuntivoPDFService.shared.generateYearlyReportPDF(
            year: selectedYear,
            yearlyClosedClaims: yearlyClosedClaims,
            yearlySentReports: yearlySentReports,
            yearlyAssignedClaims: yearlyAssignedClaims,
            monthlyBreakdown: monthlyBreakdown,
            companyBreakdown: companyBreakdown,
            averageLiquidation: averageLiquidation,
            negativePercentage: negativePercentage,
            dailyAverage: dailyAverage,
            monthlyAverage: monthlyAverage,
            totalWorkingHours: totalWorkingHours,
            dischargePercentage: dischargePercentage
        )
        
        try? pdfData.write(to: url, options: .atomic)
    }
}

// MARK: - Yearly KPI & Company

struct YearlyKPICard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let gradient: [Color]
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
                .shadow(color: gradient[0].opacity(colorScheme == .dark ? 0.3 : 0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.5
                )
                .opacity(colorScheme == .dark ? 0.5 : 0.3)
        )
    }
}

struct CompanyBreakdownCard: View {
    let data: CompanyBreakdownData
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Icona compagnia
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, Color(hex: "764BA2")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                
                Text(String(data.company.prefix(1)))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(data.company)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Label("\(data.totalClaims)", systemImage: "doc.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label(CurrencyFormatter.shared.formatCompact(data.averageLiquidation), systemImage: "eurosign.circle")
                        .font(.caption)
                        .foregroundColor(ColorUtils.getLiquidationColor(data.averageLiquidation))
                    
                    Label(String(format: "%.0f%%", data.negativePercentage), systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundColor(data.negativePercentage > 20 ? .red : .green)
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color(hex: "F7FAFC"))
        )
    }
}

// MARK: - Company Detail

struct CompanyDetailItem: Identifiable {
    let id = UUID()
    let company: String
}

struct CompanyDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var workSchedule = WorkScheduleManager.shared
    
    let company: String
    let year: Int
    let yearlyClosedClaims: [Sinistro]
    let yearlySentReports: [Sinistro]
    let yearlyAssignedClaims: [Sinistro]
    
    private var monthlyBreakdown: [MonthlyBreakdownData] {
        ConsuntivoStatsService.shared.getMonthlyBreakdown(
            for: year,
            closedClaims: yearlyClosedClaims,
            sentReports: yearlySentReports
        )
    }
    
    private var averageLiquidation: Double {
        ConsuntivoStatsService.shared.calculateAverageLiquidation(for: yearlyClosedClaims)
    }
    
    private var negativePercentage: Double {
        ConsuntivoStatsService.shared.calculateNegativePercentage(for: yearlyClosedClaims)
    }
    
    private var totalWorkingHours: Double {
        var total = 0.0
        for month in 1...12 {
            if let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 15)) {
                total += workSchedule.calculateTotalMonthHours(for: date)
            }
        }
        return total
    }
    
    private var dailyAverage: Double {
        ConsuntivoStatsService.shared.calculateDailyAverage(claims: yearlyClosedClaims, workingHours: totalWorkingHours)
    }
    
    private var monthlyAverage: Double {
        return Double(yearlyClosedClaims.count) / 12.0
    }
    
    private var dischargePercentage: Double {
        guard yearlyAssignedClaims.count > 0 else { return 0 }
        return (Double(yearlyClosedClaims.count) / Double(yearlyAssignedClaims.count)) * 100
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text(company)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Dettaglio Anno \(year)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Spacer per bilanciare il layout
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.clear)
            }
            .padding(20)
            .background(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
            
            Divider()
            
            // Contenuto
            ScrollView {
                VStack(spacing: 24) {
                    // KPI Cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        YearlyKPICard(
                            title: "Sinistri Chiusi",
                            value: "\(yearlyClosedClaims.count)",
                            subtitle: "Media \(String(format: "%.0f", monthlyAverage))/mese",
                            icon: "checkmark.seal.fill",
                            gradient: [Color(hex: "11998E"), Color(hex: "38EF7D")]
                        )
                        
                        YearlyKPICard(
                            title: "Atti Inviati",
                            value: "\(yearlySentReports.count)",
                            subtitle: "Perizie completate",
                            icon: "paperplane.fill",
                            gradient: [.blue, Color(hex: "764BA2")]
                        )
                        
                        YearlyKPICard(
                            title: "Media Liquidato",
                            value: CurrencyFormatter.shared.formatWithSymbol(averageLiquidation),
                            subtitle: "Su sinistri in PL",
                            icon: "eurosign.circle.fill",
                            gradient: [Color(hex: "F093FB"), Color(hex: "F5576C")]
                        )
                        
                        YearlyKPICard(
                            title: "% Scarico",
                            value: String(format: "%.1f%%", dischargePercentage),
                            subtitle: "\(yearlyClosedClaims.count) chiusi / \(yearlyAssignedClaims.count) assegnati",
                            icon: "checkmark.circle.fill",
                            gradient: dischargePercentage >= 80 ? [Color(hex: "56AB2F"), Color(hex: "A8E063")] : dischargePercentage >= 60 ? [Color(hex: "FFC837"), Color(hex: "FF8008")] : [Color(hex: "FF416C"), Color(hex: "FF4B2B")]
                        )
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 10, x: 0, y: 4)
                    )
                    
                    // Grafico trend mensile
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Andamento Mensile")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            HStack(spacing: 16) {
                                HStack(spacing: 4) {
                                    Circle().fill(Color(hex: "11998E")).frame(width: 8, height: 8)
                                    Text("Chiusure").font(.caption).foregroundColor(.secondary)
                                }
                                HStack(spacing: 4) {
                                    Circle().fill(.blue).frame(width: 8, height: 8)
                                    Text("Atti").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Chart {
                            ForEach(monthlyBreakdown, id: \.month) { data in
                                BarMark(
                                    x: .value("Mese", data.monthName),
                                    y: .value("Chiusure", data.closures)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "11998E"), Color(hex: "38EF7D")],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .cornerRadius(4)
                                .position(by: .value("Tipo", "Chiusure"))
                                
                                BarMark(
                                    x: .value("Mese", data.monthName),
                                    y: .value("Atti", data.reports)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, Color(hex: "764BA2")],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .cornerRadius(4)
                                .position(by: .value("Tipo", "Atti"))
                            }
                        }
                        .frame(height: 200)
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                AxisValueLabel()
                            }
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisValueLabel()
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 10, x: 0, y: 4)
                    )
                }
                .padding(24)
            }
            .background(
                Group {
                    if colorScheme == .dark {
                        Color(NSColor.windowBackgroundColor)
                    } else {
                        LinearGradient(
                            colors: [Color(hex: "F8F9FA"), Color(hex: "E9ECEF")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            )
        }
        .frame(width: 900, height: 700)
    }
}

// MARK: - Supporting types (report annuale)

struct MonthlyStats {
    let closedClaims: Int
    let dailyAverage: Double
    let averageLiquidation: Double
    let negativePercentage: Double
    let overTenCount: Int
}

struct AnnualStats {
    let totalClaims: Int
    let monthlyAverage: Double
    let dailyAverage: Double
    let averageLiquidation: Double
    let negativePercentage: Double
}

struct YearlyStatView: View {
    let title: String
    let value: Any
    let icon: String
    let color: Color
    
    var displayValue: String {
        if let stringValue = value as? String {
            return stringValue
        }
        return "\(value)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(displayValue)
                .font(.system(.title2, design: .rounded))
                .bold()
                .foregroundColor(color)
        }
        .frame(minWidth: 150)
    }
}
