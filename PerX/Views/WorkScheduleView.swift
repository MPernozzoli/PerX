import SwiftUI

struct WorkScheduleView: View {
    @ObservedObject private var scheduleManager = WorkScheduleManager.shared
    @State private var selectedDate: Date = Date()
    @State private var showingDayDetail = false
    @State private var showingDefaultSchedule = false
    private let calendar = Calendar.current
    private let calendarService = ItalianCalendarService.shared
    @State private var monthlyTarget: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header con controlli mese
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                }
                
                Text(monthYearString)
                    .font(.title2)
                    .frame(width: 200)
                
                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                }
                
                Spacer()
                
                Text("Giorni lavorativi effettivi: \(countWorkingDays())")
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Button("Oggi") {
                    selectedDate = Date()
                }
                
                Button(action: { showingDefaultSchedule = true }) {
                    Image(systemName: "clock.badge.checkmark")
                }
                .help("Imposta orari predefiniti")
            }
            .padding(.horizontal)
            
            // Nuovo header per l'obiettivo mensile
            HStack {
                Spacer()
                
                GroupBox {
                    HStack(spacing: 12) {
                        Image(systemName: "target")
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Obiettivo mensile")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                TextField("", text: $monthlyTarget)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                                    .onChange(of: monthlyTarget) { newValue in
                                        if let target = Int(newValue), !newValue.isEmpty {
                                            scheduleManager.setMonthlyTarget(target, for: selectedDate)
                                        }
                                    }
                                    .onSubmit {
                                        if let target = Int(monthlyTarget) {
                                            scheduleManager.setMonthlyTarget(target, for: selectedDate)
                                        }
                                    }
                                
                                Text("pratiche")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .help("Imposta l'obiettivo di pratiche da gestire per questo mese")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Calendario
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                // Intestazioni giorni della settimana
                ForEach(Array(zip(0..., ["L", "M", "M", "G", "V", "S", "D"])), id: \.0) { index, day in
                    Text(day)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.secondary)
                }
                
                // Giorni del mese
                ForEach(daysInMonth().indices, id: \.self) { index in
                    if let date = daysInMonth()[index] {
                        DayCell(
                            date: date,
                            scheduleManager: scheduleManager,
                            calendarService: calendarService,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate)
                        )
                        .frame(height: 80)
                        .onTapGesture {
                            selectedDate = date
                            showingDayDetail = true
                        }
                        .id("\(date.timeIntervalSince1970)-\(scheduleManager.updateCounter)")
                    } else {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 80)
                            .id("empty-\(index)-\(scheduleManager.updateCounter)")
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: scheduleManager.updateCounter) { _ in
            // Forza il refresh della vista quando il contatore cambia
            withAnimation {
                // Questo forza SwiftUI a ricreare la vista
                selectedDate = selectedDate
            }
        }
        .sheet(isPresented: $showingDefaultSchedule) {
            DefaultScheduleView(scheduleManager: scheduleManager)
        }
        .sheet(isPresented: $showingDayDetail) {
            DayDetailView(
                date: selectedDate,
                scheduleManager: scheduleManager
            )
        }
        .onChange(of: selectedDate) { newDate in
            // Aggiorna il campo obiettivo quando cambia il mese
            monthlyTarget = "\(scheduleManager.getMonthlyTarget(for: newDate))"
        }
        .onAppear {
            // Inizializza il campo obiettivo
            monthlyTarget = "\(scheduleManager.getMonthlyTarget(for: selectedDate))"
        }
    }
    
    private func previousMonth() {
        if let newDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) {
            selectedDate = newDate
        }
    }
    
    private func nextMonth() {
        if let newDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) {
            selectedDate = newDate
        }
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: selectedDate).capitalized
    }
    
    private func daysInMonth() -> [Date?] {
        let range = calendar.range(of: .day, in: .month, for: selectedDate)!
        let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
        
        var firstWeekday = calendar.component(.weekday, from: firstDay)
        firstWeekday = firstWeekday == 1 ? 7 : firstWeekday - 1
        
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        
        for day in 1...range.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }
        
        while days.count % 7 != 0 {
            days.append(nil)
        }
        
        return days
    }
    
    private func countWorkingDays() -> Int {
        let days = daysInMonth().compactMap { $0 }
        return days.filter { scheduleManager.isWorkingDay($0) }.count
    }
}

