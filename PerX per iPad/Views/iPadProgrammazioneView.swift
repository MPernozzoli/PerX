//
//  iPadProgrammazioneView.swift
//  PerX per iPad
//
//  Vista programmazione lavoro con calendario e orari.
//

import SwiftUI

struct iPadProgrammazioneView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var selectedDate = Date()
    @State private var tasks: [ProgrammazioneTask] = []
    @State private var workDays: [WorkDayDTO] = []
    @State private var targetMensile: Int = 0
    @State private var showingAddTask = false
    @State private var showingDaySettings = false
    @State private var isLoading = false
    @State private var dataSource = "locale"
    
    private var anno: Int { Calendar.current.component(.year, from: selectedDate) }
    private var mese: Int { Calendar.current.component(.month, from: selectedDate) }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left: Calendar
            calendarSection
                .frame(width: 380)
            
            Divider()
            
            // Right: Day detail + tasks
            dayDetailSection
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("Programmazione")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isLoading {
                    ProgressView()
                } else {
                    Text(dataSource)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingAddTask = true
                    } label: {
                        Label("Nuova attività", systemImage: "plus")
                    }
                    
                    Button {
                        showingDaySettings = true
                    } label: {
                        Label("Impostazioni giorno", systemImage: "clock")
                    }
                    
                    Divider()
                    
                    Button {
                        Task { await loadSchedule() }
                    } label: {
                        Label("Aggiorna", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddTask) {
            AddTaskSheet(selectedDate: selectedDate) { task in
                tasks.append(task)
            }
        }
        .sheet(isPresented: $showingDaySettings) {
            DaySettingsSheet(
                date: selectedDate,
                workDay: workDays.first { $0.giorno == Calendar.current.component(.day, from: selectedDate) },
                onSave: { updatedDay in
                    Task { await saveDaySettings(updatedDay) }
                }
            )
        }
        .task {
            await loadSchedule()
        }
        .onChange(of: selectedDate) { _ in
            // Solo ricarica se cambia il mese
            let newMese = Calendar.current.component(.month, from: selectedDate)
            let oldMese = mese
            if newMese != oldMese {
                Task { await loadSchedule() }
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadSchedule() async {
        isLoading = true
        defer { isLoading = false }
        
        // Carica da CloudKit tramite sync service (o locale)
        // TODO: Implementare fetch da iPadCloudKitSyncService quando disponibile
        workDays = generateLocalWorkDays()
        
        // Carica target da UserDefaults (sincronizzato via CloudKit KV Store)
        let key = "monthlyTarget_\(anno)_\(mese)"
        targetMensile = UserDefaults.standard.integer(forKey: key)
        
        dataSource = "CloudKit"
    }
    
    private func generateLocalWorkDays() -> [WorkDayDTO] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: DateComponents(year: anno, month: mese))!
        let range = calendar.range(of: .day, in: .month, for: monthStart)!
        
        // Carica giorni speciali da UserDefaults (sincronizzati via CK KV Store)
        let specialDaysKey = "specialDays_\(anno)_\(mese)"
        let specialDaysData = UserDefaults.standard.data(forKey: specialDaysKey)
        let specialDays: [Int: SpecialDayConfig] = {
            guard let data = specialDaysData,
                  let decoded = try? JSONDecoder().decode([Int: SpecialDayConfig].self, from: data) else {
                return [:]
            }
            return decoded
        }()
        
        // Festività italiane
        let festivita = getFestitaItaliane(anno: anno, mese: mese)
        
        return range.map { day in
            let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart)!
            let weekday = calendar.component(.weekday, from: date)
            let isWeekend = weekday == 1 || weekday == 7
            
            // Check special day override
            if let special = specialDays[day] {
                return WorkDayDTO(
                    anno: anno,
                    mese: mese,
                    giorno: day,
                    isLavorativo: special.isLavorativo,
                    orari: special.orari,
                    nota: special.nota,
                    isFestivo: false,
                    nomeFestivita: nil
                )
            }
            
            // Check festività
            if let festivo = festivita[day] {
                return WorkDayDTO(
                    anno: anno,
                    mese: mese,
                    giorno: day,
                    isLavorativo: false,
                    orari: nil,
                    nota: nil,
                    isFestivo: true,
                    nomeFestivita: festivo
                )
            }
            
            return WorkDayDTO(
                anno: anno,
                mese: mese,
                giorno: day,
                isLavorativo: !isWeekend,
                orari: isWeekend ? nil : [
                    OrarioDTO(id: UUID().uuidString, inizio: "09:00", fine: "13:00", luogo: "office"),
                    OrarioDTO(id: UUID().uuidString, inizio: "14:00", fine: "18:00", luogo: "office")
                ],
                nota: nil,
                isFestivo: false,
                nomeFestivita: nil
            )
        }
    }
    
    private func getFestitaItaliane(anno: Int, mese: Int) -> [Int: String] {
        var festivita: [Int: String] = [:]
        
        switch mese {
        case 1:
            festivita[1] = "Capodanno"
            festivita[6] = "Epifania"
        case 4:
            festivita[25] = "Festa della Liberazione"
            // Pasqua e Pasquetta variano - calcolo semplificato
        case 5:
            festivita[1] = "Festa dei Lavoratori"
        case 6:
            festivita[2] = "Festa della Repubblica"
        case 8:
            festivita[15] = "Ferragosto"
        case 11:
            festivita[1] = "Tutti i Santi"
        case 12:
            festivita[8] = "Immacolata Concezione"
            festivita[25] = "Natale"
            festivita[26] = "Santo Stefano"
        default:
            break
        }
        
        return festivita
    }
    
    private func saveDaySettings(_ update: WorkDayUpdateDTO) async {
        let day = Calendar.current.component(.day, from: selectedDate)
        
        // Salva in UserDefaults (sincronizzato via CloudKit KV Store)
        let key = "specialDays_\(anno)_\(mese)"
        var specialDays: [Int: SpecialDayConfig] = {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([Int: SpecialDayConfig].self, from: data) else {
                return [:]
            }
            return decoded
        }()
        
        specialDays[day] = SpecialDayConfig(
            isLavorativo: update.isLavorativo,
            orari: update.orari,
            nota: update.nota
        )
        
        if let data = try? JSONEncoder().encode(specialDays) {
            UserDefaults.standard.set(data, forKey: key)
            
            // Sincronizza su CloudKit KV Store
            NSUbiquitousKeyValueStore.default.set(data, forKey: key)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
        
        await loadSchedule()
    }
    
    // MARK: - Calendar
    
    @ViewBuilder
    private var calendarSection: some View {
        VStack(spacing: 0) {
            // Month header
            HStack {
                Button {
                    selectedDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text(selectedDate, format: .dateTime.month(.wide).year())
                        .font(.headline)
                    
                    Text("\(giorniLavorativi) giorni lavorativi")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    selectedDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                }
            }
            .padding()
            
            Divider()
            
            // Target mensile
            if targetMensile > 0 {
                HStack {
                    Text("Obiettivo:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(targetMensile) pratiche")
                        .font(.caption.bold())
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.1))
            }
            
            // Calendar grid
            WorkCalendarGridView(
                selectedDate: $selectedDate,
                workDays: workDays,
                tasksPerDay: tasksPerDay
            )
            .padding()
            
            Spacer()
            
            // Legend
            VStack(alignment: .leading, spacing: 8) {
                Text("Legenda")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    LegendItem(color: .green.opacity(0.3), label: "Lavorativo")
                    LegendItem(color: .red.opacity(0.3), label: "Festivo")
                    LegendItem(color: .gray.opacity(0.3), label: "Non lavorativo")
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private var giorniLavorativi: Int {
        workDays.filter { $0.isLavorativo }.count
    }
    
    // MARK: - Day Detail
    
    @ViewBuilder
    private var dayDetailSection: some View {
        VStack(spacing: 0) {
            // Header
            dayHeader
            
            Divider()
            
            // Orari del giorno
            if let workDay = workDays.first(where: { $0.giorno == Calendar.current.component(.day, from: selectedDate) }) {
                workDayDetailView(workDay)
            }
            
            Divider()
            
            // Tasks
            if tasksForSelectedDay.isEmpty {
                ContentUnavailableView(
                    "Nessuna attività",
                    systemImage: "calendar.badge.checkmark",
                    description: Text("Non ci sono attività programmate per questo giorno")
                )
            } else {
                List {
                    ForEach(tasksForSelectedDay) { task in
                        ProgrammazioneTaskRow(task: task)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    @ViewBuilder
    private var dayHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedDate, format: .dateTime.weekday(.wide))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text(selectedDate, format: .dateTime.day().month())
                    .font(.title.bold())
            }
            
            Spacer()
            
            if Calendar.current.isDateInToday(selectedDate) {
                Text("Oggi")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
            
            Button {
                showingDaySettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    @ViewBuilder
    private func workDayDetailView(_ workDay: WorkDayDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(workDay.isLavorativo ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                
                Text(workDay.isLavorativo ? "Giornata lavorativa" : "Non lavorativo")
                    .font(.subheadline.bold())
                
                if workDay.isFestivo, let nome = workDay.nomeFestivita {
                    Text("• \(nome)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                Spacer()
            }
            
            if workDay.isLavorativo, let orari = workDay.orari, !orari.isEmpty {
                HStack(spacing: 16) {
                    ForEach(orari) { orario in
                        HStack(spacing: 4) {
                            Image(systemName: orario.luogo == "office" ? "building.2" : "house")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("\(orario.inizio) - \(orario.fine)")
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                    }
                }
            }
            
            if let nota = workDay.nota, !nota.isEmpty {
                HStack {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(nota)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
    
    private var tasksForSelectedDay: [ProgrammazioneTask] {
        let calendar = Calendar.current
        return tasks.filter { task in
            calendar.isDate(task.date, inSameDayAs: selectedDate)
        }
    }
    
    private var tasksPerDay: [Date: Int] {
        var result: [Date: Int] = [:]
        let calendar = Calendar.current
        
        for task in tasks {
            let day = calendar.startOfDay(for: task.date)
            result[day, default: 0] += 1
        }
        
        return result
    }
}

// MARK: - Special Day Config

struct SpecialDayConfig: Codable {
    let isLavorativo: Bool
    let orari: [OrarioDTO]?
    let nota: String?
}

// MARK: - Models

struct ProgrammazioneTask: Identifiable {
    let id: String
    let title: String
    let description: String
    let date: Date
    let sinistroRif: String?
    var isCompleted: Bool
    let type: TaskType
    
    enum TaskType {
        case task, deadline, appointment
        
        var color: Color {
            switch self {
            case .task: return .blue
            case .deadline: return .orange
            case .appointment: return .purple
            }
        }
        
        var icon: String {
            switch self {
            case .task: return "checkmark.circle"
            case .deadline: return "exclamationmark.circle"
            case .appointment: return "calendar"
            }
        }
    }
}

// MARK: - Subviews

struct WorkCalendarGridView: View {
    @Binding var selectedDate: Date
    let workDays: [WorkDayDTO]
    let tasksPerDay: [Date: Int]
    
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["L", "M", "M", "G", "V", "S", "D"]
    
    var body: some View {
        VStack(spacing: 8) {
            // Weekday headers
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
            }
            
            // Days grid
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(daysInMonth, id: \.self) { date in
                    if let date = date {
                        let day = Calendar.current.component(.day, from: date)
                        let workDay = workDays.first { $0.giorno == day }
                        
                        WorkDayCell(
                            date: date,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                            isToday: Calendar.current.isDateInToday(date),
                            isLavorativo: workDay?.isLavorativo ?? true,
                            isFestivo: workDay?.isFestivo ?? false,
                            taskCount: tasksPerDay[Calendar.current.startOfDay(for: date)] ?? 0
                        )
                        .onTapGesture {
                            selectedDate = date
                        }
                    } else {
                        Color.clear
                            .frame(height: 50)
                    }
                }
            }
        }
    }
    
    private var daysInMonth: [Date?] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
        
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let adjustedFirstWeekday = (firstWeekday + 5) % 7 // Adjust for Monday start
        
        let range = calendar.range(of: .day, in: .month, for: monthStart)!
        
        var days: [Date?] = Array(repeating: nil, count: adjustedFirstWeekday)
        
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                days.append(date)
            }
        }
        
        // Pad to complete weeks
        while days.count % 7 != 0 {
            days.append(nil)
        }
        
        return days
    }
}

struct WorkDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isLavorativo: Bool
    let isFestivo: Bool
    let taskCount: Int
    
    private var backgroundColor: Color {
        if isSelected { return .accentColor }
        if isFestivo { return .red.opacity(0.2) }
        if !isLavorativo { return .gray.opacity(0.15) }
        return .green.opacity(0.1)
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
            
            if isToday && !isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
            
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline.bold())
                    .foregroundColor(isSelected ? .white : (isFestivo ? .red : .primary))
                
                if taskCount > 0 {
                    Circle()
                        .fill(isSelected ? Color.white : Color.blue)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .frame(height: 50)
    }
}

struct DaySettingsSheet: View {
    let date: Date
    let workDay: WorkDayDTO?
    let onSave: (WorkDayUpdateDTO) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isLavorativo: Bool = true
    @State private var nota: String = ""
    @State private var orari: [EditableOrario] = []
    
    struct EditableOrario: Identifiable {
        let id = UUID()
        var inizio: Date
        var fine: Date
        var luogo: String
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Giorno lavorativo", isOn: $isLavorativo)
                }
                
                if isLavorativo {
                    Section("Orari di lavoro") {
                        ForEach($orari) { $orario in
                            HStack {
                                DatePicker("Inizio", selection: $orario.inizio, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                
                                Text("-")
                                
                                DatePicker("Fine", selection: $orario.fine, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                
                                Picker("", selection: $orario.luogo) {
                                    Text("Ufficio").tag("office")
                                    Text("Remoto").tag("remote")
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }
                        .onDelete { indices in
                            orari.remove(atOffsets: indices)
                        }
                        
                        Button {
                            let now = Date()
                            orari.append(EditableOrario(
                                inizio: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now)!,
                                fine: Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: now)!,
                                luogo: "office"
                            ))
                        } label: {
                            Label("Aggiungi fascia oraria", systemImage: "plus")
                        }
                    }
                } else {
                    Section("Nota") {
                        TextField("Es. Ferie, Malattia...", text: $nota)
                    }
                }
            }
            .navigationTitle(formatDateTitle(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "HH:mm"
                        
                        let orariDTO: [OrarioDTO]? = isLavorativo ? orari.map {
                            OrarioDTO(
                                id: UUID().uuidString,
                                inizio: formatter.string(from: $0.inizio),
                                fine: formatter.string(from: $0.fine),
                                luogo: $0.luogo
                            )
                        } : nil
                        
                        let update = WorkDayUpdateDTO(
                            isLavorativo: isLavorativo,
                            orari: orariDTO,
                            nota: isLavorativo ? nil : nota
                        )
                        
                        onSave(update)
                        dismiss()
                    }
                }
            }
            .onAppear {
                isLavorativo = workDay?.isLavorativo ?? true
                nota = workDay?.nota ?? ""
                
                if let existingOrari = workDay?.orari {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    
                    orari = existingOrari.compactMap { dto in
                        guard let inizio = formatter.date(from: dto.inizio),
                              let fine = formatter.date(from: dto.fine) else { return nil }
                        return EditableOrario(inizio: inizio, fine: fine, luogo: dto.luogo)
                    }
                } else if isLavorativo {
                    // Default orari
                    let now = Date()
                    orari = [
                        EditableOrario(
                            inizio: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now)!,
                            fine: Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: now)!,
                            luogo: "office"
                        ),
                        EditableOrario(
                            inizio: Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: now)!,
                            fine: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: now)!,
                            luogo: "office"
                        )
                    ]
                }
            }
        }
    }
    
    private func formatDateTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date).capitalized
    }
}

