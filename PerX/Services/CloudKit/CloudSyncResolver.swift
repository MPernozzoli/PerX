//
//  CloudSyncResolver.swift
//  PerX
//
//  Gestisce la logica di risoluzione conflitti con priorità cloud.
//  Cloud wins: in caso di conflitto, i dati cloud hanno sempre la precedenza.
//
//  NOTA: Questo file è temporaneamente disabilitato in attesa di implementazione
//  delle proprietà di tracking sync in Sinistro (localModifiedAt, cloudSyncedAt, ecc.)
//

import Foundation
import CoreData

/// Configurazione per la risoluzione sync
struct CloudSyncConfig {
    /// Margine di tolleranza per confronto date (evita conflitti per millisecondi)
    static let dateToleranceSeconds: TimeInterval = 2.0
    
    /// Priorità cloud: se true, in caso di conflitto vince sempre il cloud
    static let cloudWinsOnConflict: Bool = true
    
    /// Se true, logga dettagli delle decisioni di sync
    static let verboseLogging: Bool = true
}

/// Risultato della risoluzione sync
enum SyncResolution {
    case applyCloud          // Applica dati dal cloud (pull)
    case pushLocal           // Pusha dati locali al cloud
    case skip                // Nessuna azione necessaria (già in sync)
    case conflict(cloudWins: Bool) // C'era conflitto, indica chi ha vinto
    
    var description: String {
        switch self {
        case .applyCloud: return "Applica dati cloud"
        case .pushLocal: return "Push dati locali"
        case .skip: return "Skip (già sincronizzato)"
        case .conflict(let cloudWins): return "Conflitto risolto: \(cloudWins ? "cloud vince" : "locale vince")"
        }
    }
}

/// Resolver per conflitti di sincronizzazione con priorità cloud
/// TODO: Riattivare quando le proprietà di tracking sync saranno implementate in Sinistro
@MainActor
final class CloudSyncResolver {
    
    static let shared = CloudSyncResolver()
    private init() {}
    
    // MARK: - Resolve Sync Decision (Stub - sempre applica cloud per ora)
    
    /// Determina l'azione da intraprendere per un sinistro dato il timestamp cloud
    func resolveSyncDecision(
        sinistro: Sinistro,
        cloudModifiedAt: Date
    ) -> SyncResolution {
        // Stub: per ora applica sempre cloud (comportamento sicuro)
        log("[\(sinistro.riferimento ?? "?")] → Applica cloud (stub)")
        return .applyCloud
    }
    
    /// Determina se applicare dati dal cloud (per minimal record pull)
    func shouldApplyCloudData(
        sinistro: Sinistro,
        cloudModifiedAt: Date
    ) -> Bool {
        // Stub: sempre applica cloud
        return true
    }
    
    /// Determina se pushare dati locali al cloud
    func shouldPushLocalData(sinistro: Sinistro, cloudModifiedAt: Date?) -> Bool {
        // Stub: non pusha mai automaticamente per ora
        return false
    }
    
    // MARK: - Batch Operations
    
    /// Filtra sinistri che necessitano push
    func filterForPush(_ sinistri: [Sinistro]) -> [Sinistro] {
        // Stub: nessun sinistro necessita push per ora
        return []
    }
    
    /// Ordina sinistri per priorità di sync (più recentemente modificati prima)
    func sortByPushPriority(_ sinistri: [Sinistro]) -> [Sinistro] {
        // Ordina per lastModified (se esiste) o data sinistro
        sinistri.sorted { (s1: Sinistro, s2: Sinistro) in
            let d1 = s1.dataSinistro ?? Date.distantPast
            let d2 = s2.dataSinistro ?? Date.distantPast
            return d1 > d2
        }
    }
    
    // MARK: - Migration (Stub)
    
    /// Migra sinistri esistenti al nuovo sistema di tracking
    func migrateSinistri(context: NSManagedObjectContext) async {
        // TODO: Implementare quando le proprietà di tracking saranno disponibili
        print("[CloudSyncResolver] ⏭️ Migrazione skippata (tracking sync non implementato)")
    }
    
    // MARK: - Helpers
    
    private func log(_ message: String) {
        if CloudSyncConfig.verboseLogging {
            print("[CloudSyncResolver] \(message)")
        }
    }
}

// MARK: - Extension Stub per Sinistro

extension Sinistro {
    
    /// Applica i dati dal cloud e aggiorna i campi di tracking (stub)
    func applyCloudDataAndMarkSynced(cloudModifiedAt: Date) {
        // TODO: Implementare quando le proprietà di tracking saranno disponibili
    }
    
    /// Dopo un push riuscito, aggiorna i campi di tracking (stub)
    func markPushCompleted(serverTimestamp: Date) {
        // TODO: Implementare quando le proprietà di tracking saranno disponibili
    }
}
