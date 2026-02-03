import Foundation
import SwiftUI

// MARK: - Item Reconciliation Service

/// Servizio per la riconciliazione e normalizzazione di nomi di beni/componenti
/// Gestisce case-insensitive matching, fuzzy matching per errori di battitura,
/// e distinzione tra varianti legittime (es. "caldaia 1" vs "caldaia 2")
class ItemReconciliationService {
    static let shared = ItemReconciliationService()
    
    private init() {}
    
    /// Normalizza un nome: trim, rimuove spazi multipli
    func normalizeItemName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Rimuovi spazi multipli
        let normalized = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return normalized
    }
    
    /// Verifica se il nome contiene un identificatore numerico (es. "caldaia 1", "caldaia 2")
    /// che indica una variante legittima
    func hasNumericIdentifier(_ name: String) -> Bool {
        // Pattern: numero preceduto da spazio o trattino (es. " 1", "-2", " n.1")
        let patterns = [
            #"\s+\d+$"#,           // "caldaia 1"
            #"\s+n\.?\s*\d+$"#,    // "caldaia n.1" o "caldaia n 1"
            #"\s*-\s*\d+$"#,       // "caldaia-1"
            #"\s+\(\d+\)$"#        // "caldaia (1)"
        ]
        
        for pattern in patterns {
            if name.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
    
    /// Calcola la distanza di Levenshtein tra due stringhe
    func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1.lowercased())
        let s2Array = Array(s2.lowercased())
        let m = s1Array.count
        let n = s2Array.count
        
        if m == 0 { return n }
        if n == 0 { return m }
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }
        
        return matrix[m][n]
    }
    
    /// Calcola la similarità tra due stringhe (0.0 - 1.0)
    func similarity(_ s1: String, _ s2: String) -> Double {
        let maxLen = max(s1.count, s2.count)
        if maxLen == 0 { return 1.0 }
        let distance = levenshteinDistance(s1, s2)
        return 1.0 - (Double(distance) / Double(maxLen))
    }
    
    /// Trova un match per l'input nella lista di items esistenti
    /// Ritorna il nome normalizzato esistente se trova un match, altrimenti nil
    func findMatchingItem(_ input: String, in items: [String], fuzzyThreshold: Double = 0.85) -> String? {
        let normalizedInput = normalizeItemName(input)
        guard !normalizedInput.isEmpty else { return nil }
        
        // 1. Prima cerca match esatto (case-insensitive)
        if let exactMatch = items.first(where: { 
            normalizeItemName($0).localizedCaseInsensitiveCompare(normalizedInput) == .orderedSame 
        }) {
            return exactMatch
        }
        
        // 2. Se l'input ha un identificatore numerico, non fare fuzzy matching
        // perché potrebbe essere una variante legittima
        if hasNumericIdentifier(normalizedInput) {
            return nil
        }
        
        // 3. Fuzzy matching per errori di battitura
        var bestMatch: String?
        var bestSimilarity: Double = 0
        
        for item in items {
            // Salta items con identificatori numerici (sono varianti legittime)
            if hasNumericIdentifier(item) { continue }
            
            let normalizedItem = normalizeItemName(item)
            let sim = similarity(normalizedInput, normalizedItem)
            
            if sim >= fuzzyThreshold && sim > bestSimilarity {
                bestSimilarity = sim
                bestMatch = item
            }
        }
        
        return bestMatch
    }
    
    /// Riconcilia un nome con quelli esistenti nel sinistro e restituisce il nome normalizzato
    /// Se trova un match, ritorna il nome esistente; altrimenti ritorna il nome normalizzato
    func reconcile(_ name: String, withExisting existing: [String]) -> String {
        let normalized = normalizeItemName(name)
        guard !normalized.isEmpty else { return name }
        
        // Cerca un match
        if let match = findMatchingItem(normalized, in: existing) {
            return match
        }
        
        // Nessun match: ritorna normalizzato
        return normalized
    }
}

// MARK: - Common Items Manager

/// Gestisce le liste di beni e componenti comuni per l'autocompletamento tag foto
class CommonItemsManager: ObservableObject {
    static let shared = CommonItemsManager()
    
    private let reconciliationService = ItemReconciliationService.shared
    
    @Published var customBeni: [String] = []
    @Published var customComponenti: [String] = []
    
    private let customBeniKey = "CommonItemsManager.customBeni"
    private let customComponentiKey = "CommonItemsManager.customComponenti"
    
