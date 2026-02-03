import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case sinistri = "Sinistri"
    case comunicazioni = "Comunicazioni"
    case consuntivo = "Consuntivo"
    case impostazioni = "Impostazioni"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .dashboard: return "gauge"
        case .sinistri: return "folder"
        case .comunicazioni: return "envelope"
        case .consuntivo: return "chart.bar"
        case .impostazioni: return "gear"
        }
    }
    
    static var mainItems: [SidebarItem] {
        [.dashboard, .sinistri, .comunicazioni]
    }
} 