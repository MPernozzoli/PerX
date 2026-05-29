//
//  CloudKitRubricaSyncService.swift
//  PerX
//
//  Servizio rubrica agenzie. CloudKit e' stato rimosso dal runtime.
//  NOTA: Gruppi e Compagnie sono presi da CompagniaService (enum fissi, non editabili)
//

import Foundation
import CoreData
import Combine

@MainActor
final class CloudKitRubricaSyncService: ObservableObject {
    static let shared = CloudKitRubricaSyncService()
    
    // MARK: - Published State
    
    // NOTA: Gruppi e Compagnie usano gli enum da CompagniaService, non sono sincronizzati
    // Accedi tramite GruppoAssicurativo.allCases e Compagnia.allCases
    
    @Published private(set) var agenzie: [RubricaAgenzia] = []
    @Published private(set) var agenti: [RubricaAgente] = []
    @Published private(set) var liquidatori: [RubricaLiquidatore] = []
    
    @Published private(set) var isLoading = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var error: String?
    
    // MARK: - Private
    
    private var cancellables = Set<AnyCancellable>()
    private let backend = BackendAPIClient.shared
    
    private init() {
        // Cache caricata in loadInitial() in background per non bloccare la UI
    }
    
    // MARK: - Gruppi e Compagnie (da CompagniaService, non editabili)
    
    /// Tutti i gruppi assicurativi (da enum)
    var gruppi: [GruppoAssicurativo] {
        GruppoAssicurativo.allCases.filter { $0 != .unknown }
    }
    
    /// Tutte le compagnie (da enum)
    var compagnie: [Compagnia] {
        Compagnia.allCases.filter { $0 != .unknown }
    }
    
    /// Compagnie per un gruppo specifico
    func compagniePer(gruppo: GruppoAssicurativo) -> [Compagnia] {
        gruppo.compagnie
    }
    
    // MARK: - Public API
    
    /// Ricarica i dati dal backend Supabase, con fallback su cache locale.
    func syncAll() async {
        guard !isSyncing else { return }
        
        isSyncing = true
        error = nil
        
        defer { isSyncing = false }
        
        do {
            let (a, ag, l): ([RubricaAgenzia], [RubricaAgente], [RubricaLiquidatore])
            if backend.isConfigured && backend.hasAccessToken {
                let response: RubricaAllDTO = try await backend.get("rubrica/all")
                a = response.agenzie.map { $0.toRubricaAgenzia() }
                ag = response.agenti.map { $0.toRubricaAgente() }
                l = response.liquidatori.map { $0.toRubricaLiquidatore() }
            } else {
                (a, ag, l) = try await (fetchAgenzie(), fetchAgenti(), fetchLiquidatori())
            }
            
            // Merge e sort in background per non saturare la CPU sul main thread
            let (mergedAgenzie, sortedAgenti, sortedLiquidatori) = await Task.detached(priority: .utility) {
                let merged = Self.mergeDuplicateAgenzieStatic(a)
                return (
                    merged.sorted { $0.nome < $1.nome },
                    ag.sorted { $0.cognome < $1.cognome },
                    l.sorted { $0.cognome < $1.cognome }
                )
            }.value
            
            agenzie = mergedAgenzie
            agenti = sortedAgenti
            liquidatori = sortedLiquidatori
            lastSyncDate = Date()
            saveToLocalCache()
            
            print("[RubricaSync] Rubrica caricata: \(agenzie.count) agenzie, \(agenti.count) agenti, \(liquidatori.count) liquidatori")
            
        } catch {
            self.error = error.localizedDescription
            print("[RubricaSync] Errore sync: \(error)")
        }
    }
    
    /// Carica i dati iniziali da cache locale. Lavoro pesante in background per non bloccare la UI.
    func loadInitial() async {
        guard agenzie.isEmpty else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        // Carica cache in background (decode JSON fuori dal main thread)
        let cacheData: (agenzie: [RubricaAgenzia], agenti: [RubricaAgente], liquidatori: [RubricaLiquidatore], lastSync: Date?)? = await Task.detached(priority: .userInitiated) { [cacheURL] in
            guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }
            guard let data = try? Data(contentsOf: cacheURL),
                  let cache = try? JSONDecoder().decode(CacheData.self, from: data) else { return nil }
            return (cache.agenzie, cache.agenti, cache.liquidatori, cache.lastSync)
        }.value
        
        if let cache = cacheData, !cache.agenzie.isEmpty {
            agenzie = cache.agenzie
            agenti = cache.agenti
            liquidatori = cache.liquidatori
            lastSyncDate = cache.lastSync
        }
        
