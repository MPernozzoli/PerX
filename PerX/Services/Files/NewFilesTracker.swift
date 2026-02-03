import Foundation

/// Tipo di file scaricato
enum FileStatus: String, Codable {
    case new       // File completamente nuovo
    case modified  // File esistente ma modificato sul server
}

/// Traccia i file nuovi e modificati scaricati per evidenziarli nella vista cartella
@MainActor
final class NewFilesTracker: ObservableObject {
    static let shared = NewFilesTracker()
    
    /// Mappa file per sinistro (riferimento -> [relativePath: FileStatus])
    @Published private(set) var fileStatuses: [String: [String: FileStatus]] = [:]
    
    private let storageKey = "newFilesTracker"
    
    private init() {
        loadFromStorage()
    }
    
    // MARK: - Public API
    
    /// Registra nuovi file scaricati per un sinistro
    func markAsNew(riferimento: String, relativePaths: [String]) {
        var current = fileStatuses[riferimento] ?? [:]
        for path in relativePaths {
            current[path] = .new
        }
        fileStatuses[riferimento] = current
        saveToStorage()
    }
    
    /// Registra file modificati scaricati per un sinistro
    func markAsModified(riferimento: String, relativePaths: [String]) {
        var current = fileStatuses[riferimento] ?? [:]
        for path in relativePaths {
            current[path] = .modified
        }
        fileStatuses[riferimento] = current
        saveToStorage()
    }
    
    /// Verifica se un file è nuovo
    func isNew(riferimento: String, relativePath: String) -> Bool {
        fileStatuses[riferimento]?[relativePath] == .new
    }
    
    /// Verifica se un file è modificato
    func isModified(riferimento: String, relativePath: String) -> Bool {
        fileStatuses[riferimento]?[relativePath] == .modified
    }
    
    /// Ottiene lo status di un file
    func getStatus(riferimento: String, relativePath: String) -> FileStatus? {
        fileStatuses[riferimento]?[relativePath]
    }
    
    /// Segna un file come letto (rimuove dall'elenco)
    func markAsRead(riferimento: String, relativePath: String) {
        guard var current = fileStatuses[riferimento] else { return }
        current.removeValue(forKey: relativePath)
        if current.isEmpty {
            fileStatuses.removeValue(forKey: riferimento)
        } else {
            fileStatuses[riferimento] = current
        }
        saveToStorage()
    }
    
    /// Segna tutti i file di un sinistro come letti
    func markAllAsRead(riferimento: String) {
        fileStatuses.removeValue(forKey: riferimento)
        saveToStorage()
    }
    
    /// Ottiene il conteggio dei file nuovi per un sinistro
    func countNew(for riferimento: String) -> Int {
        fileStatuses[riferimento]?.values.filter { $0 == .new }.count ?? 0
    }
    
    /// Ottiene il conteggio dei file modificati per un sinistro
    func countModified(for riferimento: String) -> Int {
        fileStatuses[riferimento]?.values.filter { $0 == .modified }.count ?? 0
    }
    
    // MARK: - Storage
    
    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: [String: FileStatus]].self, from: data) else {
            return
        }
        fileStatuses = decoded
    }
    
    private func saveToStorage() {
        guard let data = try? JSONEncoder().encode(fileStatuses) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
