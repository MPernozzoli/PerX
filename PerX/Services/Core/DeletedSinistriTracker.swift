import Foundation

/// Traccia i sinistri eliminati localmente per evitare che vengano ricreati da CloudKit sync.
/// I riferimenti eliminati vengono salvati in UserDefaults e persistono tra le sessioni.
final class DeletedSinistriTracker {
    static let shared = DeletedSinistriTracker()
    
    private let storageKey = "DeletedSinistriTracker.deletedRiferimenti"
    
    private init() {}
    
    // MARK: - Public API
    
    /// Segna un sinistro come eliminato (non verrà più ricreato da CloudKit)
    func markAsDeleted(riferimento: String) {
        var deleted = getDeletedRiferimenti()
        deleted.insert(riferimento)
        saveDeletedRiferimenti(deleted)
        print("[DeletedSinistriTracker] 🗑️ Sinistro \(riferimento) marcato come eliminato")
    }
    
    /// Verifica se un sinistro è stato eliminato
    func isDeleted(riferimento: String) -> Bool {
        return getDeletedRiferimenti().contains(riferimento)
    }
    
    /// Rimuove un sinistro dalla lista degli eliminati (es. se viene reimportato manualmente)
    func unmarkAsDeleted(riferimento: String) {
        var deleted = getDeletedRiferimenti()
        deleted.remove(riferimento)
        saveDeletedRiferimenti(deleted)
        print("[DeletedSinistriTracker] ♻️ Sinistro \(riferimento) rimosso dalla lista eliminati")
    }
    
    /// Restituisce tutti i riferimenti eliminati
    func getAllDeletedRiferimenti() -> Set<String> {
        return getDeletedRiferimenti()
    }
    
    /// Pulisce la lista degli eliminati più vecchi di N giorni (manutenzione)
    /// - Parameter olderThanDays: numero di giorni oltre i quali rimuovere gli eliminati
    /// - Note: Richiede un sistema di timestamp se si vuole questa funzionalità
    func clearAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        print("[DeletedSinistriTracker] 🧹 Lista sinistri eliminati svuotata")
    }
    
    // MARK: - Private
    
    private func getDeletedRiferimenti() -> Set<String> {
        guard let array = UserDefaults.standard.array(forKey: storageKey) as? [String] else {
            return []
        }
        return Set(array)
    }
    
    private func saveDeletedRiferimenti(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: storageKey)
    }
}
