import Foundation
import SwiftUI

/// Servizio per cachare le foto profilo WhatsApp
@MainActor
class WhatsAppProfilePicCacheService: ObservableObject {
    static let shared = WhatsAppProfilePicCacheService()
    
    /// Cache delle URL delle foto profilo
    @Published private(set) var profilePicCache: [String: String?] = [:]
    
    /// Contatti in fase di caricamento
    private var pendingFetches: Set<String> = []
    
    /// Durata cache (24 ore)
    private let cacheDuration: TimeInterval = 86400
    
    /// Timestamp cache
    private var cacheTimestamps: [String: Date] = [:]
    
    private init() {
        loadCache()
    }
    
    /// Ottiene la foto profilo per un contatto (da cache o fetch)
    func getProfilePicUrl(for contactId: String) async -> String? {
        let normalizedId = normalizeContactId(contactId)
        
        // Se in cache e non scaduta, ritorna
        if let cached = profilePicCache[normalizedId], !isCacheExpired(for: normalizedId) {
            return cached
        }
        
        // Se già in fetch, attendi
        if pendingFetches.contains(normalizedId) {
            return profilePicCache[normalizedId] ?? nil
        }
        
        // Fetch
        pendingFetches.insert(normalizedId)
        
        do {
            let url = try await WhatsAppService.shared.getProfilePicUrl(contactId: normalizedId)
            profilePicCache[normalizedId] = url
            cacheTimestamps[normalizedId] = Date()
            saveCache()
        } catch {
            // Salva nil in cache per evitare retry continui
            profilePicCache[normalizedId] = nil
            cacheTimestamps[normalizedId] = Date()
        }
        
        pendingFetches.remove(normalizedId)
        return profilePicCache[normalizedId] ?? nil
    }
    
    /// Ottiene la foto profilo dalla cache senza fetch
    func cachedProfilePicUrl(for contactId: String) -> String? {
        let normalizedId = normalizeContactId(contactId)
        return profilePicCache[normalizedId] ?? nil
    }
    
    /// Pre-fetch foto profilo per più contatti
    func prefetchProfilePics(for contactIds: [String]) async {
        let uniqueIds = Set(contactIds.map { normalizeContactId($0) })
        let needsFetch = uniqueIds.filter { 
            profilePicCache[$0] == nil || isCacheExpired(for: $0)
        }
        
        // Limita a 5 fetch paralleli
        for id in needsFetch.prefix(5) {
            if !pendingFetches.contains(id) {
                Task {
                    _ = await getProfilePicUrl(for: id)
                }
            }
        }
    }
    
    /// Pulisce la cache
    func clearCache() {
        profilePicCache.removeAll()
        cacheTimestamps.removeAll()
        UserDefaults.standard.removeObject(forKey: "whatsapp_profile_pic_cache")
        UserDefaults.standard.removeObject(forKey: "whatsapp_profile_pic_timestamps")
    }
    
    // MARK: - Private
    
    private func normalizeContactId(_ id: String) -> String {
        // Rimuovi spazi e caratteri speciali
        var normalized = id.replacingOccurrences(of: "[^0-9@a-z.]", with: "", options: .regularExpression)
        
        // Aggiungi @c.us se manca
        if !normalized.contains("@") {
            // Rimuovi prefisso + se presente
            if normalized.hasPrefix("+") {
                normalized = String(normalized.dropFirst())
            }
            normalized = "\(normalized)@c.us"
        }
        
        return normalized
    }
    
    private func isCacheExpired(for contactId: String) -> Bool {
        guard let timestamp = cacheTimestamps[contactId] else { return true }
        return Date().timeIntervalSince(timestamp) > cacheDuration
    }
    
    private func saveCache() {
        // Salva solo URL non nil
        let validCache = profilePicCache.compactMapValues { $0 }
        UserDefaults.standard.set(validCache, forKey: "whatsapp_profile_pic_cache")
        
        // Salva timestamps
        let timestampStrings = cacheTimestamps.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(timestampStrings, forKey: "whatsapp_profile_pic_timestamps")
    }
    
    private func loadCache() {
        if let saved = UserDefaults.standard.dictionary(forKey: "whatsapp_profile_pic_cache") as? [String: String] {
            for (key, value) in saved {
                profilePicCache[key] = value
            }
        }
        
        if let timestamps = UserDefaults.standard.dictionary(forKey: "whatsapp_profile_pic_timestamps") as? [String: Double] {
            for (key, value) in timestamps {
                cacheTimestamps[key] = Date(timeIntervalSince1970: value)
            }
        }
    }
}
