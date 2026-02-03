import Foundation

enum FatturatoDisplayMode: String, Codable {
    case base = "base" // Solo base + fasce
    case conBonus = "con_bonus" // Base + fasce + bonus
    case lordoStimato = "lordo_stimato" // Base + fasce + bonus + marca da bollo + rivalsa
    
    var description: String {
        switch self {
        case .base:
            return "Fatturato Sinistri"
        case .conBonus:
            return "Fatturato comprensivo di Bonus"
        case .lordoStimato:
            return "Fatturato Lordo Stimato"
        }
    }
}

