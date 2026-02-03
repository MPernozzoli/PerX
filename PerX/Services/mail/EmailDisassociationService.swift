import Foundation

/// Servizio per gestire le disassociazioni manuali di email da sinistri
/// Mantiene traccia degli override manuali dell'utente per evitare riassociazioni automatiche indesiderate
class EmailDisassociationService {
    static let shared = EmailDisassociationService()
    private let userDefaults = UserDefaults.standard
    private let disassociatedKey = "disassociatedEmails"
    
    private init() {}
    
    /// Marca un'email come disassociata da un sinistro specifico
    /// Questo override manuale previene la riassociazione automatica
    func markAsDisassociated(emailId: String, sinistroId: String) {
        var disassociated = getDisassociatedEmails()
        let key = "\(emailId):\(sinistroId)"
        if !disassociated.contains(key) {
            disassociated.append(key)
            userDefaults.set(disassociated, forKey: disassociatedKey)
            print("[EmailDisassociationService] ✅ Email \(emailId) marcata come disassociata da sinistro \(sinistroId)")
        }
    }
    
    /// Verifica se un'email è stata disassociata manualmente da un sinistro
    func isDisassociated(emailId: String, sinistroId: String) -> Bool {
        let disassociated = getDisassociatedEmails()
        let key = "\(emailId):\(sinistroId)"
        return disassociated.contains(key)
    }
    
    /// Rimuove la disassociazione manuale (permette la riassociazione automatica)
    /// Utile quando l'utente riassocia manualmente un'email
    func removeDisassociation(emailId: String, sinistroId: String) {
        var disassociated = getDisassociatedEmails()
        let key = "\(emailId):\(sinistroId)"
        let wasPresent = disassociated.contains(key)
        disassociated.removeAll { $0 == key }
        userDefaults.set(disassociated, forKey: disassociatedKey)
        if wasPresent {
            print("[EmailDisassociationService] ✅ Disassociazione rimossa per email \(emailId) e sinistro \(sinistroId)")
        }
    }
    
    /// Rimuove tutte le disassociazioni per un'email specifica
    /// Utile per reset completo
    func removeAllDisassociationsForEmail(_ emailId: String) {
        var disassociated = getDisassociatedEmails()
        disassociated.removeAll { $0.hasPrefix("\(emailId):") }
        userDefaults.set(disassociated, forKey: disassociatedKey)
        print("[EmailDisassociationService] ✅ Tutte le disassociazioni rimosse per email \(emailId)")
    }
    
    /// Rimuove tutte le disassociazioni per un sinistro specifico
    /// Utile quando un sinistro viene eliminato o resettato
    func removeAllDisassociationsForSinistro(_ sinistroId: String) {
        var disassociated = getDisassociatedEmails()
        disassociated.removeAll { $0.hasSuffix(":\(sinistroId)") }
        userDefaults.set(disassociated, forKey: disassociatedKey)
        print("[EmailDisassociationService] ✅ Tutte le disassociazioni rimosse per sinistro \(sinistroId)")
    }
    
    /// Ottiene tutte le disassociazioni attive
    func getAllDisassociations() -> [(emailId: String, sinistroId: String)] {
        let disassociated = getDisassociatedEmails()
        return disassociated.compactMap { key in
            let components = key.components(separatedBy: ":")
            guard components.count == 2 else { return nil }
            return (emailId: components[0], sinistroId: components[1])
        }
    }
    
    /// Resetta tutte le disassociazioni (utile per debug o reset completo)
    func resetAll() {
        userDefaults.removeObject(forKey: disassociatedKey)
        print("[EmailDisassociationService] ✅ Tutte le disassociazioni rimosse")
    }
    
    private func getDisassociatedEmails() -> [String] {
        return userDefaults.stringArray(forKey: disassociatedKey) ?? []
    }
}

