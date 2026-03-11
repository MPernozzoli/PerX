import SwiftUI
import Charts
import CoreData

// All'inizio del file, prima di tutte le viste
private func getDailyAverageColor(_ average: Double) -> Color {
    if average >= 10.0 {
        return .green
    } else if average >= 5.0 {
        return .yellow
    } else {
        return .red
    }
}

struct MonthlyReportView: View {
    let month: Date
    
    var body: some View {
        Text("Report mensile per \(month, style: .date)")
            .padding()
    }
}

struct ConsuntivoView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("compensationRanges") private var compensationRanges: Data = CompensationRange.defaultRanges
    @AppStorage("damageThresholds") private var damageThresholdsData: Data = DamageThreshold.defaultData
    @AppStorage("fatturatoDisplayMode") private var fatturatoDisplayModeRaw: String = FatturatoDisplayMode.lordoStimato.rawValue
    @State private var selectedMonth: Date = Date()
    @State private var showYearlyReport = false
    @State private var ranges: [CompensationRange] = []
    @State private var damageThresholds: [DamageThreshold] = []
    @ObservedObject private var workSchedule = WorkScheduleManager.shared
    @StateObject private var statoManager = StatoManager.shared
    @StateObject private var taskManager = TaskManager.shared
    @State private var taskRefresh: Int = 0
    @State private var timer: Timer?
    @State private var showingFatturatoDetail = false
    @StateObject private var fatturaMensileService = FatturaMensileService.shared
    @AppStorage("soloCompetenzaStatistiche") private var soloCompetenza = true
    let onOpenSinistro: (Sinistro) -> Void
    
    private var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
    }
    
    private var currentUserEmail: String? {
        AppState.shared.googleAuthService.userEmail?.lowercased()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header moderno
            modernHeader
            
            Divider()
            
            // Contenuto principale
            ScrollView {
                VStack(spacing: 20) {
                    let _ = taskRefresh
                    
                    // KPI Cards Grid
                    modernKPIGrid
                    
                    // SEZIONE 1: Andamento Mese / Statistiche
                    ModernCard {
                        VStack(spacing: 20) {
                            if isCurrentMonth {
                                CurrentMonthSummaryView(
                                    closedClaims: monthlyClosedClaims,
                                    sentReports: monthlySentReports.count,
                                    returnedReports: monthlyReturnedReports.count,
                                    isCurrentMonth: isCurrentMonth,
                                    monthCompletionPercentage: monthCompletionPercentage,
                                    todayClosures: todayClosuresCount,
                                    todaySentReports: todaySentReportsCount,
                                    todayTotalUnique: todayTotalUnique,
                                    todayProjection: todayProjectedClosures,
                                    plannedToday: todayPlannedTasks,
                                    todayMinorTasks: todayMinorTasksCount,
                                    weeklyClosures: currentWeekClosures,
                                    weeklyProjection: weeklyProjectedClosures,
                                    monthlyProjection: monthlyProjectedClosuresByHours,
                                    weekDelta: weekProgressDelta,
                                    momDelta: momProgressDelta,
                                    yoyDelta: yoyProgressDeltaValue,
                                    todayHours: todayWorkingHours,
                                    remainingWeekHours: remainingWeekHours,
                                    remainingMonthHours: remainingMonthHours,
                                    recentDaysStats: recentDaysStats
                                )
                                .environmentObject(workSchedule)
                            } else {
                                MonthlyStatsView(
                                    closedClaims: monthlyClosedClaims,
                                    sentReports: monthlySentReports,
                                    returnedReports: monthlyReturnedReports,
                                    workingHours: workSchedule.calculateTotalMonthHours(for: selectedMonth),
                                    selectedMonth: selectedMonth
                                )
                                .environmentObject(workSchedule)
                            }
                        }
                    }
                    
                    // SEZIONE 2: Proiezioni
                    if isCurrentMonth {
                        ModernCard {
                            VStack(spacing: 20) {
                                // Tre box colorati (oggi, settimana, mese)
                                if let screen = NSScreen.main, screen.frame.width > 800 {
                                    HStack(spacing: 16) {
                                        ProjectionCard(
                                            title: "Oggi",
                                            current: todayClosuresCount,
                                            projected: todayProjectedClosures,
                                            subtitle: "Chiusure pianificate: \(todayPlannedTasks) • Task minori: \(todayMinorTasksCount)",
                                            footer: "Ore disponibili: \(String(format: "%.1f", todayWorkingHours))h",
                                            accent: .blue,
                                            deltas: nil
                                        )
                                        
                                        ProjectionCard(
                                            title: "Settimana",
                                            current: currentWeekClosures,
                                            projected: weeklyProjectedClosures,
                                            subtitle: "Ore residue: \(String(format: "%.1f", remainingWeekHours))h",
                                            footer: "Media attuale: \(String(format: "%.2f", productivityPerHour))",
                                            accent: .orange,
                                            deltas: [
                                                ("WoW", weekProgressDelta)
                                            ]
                                        )
                                        
                                        ProjectionCard(
                                            title: "Mese",
                                            current: monthlyClosedClaims.count,
                                            projected: monthlyProjectedClosuresByHours,
                                            subtitle: "Ore residue: \(String(format: "%.1f", remainingMonthHours))h",
                                            footer: "Produttività: \(String(format: "%.2f", productivityPerHour))",
                                            accent: .purple,
                                            deltas: [
                                                ("MoM", momProgressDelta),
                                                ("YoY", yoyProgressDeltaValue)
                                            ]
                                        )
                                    }
                                } else {
                                    VStack(spacing: 16) {
                                        ProjectionCard(
                                            title: "Oggi",
                                            current: todayClosuresCount,
                                            projected: todayProjectedClosures,
                                            subtitle: "Chiusure pianificate: \(todayPlannedTasks) • Task minori: \(todayMinorTasksCount)",
                                            footer: "Ore disponibili: \(String(format: "%.1f", todayWorkingHours))h",
                                            accent: .blue,
                                            deltas: nil
                                        )
                                        
                                        ProjectionCard(
                                            title: "Settimana",
                                            current: currentWeekClosures,
                                            projected: weeklyProjectedClosures,
                                            subtitle: "Ore residue: \(String(format: "%.1f", remainingWeekHours))h",
                                            footer: "Media attuale: \(String(format: "%.2f", productivityPerHour))",
                                            accent: .orange,
                                            deltas: [
                                                ("WoW", weekProgressDelta)
                                            ]
                                        )
                                        
                                        ProjectionCard(
                                            title: "Mese",
                                            current: monthlyClosedClaims.count,
                                            projected: monthlyProjectedClosuresByHours,
                                            subtitle: "Ore residue: \(String(format: "%.1f", remainingMonthHours))h",
                                            footer: "Produttività: \(String(format: "%.2f", productivityPerHour))",
                                            accent: .purple,
                                            deltas: [
                                                ("MoM", momProgressDelta),
                                                ("YoY", yoyProgressDeltaValue)
                                            ]
                                        )
                                    }
                                }
                                
                                Divider()
                                
                                // Proiezioni dettagliate
                                if let screen = NSScreen.main, screen.frame.width > 800 {
                                    HStack(spacing: 16) {
                                        ClosuresProjectionView(
                                            currentClosures: monthlyClosedClaims.count,
                                            dailyAverage: dailyAverage,
                                            projectedClosures: projectedClosures,
                                            workingHours: workSchedule.monthlyHours,
                                            isCurrentMonth: isCurrentMonth,
                                            monthCompletionPercentage: monthCompletionPercentage,
                                            previousMonthComparison: previousMonthComparison,
                                            historicalDailyAverage: historicalDailyAverage,
                                            monthlyTarget: workSchedule.getMonthlyTarget(for: selectedMonth),
                                            selectedMonth: selectedMonth
                                        )
                                        .frame(maxWidth: .infinity)
                                        
                                        TotalProjectionView(
                                            currentClosures: monthlyClosedClaims.count,
                                            sentReports: monthlyCurrentAttoInviato.count,
                                            dailyAverage: totalDailyAverage,
                                            projectedTotal: projectedTotal,
                                            workingHours: workSchedule.monthlyHours,
                                            historicalDailyAverage: historicalDailyAverage,
                                            monthlyTarget: workSchedule.getMonthlyTarget(for: selectedMonth),
                                            selectedMonth: selectedMonth
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                } else {
                                    VStack(spacing: 16) {
                                        ClosuresProjectionView(
                                            currentClosures: monthlyClosedClaims.count,
                                            dailyAverage: dailyAverage,
                                            projectedClosures: projectedClosures,
                                            workingHours: workSchedule.monthlyHours,
                                            isCurrentMonth: isCurrentMonth,
                                            monthCompletionPercentage: monthCompletionPercentage,
                                            previousMonthComparison: previousMonthComparison,
                                            historicalDailyAverage: historicalDailyAverage,
                                            monthlyTarget: workSchedule.getMonthlyTarget(for: selectedMonth),
                                            selectedMonth: selectedMonth
                                        )
                                        .frame(maxWidth: .infinity)
                                        
                                        TotalProjectionView(
                                            currentClosures: monthlyClosedClaims.count,
                                            sentReports: monthlyCurrentAttoInviato.count,
                                            dailyAverage: totalDailyAverage,
                                            projectedTotal: projectedTotal,
                                            workingHours: workSchedule.monthlyHours,
                                            historicalDailyAverage: historicalDailyAverage,
                                            monthlyTarget: workSchedule.getMonthlyTarget(for: selectedMonth),
                                            selectedMonth: selectedMonth
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }
                    
                    // SEZIONE 3: Liquidazioni
                    ModernCard {
                        LiquidationDetailsView(
                            stats: stats,
                            previousMonthStats: previousMonthStats,
                            statsByCompany: statsByCompany,
                            companyDetailsForGroups: companyDetailsForGroups,
                            hasMultipleCompaniesInGroup: hasMultipleCompaniesInGroup,
                            isGroupUnited: isGroupUnited,
                            toggleGroupUnion: toggleGroupUnion,
                            getGroupKey: getGroupKey,
                            onOpenSinistro: onOpenSinistro,
                            soloCompetenza: $soloCompetenza
                        )
                    }
                    
                    // SEZIONE 4: Grafici (in fondo)
                    if let screen = NSScreen.main, screen.frame.width > 1000 {
                        HStack(spacing: 20) {
                            ModernCard {
                                DailyChartView(
                                    closedClaims: monthlyClosedClaims,
                                    sentReports: monthlySentReports,
                                    assignedClaims: monthlyAssignedClaims,
                                    selectedMonth: selectedMonth
                                )
                                .frame(height: 380)
                            }
                            .frame(maxWidth: .infinity)
                            
                            ModernCard {
                                ComparisonChartView(
                                    closedClaims: monthlyClosedClaims,
                                    sentReports: monthlySentReports,
                                    assignedClaims: monthlyAssignedClaims,
                                    previousMonthClaims: previousMonthClosedClaims,
                                    previousMonthReports: previousMonthSentReports,
                                    previousMonthAssignments: previousMonthAssignedClaims
                                )
                                .frame(height: 380)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 20) {
                            ModernCard {
                                DailyChartView(
                                    closedClaims: monthlyClosedClaims,
                                    sentReports: monthlySentReports,
                                    assignedClaims: monthlyAssignedClaims,
                                    selectedMonth: selectedMonth
                                )
                                .frame(height: 380)
                            }
                            
                            ModernCard {
                                ComparisonChartView(
                                    closedClaims: monthlyClosedClaims,
                                    sentReports: monthlySentReports,
                                    assignedClaims: monthlyAssignedClaims,
                                    previousMonthClaims: previousMonthClosedClaims,
                                    previousMonthReports: previousMonthSentReports,
                                    previousMonthAssignments: previousMonthAssignedClaims
                                )
                                .frame(height: 380)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Group {
                    if colorScheme == .dark {
                        Color(NSColor.windowBackgroundColor)
                    } else {
                        LinearGradient(
                            colors: [Color(hex: "F8F9FA"), Color(hex: "FFFFFF")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            )
        }
        .frame(minWidth: 800, minHeight: 600)
        .sheet(isPresented: $showYearlyReport) {
            YearlyReportView(year: Calendar.current.component(.year, from: selectedMonth))
        }
        .sheet(isPresented: $showingFatturatoDetail) {
            FatturatoDetailView(
                initialMonth: selectedMonth,
                onOpenSinistro: onOpenSinistro
            )
        }
        .onAppear {
            loadRangesAndThresholds()
            workSchedule.calculateTotalMonthHours(for: selectedMonth)
            
            timer = Timer.scheduledTimer(withTimeInterval: 3900, repeats: true) { _ in
                print("⏰ Aggiornamento automatico del progresso mensile")
                workSchedule.objectWillChange.send()
                workSchedule.calculateTotalMonthHours(for: selectedMonth)
            }
        }
        .onDisappear {
            // Ferma il timer quando la vista scompare
            timer?.invalidate()
            timer = nil
        }
        .onReceive(taskManager.$updateCounter.dropFirst()) { _ in
            // dropFirst evita trigger iniziale che causa loop
            taskRefresh += 1
        }
        .onChange(of: selectedMonth) { newMonth in
            loadRangesAndThresholds()
            workSchedule.calculateTotalMonthHours(for: newMonth)
        }
        .onChange(of: workSchedule.updateCounter) { _ in
            workSchedule.calculateTotalMonthHours(for: selectedMonth)
        }
    }
    
    private func previousMonth() {
        if let newDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
    
    private func nextMonth() {
        if let newDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
    
    // MARK: - Computed Properties
    
    private var monthCompletionPercentage: Double {
        guard isCurrentMonth else { return 100 }
        let totalHours = workSchedule.calculateTotalMonthHours(for: selectedMonth)
        guard totalHours > 0 else { return 0 }
        let workedHours = workSchedule.calculateWorkedHoursUpToNow(in: selectedMonth)
        return (workedHours / totalHours) * 100
    }
    
    private var monthlyClosedClaims: [Sinistro] {
        ConsuntivoStatsService.shared.getMonthlyClosedClaims(for: selectedMonth, in: viewContext, userEmail: currentUserEmail)
    }
    
    private var monthlySentReports: [Sinistro] {
        ConsuntivoStatsService.shared.getMonthlySentReports(for: selectedMonth, in: viewContext, userEmail: currentUserEmail)
    }
    
    private var monthlyReturnedReports: [Sinistro] {
        ConsuntivoStatsService.shared.getMonthlyReturnedReports(for: selectedMonth, in: viewContext, userEmail: currentUserEmail)
    }
    
    private var monthlyAssignedClaims: [Sinistro] {
        ConsuntivoStatsService.shared.getMonthlyAssignedClaims(for: selectedMonth, in: viewContext, userEmail: currentUserEmail)
    }
    
    private var monthlyRevokedClaims: [Sinistro] {
        ConsuntivoStatsService.shared.getMonthlyRevokedClaims(for: selectedMonth, in: viewContext, userEmail: currentUserEmail)
    }
    
    private var monthlyCurrentAttoInviato: [Sinistro] {
        var predicateFormat = "stato == %@"
        var predicateArgs: [Any] = [StatoManager.StatoSinistro.attoInviato.descrizione]
        
        if let userEmail = currentUserEmail, !userEmail.isEmpty {
            predicateFormat += " AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        return (try? viewContext.fetch(request)) ?? []
    }
    
    private var dailyAverage: Double {
        let workingDays = workSchedule.countWorkingDays()
        guard workingDays > 0 else { return 0 }
        return Double(monthlyClosedClaims.count) / Double(workingDays)
    }
    
    private var totalDailyAverage: Double {
        let workingDays = workSchedule.countWorkingDays()
        guard workingDays > 0 else { return 0 }
        return Double(monthlyClosedClaims.count + monthlyCurrentAttoInviato.count) / Double(workingDays)
    }
    
    private var projectedClosures: Int {
        monthlyProjectedClosuresByHours
    }
    
    private var projectedTotal: Int {
        let additional = Int(round(productivityPerHour * remainingMonthHours))
        return monthlyClosedClaims.count + monthlyCurrentAttoInviato.count + additional
    }
    
    private var previousMonthClosedClaims: [Sinistro] {
        let calendar = Calendar.current
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) else {
            return []
        }
        
        let startOfMonth = calendar.startOfMonth(for: previousMonth)
        let endOfMonth = calendar.endOfMonth(for: previousMonth)
        
        var predicateFormat = "dataChiusura >= %@ AND dataChiusura <= %@ AND stato == %@"
        var predicateArgs: [Any] = [startOfMonth as NSDate, endOfMonth as NSDate, StatoManager.StatoSinistro.chiusa.descrizione]
        
        if let userEmail = currentUserEmail, !userEmail.isEmpty {
            predicateFormat += " AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        return (try? viewContext.fetch(request)) ?? []
    }
    
    private var previousMonthSentReports: [Sinistro] {
        let calendar = Calendar.current
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) else {
            return []
        }
        
        let startOfMonth = calendar.startOfMonth(for: previousMonth)
        let endOfMonth = calendar.endOfMonth(for: previousMonth)
        
        var predicateFormat = "dataInvioAtto >= %@ AND dataInvioAtto <= %@"
        var predicateArgs: [Any] = [startOfMonth as NSDate, endOfMonth as NSDate]
        
        if let userEmail = currentUserEmail, !userEmail.isEmpty {
            predicateFormat += " AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        return (try? viewContext.fetch(request)) ?? []
    }
    
    private var previousMonthAssignedClaims: [Sinistro] {
        let calendar = Calendar.current
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) else {
            return []
        }
        return ConsuntivoStatsService.shared.getMonthlyAssignedClaims(for: previousMonth, in: viewContext, userEmail: currentUserEmail)
    }
    
    private var previousMonthComparison: (closures: Int, percentage: Double)? {
        guard isCurrentMonth else { return nil }
        
        let calendar = Calendar.current
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) else {
            return nil
        }
        
        // Calcola la data corrispondente alla stessa percentuale del mese precedente
        let startOfPrevMonth = calendar.startOfMonth(for: previousMonth)
        let endOfPrevMonth = calendar.endOfMonth(for: previousMonth)
        
        // Fetch dei sinistri chiusi nel mese precedente
        var predicateFormat = "dataChiusura >= %@ AND dataChiusura <= %@ AND stato == %@"
        var predicateArgs: [Any] = [startOfPrevMonth as NSDate, endOfPrevMonth as NSDate, StatoManager.StatoSinistro.chiusa.descrizione]
        
        if let userEmail = currentUserEmail, !userEmail.isEmpty {
            predicateFormat += " AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        let previousClosures = (try? viewContext.fetch(request))?.count ?? 0
        
        // Calcola la differenza percentuale
        let percentage = previousClosures > 0 
            ? Double(monthlyClosedClaims.count - previousClosures) / Double(previousClosures) * 100
            : 100
        
        return (closures: previousClosures, percentage: percentage)
    }
    
    private func isClosureTask(_ task: DailyTask) -> Bool {
        let title = task.title.lowercased()
        return title.contains("chiudi sinistro") ||
               title.contains("chiudere sinistro") ||
               title.contains("chiusura sinistro")
    }
    
    private func closuresCount(in interval: DateInterval) -> Int {
        monthlyClosedClaims.filter { sinistro in
            guard let date = sinistro.dataChiusura else { return false }
            return interval.contains(date)
        }.count
    }
    
    private var weekProgressDelta: Double {
        let calendar = Calendar.current
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        let elapsed = Date().timeIntervalSince(currentWeek.start)
        let currentInterval = DateInterval(start: currentWeek.start, end: Date())
        
        guard let previousWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeek.start),
              let previousWeek = calendar.dateInterval(of: .weekOfYear, for: previousWeekStart) else { return 0 }
        
        let previousEnd = min(previousWeek.start.addingTimeInterval(elapsed), previousWeek.end)
        let previousInterval = DateInterval(start: previousWeek.start, end: previousEnd)
        
        let current = closuresCount(in: currentInterval)
        let previous = closuresCount(in: previousInterval)
        
        guard previous > 0 else { return current > 0 ? 100 : 0 }
        return (Double(current - previous) / Double(previous)) * 100
    }
    
    private var monthProgressDelta: Double {
        guard isCurrentMonth else { return 0 }
        
        let calendar = Calendar.current
        let today = Date()
        let dayOfMonth = calendar.component(.day, from: today)
        
        // Calcola le chiusure fino ad oggi nel mese corrente
        let currentClosures = closuresCount(in: DateInterval(start: calendar.startOfMonth(for: today), end: today))
        
        // Calcola le chiusure fino allo stesso giorno del mese precedente
        guard let prevMonth = calendar.date(byAdding: .month, value: -1, to: today) else { return 0 }
        let prevMonthStart = calendar.startOfMonth(for: prevMonth)
        
        // Calcola il giorno corrispondente nel mese precedente (stesso giorno del mese)
        let daysInPrevMonth = calendar.range(of: .day, in: .month, for: prevMonth)?.count ?? 30
        let targetDay = min(dayOfMonth, daysInPrevMonth)
        
        guard let prevMonthDate = calendar.date(bySetting: .day, value: targetDay, of: prevMonthStart) else { return 0 }
        let prevInterval = DateInterval(start: prevMonthStart, end: prevMonthDate)
        
        let previousClosures = closuresCount(in: prevInterval)
        
        guard previousClosures > 0 else { return currentClosures > 0 ? 100 : 0 }
        return (Double(currentClosures - previousClosures) / Double(previousClosures)) * 100
    }
    
    private var yoyProgressDelta: Double {
        guard isCurrentMonth else { return 0 }
        
        let calendar = Calendar.current
        let today = Date()
        let dayOfMonth = calendar.component(.day, from: today)
        
        // Calcola le chiusure fino ad oggi nel mese corrente
        let currentClosures = closuresCount(in: DateInterval(start: calendar.startOfMonth(for: today), end: today))
        
        // Calcola le chiusure fino allo stesso giorno dell'anno precedente
        guard let prevYearDate = calendar.date(byAdding: .year, value: -1, to: today) else { return 0 }
        let prevYearMonthStart = calendar.startOfMonth(for: prevYearDate)
        
        // Calcola il giorno corrispondente nell'anno precedente (stesso giorno del mese)
        let daysInPrevYearMonth = calendar.range(of: .day, in: .month, for: prevYearDate)?.count ?? 30
        let targetDay = min(dayOfMonth, daysInPrevYearMonth)
        
        guard let prevYearTargetDate = calendar.date(bySetting: .day, value: targetDay, of: prevYearMonthStart) else { return 0 }
        let prevInterval = DateInterval(start: prevYearMonthStart, end: prevYearTargetDate)
        
        let previousClosures = closuresCount(in: prevInterval)
        
        guard previousClosures > 0 else { return currentClosures > 0 ? 100 : 0 }
        return (Double(currentClosures - previousClosures) / Double(previousClosures)) * 100
    }
    
    private var todayClosuresCount: Int {
        let calendar = Calendar.current
        return monthlyClosedClaims.filter {
            calendar.isDate($0.dataChiusura ?? Date.distantPast, inSameDayAs: Date())
        }.count
    }
    
    private var todaySentReportsCount: Int {
        let calendar = Calendar.current
        return monthlySentReports.filter {
            calendar.isDate($0.dataInvioAtto ?? Date.distantPast, inSameDayAs: Date())
        }.count
    }
    
    // Totale unico: sinistri che hanno avuto atto O chiusura oggi (se hanno entrambi, contano come 1)
    private var todayTotalUnique: Int {
        let calendar = Calendar.current
        let today = Date()
        
        var sinistriOggi = Set<String>()
        
        // Aggiungi sinistri con chiusura oggi
        monthlyClosedClaims.forEach { sinistro in
            if let dataChiusura = sinistro.dataChiusura,
               calendar.isDate(dataChiusura, inSameDayAs: today),
               let riferimento = sinistro.riferimento {
                sinistriOggi.insert(riferimento)
            }
        }
        
        // Aggiungi sinistri con atto inviato oggi
        monthlySentReports.forEach { sinistro in
            if let dataInvio = sinistro.dataInvioAtto,
               calendar.isDate(dataInvio, inSameDayAs: today),
               let riferimento = sinistro.riferimento {
                sinistriOggi.insert(riferimento)
            }
        }
        
        return sinistriOggi.count
    }
    
    // Struct per i dati giornalieri
    struct DailyStats {
        let date: Date
        let sentReports: Int
        let closures: Int
        let totalUnique: Int
    }
    
    // Dati degli ultimi 4-5 giorni (escluso oggi)
    // Mostra solo giorni con almeno un'ora lavorativa O con almeno un dato registrato
    private var recentDaysStats: [DailyStats] {
        guard isCurrentMonth else { return [] }
        
        let calendar = Calendar.current
        let today = Date()
        var stats: [DailyStats] = []
        
        // Prendi gli ultimi giorni (fino a 10 giorni fa per avere abbastanza opzioni)
        for daysAgo in 1...10 {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            
            // Verifica che la data sia nel mese corrente
            if !calendar.isDate(date, equalTo: today, toGranularity: .month) {
                continue
            }
            
            // Chiusure del giorno
            let closures = monthlyClosedClaims.filter {
                calendar.isDate($0.dataChiusura ?? Date.distantPast, inSameDayAs: date)
            }.count
            
            // Atti inviati del giorno
            let sentReports = monthlySentReports.filter {
                calendar.isDate($0.dataInvioAtto ?? Date.distantPast, inSameDayAs: date)
            }.count
            
            // Totale unico
            var sinistriGiorno = Set<String>()
            monthlyClosedClaims.forEach { sinistro in
                if let dataChiusura = sinistro.dataChiusura,
                   calendar.isDate(dataChiusura, inSameDayAs: date),
                   let riferimento = sinistro.riferimento {
                    sinistriGiorno.insert(riferimento)
                }
            }
            monthlySentReports.forEach { sinistro in
                if let dataInvio = sinistro.dataInvioAtto,
                   calendar.isDate(dataInvio, inSameDayAs: date),
                   let riferimento = sinistro.riferimento {
                    sinistriGiorno.insert(riferimento)
                }
            }
            
            let totalUnique = sinistriGiorno.count
            
            // Verifica se il giorno ha almeno un'ora lavorativa O almeno un dato registrato
            let hasWorkingHours = workingHours(on: date) > 0
            let hasData = sentReports > 0 || closures > 0 || totalUnique > 0
            
            // Aggiungi solo se ha ore lavorative o dati registrati
            if hasWorkingHours || hasData {
                stats.append(DailyStats(
                    date: date,
                    sentReports: sentReports,
                    closures: closures,
                    totalUnique: totalUnique
                ))
            }
            
            // Fermati quando abbiamo 4 giorni validi
            if stats.count >= 4 {
                break
            }
        }
        
        return stats
    }
    
    private var todayClosureTasks: [DailyTask] {
        taskManager.getTasksForDate(Date()).filter { $0.status == .pending && isClosureTask($0) }
    }
    
    private var todayMinorTasksCount: Int {
        taskManager.getTasksForDate(Date()).filter { $0.status == .pending && !isClosureTask($0) }.count
    }
    
    private var todayPlannedTasks: Int {
        todayClosureTasks.count
    }
    
    private var todayWorkingHours: Double {
        workingHours(on: Date())
    }
    
    private var remainingWeekHours: Double {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        var cursor = calendar.startOfDay(for: Date())
        var total = 0.0
        while cursor < interval.end {
            total += workingHours(on: cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? interval.end
        }
        return total
    }
    
    private var remainingMonthHours: Double {
        let calendar = Calendar.current
        let start = isCurrentMonth ? calendar.startOfDay(for: Date()) : calendar.startOfMonth(for: selectedMonth)
        let endOfMonth = calendar.endOfMonth(for: selectedMonth)
        
        var cursor = start
        var total = 0.0
        while cursor <= endOfMonth {
            total += workingHours(on: cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? endOfMonth
        }
        return total
    }
    
    private var productivityPerHour: Double {
        let hours = isCurrentMonth
            ? workSchedule.calculateWorkedHoursUpToNow(in: selectedMonth)
            : workSchedule.calculateTotalMonthHours(for: selectedMonth)
        guard hours > 0 else { return 0 }
        return Double(monthlyClosedClaims.count) / hours
    }
    
    private var previousMonthDate: Date? {
        Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth)
    }
    
    private var previousYearDate: Date? {
        Calendar.current.date(byAdding: .year, value: -1, to: selectedMonth)
    }
    
    private var previousYearClosedClaims: [Sinistro] {
        guard let prevYear = previousYearDate else { return [] }
        let calendar = Calendar.current
        let startOfMonth = calendar.startOfMonth(for: prevYear)
        let endOfMonth = calendar.endOfMonth(for: prevYear)
        
        var predicateFormat = "dataChiusura >= %@ AND dataChiusura <= %@ AND stato == %@"
        var predicateArgs: [Any] = [startOfMonth as NSDate, endOfMonth as NSDate, StatoManager.StatoSinistro.chiusa.descrizione]
        
        if let userEmail = currentUserEmail, !userEmail.isEmpty {
            predicateFormat += " AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        return (try? viewContext.fetch(request)) ?? []
    }
    
    private var previousMonthProductivity: Double {
        guard let prevMonth = previousMonthDate else { return 0 }
        let hours = workSchedule.calculateTotalMonthHours(for: prevMonth)
        guard hours > 0 else { return 0 }
        return Double(previousMonthClosedClaims.count) / hours
    }
    
    private var previousYearProductivity: Double {
        guard let prevYear = previousYearDate else { return 0 }
        let hours = workSchedule.calculateTotalMonthHours(for: prevYear)
        guard hours > 0 else { return 0 }
        return Double(previousYearClosedClaims.count) / hours
    }
    
    private var momProgressDelta: Double { monthProgressDelta }
    
    private var yoyProgressDeltaValue: Double { yoyProgressDelta }
    
    private var todayProjectedClosures: Int {
        max(todayPlannedTasks, Int(round(productivityPerHour * todayWorkingHours)))
    }
    
    private var currentWeekClosures: Int {
        let calendar = Calendar.current
        return monthlyClosedClaims.filter {
            guard let date = $0.dataChiusura else { return false }
            return calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
        }.count
    }
    
    private var weeklyProjectedClosures: Int {
        currentWeekClosures + Int(round(productivityPerHour * remainingWeekHours))
    }
    
    private var monthlyProjectedClosuresByHours: Int {
        monthlyClosedClaims.count + Int(round(productivityPerHour * remainingMonthHours))
    }
    
    private var liquidationHistory: [MonthlyLiquidationStats] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        
        // Prendi gli ultimi 12 mesi
        return (0...11).compactMap { monthOffset in
            guard let date = calendar.date(byAdding: .month, value: -monthOffset, to: selectedMonth) else { return nil }
            
            let startOfMonth = calendar.startOfMonth(for: date)
            let endOfMonth = calendar.endOfMonth(for: date)
            
            var predicateFormat = "dataChiusura >= %@ AND dataChiusura <= %@ AND stato == %@"
            var predicateArgs: [Any] = [startOfMonth as NSDate, endOfMonth as NSDate, "Chiuso"]
            
            if let userEmail = currentUserEmail, !userEmail.isEmpty {
                predicateFormat += " AND assignedToUserEmail ==[c] %@"
                predicateArgs.append(userEmail)
            }
            
            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
            
            guard let claims = try? viewContext.fetch(request) else { return nil }
            
            // Per le medie liquidato contiamo SOLO i sinistri in PL
            let inPLClaims = claims.filter { $0.isInPL }
            
            let under5k = inPLClaims.filter { sinistro in
                guard let importo = sinistro.importoLiquidatoEffettivo?.doubleValue else { return false }
                return importo >= 1 && importo <= 5000
            }
            
            let under10k = inPLClaims.filter { sinistro in
                guard let importo = sinistro.importoLiquidatoEffettivo?.doubleValue else { return false }
                return importo >= 1 && importo <= 10000
            }
            
            // Per le negative contiamo SOLO i sinistri senza liquidazione
            let negative = claims.filter { $0.isNegativa }
            
            let avg5k = under5k.isEmpty ? 0 : under5k.compactMap { $0.importoLiquidatoEffettivo?.doubleValue }.reduce(0, +) / Double(under5k.count)
            let avg10k = under10k.isEmpty ? 0 : under10k.compactMap { $0.importoLiquidatoEffettivo?.doubleValue }.reduce(0, +) / Double(under10k.count)
            let negativePerc = claims.count > 0 ? (Double(negative.count) / Double(claims.count)) * 100 : 0
            
            return MonthlyLiquidationStats(
                date: date,
                monthName: formatter.string(from: date).capitalized,
                averageUnder5k: avg5k,
                averageUnder10k: avg10k,
                negativePercentage: negativePerc,
                totalClaims: claims.count
            )
        }
    }
    
    private var historicalDailyAverage: Double {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .month, value: -12, to: endDate) else { return 0 }
        
        var predicateFormat = "(dataChiusura >= %@ AND dataChiusura <= %@ AND stato == %@) OR (dataRitornoAtto >= %@ AND dataRitornoAtto <= %@)"
        var predicateArgs: [Any] = [startDate as NSDate, endDate as NSDate, "Chiuso", startDate as NSDate, endDate as NSDate]
        
        if let userEmail = currentUserEmail, !userEmail.isEmpty {
            predicateFormat = "(\(predicateFormat)) AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        guard let claims = try? viewContext.fetch(request) else { return 0 }
        let totalWorkingDays = workSchedule.countWorkingDaysInPeriod(from: startDate, to: endDate)
        guard totalWorkingDays > 0 else { return 0 }
        
        return Double(claims.count) / Double(totalWorkingDays)
    }
    
    private func requiredDailyClosures(target: Int, currentCount: Int) -> Double {
        let remainingDays = workSchedule.remainingWorkingDays(from: Date(), in: selectedMonth)
        guard remainingDays > 0 else { return 0 }
        let remaining = max(0, target - currentCount)
        return Double(remaining) / Double(remainingDays)
    }
    
    private func getRequiredClosuresColor(_ required: Double, historicalAverage: Double) -> Color {
        if required <= historicalAverage {
            return .green
        } else if required <= historicalAverage * 1.3 { // 30% in più della media
            return .yellow
        } else {
            return .red
        }
    }
    
    private func workingHours(on date: Date) -> Double {
        workSchedule
            .getWorkingHours(for: date)
            .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) / 3600 }
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: selectedMonth).capitalized
    }
    
    private var fatturatoDisplayMode: FatturatoDisplayMode {
        get {
            FatturatoDisplayMode(rawValue: fatturatoDisplayModeRaw) ?? .lordoStimato
        }
        set {
            fatturatoDisplayModeRaw = newValue.rawValue
        }
    }
    
    private var monthlyRevenue: Double {
        // Se c'è una fattura effettiva, usala indipendentemente dalla modalità
        if let fatturatoEffettivo = fatturaMensileService.getFatturatoEffettivo(for: selectedMonth) {
            return fatturatoEffettivo
        }
        
        // Calcola i breakdown
        let sinistri = monthlyClosedClaims
        let sinistriChiusiSuccessful = ConsuntivoStatsService.shared.getMonthlyClosedClaimsSuccessful(for: selectedMonth, in: viewContext, userEmail: currentUserEmail)
        let bonusMensili = BonusMensileService.shared.calcolaTotaleBonus(for: selectedMonth, sinistriChiusi: sinistriChiusiSuccessful, in: viewContext)
        let bonusList = BonusMensileService.shared.getBonus(for: selectedMonth).filter { $0.attivo }
        let bonusDetails = bonusList.map { bonus in
            let importoBonus = BonusMensileService.shared.calcolaImportoBonus(bonus, for: sinistriChiusiSuccessful, in: viewContext, month: selectedMonth)
            return BonusMensileDetail(
                nome: bonus.nome,
                tipo: bonus.tipo,
                importo: importoBonus
            )
        }
        let breakdown = FatturatoSettings.shared.calcolaBreakdownFatturato(sinistri: sinistri, bonusMensili: bonusMensili, bonusMensiliList: bonusDetails)
        let fiscaleBreakdown = FatturatoSettings.shared.calcolaFatturatoFiscale(
            breakdown: breakdown,
            fiscaleSettings: FatturatoFiscaleSettings.shared,
            for: selectedMonth
        )
        
        // Restituisce il valore in base alla modalità selezionata
        switch fatturatoDisplayMode {
        case .base:
            // Solo base + fasce (senza bonus, senza marca da bollo, senza rivalsa)
            return breakdown.totaleFatturato - breakdown.bonusMensili
        case .conBonus:
            // Base + fasce + bonus (senza marca da bollo e rivalsa)
            return breakdown.totaleFatturato
        case .lordoStimato:
            // Base + fasce + bonus + marca da bollo + rivalsa
            return fiscaleBreakdown.fatturatoLordo
        }
    }
    
    private var fatturatoTitle: String {
        if let _ = fatturaMensileService.getFatturatoEffettivo(for: selectedMonth) {
            return "Fatturato"
        }
        return fatturatoDisplayMode.description
    }
    
    private var isFatturatoStimato: Bool {
        fatturaMensileService.getFatturatoEffettivo(for: selectedMonth) == nil
    }
    
    // Gruppi uniti salvati in UserDefaults (chiave: nome gruppo normalizzato)
    @AppStorage("unitedGroups") private var unitedGroupsData: Data = Data()
    
    private var unitedGroups: Set<String> {
        if let decoded = try? JSONDecoder().decode(Set<String>.self, from: unitedGroupsData) {
            return decoded
        }
        return []
    }
    
    private func setUnitedGroups(_ groups: Set<String>) {
        if let encoded = try? JSONEncoder().encode(groups) {
            unitedGroupsData = encoded
        }
    }
    
    // MARK: - Competenza Helpers
    
    /// Estrae l'anno di competenza dal riferimento (primi due numeri)
    /// Esempio: 2514419 -> 2025
    private func annoCompetenza(from riferimento: String?) -> Int? {
        guard let rif = riferimento, rif.count >= 2 else { return nil }
        let firstTwo = String(rif.prefix(2))
        guard let yearDigits = Int(firstTwo) else { return nil }
        // Se i primi due numeri sono >= 20, assumiamo 20XX, altrimenti 2000 + XX
        return yearDigits >= 20 ? 2000 + yearDigits : 2000 + yearDigits
    }
    
    /// Determina se un sinistro è di competenza dell'anno corrente
    private func isSinistroDiCompetenzaAnnoCorrente(_ sinistro: Sinistro, annoChiusura: Int) -> Bool {
        // Prima prova con il riferimento
        if let riferimento = sinistro.riferimento,
           let annoCompetenza = annoCompetenza(from: riferimento) {
            return annoCompetenza == annoChiusura
        }
        
        // Se non c'è riferimento valido, usa la data di incarico
        if let dataIncarico = sinistro.dataIncarico {
            let annoIncarico = Calendar.current.component(.year, from: dataIncarico)
            return annoIncarico == annoChiusura
        }
        
        // Se non c'è né riferimento né data incarico, escludi
        return false
    }
    
    /// Filtra i sinistri per competenza dell'anno di chiusura
    private func filtraPerCompetenza(_ sinistri: [Sinistro], annoRiferimento: Int? = nil) -> [Sinistro] {
        guard soloCompetenza else { return sinistri }
        
        return sinistri.filter { sinistro in
            guard let dataChiusura = sinistro.dataChiusura else { return false }
            let annoChiusuraSinistro = Calendar.current.component(.year, from: dataChiusura)
            
            // Determina l'anno di competenza
            var annoCompetenzaSinistro: Int?
            
            // Prima prova con il riferimento
            if let riferimento = sinistro.riferimento,
               let annoCompetenza = annoCompetenza(from: riferimento) {
                annoCompetenzaSinistro = annoCompetenza
            }
            // Se non c'è riferimento valido, usa la data di incarico
            else if let dataIncarico = sinistro.dataIncarico {
                annoCompetenzaSinistro = Calendar.current.component(.year, from: dataIncarico)
            }
            
            guard let annoCompetenza = annoCompetenzaSinistro else { return false }
            
            // Il sinistro deve essere di competenza dell'anno di chiusura
            // E se è chiuso in un anno diverso da quello di competenza, escludilo
            if annoCompetenza != annoChiusuraSinistro {
                return false
            }
            
            // Se è specificato un anno di riferimento, verifica anche quello
            if let annoRif = annoRiferimento {
                return annoCompetenza == annoRif
            }
            
            return true
        }
    }
    
    // Statistiche per compagnia (sempre calcolate per compagnia)
    private var statsByCompany: [LiquidationStats] {
        let filteredClaims = filtraPerCompetenza(monthlyClosedClaims)
        return ConsuntivoStatsService.shared.getLiquidationStats(for: filteredClaims, groupByCompany: true)
    }
    
    // Statistiche finali (unite per gruppo se necessario)
    private var stats: [LiquidationStats] {
        let companyStats = statsByCompany
        
        // Raggruppa per gruppo
        let groupedByGruppo = Dictionary(grouping: companyStats) { stat in
            // Trova il gruppo dalla compagnia
            let compagnia = Compagnia.from(nomeCompagnia: stat.company)
            return compagnia.gruppo.rawValue.lowercased().trimmingCharacters(in: .whitespaces)
        }
        
        var result: [LiquidationStats] = []
        
        for (gruppoKey, statsInGruppo) in groupedByGruppo {
            let gruppoNormalized = gruppoKey
            let shouldUnite = unitedGroups.contains(gruppoNormalized) && statsInGruppo.count > 1
            
            if shouldUnite {
                // Unisci le compagnie del gruppo
                let gruppoEnum = GruppoAssicurativo.from(nomeGruppo: statsInGruppo.first?.company)
                let gruppoName = "Gruppo \(gruppoEnum.rawValue)"
                
                // Calcola le statistiche aggregate
                let totalClaims = statsInGruppo.reduce(0) { $0 + $1.totalClaims }
                
                // Media ponderata per le liquidazioni
                let totalInPL = statsInGruppo.reduce(0.0) { sum, stat in
                    sum + (stat.averageUnder10kInPL * Double(stat.totalClaims))
                }
                let avgInPL = totalClaims > 0 ? totalInPL / Double(totalClaims) : 0
                
                let totalAll = statsInGruppo.reduce(0.0) { sum, stat in
                    sum + (stat.averageUnder10kAll * Double(stat.totalClaims))
                }
                let avgAll = totalClaims > 0 ? totalAll / Double(totalClaims) : 0
                
                // Media ponderata per le negative
                let totalNegative = statsInGruppo.reduce(0.0) { sum, stat in
                    sum + (stat.negativePercentage * Double(stat.totalClaims))
                }
                let avgNegative = totalClaims > 0 ? totalNegative / Double(totalClaims) : 0
                
                // Media ponderata per tempo gestione
                let totalGestione = statsInGruppo.reduce(0.0) { sum, stat in
                    sum + (stat.averageGestioneDays * Double(stat.totalClaims))
                }
                let avgGestione = totalClaims > 0 ? totalGestione / Double(totalClaims) : 0
                
                // Media ponderata per concordate
                let totalConcordate = statsInGruppo.reduce(0.0) { sum, stat in
                    sum + (stat.concordatePercentage * Double(stat.totalClaims))
                }
                let avgConcordate = totalClaims > 0 ? totalConcordate / Double(totalClaims) : 0
                
                // Dettagli per compagnia (per mostrare sotto il nome)
                let companyDetails = statsInGruppo.map { stat in
                    (company: stat.company, count: stat.totalClaims)
                }
                
                // Crea una stat unificata (useremo un campo custom per i dettagli)
                // Unisci anche i sinistri senza dati
                let sinistriSenzaDataAssegnazione = statsInGruppo.flatMap { $0.sinistriSenzaDataAssegnazione }
                let sinistriSenzaLiquidazione = statsInGruppo.flatMap { $0.sinistriSenzaLiquidazione }
                let sinistriSenzaDefinizione = statsInGruppo.flatMap { $0.sinistriSenzaDefinizione }
                
                let unifiedStat = LiquidationStats(
                    company: gruppoName,
                    averageUnder5k: avgInPL,
                    averageUnder10k: avgInPL,
                    averageUnder5kInPL: avgInPL,
                    averageUnder10kInPL: avgInPL,
                    averageUnder5kAll: avgAll,
                    averageUnder10kAll: avgAll,
                    negativePercentage: avgNegative,
                    concordatePercentage: avgConcordate,
                    averageGestioneDays: avgGestione,
                    totalClaims: totalClaims,
                    sinistriSenzaDataAssegnazione: sinistriSenzaDataAssegnazione,
                    sinistriSenzaLiquidazione: sinistriSenzaLiquidazione,
                    sinistriSenzaDefinizione: sinistriSenzaDefinizione
                )
                
                // Aggiungi i dettagli delle compagnie (useremo un'estensione o campo custom)
                result.append(unifiedStat)
            } else {
                // Mostra le compagnie separate
                result.append(contentsOf: statsInGruppo)
            }
        }
        
        return result.sorted { $0.company < $1.company }
    }
    
    // Dettagli delle compagnie per ogni gruppo unito
    private var companyDetailsForGroups: [String: [(company: String, count: Int)]] {
        let companyStats = statsByCompany
        let groupedByGruppo = Dictionary(grouping: companyStats) { stat in
            let compagnia = Compagnia.from(nomeCompagnia: stat.company)
            return compagnia.gruppo.rawValue.lowercased().trimmingCharacters(in: .whitespaces)
        }
        
        var details: [String: [(company: String, count: Int)]] = [:]
        
        for (gruppoKey, statsInGruppo) in groupedByGruppo {
            let gruppoNormalized = gruppoKey
            if unitedGroups.contains(gruppoNormalized) && statsInGruppo.count > 1 {
                details[gruppoNormalized] = statsInGruppo.map { stat in
                    (company: stat.company, count: stat.totalClaims)
                }
            }
        }
        
        return details
    }
    
    private var previousMonthStats: [LiquidationStats] {
        guard let prevMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) else {
            return []
        }
        let prevMonthClaims = ConsuntivoStatsService.shared.getMonthlyClosedClaims(for: prevMonth, in: viewContext, userEmail: currentUserEmail)
        let annoPrevMonth = Calendar.current.component(.year, from: prevMonth)
        let filteredPrevMonthClaims = soloCompetenza ? filtraPerCompetenza(prevMonthClaims, annoRiferimento: annoPrevMonth) : prevMonthClaims
        let prevCompanyStats = ConsuntivoStatsService.shared.getLiquidationStats(for: filteredPrevMonthClaims, groupByCompany: true)
        
        // Applica la stessa logica di unione
        let groupedByGruppo = Dictionary(grouping: prevCompanyStats) { stat in
            let compagnia = Compagnia.from(nomeCompagnia: stat.company)
            return compagnia.gruppo.rawValue.lowercased().trimmingCharacters(in: .whitespaces)
        }
        
        var result: [LiquidationStats] = []
        
        for (gruppoKey, statsInGruppo) in groupedByGruppo {
            let gruppoNormalized = gruppoKey
            let shouldUnite = unitedGroups.contains(gruppoNormalized) && statsInGruppo.count > 1
            
            if shouldUnite {
                let gruppoEnum = GruppoAssicurativo.from(nomeGruppo: statsInGruppo.first?.company)
                let gruppoName = "Gruppo \(gruppoEnum.rawValue)"
                let totalClaims = statsInGruppo.reduce(0) { $0 + $1.totalClaims }
                
                let totalInPL = statsInGruppo.reduce(0.0) { sum, stat in
                    sum + (stat.averageUnder10kInPL * Double(stat.totalClaims))
                }
                let avgInPL = totalClaims > 0 ? totalInPL / Double(totalClaims) : 0
                
                let totalAll = statsInGruppo.reduce(0.0) { sum, stat in
                    sum + (stat.averageUnder10kAll * Double(stat.totalClaims))
                }
                let avgAll = totalClaims > 0 ? totalAll / Double(totalClaims) : 0
                
                let totalNegative = statsInGruppo.reduce(0.0) { sum, stat in
                    sum + (stat.negativePercentage * Double(stat.totalClaims))
                }
                let avgNegative = totalClaims > 0 ? totalNegative / Double(totalClaims) : 0
                
                // Media ponderata per tempo gestione
                let totalGestione = statsInGruppo.reduce(0.0) { sum, stat in
                    sum + (stat.averageGestioneDays * Double(stat.totalClaims))
                }
                let avgGestione = totalClaims > 0 ? totalGestione / Double(totalClaims) : 0
                
                // Media ponderata per concordate
                let totalConcordate = statsInGruppo.reduce(0.0) { sum, stat in
                    sum + (stat.concordatePercentage * Double(stat.totalClaims))
                }
                let avgConcordate = totalClaims > 0 ? totalConcordate / Double(totalClaims) : 0
                
                // Unisci anche i sinistri senza dati
                let sinistriSenzaDataAssegnazione = statsInGruppo.flatMap { $0.sinistriSenzaDataAssegnazione }
                let sinistriSenzaLiquidazione = statsInGruppo.flatMap { $0.sinistriSenzaLiquidazione }
                let sinistriSenzaDefinizione = statsInGruppo.flatMap { $0.sinistriSenzaDefinizione }
                
                let unifiedStat = LiquidationStats(
                    company: gruppoName,
                    averageUnder5k: avgInPL,
                    averageUnder10k: avgInPL,
                    averageUnder5kInPL: avgInPL,
                    averageUnder10kInPL: avgInPL,
                    averageUnder5kAll: avgAll,
                    averageUnder10kAll: avgAll,
                    negativePercentage: avgNegative,
                    concordatePercentage: avgConcordate,
                    averageGestioneDays: avgGestione,
                    totalClaims: totalClaims,
                    sinistriSenzaDataAssegnazione: sinistriSenzaDataAssegnazione,
                    sinistriSenzaLiquidazione: sinistriSenzaLiquidazione,
                    sinistriSenzaDefinizione: sinistriSenzaDefinizione
                )
                
                result.append(unifiedStat)
            } else {
                result.append(contentsOf: statsInGruppo)
            }
        }
        
        return result.sorted { $0.company < $1.company }
    }
    
    // Determina se ci sono più compagnie dello stesso gruppo nel mese
    private func hasMultipleCompaniesInGroup(for stat: LiquidationStats) -> Bool {
        // Calcola il gruppo dal nome della compagnia
        let compagnia = Compagnia.from(nomeCompagnia: stat.company)
        let gruppo = compagnia.gruppo
        let gruppoKey = gruppo.rawValue.lowercased().trimmingCharacters(in: CharacterSet.whitespaces)
        
        // Conta quante compagnie di questo gruppo ci sono nelle stats per compagnia
        let companiesInGroup = statsByCompany.filter { companyStat in
            let comp = Compagnia.from(nomeCompagnia: companyStat.company)
            return comp.gruppo.rawValue.lowercased().trimmingCharacters(in: CharacterSet.whitespaces) == gruppoKey
        }
        
        return companiesInGroup.count > 1
    }
    
    // Ottiene la chiave del gruppo normalizzata per una stat
    private func getGroupKey(for stat: LiquidationStats) -> String {
        let compagnia = Compagnia.from(nomeCompagnia: stat.company)
        return compagnia.gruppo.rawValue.lowercased().trimmingCharacters(in: CharacterSet.whitespaces)
    }
    
    // Toggle per unire/separare un gruppo
    private func toggleGroupUnion(for stat: LiquidationStats) {
        let groupKey = getGroupKey(for: stat)
        var updatedGroups = unitedGroups
        if updatedGroups.contains(groupKey) {
            updatedGroups.remove(groupKey)
        } else {
            updatedGroups.insert(groupKey)
        }
        setUnitedGroups(updatedGroups)
    }
    
    // Verifica se un gruppo è unito
    private func isGroupUnited(for stat: LiquidationStats) -> Bool {
        let groupKey = getGroupKey(for: stat)
        return unitedGroups.contains(groupKey)
    }
    
    private func loadRangesAndThresholds() {
        if let decodedRanges = try? JSONDecoder().decode([CompensationRange].self, from: compensationRanges) {
            ranges = decodedRanges
        }
        if let decodedThresholds = try? JSONDecoder().decode([DamageThreshold].self, from: damageThresholdsData) {
            damageThresholds = decodedThresholds
        }
    }
    
    // MARK: - Modern UI Components
    
    private var modernHeader: some View {
        HStack(spacing: 20) {
            // Navigazione mesi moderna
            HStack(spacing: 8) {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Mese precedente")
                
                VStack(spacing: 2) {
                    Text(monthYearString)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    if !isCurrentMonth {
                        Button {
                            selectedMonth = Date()
                        } label: {
                            Text("Oggi")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 140)
                
                Button(action: nextMonth) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Mese successivo")
                .disabled(Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
            
            Spacer()
            
            // Bottone Report Annuale
            Button {
                showYearlyReport.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.doc.horizontal.fill")
                    Text("Report Annuale")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [.blue, Color(hex: "764BA2")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(10)
                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Group {
                if colorScheme == .dark {
                    Color(NSColor.windowBackgroundColor)
                } else {
                    LinearGradient(
                        colors: [Color.white, Color(hex: "F8F9FA")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        )
    }
    
    private var modernKPIGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ModernKPICard(
                title: "Sinistri Chiusi",
                value: String(monthlyClosedClaims.count),
                icon: StatoManager.StatoSinistro.chiusa.icon,
                color: StatoManager.StatoSinistro.chiusa.color,
                gradient: [Color(hex: "11998E"), Color(hex: "38EF7D")]
            )
            .onTapGesture {
                openClosedClaimsWindow()
            }
            
            ModernKPICard(
                title: "Atti Inviati",
                value: String(monthlySentReports.count),
                icon: StatoManager.StatoSinistro.attoInviato.icon,
                color: StatoManager.StatoSinistro.attoInviato.color,
                gradient: [.blue, Color(hex: "764BA2")]
            )
            .onTapGesture {
                openSentReportsWindow()
            }
            
            ModernKPICard(
                title: "Media Giornaliera",
                value: String(format: "%.1f", dailyAverage),
                icon: "chart.line.uptrend.xyaxis",
                color: getDailyAverageColor(dailyAverage),
                gradient: getDailyAverageColor(dailyAverage) == .green 
                    ? [Color(hex: "11998E"), Color(hex: "38EF7D")]
                    : getDailyAverageColor(dailyAverage) == .yellow
                    ? [Color(hex: "FFC837"), Color(hex: "FF8008")]
                    : [Color(hex: "FF416C"), Color(hex: "FF4B2B")]
            )
            
            ModernKPICard(
                title: fatturatoTitle,
                value: CurrencyFormatter.shared.formatWithSymbol(monthlyRevenue),
                icon: "eurosign.circle.fill",
                color: .purple,
                gradient: [Color(hex: "F093FB"), Color(hex: "F5576C")]
            )
            .onTapGesture {
                showingFatturatoDetail = true
            }
            .contextMenu {
                Button(action: {
                    fatturatoDisplayModeRaw = FatturatoDisplayMode.base.rawValue
                }) {
                    Label("Fatturato Sinistri", systemImage: fatturatoDisplayMode == .base ? "checkmark" : "")
                }
                
                Button(action: {
                    fatturatoDisplayModeRaw = FatturatoDisplayMode.conBonus.rawValue
                }) {
                    Label("Fatturato comprensivo di Bonus", systemImage: fatturatoDisplayMode == .conBonus ? "checkmark" : "")
                }
                
                Button(action: {
                    fatturatoDisplayModeRaw = FatturatoDisplayMode.lordoStimato.rawValue
                }) {
                    Label("Fatturato Lordo Stimato", systemImage: fatturatoDisplayMode == .lordoStimato ? "checkmark" : "")
                }
            }
            
            ModernKPICard(
                title: "Assegnati",
                value: String(monthlyAssignedClaims.count),
                icon: "envelope.badge.fill",
                color: .blue,
                gradient: [Color(hex: "4A90E2"), Color(hex: "357ABD")]
            )
            .onTapGesture {
                openAssignedClaimsWindow()
            }
        }
    }
    
    // MARK: - KPI Window Helpers
    
    private func openClosedClaimsWindow() {
        let cal = Calendar.current
        let config = FilterConfig.closedSinistriForMonth(
            year: cal.component(.year, from: selectedMonth),
            month: cal.component(.month, from: selectedMonth),
            userEmail: currentUserEmail
        )
        FilteredSinistriWindowHelper.open(config: config)
    }
    
    private func openSentReportsWindow() {
        let cal = Calendar.current
        let config = FilterConfig.sentReportsForMonth(
            year: cal.component(.year, from: selectedMonth),
            month: cal.component(.month, from: selectedMonth),
            userEmail: currentUserEmail
        )
        FilteredSinistriWindowHelper.open(config: config)
    }
    
    private func openAssignedClaimsWindow() {
        let cal = Calendar.current
        let config = FilterConfig.assignedClaimsForMonth(
            year: cal.component(.year, from: selectedMonth),
            month: cal.component(.month, from: selectedMonth),
            userEmail: currentUserEmail
        )
        FilteredSinistriWindowHelper.open(config: config)
    }
}

// MARK: - Supporting Views

// MARK: - Modern Card Component
struct ModernCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(24)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 4)
        )
    }
}

// MARK: - Modern KPI Card
struct ModernKPICard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let gradient: [Color]
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 2
                        )
                        .opacity(colorScheme == .dark ? 0.5 : 0.3)
                )
                .shadow(color: gradient[0].opacity(colorScheme == .dark ? 0.3 : 0.15), radius: 10, x: 0, y: 4)
        )
    }
}

struct KPICard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title3)  // Ridotto da .title2
                .bold()
                .foregroundColor(color)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(color.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(color.opacity(0.2), lineWidth: 1)
            ))
        .frame(width: 140)  // Ridotto da 160
    }
}

struct AdaptiveTileRow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content
    
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: spacing)],
            alignment: .leading,
            spacing: spacing
        ) {
            content
        }
    }
}

struct ProjectionBoardView: View {
    let productivityPerHour: Double
    let todayClosures: Int
    let todayProjection: Int
    let plannedToday: Int
    let todayMinorTasks: Int
    let weeklyClosures: Int
    let weeklyProjection: Int
    let monthlyClosures: Int
    let monthlyProjection: Int
    let weekDelta: Double
    let momDelta: Double
    let yoyDelta: Double
    let remainingWeekHours: Double
    let remainingMonthHours: Double
    let todayHours: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Proiezioni operative")
                    .font(.headline)
                Spacer()
                Text("Produttività \(String(format: "%.2f", productivityPerHour)) chiusure/ora")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
                ProjectionCard(
                    title: "Oggi",
                    current: todayClosures,
                    projected: todayProjection,
                    subtitle: "Chiusure pianificate: \(plannedToday) • Task minori: \(todayMinorTasks)",
                    footer: "Ore disponibili: \(String(format: "%.1f", todayHours))h",
                    accent: .blue,
                    deltas: nil
                )
                
                ProjectionCard(
                    title: "Settimana",
                    current: weeklyClosures,
                    projected: weeklyProjection,
                    subtitle: "Ore residue: \(String(format: "%.1f", remainingWeekHours))h",
                    footer: "Media attuale: \(String(format: "%.2f", productivityPerHour))",
                    accent: .orange,
                    deltas: [
                        ("WoW", weekDelta)
                    ]
                )
                
                ProjectionCard(
                    title: "Mese",
                    current: monthlyClosures,
                    projected: monthlyProjection,
                    subtitle: "Ore residue: \(String(format: "%.1f", remainingMonthHours))h",
                    footer: "Produttività: \(String(format: "%.2f", productivityPerHour))",
                    accent: .purple,
                    deltas: [
                        ("MoM", momDelta),
                        ("YoY", yoyDelta)
                    ]
                )
            }
        }
        .padding()
    }
}

