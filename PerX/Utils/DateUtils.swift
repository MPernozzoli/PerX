import Foundation

// MARK: - Calendar Extensions

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
    
    func endOfMonth(for date: Date) -> Date {
        var components = DateComponents()
        components.month = 1
        components.second = -1
        return self.date(byAdding: components, to: startOfMonth(for: date)) ?? date
    }
    
    func daysInMonth(_ date: Date) -> Int {
        let range = self.range(of: .day, in: .month, for: date)
        return range?.count ?? 0
    }
}

// MARK: - Locale

extension Locale {
    /// Locale italiano per la formattazione di date e numeri
    static let italian = Locale(identifier: "it_IT")
}

// MARK: - DateUtils

/// Utility centralizzate per la formattazione delle date.
/// Sostituisce le implementazioni duplicate in 15+ file.
enum DateUtils {
    
    // MARK: - Pre-configured Formatters (Cached)
    
    /// Formatter per date brevi (es. "01/02/25")
    static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.locale = .italian
        return formatter
    }()
    
    /// Formatter per date complete (es. "Lunedì 1 Febbraio 2025")
    static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.locale = .italian
        return formatter
    }()
    
    /// Formatter per mese e anno (es. "Febbraio 2025")
    static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = .italian
        return formatter
    }()
    
    /// Formatter per giorno settimana (es. "Lunedì")
    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = .italian
        return formatter
    }()
    
    /// Formatter per data dettagliata con ora (es. "01 Febbraio 2025 alle 14:30")
    static let detailFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMMM yyyy 'alle' HH:mm"
        formatter.locale = .italian
        return formatter
    }()
    
    /// Formatter per solo ora (es. "14:30")
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = .italian
        return formatter
    }()
    
    /// Formatter per data semplice (es. "01/02/2025")
    static let simpleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.locale = .italian
        return formatter
    }()
    
    /// Formatter per data media (es. "1 feb 2025")
    static let mediumFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = .italian
        return formatter
    }()
    
    /// Formatter per data lunga (es. "1 febbraio 2025")
    static let longFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = .italian
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        return formatter
    }()
    
    /// Formatter per data media con ora (es. "1 feb 2025, 14:30")
    static let mediumWithTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .italian
        return formatter
    }()
    
    /// Formatter per data breve con ora relativa (es. "oggi, 14:30")
    static let relativeWithTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = .italian
        return formatter
    }()
    
    /// Formatter per data breve dd/MM/yy (es. "01/02/25")
    static let shortYYFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy"
        formatter.locale = .italian
        return formatter
    }()
    
    // MARK: - Formatting Functions
    
    /// Formatta data in formato breve (es. "01/02/25")
    static func formatShort(_ date: Date) -> String {
        shortFormatter.string(from: date)
    }
    
    /// Formatta data in formato completo (es. "Lunedì 1 Febbraio 2025")
    static func formatFull(_ date: Date) -> String {
        fullFormatter.string(from: date).capitalized
    }
    
    /// Formatta data con mese e anno (es. "Febbraio 2025")
    static func formatMonthYear(_ date: Date) -> String {
        monthYearFormatter.string(from: date).capitalized
    }
    
    /// Formatta data in modo intelligente per liste email/messaggi.
    /// - Oggi: mostra l'ora (es. "14:30")
    /// - Ieri: mostra "Ieri"
    /// - Ultima settimana: mostra il giorno (es. "Martedì")
    /// - Altrimenti: mostra la data breve (es. "01/02/25")
    static func formatSmart(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Ieri"
        } else if let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()), date > sevenDaysAgo {
            return weekdayFormatter.string(from: date)
        } else {
            return shortFormatter.string(from: date)
        }
    }
    
    /// Formatta data per dettaglio email (es. "01 Febbraio 2025 alle 14:30")
    static func formatDetail(_ date: Date) -> String {
        detailFormatter.string(from: date)
    }
    
    /// Formatta data relativa (es. "2 ore fa", "ieri")
    static func formatRelative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = .italian
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    /// Formatta data con formato completo (es. "Lunedì 1 Febbraio 2025")
    /// Alias per backward compatibility
    static func formatDate(_ date: Date) -> String {
        formatFull(date)
    }
    
    /// Formatta data in formato lungo (es. "1 febbraio 2025")
    static func formatLong(_ date: Date) -> String {
        longFormatter.string(from: date)
    }
    
    /// Formatta data in formato medio (es. "1 feb 2025")
    static func formatMedium(_ date: Date) -> String {
        mediumFormatter.string(from: date)
    }
    
    /// Formatta data in formato medio con ora (es. "1 feb 2025, 14:30")
    static func formatMediumWithTime(_ date: Date) -> String {
        mediumWithTimeFormatter.string(from: date)
    }
    
    /// Formatta data relativa con ora (es. "oggi, 14:30")
    static func formatRelativeWithTime(_ date: Date) -> String {
        relativeWithTimeFormatter.string(from: date)
    }
    
    /// Formatta data breve dd/MM/yy (es. "01/02/25")
    static func formatShortYY(_ date: Date) -> String {
        shortYYFormatter.string(from: date)
    }
} 