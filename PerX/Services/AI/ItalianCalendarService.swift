import Foundation

class ItalianCalendarService {
    static let shared = ItalianCalendarService()
    private let calendar = Calendar(identifier: .gregorian)
    
    private init() {}
    
    func getHolidays(for year: Int) -> [Date] {
        var holidays: [Date] = []
        
        // Festività fisse
        let fixedHolidays = [
            (1, 1),    // Capodanno
            (1, 6),    // Epifania
            (4, 25),   // Liberazione
            (5, 1),    // Festa del Lavoro
            (6, 2),    // Repubblica
            (8, 15),   // Ferragosto
            (11, 1),   // Tutti i Santi
            (12, 8),   // Immacolata
            (12, 25),  // Natale
            (12, 26)   // Santo Stefano
        ]
        
        // Aggiungi le festività fisse
        for (month, day) in fixedHolidays {
            if let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
                holidays.append(date)
            }
        }
        
        // Calcola Pasqua e aggiungi Pasqua e Pasquetta
        if let easter = calculateEaster(year: year) {
            holidays.append(easter)
            
            // Pasquetta (giorno dopo Pasqua)
            if let easterMonday = calendar.date(byAdding: .day, value: 1, to: easter) {
                holidays.append(easterMonday)
            }
        }
        
        return holidays.sorted()
    }
    
    // Algoritmo di Meeus/Jones/Butcher per calcolare la Pasqua
    private func calculateEaster(year: Int) -> Date? {
        let a = year % 19
        let b = Int(floor(Double(year) / 100))
        let c = year % 100
        let d = Int(floor(Double(b) / 4))
        let e = b % 4
        let f = Int(floor(Double(b + 8) / 25))
        let g = Int(floor(Double(b - f + 1) / 3))
        let h = (19 * a + b - d - g + 15) % 30
        let i = Int(floor(Double(c) / 4))
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = Int(floor(Double(a + 11 * h + 22 * l) / 451))
        let month = Int(floor(Double(h + l - 7 * m + 114) / 31))
        let day = ((h + l - 7 * m + 114) % 31) + 1
        
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
    
    func isHoliday(_ date: Date) -> Bool {
        let year = calendar.component(.year, from: date)
        let holidays = getHolidays(for: year)
        return holidays.contains { calendar.isDate($0, inSameDayAs: date) }
    }
    
    func getWorkingDays(in month: Date) -> Int {
        let range = calendar.range(of: .day, in: .month, for: month)!
        let year = calendar.component(.year, from: month)
        let monthNum = calendar.component(.month, from: month)
        
        let holidays = getHolidays(for: year)
        var workingDays = 0
        
        for day in range {
            if let date = calendar.date(from: DateComponents(year: year, month: monthNum, day: day)) {
                let weekday = calendar.component(.weekday, from: date)
                // Se non è weekend (1 = domenica, 7 = sabato) e non è festivo
                if weekday != 1 && weekday != 7 && !holidays.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
                    workingDays += 1
                }
            }
        }
        
        return workingDays
    }
    
    func getWorkingDaysLeft(from date: Date) -> Int {
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: date)!
        var currentDate = date
        var workingDays = 0
        
        while currentDate <= endOfMonth {
            let weekday = calendar.component(.weekday, from: currentDate)
            if weekday != 1 && weekday != 7 && !isHoliday(currentDate) {
                workingDays += 1
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return workingDays
    }
    
    func getElapsedWorkingDays(in month: Date) -> Int {
        let today = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        var currentDate = startOfMonth
        var workingDays = 0
        
        while currentDate <= today && calendar.isDate(currentDate, equalTo: month, toGranularity: .month) {
            let weekday = calendar.component(.weekday, from: currentDate)
            if weekday != 1 && weekday != 7 && !isHoliday(currentDate) {
                workingDays += 1
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return workingDays
    }
    
    /// Calcola i giorni lavorativi tra due date (esclude weekend e festività italiane)
    /// - Parameters:
    ///   - startDate: Data di inizio (esclusa dal conteggio)
    ///   - endDate: Data di fine (inclusa nel conteggio se lavorativa)
    /// - Returns: Numero di giorni lavorativi
    func getWorkingDaysBetween(from startDate: Date, to endDate: Date) -> Int {
        var currentDate = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        var workingDays = 0
        
        // Inizia dal giorno successivo alla data di inizio
        currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        
        while currentDate <= end {
            let weekday = calendar.component(.weekday, from: currentDate)
            // Se non è weekend (1 = domenica, 7 = sabato) e non è festivo
            if weekday != 1 && weekday != 7 && !isHoliday(currentDate) {
                workingDays += 1
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return workingDays
    }
    
    /// Calcola i giorni lavorativi da una data ad oggi
    /// - Parameter date: Data di inizio
    /// - Returns: Numero di giorni lavorativi da quella data ad oggi
    func getWorkingDaysSince(_ date: Date) -> Int {
        return getWorkingDaysBetween(from: date, to: Date())
    }
} 