//
//  iPadTypeBridge.swift
//  PerX per iPad
//
//  Utility condivise specifiche per iPad
//

import Foundation

// MARK: - Calendar Extensions per iPad
extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
    
    func endOfMonth(for date: Date) -> Date {
        guard let startOfMonth = self.date(from: dateComponents([.year, .month], from: date)),
              let nextMonth = self.date(byAdding: .month, value: 1, to: startOfMonth) else {
            return date
        }
        return self.date(byAdding: .day, value: -1, to: nextMonth) ?? date
    }
}