struct ProjectionCard: View {
    let title: String
    let current: Int
    let projected: Int
    let subtitle: String
    let footer: String?
    let accent: Color
    let deltas: [(String, Double)]?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(projected)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Attuali")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(current)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if let deltas = deltas {
                    HStack(spacing: 8) {
                        ForEach(deltas, id: \.0) { delta in
                            DeltaBadge(title: delta.0, value: delta.1)
                        }
                    }
                }
            }
            
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let footer = footer, !footer.isEmpty {
                Text(footer)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.gray.opacity(0.3) : Color(hex: "E2E8F0"), lineWidth: 1)
        )
    }
}

struct DeltaBadge: View {
    let title: String
    let value: Double
    
    private var formattedValue: String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", value))%"
    }
    
    private var color: Color {
        if value > 5 { return .green }
        if value < -5 { return .red }
        return .yellow
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .bold()
            Text(formattedValue)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
    }
}

struct RecentDayCard: View {
    let stat: ConsuntivoView.DailyStats
    @Environment(\.colorScheme) private var colorScheme
    
    private var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: stat.date).capitalized
    }
    
    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: stat.date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(dayNumber)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stat.sentReports)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(StatoManager.StatoSinistro.attoInviato.color)
                    Text("Atti")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stat.closures)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(StatoManager.StatoSinistro.chiusa.color)
                    Text("Chius.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stat.totalUnique)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                    Text("Tot.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.04), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colorScheme == .dark ? Color.gray.opacity(0.3) : Color(hex: "E2E8F0"), lineWidth: 1)
        )
    }
}