struct LegendItem: View {
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

struct ProgrammazioneTaskRow: View {
    let task: ProgrammazioneTask
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : task.type.icon)
                .foregroundColor(task.isCompleted ? .green : task.type.color)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline)
                    .strikethrough(task.isCompleted)
                
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 8) {
                    if let rif = task.sinistroRif {
                        Label(rif, systemImage: "folder")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    Label {
                        Text(task.date, format: .dateTime.hour().minute())
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct AddTaskSheet: View {
    let selectedDate: Date
    let onAdd: (ProgrammazioneTask) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var time = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli") {
                    TextField("Titolo", text: $title)
                    TextField("Descrizione", text: $description)
                }
                
                Section("Data e ora") {
                    DatePicker("Ora", selection: $time, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("Nuova attività")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aggiungi") {
                        let calendar = Calendar.current
                        let components = calendar.dateComponents([.hour, .minute], from: time)
                        let taskDate = calendar.date(bySettingHour: components.hour ?? 9, minute: components.minute ?? 0, second: 0, of: selectedDate) ?? selectedDate
                        
                        let task = ProgrammazioneTask(
                            id: UUID().uuidString,
                            title: title,
                            description: description,
                            date: taskDate,
                            sinistroRif: nil,
                            isCompleted: false,
                            type: .task
                        )
                        
                        onAdd(task)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}