        await syncAll()
    }
    
    // MARK: - CRUD Agenzie
    
    func saveAgenzia(_ agenzia: RubricaAgenzia) async throws {
        var a = agenzia
        a.lastModified = Date()
        addOrUpdateAgenziaLocally(a)
        guard backend.isConfigured && backend.hasAccessToken else { return }
        do {
            let saved: RubricaAgenziaDTO = try await backend.put("rubrica/agenzie/\(a.id)", body: RubricaAgenziaUpsertDTO(agenzia: a))
            addOrUpdateAgenziaLocally(saved.toRubricaAgenzia())
        } catch BackendAPIError.notFound {
            let saved: RubricaAgenziaDTO = try await backend.post("rubrica/agenzie", body: RubricaAgenziaUpsertDTO(agenzia: a))
            addOrUpdateAgenziaLocally(saved.toRubricaAgenzia())
        }
    }
    
    /// Mantiene compatibilita' con il vecchio import: ora aggiorna solo cache locale.
    private func saveAgenziaToCloudOnly(_ agenzia: RubricaAgenzia) async throws {
        var a = agenzia
        a.lastModified = Date()
        addOrUpdateAgenziaLocally(a)
        if backend.isConfigured && backend.hasAccessToken {
            try await saveAgenzia(a)
        }
    }
    
    /// Aggiorna solo l'array locale e la cache. lastModified va impostato dal chiamante (solo in caso di modifica effettiva).
    private func addOrUpdateAgenziaLocally(_ agenzia: RubricaAgenzia) {
        let a = agenzia
        if let index = agenzie.firstIndex(where: { $0.id == a.id }) {
            agenzie[index] = a
        } else {
            agenzie.append(a)
            agenzie.sort { $0.nome < $1.nome }
        }
        saveToLocalCache()
    }
    
    func deleteAgenzia(_ id: String) async throws {
        if backend.isConfigured && backend.hasAccessToken {
            try await backend.delete("rubrica/agenzie/\(id)")
        }
        // Trova e rimuovi filiali associate
        let filialiIds = agenzie.filter { $0.agenziaParentId == id }.map { $0.id }

        agenzie.removeAll { $0.id == id || $0.agenziaParentId == id }
        // Rimuovi agenti associati all'agenzia e alle filiali
        agenti.removeAll { $0.agenziaId == id || filialiIds.contains($0.agenziaId) }
        
        saveToLocalCache()
    }
    
    /// DEBUG: Cancella tutte le agenzie, agenti e liquidatori locali.
    func deleteAllData() async {
        print("[RubricaSync] 🗑️ Cancellazione completa rubrica...")

        // Svuota liste locali
        agenzie.removeAll()
        agenti.removeAll()
        liquidatori.removeAll()
        
        // Cancella cache locale
        try? FileManager.default.removeItem(at: cacheURL)
        
        print("[RubricaSync] ✅ Rubrica cancellata completamente")
    }
    
    // MARK: - CRUD Agenti
    
    func saveAgente(_ agente: RubricaAgente) async throws {
        var a = agente
        a.lastModified = Date()

        upsertAgenteLocally(a)
        guard backend.isConfigured && backend.hasAccessToken else { return }
        do {
            let saved: RubricaAgenteDTO = try await backend.put("rubrica/agenti/\(a.id)", body: RubricaAgenteUpsertDTO(agente: a))
            upsertAgenteLocally(saved.toRubricaAgente())
        } catch BackendAPIError.notFound {
            let saved: RubricaAgenteDTO = try await backend.post("rubrica/agenti", body: RubricaAgenteUpsertDTO(agente: a))
            upsertAgenteLocally(saved.toRubricaAgente())
        }
    }
    
    func deleteAgente(_ id: String) async throws {
        if backend.isConfigured && backend.hasAccessToken {
            try await backend.delete("rubrica/agenti/\(id)")
        }
        agenti.removeAll { $0.id == id }
        saveToLocalCache()
    }

    private func upsertAgenteLocally(_ agente: RubricaAgente) {
        if let index = agenti.firstIndex(where: { $0.id == agente.id }) {
            agenti[index] = agente
        } else {
            agenti.append(agente)
        }
        agenti.sort { $0.cognome < $1.cognome }
        saveToLocalCache()
    }
    
    // MARK: - CRUD Liquidatori
    
    func saveLiquidatore(_ liquidatore: RubricaLiquidatore) async throws {
        var l = liquidatore
        l.lastModified = Date()

        if let index = liquidatori.firstIndex(where: { $0.id == l.id }) {
            liquidatori[index] = l
        } else {
            liquidatori.append(l)
            liquidatori.sort { $0.cognome < $1.cognome }
        }
        
        saveToLocalCache()
        guard backend.isConfigured && backend.hasAccessToken else { return }
        do {
            let saved: RubricaLiquidatoreDTO = try await backend.put("rubrica/liquidatori/\(l.id)", body: RubricaLiquidatoreUpsertDTO(liquidatore: l))
            upsertLiquidatoreLocally(saved.toRubricaLiquidatore())
        } catch BackendAPIError.notFound {
            let saved: RubricaLiquidatoreDTO = try await backend.post("rubrica/liquidatori", body: RubricaLiquidatoreUpsertDTO(liquidatore: l))
            upsertLiquidatoreLocally(saved.toRubricaLiquidatore())
        }
    }
    
    func deleteLiquidatore(_ id: String) async throws {
        if backend.isConfigured && backend.hasAccessToken {
            try await backend.delete("rubrica/liquidatori/\(id)")
        }
        liquidatori.removeAll { $0.id == id }
        saveToLocalCache()
    }

    private func upsertLiquidatoreLocally(_ liquidatore: RubricaLiquidatore) {
        if let index = liquidatori.firstIndex(where: { $0.id == liquidatore.id }) {
            liquidatori[index] = liquidatore
        } else {
            liquidatori.append(liquidatore)
        }
        liquidatori.sort { $0.cognome < $1.cognome }
        saveToLocalCache()
    }
    
    // MARK: - Query Helpers
    
    /// Trova agenzia per codice (principale o alternativo)
    func findAgenziaByCodice(_ codice: String) -> RubricaAgenzia? {
        agenzie.first { $0.matches(codice: codice) }
    }
    
    /// Trova agenzia per codice (principale o alternativo) E nome (match esatto)
    func findAgenziaByMatch(codice: String?, nome: String?) -> RubricaAgenzia? {
        guard let codice = codice?.trimmingCharacters(in: .whitespaces).uppercased(),
              let nome = nome?.trimmingCharacters(in: .whitespaces).lowercased(),
              !codice.isEmpty, !nome.isEmpty else {
            return nil
        }
        
        return agenzie.first { agenzia in
            agenzia.matches(codice: codice) &&
            agenzia.nome.lowercased() == nome
        }
    }
    
    /// Tenta di associare automaticamente la compagnia a un'agenzia non abbinata
    /// basandosi sui dati del sinistro
    /// - Parameters:
    ///   - codiceAgenzia: Codice agenzia dal sinistro
    ///   - nomeAgenzia: Nome agenzia dal sinistro
    ///   - nomeCompagnia: Nome compagnia dal sinistro
    ///   - gruppo: Gruppo dal sinistro
    /// - Returns: true se l'agenzia è stata aggiornata
    @discardableResult
    func tryAutoAssociateCompagnia(
        codiceAgenzia: String?,
        nomeAgenzia: String?,
        nomeCompagnia: String?,
        gruppo: String?
    ) async -> Bool {
        // Trova l'agenzia con match esatto
        guard let agenzia = findAgenziaByMatch(codice: codiceAgenzia, nome: nomeAgenzia) else {
            return false
        }
        
        // Solo se l'agenzia non ha compagnia assegnata (è "Altro")
        guard agenzia.compagniaId == Compagnia.unknown.rubricaId else {
            return false
        }
        
        // Determina la compagnia dai dati del sinistro
        let compagnia = Compagnia.detect(gruppo: gruppo, compagnia: nomeCompagnia)
        
        // Se abbiamo trovato una compagnia valida, aggiorna l'agenzia
        guard compagnia != .unknown else {
            return false
        }
        
        var agenziaAggiornata = agenzia
        agenziaAggiornata.compagniaId = compagnia.rubricaId
        
        do {
            try await saveAgenzia(agenziaAggiornata)
            print("[RubricaSync] ✅ Auto-associata agenzia '\(agenzia.nome)' a \(compagnia.rawValue)")
            return true
        } catch {
            print("[RubricaSync] ❌ Errore auto-associazione: \(error)")
            return false
        }
    }
    
    // MARK: - Scansione Background Sinistri
    
    @Published var isScanning = false
    @Published var scanProgress: (current: Int, total: Int, associated: Int) = (0, 0, 0)
    
    /// Scansiona tutti i sinistri e associa automaticamente le compagnie alle agenzie non abbinate
    /// - Parameter context: Core Data context per leggere i sinistri
    /// - Returns: Numero di agenzie associate
    @discardableResult
    func scanAndAssociateFromSinistri(context: NSManagedObjectContext) async -> Int {
        guard !isScanning else { return 0 }
        
        isScanning = true
        defer { isScanning = false }
        
        // Trova agenzie non abbinate
        let agenzieNonAbbinate = agenzie.filter { $0.compagniaId == Compagnia.unknown.rubricaId }
        guard !agenzieNonAbbinate.isEmpty else {
            print("[RubricaSync] Nessuna agenzia da abbinare")
            return 0
        }
        
        print("[RubricaSync] 🔍 Scansione sinistri per \(agenzieNonAbbinate.count) agenzie non abbinate...")
        
        // Fetch tutti i sinistri con codice e nome agenzia
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Sinistro")
        request.propertiesToFetch = ["codiceAgenzia", "agenzia", "nomeCompagnia", "gruppo"]
        request.resultType = .dictionaryResultType
        
        var sinistri: [[String: Any]] = []
        do {
            sinistri = try await context.perform {
                (try? context.fetch(request) as? [[String: Any]]) ?? []
            }
        } catch {
            print("[RubricaSync] Errore fetch sinistri: \(error)")
            return 0
        }
        
        scanProgress = (0, sinistri.count, 0)
        var associatedCount = 0
        
        // Itera sui sinistri e cerca match
        for (index, sinistro) in sinistri.enumerated() {
            let codiceAgenzia = sinistro["codiceAgenzia"] as? String
            let nomeAgenzia = sinistro["agenzia"] as? String
            let nomeCompagnia = sinistro["nomeCompagnia"] as? String
            let gruppo = sinistro["gruppo"] as? String
            
            // Salta se non ha dati agenzia validi
            guard let codice = codiceAgenzia, !codice.isEmpty,
                  let nome = nomeAgenzia, !nome.isEmpty else {
                continue
            }
            
            // Prova ad associare
            let associated = await tryAutoAssociateCompagnia(
                codiceAgenzia: codice,
                nomeAgenzia: nome,
                nomeCompagnia: nomeCompagnia,
                gruppo: gruppo
            )
            
            if associated {
                associatedCount += 1
            }
            
            // Aggiorna progresso ogni 100 sinistri
            if index % 100 == 0 {
                scanProgress = (index, sinistri.count, associatedCount)
            }
            
            // Yield per non bloccare
            if index % 500 == 0 {
                await Task.yield()
            }
        }
        
        scanProgress = (sinistri.count, sinistri.count, associatedCount)
        print("[RubricaSync] ✅ Scansione completata: \(associatedCount) agenzie associate su \(sinistri.count) sinistri")
        
        return associatedCount
    }
    
    /// Avvia la scansione in background (non bloccante)
    func startBackgroundScan(context: NSManagedObjectContext) {
        Task.detached(priority: .utility) { [weak self] in
            await self?.scanAndAssociateFromSinistri(context: context)
        }
    }
    
    /// Trova agenzie per compagnia (solo principali, esclude filiali)
    func agenziePer(compagniaId: String) -> [RubricaAgenzia] {
        agenzie.filter { $0.compagniaId == compagniaId && !$0.isFiliale }
    }
    
    /// Trova tutte le agenzie per compagnia (incluse filiali)
    func tutteAgenziePer(compagniaId: String) -> [RubricaAgenzia] {
        agenzie.filter { $0.compagniaId == compagniaId }
    }
    
    /// Trova filiali di un'agenzia madre
    func filialiPer(agenziaId: String) -> [RubricaAgenzia] {
        agenzie.filter { $0.agenziaParentId == agenziaId }
    }
    
    /// Verifica se un'agenzia ha filiali
    func hasFiliali(_ agenziaId: String) -> Bool {
        agenzie.contains { $0.agenziaParentId == agenziaId }
    }
    
    /// Conta filiali di un'agenzia
    func countFiliali(_ agenziaId: String) -> Int {
        agenzie.filter { $0.agenziaParentId == agenziaId }.count
    }
    
    /// Trova agenti per agenzia
    func agentiPer(agenziaId: String) -> [RubricaAgente] {
        agenti.filter { $0.agenziaId == agenziaId }
    }
    
    /// Trova agenzie per compagnia (usando enum Compagnia)
    func agenziePer(compagnia: Compagnia) -> [RubricaAgenzia] {
        agenziePer(compagniaId: compagnia.rubricaId)
    }
    
    /// Cerca agenzie per testo (nome, codice, città, telefono, email)
    func searchAgenzie(_ query: String, limit: Int = 50) -> [RubricaAgenzia] {
        guard query.count >= 2 else { return [] }
        
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        
        func matchesQuery(_ agenzia: RubricaAgenzia) -> Bool {
            var searchFields: [String] = []
            searchFields.append(agenzia.nome)
            searchFields.append(agenzia.codice)
            searchFields.append(contentsOf: agenzia.tuttiICodici)
            searchFields.append(agenzia.citta ?? "")
            searchFields.append(agenzia.provincia ?? "")
            searchFields.append(agenzia.indirizzo ?? "")
            searchFields.append(agenzia.note ?? "")
            searchFields.append(agenzia.descrAreaLegacy ?? "")
            searchFields.append(agenzia.suffissoNome ?? "")
            searchFields.append(contentsOf: agenzia.telefoni)
            searchFields.append(contentsOf: agenzia.email)
            return searchFields.contains { $0.lowercased().contains(q) }
        }
        
        return agenzie.filter { matchesQuery($0) }.prefix(limit).map { $0 }
    }
    
    // MARK: - Dedup e merge agenzie
    
    /// Chiave univoca per identificare lo stesso soggetto agenzia (compagnia + codice + parent)
    private func agenziaMergeKey(_ a: RubricaAgenzia) -> String {
        Self.agenziaMergeKeyStatic(a)
    }
    
    private nonisolated static func agenziaMergeKeyStatic(_ a: RubricaAgenzia) -> String {
        let codiceNorm = a.codice.trimmingCharacters(in: .whitespaces).uppercased()
        let parent = a.agenziaParentId ?? ""
        return "\(a.compagniaId)|\(codiceNorm)|\(parent)"
    }
    
    /// Deduplica agenzie con stessa chiave (compagnia+codice+parent) e le unisce. Versione statica per esecuzione in Task.detached.
    private nonisolated static func mergeDuplicateAgenzieStatic(_ list: [RubricaAgenzia]) -> [RubricaAgenzia] {
        let grouped = Dictionary(grouping: list) { agenziaMergeKeyStatic($0) }
        return grouped.compactMap { _, group -> RubricaAgenzia? in
            guard let keeper = group.max(by: { $0.lastModified < $1.lastModified }) else { return nil }
            if group.count == 1 { return keeper }
            var merged = keeper
            for other in group where other.id != keeper.id {
                merged.problematica = merged.problematica || other.problematica
                merged.puntigliosa = merged.puntigliosa || other.puntigliosa
                merged.critica = merged.critica || other.critica
                merged.comunicareSempreEsitiInAgenzia = merged.comunicareSempreEsitiInAgenzia || other.comunicareSempreEsitiInAgenzia
                merged.attiSempreInAgenzia = merged.attiSempreInAgenzia || other.attiSempreInAgenzia
                merged.chiamarePrimaDiInviareAtti = merged.chiamarePrimaDiInviareAtti || other.chiamarePrimaDiInviareAtti
                merged.prioritaria = merged.prioritaria || other.prioritaria
                merged.telefoni = Array(Set(merged.telefoni + other.telefoni)).sorted()
                merged.email = Array(Set(merged.email + other.email)).sorted()
                merged.codiciAlternativi = Array(Set(merged.codiciAlternativi + other.codiciAlternativi + [other.codice].filter { !$0.isEmpty })).filter { $0.uppercased() != merged.codice.uppercased() }.sorted()
                if (merged.note ?? "").isEmpty, let n = other.note, !n.isEmpty { merged.note = n }
                if (merged.indirizzo ?? "").isEmpty, let i = other.indirizzo, !i.isEmpty { merged.indirizzo = i }
            }
            return merged
        }
    }
    
    private func mergeDuplicateAgenzie(_ list: [RubricaAgenzia]) -> [RubricaAgenzia] {
        Self.mergeDuplicateAgenzieStatic(list)
    }
    
    // MARK: - Fetch locale
    
    private func fetchAgenzie() async throws -> [RubricaAgenzia] {
        agenzie
    }
    
    private func fetchAgenti() async throws -> [RubricaAgente] {
        agenti
    }
    
    private func fetchLiquidatori() async throws -> [RubricaLiquidatore] {
        liquidatori
    }
    
    // MARK: - Local Cache
    
    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RubricaCache_v2.json") // v2: senza gruppi/compagnie
    }
    
    private struct CacheData: Codable {
        // NOTA: gruppi e compagnie non sono più in cache (usano enum fissi)
        var agenzie: [RubricaAgenzia]
        var agenti: [RubricaAgente]
        var liquidatori: [RubricaLiquidatore]
        var lastSync: Date?
    }
    
    private func saveToLocalCache() {
        let data = CacheData(
            agenzie: agenzie,
            agenti: agenti,
            liquidatori: liquidatori,
            lastSync: lastSyncDate
        )
        
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: cacheURL)
        } catch {
            print("[RubricaSync] Errore salvataggio cache: \(error)")
        }
    }
    
    private func loadFromLocalCache() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: cacheURL)
            let cache = try JSONDecoder().decode(CacheData.self, from: data)
            
            agenzie = cache.agenzie
            agenti = cache.agenti
            liquidatori = cache.liquidatori
            lastSyncDate = cache.lastSync
            
            print("[RubricaSync] Cache caricata: \(agenzie.count) agenzie")
        } catch {
            print("[RubricaSync] Errore caricamento cache: \(error)")
        }
    }
    
    // MARK: - Migration from JSON
    
    /// Importa dati da JSON (supporta più formati) - da URL
    func importFromLegacyJSON(url: URL) async throws -> Int {
        let data = try Data(contentsOf: url)
        return try await importFromData(data)
    }
    
    /// Importa dati da JSON (supporta più formati) - da Data
    func importFromData(_ data: Data) async throws -> Int {
        print("[RubricaSync] Ricevuti \(data.count) bytes")
        
        // Debug: mostra primi 500 caratteri
        if let preview = String(data: data.prefix(500), encoding: .utf8) {
            print("[RubricaSync] Preview JSON: \(preview)")
        }
        
        // Prova prima il nuovo formato semplificato
        do {
            let count = try await importNewFormat(data: data)
            return count
        } catch {
            print("[RubricaSync] Errore nuovo formato: \(error)")
        }
        
        // Fallback al vecchio formato legacy
        do {
            return try await importOldFormat(data: data)
        } catch {
            print("[RubricaSync] Errore vecchio formato: \(error)")
            throw error
        }
    }
    
    // MARK: - Parse per Preview (senza salvataggio)
    
    /// Parsa i dati JSON e restituisce un array di AgenziaImportItem per la preview
    func parseAgenzieFromData(_ data: Data) async throws -> [AgenziaImportItem] {
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            // Prova vecchio formato
            return try await parseOldFormatForPreview(data: data)
        }
        
        return try await parseNewFormatForPreview(jsonArray: jsonArray)
    }
    
    /// Parse nuovo formato per preview
    private func parseNewFormatForPreview(jsonArray: [[String: Any]]) async throws -> [AgenziaImportItem] {
        var rows: [ParsedAgenziaRow] = []
        
        for obj in jsonArray {
            // Estrai codici
            var codici: [String] = []
            if let codesArray = obj["codici_agenzia"] as? [String] {
                codici = codesArray.map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
            } else if let codiciRaw = obj["codici_agenzia"] as? String {
                codici = codiciRaw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
            }
            if codici.isEmpty, let singolo = obj["codice_agenzia"] as? String {
                let c = singolo.trimmingCharacters(in: .whitespaces).uppercased()
                if !c.isEmpty { codici = [c] }
            }
            
            // Estrai nome
            let nome = (obj["nome_agenzia"] as? String ?? obj["nome"] as? String ?? obj["ragione_sociale"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            
            // Estrai compagnia
            let compagniaStr = obj["compagnia"] as? String ?? obj["descr_area"] as? String ?? ""
            let compagnia = Compagnia.detect(gruppo: nil, compagnia: compagniaStr)
            
            // Telefoni
            var telefoni: [String] = []
            for key in ["telefono_1", "telefono_2", "telefono1", "telefono2", "telefono"] {
                if let t = obj[key] as? String, !t.trimmingCharacters(in: .whitespaces).isEmpty {
                    telefoni.append(t.trimmingCharacters(in: .whitespaces))
                }
            }
            
            // Email
            var emails: [String] = []
            for key in ["email_1", "email_2", "email1", "email2", "email"] {
                if let e = obj[key] as? String, !e.trimmingCharacters(in: .whitespaces).isEmpty {
                    emails.append(e.trimmingCharacters(in: .whitespaces).lowercased())
                }
            }
            
            // Indirizzo
            let indirizzoRaw = obj["indirizzo"] as? String ?? ""
            var indirizzo = indirizzoRaw
            var citta: String?
            var provincia: String?
            var cap: String?
            
            // Parse indirizzo se contiene città/provincia
            if let c = obj["citta"] as? String { citta = c }
            if let p = obj["provincia"] as? String { provincia = p }
            if let c = obj["cap"] as? String { cap = c }
            
            rows.append(ParsedAgenziaRow(
                codici: codici,
                nome: nome,
                compagnia: compagnia,
                telefoni: telefoni,
                email: emails,
                indirizzo: indirizzo.isEmpty ? nil : indirizzo,
                citta: citta,
                provincia: provincia,
                cap: cap
            ))
        }
        
        // Raggruppa duplicati
        var parent = Array(0..<rows.count)
        func find(_ i: Int) -> Int {
            if parent[i] != i { parent[i] = find(parent[i]) }
            return parent[i]
        }
        func union(_ i: Int, _ j: Int) {
            let a = find(i), b = find(j)
            if a != b { parent[a] = b }
        }
        for i in 0..<rows.count {
            for j in (i+1)..<rows.count where rows[i].shareWith(rows[j]) {
                union(i, j)
            }
        }
        
        var groups: [Int: [ParsedAgenziaRow]] = [:]
        for i in 0..<rows.count {
            let root = find(i)
            groups[root, default: []].append(rows[i])
        }
        
        // Merge gruppi e crea AgenziaImportItem
        var result: [AgenziaImportItem] = []
        
        for (_, groupRows) in groups {
            var allCodici = Set<String>()
            var allTelefoni = Set<String>()
            var allEmails = Set<String>()
            var nome = ""
            var indirizzo: String = ""
            var citta: String = ""
            
            for r in groupRows {
                allCodici.formUnion(r.codici)
                allTelefoni.formUnion(r.telefoni)
                allEmails.formUnion(r.email)
                if !r.nome.isEmpty { nome = r.nome }
                if indirizzo.isEmpty, let i = r.indirizzo, !i.isEmpty { indirizzo = i }
                if citta.isEmpty, let c = r.citta, !c.isEmpty { citta = c }
            }
            
            let codiciList = allCodici.filter { !$0.isEmpty }.sorted()
            let primaryCode = codiciList.first ?? ""
            
            // Verifica se esiste già
            var existing: RubricaAgenzia?
            for c in codiciList where !c.isEmpty {
                if let ag = findAgenziaByCodice(c) {
                    existing = ag
                    break
                }
            }
            
            let isNew = existing == nil
            let isModified = existing != nil
            
            result.append(AgenziaImportItem(
                codice: primaryCode,
                nome: nome.isEmpty ? primaryCode : nome,
                indirizzo: indirizzo,
                citta: citta,
                telefoni: Array(allTelefoni).sorted(),
                email: Array(allEmails).sorted(),
                isNew: isNew,
                isModified: isModified
            ))
        }
        
        return result.sorted { $0.nome < $1.nome }
    }
    
    /// Parse vecchio formato per preview
    private func parseOldFormatForPreview(data: Data) async throws -> [AgenziaImportItem] {
        struct LegacyAgenzia: Codable {
            let id_agenzia: Int
            let ragione_sociale: String
            let indirizzo: String?
            let citta: String?
            let telefono1: String?
            let telefono2: String?
            let email1: String?
        }
        
        let legacyAgenzie = try JSONDecoder().decode([LegacyAgenzia].self, from: data)
        
        var result: [AgenziaImportItem] = []
        
        for legacy in legacyAgenzie {
            let parts = legacy.ragione_sociale.components(separatedBy: " - ")
            let codice = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
            let nome = parts.count > 1 ? parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces) : legacy.ragione_sociale
            
            var telefoni: [String] = []
            if let t1 = legacy.telefono1, !t1.isEmpty { telefoni.append(t1) }
            if let t2 = legacy.telefono2, !t2.isEmpty { telefoni.append(t2) }
            
            var emails: [String] = []
            if let e1 = legacy.email1, !e1.isEmpty { emails.append(e1.lowercased()) }
            
            let existing = findAgenziaByCodice(codice)
            
            result.append(AgenziaImportItem(
                codice: codice,
                nome: nome,
                indirizzo: legacy.indirizzo ?? "",
                citta: legacy.citta ?? "",
                telefoni: telefoni,
                email: emails,
                isNew: existing == nil,
                isModified: existing != nil
            ))
        }
        
        return result.sorted { $0.nome < $1.nome }
    }
    
    /// Importa le agenzie dalla preview (dopo che l'utente ha confermato)
    func importFromPreview(_ items: [AgenziaImportItem]) async -> Int {
        var count = 0
        
        for item in items {
            // Cerca esistente
            var existing = findAgenziaByCodice(item.codice)
            
            var agenzia: RubricaAgenzia
            if var existingAg = existing {
                // Aggiorna esistente
                if !item.nome.isEmpty { existingAg.nome = item.nome }
                existingAg.telefoni = Array(Set(existingAg.telefoni + item.telefoni)).sorted()
                existingAg.email = Array(Set(existingAg.email + item.email)).sorted()
                if (existingAg.indirizzo ?? "").isEmpty && !item.indirizzo.isEmpty {
                    existingAg.indirizzo = item.indirizzo
                }
                if (existingAg.citta ?? "").isEmpty && !item.citta.isEmpty {
                    existingAg.citta = item.citta
                }
                existingAg.lastModified = Date()
                agenzia = existingAg
                
                if let idx = agenzie.firstIndex(where: { $0.id == agenzia.id }) {
                    agenzie[idx] = agenzia
                }
            } else {
                // Crea nuova
                agenzia = RubricaAgenzia(
                    compagniaId: Compagnia.unknown.rubricaId,
                    codice: item.codice.isEmpty ? "IMPORT-\(UUID().uuidString.prefix(8))" : item.codice,
                    codiciAlternativi: [],
                    nome: item.nome.isEmpty ? "Agenzia importata" : item.nome,
                    indirizzo: item.indirizzo.isEmpty ? nil : item.indirizzo,
                    citta: item.citta.isEmpty ? nil : item.citta,
                    provincia: nil,
                    cap: nil,
                    telefoni: item.telefoni,
                    email: item.email,
                    fax: nil,
                    orariApertura: nil,
                    note: nil,
                    idAreaLegacy: nil,
                    descrAreaLegacy: nil
                )
                agenzie.append(agenzia)
                agenzie.sort { $0.nome < $1.nome }
            }
            
            count += 1
        }
        
        saveToLocalCache()
        
        // Sync in background
        let toSync = agenzie.filter { ag in items.contains { $0.codice == ag.codice } }
        Task.detached(priority: .utility) { [weak self] in
            await self?.syncImportedAgenzieToCloudInBackground(toSync)
        }
        
        return count
    }
    
    /// Riga parsata dal JSON (prima del raggruppamento e merge)
    private struct ParsedAgenziaRow {
        var codici: [String]
        var nome: String
        var compagnia: Compagnia
        var telefoni: [String]
        var email: [String]
        var indirizzo: String?
        var citta: String?
        var provincia: String?
        var cap: String?
        
        var nomeNorm: String { nome.trimmingCharacters(in: .whitespaces).lowercased() }
        
        func shareWith(_ other: ParsedAgenziaRow) -> Bool {
            if nomeNorm.isEmpty && other.nomeNorm.isEmpty {
                return Set(codici).intersection(Set(other.codici)).isEmpty == false
            }
            if nomeNorm == other.nomeNorm && compagnia == other.compagnia { return true }
            return Set(codici).intersection(Set(other.codici)).isEmpty == false
        }
    }
    
    /// Nuovo formato JSON: nome_agenzia, codici_agenzia (array) o codice_agenzia, telefono_1/2, email_1/2, indirizzo, compagnia.
    /// Consolida duplicati (stesso nome+compagnia o codici in comune) in una sola agenzia con tutti i codici.
    /// Aggiorna le esistenti (match per codice) senza creare duplicati.
    private func importNewFormat(data: Data) async throws -> Int {
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NSError(domain: "RubricaSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Formato JSON non valido"])
        }
        
        print("[RubricaSync] Trovate \(jsonArray.count) righe nel JSON (nuovo formato)")
        
        var rows: [ParsedAgenziaRow] = []
        
        for json in jsonArray {
            // nome_agenzia
            let nome = (json["nome_agenzia"] as? String) ?? (json["nome"] as? String) ?? ""
            
            // codici_agenzia (array) oppure codice_agenzia / codice (singolo)
            var codici: [String] = []
            if let arr = json["codici_agenzia"] as? [String] {
                codici = arr.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            if codici.isEmpty, let single = (json["codice_agenzia"] as? String) ?? (json["codice"] as? String), !single.isEmpty {
                codici = [single.trimmingCharacters(in: .whitespaces)]
            }
            
            guard !nome.isEmpty || !codici.isEmpty else { continue }
            
            // Telefoni: telefono_1, telefono_2 (e alias)
            var telefoni: [String] = []
            for key in ["telefono_1", "telefono_2", "telefono1", "telefono2"] {
                if let t = json[key] as? String, !t.isEmpty { telefoni.append(t) }
            }
            
            // Email: email_1, email_2 (e alias)
            var emails: [String] = []
            for key in ["email_1", "email_2", "email1", "email2"] {
                if let e = json[key] as? String, !e.isEmpty { emails.append(e) }
            }
            
            let indirizzo = (json["indirizzo"] as? String)?.trimmingCharacters(in: .whitespaces)
            var citta: String?, provincia: String?, cap: String?
            if let ind = indirizzo, !ind.isEmpty {
                let capPattern = /\b(\d{5})\s+([^,\(\)]+)/
                if let match = ind.firstMatch(of: capPattern) {
                    cap = String(match.1)
                    citta = String(match.2).trimmingCharacters(in: .whitespaces)
                }
                let provPattern = /\(([A-Z]{2})\)/
                if let match = ind.firstMatch(of: provPattern) {
                    provincia = String(match.1)
                }
            }
            
            let compagnia: Compagnia
            if let comp = (json["compagnia"] as? String)?.trimmingCharacters(in: .whitespaces).lowercased(), !comp.isEmpty {
                if comp.contains("unipol") { compagnia = .unipolItalia }
                else if comp.contains("cattolica") { compagnia = .cattolica }
                else if comp.contains("generali") { compagnia = .generaliItalia }
                else if comp.contains("zurich") { compagnia = .zurichItalia }
                else { compagnia = .unknown }
            } else {
                compagnia = .unknown
            }
            
            rows.append(ParsedAgenziaRow(
                codici: codici,
                nome: nome,
                compagnia: compagnia,
                telefoni: telefoni,
                email: emails,
                indirizzo: indirizzo?.isEmpty == true ? nil : indirizzo,
                citta: citta,
                provincia: provincia,
                cap: cap
            ))
        }
        
        // Union-Find: raggruppa righe che rappresentano la stessa agenzia (stesso nome+compagnia o codici in comune)
        var parent = Array(0..<rows.count)
        func find(_ i: Int) -> Int {
            if parent[i] != i { parent[i] = find(parent[i]) }
            return parent[i]
        }
        func union(_ i: Int, _ j: Int) {
            let a = find(i), b = find(j)
            if a != b { parent[a] = b }
        }
        for i in 0..<rows.count {
            for j in (i+1)..<rows.count where rows[i].shareWith(rows[j]) {
                union(i, j)
            }
        }
        
        var groups: [Int: [ParsedAgenziaRow]] = [:]
        for i in 0..<rows.count {
            let root = find(i)
            groups[root, default: []].append(rows[i])
        }
        
        // Per ogni gruppo: merge in una sola agenzia (union codici, contatti, primo indirizzo non vuoto)
        var mergedToSave: [(codice: String, codiciAlternativi: [String], nome: String, compagnia: Compagnia, telefoni: [String], emails: [String], indirizzo: String?, citta: String?, provincia: String?, cap: String?)] = []
        for (_, groupRows) in groups {
            var allCodici = Set<String>()
            var allTelefoni = Set<String>()
            var allEmails = Set<String>()
            var nome = ""
            var compagnia = Compagnia.unknown
            var indirizzo: String?, citta: String?, provincia: String?, cap: String?
            for r in groupRows {
                allCodici.formUnion(r.codici)
                allTelefoni.formUnion(r.telefoni)
                allEmails.formUnion(r.email)
                if !r.nome.isEmpty { nome = r.nome }
                if r.compagnia != .unknown { compagnia = r.compagnia }
                if indirizzo == nil, let i = r.indirizzo, !i.isEmpty { indirizzo = i }
                if citta == nil, let c = r.citta { citta = c }
                if provincia == nil, let p = r.provincia { provincia = p }
                if cap == nil, let c = r.cap { cap = c }
            }
            let codiciList = allCodici.filter { !$0.isEmpty }.sorted()
            let primary = codiciList.first ?? ""
            let alt = Array(codiciList.dropFirst())
            mergedToSave.append((
                primary,
                alt,
                nome.isEmpty ? primary : nome,
                compagnia,
                Array(allTelefoni).sorted(),
                Array(allEmails).sorted(),
                indirizzo,
                citta,
                provincia,
                cap
            ))
        }
        
        // 1. Applica tutto in locale (array + cache), senza CloudKit → import veloce
        var toSyncToCloud: [RubricaAgenzia] = []
        
        for m in mergedToSave {
            let allCodes = [m.codice] + m.codiciAlternativi
            var existing: RubricaAgenzia? = nil
            for c in allCodes where !c.isEmpty {
                if let ag = findAgenziaByCodice(c) {
                    existing = ag
                    break
                }
            }
            
            var ag: RubricaAgenzia
            if var existingAg = existing {
                existingAg.codice = m.codice.isEmpty ? existingAg.codice : m.codice
                existingAg.codiciAlternativi = Array(Set(existingAg.codiciAlternativi + m.codiciAlternativi + [m.codice].filter { !$0.isEmpty }).filter { $0.uppercased() != existingAg.codice.uppercased() }).sorted()
                if !m.nome.isEmpty { existingAg.nome = m.nome }
                existingAg.compagniaId = m.compagnia.rubricaId
                existingAg.telefoni = Array(Set(existingAg.telefoni + m.telefoni)).sorted()
                existingAg.email = Array(Set(existingAg.email + m.emails)).sorted()
                if (existingAg.indirizzo ?? "").isEmpty { existingAg.indirizzo = m.indirizzo }
                if (existingAg.citta ?? "").isEmpty { existingAg.citta = m.citta }
                if (existingAg.provincia ?? "").isEmpty { existingAg.provincia = m.provincia }
                if (existingAg.cap ?? "").isEmpty { existingAg.cap = m.cap }
                existingAg.lastModified = Date()
                ag = existingAg
                if let idx = agenzie.firstIndex(where: { $0.id == ag.id }) {
                    agenzie[idx] = ag
                }
            } else {
                ag = RubricaAgenzia(
                    compagniaId: m.compagnia.rubricaId,
                    codice: m.codice.isEmpty ? "IMPORT-\(UUID().uuidString.prefix(8))" : m.codice,
                    codiciAlternativi: m.codiciAlternativi,
                    nome: m.nome.isEmpty ? "Agenzia importata" : m.nome,
                    indirizzo: m.indirizzo,
                    citta: m.citta,
                    provincia: m.provincia,
                    cap: m.cap,
                    telefoni: m.telefoni,
                    email: m.emails,
                    fax: nil,
                    orariApertura: nil,
                    note: nil,
                    idAreaLegacy: nil,
                    descrAreaLegacy: nil
                )
                agenzie.append(ag)
                agenzie.sort { $0.nome < $1.nome }
            }
            toSyncToCloud.append(ag)
        }
        
        saveToLocalCache()
        
        let savedCount = toSyncToCloud.count
        let listToSync = toSyncToCloud
        print("[RubricaSync] Import nuovo formato: \(rows.count) righe -> \(savedCount) agenzie in locale (cache salvata).")
        await syncImportedAgenzieToCloudInBackground(listToSync)
        
        return savedCount
    }
    
    /// Compatibilita' vecchio nome: aggiorna solo cache locale.
    private func syncImportedAgenzieToCloudInBackground(_ list: [RubricaAgenzia]) async {
        let total = list.count
        var ok = 0
        for a in list {
            await CPUThrottler.shared.throttleIfNeeded()
            do {
                try await saveAgenziaToCloudOnly(a)
                ok += 1
            } catch {
                print("[RubricaSync] ⚠️ Aggiornamento cache fallito per \(a.nomeCompleto): \(error)")
            }
        }
        print("[RubricaSync] Cache aggiornata: \(ok)/\(total) agenzie")
    }
    
    /// Vecchio formato JSON legacy: id_agenzia, ragione_sociale, etc.
    private func importOldFormat(data: Data) async throws -> Int {
        struct LegacyAgenzia: Codable {
            let id_agenzia: Int
            let id_divisione_old: Int?
            let ragione_sociale: String
            let indirizzo: String?
            let citta: String?
            let provincia: String?
            let cap: String?
            let telefono1: String?
            let telefono2: String?
            let note: String?
            let email1: String?
            let id_area: Int?
            let fax1: String?
            let password_jftech: String?
            let descr_area: String?
        }
        
        let legacyAgenzie = try JSONDecoder().decode([LegacyAgenzia].self, from: data)
        
        var newAgenzie: [RubricaAgenzia] = []
        
        for legacy in legacyAgenzie {
            // Estrai codice e nome dalla ragione_sociale (es. "5239 - Milano Argentina")
            let parts = legacy.ragione_sociale.components(separatedBy: " - ")
            let codice = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
            let nome = parts.count > 1 ? parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces) : legacy.ragione_sociale
            
            // Determina compagnia da descr_area usando gli enum di CompagniaService
            let compagnia: Compagnia
            let area = legacy.descr_area?.lowercased() ?? ""
            
            if area.contains("unipol") {
                compagnia = .unipolItalia
            } else if area.contains("cattolica") {
                compagnia = .cattolica
            } else if area.contains("generali") || area.contains("fabbricati") || area.contains("servizio") {
                compagnia = .generaliItalia
            } else if area.contains("zurich") {
                compagnia = .zurichItalia
            } else {
                compagnia = .unknown
            }
            
            // Costruisci array telefoni
            var telefoni: [String] = []
            if let t1 = legacy.telefono1, !t1.isEmpty { telefoni.append(t1) }
            if let t2 = legacy.telefono2, !t2.isEmpty { telefoni.append(t2) }
            
            // Costruisci array email (split per ; se multiple)
            var emails: [String] = []
            if let e = legacy.email1, !e.isEmpty {
                emails = e.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            
            let agenzia = RubricaAgenzia(
                id: "legacy-\(legacy.id_agenzia)",
                compagniaId: compagnia.rubricaId,
                codice: codice,
                nome: nome,
                indirizzo: legacy.indirizzo,
                citta: legacy.citta,
                provincia: legacy.provincia,
                cap: legacy.cap,
                telefoni: telefoni,
                email: emails,
                fax: legacy.fax1,
                orariApertura: nil,
                note: legacy.note,
                idAreaLegacy: legacy.id_area,
                descrAreaLegacy: legacy.descr_area
            )
            
            newAgenzie.append(agenzia)
        }
        
        print("[RubricaSync] Importazione formato legacy: \(newAgenzie.count) agenzie")
        
        for agenzia in newAgenzie {
            try await saveAgenzia(agenzia)
        }
        
        return newAgenzie.count
    }
}

