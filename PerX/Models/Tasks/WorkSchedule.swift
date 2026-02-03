import Foundation

/// Luogo di lavoro per una fascia oraria
enum WorkPlace: String, Codable, CaseIterable, Equatable {
    case office = "office"   // Ufficio
    case remote = "remote"   // Da remoto / casa
    
    var displayName: String {
        switch self {
        case .office: return "Ufficio"
        case .remote: return "Da remoto"
        }
    }
    
    var icon: String {
        switch self {
        case .office: return "building.2"
        case .remote: return "house"
        }
    }
}

struct WorkingHours: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Date
    var end: Date
    var place: WorkPlace
    
    // Inizializzatore con default per retrocompatibilità
    init(id: UUID = UUID(), start: Date, end: Date, place: WorkPlace = .office) {
        self.id = id
        self.start = start
        self.end = end
        self.place = place
    }
    
    // Decodifica con fallback per dati esistenti senza "place"
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        place = try container.decodeIfPresent(WorkPlace.self, forKey: .place) ?? .office
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, start, end, place
    }
    
    static func == (lhs: WorkingHours, rhs: WorkingHours) -> Bool {
        lhs.id == rhs.id &&
        lhs.start == rhs.start &&
        lhs.end == rhs.end &&
        lhs.place == rhs.place
    }
}

struct WorkingDay: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var isWorkingDay: Bool
    var hours: [WorkingHours]
    var note: String?
    
    static func == (lhs: WorkingDay, rhs: WorkingDay) -> Bool {
        lhs.id == rhs.id &&
        lhs.date == rhs.date &&
        lhs.isWorkingDay == rhs.isWorkingDay &&
        lhs.hours == rhs.hours &&
        lhs.note == rhs.note
    }
}

struct WeekdaySchedule: Codable, Equatable {
    var isWorkingDay: Bool
    var hours: [WorkingHours]
    
    static func == (lhs: WeekdaySchedule, rhs: WeekdaySchedule) -> Bool {
        lhs.isWorkingDay == rhs.isWorkingDay &&
        lhs.hours == rhs.hours
    }
}

class WorkScheduleManager: ObservableObject {
    // MARK: - Singleton
    static let shared = WorkScheduleManager()
    
    @Published var weekdaySchedules: [Int: WeekdaySchedule]
    @Published var specialDays: [WorkingDay]
    @Published var updateCounter: Int = 0
    private let calendar = Calendar.current
    private let calendarService = ItalianCalendarService.shared
    @Published var monthlyTargets: [String: Int] = [:] // Chiave: "YYYY-MM", Valore: obiettivo
    
    private var cloudKitObserver: NSObjectProtocol?
    
    private init() {
        // Inizializza le variabili
        self.weekdaySchedules = [:]
        self.specialDays = []
        
        // Carica le impostazioni salvate
        loadFromDefaults()
        
        // Sottoscrivi alla notifica CloudKit per ricaricare quando i settings vengono aggiornati
        cloudKitObserver = NotificationCenter.default.addObserver(
            forName: NotificationNames.cloudKitSettingsUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Verifica se le chiavi aggiornate includono WorkSchedule
            if let keys = notification.userInfo?["keys"] as? [String],
               keys.contains(where: { $0.hasPrefix("weekdaySchedules") || $0.hasPrefix("specialDays") || $0.hasPrefix("monthlyTargets") }) {
                self?.reloadFromDefaults()
            } else if notification.userInfo?["keys"] == nil {
                // Se non ci sono chiavi specifiche, ricarica sempre
                self?.reloadFromDefaults()
            }
        }
    }
    
