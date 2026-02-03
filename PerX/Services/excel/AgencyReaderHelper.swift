import Foundation

class AgencyReaderHelper {
    static let shared = AgencyReaderHelper()
    
    private init() {}
    
    // MARK: - Legacy CompagniaType (per compatibilità)
    // NOTA: Usa CompagniaService.Compagnia per il nuovo codice
    
    enum CompagniaType {
        case cattolica
        case generaliItalia
        case zurichItalia
        case unknown
        
        static func from(nomeCompagnia: String?) -> CompagniaType {
            let compagnia = Compagnia.from(nomeCompagnia: nomeCompagnia)
            switch compagnia {
            case .cattolica: return .cattolica
            case .generaliItalia: return .generaliItalia
            case .zurichItalia: return .zurichItalia
            default: return .unknown
            }
        }
        
        /// Converte in Compagnia per usare CompagniaService
        var toCompagnia: Compagnia {
            switch self {
            case .cattolica: return .cattolica
            case .generaliItalia: return .generaliItalia
            case .zurichItalia: return .zurichItalia
            case .unknown: return .unknown
            }
        }
    }
    
    struct ParsedAgenzia {
        let codice: String
        let nome: String
    }
    
    /// Estrae codice e nome agenzia in base al tipo di compagnia
    /// Formato standard: [CODICE 3 char alfanumerici][NOME senza separatore]
    /// - codice: sempre in UPPERCASE
    /// - nome: sempre in Title Case (iniziali maiuscole)
    func parseAgenzia(_ agenziaFull: String, compagnia: String?) -> ParsedAgenzia {
        let compagniaType = Compagnia.from(nomeCompagnia: compagnia)
        let trimmed = agenziaFull.trimmingCharacters(in: .whitespaces)
        
        switch compagniaType {
        case .cattolica, .generaliItalia:
            // Formato: primi 3 caratteri = codice, resto = nome
            if trimmed.count >= 3 {
                let codice = String(trimmed.prefix(3)).uppercased()
                let nomeRaw = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                return ParsedAgenzia(codice: codice, nome: titleCase(nomeRaw))
            } else {
                return ParsedAgenzia(codice: "", nome: titleCase(trimmed))
            }
            
        case .zurichItalia:
            // Formato: "0305 - Reccagni Paolo" o "0305-Reccagni Paolo"
            // Il codice è la parte numerica all'inizio, il resto è il nome
            let pattern = #"^(\d+)\s*[-–—]\s*(.+)$"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)) {
                
                if let codiceRange = Range(match.range(at: 1), in: trimmed),
                   let nomeRange = Range(match.range(at: 2), in: trimmed) {
                    let codice = String(trimmed[codiceRange]).uppercased()
                    let nomeRaw = String(trimmed[nomeRange]).trimmingCharacters(in: .whitespaces)
                    return ParsedAgenzia(codice: codice, nome: titleCase(nomeRaw))
                }
            }
            
            // Fallback: se inizia con numeri, prendi quelli come codice
            if let match = trimmed.range(of: #"^\d+"#, options: .regularExpression) {
                let codice = String(trimmed[match]).uppercased()
                let nomeRaw = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                return ParsedAgenzia(codice: codice, nome: titleCase(nomeRaw))
            }
            
            return ParsedAgenzia(codice: "", nome: titleCase(trimmed))
            
        case .unipolItalia:
            // Per Unipol: formato da definire, per ora usiamo default
            fallthrough
            
        case .unknown:
            // Default: primi 3 caratteri = codice (alfanumerici), resto = nome
            if trimmed.count >= 3 {
                let codice = String(trimmed.prefix(3)).uppercased()
                let nomeRaw = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                return ParsedAgenzia(codice: codice, nome: titleCase(nomeRaw))
            } else {
                return ParsedAgenzia(codice: "", nome: titleCase(trimmed))
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Converte una stringa in Title Case (iniziali maiuscole)
    private func titleCase(_ string: String) -> String {
        guard !string.isEmpty else { return string }
        return string.components(separatedBy: " ")
            .map { word in
                guard !word.isEmpty else { return word }
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}

