import Foundation

struct LiquidationStats: Identifiable {
    let id = UUID()
    let company: String
    let averageUnder5k: Double
    let averageUnder10k: Double
    let averageUnder5kInPL: Double  // Media solo sinistri in PL
    let averageUnder10kInPL: Double  // Media solo sinistri in PL
    let averageUnder5kAll: Double   // Media tutti i sinistri (esclusi negativi)
    let averageUnder10kAll: Double  // Media tutti i sinistri (esclusi negativi)
    let negativePercentage: Double
    let concordatePercentage: Double  // % di sinistri concordati: [n concordate]/[chiusure totali]
    let averageGestioneDays: Double  // Tempo medio gestione in giorni (dataAssegnazione -> dataChiusura)
    let totalClaims: Int
    let sinistriSenzaDataAssegnazione: [String]  // Riferimenti dei sinistri chiusi senza dataAssegnazione
    let sinistriSenzaLiquidazione: [String]  // Riferimenti dei sinistri in PL senza importo liquidazione
    let sinistriSenzaDefinizione: [String]  // Riferimenti dei sinistri chiusi senza definizione
}

struct MonthlyLiquidationStats: Identifiable {
    let id = UUID()
    let date: Date
    let monthName: String
    let averageUnder5k: Double
    let averageUnder10k: Double
    let negativePercentage: Double
    let totalClaims: Int
}

struct DailyStat {
    let date: Date
    let closures: Int
    let reports: Int
    let assignments: Int
    let isWorkingDay: Bool
    
    init(date: Date, closures: Int, reports: Int, assignments: Int = 0, isWorkingDay: Bool = true) {
        self.date = date
        self.closures = closures
        self.reports = reports
        self.assignments = assignments
        self.isWorkingDay = isWorkingDay
    }
}

struct MonthlyBreakdownData {
    let month: Int
    let monthName: String
    let closures: Int
    let reports: Int
}

struct CompanyBreakdownData {
    let company: String
    let totalClaims: Int
    let inPLClaims: Int
    let averageLiquidation: Double
    let negativePercentage: Double
} 
