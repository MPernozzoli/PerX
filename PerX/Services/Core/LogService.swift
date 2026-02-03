import Foundation
import SwiftUI

class LogService: ObservableObject {
    @Published var logs: [LogEntry] = []
    
    func addLog(_ type: LogType, message: String) {
        let entry = LogEntry(type: type, message: message, timestamp: Date())
        DispatchQueue.main.async {
            self.logs.append(entry)
            // Manteniamo solo gli ultimi 1000 log
            if self.logs.count > 1000 {
                self.logs.removeFirst()
            }
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let type: LogType
    let message: String
    let timestamp: Date
}

enum LogType {
    case info
    case warning
    case error
    
    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .yellow
        case .error: return .red
        }
    }
} 