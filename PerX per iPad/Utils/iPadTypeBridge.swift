//
//  iPadTypeBridge.swift
//  PerX per iPad
//
//  Typealias e tipi necessari per iPad che sono definiti altrove su macOS
//

import Foundation
import SwiftUI

// MARK: - StatoSinistro Bridge
// StatoSinistro è definito in StatoManager, questo typealias lo rende accessibile
typealias StatoSinistro = StatoManager.StatoSinistro

// MARK: - PriorityLevel per iPad
enum PriorityLevel: Int, CaseIterable, Codable {
    case bassa = 1
    case media = 2
    case alta = 3
    case urgente = 4
    
    var descrizione: String {
        switch self {
        case .bassa: return "Bassa"
        case .media: return "Media"
        case .alta: return "Alta"
        case .urgente: return "Urgente"
        }
    }
    
    var color: Color {
        switch self {
        case .bassa: return .green
        case .media: return .yellow
        case .alta: return .orange
        case .urgente: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .bassa: return "arrow.down.circle"
        case .media: return "minus.circle"
        case .alta: return "arrow.up.circle"
        case .urgente: return "exclamationmark.circle"
        }
    }
    
    static func from(value: Double) -> PriorityLevel {
        switch value {
        case ..<2: return .bassa
        case 2..<3: return .media
        case 3..<4: return .alta
        default: return .urgente
        }
    }
}

// MARK: - GradoComplessita per iPad
enum GradoComplessita: String, CaseIterable, Codable {
    case semplice = "Semplice"
    case media = "Media"
    case complessa = "Complessa"
    case moltocomplessa = "Molto Complessa"
    
    var color: Color {
        switch self {
        case .semplice: return .green
        case .media: return .yellow
        case .complessa: return .orange
        case .moltocomplessa: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .semplice: return "1.circle"
        case .media: return "2.circle"
        case .complessa: return "3.circle"
        case .moltocomplessa: return "4.circle"
        }
    }
    
    static func from(value: String?) -> GradoComplessita? {
        guard let value = value else { return nil }
        return GradoComplessita(rawValue: value)
    }
}

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
