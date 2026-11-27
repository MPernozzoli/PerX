import Foundation

/// Utility per validare i riferimenti sinistro
struct RiferimentoValidator {
    
    /// Anno dalle prime due cifre. Vale per `2500876` e per `26-602322`.
    static func extractYear(from riferimento: String) -> Int? {
        guard isValidFormat(riferimento) else { return nil }
        let yearDigits = riferimento.prefix(2).filter(\.isNumber)
        guard yearDigits.count == 2, let year = Int(yearDigits) else { return nil }
        return 2000 + year
    }

    /// `2500876` oppure il riferimento Chiari `26-602322`.
    static func isValidFormat(_ riferimento: String) -> Bool {
        if riferimento.count == 7, riferimento.allSatisfy(\.isNumber) {
            return true
        }
        guard riferimento.count == 9, riferimento.dropFirst(2).first == "-" else { return false }
        let year = riferimento.prefix(2)
        let serial = riferimento.suffix(6)
        return year.allSatisfy(\.isNumber) && serial.allSatisfy(\.isNumber)
    }

    /// Riferimento in testa a un nome di cartella: `26-602322_Rossi` o `2500876 foto`.
    static func reference(inFolderName name: String) -> String? {
        if isValidFormat(name) { return name }
        if let range = name.range(of: #"^\d{2}-\d{6}(?=[_\s.]|$)"#, options: .regularExpression) {
            return String(name[range])
        }
        guard name.count >= 7 else { return nil }
        let prefix = String(name.prefix(7))
        guard prefix.allSatisfy(\.isNumber) else { return nil }
        if name.count == 7 { return prefix }
        let boundary = name[name.index(name.startIndex, offsetBy: 7)]
        return boundary.isNumber ? nil : prefix
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
        guard RiferimentoValidator.isValidFormat(riferimento) else {
            return "Riferimento non valido: atteso 7 cifre oppure 26-602322"
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
