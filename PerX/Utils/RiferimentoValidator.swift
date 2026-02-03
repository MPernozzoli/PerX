import Foundation

/// Utility per validare i riferimenti sinistro
struct RiferimentoValidator {
    
    /// Estrae l'anno dal riferimento (prime 2 cifre)
    /// Esempio: 2500876 -> 2025
    static func extractYear(from riferimento: String) -> Int? {
        guard riferimento.count == 7, riferimento.allSatisfy({ $0.isNumber }) else {
            return nil
        }
        
        let yearString = String(riferimento.prefix(2))
        guard let yearDigits = Int(yearString) else {
            return nil
        }
        
        // Converti in anno completo (20 -> 2020, 25 -> 2025, ecc.)
        return 2000 + yearDigits
    }
    
    /// Verifica se un riferimento è "recente" (anno corrente o anno precedente)
    /// - Parameter riferimento: Il riferimento sinistro (7 cifre)
    /// - Returns: true se il riferimento è dell'anno corrente o precedente
    static func isRecent(_ riferimento: String) -> Bool {
        guard let year = extractYear(from: riferimento) else {
            return false
        }
        
        let currentYear = Calendar.current.component(.year, from: Date())
        let previousYear = currentYear - 1
        
        return year == currentYear || year == previousYear
    }
    
    /// Verifica se l'importazione di sinistri recenti è limitata
    static var isImportLimitedToRecent: Bool {
        UserDefaults.standard.bool(forKey: "limitaImportazioneSinistriRecenti")
    }
    
    /// Valida se un riferimento può essere importato
    /// - Parameter riferimento: Il riferimento sinistro
    /// - Returns: true se può essere importato, false se deve essere rifiutato
    static func canImport(_ riferimento: String) -> Bool {
        // Se il limite non è attivo, permette tutto
        guard isImportLimitedToRecent else {
            return true
        }
        
        // Se il limite è attivo, verifica che sia recente
        return isRecent(riferimento)
    }
    
    /// Valida completamente un riferimento sinistro
    /// - Parameter riferimento: Il riferimento da validare
    /// - Returns: nil se valido, messaggio di errore se non valido
    static func validate(_ riferimento: String) -> String? {
        // 1. Verifica formato: deve essere esattamente 7 caratteri e tutti numerici
        guard riferimento.count == 7 else {
            return "Riferimento deve essere esattamente 7 cifre"
        }
        
        guard riferimento.allSatisfy({ $0.isNumber }) else {
            return "Riferimento deve contenere solo numeri"
        }
        
        // 2. Estrai anno dalle prime 2 cifre
        guard let year = extractYear(from: riferimento) else {
            return "Impossibile estrarre anno dal riferimento"
        }
        
        // 3. Verifica che l'anno non sia futuro
        let currentYear = Calendar.current.component(.year, from: Date())
        if year > currentYear {
            return "Riferimento \(riferimento) rifiutato: anno \(year) è futuro (anno corrente: \(currentYear))"
        }
        
        // 4. Verifica che l'anno sia ragionevole (dal 2000 in poi)
        if year < 2000 {
            return "Riferimento \(riferimento) rifiutato: anno \(year) non valido (minimo 2000)"
        }
        
        // 5. Se il limite importazione è attivo, verifica che sia recente
        if isImportLimitedToRecent && !isRecent(riferimento) {
            return "Riferimento \(riferimento) rifiutato: anno \(year) troppo vecchio (solo anno corrente e precedente)"
        }
        
        return nil
    }
}
