//
//  CloudKitRubricaSyncService.swift
//  PerX per iPad
//
//  Servizio per sincronizzazione pubblica della rubrica agenzie via CloudKit
//  NOTA: Gruppi e Compagnie sono enum fissi da CompagniaService, non editabili
//

import Foundation
import CloudKit
import Combine

@MainActor
final class CloudKitRubricaSyncService: ObservableObject {
    static let shared = CloudKitRubricaSyncService()
    
    // MARK: - Published State
    // NOTA: Gruppi e Compagnie sono enum fissi, non array dinamici
    
    @Published private(set) var agenzie: [RubricaAgenzia] = []
    @Published private(set) var agenti: [RubricaAgente] = []
    @Published private(set) var liquidatori: [RubricaLiquidatore] = []
    
    @Published private(set) var isLoading = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var error: String?
    
    // MARK: - Gruppi e Compagnie (computed, basati su enum fissi)
    
    /// Lista gruppi assicurativi (enum fissi, non editabili)
    var gruppi: [GruppoAssicurativo] {
        GruppoAssicurativo.allCases.filter { $0 != .unknown }
    }
    
    /// Lista compagnie (enum fissi, non editabili)
    var compagnie: [Compagnia] {
        Compagnia.allCases.filter { $0 != .unknown }
    }
    
    /// Compagnie appartenenti a un gruppo specifico
    func compagniePer(gruppo: GruppoAssicurativo) -> [Compagnia] {
        gruppo.compagnie
    }
    
    // MARK: - Private
    
    private let container: CKContainer
    private let publicDB: CKDatabase
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        self.container = CKContainer(identifier: "iCloud.it.pernozzoli.PerX")
        self.publicDB = container.publicCloudDatabase
        
