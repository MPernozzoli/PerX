import Foundation
import CoreData

/// Servizio per la stima e adattamento della durata delle task
@MainActor
class TaskDurationService: ObservableObject {
    static let shared = TaskDurationService()
    
    private let userDefaults = UserDefaults.standard
    private let durationHistoryKey = "taskDurationHistory"
    private let baseDurationsKey = "taskBaseDurations"
    
    /// Durate base per tipo di task (in secondi)
    private var baseDurations: [TaskType: TimeInterval] = [
        .sinistroActivity: 1800,      // 30 minuti per gestione sinistro
        .reminder: 300,               // 5 minuti per solleciti/richiami
        .meeting: 2400,               // 40 minuti riunioni/videoperizie
        .manual: 900,                 // 15 minuti per attività rapide manuali
        .aiGenerated: 420             // 7 minuti per email/whatsapp/risposte brevi
    ]
    
    /// History delle durate effettive per tipo di task
    private var durationHistory: [TaskType: [TimeInterval]] = [:]
    
    private init() {
        loadBaseDurations()
        loadDurationHistory()
    }
    
    // MARK: - Public API
    
    /// Ottiene la durata stimata per un tipo di task, con adattamento basato su history
    func getEstimatedDuration(for taskType: TaskType, sinistro: Sinistro? = nil) -> TimeInterval {
        let baseDuration = baseDurations[taskType] ?? 1800
        
        // Applica coefficiente di complessità se disponibile
        let complexityCoefficient = getComplexityCoefficient(for: sinistro)
        let adjustedBaseDuration = baseDuration * complexityCoefficient
        
        // Se abbiamo history, calcola durata adattata
        if let history = durationHistory[taskType], history.count >= 3 {
            // Usa algoritmo adattivo più reattivo
            let recentHistory = Array(history.suffix(20)) // Ultime 20 task
            
            // Calcola media mobile esponenziale (più peso alle task recenti)
            let weightedAverage = calculateWeightedAverage(recentHistory)
            
            // Se la media è significativamente diversa dalla base, adatta progressivamente
            let difference = weightedAverage - adjustedBaseDuration
            let adaptationFactor = min(0.8, Double(history.count) / 20.0) // Max 80% adattamento dopo 20 task
            
            // Adattamento progressivo: più task completate, più ci fidiamo della history
            let estimatedDuration = adjustedBaseDuration + (difference * adaptationFactor)
            
            // Non scendere sotto il 50% della base duration
            return max(adjustedBaseDuration * 0.5, estimatedDuration)
        }
        
        return adjustedBaseDuration
    }
    
    /// Calcola media mobile esponenziale con più peso alle task recenti
    private func calculateWeightedAverage(_ history: [TimeInterval]) -> TimeInterval {
        guard !history.isEmpty else { return 0 }
        
        // Peso esponenziale: ultime task hanno peso maggiore
        var weightedSum: Double = 0
        var totalWeight: Double = 0
        
        for (index, duration) in history.enumerated() {
            let weight = pow(1.1, Double(index)) // Peso crescente per task più recenti
            weightedSum += duration * weight
            totalWeight += weight
        }
        
        return weightedSum / totalWeight
    }
    
    /// Ottiene il coefficiente di complessità per un sinistro
    /// In futuro questo sarà calcolato basandosi su:
    /// - importo richiesta (es. > 10k = +0.2, > 50k = +0.4)
    /// - numero foto in cartella (es. > 20 foto = +0.15, > 50 foto = +0.3)
    /// - numero beni in denuncia (es. > 5 beni = +0.1, > 10 beni = +0.2)
    /// - tipo di sinistro (fulminazione, allagamento, etc.)
    /// - altri fattori di complessità
    /// 
    /// Il coefficiente viene moltiplicato alla durata base:
    /// - 1.0 = durata normale
    /// - 1.5 = 50% più tempo
    /// - 2.0 = doppio tempo (max)
    private func getComplexityCoefficient(for sinistro: Sinistro?) -> Double {
        guard let sinistro = sinistro else { return 1.0 }
        
        // Placeholder: per ora ritorna 1.0 (nessuna modifica)
        // TODO: Implementare calcolo complessità quando disponibili:
        // - Metodo per contare foto in cartella sinistro
        // - Metodo per contare beni in denuncia
        // - Analisi importo richiesta
        //
        // Esempio implementazione futura:
        // var coefficient = 1.0
        // 
        // if let importo = sinistro.richiesta?.doubleValue {
        //     if importo > 50000 { coefficient += 0.4 }
        //     else if importo > 10000 { coefficient += 0.2 }
        // }
        // 
        // if let fotoCount = FileService.shared.countPhotos(in: sinistro.cartella ?? ""), fotoCount > 0 {
        //     if fotoCount > 50 { coefficient += 0.3 }
        //     else if fotoCount > 20 { coefficient += 0.15 }
        // }
        // 
        // if let beniCount = getBeniCountFromDenuncia(for: sinistro), beniCount > 0 {
        //     if beniCount > 10 { coefficient += 0.2 }
        //     else if beniCount > 5 { coefficient += 0.1 }
        // }
        // 
        // return min(2.0, max(0.5, coefficient)) // Range 0.5x - 2.0x
        
        return 1.0
    }
    
