import Foundation
import Combine

// ============================================================================
// MARK: - ClaimAdapter
// Adapter per sinistri con routing locale/Hub
// ============================================================================

@MainActor
final class ClaimAdapter: ObservableObject {
    static let shared = ClaimAdapter()
    
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    
    private let hubMode = HubModeService.shared
    private let hubClient = HubAPIAdapterClient.shared
    
    private init() {}
    
    // MARK: - Fetch Claims
    
    /// Recupera sinistri per utente (passare currentUsername da CurrentUserService)
    func getSinistri(userId: String, userEmail: String? = nil) async throws -> [SinistroListItem] {
        if hubClient.isCloudConfigured {
            return try await fetchFromCloud()
        } else if hubMode.shouldUseHub(for: .claim) {
            return try await fetchFromHub(userId: userId, userEmail: userEmail)
        } else {
            return try await fetchFromLocal(userId: userId, userEmail: userEmail)
        }
    }
    
    /// Recupera dettaglio sinistro
    func getSinistro(riferimento: String) async throws -> SinistroDetail? {
        if hubClient.isCloudConfigured {
            return try await fetchDetailFromCloud(riferimento: riferimento)
        } else if hubMode.shouldUseHub(for: .claim) {
            return try await fetchDetailFromHub(riferimento: riferimento)
        } else {
            return try await fetchDetailFromLocal(riferimento: riferimento)
        }
    }
    
    // MARK: - Actions
    
    /// Cambia stato sinistro
    func changeState(
        riferimento: String,
        newState: StatoSinistro,
        reason: String?,
        changedBy: String
    ) async throws {
        if hubClient.isCloudConfigured {
            try await changeStateOnCloud(
                riferimento: riferimento,
                newState: newState,
                reason: reason
            )
        } else if hubMode.shouldUseHub(for: .claim) {
            try await changeStateOnHub(
                riferimento: riferimento,
                newState: newState,
                reason: reason,
                changedBy: changedBy
            )
        } else {
            try await changeStateLocally(
                riferimento: riferimento,
                newState: newState,
                reason: reason,
                changedBy: changedBy
            )
        }
    }
    
    // MARK: - Hub Implementation

    private func fetchFromCloud() async throws -> [SinistroListItem] {
        let response: CloudClaimListResponse = try await hubClient.cloudGet("/api/v1/claims")
        return response.items.map { SinistroListItem(from: $0) }
    }

    private func fetchDetailFromCloud(riferimento: String) async throws -> SinistroDetail? {
        let response: CloudClaimResponse = try await hubClient.cloudGet("/api/v1/claims/\(riferimento)")
        return SinistroDetail(from: response)
    }

    /// Accoda il cambio di stato sul server tramite `ClaimStateSyncQueue`
    /// (offline-first: il flush avviene subito se online, altrimenti al ritorno
    /// della connessione). Lo `stato_corrente` corrente è recuperato dalla copia
    /// CoreData se disponibile, così il backend può validare la transizione e
    /// rifiutare in modo idempotente eventuali replay.
    private func changeStateOnCloud(
        riferimento: String,
        newState: StatoSinistro,
        reason: String?
    ) async throws {
        // Slug canonico per il backend (post-migration 020).
        // Se lo stato non ha equivalente cloud (es. stati di sistema SI*), non
        // accodare niente: la transizione resta puramente locale.
        guard let toSlug = newState.cloudSlug else {
            print("[ClaimAdapter] ⏭️ Stato \(newState.rawValue) senza equivalente cloud: skip")
            return
        }
        let fromSlug = await fetchCurrentStateLocally(riferimento: riferimento)
        await ClaimStateSyncQueue.shared.enqueue(
            riferimento: riferimento,
            fromState: fromSlug,
            toState: toSlug,
            sopralluogo_substato: newState.impliedSubstato,
            reason: reason
        )
    }

