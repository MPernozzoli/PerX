import Foundation
import Combine

// ============================================================================
// MARK: - ActorRepository
//
// Wrapper @MainActor sopra HubAPIAdapterClient per le API /actors.
// Espone @Published per pilotare direttamente le View SwiftUI, gestisce
// debouncing della ricerca e una cache di breve durata per ridurre i round
// trip quando lo stesso attore viene rivisitato.
// ============================================================================

@MainActor
final class ActorRepository: ObservableObject {

    static let shared = ActorRepository()

    private let client: HubAPIAdapterClient
    private var detailCache: [String: (CloudActorDetail, Date)] = [:]
    private let cacheTTL: TimeInterval = 60  // 1 minuto: utile per riapertura schede

    private var searchTask: Task<Void, Never>?

    @Published private(set) var lastSearchResults: [CloudActorSummary] = []
    @Published private(set) var isSearching = false
    @Published var lastError: String?

    private init(client: HubAPIAdapterClient = .shared) {
        self.client = client
    }

    // MARK: - Search

    /// Esegue una ricerca con debounce (350ms). Aggiorna `lastSearchResults`
    /// e `isSearching`. Cancella query precedenti ancora in volo.
    /// `claimContextId` viene loggato dal backend per attestare il motivo
    /// del trattamento (sinistro in lavorazione).
    func search(
        query: String,
        actorType: CloudActorType? = nil,
        claimContextId: String? = nil,
        limit: Int = 30
    ) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            lastSearchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch { return }
            if Task.isCancelled { return }
            do {
                let response = try await self.client.listActors(
                    query: trimmed,
                    actorType: actorType,
                    claimContextId: claimContextId,
                    limit: limit
                )
                if Task.isCancelled { return }
                self.lastSearchResults = response.items
                self.isSearching = false
            } catch {
                if Task.isCancelled { return }
                self.lastError = (error as NSError).localizedDescription
                self.isSearching = false
            }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        lastSearchResults = []
        isSearching = false
    }

    // MARK: - Detail / CRUD

    func detail(id: String, forceRefresh: Bool = false) async throws -> CloudActorDetail {
        if !forceRefresh, let (cached, ts) = detailCache[id], Date().timeIntervalSince(ts) < cacheTTL {
            return cached
        }
        let fresh = try await client.getActor(id: id)
        detailCache[id] = (fresh, Date())
        return fresh
    }

    func invalidate(id: String) {
        detailCache.removeValue(forKey: id)
    }

    func create(_ payload: CloudActorCreate, claimContextId: String? = nil) async throws -> CloudActorResponse {
        let actor = try await client.createActor(payload, claimContextId: claimContextId)
        // L'API è upsert per CF/PIVA: invalida la cache se per caso esisteva.
        detailCache.removeValue(forKey: actor.id)
        return actor
    }

    func update(id: String, payload: CloudActorUpdate) async throws -> CloudActorResponse {
        let actor = try await client.updateActor(id: id, payload: payload)
        detailCache.removeValue(forKey: id)
        return actor
    }

    // MARK: - Addresses / IBAN / Relations

    func addAddress(actorId: String, payload: CloudActorAddressCreate) async throws -> CloudActorAddress {
        defer { invalidate(id: actorId) }
        return try await client.addActorAddress(actorId: actorId, payload: payload)
    }

    func listAddresses(actorId: String) async throws -> [CloudActorAddress] {
        try await client.listActorAddresses(actorId: actorId)
    }

    func addIban(actorId: String, payload: CloudActorIbanCreate) async throws -> CloudActorIban {
        defer { invalidate(id: actorId) }
        return try await client.addActorIban(actorId: actorId, payload: payload)
    }

    func listIbans(actorId: String) async throws -> [CloudActorIban] {
        try await client.listActorIbans(actorId: actorId)
    }

    func addRelation(actorId: String, payload: CloudActorRelationCreate) async throws -> CloudActorRelation {
        defer { invalidate(id: actorId) }
        return try await client.addActorRelation(actorId: actorId, payload: payload)
    }

    // MARK: - Cross-claim views

    func listClaims(actorId: String) async throws -> [CloudClaimResponse] {
        try await client.listActorClaims(actorId: actorId)
    }

    func listAgencies(actorId: String) async throws -> [CloudActorAgencyLink] {
        try await client.listActorAgencies(actorId: actorId)
    }

    func listCompanies(actorId: String) async throws -> [CloudActorCompanyLink] {
        try await client.listActorCompanies(actorId: actorId)
    }
}
