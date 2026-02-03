import SwiftUI
import CoreData

struct DailyScheduleView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var taskManager = TaskManager.shared
    @ObservedObject private var workScheduleManager = WorkScheduleManager.shared
    @State private var refreshID = UUID()
    
    private let calendar = Calendar.current
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Oggi
                DayScheduleSection(
                    title: "Oggi",
                    date: Date(),
                    taskManager: taskManager,
                    workScheduleManager: workScheduleManager,
                    viewContext: viewContext
                )
                .id("today-\(refreshID)")
                
                // Domani
                if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) {
                    DayScheduleSection(
                        title: "Domani",
                        date: tomorrow,
                        taskManager: taskManager,
                        workScheduleManager: workScheduleManager,
                        viewContext: viewContext
                    )
                    .id("tomorrow-\(refreshID)")
                }
                
                // Dopodomani
                if let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: Date()) {
                    DayScheduleSection(
                        title: "Dopodomani",
                        date: dayAfterTomorrow,
                        taskManager: taskManager,
                        workScheduleManager: workScheduleManager,
                        viewContext: viewContext
                    )
                    .id("dayAfter-\(refreshID)")
                }
            }
            .padding()
        }
        .onReceive(taskManager.$updateCounter.dropFirst()) { _ in
            // Aggiorna la vista quando cambiano le task (dropFirst evita trigger iniziale)
            refreshID = UUID()
        }
        .onReceive(workScheduleManager.$updateCounter.dropFirst()) { _ in
            // Quando cambiano gli orari, riorganizza le task e aggiorna la vista
            // dropFirst evita trigger iniziale che causa loop
            Task { @MainActor in
                ScheduleManager.shared.reorganizeAllTasksBasedOnSchedule()
            }
            refreshID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workScheduleChanged)) { _ in
            // Quando cambiano gli orari lavorativi, forza riorganizzazione completa
            Task { @MainActor in
                ScheduleManager.shared.reorganizeAllTasksBasedOnSchedule()
                refreshID = UUID()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskCreated)) { _ in
            // Quando viene creata una nuova task, riorganizza e aggiorna la vista
            Task { @MainActor in
                ScheduleManager.shared.reorganizeAllTasksBasedOnSchedule()
            }
            refreshID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .emailReceived)) { _ in
            Task { @MainActor in
                await taskManager.regenerateBaseTasks(triggeredByEmail: true)
            }
            refreshID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sinistroStatoChanged)) { _ in
            // Quando cambia lo stato di un sinistro, potrebbe generare task, aggiorna la vista
            refreshID = UUID()
        }
        .onAppear {
            // Forza rigenerazione task di base all'apertura
            Task {
                await taskManager.regenerateBaseTasks()
            }
        }
    }
}