struct CurrentMonthSummaryView: View {
    let closedClaims: [Sinistro]
    let sentReports: Int
    let returnedReports: Int
    let isCurrentMonth: Bool
    let monthCompletionPercentage: Double
    let todayClosures: Int
    let todaySentReports: Int
    let todayTotalUnique: Int
    let todayProjection: Int
    let plannedToday: Int
    let todayMinorTasks: Int
    let weeklyClosures: Int
    let weeklyProjection: Int
    let monthlyProjection: Int
    let weekDelta: Double
    let momDelta: Double
    let yoyDelta: Double
    let todayHours: Double
    let remainingWeekHours: Double
    let remainingMonthHours: Double
    let recentDaysStats: [ConsuntivoView.DailyStats]
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var workSchedule: WorkScheduleManager  // Aggiunto per accedere all'obiettivo
    @StateObject private var statoManager = StatoManager.shared
    
    private var monthlyTarget: Int {
        workSchedule.getMonthlyTarget(for: closedClaims.first?.dataChiusura ?? Date())
    }
    
    private var targetProgress: Double {
        guard monthlyTarget > 0 else { return 0 }
        return min(Double(closedClaims.count) / Double(monthlyTarget) * 100, 100)
    }
    
    // Previsione lineare: obiettivo / giorni totali * giorni passati (incluso oggi)
    private var linearProjectedToday: Int {
        let calendar = Calendar.current
        let today = Date()
        guard let startOfMonth = calendar.dateInterval(of: .month, for: today)?.start else { return 0 }
        
        let totalDaysInMonth = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
        // Giorni passati dal primo del mese fino ad oggi (incluso oggi)
        let daysPassed = calendar.dateComponents([.day], from: startOfMonth, to: today).day ?? 0
        let daysPassedIncludingToday = daysPassed + 1 // +1 per includere oggi
        
        guard totalDaysInMonth > 0 else { return 0 }
        return Int(round(Double(monthlyTarget) * Double(daysPassedIncludingToday) / Double(totalDaysInMonth)))
    }
    
