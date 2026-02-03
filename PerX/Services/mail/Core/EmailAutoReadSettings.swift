import Foundation

/// Servizio per gestire le impostazioni di auto-marcatura come letta per email processate
class EmailAutoReadSettings {
    static let shared = EmailAutoReadSettings()
    
    private let userDefaults = UserDefaults.standard
    private let enabledKey = "emailAutoReadEnabled"
    private let categoriesKey = "emailAutoReadCategories"
    
    private init() {}
    
    /// Indica se l'auto-marcatura come letta è abilitata
    var isEnabled: Bool {
        get {
            // Se non è mai stata impostata, usa il default (true)
            if userDefaults.object(forKey: enabledKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: enabledKey)
        }
        set {
            userDefaults.set(newValue, forKey: enabledKey)
        }
    }
    
    /// Categorie per cui auto-marcare come letta (default: solo assegnazioni)
    var enabledCategories: Set<EmailCategory> {
        get {
            if let data = userDefaults.data(forKey: categoriesKey),
               let categories = try? JSONDecoder().decode([String].self, from: data) {
                return Set(categories.compactMap { EmailCategory(rawValue: $0) })
            }
            // Default: solo assegnazioni
            return [.assignment]
        }
        set {
            let categories = newValue.map { $0.rawValue }
            if let data = try? JSONEncoder().encode(categories) {
                userDefaults.set(data, forKey: categoriesKey)
            }
        }
    }
    
    /// Verifica se una categoria è abilitata per auto-marcatura come letta
    func isCategoryEnabled(_ category: EmailCategory) -> Bool {
        guard isEnabled else { return false }
        return enabledCategories.contains(category)
    }
    
    /// Abilita/disabilita una categoria specifica
    func setCategory(_ category: EmailCategory, enabled: Bool) {
        var categories = enabledCategories
        if enabled {
            categories.insert(category)
        } else {
            categories.remove(category)
        }
        enabledCategories = categories
    }
}