        // Carica cache locale all'avvio
        loadFromLocalCache()
    }
    
    // MARK: - Public API
    
    /// Sincronizza tutti i dati dal CloudKit pubblico
    func syncAll() async {
        guard !isSyncing else { return }
        
        isSyncing = true
        error = nil
        
        defer { isSyncing = false }
        
        do {
            // Fetch parallelo (gruppi e compagnie sono enum, non serve fetch)
            async let agenzieTask = fetchAgenzie()
            async let agentiTask = fetchAgenti()
            async let liquidatoriTask = fetchLiquidatori()
            
            let (a, ag, l) = try await (agenzieTask, agentiTask, liquidatoriTask)
            
            agenzie = a.sorted { $0.nome < $1.nome }
            agenti = ag.sorted { $0.cognome < $1.cognome }
            liquidatori = l.sorted { $0.cognome < $1.cognome }
            
            lastSyncDate = Date()
            
            // Salva cache locale
            saveToLocalCache()
            
            print("[RubricaSync iPad] Sincronizzate: \(agenzie.count) agenzie")
            
        } catch {
            self.error = error.localizedDescription
            print("[RubricaSync iPad] Errore sync: \(error)")
        }
    }
    
    /// Carica i dati iniziali (da cache o CloudKit)
    func loadInitial() async {
        guard agenzie.isEmpty else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        // Prima carica da cache
        loadFromLocalCache()
        
        // Poi sincronizza in background
        await syncAll()
    }
    
    // MARK: - CRUD Agenzie
    
    func saveAgenzia(_ agenzia: RubricaAgenzia) async throws {
        var a = agenzia
        a.lastModified = Date()
        
        let record = a.toCKRecord()
        _ = try await publicDB.saveRecordAsync(record)
        
        if let index = agenzie.firstIndex(where: { $0.id == a.id }) {
            agenzie[index] = a
        } else {
            agenzie.append(a)
            agenzie.sort { $0.nome < $1.nome }
        }
        
        saveToLocalCache()
    }
    
    func deleteAgenzia(_ id: String) async throws {
        let recordID = CKRecord.ID(recordName: id)
        try await publicDB.deleteRecordAsync(recordID)
        
        // Trova e rimuovi filiali associate
        let filialiIds = agenzie.filter { $0.agenziaParentId == id }.map { $0.id }
        for filialeId in filialiIds {
            let filialeRecordID = CKRecord.ID(recordName: filialeId)
            try? await publicDB.deleteRecordAsync(filialeRecordID)
        }
        
        agenzie.removeAll { $0.id == id || $0.agenziaParentId == id }
        // Rimuovi agenti associati all'agenzia e alle filiali
        agenti.removeAll { $0.agenziaId == id || filialiIds.contains($0.agenziaId) }
        
        saveToLocalCache()
    }
    
    // MARK: - CRUD Agenti
    
    func saveAgente(_ agente: RubricaAgente) async throws {
        var a = agente
        a.lastModified = Date()
        
        let record = a.toCKRecord()
        _ = try await publicDB.saveRecordAsync(record)
        
        if let index = agenti.firstIndex(where: { $0.id == a.id }) {
            agenti[index] = a
        } else {
            agenti.append(a)
            agenti.sort { $0.cognome < $1.cognome }
        }
        
        saveToLocalCache()
    }
    
    func deleteAgente(_ id: String) async throws {
        let recordID = CKRecord.ID(recordName: id)
        try await publicDB.deleteRecordAsync(recordID)
        
        agenti.removeAll { $0.id == id }
        saveToLocalCache()
    }
    
    // MARK: - CRUD Liquidatori
    
    func saveLiquidatore(_ liquidatore: RubricaLiquidatore) async throws {
        var l = liquidatore
        l.lastModified = Date()
        
        let record = l.toCKRecord()
        _ = try await publicDB.saveRecordAsync(record)
        
        if let index = liquidatori.firstIndex(where: { $0.id == l.id }) {
            liquidatori[index] = l
        } else {
            liquidatori.append(l)
            liquidatori.sort { $0.cognome < $1.cognome }
        }
        
        saveToLocalCache()
    }
    
    func deleteLiquidatore(_ id: String) async throws {
        let recordID = CKRecord.ID(recordName: id)
        try await publicDB.deleteRecordAsync(recordID)
        
        liquidatori.removeAll { $0.id == id }
        saveToLocalCache()
    }
    
    // MARK: - Query Helpers
    
    /// Trova agenzia per codice
    func findAgenziaByCodice(_ codice: String) -> RubricaAgenzia? {
        agenzie.first { $0.codice.uppercased() == codice.uppercased() }
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
    
    /// Cerca agenzie per testo (nome, codice, città, telefono, email)
    func searchAgenzie(_ query: String, limit: Int = 50) -> [RubricaAgenzia] {
        guard query.count >= 2 else { return [] }
        
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        
        return agenzie.filter { agenzia in
            let searchFields = [
                agenzia.nome,
                agenzia.codice,
                agenzia.citta ?? "",
                agenzia.provincia ?? "",
                agenzia.indirizzo ?? "",
                agenzia.note ?? "",
                agenzia.descrAreaLegacy ?? "",
                agenzia.suffissoNome ?? ""
            ] + agenzia.telefoni + agenzia.email
            
            return searchFields.contains { $0.lowercased().contains(q) }
        }.prefix(limit).map { $0 }
    }
    
    // MARK: - Fetch from CloudKit
    
    private func fetchAgenzie() async throws -> [RubricaAgenzia] {
        let query = CKQuery(recordType: RubricaAgenzia.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "nome", ascending: true)]
        
        // Fetch in batch per gestire grandi quantità
        var allRecords: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        
        repeat {
            let (records, nextCursor) = try await fetchBatch(query: query, cursor: cursor)
            allRecords.append(contentsOf: records)
            cursor = nextCursor
        } while cursor != nil
        
        return allRecords.map { RubricaAgenzia(from: $0) }
    }
    
    private func fetchAgenti() async throws -> [RubricaAgente] {
        let query = CKQuery(recordType: RubricaAgente.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "cognome", ascending: true)]
        
        let records = try await publicDB.performQueryAsync(query)
        return records.map { RubricaAgente(from: $0) }
    }
    
    private func fetchLiquidatori() async throws -> [RubricaLiquidatore] {
        let query = CKQuery(recordType: RubricaLiquidatore.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "cognome", ascending: true)]
        
        let records = try await publicDB.performQueryAsync(query)
        return records.map { RubricaLiquidatore(from: $0) }
    }
    
    private func fetchBatch(query: CKQuery, cursor: CKQueryOperation.Cursor?) async throws -> ([CKRecord], CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            let operation: CKQueryOperation
            if let cursor = cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                operation = CKQueryOperation(query: query)
            }
            
            operation.resultsLimit = 400
            
            var fetchedRecords: [CKRecord] = []
            
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    fetchedRecords.append(record)
                }
            }
            
            operation.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    continuation.resume(returning: (fetchedRecords, cursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            
            publicDB.add(operation)
        }
    }
    
    // MARK: - Local Cache
    
    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RubricaCache_v2.json")
    }
    
    private struct CacheData: Codable {
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
            print("[RubricaSync iPad] Errore salvataggio cache: \(error)")
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
            
            print("[RubricaSync iPad] Cache caricata: \(agenzie.count) agenzie")
        } catch {
            print("[RubricaSync iPad] Errore caricamento cache: \(error)")
        }
    }
}

// MARK: - CKDatabase Extensions

extension CKDatabase {
    func performQueryAsync(_ query: CKQuery) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKQueryOperation(query: query)
            var records: [CKRecord] = []
            
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    records.append(record)
                }
            }
            
            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: records)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            
            self.add(operation)
        }
    }
    
    func saveRecordAsync(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            self.save(record) { savedRecord, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let savedRecord = savedRecord {
                    continuation.resume(returning: savedRecord)
                } else {
                    continuation.resume(throwing: NSError(domain: "CloudKit", code: -1))
                }
            }
        }
    }
    
    func deleteRecordAsync(_ recordID: CKRecord.ID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.delete(withRecordID: recordID) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