    /// Stato corrente del sinistro in CoreData, tradotto in slug canonico.
    /// Restituisce `nil` se il sinistro non è in cache o lo stato non ha
    /// equivalente cloud.
    private func fetchCurrentStateLocally(riferimento: String) async -> String? {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        request.fetchLimit = 1
        let raw: String? = await context.perform {
            (try? context.fetch(request).first)?.stato
        }
        guard let raw = raw else { return nil }
        return BackendStatoMapping.cloudSlug(forCoreDataRaw: raw)
    }

    private func fetchFromHub(userId: String, userEmail: String? = nil) async throws -> [SinistroListItem] {
        var path = "/sinistri?user=\(userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId)"
        if let email = userEmail, !email.isEmpty {
            path += "&email=\(email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email)"
        }
        let response: [SinistroDTO] = try await hubClient.get(path)
        return response.map { SinistroListItem(from: $0) }
    }
    
    private func fetchDetailFromHub(riferimento: String) async throws -> SinistroDetail? {
        let response: SinistroDTO = try await hubClient.get("/sinistri/\(riferimento)")
        return SinistroDetail(from: response)
    }
    
    private func changeStateOnHub(
        riferimento: String,
        newState: StatoSinistro,
        reason: String?,
        changedBy: String
    ) async throws {
        let request = StateChangeRequest(
            newState: newState.rawValue,
            reason: reason,
            changedBy: changedBy
        )
        
        let _: StateChangeResponse = try await hubClient.post("/sinistri/\(riferimento)/stato", body: request)
        print("[ClaimAdapter] Stato cambiato su Hub: \(riferimento) → \(newState.descrizione)")
    }
    
    // MARK: - Local Implementation
    
    private func fetchFromLocal(userId: String, userEmail: String? = nil) async throws -> [SinistroListItem] {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        let pred: NSPredicate
        if let email = userEmail, !email.isEmpty, email.lowercased() != userId.lowercased() {
            pred = NSPredicate(format: "assignedToUserEmail == %@ OR assignedToUserEmail == %@", userId.lowercased(), email.lowercased())
        } else {
            pred = NSPredicate(format: "assignedToUserEmail == %@", userId.lowercased())
        }
        request.predicate = pred
        request.sortDescriptors = [NSSortDescriptor(key: "dataAssegnazione", ascending: false)]
        
        return try await context.perform {
            let sinistri = try context.fetch(request)
            return sinistri.map { SinistroListItem(from: $0) }
        }
    }
    
    private func fetchDetailFromLocal(riferimento: String) async throws -> SinistroDetail? {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        request.fetchLimit = 1
        
        return try await context.perform {
            guard let sinistro = try context.fetch(request).first else {
                return nil
            }
            return SinistroDetail(from: sinistro)
        }
    }
    
    private func changeStateLocally(
        riferimento: String,
        newState: StatoSinistro,
        reason: String?,
        changedBy: String
    ) async throws {
        // Trova il sinistro e cambia stato usando StatoManager
        let context = PersistenceController.shared.container.viewContext
        
        let fetchRequest = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        fetchRequest.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        fetchRequest.fetchLimit = 1
        
        guard let sinistro = try context.fetch(fetchRequest).first else {
            throw AdapterError.notFound("Sinistro non trovato: \(riferimento)")
        }
        
        try await StatoManager.shared.changeState(
            for: sinistro,
            to: newState,
            context: context,
            userEmail: changedBy
        )
        
        print("[ClaimAdapter] Stato cambiato localmente: \(riferimento) → \(newState.descrizione)")
    }
}

// MARK: - View Models

struct SinistroListItem: Identifiable {
    let id: String
    let riferimento: String
    let garanzia: String?
    let stato: StatoSinistro
    let nomeAssicurato: String?
    let nomeCompagnia: String?
    let dataAssegnazione: Date?
    let assignedToUserEmail: String?
    
