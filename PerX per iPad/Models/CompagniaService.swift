//
//  CompagniaService.swift
//  PerX per iPad
//
//  Helper di riconoscimento per i tipi definiti in RubricaModels.swift
//

import Foundation

extension GruppoAssicurativo {
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

    var shortLabel: String {
        switch self {
        case .zurich: return "Zurich"
        case .generali: return "Generali"
        case .unipolSai: return "Unipol"
        case .unknown: return "Altro"
        }
    }
}

extension Compagnia {
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
}
