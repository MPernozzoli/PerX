import Foundation

/// Servizio per gestire le impostazioni e lo stato del diario
class DiarioService {
    static let shared = DiarioService()
    
    private let defaults = UserDefaults.standard
    private let diarioActivationDateKey = "diarioActivationDate"
    
    private init() {
        // Se è la prima volta, salva la data corrente
        if activationDate == nil {
            activationDate = Date()
        }
    }
    
    /// Data di prima attivazione della funzione diario
    var activationDate: Date? {
        get {
            if let timeInterval = defaults.object(forKey: diarioActivationDateKey) as? TimeInterval {
                return Date(timeIntervalSince1970: timeInterval)
            }
            return nil
        }
        set {
            if let date = newValue {
                defaults.set(date.timeIntervalSince1970, forKey: diarioActivationDateKey)
            } else {
                defaults.removeObject(forKey: diarioActivationDateKey)
            }
        }
    }
    
    /// Verifica se un'email deve essere processata automaticamente
    func shouldProcessAutomatically(emailDate: Date?) -> Bool {
        guard let emailDate = emailDate,
              let activationDate = activationDate else {
            return false
        }
        return emailDate >= activationDate
    }
}