    // Lista predefinita di beni elettrici comuni
    static let defaultBeni: [String] = [
        "Lavatrice",
        "Asciugatrice",
        "Impianto elettrico",
        "Impianto di illuminazione",
        "Lavastoviglie",
        "Frigorifero",
        "Congelatore",
        "Frigorifero combinato",
        "Forno",
        "Forno a microonde",
        "Piano cottura a induzione",
        "Cappa aspirante",
        "Impianto citofonico",
        "Impianto Videocitofonico",
        "Impianto d'allarme",
        "Centrale allarme",
        "Televisore",
        "Decoder",
        "Parabola",
        "Router",
        "Modem",
        "Condizionatore",
        "Climatizzatore",
        "Pompa di calore",
        "Caldaia",
        "Scaldabagno",
        "Boiler elettrico",
        "Stufa elettrica",
        "Termoconvettore",
        "Aspirapolvere",
        "Robot aspirapolvere",
        "Macchina da caffè",
        "Tostapane",
        "Bollitore",
        "Impastatrice",
        "Robot da cucina",
        "Frullatore",
        "Asciugacapelli",
        "Piastra per capelli",
        "Computer",
        "Notebook",
        "Monitor",
        "Stampante",
        "Console giochi",
        "Impianto stereo",
        "Impianto antenna televisiva",
        "Soundbar",
        "Fotocamera",
        "Videocamera",
        "Cancello elettrico",
        "Motore cancello",
        "Serranda elettrica",
        "Persiana elettrica",
        "Domotica",
        "Centralina domotica",
        "Ascensore",
        "Montacarichi",
        "Pompa sommersa",
        "Pompa di sollevamento",
        "Autoclave",
        "Addolcitore",
        "Depuratore acqua",
        "Impianto fotovoltaico",
        "fotovoltaico"
    ]
    
    // Lista predefinita di componenti comuni
    static let defaultComponenti: [String] = [
        "Scheda di alimentazione",
        "Scheda di controllo",
        "Scheda madre",
        "Scheda elettronica",
        "Inverter",
        "Compressore",
        "Motore",
        "Motoriduttore",
        "Condensatore",
        "Trasformatore",
        "Alimentatore",
        "Display",
        "Display LCD",
        "Pannello comandi",
        "Tastiera",
        "Telecomando",
        "Sensore temperatura",
        "Termostato",
        "Sonda",
        "Pressostato",
        "Elettrovalvola",
        "Pompa",
        "Pompa di scarico",
        "Pompa di circolazione",
        "Resistenza",
        "Resistenza riscaldante",
        "Ventola",
        "Ventilatore",
        "Relè",
        "Contattore",
        "Fusibile",
        "Interruttore",
        "Selettore",
        "Manopola",
        "Cavo alimentazione",
        "Cablaggio",
        "Connettore",
        "Morsettiera",
        "Batteria",
        "Batteria tampone",
        "Magnetotermico",
        "Differenziale",
        "Scaricatore SPD",
        "Varistor",
        "Modulo GSM",
        "Modulo WiFi",
        "Antenna",
        "Ricevitore",
        "Trasmettitore",
        "Gruppo ottico",
        "Obiettivo",
        "Unità esterna",
        "Unità interna",
        "Evaporatore",
        "Condensatore esterno",
        "Valvola espansione",
        "Bruciatore",
        "Scambiatore",
        "cavi elettrici",
        "componenti non elettriche",
        "Elettrodo accensione",
        "Sonda fumi"
    ]
    
    private init() {
        loadCustomItems()
    }
    
