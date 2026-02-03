import Foundation

extension Date {
    /// Formatta data per liste email (usa DateUtils.formatSmart internamente)
    func formattedForEmailList() -> String {
        DateUtils.formatSmart(self)
    }

    /// Formatta data per dettaglio email (usa DateUtils.formatDetail internamente)
    func formattedForEmailDetail() -> String {
        DateUtils.formatDetail(self)
    }
}

class EmailDateParser {
    static let rfc2822Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter
    }()
    
    static func date(from rfc2822String: String) -> Date? {
        // Try the standard formatter first
        if let date = rfc2822Formatter.date(from: rfc2822String) {
            return date
        }
        // Add fallbacks for other common formats if needed
        return nil
    }
    
    // Gmail's internalDate is milliseconds since epoch
    static func date(fromInternalDate internalDateString: String) -> Date? {
        guard let timestamp = TimeInterval(internalDateString) else { return nil }
        return Date(timeIntervalSince1970: timestamp / 1000.0)
    }
} 