    deinit {
        if let observer = cloudKitObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Ricarica tutti i dati da UserDefaults (chiamato dopo sync CloudKit)
    func reloadFromDefaults() {
        print("[WorkScheduleManager] 🔄 Ricaricamento da UserDefaults dopo sync CloudKit")
        loadFromDefaults()
        updateCounter += 1
        objectWillChange.send()
    }
    
    private func loadFromDefaults() {
        if let saved = UserDefaults.standard.data(forKey: "weekdaySchedules"),
           let decoded = try? JSONDecoder().decode([Int: WeekdaySchedule].self, from: saved) {
            weekdaySchedules = decoded
        } else if weekdaySchedules.isEmpty {
            // Default: Lun-Ven, 9-13 e 14-18 (ufficio)
            let defaultHours = [
                WorkingHours(
                    start: calendar.date(from: DateComponents(hour: 9, minute: 0))!,
                    end: calendar.date(from: DateComponents(hour: 13, minute: 0))!,
                    place: .office
                ),
                WorkingHours(
                    start: calendar.date(from: DateComponents(hour: 14, minute: 0))!,
                    end: calendar.date(from: DateComponents(hour: 18, minute: 0))!,
                    place: .office
                )
            ]
            
            for weekday in 2...6 { // Lunedì a Venerdì
                weekdaySchedules[weekday] = WeekdaySchedule(
                    isWorkingDay: true,
                    hours: defaultHours
                )
            }
            // Sabato e Domenica non lavorativi
            weekdaySchedules[1] = WeekdaySchedule(isWorkingDay: false, hours: [])
            weekdaySchedules[7] = WeekdaySchedule(isWorkingDay: false, hours: [])
        }
        
        if let saved = UserDefaults.standard.data(forKey: "specialDays"),
           let decoded = try? JSONDecoder().decode([WorkingDay].self, from: saved) {
            specialDays = decoded
        }
        
        // Carica gli obiettivi mensili
        if let savedTargets = UserDefaults.standard.data(forKey: "monthlyTargets"),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: savedTargets) {
            monthlyTargets = decoded
        }
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(weekdaySchedules) {
            UserDefaults.standard.set(encoded, forKey: "weekdaySchedules")
        }
        if let encoded = try? JSONEncoder().encode(specialDays) {
            UserDefaults.standard.set(encoded, forKey: "specialDays")
        }
        if let encoded = try? JSONEncoder().encode(monthlyTargets) {
            UserDefaults.standard.set(encoded, forKey: "monthlyTargets")
        }
        
        // Notifica che gli orari sono cambiati per aggiornare il calendario
        print("[WorkScheduleManager] 📢 Invio notifica workScheduleChanged")
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .workScheduleChanged, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .workScheduleChanged, object: nil)
            }
        }
    }
    
    func isWorkingDay(_ date: Date) -> Bool {
        // Prima controlla se è una festività nazionale
        if calendarService.isHoliday(date) {
            return false
        }
        
        // Poi controlla se è un giorno speciale
        if let specialDay = specialDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            return specialDay.isWorkingDay
        }
        
        // Infine usa la programmazione settimanale
        let weekday = calendar.component(.weekday, from: date)
        return weekdaySchedules[weekday]?.isWorkingDay ?? false
    }
    
    func addSpecialDay(_ day: WorkingDay) {
        print("\n📥 INIZIO AGGIUNTA/MODIFICA GIORNO SPECIALE")
        print("📅 Data: \(formatDate(day.date))")
        print("👷‍♂️ Lavorativo: \(day.isWorkingDay)")
        
        // Prima rimuoviamo SEMPRE il giorno speciale esistente
        specialDays.removeAll { calendar.isDate($0.date, inSameDayAs: day.date) }
        print("🗑️ Rimosso eventuale giorno speciale esistente")
        
        // Se è lavorativo e non ha orari personalizzati, controlla se gli orari sono diversi da quelli standard
        if day.isWorkingDay && day.hours.isEmpty {
            let weekday = calendar.component(.weekday, from: day.date)
            if let defaultSchedule = weekdaySchedules[weekday] {
                print("✨ Giorno lavorativo con orari standard - nessun giorno speciale necessario")
                updateCounter += 1
                objectWillChange.send()
                save()
                return
            }
        }
        
        // Se è lavorativo con orari, verifica se sono diversi da quelli standard
        if day.isWorkingDay && !day.hours.isEmpty {
            let weekday = calendar.component(.weekday, from: day.date)
            if let defaultSchedule = weekdaySchedules[weekday],
               defaultSchedule.isWorkingDay,
               areHoursEqual(day.hours, defaultSchedule.hours) {
                // Gli orari sono uguali a quelli standard, non serve salvare come giorno speciale
                print("✨ Giorno lavorativo con orari identici a quelli standard - nessun giorno speciale necessario")
                updateCounter += 1
                objectWillChange.send()
                save()
                return
            }
        }
        
        // In tutti gli altri casi, aggiungiamo il giorno speciale
        specialDays.append(day)
        print("➕ Aggiunto nuovo giorno speciale:")
        print("   🔹 Lavorativo: \(day.isWorkingDay)")
        print("   🔹 Orari: \(day.hours.map { "\(formatTime($0.start))-\(formatTime($0.end))" })")
        print("   🔹 Nota: \(day.note ?? "nessuna")")
        
        updateCounter += 1
        objectWillChange.send()
        save()
        print("💾 Modifiche salvate")
        print("✅ FINE AGGIUNTA/MODIFICA GIORNO SPECIALE\n")
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    func updateSpecialDay(_ day: WorkingDay) {
        // Aggiorna o aggiungi sempre, senza condizioni
        if let index = specialDays.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: day.date) }) {
            specialDays[index] = day
        } else {
            specialDays.append(day)
        }
        
        save()
    }
    
    func removeSpecialDay(_ day: WorkingDay) {
        specialDays.removeAll { calendar.isDate($0.date, inSameDayAs: day.date) }
        objectWillChange.send()
        save()
    }
    
    func updateDefaultSchedule(from date: Date, weekday: Int, schedule: WeekdaySchedule) {
        // Salva il nuovo orario predefinito
        weekdaySchedules[weekday] = schedule
        
        // Aggiorna tutti i giorni futuri che non sono giorni speciali
        let calendar = Calendar.current
        var currentDate = date
        let endOfYear = calendar.date(byAdding: .year, value: 1, to: date)!
        
        while currentDate <= endOfYear {
            let currentWeekday = calendar.component(.weekday, from: currentDate)
            
            // Se è lo stesso giorno della settimana e non è un giorno speciale
            if currentWeekday == weekday && !specialDays.contains(where: { calendar.isDate($0.date, inSameDayAs: currentDate) }) {
                // Non fare nulla, lascia che venga usato l'orario predefinito
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        objectWillChange.send()
        updateCounter += 1
        save()
    }
    
    var currentUpdateId: UUID {
        UUID()
    }
    
    func getWorkingHours(for date: Date) -> [WorkingHours] {
        // Prima controlla se è un giorno speciale (priorità massima)
        if let specialDay = specialDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            return specialDay.hours
        }
        
        // Se è un giorno lavorativo standard, usa gli orari di default
        if isWorkingDay(date) {
            let weekday = calendar.component(.weekday, from: date)
            return weekdaySchedules[weekday]?.hours ?? []
        }
        
        return []
    }
    
    func calculateStandardHoursPerDay() -> Double {
        var totalWeeklyHours = 0.0
        var workingDaysCount = 0
        
        for weekday in 2...6 { // Lunedì a Venerdì
            if let schedule = weekdaySchedules[weekday], schedule.isWorkingDay {
                workingDaysCount += 1
                totalWeeklyHours += schedule.hours.reduce(0) { total, hours in
                    total + hours.end.timeIntervalSince(hours.start) / 3600
                }
            }
        }
        
        return workingDaysCount > 0 ? totalWeeklyHours / Double(workingDaysCount) : 8.0
    }
    
    func calculateWorkedHours(upTo date: Date, from startDate: Date) -> Double {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate))!
        let endDate = min(date, calendar.date(byAdding: .month, value: 1, to: startOfMonth)!)
        
        var currentDate = startOfMonth
        var totalHours = 0.0
        
        while currentDate < endDate {
            if let specialDay = specialDays.first(where: { calendar.isDate($0.date, inSameDayAs: currentDate) }) {
                if specialDay.isWorkingDay {
                    totalHours += specialDay.hours.reduce(0) { total, hours in
                        total + hours.end.timeIntervalSince(hours.start) / 3600
                    }
                }
            } else if isWorkingDay(currentDate) {
                let weekday = calendar.component(.weekday, from: currentDate)
                if let schedule = weekdaySchedules[weekday] {
                    totalHours += schedule.hours.reduce(0) { total, hours in
                        total + hours.end.timeIntervalSince(hours.start) / 3600
                    }
                }
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return totalHours
    }
    
    func calculateTotalMonthHours(for date: Date) -> Double {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
        
        return calculateWorkedHours(upTo: endOfMonth, from: startOfMonth)
    }
    
    var monthlyHours: Double {
        calculateTotalMonthHours(for: Date())
    }
    
    func countWorkingDays() -> Int {
        let calendar = Calendar.current
        let startOfMonth = calendar.startOfMonth(for: Date())
        let endOfMonth = calendar.endOfMonth(for: Date())
        
        var currentDate = startOfMonth
        var count = 0
        
        while currentDate <= endOfMonth {
            if isWorkingDay(currentDate) {
                count += 1
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return count
    }
    
    func remainingWorkingDays(from: Date, in month: Date) -> Int {
        let calendar = Calendar.current
        let endOfMonth = calendar.endOfMonth(for: month)
        
        var currentDate = from
        var count = 0
        
        while currentDate <= endOfMonth {
            if isWorkingDay(currentDate) {
                count += 1
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return count
    }
    
    func setMonthlyTarget(_ target: Int, for date: Date) {
        let key = monthKey(for: date)
        print("📊 Salvataggio obiettivo mensile:")
        print("   📅 Mese: \(key)")
        print("   🎯 Obiettivo: \(target)")
        monthlyTargets[key] = target
        saveMonthlyTargets()
        save()
        print("✅ Obiettivo salvato")
    }
    
    func getMonthlyTarget(for date: Date) -> Int {
        let key = monthKey(for: date)
        return monthlyTargets[key] ?? 0
    }
    
    private func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
    
    private func saveMonthlyTargets() {
        if let encoded = try? JSONEncoder().encode(monthlyTargets) {
            UserDefaults.standard.set(encoded, forKey: "monthlyTargets")
        }
    }
    
    func countWorkingDaysInPeriod(from startDate: Date, to endDate: Date) -> Int {
        var currentDate = startDate
        var count = 0
        
        while currentDate <= endDate {
            if isWorkingDay(currentDate) {
                count += 1
            }
            currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return count
    }
    
    func requiredDailyClosures(target: Int, currentCount: Int, from: Date, in month: Date) -> Double {
        let remainingDays = remainingWorkingDays(from: from, in: month)
        guard remainingDays > 0 else { return 0 }
        let remaining = max(0, target - currentCount)
        return Double(remaining) / Double(remainingDays)
    }
    
    func calculateWorkedHoursUpToNow(in date: Date) -> Double {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.startOfMonth(for: date)
        
        // Se non siamo nel mese corrente, ritorna 0 o il totale delle ore
        if !calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return calculateTotalMonthHours(for: date)
        }
        
        var totalHours = 0.0
        var currentDate = startOfMonth
        
        while currentDate <= now {
            if let specialDay = specialDays.first(where: { calendar.isDate($0.date, inSameDayAs: currentDate) }) {
                if specialDay.isWorkingDay {
                    if calendar.isDate(currentDate, inSameDayAs: now) {
                        // Per oggi, conta solo le ore fino all'ora corrente
                        totalHours += specialDay.hours.reduce(0) { total, hours in
                            let endTime = min(hours.end, now)
                            if endTime > hours.start {
                                return total + endTime.timeIntervalSince(hours.start) / 3600
                            }
                            return total
                        }
                    } else {
                        // Per i giorni precedenti, conta tutte le ore
                        totalHours += specialDay.hours.reduce(0) { total, hours in
                            total + hours.end.timeIntervalSince(hours.start) / 3600
                        }
                    }
                }
            } else if isWorkingDay(currentDate) {
                let weekday = calendar.component(.weekday, from: currentDate)
                if let schedule = weekdaySchedules[weekday] {
                    if calendar.isDate(currentDate, inSameDayAs: now) {
                        // Per oggi, conta solo le ore fino all'ora corrente
                        totalHours += schedule.hours.reduce(0) { total, hours in
                            let endTime = min(hours.end, now)
                            if endTime > hours.start {
                                return total + endTime.timeIntervalSince(hours.start) / 3600
                            }
                            return total
                        }
                    } else {
                        // Per i giorni precedenti, conta tutte le ore
                        totalHours += schedule.hours.reduce(0) { total, hours in
                            total + hours.end.timeIntervalSince(hours.start) / 3600
                        }
                    }
                }
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return totalHours
    }
    
    // MARK: - Task System Support
    
    /// Conta giorni lavorativi tra due date (alias di countWorkingDaysInPeriod)
    /// Usato da BaseTaskGenerator per logica solleciti temporizzati
    func countWorkingDays(from startDate: Date, to endDate: Date) -> Int {
        return countWorkingDaysInPeriod(from: startDate, to: endDate)
    }
    
    /// Giorni lavorativi fino a fine mese corrente
    /// Usato da BaseTaskGenerator per decisioni su solleciti e concordati verbali
    func workingDaysUntilEndOfMonth(from date: Date) -> Int {
        let calendar = Calendar.current
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: calendar.startOfDay(for: date))!
        return countWorkingDays(from: date, to: endOfMonth)
    }
} 