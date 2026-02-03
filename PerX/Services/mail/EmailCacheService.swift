import Foundation

/// Servizio ottimizzato per la gestione della cache delle email con cache in memoria
class EmailCacheService {
    static let shared = EmailCacheService()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    // Cache in memoria per accesso rapido
    // OTTIMIZZAZIONE: Aumentato da 100 a 500 per migliore hit rate
    private var memoryCache: [String: Email] = [:]
    private let memoryCacheLimit = 500 // Massimo 500 email in memoria
    private var cacheAccessOrder: [String] = [] // Per LRU eviction
    
    // Queue per operazioni thread-safe
    private let cacheQueue = DispatchQueue(label: "EmailCacheService", qos: .utility)
    
    private init() {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDirectory = documentsPath.appendingPathComponent("EmailCache")
        createCacheDirectoryIfNeeded()
        
        print("[EmailCache] Inizializzato con cache in memoria (limite: \(memoryCacheLimit))")
    }
    
    private func createCacheDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            do {
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                print("[EmailCache] Directory cache creata: \(cacheDirectory.path)")
            } catch {
                print("[EmailCache] Errore nella creazione della directory cache: \(error)")
            }
        }
    }
    
    // MARK: - Public Interface
    
    /// Salva una email completa con cache in memoria
    func saveFullEmail(_ email: Email, forId id: String) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Aggiorna cache in memoria
            self.updateMemoryCache(email: email, id: id)
            
            // Salva su disco
            let fileURL = self.cacheDirectory.appendingPathComponent("full_\(id).json")
            do {
                let data = try JSONEncoder().encode(email)
                try data.write(to: fileURL)
            } catch {
                // Log solo in caso di errore reale
            }
        }
    }
    
    /// Carica una email completa (prima dalla memoria, poi dal disco) - SINCRONO (per backward compatibility)
    func loadFullEmail(forId id: String) -> Email? {
        return cacheQueue.sync { [weak self] in
            guard let self = self else { return nil }
            
            // Prima controlla la cache in memoria
            if let cachedEmail = self.memoryCache[id] {
                self.updateAccessOrder(for: id)
                return cachedEmail
            }
            
            // Se non in memoria, carica dal disco
            return self.loadFullEmailFromDisk(id: id)
        }
    }
    
    /// Carica una email solo dalla memoria (veloce, non blocca con I/O disco)
    func loadFullEmailFromMemory(forId id: String) -> Email? {
        return cacheQueue.sync { [weak self] in
            guard let self = self else { return nil }
            
            if let cachedEmail = self.memoryCache[id] {
                self.updateAccessOrder(for: id)
                return cachedEmail
            }
            
            return nil
        }
    }
    
    /// Carica una email completa in modo asincrono (non blocca il thread principale)
    func loadFullEmailAsync(forId id: String) async -> Email? {
        return await withCheckedContinuation { continuation in
            cacheQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Prima controlla la cache in memoria
                if let cachedEmail = self.memoryCache[id] {
                    self.updateAccessOrder(for: id)
                    continuation.resume(returning: cachedEmail)
                    return
                }
                
                // Se non in memoria, carica dal disco
                let email = self.loadFullEmailFromDisk(id: id)
                continuation.resume(returning: email)
            }
        }
    }
    
    /// Verifica se una email esiste senza log (veloce)
    func hasEmail(id: String) -> Bool {
        return cacheQueue.sync { [weak self] in
            guard let self = self else { return false }
            
            // Controlla prima la memoria
            if self.memoryCache[id] != nil {
                return true
            }
            
            // Poi controlla il disco (solo esistenza file, non carica)
            let fileURL = self.cacheDirectory.appendingPathComponent("full_\(id).json")
            return self.fileManager.fileExists(atPath: fileURL.path)
        }
    }
    
    /// Verifica se una email è in cache (memoria o disco)
    func isEmailCached(id: String) -> Bool {
        return cacheQueue.sync { [weak self] in
            guard let self = self else { return false }
            
            // Controlla prima la memoria
            if self.memoryCache[id] != nil {
                return true
            }
            
            // Poi controlla il disco
            let fileURL = self.cacheDirectory.appendingPathComponent("full_\(id).json")
            return self.fileManager.fileExists(atPath: fileURL.path)
        }
    }
    
    /// Precarica email in memoria per accesso rapido
    func preloadEmails(ids: [String]) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            let idsToLoad = ids.filter { !self.memoryCache.keys.contains($0) }
            guard !idsToLoad.isEmpty else { return }
            
            print("[EmailCache] Precaricamento di \(idsToLoad.count) email in memoria")
            
            for id in idsToLoad {
                if let email = self.loadFullEmailFromDisk(id: id) {
                    self.updateMemoryCache(email: email, id: id)
                }
            }
        }
    }
    
    // MARK: - Email Index Management
    
    /// Salva l'indice completo delle email (tutte le email per tutte le caselle)
    func saveEmailIndex(_ index: [String: Email]) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            let fileURL = self.cacheDirectory.appendingPathComponent("email_index.json")
            
            do {
                let data = try JSONEncoder().encode(index)
                try data.write(to: fileURL)
                print("[EmailCache] ✅ Salvato indice email completo (\(index.count) email)")
            } catch {
                print("[EmailCache] ❌ Errore nel salvataggio dell'indice email: \(error)")
            }
        }
    }
    
    /// Carica l'indice completo delle email con validazione e recovery
    func loadEmailIndex() -> [String: Email]? {
        return cacheQueue.sync { [weak self] in
            guard let self = self else { return nil }
            
            let fileURL = self.cacheDirectory.appendingPathComponent("email_index.json")
            guard self.fileManager.fileExists(atPath: fileURL.path) else {
                print("[EmailCache] ℹ️ Indice email non trovato")
                return nil
            }
            
            do {
                let data = try Data(contentsOf: fileURL)
                
                // Validazione: verifica che il file non sia vuoto o troppo grande (possibile corruzione)
                guard !data.isEmpty else {
                    print("[EmailCache] ⚠️ Indice email vuoto - possibile corruzione, elimino")
                    try? self.fileManager.removeItem(at: fileURL)
                    return nil
                }
                
                // Limite di sicurezza: se il file è > 100MB, probabilmente è corrotto
                guard data.count < 100_000_000 else {
                    print("[EmailCache] ⚠️ Indice email troppo grande (\(data.count) bytes) - possibile corruzione, elimino")
                    try? self.fileManager.removeItem(at: fileURL)
                    return nil
                }
                
                let decoder = JSONDecoder()
                let index = try decoder.decode([String: Email].self, from: data)
                
                // Validazione: verifica che l'indice non sia vuoto dopo il decode
                guard !index.isEmpty else {
                    print("[EmailCache] ⚠️ Indice email vuoto dopo decode - possibile corruzione, elimino")
                    try? self.fileManager.removeItem(at: fileURL)
                    return nil
                }
                
                print("[EmailCache] ✅ Caricato indice email completo (\(index.count) email)")
                return index
            } catch {
                print("[EmailCache] ❌ Errore nel caricamento dell'indice email: \(error)")
                // Recovery: elimina il file corrotto per permettere ricreazione
                print("[EmailCache] 🔧 Recovery: elimino indice corrotto per permettere ricreazione")
                try? self.fileManager.removeItem(at: fileURL)
                return nil
            }
        }
    }
    
    /// Deduplica un array di email mantenendo solo la versione più recente per ogni messageId
    func deduplicateEmails(_ emails: [Email]) -> [Email] {
        var seen = Set<String>()
        var deduplicated: [Email] = []
        var duplicatesFound = 0
        
        // Ordina per data (più recente prima) per mantenere la versione più aggiornata
        let sorted = emails.sorted { $0.date > $1.date }
        
        for email in sorted {
            if !seen.contains(email.id) {
                seen.insert(email.id)
                deduplicated.append(email)
            } else {
                duplicatesFound += 1
            }
        }
        
        if duplicatesFound > 0 {
            print("[EmailCache] 🧹 Deduplicazione: rimossi \(duplicatesFound) duplicati da \(emails.count) email")
        }
        
        return deduplicated
    }
    
    // MARK: - Legacy Interface (per compatibilità - DEPRECATO)
    
    private func safeFileName(_ label: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return label.components(separatedBy: invalidChars).joined(separator: "_")
    }
    
    /// DEPRECATO: Usare EmailRepository invece. Mantenuto per backward compatibility.
    @available(*, deprecated, message: "Usare EmailRepository.addOrUpdateEmail invece")
    func saveEmails(_ emails: [Email], forLabel label: String) {
        // Deduplica prima di salvare
        let deduplicated = deduplicateEmails(emails)
        
        let fileURL = cacheDirectory.appendingPathComponent("\(safeFileName(label)).json")
        print("[EmailCache] ⚠️ DEPRECATO: Salvataggio legacy per label=\(label), file=\(fileURL.path)")
        
        // Assicurati che la directory esista
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(deduplicated)
                try data.write(to: fileURL)
                
                // Salva anche ogni email individualmente nella cache principale
                for email in deduplicated {
                    self.saveFullEmail(email, forId: email.id)
                }
            } catch {
                print("[EmailCache] Errore nel salvataggio della cache per \(label): \(error)")
            }
        }
    }
    
    func loadEmails(forLabel label: String) -> [Email] {
        let fileURL = cacheDirectory.appendingPathComponent("\(safeFileName(label)).json")
        print("[EmailCache] Lettura: label=\(label), file=\(fileURL.path)")
        
        // Assicurati che la directory esista
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            
            // Prova prima come array
            if let emails = try? decoder.decode([Email].self, from: data) {
                return emails
            }
            
            // Se fallisce, prova come singolo oggetto
            if let email = try? decoder.decode(Email.self, from: data) {
                return [email]
            }
            
            return []
        } catch {
            print("[EmailCache] Errore nel caricamento della cache per \(label): \(error)")
            return []
        }
    }
    
    /// DEPRECATO: Usare EmailRepository invece. Mantenuto per backward compatibility.
    @available(*, deprecated, message: "Usare EmailRepository.saveToCache invece")
    func saveAllMailboxes(_ mailboxes: [String: [Email]]) {
        print("[EmailCache] ⚠️ DEPRECATO: saveAllMailboxes chiamato - migrare a EmailRepository")
        
        for (label, emails) in mailboxes {
            // Deduplica prima di salvare
            let deduplicated = deduplicateEmails(emails)
            saveEmails(deduplicated, forLabel: label)
        }
    }
    
    func loadAllMailboxes() -> [String: [Email]] {
        return cacheQueue.sync {
            var result: [String: [Email]] = [:]
            do {
                let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
                for file in files where file.pathExtension == "json" && !file.lastPathComponent.hasPrefix("full_") {
                    let label = file.deletingPathExtension().lastPathComponent
                    result[label] = loadEmails(forLabel: label)
                }
            } catch {
                print("[EmailCache] Errore nel caricamento di tutte le caselle: \(error)")
            }
            return result
        }
    }
    
    /// Rimuove una singola email dalla cache (memoria e disco)
    func removeEmail(forId id: String) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Rimuovi dalla memoria
            self.memoryCache.removeValue(forKey: id)
            self.cacheAccessOrder.removeAll { $0 == id }
            
            // Rimuovi dal disco
            let fileURL = self.cacheDirectory.appendingPathComponent("full_\(id).json")
            if self.fileManager.fileExists(atPath: fileURL.path) {
                do {
                    try self.fileManager.removeItem(at: fileURL)
                    print("[EmailCache] 🗑️ Email \(id) rimossa dalla cache")
                } catch {
                    print("[EmailCache] ⚠️ Errore nella rimozione email \(id): \(error)")
                }
            }
        }
    }
    
    /// Pulisce la cache (memoria e disco)
    func clearCache() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Pulisci memoria
            self.memoryCache.removeAll()
            self.cacheAccessOrder.removeAll()
            
            // Pulisci disco
            do {
                let files = try self.fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil)
                for file in files {
                    try self.fileManager.removeItem(at: file)
                }
                print("[EmailCache] Cache pulita completamente")
            } catch {
                print("[EmailCache] Errore nella pulizia della cache: \(error)")
            }
        }
    }
    
    /// Ottieni statistiche della cache
    func getCacheStats() -> (memoryCount: Int, diskCount: Int, memoryLimit: Int) {
        return cacheQueue.sync { [weak self] in
            guard let self = self else { return (0, 0, 0) }
            
            let diskCount = (try? self.fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("full_") }.count) ?? 0
            
            return (self.memoryCache.count, diskCount, self.memoryCacheLimit)
        }
    }
    
    // MARK: - Private Methods
    
    private func updateMemoryCache(email: Email, id: String) {
        // Rimuovi dalla posizione corrente se esiste
        if memoryCache[id] != nil {
            cacheAccessOrder.removeAll { $0 == id }
        }
        
        // Aggiungi in cima
        memoryCache[id] = email
        cacheAccessOrder.insert(id, at: 0)
        
        // Evict se necessario (LRU)
        while memoryCache.count > memoryCacheLimit {
            if let oldestId = cacheAccessOrder.popLast() {
                memoryCache.removeValue(forKey: oldestId)
            }
        }
    }
    
    private func updateAccessOrder(for id: String) {
        cacheAccessOrder.removeAll { $0 == id }
        cacheAccessOrder.insert(id, at: 0)
    }
    
    private func loadFullEmailFromDisk(id: String) -> Email? {
        let fileURL = cacheDirectory.appendingPathComponent("full_\(id).json")
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            
            // Prova prima come singolo oggetto
            if let email = try? decoder.decode(Email.self, from: data) {
                // Aggiorna cache in memoria
                updateMemoryCache(email: email, id: id)
                return email
            }
            
            // Se fallisce, prova come array e prendi il primo elemento
            if let emails = try? decoder.decode([Email].self, from: data), let firstEmail = emails.first {
                updateMemoryCache(email: firstEmail, id: id)
                return firstEmail
            }
            
            return nil
        } catch {
            return nil
        }
    }
} 