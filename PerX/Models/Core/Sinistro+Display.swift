import Foundation

extension Sinistro {
    
    /// Riferimento formattato per visualizzazione (con sigla compagnia se abilitato nelle impostazioni)
    /// Esempio: "ZUR-2500123" se abilitato, "2500123" se disabilitato
    /// NOTA: Usare solo per visualizzazione UI, NON per operazioni logiche o copia
    var riferimentoVisualizzato: String {
        let showSigla = UserDefaults.standard.bool(forKey: "includiCodiceCompagniaRiferimento")
        guard let rif = riferimento else { return "N/D" }
        
        if showSigla {
            let compagniaDetected = Compagnia.detect(gruppo: gruppo, compagnia: nomeCompagnia)
            if compagniaDetected != Compagnia.unknown {
                return "\(compagniaDetected.sigla)-\(rif)"
            }
        }
        return rif
    }
    
    // MARK: - Beni da Perxia
    
    /// Restituisce l'ultima analisi Perxia (la più recente)
    var ultimaAnalisiPerxia: PerxiaAnalisi? {
        guard let analisiSet = perxiaAnalisi as? Set<PerxiaAnalisi> else { return nil }
        return analisiSet.sorted { ($0.dataAnalisi ?? .distantPast) > ($1.dataAnalisi ?? .distantPast) }.first
    }
    
    /// Restituisce i beni dall'ultima analisi Perxia
    var beniPerxia: [PerxiaBene] {
        return ultimaAnalisiPerxia?.beniArray ?? []
    }
    
    /// Restituisce il numero totale di beni
    var numeroBeni: Int {
        return beniPerxia.count
    }
    
    // MARK: - Grado Complessità
    
    /// Enum per i livelli di complessità
    enum GradoComplessita: String, CaseIterable {
        case bassa = "Bassa"
        case media = "Media"
        case alta = "Alta"
        case moltaAlta = "Molto Alta"
        case unknown = "N/D"
        
        var color: (red: Double, green: Double, blue: Double) {
            switch self {
            case .bassa: return (0.2, 0.7, 0.3)       // Verde
            case .media: return (0.95, 0.75, 0.1)    // Giallo/Oro
            case .alta: return (0.95, 0.5, 0.1)      // Arancione
            case .moltaAlta: return (0.9, 0.2, 0.2)  // Rosso
            case .unknown: return (0.5, 0.5, 0.5)    // Grigio
            }
        }
        
        static func from(_ string: String?) -> GradoComplessita {
            guard let str = string?.lowercased() else { return .unknown }
            if str.contains("molto") && str.contains("alta") { return .moltaAlta }
            if str.contains("alta") { return .alta }
            if str.contains("media") { return .media }
            if str.contains("bassa") { return .bassa }
            return .unknown
        }
    }
    
    /// Restituisce il grado di complessità come enum
    var gradoComplessita: GradoComplessita {
        return GradoComplessita.from(complessita)
    }
    
    // MARK: - Anno Sinistro (da riferimento)
    
    /// Estrae l'anno del sinistro dalle prime 2 cifre numeriche del riferimento
    /// Es: "2515538" → 2025, "25/15538" → 2025, "2400123" → 2024
    var annoSinistro: Int? {
        guard let rif = riferimento else { return nil }
        
        // Estrai le prime 2 cifre numeriche consecutive
        var digits = ""
        for char in rif {
            if char.isNumber {
                digits.append(char)
                if digits.count == 2 {
                    break
                }
            }
        }
        
        guard digits.count == 2, let yy = Int(digits) else { return nil }
        return 2000 + yy
    }
    
    /// Verifica se il sinistro è "recente" (anno corrente o anno precedente)
    var isRecente: Bool {
        guard let anno = annoSinistro else { return false }
        let currentYear = Calendar.current.component(.year, from: Date())
        return anno == currentYear || anno == currentYear - 1
    }
}

