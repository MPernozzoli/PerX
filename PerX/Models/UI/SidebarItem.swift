import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case sinistri = "Sinistri"
    case comunicazioni = "Comunicazioni"
    case team = "Team"
    case studio = "Studio"
    case programmazione = "Programmazione"
    case consuntivo = "Consuntivo"
    case impostazioni = "Impostazioni"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .dashboard: return "gauge"
        case .sinistri: return "folder"
        case .comunicazioni: return "envelope"
        case .team: return "person.3"
        case .studio: return "building.2"
        case .programmazione: return "calendar.badge.clock"
        case .consuntivo: return "chart.bar"
        case .impostazioni: return "gear"
        }
    }
    
    static var mainItems: [SidebarItem] {
        [.dashboard, .sinistri, .comunicazioni, .team, .studio, .programmazione, .consuntivo]
    }
}
