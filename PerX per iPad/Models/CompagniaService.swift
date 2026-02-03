//
//  CompagniaService.swift
//  PerX per iPad
//
//  Riconoscimento compagnie assicurative per sigla riferimento
//

import Foundation
import SwiftUI

// MARK: - Gruppi Assicurativi

enum GruppoAssicurativo: String, CaseIterable, Codable {
    case zurich = "Zurich Group"
    case generali = "Generali"
    case unipolSai = "UnipolSai"
    case unknown = "Altro"
    
    static func from(nomeGruppo: String?) -> GruppoAssicurativo {
        guard let nome = nomeGruppo?.lowercased() else { return .unknown }
        
        if nome.contains("zurich") {
            return .zurich
        } else if nome.contains("generali") || nome.contains("cattolica") {
            return .generali
        } else if nome.contains("unipol") {
            return .unipolSai
        }
        return .unknown
    }
    
    var compagnie: [Compagnia] {
        switch self {
        case .zurich:
            return [.zurichItalia]
        case .generali:
            return [.cattolica, .generaliItalia]
        case .unipolSai:
            return [.unipolItalia]
        case .unknown:
            return []
        }
    }
    
    var color: Color {
        switch self {
        case .zurich: return Color(red: 0.0, green: 0.47, blue: 0.78)
        case .generali: return Color(red: 0.77, green: 0.12, blue: 0.23)
        case .unipolSai: return Color(red: 0.0, green: 0.44, blue: 0.25)
        case .unknown: return .gray
        }
    }
    
    var shortLabel: String {
        switch self {
        case .zurich: return "Zurich"
        case .generali: return "Generali"
        case .unipolSai: return "Unipol"
        case .unknown: return "Altro"
        }
    }
}

// MARK: - Compagnie

enum Compagnia: String, CaseIterable, Codable {
    case zurichItalia = "Zurich Italia"
    case cattolica = "Cattolica"
    case generaliItalia = "Generali Italia"
    case unipolItalia = "Unipol Italia"
    case unknown = "Altro"
    
    static func from(nomeCompagnia: String?) -> Compagnia {
        guard let nome = nomeCompagnia?.lowercased() else { return .unknown }
        
        if nome.contains("zurich") && nome.contains("italia") {
            return .zurichItalia
        } else if nome.contains("cattolica") {
            return .cattolica
        } else if nome.contains("generali") && nome.contains("italia") {
            return .generaliItalia
        } else if nome.contains("unipol") && nome.contains("italia") {
            return .unipolItalia
        }
        return .unknown
    }
    
    /// Determina la compagnia prima dal gruppo, poi dal nome compagnia
    static func detect(gruppo: String?, compagnia: String?) -> Compagnia {
        let gruppoRiconosciuto = GruppoAssicurativo.from(nomeGruppo: gruppo)
        
        if gruppoRiconosciuto.compagnie.count == 1 {
            return gruppoRiconosciuto.compagnie[0]
        }
        
        return from(nomeCompagnia: compagnia)
    }
    
    var sigla: String {
        switch self {
        case .zurichItalia: return "ZUR"
        case .cattolica: return "CAT"
        case .generaliItalia: return "GEN"
        case .unipolItalia: return "UNI"
        case .unknown: return ""
        }
    }
    
    var gruppo: GruppoAssicurativo {
        switch self {
        case .zurichItalia: return .zurich
        case .cattolica, .generaliItalia: return .generali
        case .unipolItalia: return .unipolSai
        case .unknown: return .unknown
        }
    }
    
    var color: Color {
        switch self {
        case .zurichItalia: return Color(red: 0.0, green: 0.47, blue: 0.78)
        case .cattolica: return Color(red: 0.85, green: 0.55, blue: 0.0)
        case .generaliItalia: return Color(red: 0.77, green: 0.12, blue: 0.23)
        case .unipolItalia: return Color(red: 0.0, green: 0.44, blue: 0.25)
        case .unknown: return .gray
        }
    }
}