    init(from dto: SinistroDTO) {
        self.id = dto.id
        self.riferimento = dto.riferimento
        self.garanzia = dto.garanzia
        self.stato = StatoSinistro(rawValue: dto.stato) ?? .istruzione
        self.nomeAssicurato = dto.nomeAssicurato
        self.nomeCompagnia = dto.nomeCompagnia
        self.dataAssegnazione = dto.dataAssegnazione
        self.assignedToUserEmail = dto.assignedToUserEmail
    }
    
    init(from sinistro: Sinistro) {
        self.id = sinistro.riferimento ?? UUID().uuidString
        self.riferimento = sinistro.riferimento ?? ""
        self.garanzia = sinistro.garanzia ?? sinistro.fulminazione
        self.stato = StatoSinistro(rawValue: sinistro.stato ?? "") ?? .istruzione
        self.nomeAssicurato = sinistro.nomeAssicurato
        self.nomeCompagnia = sinistro.nomeCompagnia
        self.dataAssegnazione = sinistro.dataAssegnazione
        self.assignedToUserEmail = sinistro.assignedToUserEmail
    }

    init(from dto: CloudClaimResponse) {
        self.id = dto.id
        self.riferimento = dto.external_ref ?? dto.id
        self.garanzia = dto.garanzia
        self.stato = BackendStatoMapping.statoSinistro(forCloudSlug: dto.stato_corrente) ?? .istruzione
        self.nomeAssicurato = dto.nome_assicurato
        self.nomeCompagnia = dto.compagnia
        self.dataAssegnazione = dto.created_at
        self.assignedToUserEmail = nil
    }
}

struct SinistroDetail: Identifiable {
    let id: String
    let riferimento: String
    let garanzia: String?
    let stato: StatoSinistro
    let numeroSinistroCompagnia: String?
    let nomeAssicurato: String?
    let nomeCompagnia: String?
    let dataAssegnazione: Date?
    let dataChiusura: Date?
    let assignedToUserEmail: String?
    let assignedToUserName: String?
    
    init(from dto: SinistroDTO) {
        self.id = dto.id
        self.riferimento = dto.riferimento
        self.garanzia = dto.garanzia
        self.stato = StatoSinistro(rawValue: dto.stato) ?? .istruzione
        self.numeroSinistroCompagnia = dto.numeroSinistroCompagnia
        self.nomeAssicurato = dto.nomeAssicurato
        self.nomeCompagnia = dto.nomeCompagnia
        self.dataAssegnazione = dto.dataAssegnazione
        self.dataChiusura = dto.dataChiusura
        self.assignedToUserEmail = dto.assignedToUserEmail
        self.assignedToUserName = nil
    }
    
    init(from sinistro: Sinistro) {
        self.id = sinistro.riferimento ?? UUID().uuidString
        self.riferimento = sinistro.riferimento ?? ""
        self.garanzia = sinistro.garanzia ?? sinistro.fulminazione
        self.stato = StatoSinistro(rawValue: sinistro.stato ?? "") ?? .istruzione
        self.numeroSinistroCompagnia = sinistro.numeroSinistroCompagnia
        self.nomeAssicurato = sinistro.nomeAssicurato
        self.nomeCompagnia = sinistro.nomeCompagnia
        self.dataAssegnazione = sinistro.dataAssegnazione
        self.dataChiusura = sinistro.dataChiusura
        self.assignedToUserEmail = sinistro.assignedToUserEmail
        self.assignedToUserName = sinistro.assignedToUserName
    }

    init(from dto: CloudClaimResponse) {
        self.id = dto.id
        self.riferimento = dto.external_ref ?? dto.id
        self.garanzia = dto.garanzia
        self.stato = BackendStatoMapping.statoSinistro(forCloudSlug: dto.stato_corrente) ?? .istruzione
        self.numeroSinistroCompagnia = dto.numero_sinistro
        self.nomeAssicurato = dto.nome_assicurato
        self.nomeCompagnia = dto.compagnia
        self.dataAssegnazione = dto.created_at
        self.dataChiusura = dto.closed_at
        self.assignedToUserEmail = nil
        self.assignedToUserName = nil
    }
}

// MARK: - CoreData import

import CoreData
