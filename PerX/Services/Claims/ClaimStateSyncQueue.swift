import Foundation
import Network

// MARK: - Pending operation model

/// Operazione di cambio stato sinistro in attesa di sincronizzazione.
/// Persistita in UserDefaults e ritentata al ritorno della connessione.
struct PendingClaimStateOperation: Codable {
    let opId: UUID
    let riferimento: String
    let fromState: String?
    let toState: String
    let sopralluogoSubstato: String?
    let reason: String?
    var retryCount: Int
    let enqueuedAt: Date
}

// MARK: - Sync queue

/// Coda offline-first per i cambi di stato sinistro.
///
/// Simmetrica a `TaskSyncQueue`:
/// 1. `enqueue(...)` salva l'op e tenta subito il flush.
/// 2. Se offline → resta in UserDefaults.
/// 3. `NWPathMonitor` rileva il ritorno online → `flush()`.
/// 4. Idempotenza: server valida `from_state` contro `stato_corrente`.
///    Se non combaciano (già applicata o conflitto) il backend risponde
///    400 → l'op viene rimossa dalla coda.
@MainActor
final class ClaimStateSyncQueue: ObservableObject {
    static let shared = ClaimStateSyncQueue()

    @Published private(set) var pendingCount = 0
    @Published private(set) var isSyncing = false

    private let queueKey = "claim_state_sync_queue_v1"
    private let maxRetries = 5

    private var queue: [PendingClaimStateOperation] = []

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.perx.claimstatesync.monitor",
                                             qos: .utility)

    private init() {
        loadState()
        startNetworkMonitor()
    }

    // MARK: - Enqueue

    /// Accoda un cambio stato e tenta subito il flush.
    func enqueue(
        riferimento: String,
        fromState: String?,
        toState: String,
        sopralluogo_substato: String? = nil,
        reason: String?
    ) async {
        let op = PendingClaimStateOperation(
            opId: UUID(),
            riferimento: riferimento,
            fromState: fromState,
            toState: toState,
            sopralluogoSubstato: sopralluogo_substato,
            reason: reason,
            retryCount: 0,
            enqueuedAt: Date()
        )
        queue.append(op)
        persistState()
        pendingCount = queue.count
        await flush()
    }

    // MARK: - Flush

    func flush() async {
        guard !isSyncing, !queue.isEmpty else { return }
        guard HubAPIAdapterClient.shared.isCloudConfigured else { return }

        isSyncing = true
        defer { isSyncing = false }

        var remaining: [PendingClaimStateOperation] = []

        for var op in queue {
            do {
                try await execute(op)
                print("[ClaimStateSyncQueue] ☁️ Applied \(op.riferimento) → \(op.toState)")
            } catch let HubClientError.httpError(code) where code == 400 || code == 409 {
                // Server rifiuta la transizione: già applicata o conflitto reale.
                // In entrambi i casi, ritentare non aiuta → drop.
                print("[ClaimStateSyncQueue] ⛔️ Drop op \(op.opId) (HTTP \(code) — già applicata o invalida)")
            } catch {
                op.retryCount += 1
                if op.retryCount < maxRetries {
                    remaining.append(op)
                }
                print("[ClaimStateSyncQueue] ⚠️ \(op.riferimento) → \(op.toState) tentativo \(op.retryCount): \(error.localizedDescription)")
            }
        }

        queue = remaining
        persistState()
        pendingCount = queue.count
    }

    // MARK: - Execute

    private func execute(_ op: PendingClaimStateOperation) async throws {
        struct Body: Encodable {
            let from_state: String?
            let to_state: String
            let reason: String?
            let payload: [String: String]?
            let sopralluogo_substato: String?
        }
        struct Resp: Decodable { let status: String }

        let body = Body(
            from_state: op.fromState,
            to_state: op.toState,
            reason: op.reason,
            payload: ["client_op_id": op.opId.uuidString],
            sopralluogo_substato: op.sopralluogoSubstato
        )
        let _: Resp = try await HubAPIAdapterClient.shared.cloudPost(
            "/api/v1/claims/\(op.riferimento)/state-transitions",
            body: body
        )
    }

    // MARK: - Network monitor

    private func startNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                await self?.flush()
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Persistence

    private func loadState() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = UserDefaults.standard.data(forKey: queueKey),
           let ops = try? decoder.decode([PendingClaimStateOperation].self, from: data) {
            queue = ops
            pendingCount = ops.count
        }
    }

    private func persistState() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(queue) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }
}
