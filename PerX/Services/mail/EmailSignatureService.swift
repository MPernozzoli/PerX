import Foundation

class EmailSignatureService {
    static let shared = EmailSignatureService()
    
    private let userDefaults = UserDefaults.standard
    private let signatureKey = "emailSignature"
    private let defaultSignatureKey = "defaultEmailSignature"
    
    private init() {}
    
    /// Ottiene la firma email salvata
    func getSignature() -> String {
        return userDefaults.string(forKey: signatureKey) ?? ""
    }
    
    /// Salva la firma email
    func saveSignature(_ signature: String) {
        userDefaults.set(signature, forKey: signatureKey)
    }
    
    /// Ottiene la firma di default (se non è stata impostata una personalizzata)
    func getDefaultSignature() -> String {
        return userDefaults.string(forKey: defaultSignatureKey) ?? ""
    }
    
    /// Salva la firma di default
    func saveDefaultSignature(_ signature: String) {
        userDefaults.set(signature, forKey: defaultSignatureKey)
    }
    
    /// Ottiene la firma da usare (personalizzata o default)
    func getActiveSignature() -> String {
        let custom = getSignature()
        if !custom.isEmpty {
            return custom
        }
        return getDefaultSignature()
    }
    
    /// Verifica se esiste una firma salvata
    func hasSignature() -> Bool {
        return !getSignature().isEmpty
    }
}

// MARK: - Read Receipt Settings

class ReadReceiptSettings: ObservableObject {
    static let shared = ReadReceiptSettings()
    
    private let userDefaults = UserDefaults.standard
    private let readReceiptEnabledKey = "readReceiptEnabled"
    
    private init() {}
    
    var isEnabled: Bool {
        get {
            return userDefaults.bool(forKey: readReceiptEnabledKey)
        }
        set {
            userDefaults.set(newValue, forKey: readReceiptEnabledKey)
        }
    }
}