struct DayCell: View {
    let date: Date
    let scheduleManager: WorkScheduleManager
    let calendarService: ItalianCalendarService
    let isSelected: Bool
    @State private var showPopover = false
    @Environment(\.colorScheme) private var colorScheme
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(spacing: 4) {
            // Numero del giorno centrato e spostato in basso
            Spacer()
                .frame(height: 4)
            Text("\(calendar.component(.day, from: date))")
                .font(.headline)
                .frame(maxWidth: .infinity)
            
            if let specialDay = scheduleManager.specialDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
                // Giorno speciale
                VStack(alignment: .leading, spacing: 2) {
                    if !specialDay.isWorkingDay {
                        Text("Non lavorativo")
                            .font(.caption2)
                    }
                    if specialDay.isWorkingDay {
                        ForEach(specialDay.hours) { hours in
                            HStack(spacing: 2) {
                                Image(systemName: hours.place.icon)
                                    .font(.system(size: 8))
                                    .foregroundColor(hours.place == .remote ? .blue : .secondary)
                                Text("\(formatTime(hours.start))-\(formatTime(hours.end))")
                                    .font(.caption2)
                            }
                        }
                    }
                    if let note = specialDay.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            } else if scheduleManager.isWorkingDay(date) {
                // Giorno lavorativo standard
                if let schedule = scheduleManager.weekdaySchedules[calendar.component(.weekday, from: date)] {
                    ForEach(schedule.hours) { hours in
                        HStack(spacing: 2) {
                            Image(systemName: hours.place.icon)
                                .font(.system(size: 8))
                                .foregroundColor(hours.place == .remote ? .blue : .secondary)
                            Text("\(formatTime(hours.start))-\(formatTime(hours.end))")
                                .font(.caption2)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            showPopover = true
        }
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            DayDetailView(
                date: date,
                scheduleManager: scheduleManager
            )
            .frame(width: 300)
            .padding()
        }
    }
    
    private var backgroundColor: Color {
        let baseColor = colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : .white
        
        if calendarService.isHoliday(date) {
            return .red.opacity(0.1)
        } else if let specialDay = scheduleManager.specialDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            return specialDay.isWorkingDay ? baseColor : .green.opacity(0.1)
        } else if isWeekend {
            return .gray.opacity(0.1)
        }
        return baseColor
    }
    
    private var isWeekend: Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct DefaultScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var scheduleManager: WorkScheduleManager
    @State private var selectedDay: Int = 2 // Lunedì di default
    
    private let weekdays = [
        (2, "L"),
        (3, "M"),
        (4, "M"),
        (5, "G"),
        (6, "V"),
        (7, "S"),
        (1, "D")
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Orari Lavorativi Predefiniti")
                .font(.headline)
            
            // Selettore giorni
            HStack {
                ForEach(weekdays, id: \.0) { weekday, name in
                    Button(action: {
                        selectedDay = weekday
                    }) {
                        Text(name)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedDay == weekday ? Color.accentColor : Color.clear)
                            .foregroundColor(selectedDay == weekday ? .white : .primary)
                            .cornerRadius(4)
                    }
                }
            }
            
            // Toggle per giorno lavorativo/non lavorativo
            Toggle("Giorno lavorativo", isOn: Binding(
                get: {
                    scheduleManager.weekdaySchedules[selectedDay]?.isWorkingDay ?? false
                },
                set: { newValue in
                    var schedule = scheduleManager.weekdaySchedules[selectedDay] ?? WeekdaySchedule(isWorkingDay: false, hours: [])
                    schedule.isWorkingDay = newValue
                    scheduleManager.weekdaySchedules[selectedDay] = schedule
                }
            ))
            
            if scheduleManager.weekdaySchedules[selectedDay]?.isWorkingDay ?? false {
                VStack(spacing: 12) {
                    ForEach(Array(scheduleManager.weekdaySchedules[selectedDay]?.hours.enumerated() ?? [].enumerated()), id: \.element.id) { index, hours in
                        HStack {
                            DatePicker("", selection: Binding(
                                get: { hours.start },
                                set: { newValue in
                                    var schedule = scheduleManager.weekdaySchedules[selectedDay] ?? WeekdaySchedule(isWorkingDay: true, hours: [])
                                    schedule.hours[index].start = newValue
                                    scheduleManager.weekdaySchedules[selectedDay] = schedule
                                }
                            ), displayedComponents: .hourAndMinute)
                            
                            Text("-")
                            
                            DatePicker("", selection: Binding(
                                get: { hours.end },
                                set: { newValue in
                                    var schedule = scheduleManager.weekdaySchedules[selectedDay] ?? WeekdaySchedule(isWorkingDay: true, hours: [])
                                    schedule.hours[index].end = newValue
                                    scheduleManager.weekdaySchedules[selectedDay] = schedule
                                }
                            ), displayedComponents: .hourAndMinute)
                            
                            // Picker per luogo di lavoro
                            Picker("", selection: Binding(
                                get: { hours.place },
                                set: { newValue in
                                    var schedule = scheduleManager.weekdaySchedules[selectedDay] ?? WeekdaySchedule(isWorkingDay: true, hours: [])
                                    schedule.hours[index].place = newValue
                                    scheduleManager.weekdaySchedules[selectedDay] = schedule
                                }
                            )) {
                                ForEach(WorkPlace.allCases, id: \.self) { place in
                                    Label(place.displayName, systemImage: place.icon).tag(place)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 130)
                            
                            Button(role: .destructive) {
                                var schedule = scheduleManager.weekdaySchedules[selectedDay] ?? WeekdaySchedule(isWorkingDay: true, hours: [])
                                schedule.hours.remove(at: index)
                                scheduleManager.weekdaySchedules[selectedDay] = schedule
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                        }
                    }
                    
                    Button("Aggiungi orario") {
                        let calendar = Calendar.current
                        var schedule = scheduleManager.weekdaySchedules[selectedDay] ?? WeekdaySchedule(isWorkingDay: true, hours: [])
                        schedule.hours.append(WorkingHours(
                            start: calendar.date(from: DateComponents(hour: 9))!,
                            end: calendar.date(from: DateComponents(hour: 13))!,
                            place: .office
                        ))
                        scheduleManager.weekdaySchedules[selectedDay] = schedule
                    }
                }
            }
            
            Divider()
            
            Text("Questi orari verranno applicati come predefiniti solo ai nuovi giorni, senza modificare quelli già programmati nel calendario.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                
                Button("Salva") {
                    saveDefaultSchedule()
                    dismiss()
                }
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    private func saveDefaultSchedule() {
        let today = Date()
        for weekday in 2...6 {
            if let schedule = scheduleManager.weekdaySchedules[weekday], schedule.isWorkingDay {
                scheduleManager.updateDefaultSchedule(
                    from: today,
                    weekday: weekday,
                    schedule: schedule
                )
            }
        }
    }
}

struct DayDetailView: View {
    let date: Date
    @ObservedObject var scheduleManager: WorkScheduleManager
    @Environment(\.dismiss) private var dismiss
    private let calendar = Calendar.current
    
    @State private var isWorkingDay: Bool
    @State private var workingHours: [WorkingHours]
    @State private var note: String
    @State private var applyUntilDate: Date
    @State private var applyToWorkingDaysOnly: Bool
    
    @State private var wasCustomized: Bool = false
    
    init(date: Date, scheduleManager: WorkScheduleManager) {
        self.date = date
        self.scheduleManager = scheduleManager
        
        // Inizializza gli stati con i valori correnti
        let specialDay = scheduleManager.specialDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })
        let weekday = Calendar.current.component(.weekday, from: date)
        let defaultSchedule = scheduleManager.weekdaySchedules[weekday] ?? WeekdaySchedule(isWorkingDay: false, hours: [])
        
        _isWorkingDay = State(initialValue: specialDay?.isWorkingDay ?? defaultSchedule.isWorkingDay)
        _workingHours = State(initialValue: specialDay?.hours ?? defaultSchedule.hours)
        _note = State(initialValue: specialDay?.note ?? "")
        _applyUntilDate = State(initialValue: date)
        _applyToWorkingDaysOnly = State(initialValue: true)
        _wasCustomized = State(initialValue: specialDay != nil)
    }
    
    // Verifica se è un giorno non lavorativo salvato
    private var isStoredNonWorkingDay: Bool {
        if let specialDay = scheduleManager.specialDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            return !specialDay.isWorkingDay
        }
        return false
    }
    
    var body: some View {
        if isStoredNonWorkingDay {
            // Vista semplificata per giorni non lavorativi salvati
            VStack(spacing: 20) {
                Text(formatDate(date))
                    .font(.headline)
                
                Text("Non lavorativo")
                    .foregroundColor(.secondary)
                
                if let specialDay = scheduleManager.specialDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }),
                   let note = specialDay.note {
                    Text(note)
                        .foregroundColor(.secondary)
                }
                
                Button("Elimina", role: .destructive) {
                    // Rimuovi il giorno speciale
                    let dayToRemove = WorkingDay(
                        id: UUID(),
                        date: date,
                        isWorkingDay: false,
                        hours: [],
                        note: nil
                    )
                    scheduleManager.removeSpecialDay(dayToRemove)
                    scheduleManager.updateCounter += 1
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(width: 250)
        } else {
            // Vista normale per tutti gli altri giorni
            VStack(spacing: 20) {
                Text(formatDate(date))
                    .font(.headline)
                
                Picker("", selection: $isWorkingDay) {
                    Text("Lavorativo").tag(true)
                    Text("Non lavorativo").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .onChange(of: isWorkingDay) { newValue in
                    if newValue {
                        if workingHours.isEmpty {
                            workingHours = defaultWorkingHoursForCurrentDate()
                        }
                    } else {
                        workingHours.removeAll()
                    }
                    wasCustomized = true
                }
                
                if isWorkingDay {
                    // Orari
                    VStack(spacing: 12) {
                        ForEach(workingHours.indices, id: \.self) { index in
                            HStack {
                                DatePicker("", selection: Binding(
                                    get: { workingHours[index].start },
                                    set: { newValue in
                                        workingHours[index].start = newValue
                                        wasCustomized = true
                                    }
                                ), displayedComponents: .hourAndMinute)
                                Text("-")
                                DatePicker("", selection: Binding(
                                    get: { workingHours[index].end },
                                    set: { newValue in
                                        workingHours[index].end = newValue
                                        wasCustomized = true
                                    }
                                ), displayedComponents: .hourAndMinute)
                                
                                // Picker per luogo di lavoro
                                Picker("", selection: Binding(
                                    get: { workingHours[index].place },
                                    set: { newValue in
                                        workingHours[index].place = newValue
                                        wasCustomized = true
                                    }
                                )) {
                                    ForEach(WorkPlace.allCases, id: \.self) { place in
                                        Label(place.displayName, systemImage: place.icon).tag(place)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 130)
                                
                                Button(role: .destructive) {
                                    workingHours.remove(at: index)
                                    wasCustomized = true
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                            }
                        }
                        
                        Button("Aggiungi orario") {
                            let defaults = defaultWorkingHoursForCurrentDate()
                            if workingHours.count < defaults.count {
                                workingHours.append(defaults[workingHours.count])
                            } else {
                                workingHours.append(WorkingHours(
                                    start: calendar.date(from: DateComponents(hour: 9))!,
                                    end: calendar.date(from: DateComponents(hour: 13))!,
                                    place: .office
                                ))
                            }
                            wasCustomized = true
                        }
                    }
                } else {
                    TextField("", text: $note, prompt: Text("es: ferie, visita medica (nota privata)"))
                        .textFieldStyle(.roundedBorder)
                }
                
                Divider()
                
                DatePicker("Applica fino al", selection: $applyUntilDate, displayedComponents: .date)
                
                if isWorkingDay {
                    Toggle("Solo ai giorni lavorativi", isOn: $applyToWorkingDaysOnly)
                }
                
                HStack {
                    Button("Annulla") {
                        dismiss()
                    }
                    
                    Button("Salva") {
                        applyChanges()
                        dismiss()
                    }
                }
            }
            .padding()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        DateUtils.formatFull(date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func defaultWorkingHoursForCurrentDate() -> [WorkingHours] {
        let weekday = calendar.component(.weekday, from: date)
        if let schedule = scheduleManager.weekdaySchedules[weekday],
           schedule.isWorkingDay,
           !schedule.hours.isEmpty {
            return schedule.hours
        }
        
        return [
            WorkingHours(
                start: calendar.date(from: DateComponents(hour: 9))!,
                end: calendar.date(from: DateComponents(hour: 13))!,
                place: .office
            ),
            WorkingHours(
                start: calendar.date(from: DateComponents(hour: 14))!,
                end: calendar.date(from: DateComponents(hour: 18))!,
                place: .office
            )
        ]
    }
    
    private func areHoursEqual(_ hours1: [WorkingHours], _ hours2: [WorkingHours]) -> Bool {
        guard hours1.count == hours2.count else { return false }
        for (h1, h2) in zip(hours1, hours2) {
            let cal = Calendar.current
            let comp1 = cal.dateComponents([.hour, .minute], from: h1.start)
            let comp2 = cal.dateComponents([.hour, .minute], from: h2.start)
            let comp3 = cal.dateComponents([.hour, .minute], from: h1.end)
            let comp4 = cal.dateComponents([.hour, .minute], from: h2.end)
            
            if comp1.hour != comp2.hour || comp1.minute != comp2.minute ||
               comp3.hour != comp4.hour || comp3.minute != comp4.minute ||
               h1.place != h2.place {
                return false
            }
        }
        return true
    }
    
    private func applyChanges() {
        // Se stiamo passando da non lavorativo a lavorativo, assicuriamoci che la nota sia vuota
        if isWorkingDay {
            note = ""
        }
        
        print("🔄 INIZIO SALVATAGGIO MODIFICHE")
        print("📅 Data selezionata: \(formatDate(date))")
        print("👷‍♂️ Lavorativo: \(isWorkingDay)")
        print("📋 Orari: \(workingHours.map { "\(formatTime($0.start))-\(formatTime($0.end))" })")
        
        let calendar = Calendar.current
        var currentDate = date
        
        while currentDate <= applyUntilDate {
            // Processa sempre il giorno di partenza, anche se attualmente marcato come non lavorativo
            let isStartDate = calendar.isDate(currentDate, inSameDayAs: date)
            if !applyToWorkingDaysOnly || isStartDate || scheduleManager.isWorkingDay(currentDate) {
                print("\n🔄 Processando data: \(formatDate(currentDate))")
                
                // Determina gli orari da usare
                let hoursToUse: [WorkingHours]
                if isWorkingDay {
                    if workingHours.isEmpty && !wasCustomized {
                        // Se non ci sono orari personalizzati e non è stato mai personalizzato, usa quelli standard
                        hoursToUse = scheduleManager.getWorkingHours(for: currentDate)
                    } else {
                        // Usa gli orari personalizzati (anche se vuoti, se è stato personalizzato)
                        hoursToUse = workingHours.isEmpty ? scheduleManager.getWorkingHours(for: currentDate) : workingHours
                    }
                } else {
                    hoursToUse = []
                }
                
                // Se è stato personalizzato o ha orari diversi da quelli standard, salva come giorno speciale
                let weekday = calendar.component(.weekday, from: currentDate)
                let defaultSchedule = scheduleManager.weekdaySchedules[weekday]
                let hasCustomHours = wasCustomized || (isWorkingDay && !workingHours.isEmpty && defaultSchedule != nil && !areHoursEqual(workingHours, defaultSchedule!.hours))
                
                // Creiamo sempre un nuovo giorno speciale se è stato personalizzato o se è non lavorativo o se ha orari personalizzati
                if !isWorkingDay || hasCustomHours {
                    let newSpecialDay = WorkingDay(
                        id: UUID(),
                        date: currentDate,
                        isWorkingDay: isWorkingDay,
                        hours: hoursToUse,
                        note: note.isEmpty ? nil : note
                    )
                    
                    print("💾 Salvo nuovo giorno speciale:")
                    print("   🔹 ID: \(newSpecialDay.id)")
                    print("   🔹 Data: \(formatDate(newSpecialDay.date))")
                    print("   🔹 Lavorativo: \(newSpecialDay.isWorkingDay)")
                    print("   🔹 Orari: \(newSpecialDay.hours.map { "\(formatTime($0.start))-\(formatTime($0.end))" })")
                    print("   🔹 Nota: \(newSpecialDay.note ?? "nessuna")")
                    
                    // Aggiungiamo sempre il nuovo giorno speciale
                    scheduleManager.addSpecialDay(newSpecialDay)
                } else {
                    // Rimuoviamo il giorno speciale se esiste, per tornare agli orari standard
                    scheduleManager.removeSpecialDay(WorkingDay(
                        id: UUID(),
                        date: currentDate,
                        isWorkingDay: false,
                        hours: [],
                        note: nil
                    ))
                }
                
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        // Forza l'aggiornamento della vista
        scheduleManager.updateCounter += 1
        print("✅ FINE SALVATAGGIO MODIFICHE\n")
    }
}

struct CellFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?
    
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
} 