private struct RubricaAllDTO: Codable {
    let agenzie: [RubricaAgenziaDTO]
    let agenti: [RubricaAgenteDTO]
    let liquidatori: [RubricaLiquidatoreDTO]
    let synced_at: Date
}

private struct RubricaAgenziaDTO: Codable {
    let id: String
    let tenant_id: String?
    let nome: String
    let codice: String?
    let indirizzo: String?
    let citta: String?
    let provincia: String?
    let telefono: String?
    let email: String?
    let compagnia: String?
    let gruppo: String?
    let note: String?
    let is_active: Bool
    let created_at: Date?
    let updated_at: Date?

    func toRubricaAgenzia() -> RubricaAgenzia {
        let compagnia = Compagnia.detect(gruppo: gruppo, compagnia: compagnia)
        return RubricaAgenzia(
            id: id,
            compagniaId: compagnia.rubricaId,
            codice: codice ?? "",
            nome: nome,
            indirizzo: indirizzo,
            citta: citta,
            provincia: provincia,
            telefoni: telefono.map { [$0] } ?? [],
            email: email.map { [$0] } ?? [],
            note: note
        )
    }
}

private struct RubricaAgenziaUpsertDTO: Codable {
    let id: String
    let nome: String
    let codice: String?
    let indirizzo: String?
    let citta: String?
    let provincia: String?
    let telefono: String?
    let email: String?
    let compagnia: String?
    let gruppo: String?
    let note: String?
    let is_active: Bool