    private var projectedProgress: Double {
        guard monthlyTarget > 0 else { return 0 }
        return min(Double(linearProjectedToday) / Double(monthlyTarget) * 100, 100)
    }
    
    private var targetProgressColor: Color {
        if targetProgress >= 100 {
            return .green
        } else if targetProgress >= 90 {
            return .green.opacity(0.7)
        } else if targetProgress >= 70 {
            return .yellow
        } else {
            return .red
        }
    }
    
    private var overTenBeningsCount: Int {
        closedClaims.filter { $0.oltreDieciBeni }.count
    }
    
    private var thresholdClaimsCount: Int {
        closedClaims.filter { sinistro in
            guard let importo = sinistro.liquidato?.doubleValue else { return false }
            return importo >= 10000  // Consideriamo qualsiasi soglia sopra 10K
        }.count
    }
    
    private var productivityPerHour: Double {
        let hours = workSchedule.calculateWorkedHoursUpToNow(in: Date())
        guard hours > 0 else { return 0 }
        return Double(closedClaims.count) / hours
    }
    
    var body: some View {
        GroupBox {
            VStack(spacing: 16) {
                if isCurrentMonth {
                    // Progress bar del mese
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Completamento mese")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(monthCompletionPercentage))%")
                                .font(.caption)
                                .bold()
                                .foregroundColor(.orange)
                        }
                        
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.orange.opacity(0.2))
                                    .frame(width: geometry.size.width, height: 8)
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.orange)
                                    .frame(width: geometry.size.width * monthCompletionPercentage / 100, height: 8)
                            }
                        }
                        .frame(height: 8)
                    }
                    
                    // Progress bar dell'obiettivo con previsto
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Progresso obiettivo (\(monthlyTarget) pratiche)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            HStack(spacing: 12) {
                                Text("Previsto: \(linearProjectedToday)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Effettivo: \(closedClaims.count)")
                                    .font(.caption)
                                    .bold()
                                Text("\(Int(targetProgress))%")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(targetProgressColor)
                            }
                        }
                        
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(targetProgressColor.opacity(0.2))
                                    .frame(width: geometry.size.width, height: 10)
                                
                                let projectedWidth = geometry.size.width * min(projectedProgress, 100) / 100
                                let actualWidth = geometry.size.width * min(targetProgress, 100) / 100
                                
                                // Barra prevista (più chiara, dietro)
                                if projectedProgress > 0 {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(targetProgressColor.opacity(0.4))
                                        .frame(width: projectedWidth, height: 10)
                                }
                                
                                // Barra effettiva
                                if targetProgress <= projectedProgress {
                                    // Se effettivo <= previsto, mostra solo la parte effettiva
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(targetProgressColor)
                                        .frame(width: actualWidth, height: 10)
                                } else {
                                    // Se effettivo > previsto, mostra prima la parte fino al previsto, poi la parte extra in verde
                                    if projectedProgress > 0 {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(targetProgressColor)
                                            .frame(width: projectedWidth, height: 10)
                                    }
                                    // Parte extra oltre la previsione
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.green.opacity(0.7))
                                        .frame(width: actualWidth - projectedWidth, height: 10)
                                        .offset(x: projectedWidth)
                                }
                            }
                        }
                        .frame(height: 10)
                    }
                    
                    Divider()
                    
                    // Statistiche giornata odierna
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Giornata Odierna")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Atti Inviati")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(todaySentReports)")
                                    .font(.title2)
                                    .bold()
                                    .foregroundColor(StatoManager.StatoSinistro.attoInviato.color)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Chiusure")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(todayClosures)")
                                    .font(.title2)
                                    .bold()
                                    .foregroundColor(StatoManager.StatoSinistro.chiusa.color)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Totale")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(todayTotalUnique)")
                                    .font(.title2)
                                    .bold()
                                    .foregroundColor(.blue)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color(hex: "F7FAFC"))
                        )
                    }
                    
                    // Statistiche ultimi giorni
                    if !recentDaysStats.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Ultimi Giorni")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            // Layout adattivo: mostra fino a 5 giorni
                            HStack(spacing: 12) {
                                ForEach(recentDaysStats.indices, id: \.self) { index in
                                    RecentDayCard(stat: recentDaysStats[index])
                                }
                                Spacer()
                            }
                        }
                    }
                    
                    Divider()
                }
                
                // Statistiche principali
                AdaptiveTileRow(spacing: 12) {
                    StatView(
                        title: "Sinistri Chiusi",
                        value: closedClaims.count,
                        icon: StatoManager.StatoSinistro.chiusa.icon,
                        color: StatoManager.StatoSinistro.chiusa.color
                    )
                    
                    StatView(
                        title: "Atti Inviati",
                        value: sentReports,
                        icon: StatoManager.StatoSinistro.attoInviato.icon,
                        color: StatoManager.StatoSinistro.attoInviato.color
                    )
                    
                    StatView(
                        title: "Atti Restituiti",
                        value: returnedReports,
                        icon: StatoManager.StatoSinistro.attoRicevutoSottoscritto.icon,
                        color: StatoManager.StatoSinistro.attoRicevutoSottoscritto.color
                    )
                    
                    StatView(
                        title: "Oltre 10 Beni",
                        value: overTenBeningsCount,
                        icon: "list.bullet.clipboard.fill",
                        color: .indigo
                    )
                    
                    StatView(
                        title: "Sinistri Complessi",
                        value: thresholdClaimsCount,
                        icon: "chart.line.uptrend.xyaxis.circle.fill",
                        color: .teal
                    )
                }
            }
            .padding()
        }
        .background(colorScheme == .dark ? Color(NSColor.windowBackgroundColor) : .white)
    }
}

