import Foundation
import Combine

/// Servizio rubrica agenzie per iPad.
/// CloudKit rimosso: i dati sono mantenuti in cache locale JSON.
/// Gruppi e Compagnie restano enum fissi.
@MainActor
final class CloudKitRubricaSyncService: ObservableObject {
    static let shared = CloudKitRubricaSyncService()

    @Published private(set) var agenzie: [RubricaAgenzia] = []
    @Published private(set) var agenti: [RubricaAgente] = []
    @Published private(set) var liquidatori: [RubricaLiquidatore] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var error: String?

    var gruppi: [GruppoAssicurativo] { GruppoAssicurativo.allCases.filter { $0 != .unknown } }
    var compagnie: [Compagnia] { Compagnia.allCases.filter { $0 != .unknown } }

    func compagniePer(gruppo: GruppoAssicurativo) -> [Compagnia] { gruppo.compagnie }

    private init() { loadFromLocalCache() }

    // MARK: - Public API

    func loadInitial() async {
        guard agenzie.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        loadFromLocalCache()
    }

    // MARK: - CRUD Agenzie

    func saveAgenzia(_ agenzia: RubricaAgenzia) async throws {
        var a = agenzia; a.lastModified = Date()
        if let index = agenzie.firstIndex(where: { $0.id == a.id }) {
            agenzie[index] = a
        } else {
            agenzie.append(a)
            agenzie.sort { $0.nome < $1.nome }
        }
        saveToLocalCache()
    }

    func deleteAgenzia(_ id: String) async throws {
        let filialiIds = agenzie.filter { $0.agenziaParentId == id }.map { $0.id }
        agenzie.removeAll { $0.id == id || $0.agenziaParentId == id }
        agenti.removeAll { $0.agenziaId == id || filialiIds.contains($0.agenziaId) }
        saveToLocalCache()
    }

    // MARK: - CRUD Agenti

    func saveAgente(_ agente: RubricaAgente) async throws {
        var a = agente; a.lastModified = Date()
        if let index = agenti.firstIndex(where: { $0.id == a.id }) {
            agenti[index] = a
        } else {
            agenti.append(a)
            agenti.sort { $0.cognome < $1.cognome }
        }
        saveToLocalCache()
    }

    func deleteAgente(_ id: String) async throws {
        agenti.removeAll { $0.id == id }
        saveToLocalCache()
    }

    // MARK: - CRUD Liquidatori

    func saveLiquidatore(_ liquidatore: RubricaLiquidatore) async throws {
        var l = liquidatore; l.lastModified = Date()
        if let index = liquidatori.firstIndex(where: { $0.id == l.id }) {
            liquidatori[index] = l
        } else {
            liquidatori.append(l)
            liquidatori.sort { $0.cognome < $1.cognome }
        }
        saveToLocalCache()
    }

    func deleteLiquidatore(_ id: String) async throws {
        liquidatori.removeAll { $0.id == id }
        saveToLocalCache()
    }

    // MARK: - Query

    func findAgenziaByCodice(_ codice: String) -> RubricaAgenzia? {
        agenzie.first { $0.codice.uppercased() == codice.uppercased() }
    }

    func agenziePer(compagniaId: String) -> [RubricaAgenzia] {
        agenzie.filter { $0.compagniaId == compagniaId && !$0.isFiliale }
    }

    func tutteAgenziePer(compagniaId: String) -> [RubricaAgenzia] {
        agenzie.filter { $0.compagniaId == compagniaId }
    }

    func filialiPer(agenziaId: String) -> [RubricaAgenzia] {
        agenzie.filter { $0.agenziaParentId == agenziaId }
    }

    func hasFiliali(_ agenziaId: String) -> Bool {
        agenzie.contains { $0.agenziaParentId == agenziaId }
    }

    func countFiliali(_ agenziaId: String) -> Int {
        agenzie.filter { $0.agenziaParentId == agenziaId }.count
    }

    func searchAgenzie(_ query: String, limit: Int = 50) -> [RubricaAgenzia] {
        guard query.count >= 2 else { return [] }
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return agenzie.filter { a in
            let fields = [a.nome, a.codice, a.citta ?? "", a.provincia ?? "",
                          a.indirizzo ?? "", a.note ?? "", a.descrAreaLegacy ?? "",
                          a.suffissoNome ?? ""] + a.telefoni + a.email
            return fields.contains { $0.lowercased().contains(q) }
        }.prefix(limit).map { $0 }
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
        let data = CacheData(agenzie: agenzie, agenti: agenti, liquidatori: liquidatori, lastSync: lastSyncDate)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: cacheURL)
        }
    }

    private func loadFromLocalCache() {
        guard FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(CacheData.self, from: data) else { return }
        agenzie = cache.agenzie
        agenti = cache.agenti
        liquidatori = cache.liquidatori
        lastSyncDate = cache.lastSync
        print("[Rubrica iPad] Cache caricata: \(agenzie.count) agenzie")
    }
}
