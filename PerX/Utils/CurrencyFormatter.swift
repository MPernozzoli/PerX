import Foundation

struct CurrencyFormatter {
    static let shared = CurrencyFormatter()
    
    private let formatter: NumberFormatter
    
    private init() {
        formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.locale = Locale(identifier: "it_IT")
    }
    
    func format(_ value: Double) -> String {
        return formatter.string(from: NSNumber(value: value)) ?? "0,00"
    }
    
    func formatWithSymbol(_ value: Double) -> String {
        return "€ \(format(value))"
    }
    
    func format(_ value: NSDecimalNumber) -> String {
        return format(value.doubleValue)
    }
    
    func formatWithSymbol(_ value: NSDecimalNumber) -> String {
        return formatWithSymbol(value.doubleValue)
    }
    
    /// Formato compatto per spazi ridotti (es. "€1,2M", "€15K", "€1,5M") - formato italiano
    func formatCompact(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.decimalSeparator = ","
        formatter.groupingSeparator = "."
        formatter.usesGroupingSeparator = true
        formatter.locale = Locale(identifier: "it_IT")
        
        if value >= 1_000_000 {
            let millions = value / 1_000_000
            return "€\(formatter.string(from: NSNumber(value: millions)) ?? "0")M"
        } else if value >= 1_000 {
            let thousands = value / 1_000
            return "€\(formatter.string(from: NSNumber(value: thousands)) ?? "0")K"
        } else {
            return formatWithSymbol(value)
        }
    }
}