struct DayScheduleSection: View {
    let title: String
    let date: Date
    @ObservedObject var taskManager: TaskManager
    @ObservedObject var workScheduleManager: WorkScheduleManager
    let viewContext: NSManagedObjectContext
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter
    }()
    
    var body: some View {
        let dayKind: DayKind = {
            if calendar.isDateInToday(date) { return .today }
            if date < calendar.startOfDay(for: Date()) { return .past }
            return .future
        }()
        
        VStack(alignment: .leading, spacing: 12) {
            // Header giorno
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(dateFormatter.string(from: date))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Indicatore ore lavorative con icona luogo
                if workScheduleManager.isWorkingDay(date) {
                    let hours = workScheduleManager.getWorkingHours(for: date)
                    let totalHours = hours.reduce(0) { total, workingHours in
                        total + workingHours.end.timeIntervalSince(workingHours.start) / 3600
                    }
                    HStack(spacing: 4) {
                        // Mostra icone dei luoghi di lavoro del giorno
                        let places = Set(hours.map { $0.place })
                        ForEach(Array(places), id: \.self) { place in
                            Image(systemName: place.icon)
                                .font(.caption)
                                .foregroundColor(place == .remote ? .blue : .secondary)
                        }
                        Text(String(format: "%.1f h", totalHours))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Non lavorativo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Task per il giorno (includendo completate/ignorate)
            let tasksForDay = taskManager.tasks
                .filter { task in
                    let day = task.scheduledDate ?? calendar.startOfDay(for: task.createdAt)
                    return calendar.isDate(day, inSameDayAs: date)
                }
                .sorted {
                    let t1 = $0.scheduledTime ?? $0.createdAt
                    let t2 = $1.scheduledTime ?? $1.createdAt
                    return t1 < t2
                }
            
            // Vista calendario oraria stile Apple Calendar
            TodayCalendarView(
                date: date,
                tasks: tasksForDay,
                workScheduleManager: workScheduleManager,
                onComplete: { task in
                    taskManager.markTaskCompleted(taskID: task.id, manually: true)
                },
                onIgnore: { task in
                    taskManager.markTaskIgnored(taskID: task.id)
                },
                viewContext: viewContext
            )
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

enum DayKind {
    case today
    case future
    case past
}

// MARK: - Today calendar view
struct TodayCalendarView: View {
    let date: Date
    let tasks: [DailyTask]
    let workScheduleManager: WorkScheduleManager
    let onComplete: (DailyTask) -> Void
    let onIgnore: (DailyTask) -> Void
    let viewContext: NSManagedObjectContext
    
    private let calendar = Calendar.current
    
    // Spazio minimo per ora senza task
    private let minHourHeight: CGFloat = 60
    // Spazio base per task
    private let baseTaskHeight: CGFloat = 80
    // Spazio extra per ogni task aggiuntiva nella stessa ora
    private let extraTaskHeight: CGFloat = 70
    // Padding tra task
    private let taskPadding: CGFloat = 4
    
    var body: some View {
        let workingHours = workScheduleManager.getWorkingHours(for: date).sorted { $0.start < $1.start }
        let startTime = workingHours.first?.start ?? calendar.startOfDay(for: date).addingTimeInterval(8 * 3600)
        let endTime = workingHours.last?.end ?? calendar.startOfDay(for: date).addingTimeInterval(17 * 3600)
        
        // Calcola layout non lineare
        let layout = calculateNonLinearLayout(
            tasks: tasks,
            startTime: startTime,
            endTime: endTime,
            workingHours: workingHours
        )
        
        VStack(alignment: .leading, spacing: 12) {
            if tasks.isEmpty {
                Text("Nessuna task programmata")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        // Linee orarie
                        ForEach(layout.hourMarks, id: \.time) { hourMark in
                            let y = layout.yPosition(for: hourMark.time)
                            Rectangle()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 1)
                                .position(x: geo.size.width / 2, y: y * geo.size.height)
                            
                            Text(hourFormatter.string(from: hourMark.time))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .position(x: 30, y: (y * geo.size.height) - 8)
                        }
                        
                        // Linea rossa del "now"
                        if calendar.isDateInToday(date) {
                            let now = Date()
                            if now >= startTime && now <= endTime {
                                let yNow = layout.yPosition(for: now) * geo.size.height
                                Rectangle()
                                    .fill(Color.red)
                                    .frame(height: 2)
                                    .position(x: geo.size.width / 2, y: yNow)
                            }
                        }
                        
                        // Task box
                        ForEach(layout.positionedTasks) { positionedTask in
                            let task = positionedTask.task
                            let yStart = positionedTask.yStart * geo.size.height
                            let yEnd = positionedTask.yEnd * geo.size.height
                            let boxHeight = max(38, yEnd - yStart)
                            
                            let style = stateStyle(for: task)
                            let isUpcoming = positionedTask.startTime > Date()
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .lineLimit(1)
                                        if let rif = task.sinistroID {
                                            Text(riferimentoVisualizzato(for: rif))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if task.isExpired {
                                        Text("SCADUTO")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.red)
                                            .cornerRadius(4)
                                    } else if task.isDeadlineImminent {
                                        Image(systemName: "clock.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                    }
                                }
                                
                                Text(task.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                
                                HStack(spacing: 8) {
                                    if task.status == .pending {
                                        Button("Completa") { onComplete(task) }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                        Button("Ignora") { onIgnore(task) }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                    } else if task.status == .completed {
                                        Label("Completata", systemImage: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    } else if task.status == .inProgress {
                                        Label("In corso", systemImage: "clock")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                ZStack(alignment: .topTrailing) {
                                    (isUpcoming ? style.color.opacity(0.18) : todayBackground(for: task))
                                    Image(systemName: style.icon)
                                        .font(.system(size: 42))
                                        .foregroundColor(style.color.opacity(0.15))
                                        .padding(8)
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(style.color.opacity(0.35), lineWidth: 1)
                            )
                            .cornerRadius(10)
                            .position(x: geo.size.width / 2, y: yStart + boxHeight / 2)
                            .frame(height: boxHeight)
                        }
                    }
                }
                .frame(height: layout.totalHeight)
            }
        }
    }
    
    // MARK: - Layout Calculation
    
    private struct HourMark {
        let time: Date
    }
    
    private struct PositionedTask: Identifiable {
        let id: UUID
        let task: DailyTask
        let startTime: Date
        let endTime: Date
        let yStart: CGFloat
        let yEnd: CGFloat
    }
    
    private struct NonLinearLayout {
        let hourMarks: [HourMark]
        let positionedTasks: [PositionedTask]
        let totalHeight: CGFloat
        let startTime: Date
        let endTime: Date
        
        // Mappa tempo -> posizione Y normalizzata (0.0 - 1.0)
        private let timeToY: [Date: CGFloat]
        
        init(
            hourMarks: [HourMark],
            positionedTasks: [PositionedTask],
            totalHeight: CGFloat,
            startTime: Date,
            endTime: Date,
            timeToY: [Date: CGFloat]
        ) {
            self.hourMarks = hourMarks
            self.positionedTasks = positionedTasks
            self.totalHeight = totalHeight
            self.startTime = startTime
            self.endTime = endTime
            self.timeToY = timeToY
        }
        
        func yPosition(for time: Date) -> CGFloat {
            // Trova i due punti più vicini per interpolazione
            let sortedTimes = timeToY.keys.sorted()
            
            // Se il tempo è prima del primo punto
            if let first = sortedTimes.first, time <= first {
                return timeToY[first] ?? 0
            }
            
            // Se il tempo è dopo l'ultimo punto
            if let last = sortedTimes.last, time >= last {
                return timeToY[last] ?? 1.0
            }
            
            // Trova i due punti tra cui interpolare
            for i in 0..<(sortedTimes.count - 1) {
                let t1 = sortedTimes[i]
                let t2 = sortedTimes[i + 1]
                
                if time >= t1 && time <= t2 {
                    let y1 = timeToY[t1] ?? 0
                    let y2 = timeToY[t2] ?? 1.0
                    
                    // Interpolazione lineare tra i due punti
                    let ratio = time.timeIntervalSince(t1) / t2.timeIntervalSince(t1)
                    return y1 + (y2 - y1) * CGFloat(ratio)
                }
            }
            
            return 0
        }
    }
    
    private func calculateNonLinearLayout(
        tasks: [DailyTask],
        startTime: Date,
        endTime: Date,
        workingHours: [WorkingHours]
    ) -> NonLinearLayout {
        // Filtra task valide con orario
        let validTasks = tasks.compactMap { task -> (DailyTask, Date, Date)? in
            guard let start = task.scheduledTime else { return nil }
            let duration = taskDuration(task)
            let end = start.addingTimeInterval(duration)
            
            // Solo task che si sovrappongono con le ore lavorative
            if end < startTime || start > endTime {
                return nil
            }
            
            return (task, start, end)
        }
        
        // Genera intervalli orari basati su startTime ed endTime
        var hourIntervals: [(start: Date, end: Date)] = []
        var current = startTime
        while current < endTime {
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: current) ?? current.addingTimeInterval(3600)
            let intervalEnd = min(nextHour, endTime)
            hourIntervals.append((start: current, end: intervalEnd))
            current = nextHour
        }
        
        // Genera marcatori orari
        var hourMarks: [HourMark] = []
        for interval in hourIntervals {
            hourMarks.append(HourMark(time: interval.start))
        }
        hourMarks.append(HourMark(time: endTime))
        
        // Calcola task per ogni intervallo orario
        var tasksByInterval: [Int: [(DailyTask, Date, Date)]] = [:]
        for (index, interval) in hourIntervals.enumerated() {
            for (task, start, end) in validTasks {
                // Task che si sovrappone con questo intervallo
                if end > interval.start && start < interval.end {
                    if tasksByInterval[index] == nil {
                        tasksByInterval[index] = []
                    }
                    // Evita duplicati
                    if !tasksByInterval[index]!.contains(where: { $0.0.id == task.id }) {
                        tasksByInterval[index]?.append((task, start, end))
                    }
                }
            }
        }
        
        // Calcola altezza per ogni intervallo
        var cumulativeY: CGFloat = 0
        var timeToY: [Date: CGFloat] = [:]
        timeToY[startTime] = 0
        
        for (index, interval) in hourIntervals.enumerated() {
            let tasksInInterval = tasksByInterval[index] ?? []
            let uniqueTaskCount = Set(tasksInInterval.map { $0.0.id }).count
            
            // Calcola altezza: minimo se nessuna task, altrimenti base + extra per ogni task
            let height: CGFloat
            if uniqueTaskCount == 0 {
                height = minHourHeight
            } else {
                // Altezza base + spazio per ogni task aggiuntiva
                height = baseTaskHeight + CGFloat(uniqueTaskCount - 1) * extraTaskHeight
            }
            
            timeToY[interval.start] = cumulativeY
            cumulativeY += height
            timeToY[interval.end] = cumulativeY
        }
        
        // Normalizza le posizioni Y (0.0 - 1.0)
        let totalHeight = cumulativeY
        let normalizedTimeToY = Dictionary(uniqueKeysWithValues: timeToY.map { ($0.key, $0.value / totalHeight) })
        
        // Crea layout temporaneo per calcolare posizioni task
        let tempLayout = NonLinearLayout(
            hourMarks: hourMarks,
            positionedTasks: [],
            totalHeight: totalHeight,
            startTime: startTime,
            endTime: endTime,
            timeToY: normalizedTimeToY
        )
        
        // Posiziona le task usando il layout
        var positionedTasks: [PositionedTask] = []
        for (task, start, end) in validTasks {
            let yStart = tempLayout.yPosition(for: start)
            let yEnd = tempLayout.yPosition(for: end)
            
            positionedTasks.append(PositionedTask(
                id: task.id,
                task: task,
                startTime: start,
                endTime: end,
                yStart: yStart,
                yEnd: yEnd
            ))
        }
        
        // Ordina task per posizione Y
        positionedTasks.sort { $0.yStart < $1.yStart }
        
        return NonLinearLayout(
            hourMarks: hourMarks,
            positionedTasks: positionedTasks,
            totalHeight: max(320, totalHeight),
            startTime: startTime,
            endTime: endTime,
            timeToY: normalizedTimeToY
        )
    }
    
    private var hourFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }
    
    private func taskDuration(_ task: DailyTask) -> TimeInterval {
        if task.status == .completed {
            return task.actualDuration ?? task.estimatedDuration
        }
        return task.estimatedDuration
    }
    
    private func todayBackground(for task: DailyTask) -> Color {
        if task.isExpired { return Color.red.opacity(0.1) }
        if task.isDeadlineImminent { return Color.orange.opacity(0.1) }
        return Color(NSColor.controlBackgroundColor)
    }
    
    private func stateStyle(for task: DailyTask) -> (color: Color, icon: String) {
        if let statoRaw = task.metadata["stato"]?.value as? String {
            if let stato = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == statoRaw || $0.rawValue == statoRaw }) {
                return (stato.color, stato.icon)
            }
        }
        return (.blue.opacity(0.8), "checkmark.circle")
    }
    
    /// Restituisce il riferimento visualizzato (con sigla compagnia se abilitato)
    private func riferimentoVisualizzato(for sinistroID: String) -> String {
        let showSigla = UserDefaults.standard.bool(forKey: "includiCodiceCompagniaRiferimento")
        guard showSigla else { return sinistroID }
        
        // Cerca il sinistro nel contesto
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
        request.fetchLimit = 1
        
        if let sinistro = try? viewContext.fetch(request).first {
            return sinistro.riferimentoVisualizzato
        }
        
        return sinistroID
    }
}

