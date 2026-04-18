import Foundation

/// Gestisce gli aggiornamenti pendenti dei componenti
/// Mantiene in memoria le notifiche di aggiornamento fino a quando non vengono confermate
public actor UpdatesManager {
    public static let shared = UpdatesManager()
    
    /// Aggiornamenti pendenti: component -> [changedFiles]
    private var pendingUpdates: [String: [String]] = [:]
    
    /// Timestamp dell'ultimo aggiornamento per componente
    private var updateTimestamps: [String: Date] = [:]
    
    private init() {}
    
    // MARK: - Public API
    
    /// Registra un aggiornamento per un componente
    public func recordUpdate(component: String, changedFiles: [String]) {
        if var existing = pendingUpdates[component] {
            // Aggiungi solo file non già presenti
            for file in changedFiles {
                if !existing.contains(file) {
                    existing.append(file)
                }
            }
            pendingUpdates[component] = existing
        } else {
            pendingUpdates[component] = changedFiles
        }
        
        updateTimestamps[component] = Date()
        
        print("[UpdatesManager] Recorded update for \(component): \(changedFiles.count) files")
    }
    
    /// Restituisce tutti gli aggiornamenti pendenti
    public func getPendingUpdates() -> [String: [String]] {
        return pendingUpdates
    }
    
    /// Verifica se ci sono aggiornamenti per un componente
    public func hasUpdate(for component: String) -> Bool {
        return pendingUpdates[component] != nil && !(pendingUpdates[component]?.isEmpty ?? true)
    }
    
    /// Restituisce i file cambiati per un componente
    public func getChangedFiles(for component: String) -> [String] {
        return pendingUpdates[component] ?? []
    }
    
    /// Restituisce il timestamp dell'ultimo aggiornamento
    public func getUpdateTimestamp(for component: String) -> Date? {
        return updateTimestamps[component]
    }
    
    /// Conferma che un aggiornamento è stato applicato
    public func acknowledgeUpdate(component: String) {
        pendingUpdates.removeValue(forKey: component)
        updateTimestamps.removeValue(forKey: component)
        
        print("[UpdatesManager] Update acknowledged for \(component)")
    }
    
    /// Restituisce un riepilogo degli aggiornamenti per il Monitor
    public func getSummary() -> [ComponentUpdateSummary] {
        var summaries: [ComponentUpdateSummary] = []
        
        for (component, files) in pendingUpdates {
            summaries.append(ComponentUpdateSummary(
                component: component,
                filesChanged: files.count,
                timestamp: updateTimestamps[component],
                isReadyToUpdate: true
            ))
        }
        
        return summaries.sorted { $0.component < $1.component }
    }
}

// MARK: - DTOs

public struct ComponentUpdateSummary: Codable, Sendable {
    public let component: String
    public let filesChanged: Int
    public let timestamp: Date?
    public let isReadyToUpdate: Bool
}