struct StatView: View {
    let title: String
    let value: Any
    let icon: String
    let color: Color
    
    private var displayValue: String {
        if let intValue = value as? Int {
            return "\(intValue)"
        }
        if let stringValue = value as? String {
            return stringValue
        }
        return ""
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
        .frame(minWidth: 120)
    }
}

struct ClosuresProjectionView: View {
    let currentClosures: Int
    let dailyAverage: Double
    let projectedClosures: Int
    let workingHours: Double
    let isCurrentMonth: Bool
    let monthCompletionPercentage: Double
    let previousMonthComparison: (closures: Int, percentage: Double)?
    let historicalDailyAverage: Double
    let monthlyTarget: Int
    let selectedMonth: Date
    @EnvironmentObject private var workSchedule: WorkScheduleManager
    @StateObject private var statoManager = StatoManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var requiredDaily: Double {
        if currentClosures >= monthlyTarget {
            return -1  // Valore speciale per indicare obiettivo raggiunto
        }
        return workSchedule.requiredDailyClosures(target: monthlyTarget, currentCount: currentClosures, from: Date(), in: selectedMonth)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Proiezione Chiusure")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            // Statistiche in una griglia uniforme
            HStack(spacing: 40) {
                // Media giornaliera
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(getDailyAverageColor(dailyAverage))
                            .font(.caption)
                        Text("Media giornaliera")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(String(format: "%.1f", dailyAverage))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .help("Media giornaliera:\n≥ 10: ottimo\n≥ 5: nella norma\n< 5: critico")
                
                // Ore lavorate
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("Ore lavorate")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("\(Int(workingHours))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .help("Totale delle ore lavorative programmate per questo mese, basato sul calendario di lavoro impostato.")
            }
            
            Divider()
            
            // Statistiche attuali e proiezione
            HStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: StatoManager.StatoSinistro.chiusa.icon)
                            .foregroundColor(StatoManager.StatoSinistro.chiusa.color)
                            .font(.caption)
                        Text("Chiusure attuali")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("\(currentClosures)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    // Confronto con mese precedente
                    if let comparison = previousMonthComparison {
                        HStack(spacing: 4) {
                            Image(systemName: comparison.percentage > 0 ? "arrow.up" : "arrow.down")
                                .font(.caption2)
                                .foregroundColor(comparison.percentage > 0 ? .green : .red)
                            Text("\(abs(Int(comparison.percentage)))% vs mese prec. (\(comparison.closures))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .help("Numero totale di sinistri chiusi nel mese corrente. Il confronto percentuale è calcolato rispetto allo stesso punto del mese precedente.")
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("Proiezione")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("\(projectedClosures)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .help("Stima del numero totale di chiusure previste per fine mese, basata sulla media giornaliera attuale e i giorni lavorativi rimanenti.")
                
                // Richiesto giornaliero
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .foregroundColor(requiredDaily < 0 ? .green : ColorUtils.getRequiredClosuresColor(requiredDaily, historicalAverage: historicalDailyAverage))
                            .font(.caption)
                        Text("Al giorno per obiettivo")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(requiredDaily < 0 ? "Obiettivo raggiunto" : String(format: "%.1f", requiredDaily))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .help("Pratiche giornaliere necessarie per raggiungere l'obiettivo\nMedia storica: \(String(format: "%.1f", historicalDailyAverage))\nVerde: Sotto la media storica\nGiallo: Fino al 30% sopra la media\nRosso: Oltre il 30% sopra la media")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.gray.opacity(0.3) : Color(hex: "E2E8F0"), lineWidth: 1)
        )
    }
}

struct MonthlyStatsView: View {
    let closedClaims: [Sinistro]
    let sentReports: [Sinistro]
    let returnedReports: [Sinistro]
    let workingHours: Double
    let selectedMonth: Date
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var workSchedule: WorkScheduleManager
    @StateObject private var statoManager = StatoManager.shared
    
    private var averageHoursPerClaim: Double {
        guard closedClaims.count > 0 else { return 0 }
        return workingHours / Double(closedClaims.count)
    }
    
    private var overTenBeningsCount: Int {
        closedClaims.filter { $0.oltreDieciBeni }.count
    }
    
    private var thresholdClaimsCount: Int {
        closedClaims.filter { sinistro in
            guard let dannoAccertato = sinistro.dannoAccertato?.doubleValue else { return false }
            return dannoAccertato >= 10000
        }.count
    }
    
    var body: some View {
        GroupBox {
            VStack(spacing: 24) {
                // Statistiche principali
                HStack(spacing: 40) {
                    StatView(
                        title: "Sinistri Chiusi",
                        value: closedClaims.count,
                        icon: StatoManager.StatoSinistro.chiusa.icon,
                        color: StatoManager.StatoSinistro.chiusa.color
                    )
                    
                    StatView(
                        title: "Atti Inviati",
                        value: sentReports.count,
                        icon: StatoManager.StatoSinistro.attoInviato.icon,
                        color: StatoManager.StatoSinistro.attoInviato.color
                    )
                    
                    StatView(
                        title: "Atti Restituiti",
                        value: returnedReports.count,
                        icon: StatoManager.StatoSinistro.attoRicevutoSottoscritto.icon,
                        color: StatoManager.StatoSinistro.attoRicevutoSottoscritto.color
                    )
                }
                
                Divider()
                
                // Medie ed efficienza
                HStack(spacing: 40) {
                    StatView(
                        title: "Media Giornaliera",
                        value: String(format: "%.1f", Double(closedClaims.count) / 22),
                        icon: "chart.bar.fill",
                        color: ColorUtils.getDailyAverageColor(Double(closedClaims.count) / 22)
                    )
                    .help("Media giornaliera:\n≥ 10: ottimo\n≥ 5: nella norma\n< 5: critico")
                    
                    StatView(
                        title: "Ore per Sinistro",
                        value: String(format: "%.1f", averageHoursPerClaim),
                        icon: "clock.fill",
                        color: ColorUtils.getHoursPerClaimColor(averageHoursPerClaim)
                    )
                    .help("Media ore lavorate per sinistro:\n≤ 1 ora: ottimo\n≤ 2 ore: nella norma\n> 2 ore: critico")
                }
                
                Divider()
                
                // Dettaglio tipologie
                HStack(spacing: 40) {
                    StatView(
                        title: "Oltre 10 Beni",
                        value: overTenBeningsCount,
                        icon: "list.bullet.clipboard.fill",
                        color: .indigo
                    )
                    .help("Numero di sinistri chiusi con più di 10 beni")
                    
                    StatView(
                        title: "Sinistri Complessi",
                        value: thresholdClaimsCount,
                        icon: "chart.line.uptrend.xyaxis.circle.fill",
                        color: .teal
                    )
                    .help("Numero di sinistri chiusi con danno accertato superiore a 10.000€")
                }
            }
            .padding()
        }
        .background(colorScheme == .dark ? Color(NSColor.windowBackgroundColor) : .white)
    }
}

struct TotalProjectionView: View {
    let currentClosures: Int
    let sentReports: Int
    let dailyAverage: Double
    let projectedTotal: Int
    let workingHours: Double
    let historicalDailyAverage: Double
    let monthlyTarget: Int
    let selectedMonth: Date
    @EnvironmentObject private var workSchedule: WorkScheduleManager
    @StateObject private var statoManager = StatoManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var requiredDaily: Double {
        if currentClosures + sentReports >= monthlyTarget {
            return -1  // Valore speciale per indicare obiettivo raggiunto
        }
        return workSchedule.requiredDailyClosures(target: monthlyTarget, currentCount: currentClosures + sentReports, from: Date(), in: selectedMonth)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Proiezione Totale")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            // Statistiche in una griglia uniforme
            HStack(spacing: 40) {
                // Media giornaliera
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: StatoManager.StatoSinistro.attoInviato.icon)
                            .foregroundColor(ColorUtils.getDailyAverageColor(dailyAverage))
                            .font(.caption)
                        Text("Media giornaliera")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(String(format: "%.1f", dailyAverage))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .help("Media giornaliera:\n≥ 10: ottimo\n≥ 5: nella norma\n< 5: critico")
                
                // Ore lavorate
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("Ore lavorate")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("\(Int(workingHours))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .help("Totale delle ore lavorative programmate per questo mese, basato sul calendario di lavoro impostato.")
            }
            
            Divider()
            
            // Statistiche attuali e proiezione
            HStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: StatoManager.StatoSinistro.attoInviato.icon)
                            .foregroundColor(StatoManager.StatoSinistro.attoInviato.color)
                            .font(.caption)
                        Text("Pratiche attuali")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("\(currentClosures + sentReports)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 4) {
                        Text("\(currentClosures) chiusi")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                        Text("•")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                        Text("\(sentReports) inviati")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("Proiezione")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("\(projectedTotal)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .help("Stima del numero totale di pratiche previste per fine mese, basata sulla media giornaliera attuale e i giorni lavorativi rimanenti.")
                
                // Al giorno per obiettivo
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .foregroundColor(requiredDaily < 0 ? .green : ColorUtils.getRequiredClosuresColor(requiredDaily, historicalAverage: historicalDailyAverage))
                            .font(.caption)
                        Text("Al giorno per obiettivo")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(requiredDaily < 0 ? "Obiettivo raggiunto" : String(format: "%.1f", requiredDaily))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .help("Pratiche giornaliere necessarie per raggiungere l'obiettivo\nMedia storica: \(String(format: "%.1f", historicalDailyAverage))\nVerde: Sotto la media storica\nGiallo: Fino al 30% sopra la media\nRosso: Oltre il 30% sopra la media")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.gray.opacity(0.3) : Color(hex: "E2E8F0"), lineWidth: 1)
        )
    }
}

struct DailyChartView: View {
    let closedClaims: [Sinistro]
    let sentReports: [Sinistro]
    let assignedClaims: [Sinistro]
    let selectedMonth: Date
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var workSchedule = WorkScheduleManager.shared
    @State private var selectedDate: Date?
    @State private var selectedStats: DailyStat?
    
    private let assignmentColor = Color.blue
    
    private var dailyStats: [DailyStat] {
        let calendar = Calendar.current
        let startOfMonth = calendar.startOfMonth(for: selectedMonth)
        let endOfMonth = calendar.endOfMonth(for: selectedMonth)
        
        var stats: [DailyStat] = []
        var currentDate = startOfMonth
        
        while currentDate <= endOfMonth {
            let dayClosures = closedClaims.filter {
                calendar.isDate($0.dataChiusura ?? Date(), inSameDayAs: currentDate)
            }.count
            
            let dayReports = sentReports.filter {
                calendar.isDate($0.dataInvioAtto ?? Date(), inSameDayAs: currentDate)
            }.count
            
            let dayAssignments = assignedClaims.filter {
                calendar.isDate($0.dataAssegnazione ?? Date(), inSameDayAs: currentDate)
            }.count
            
            let isWorking = workSchedule.isWorkingDay(currentDate)
            
            stats.append(DailyStat(
                date: currentDate,
                closures: dayClosures,
                reports: dayReports,
                assignments: dayAssignments,
                isWorkingDay: isWorking
            ))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return stats
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Andamento Giornaliero")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Legenda
                HStack(spacing: 16) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(assignmentColor)
                            .frame(width: 8, height: 8)
                        Text("Assegnazioni")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 5) {
                        Circle()
                            .fill(StatoManager.StatoSinistro.chiusa.color)
                            .frame(width: 8, height: 8)
                        Text("Chiusure")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 5) {
                        Circle()
                            .fill(StatoManager.StatoSinistro.attoInviato.color)
                            .frame(width: 8, height: 8)
                        Text("Atti")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.red.opacity(0.3))
                            .frame(width: 2, height: 12)
                        Text("Non lavorativo")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Info hover
            VStack(alignment: .leading) {
                if let selectedStats = selectedStats {
                    HStack {
                        Text(DateUtils.formatDate(selectedStats.date))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        if !selectedStats.isWorkingDay {
                            Text("(non lavorativo)")
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.7))
                        }
                    }
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(assignmentColor)
                                .frame(width: 6, height: 6)
                            Text("Assegnazioni: \(selectedStats.assignments)")
                                .foregroundColor(assignmentColor)
                        }
                        HStack(spacing: 4) {
                            Circle()
                                .fill(StatoManager.StatoSinistro.chiusa.color)
                                .frame(width: 6, height: 6)
                            Text("Chiusure: \(selectedStats.closures)")
                                .foregroundColor(StatoManager.StatoSinistro.chiusa.color)
                        }
                        HStack(spacing: 4) {
                            Circle()
                                .fill(StatoManager.StatoSinistro.attoInviato.color)
                                .frame(width: 6, height: 6)
                            Text("Atti: \(selectedStats.reports)")
                                .foregroundColor(StatoManager.StatoSinistro.attoInviato.color)
                        }
                    }
                    .font(.caption)
                }
            }
            .frame(height: 45)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color(hex: "F7FAFC"))
            )
            
            Chart {
                ForEach(dailyStats, id: \.date) { stat in
                    let chiusureColor = StatoManager.StatoSinistro.chiusa.color
                    let attiColor = StatoManager.StatoSinistro.attoInviato.color
                    
                    // Evidenzia giorni non lavorativi con una RectangleMark sottile
                    if !stat.isWorkingDay {
                        RuleMark(x: .value("Non lavorativo", stat.date))
                            .foregroundStyle(Color.red.opacity(0.15))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                    
                    // Area sotto le linee - Assegnazioni
                    AreaMark(
                        x: .value("Data", stat.date),
                        y: .value("Assegnazioni", stat.assignments)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [assignmentColor.opacity(0.15), assignmentColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Area sotto le linee - Chiusure
                    AreaMark(
                        x: .value("Data", stat.date),
                        y: .value("Chiusure", stat.closures)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [chiusureColor.opacity(0.15), chiusureColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Area sotto le linee - Atti
                    AreaMark(
                        x: .value("Data", stat.date),
                        y: .value("Atti", stat.reports)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [attiColor.opacity(0.15), attiColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Linea Assegnazioni
                    LineMark(
                        x: .value("Data", stat.date),
                        y: .value("Assegnazioni", stat.assignments)
                    )
                    .foregroundStyle(assignmentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .symbol {
                        Circle()
                            .fill(assignmentColor)
                            .frame(width: 5, height: 5)
                    }
                    
                    // Linea Chiusure
                    LineMark(
                        x: .value("Data", stat.date),
                        y: .value("Chiusure", stat.closures)
                    )
                    .foregroundStyle(chiusureColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .symbol {
                        Circle()
                            .fill(chiusureColor)
                            .frame(width: 5, height: 5)
                    }
                    
                    // Linea Atti
                    LineMark(
                        x: .value("Data", stat.date),
                        y: .value("Atti", stat.reports)
                    )
                    .foregroundStyle(attiColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .symbol {
                        Circle()
                            .fill(attiColor)
                            .frame(width: 5, height: 5)
                    }
                    
                    // Linea di selezione
                    if let selectedDate = selectedDate,
                       Calendar.current.isDate(stat.date, inSameDayAs: selectedDate) {
                        RuleMark(x: .value("Selected", stat.date))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
            }
            .frame(height: 260)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = value.location.x - geometry[proxy.plotAreaFrame].origin.x
                                    guard let date = proxy.value(atX: x, as: Date.self) else { return }
                                    
                                    selectedDate = date
                                    selectedStats = dailyStats.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
                                }
                                .onEnded { _ in
                                    selectedDate = nil
                                    selectedStats = nil
                                }
                        )
                }
            }
        }
    }
}

struct ComparisonChartView: View {
    let closedClaims: [Sinistro]
    let sentReports: [Sinistro]
    let assignedClaims: [Sinistro]
    let previousMonthClaims: [Sinistro]
    let previousMonthReports: [Sinistro]
    let previousMonthAssignments: [Sinistro]
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var statoManager = StatoManager.shared
    
    private let assignmentColor = Color.blue
    
    // Struttura per i dati del grafico a barre raggruppate
    private struct ComparisonData: Identifiable {
        let id = UUID()
        let category: String
        let period: String
        let value: Int
        let color: Color
    }
    
    private var chartData: [ComparisonData] {
        let chiusureColor = StatoManager.StatoSinistro.chiusa.color
        let attiColor = StatoManager.StatoSinistro.attoInviato.color
        let grayColor = Color.gray.opacity(0.4)
        
        return [
            // Assegnazioni
            ComparisonData(category: "Assegnazioni", period: "Precedente", value: previousMonthAssignments.count, color: grayColor),
            ComparisonData(category: "Assegnazioni", period: "Corrente", value: assignedClaims.count, color: assignmentColor),
            // Chiusure
            ComparisonData(category: "Chiusure", period: "Precedente", value: previousMonthClaims.count, color: grayColor),
            ComparisonData(category: "Chiusure", period: "Corrente", value: closedClaims.count, color: chiusureColor),
            // Atti
            ComparisonData(category: "Atti", period: "Precedente", value: previousMonthReports.count, color: grayColor),
            ComparisonData(category: "Atti", period: "Corrente", value: sentReports.count, color: attiColor)
        ]
    }
    
    private func variationText(current: Int, previous: Int) -> (text: String, color: Color) {
        guard previous > 0 else {
            return current > 0 ? ("+\(current)", .green) : ("=", .secondary)
        }
        let diff = current - previous
        let percentage = Double(diff) / Double(previous) * 100
        if diff > 0 {
            return ("+\(diff) (\(String(format: "%.0f", percentage))%)", .green)
        } else if diff < 0 {
            return ("\(diff) (\(String(format: "%.0f", percentage))%)", .red)
        } else {
            return ("=", .secondary)
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Confronto con Mese Precedente")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Legenda
                HStack(spacing: 16) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.gray.opacity(0.4))
                            .frame(width: 16, height: 8)
                        Text("Precedente")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [assignmentColor, StatoManager.StatoSinistro.chiusa.color, StatoManager.StatoSinistro.attoInviato.color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 16, height: 8)
                        Text("Corrente")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Riepilogo variazioni
            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text("Assegnazioni")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    let variation = variationText(current: assignedClaims.count, previous: previousMonthAssignments.count)
                    Text(variation.text)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(variation.color)
                }
                
                VStack(spacing: 2) {
                    Text("Chiusure")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    let variation = variationText(current: closedClaims.count, previous: previousMonthClaims.count)
                    Text(variation.text)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(variation.color)
                }
                
                VStack(spacing: 2) {
                    Text("Atti")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    let variation = variationText(current: sentReports.count, previous: previousMonthReports.count)
                    Text(variation.text)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(variation.color)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color(hex: "F7FAFC"))
            )
            
            Chart(chartData) { item in
                BarMark(
                    x: .value("Categoria", item.category),
                    y: .value("Valore", item.value)
                )
                .foregroundStyle(item.color.gradient)
                .cornerRadius(4)
                .position(by: .value("Periodo", item.period))
                .annotation(position: .top, alignment: .center, spacing: 2) {
                    if item.value > 0 {
                        Text("\(item.value)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 240)
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct LiquidationDetailsView: View {
    let stats: [LiquidationStats]
    let previousMonthStats: [LiquidationStats]
    let statsByCompany: [LiquidationStats]
    let companyDetailsForGroups: [String: [(company: String, count: Int)]]
    let hasMultipleCompaniesInGroup: (LiquidationStats) -> Bool
    let isGroupUnited: (LiquidationStats) -> Bool
    let toggleGroupUnion: (LiquidationStats) -> Void
    let getGroupKey: (LiquidationStats) -> String
    let onOpenSinistro: (Sinistro) -> Void
    @Binding var soloCompetenza: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var hoveredCompany: String? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Statistiche Liquidazione")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            // Statistiche per compagnia/gruppo in griglia
            if stats.isEmpty {
                Text("Nessun dato disponibile")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if stats.count == 1 {
                // Una sola compagnia: riga intera
                CompanyLiquidationCard(
                    stat: stats[0],
                    previousStat: previousMonthStats.first(where: { $0.company == stats[0].company }),
                    isFullWidth: true,
                    companyDetails: getCompanyDetails(for: stats[0]),
                    hasMultipleCompanies: hasMultipleCompaniesInGroup(stats[0]),
                    isUnited: isGroupUnited(stats[0]),
                    onToggleUnion: { toggleGroupUnion(stats[0]) },
                    onOpenSinistro: onOpenSinistro
                )
            } else {
                // Più compagnie: griglia a 2 colonne
                let pairedStats = Array(stats.prefix(stats.count % 2 == 0 ? stats.count : stats.count - 1))
                let lastStat = stats.count % 2 != 0 ? stats.last : nil
                
                VStack(spacing: 16) {
                    // Griglia per le compagnie pari
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(pairedStats, id: \.company) { stat in
                            CompanyLiquidationCard(
                                stat: stat,
                                previousStat: previousMonthStats.first(where: { $0.company == stat.company }),
                                isFullWidth: false,
                                companyDetails: getCompanyDetails(for: stat),
                                hasMultipleCompanies: hasMultipleCompaniesInGroup(stat),
                                isUnited: isGroupUnited(stat),
                                onToggleUnion: { toggleGroupUnion(stat) },
                                onOpenSinistro: onOpenSinistro
                            )
                            .onHover { hovering in
                                hoveredCompany = hovering ? stat.company : nil
                            }
                        }
                    }
                    
                    // Ultima compagnia dispari in riga intera
                    if let last = lastStat {
                        CompanyLiquidationCard(
                            stat: last,
                            previousStat: previousMonthStats.first(where: { $0.company == last.company }),
                            isFullWidth: true,
                            companyDetails: getCompanyDetails(for: last),
                            hasMultipleCompanies: hasMultipleCompaniesInGroup(last),
                            isUnited: isGroupUnited(last),
                            onToggleUnion: { toggleGroupUnion(last) },
                            onOpenSinistro: onOpenSinistro
                        )
                        .onHover { hovering in
                            hoveredCompany = hovering ? last.company : nil
                        }
                    }
                }
            }
        }
        .contextMenu {
            Button(action: {
                soloCompetenza = false
            }) {
                Label("Tutti i sinistri", systemImage: soloCompetenza ? "circle" : "checkmark.circle.fill")
            }
            
            Button(action: {
                soloCompetenza = true
            }) {
                Label("Solo competenza", systemImage: soloCompetenza ? "checkmark.circle.fill" : "circle")
            }
            
            // Opzioni per unire/separare i gruppi
            let groupsWithMultipleCompanies = getGroupsWithMultipleCompanies()
            if !groupsWithMultipleCompanies.isEmpty {
                Divider()
                
                ForEach(groupsWithMultipleCompanies) { groupInfo in
                    Button(action: {
                        // Trova la prima stat di questo gruppo e toggle
                        if let firstStat = stats.first(where: { getGroupKey($0) == groupInfo.groupKey }) {
                            toggleGroupUnion(firstStat)
                        }
                    }) {
                        Label(
                            groupInfo.isUnited ? "Separa \(groupInfo.groupName)" : "Unisci \(groupInfo.groupName)",
                            systemImage: groupInfo.isUnited ? "rectangle.stack.badge.minus" : "rectangle.stack.badge.plus"
                        )
                    }
                }
            }
        }
    }
    
    private func getCompanyDetails(for stat: LiquidationStats) -> [(company: String, count: Int)]? {
        let groupKey = getGroupKey(stat)
        return companyDetailsForGroups[groupKey]
    }
    
    /// Struttura per le informazioni sui gruppi
    private struct GroupInfo: Identifiable {
        let id: String
        let groupKey: String
        let groupName: String
        let isUnited: Bool
    }
    
    /// Trova tutti i gruppi che hanno più compagnie
    private func getGroupsWithMultipleCompanies() -> [GroupInfo] {
        var groupsInfo: [String: (groupName: String, isUnited: Bool)] = [:]
        
        for stat in stats {
            if hasMultipleCompaniesInGroup(stat) {
                let groupKey = getGroupKey(stat)
                if groupsInfo[groupKey] == nil {
                    // Estrai il nome del gruppo dal nome della stat o dal gruppo
                    let compagnia = Compagnia.from(nomeCompagnia: stat.company)
                    let gruppoEnum = compagnia.gruppo
                    let groupName = gruppoEnum.rawValue
                    
                    groupsInfo[groupKey] = (groupName: groupName, isUnited: isGroupUnited(stat))
                }
            }
        }
        
        return groupsInfo.map { 
            GroupInfo(id: $0.key, groupKey: $0.key, groupName: $0.value.groupName, isUnited: $0.value.isUnited)
        }.sorted { $0.groupName < $1.groupName }
    }
    
    /// Determina la compagnia o il gruppo dal nome
    private func getTarget(for companyName: String) -> (liquidato: Double, negative: Double) {
        let settings = CompagniaSettingsService.shared
        // Cerca prima per compagnia
        let compagnia = Compagnia.from(nomeCompagnia: companyName)
        if compagnia != .unknown {
            return (settings.effectiveTargetLiquidatoMedio(compagnia), settings.effectiveTargetNegative(compagnia))
        }
        
        // Se non trovata, cerca per gruppo
        let gruppo = GruppoAssicurativo.from(nomeGruppo: companyName)
        if let prima = gruppo.compagnie.first {
            return (settings.effectiveTargetLiquidatoMedio(prima), settings.effectiveTargetNegative(prima))
        }
        return (gruppo.targetLiquidatoMedio, gruppo.targetNegative)
    }
    
    /// Calcola il colore per la media liquidato in base al target
    private func getAverageColor(_ stat: LiquidationStats, isInPL: Bool) -> Color {
        let value = isInPL ? stat.averageUnder10kInPL : stat.averageUnder10kAll
        let target = getTarget(for: stat.company).liquidato
        
        // Verde: sotto del 10% rispetto al target (< target * 0.9)
        if value < target * 0.9 {
            return .green
        }
        // Giallo: forbice ±10% dal target (target * 0.9 <= valore <= target * 1.1)
        else if value >= target * 0.9 && value <= target * 1.1 {
            return .yellow
        }
        // Rosso: oltre il target * 1.1
        else {
            return .red
        }
    }
    
    /// Calcola il colore per la percentuale di negative in base al target
    private func getNegativeColor(_ stat: LiquidationStats) -> Color {
        let value = stat.negativePercentage
        let target = getTarget(for: stat.company).negative
        
        // Rosso: più basse del 20% del target (< target * 0.8)
        if value < target * 0.8 {
            return .red
        }
        // Giallo: nel 20% sotto (target * 0.8 <= valore < target)
        else if value >= target * 0.8 && value < target {
            return .yellow
        }
        // Verde: dal target fino al 25% in più (target <= valore <= target * 1.25)
        else if value >= target && value <= target * 1.25 {
            return .green
        }
        // Giallo: oltre il 25% ma non oltre il 50% (target * 1.25 < valore <= target * 1.5)
        else if value > target * 1.25 && value <= target * 1.5 {
            return .yellow
        }
        // Rosso: oltre il 50% in più (> target * 1.5)
        else {
            return .red
        }
    }
}

// MARK: - Company Liquidation Card
struct CompanyLiquidationCard: View {
    let stat: LiquidationStats
    let previousStat: LiquidationStats?
    let isFullWidth: Bool
    let companyDetails: [(company: String, count: Int)]?
    let hasMultipleCompanies: Bool
    let isUnited: Bool
    let onToggleUnion: () -> Void
    let onOpenSinistro: (Sinistro) -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header con nome compagnia/gruppo
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: isUnited ? "building.2.crop.circle.fill" : "building.2.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                    
                    Text(stat.company)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    // Icona per unire/separare (solo se ci sono più compagnie nel gruppo)
                    if hasMultipleCompanies {
                        Button(action: onToggleUnion) {
                            Image(systemName: isUnited ? "rectangle.stack.badge.minus" : "rectangle.stack.badge.plus")
                                .font(.caption)
                                .foregroundColor(isUnited ? .blue : .secondary)
                                .padding(4)
                                .background(
                                    Circle()
                                        .fill(isUnited ? .blue.opacity(0.1) : Color.gray.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                        .help(isUnited ? "Separa le compagnie" : "Unisci in gruppo")
                    }
                    
                    Spacer()
                    
                    // Numero sinistri (mostrato sempre, più grande su hover)
                    Text("\(stat.totalClaims) sinistri")
                        .font(isHovered ? .subheadline : .caption)
                        .fontWeight(isHovered ? .semibold : .regular)
                        .foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.2), value: isHovered)
                        .help("Numero esatto: \(stat.totalClaims) sinistri")
                }
                
                // Dettagli delle compagnie quando unite
                if isUnited, let details = companyDetails, !details.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(details, id: \.company) { detail in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.blue.opacity(0.3))
                                    .frame(width: 4, height: 4)
                                Text("\(detail.company): \(detail.count) sinistri")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.leading, 32)
                }
            }
            
            // I quattro valori in una riga
            HStack(spacing: 20) {
                // Entro 5k (PL)
                CompactStatView(
                    label: "Entro 5k",
                    value: stat.averageUnder10kInPL,
                    color: getAverageColor(stat, isInPL: true),
                    previousValue: previousStat?.averageUnder10kInPL,
                    icon: "eurosign.circle.fill",
                    sinistriSenzaLiquidazione: stat.sinistriSenzaLiquidazione,
                    onOpenSinistro: { riferimento in
                        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
                        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
                        if let sinistro = try? viewContext.fetch(request).first {
                            onOpenSinistro(sinistro)
                        }
                    },
                    higherIsBetter: false,  // Più basso è meglio
                    company: stat.company
                )
                
                // Concordate
                CompactStatView(
                    label: "Concordate",
                    value: stat.concordatePercentage,
                    color: getConcordateColor(stat),
                    previousValue: previousStat?.concordatePercentage,
                    icon: "checkmark.seal.fill",
                    isPercentage: true,
                    sinistriSenzaDefinizione: stat.sinistriSenzaDefinizione,
                    onOpenSinistro: { riferimento in
                        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
                        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
                        if let sinistro = try? viewContext.fetch(request).first {
                            onOpenSinistro(sinistro)
                        }
                    },
                    higherIsBetter: true,  // Più alto è meglio
                    company: stat.company
                )
                
                // Negativi
                CompactStatView(
                    label: "Negativi",
                    value: stat.negativePercentage,
                    color: getNegativeColor(stat),
                    previousValue: previousStat?.negativePercentage,
                    icon: "xmark.circle.fill",
                    isPercentage: true,
                    higherIsBetter: true,  // Più alto è meglio
                    hasRange: true,  // Ha un range target (target a target*1.25)
                    company: stat.company
                )
                
                // Tempo gestione
                CompactStatView(
                    label: "Tempo gestione",
                    value: stat.averageGestioneDays,
                    color: getGestioneColor(stat),
                    previousValue: previousStat?.averageGestioneDays,
                    icon: "clock.fill",
                    isDays: true,
                    sinistriSenzaDataAssegnazione: stat.sinistriSenzaDataAssegnazione,
                    onOpenSinistro: { riferimento in
                        // Trova e apri il sinistro
                        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
                        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
                        if let sinistro = try? viewContext.fetch(request).first {
                            onOpenSinistro(sinistro)
                        }
                    },
                    higherIsBetter: false,  // Più basso è meglio
                    hasRange: true,  // Ha un range target (target*0.85 a target*1.15)
                    company: stat.company
                )
            }
        }
        .padding(20)
        .frame(maxWidth: isFullWidth ? .infinity : nil)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.gray.opacity(0.3) : Color(hex: "E2E8F0"), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func getAverageColor(_ stat: LiquidationStats, isInPL: Bool) -> Color {
        let target = CompagniaSettingsService.shared.effectiveTargetLiquidatoMedio(Compagnia.from(nomeCompagnia: stat.company))
        let value = isInPL ? stat.averageUnder10kInPL : stat.averageUnder10kAll
        
        if value < target * 0.9 {
            return .green
        } else if value >= target * 0.9 && value <= target * 1.1 {
            return .yellow
        } else {
            return .red
        }
    }
    
    private func getNegativeColor(_ stat: LiquidationStats) -> Color {
        let value = stat.negativePercentage
        let target = CompagniaSettingsService.shared.effectiveTargetNegative(Compagnia.from(nomeCompagnia: stat.company))
        
        if value < target * 0.8 {
            return .red
        } else if value >= target * 0.8 && value < target {
            return .yellow
        } else if value >= target && value <= target * 1.25 {
            return .green
        } else if value > target * 1.25 && value <= target * 1.5 {
            return .yellow
        } else {
            return .red
        }
    }
    
    private func getGestioneColor(_ stat: LiquidationStats) -> Color {
        let value = stat.averageGestioneDays
        let target = CompagniaSettingsService.shared.effectiveTargetTempoGestione(Compagnia.from(nomeCompagnia: stat.company))
        
        // Verde: entro ±15% del target (target * 0.85 <= valore <= target * 1.15)
        if value >= target * 0.85 && value <= target * 1.15 {
            return .green
        }
        // Giallo: oltre ±15% ma non oltre +15% aggiuntivo
        else if value < target * 0.85 || (value > target * 1.15 && value <= target * 1.30) {
            return .yellow
        }
        // Rosso: oltre +15% aggiuntivo (valore > target * 1.30)
        else {
            return .red
        }
    }
    
    private func getConcordateColor(_ stat: LiquidationStats) -> Color {
        let value = stat.concordatePercentage
        let compagnia = Compagnia.from(nomeCompagnia: stat.company)
        let target: Double
        if stat.company.starts(with: "Gruppo"), let prima = compagnia.gruppo.compagnie.first {
            target = CompagniaSettingsService.shared.effectiveTargetConcordate(prima)
        } else {
            target = CompagniaSettingsService.shared.effectiveTargetConcordate(compagnia)
        }
        
        // Verde: >= target (es. 85% o 90%)
        if value >= target {
            return .green
        }
        // Giallo: tra target-5% e target (margine 5%)
        else if value >= target - 5 {
            return .yellow
        }
        // Rosso: sotto target-5%
        else {
            return .red
        }
    }
}

// MARK: - Compact Stat View
struct CompactStatView: View {
    let label: String
    let value: Double
    let color: Color
    let previousValue: Double?
    let icon: String
    var isPercentage: Bool = false
    var isDays: Bool = false
    var sinistriSenzaDataAssegnazione: [String] = []
    var sinistriSenzaLiquidazione: [String] = []
    var sinistriSenzaDefinizione: [String] = []
    var onOpenSinistro: ((String) -> Void)?
    
    // Parametri per calcolo colore variazione
    var higherIsBetter: Bool = true  // true = più alto è meglio (es. concordate, negativi), false = più basso è meglio (es. liquidato, tempo)
    var hasRange: Bool = false  // true = ha un range target (deve stare tra min e max), false = ha solo un target singolo
    var target: Double? = nil  // Target per la metrica (o centro del range se hasRange = true)
    var targetMin: Double? = nil  // Minimo del range (solo se hasRange = true)
    var targetMax: Double? = nil  // Massimo del range (solo se hasRange = true)
    var company: String? = nil  // Nome compagnia per ottenere target se non fornito
    
    @State private var showMissingDataPopover = false
    @State private var tipoDatoMancante: MissingDataPopover.TipoDatoMancante = .dataAssegnazione
    
    private var missingDataInfo: (sinistri: [String], tipo: MissingDataPopover.TipoDatoMancante, helpText: String)? {
        if isDays && !sinistriSenzaDataAssegnazione.isEmpty {
            return (sinistriSenzaDataAssegnazione, .dataAssegnazione, "\(sinistriSenzaDataAssegnazione.count) sinistri senza data assegnazione")
        } else if !sinistriSenzaLiquidazione.isEmpty {
            return (sinistriSenzaLiquidazione, .liquidazione, "\(sinistriSenzaLiquidazione.count) sinistri senza importo liquidazione")
        } else if !sinistriSenzaDefinizione.isEmpty {
            return (sinistriSenzaDefinizione, .definizione, "\(sinistriSenzaDefinizione.count) sinistri senza definizione")
        }
        return nil
    }
    
    private var variation: (value: Double, isIncrease: Bool, isImprovement: Bool, angle: Double)? {
        guard let prev = previousValue, prev > 0 else { return nil }
        let diff = ((value - prev) / prev) * 100
        let isIncrease = diff > 0
        
        // Determina se è un miglioramento in base a higherIsBetter
        let isImprovement: Bool
        if higherIsBetter {
            isImprovement = isIncrease  // Aumento = miglioramento
        } else {
            isImprovement = !isIncrease  // Diminuzione = miglioramento
        }
        
        // Calcola angolo: 0% = 0° (->), 100%+ = 90° (⬆️ o ⬇️)
        // Per miglioramenti: angolo positivo (su), per peggioramenti: angolo negativo (giù)
        let normalizedDiff = min(abs(diff), 100)  // Limita a 100%
        let angle = isImprovement ? normalizedDiff * 0.9 : -normalizedDiff * 0.9  // 0.9 per convertire % in gradi (90° = 100%)
        
        return (abs(diff), isIncrease, isImprovement, angle)
    }
    
    private var variationColor: Color {
        guard let variation = variation, let prev = previousValue else { return .secondary }
        
        // Ottieni target e range se disponibili
        let (effectiveTarget, effectiveMin, effectiveMax): (Double?, Double?, Double?)
        
        if hasRange {
            // Usa range esplicito se fornito
            effectiveMin = targetMin
            effectiveMax = targetMax
            effectiveTarget = target  // Centro del range
        } else if let target = target {
            // Target singolo esplicito
            effectiveTarget = target
            effectiveMin = nil
            effectiveMax = nil
        } else if let company = company {
            let settings = CompagniaSettingsService.shared
            let compagnia = Compagnia.from(nomeCompagnia: company)
            let gruppo = compagnia.gruppo
            
            if label.contains("Concordate") {
                let t: Double
                if company.starts(with: "Gruppo"), let prima = gruppo.compagnie.first {
                    t = settings.effectiveTargetConcordate(prima)
                } else {
                    t = settings.effectiveTargetConcordate(compagnia)
                }
                effectiveTarget = t
                effectiveMin = nil
                effectiveMax = nil
            } else if label.contains("Negativi") {
                let t: Double
                if company.starts(with: "Gruppo"), let prima = gruppo.compagnie.first {
                    t = settings.effectiveTargetNegative(prima)
                } else {
                    t = settings.effectiveTargetNegative(compagnia)
                }
                effectiveTarget = t
                effectiveMin = t
                effectiveMax = t * 1.25
            } else if label.contains("Tempo") || isDays {
                let t = settings.effectiveTargetTempoGestione(compagnia)
                effectiveTarget = t
                effectiveMin = t * 0.85
                effectiveMax = t * 1.15
            } else {
                let t = settings.effectiveTargetLiquidatoMedio(compagnia)
                effectiveTarget = t
                // Verde sotto target*0.9, giallo tra 0.9 e 1.1, rosso sopra 1.1
                // Quindi il "buono" è sotto 0.9, l'accettabile è sotto 1.1
                effectiveMin = nil
                effectiveMax = t * 1.1  // Limite superiore accettabile
            }
        } else {
            effectiveTarget = nil
            effectiveMin = nil
            effectiveMax = nil
        }
        
        // Valuta la posizione rispetto al target/range
        if let min = effectiveMin, let max = effectiveMax {
            // Ha un range: deve stare tra min e max
            let currentInRange = value >= min && value <= max
            let previousInRange = prev >= min && prev <= max
            
            if variation.isImprovement {
                // Miglioramento
                if currentInRange && !previousInRange {
                    // Siamo entrati nel range: verde
                    return .green
                } else if currentInRange && previousInRange {
                    // Entrambi nel range, miglioramento: verde
                    return .green
                } else if !currentInRange && !previousInRange {
                    // Entrambi fuori, ma miglioramento verso il range: verde
                    return .green
                } else {
                    // Caso particolare: miglioramento ma usciti dal range
                    // Se ci stiamo avvicinando al range, verde, altrimenti arancione
                    let distanceToRange = value < min ? (min - value) : (value - max)
                    let prevDistanceToRange = prev < min ? (min - prev) : (prev - max)
                    return distanceToRange < prevDistanceToRange ? .green : .orange
                }
            } else {
                // Peggioramento
                if currentInRange && previousInRange {
                    // Entrambi nel range, ma peggioramento: arancione (ancora ok)
                    return .orange
                } else if !currentInRange && previousInRange {
                    // Siamo usciti dal range: rosso
                    return .red
                } else if !currentInRange && !previousInRange {
                    // Entrambi fuori, peggioramento: rosso
                    return .red
                } else {
                    // Caso particolare: peggioramento ma entrati nel range
                    return .orange
                }
            }
        } else if let target = effectiveTarget {
            // Target singolo (senza range) o con limite superiore
            let hasMaxLimit = effectiveMax != nil && !hasRange  // Caso liquidato medio
            
            if hasMaxLimit, let max = effectiveMax {
                // Caso speciale: liquidato medio (più basso è meglio, ma ha limite superiore)
                let currentIsGood = value <= target * 0.9  // Verde
                let currentIsAcceptable = value <= max  // Giallo o verde
                let previousIsGood = prev <= target * 0.9
                let previousIsAcceptable = prev <= max
                
                if variation.isImprovement {
                    // Miglioramento: sempre verde
                    return .green
                } else {
                    // Peggioramento
                    if currentIsGood && previousIsGood {
                        // Entrambi buoni, peggioramento: arancione
                        return .orange
                    } else if currentIsAcceptable && previousIsGood {
                        // Eravamo buoni, ora accettabili: arancione
                        return .orange
                    } else if !currentIsAcceptable && previousIsAcceptable {
                        // Siamo passati sopra il limite: rosso
                        return .red
                    } else {
                        // Peggioramento: rosso
                        return .red
                    }
                }
            } else {
                // Target singolo normale
                let currentIsGood = higherIsBetter ? (value >= target) : (value <= target)
                let previousIsGood = higherIsBetter ? (prev >= target) : (prev <= target)
                
                if variation.isImprovement {
                    // Miglioramento: sempre verde (anche se ancora sotto target, è comunque positivo)
                    return .green
                } else {
                    // Peggioramento
                    if currentIsGood && previousIsGood {
                        // Entrambi sopra/sotto target, ma peggioramento: arancione (peggioramento ma ancora ok)
                        return .orange
                    } else if !currentIsGood && previousIsGood {
                        // Siamo passati sotto/sopra target: rosso (peggioramento significativo)
                        return .red
                    } else {
                        // Entrambi sotto/sopra target, peggioramento: rosso
                        return .red
                    }
                }
            }
        } else {
            // Senza target, usa verde per miglioramenti, rosso per peggioramenti
            return variation.isImprovement ? .green : .red
        }
    }
    
    private var formattedValue: String {
        if isPercentage {
            return String(format: "%.1f%%", value)
        } else if isDays {
            return String(format: "%.1f gg", value)
        } else {
            return CurrencyFormatter.shared.formatWithSymbol(value)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Indicatore triangolo se ci sono sinistri con dati mancanti
                if let info = missingDataInfo {
                    Button {
                        tipoDatoMancante = info.tipo
                        showMissingDataPopover = true
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .help(info.helpText)
                    .popover(isPresented: $showMissingDataPopover, arrowEdge: .bottom) {
                        MissingDataPopover(
                            sinistriRiferimenti: info.sinistri,
                            tipoDatoMancante: tipoDatoMancante
                        )
                    }
                }
            }
            
            HStack(spacing: 6) {
                Text(formattedValue)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                
                if let variation = variation {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .rotationEffect(.degrees(variation.angle))
                        Text(String(format: "%.1f%%", variation.value))
                            .font(.caption2)
                    }
                    .foregroundColor(variationColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(
            previousValue != nil && previousValue! > 0
                ? "Valore attuale: \(formattedValue)\nValore precedente: \(isPercentage ? String(format: "%.1f%%", previousValue!) : (isDays ? String(format: "%.1f gg", previousValue!) : CurrencyFormatter.shared.formatWithSymbol(previousValue!)))\nVariazione: \(variation != nil ? (variation!.isIncrease ? "+" : "-") + String(format: "%.1f%%", variation!.value) : "N/A")"
                : "Valore attuale: \(formattedValue)"
        )
    }
}

// MARK: - Missing Data Popover (Generico)
struct MissingDataPopover: View {
    let sinistriRiferimenti: [String]
    let tipoDatoMancante: TipoDatoMancante
    @Environment(\.managedObjectContext) private var viewContext
    
    enum TipoDatoMancante {
        case dataAssegnazione
        case liquidazione
        case definizione
        
        var titolo: String {
            switch self {
            case .dataAssegnazione: return "Manca data assegnazione"
            case .liquidazione: return "Manca importo liquidazione"
            case .definizione: return "Manca definizione"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Dati Mancanti")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(sinistriRiferimenti.count)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.orange)
            }
            .padding(14)
            .background(LinearGradient(colors: [Color.orange.opacity(0.12), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            
            Divider()
            
            // Lista sinistri
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sinistriRiferimenti.enumerated()), id: \.element) { index, riferimento in
                        sinistroRow(riferimento: riferimento, index: index + 1)
                        if index < sinistriRiferimenti.count - 1 {
                            Divider().padding(.leading, 32)
                        }
                    }
                }
            }
            .frame(maxHeight: 250)
        }
        .frame(width: 300)
    }
    
    @ViewBuilder
    private func sinistroRow(riferimento: String, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.orange))
            
            VStack(alignment: .leading, spacing: 3) {
                Text(riferimento)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                Text(tipoDatoMancante.titolo)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                apriSinistro(riferimento: riferimento)
            } label: {
                Text("Apri")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    private func apriSinistro(riferimento: String) {
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        if let sinistro = try? viewContext.fetch(request).first {
            AppState.shared.openSinistro(sinistro, openInNewWindow: true)
        }
    }
}

// MARK: - Missing Data Assegnazione Popover (Retrocompatibilità)
struct MissingDataAssegnazionePopover: View {
    let sinistriRiferimenti: [String]
    let onOpenSinistro: ((String) -> Void)?
    
    var body: some View {
        MissingDataPopover(
            sinistriRiferimenti: sinistriRiferimenti,
            tipoDatoMancante: .dataAssegnazione
        )
    }
}

struct LegendItem: View {
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct CompanyYearStats: Identifiable {
    let id = UUID()
    let company: String
    let totalClaims: Int
    let averageLiquidation: Double
    let negativePercentage: Double
}