    init(agenzia: RubricaAgenzia) {
        let compagnia = Compagnia(rawValue: agenzia.compagniaId)
        self.id = agenzia.id
        self.nome = agenzia.nome
        self.codice = agenzia.codice.isEmpty ? nil : agenzia.codice
        self.indirizzo = agenzia.indirizzo
        self.citta = agenzia.citta
        self.provincia = agenzia.provincia
        self.telefono = agenzia.telefoni.first
        self.email = agenzia.email.first
        self.compagnia = compagnia?.rawValue ?? agenzia.compagniaId
        self.gruppo = compagnia?.gruppo.rawValue
        self.note = agenzia.note
        self.is_active = true
    }
}

private struct RubricaAgenteDTO: Codable {
    let id: String
    let tenant_id: String?
    let agenzia_id: String
    let nome: String
    let cognome: String
    let ruolo: String?
    let telefono: String?
    let email: String?
    let note: String?
    let is_active: Bool
    let created_at: Date?
    let updated_at: Date?

    func toRubricaAgente() -> RubricaAgente {
        RubricaAgente(
            id: id,
            agenziaId: agenzia_id,
            nome: nome,
            cognome: cognome,
            ruolo: ruolo,
            telefoni: telefono.map { [$0] } ?? [],
            email: email.map { [$0] } ?? [],
            note: note
        )
    }
}