    /// Tutti i beni disponibili (default + custom)
    var allBeni: [String] {
        let combined = Set(Self.defaultBeni).union(Set(customBeni))
        return Array(combined).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    /// Tutti i componenti disponibili (default + custom)
    var allComponenti: [String] {
        let combined = Set(Self.defaultComponenti).union(Set(customComponenti))
        return Array(combined).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    /// Aggiunge un bene custom se non esiste già
    func addCustomBene(_ bene: String) {
        let trimmed = bene.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Verifica se esiste già (case insensitive)
        let exists = allBeni.contains { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        if !exists {
            customBeni.append(trimmed)
            saveCustomItems()
            objectWillChange.send()
        }
    }
    
    /// Aggiunge un componente custom se non esiste già
    func addCustomComponente(_ componente: String) {
        let trimmed = componente.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Verifica se esiste già (case insensitive)
        let exists = allComponenti.contains { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        if !exists {
            customComponenti.append(trimmed)
            saveCustomItems()
            objectWillChange.send()
        }
    }
    
    /// Ottiene i beni già usati nel sinistro (per priorità nei suggerimenti)
    func getBeniUsedInSinistro(sinistroPath: String) async -> [String] {
        let fileTagManager = FileTagManager.shared
        var usedBeni: Set<String> = []
        
        let fileTags = await MainActor.run {
            fileTagManager.fileTags
        }
        
        for (path, tags) in fileTags {
            guard path.hasPrefix(sinistroPath) else { continue }
            
            for tag in tags where tag.id == "foto_bene" {
                let bene = await fileTagManager.getAdditionalText(forFile: path, tagId: tag.id)
                if let bene = bene, !bene.isEmpty {
                    usedBeni.insert(bene)
                }
            }
            
            // Anche i beni di riferimento usati in foto_componente
            for tag in tags where FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id) {
                let bene = await fileTagManager.getBeneRiferimento(forFile: path, tagId: tag.id)
                if let bene = bene, !bene.isEmpty {
                    usedBeni.insert(bene)
                }
            }
        }
        
        return Array(usedBeni).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    /// Ottiene i componenti già usati nel sinistro (per priorità nei suggerimenti)
    func getComponentiUsedInSinistro(sinistroPath: String) async -> [String] {
        let fileTagManager = FileTagManager.shared
        var usedComponenti: Set<String> = []
        
        let fileTags = await MainActor.run {
            fileTagManager.fileTags
        }
        
        for (path, tags) in fileTags {
            guard path.hasPrefix(sinistroPath) else { continue }
            
            for tag in tags where tag.id == "foto_componente" {
                let componente = await fileTagManager.getAdditionalText(forFile: path, tagId: tag.id)
                if let componente = componente, !componente.isEmpty {
                    usedComponenti.insert(componente)
                }
            }
        }
        
        return Array(usedComponenti).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    /// Ottiene suggerimenti per beni ordinati: prima quelli usati nel sinistro, poi gli altri
    func getBeniSuggestions(for query: String, sinistroPath: String?) async -> [String] {
        let usedInSinistro = sinistroPath != nil ? await getBeniUsedInSinistro(sinistroPath: sinistroPath!) : []
        let otherBeni = allBeni.filter { bene in
            !usedInSinistro.contains { $0.localizedCaseInsensitiveCompare(bene) == .orderedSame }
        }
        
        let filter: (String) -> Bool = { item in
            query.isEmpty || item.localizedCaseInsensitiveContains(query)
        }
        
        let filteredUsed = usedInSinistro.filter(filter)
        let filteredOthers = otherBeni.filter(filter)
        
        return filteredUsed + filteredOthers
    }
    
    /// Ottiene suggerimenti per componenti ordinati: prima quelli usati nel sinistro, poi gli altri
    func getComponentiSuggestions(for query: String, sinistroPath: String?) async -> [String] {
        let usedInSinistro = sinistroPath != nil ? await getComponentiUsedInSinistro(sinistroPath: sinistroPath!) : []
        let otherComponenti = allComponenti.filter { comp in
            !usedInSinistro.contains { $0.localizedCaseInsensitiveCompare(comp) == .orderedSame }
        }
        
        let filter: (String) -> Bool = { item in
            query.isEmpty || item.localizedCaseInsensitiveContains(query)
        }
        
        let filteredUsed = usedInSinistro.filter(filter)
        let filteredOthers = otherComponenti.filter(filter)
        
        return filteredUsed + filteredOthers
    }
    
    // MARK: - Riconciliazione
    
    /// Riconcilia un nome bene con quelli esistenti nel sinistro
    /// Gestisce case-insensitive e fuzzy matching per errori di battitura
    func reconcileBene(_ name: String, sinistroPath: String?) async -> String {
        var existing: [String] = allBeni
        
        // Aggiungi anche i beni usati nel sinistro (potrebbero essere custom non ancora salvati)
        if let path = sinistroPath {
            let usedInSinistro = await getBeniUsedInSinistro(sinistroPath: path)
            existing = Array(Set(existing + usedInSinistro))
        }
        
        return reconciliationService.reconcile(name, withExisting: existing)
    }
    
    /// Riconcilia un nome componente con quelli esistenti nel sinistro
    /// Gestisce case-insensitive e fuzzy matching per errori di battitura
    func reconcileComponente(_ name: String, sinistroPath: String?) async -> String {
        var existing: [String] = allComponenti
        
        // Aggiungi anche i componenti usati nel sinistro (potrebbero essere custom non ancora salvati)
        if let path = sinistroPath {
            let usedInSinistro = await getComponentiUsedInSinistro(sinistroPath: path)
            existing = Array(Set(existing + usedInSinistro))
        }
        
        return reconciliationService.reconcile(name, withExisting: existing)
    }
    
    /// Normalizza un nome (senza riconciliazione, solo pulizia)
    func normalize(_ name: String) -> String {
        return reconciliationService.normalizeItemName(name)
    }
    
    // MARK: - Persistenza
    
    private func saveCustomItems() {
        if let beniData = try? JSONEncoder().encode(customBeni) {
            UserDefaults.standard.set(beniData, forKey: customBeniKey)
        }
        if let componentiData = try? JSONEncoder().encode(customComponenti) {
            UserDefaults.standard.set(componentiData, forKey: customComponentiKey)
        }
    }
    
    private func loadCustomItems() {
        if let beniData = UserDefaults.standard.data(forKey: customBeniKey),
           let beni = try? JSONDecoder().decode([String].self, from: beniData) {
            customBeni = beni
        }
        if let componentiData = UserDefaults.standard.data(forKey: customComponentiKey),
           let componenti = try? JSONDecoder().decode([String].self, from: componentiData) {
            customComponenti = componenti
        }
    }
}
