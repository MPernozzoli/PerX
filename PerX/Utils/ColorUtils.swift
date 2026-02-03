import SwiftUI

enum ColorUtils {
    static func getDailyAverageColor(_ average: Double) -> Color {
        if average >= 10.0 {
            return .green
        } else if average >= 5.0 {
            return .yellow
        } else {
            return .red
        }
    }
    
    static func getLiquidationColor(_ value: Double) -> Color {
        if value >= 500 && value <= 800 {
            return .green
        } else if (value >= 300 && value < 500) || (value > 800 && value <= 1000) {
            return .yellow
        } else {
            return .red
        }
    }
    
    static func getHoursPerClaimColor(_ hours: Double) -> Color {
        if hours <= 1.0 {
            return .green
        } else if hours <= 2.0 {
            return .yellow
        } else {
            return .red
        }
    }
    
    static func getRequiredClosuresColor(_ required: Double, historicalAverage: Double) -> Color {
        if required <= historicalAverage {
            return .green
        } else if required <= historicalAverage * 1.3 { // 30% in più della media
            return .yellow
        } else {
            return .red
        }
    }
} 