private struct RubricaAgenteUpsertDTO: Codable {
    let id: String
    let agenzia_id: String
    let nome: String
    let cognome: String
    let ruolo: String?
    let telefono: String?
    let email: String?
    let note: String?
    let is_active: Bool

    init(agente: RubricaAgente) {
        self.id = agente.id
        self.agenzia_id = agente.agenziaId
        self.nome = agente.nome
        self.cognome = agente.cognome
        self.ruolo = agente.ruolo
        self.telefono = agente.telefoni.first
        self.email = agente.email.first
        self.note = agente.note
        self.is_active = true
    }
}

private struct RubricaLiquidatoreDTO: Codable {
    let id: String
    let tenant_id: String?
    let nome: String?
    let cognome: String
    let email: String?
    let telefono: String?
    let compagnia: String?
    let zona: String?
    let is_active: Bool
    let note: String?
    let created_at: Date?
    let updated_at: Date?

    func toRubricaLiquidatore() -> RubricaLiquidatore {
        let compagnia = Compagnia.from(nomeCompagnia: compagnia)
        return RubricaLiquidatore(
            id: id,
            gruppoId: compagnia.gruppo.rubricaId,
            compagniaId: compagnia.rubricaId,
            nome: nome ?? "",
            cognome: cognome,
            telefoni: telefono.map { [$0] } ?? [],
            email: email.map { [$0] } ?? [],
            area: zona,
            note: note
        )
    }
}

private struct RubricaLiquidatoreUpsertDTO: Codable {
    let id: String
    let nome: String?
    let cognome: String
    let email: String?
    let telefono: String?
    let compagnia: String?
    let zona: String?
    let is_active: Bool
    let note: String?

    init(liquidatore: RubricaLiquidatore) {
        self.id = liquidatore.id
        self.nome = liquidatore.nome.isEmpty ? nil : liquidatore.nome
        self.cognome = liquidatore.cognome
        self.email = liquidatore.email.first
        self.telefono = liquidatore.telefoni.first
        self.compagnia = liquidatore.compagniaId.flatMap { Compagnia(rawValue: $0)?.rawValue } ?? liquidatore.compagniaId
        self.zona = liquidatore.area
        self.is_active = true
        self.note = liquidatore.note
    }
}