    /// Registra la durata effettiva di una task completata
    func recordTaskDuration(taskType: TaskType, actualDuration: TimeInterval) {
        if durationHistory[taskType] == nil {
            durationHistory[taskType] = []
        }
        
        durationHistory[taskType]?.append(actualDuration)
        
        // Mantieni solo le ultime 100 durate per tipo (più dati = migliore adattamento)
        if let history = durationHistory[taskType], history.count > 100 {
            durationHistory[taskType] = Array(history.suffix(100))
        }
        
        // Adatta progressivamente la durata base se c'è una tendenza chiara
        adaptBaseDurationIfNeeded(for: taskType)
        
        saveDurationHistory()
    }
    
    /// Adatta la durata base se c'è una tendenza chiara nella history
    private func adaptBaseDurationIfNeeded(for taskType: TaskType) {
        guard let history = durationHistory[taskType], history.count >= 10 else { return }
        
        let recentHistory = Array(history.suffix(10))
        let average = recentHistory.reduce(0, +) / Double(recentHistory.count)
        let currentBase = baseDurations[taskType] ?? 1800
        
        // Se la media recente è significativamente diversa dalla base (oltre 20% di differenza)
        let difference = abs(average - currentBase) / currentBase
        
        if difference > 0.2 {
            // Adatta la base duration gradualmente (5% per volta)
            let adaptation = (average - currentBase) * 0.05
            let newBase = currentBase + adaptation
            
            // Non scendere sotto il 50% della base originale
            let minBase = baseDurations[taskType] ?? 1800
            baseDurations[taskType] = max(minBase * 0.5, newBase)
            saveBaseDurations()
        }
    }
    
    /// Aggiorna la durata base per un tipo di task
    func updateBaseDuration(for taskType: TaskType, duration: TimeInterval) {
        baseDurations[taskType] = duration
        saveBaseDurations()
    }
    
    /// Ottiene la durata base per un tipo di task
    func getBaseDuration(for taskType: TaskType) -> TimeInterval {
        return baseDurations[taskType] ?? 1800
    }
    
    // MARK: - Persistence
    
    private func loadBaseDurations() {
        if let data = userDefaults.data(forKey: baseDurationsKey),
           let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
            baseDurations = decoded.reduce(into: [TaskType: TimeInterval]()) { result, pair in
                if let taskType = TaskType(rawValue: pair.key) {
                    result[taskType] = pair.value
                }
            }
        }
    }
    
    private func saveBaseDurations() {
        let encoded = baseDurations.reduce(into: [String: TimeInterval]()) { result, pair in
            result[pair.key.rawValue] = pair.value
        }
        if let data = try? JSONEncoder().encode(encoded) {
            userDefaults.set(data, forKey: baseDurationsKey)
        }
    }
    
    private func loadDurationHistory() {
        if let data = userDefaults.data(forKey: durationHistoryKey),
           let decoded = try? JSONDecoder().decode([String: [TimeInterval]].self, from: data) {
            durationHistory = decoded.reduce(into: [TaskType: [TimeInterval]]()) { result, pair in
                if let taskType = TaskType(rawValue: pair.key) {
                    result[taskType] = pair.value
                }
            }
        }
    }
    
    private func saveDurationHistory() {
        let encoded = durationHistory.reduce(into: [String: [TimeInterval]]()) { result, pair in
            result[pair.key.rawValue] = pair.value
        }
        if let data = try? JSONEncoder().encode(encoded) {
            userDefaults.set(data, forKey: durationHistoryKey)
        }
    }
}

