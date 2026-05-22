import Foundation
import Network

/// Coda offline-first per operazioni sui task.
///
/// Flusso:
/// 1. `enqueueCreate/Update/Complete/Delete` tenta la chiamata immediata.
/// 2. Se il server non è raggiungibile, l'operazione viene salvata in
///    UserDefaults come `PendingTaskOperation`.
/// 3. `NWPathMonitor` rileva il ritorno della connessione e chiama `flush()`.
/// 4. A flush avvenuto, la mappa `localId → cloudId` viene aggiornata così
///    che le operazioni successive (update, complete) trovino l'ID server.
@MainActor
final class TaskSyncQueue: ObservableObject {
    static let shared = TaskSyncQueue()

    @Published private(set) var pendingCount = 0
    @Published private(set) var isSyncing = false

    // MARK: - Storage keys
    private let queueKey    = "task_sync_queue_v1"
    private let cloudMapKey = "task_cloud_id_map_v1"

    // MARK: - State
    private var queue: [PendingTaskOperation] = []

    /// Mappa localId (UUID string) → cloudId (UUID string assegnato dal server).
    private var cloudIdMap: [String: String] = [:]

    // MARK: - Network monitor
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.perx.tasksync.monitor",
                                             qos: .utility)

    private init() {
        loadState()
        startNetworkMonitor()
    }

    // MARK: - Public accessors

    /// ID server corrispondente a una task locale, se già sincronizzata.
    func cloudTaskId(for localId: UUID) -> String? {
        cloudIdMap[localId.uuidString]
    }

    // MARK: - Enqueue helpers

    /// Aggiunge una create-task alla coda e prova immediatamente a sincronizzare.
    func enqueueCreate(_ task: DailyTask) async {
        addToQueue(.create(task: task))
        await flush()
    }

    /// Aggiunge un aggiornamento alla coda e prova immediatamente.
    func enqueueUpdate(
        localId: UUID,
        title: String?,
        description: String?,
        priority: Double?,
        dueDate: Date?,
        status: TaskStatus?
    ) async {
        let cloudId = cloudIdMap[localId.uuidString]
        addToQueue(.update(
            localId: localId,
            cloudId: cloudId,
            title: title,
            description: description,
            priority: priority,
            dueDate: dueDate,
            status: status
        ))
        await flush()
    }

    /// Aggiunge un completamento alla coda (solo se la task è già sul server).
    func enqueueComplete(localId: UUID) async {
        guard let cloudId = cloudIdMap[localId.uuidString] else {
            // Task mai sincronizzata: marca il completamento nel payload create
            // (sarà creata già come completed al prossimo flush).
            if let idx = queue.firstIndex(where: { $0.localId == localId && $0.type == .create }) {
                queue[idx].status = TaskStatus.completed.rawValue
                persistState()
            }
            return
        }
        addToQueue(.complete(localId: localId, cloudId: cloudId))
        await flush()
    }

    /// Aggiunge una delete alla coda (solo se la task è già sul server).
    func enqueueDelete(localId: UUID) async {
        guard let cloudId = cloudIdMap[localId.uuidString] else {
            // Task mai sincronizzata: rimuovila anche dalla coda di create.
            queue.removeAll { $0.localId == localId }
            persistState()
            pendingCount = queue.count
            return
        }
        // Rimuovi eventuali operazioni precedenti per questa task
        queue.removeAll { $0.localId == localId }
        addToQueue(.delete(localId: localId, cloudId: cloudId))
        await flush()
    }

    // MARK: - Flush

    /// Esegue tutte le operazioni in coda. Le operazioni fallite vengono
    /// mantenute in coda (fino a 5 tentativi).
    func flush() async {
        guard !isSyncing, !queue.isEmpty else { return }
        guard HubAPIAdapterClient.shared.isCloudConfigured else { return }

        isSyncing = true
        defer { isSyncing = false }

        var remaining: [PendingTaskOperation] = []

        for var op in queue {
            do {
                try await execute(op)
            } catch {
                op.retryCount += 1
                if op.retryCount < 5 {
                    remaining.append(op)
                }
                print("[TaskSyncQueue] ⚠️ \(op.type.rawValue) localId=\(op.localId) tentativo \(op.retryCount): \(error.localizedDescription)")
            }
        }

        queue = remaining
        persistState()
        pendingCount = queue.count
        print("[TaskSyncQueue] ✅ Flush: \(remaining.count) operazioni ancora in coda")
    }

    // MARK: - Execute single operation

    private func execute(_ op: PendingTaskOperation) async throws {
        let client = HubAPIAdapterClient.shared

        switch op.type {
        case .create:
            guard let title = op.title else { return }
            let body = CreateTaskRequest(
                title: title,
                description: op.taskDescription,
                type: op.taskType ?? "manual",
                priority: op.priority ?? "normal",
                sinistroRef: op.sinistroRef,
                dueDate: op.dueDate,
                assignedTo: op.assignedTo,
                createdBy: CurrentUserService.shared.currentEmail ?? "unknown",
                clientId: op.localId.uuidString
            )
            let dto: TaskDTO = try await client.cloudPost("/api/v1/tasks", body: body)
            cloudIdMap[op.localId.uuidString] = dto.id
            persistState()
            print("[TaskSyncQueue] ☁️ Created on server: localId=\(op.localId) → cloudId=\(dto.id)")

        case .update:
            guard let cloudId = op.cloudId else {
                print("[TaskSyncQueue] ⏭️ Update ignorato: cloudId non disponibile per \(op.localId)")
                return
            }
            let body = UpdateTaskRequest(
                title: op.title,
                description: op.taskDescription,
                priority: op.priority,
                dueDate: op.dueDate,
                status: op.status
            )
            let _: TaskDTO = try await client.cloudPut("/api/v1/tasks/\(cloudId)", body: body)
            print("[TaskSyncQueue] ☁️ Updated on server: cloudId=\(cloudId)")

        case .complete:
            guard let cloudId = op.cloudId else { return }
            struct EmptyBody: Encodable {}
            let _: TaskDTO = try await client.cloudPost("/api/v1/tasks/\(cloudId)/complete", body: EmptyBody())
            print("[TaskSyncQueue] ☁️ Completed on server: cloudId=\(cloudId)")

        case .delete:
            guard let cloudId = op.cloudId else { return }
            try await client.cloudDelete("/api/v1/tasks/\(cloudId)")
            cloudIdMap.removeValue(forKey: op.localId.uuidString)
            persistState()
            print("[TaskSyncQueue] ☁️ Deleted on server: cloudId=\(cloudId)")
        }
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

    // MARK: - Internal queue management

    private func addToQueue(_ op: PendingTaskOperation) {
        // Sostituisce un'operazione precedente dello stesso tipo sullo stesso task
        queue.removeAll { $0.localId == op.localId && $0.type == op.type }
        queue.append(op)
        persistState()
        pendingCount = queue.count
    }

    // MARK: - Persistence

    private func loadState() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = UserDefaults.standard.data(forKey: queueKey),
           let ops = try? decoder.decode([PendingTaskOperation].self, from: data) {
            queue = ops
            pendingCount = ops.count
        }
        if let data = UserDefaults.standard.data(forKey: cloudMapKey),
           let map = try? decoder.decode([String: String].self, from: data) {
            cloudIdMap = map
        }
    }

    private func persistState() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(queue) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
        if let data = try? encoder.encode(cloudIdMap) {
            UserDefaults.standard.set(data, forKey: cloudMapKey)
        }
    }
}
