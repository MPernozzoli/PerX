import Foundation

/// Cache per i risultati di verifica numeri WhatsApp
/// Evita verifiche ripetute dello stesso numero
@MainActor
class WhatsAppNumberCacheService: ObservableObject {
    static let shared = WhatsAppNumberCacheService()
    
    /// Stato di verifica di un numero
    enum NumberStatus: Equatable {
        case unknown
        case checking
        case registered
        case notRegistered
        case error
    }
    
    /// Cache dei numeri verificati (normalizzati)
    @Published private(set) var numberCache: [String: NumberStatus] = [:]
    
    /// Numeri in fase di verifica (per evitare verifiche duplicate)
    private var pendingChecks: Set<String> = []
    
    /// Durata cache in secondi (24 ore)
    private let cacheDuration: TimeInterval = 86400
    
    /// Timestamp ultima verifica per numero
    private var cacheTimestamps: [String: Date] = [:]
    
    private init() {
        loadCache()
    }
    
    // MARK: - Public API
    
    /// Verifica se un numero è su WhatsApp (usa cache se disponibile)
    func checkNumber(_ phoneNumber: String) async -> NumberStatus {
        let normalized = normalizeNumber(phoneNumber)
        
        // Se già in cache e non scaduto, ritorna il risultato
        if let cached = numberCache[normalized],
           cached != .unknown && cached != .checking,
           !isCacheExpired(for: normalized) {
            return cached
        }
        
        // Se già in fase di verifica, aspetta
        if pendingChecks.contains(normalized) {
            // Attendi che la verifica in corso finisca
            for _ in 0..<50 { // max 5 secondi
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                if !pendingChecks.contains(normalized),
                   let result = numberCache[normalized],
                   result != .checking {
                    return result
                }
            }
            return numberCache[normalized] ?? .unknown
        }
        
        // Avvia verifica
        pendingChecks.insert(normalized)
        numberCache[normalized] = .checking
        
        do {
            let isRegistered = try await WhatsAppService.shared.checkNumberRegistered(phoneNumber: normalized)
            let status: NumberStatus = isRegistered ? .registered : .notRegistered
            
            numberCache[normalized] = status
            cacheTimestamps[normalized] = Date()
            pendingChecks.remove(normalized)
            saveCache()
            
            return status
        } catch {
            numberCache[normalized] = .error
            pendingChecks.remove(normalized)
            return .error
        }
    }
    
    /// Verifica multipli numeri in parallelo (deduplica automaticamente)
    func checkNumbers(_ phoneNumbers: [String]) async {
        // Deduplica e normalizza
        let uniqueNumbers = Set(phoneNumbers.map { normalizeNumber($0) })
            .filter { !$0.isEmpty }
        
        // Filtra quelli già in cache valida
        let numbersToCheck = uniqueNumbers.filter { number in
            if let cached = numberCache[number],
               cached != .unknown && cached != .checking,
               !isCacheExpired(for: number) {
                return false
            }
            return true
        }
        
        guard !numbersToCheck.isEmpty else { return }
        
        // Verifica in parallelo (max 3 alla volta per non sovraccaricare)
        await withTaskGroup(of: Void.self) { group in
            var count = 0
            for number in numbersToCheck {
                if count >= 3 {
                    await group.next()
                }
                group.addTask {
                    _ = await self.checkNumber(number)
                }
                count += 1
            }
        }
    }
    
    /// Stato corrente di un numero (senza avviare verifica)
    func status(for phoneNumber: String) -> NumberStatus {
        let normalized = normalizeNumber(phoneNumber)
        return numberCache[normalized] ?? .unknown
    }
    
    /// Resetta la cache
    func clearCache() {
        numberCache.removeAll()
        cacheTimestamps.removeAll()
        pendingChecks.removeAll()
        UserDefaults.standard.removeObject(forKey: "whatsapp_number_cache")
        UserDefaults.standard.removeObject(forKey: "whatsapp_number_cache_timestamps")
    }
    
    // MARK: - Private
    
    private func normalizeNumber(_ number: String) -> String {
        var cleaned = number.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        // Aggiungi prefisso italiano se non presente
        if !cleaned.hasPrefix("39") && cleaned.count <= 10 && cleaned.count >= 9 {
            cleaned = "39\(cleaned)"
        }
        return cleaned
    }
    
    private func isCacheExpired(for number: String) -> Bool {
        guard let timestamp = cacheTimestamps[number] else { return true }
        return Date().timeIntervalSince(timestamp) > cacheDuration
    }
    
    private func saveCache() {
        // Salva solo registered/notRegistered
        var toSave: [String: Bool] = [:]
        for (number, status) in numberCache {
            switch status {
            case .registered: toSave[number] = true
            case .notRegistered: toSave[number] = false
            default: break
            }
        }
        
        UserDefaults.standard.set(toSave, forKey: "whatsapp_number_cache")
        
        // Salva timestamps
        let timestamps = cacheTimestamps.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(timestamps, forKey: "whatsapp_number_cache_timestamps")
    }
    
    private func loadCache() {
        if let saved = UserDefaults.standard.dictionary(forKey: "whatsapp_number_cache") as? [String: Bool] {
            for (number, isRegistered) in saved {
                numberCache[number] = isRegistered ? .registered : .notRegistered
            }
        }
        
        if let timestamps = UserDefaults.standard.dictionary(forKey: "whatsapp_number_cache_timestamps") as? [String: Double] {
            for (number, interval) in timestamps {
                cacheTimestamps[number] = Date(timeIntervalSince1970: interval)
            }
        }
        
        // Rimuovi cache scadute
        let now = Date()
        for (number, timestamp) in cacheTimestamps {
            if now.timeIntervalSince(timestamp) > cacheDuration {
                numberCache.removeValue(forKey: number)
                cacheTimestamps.removeValue(forKey: number)
            }
        }
    }
}
