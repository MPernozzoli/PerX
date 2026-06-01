import Foundation

enum AIRoutingMode: String, Codable {
    case localOnly = "local_only"
    case preferLocal = "prefer_local"
    case preferCloud = "prefer_cloud"
    case cloudOnly = "cloud_only"
}

enum AIRoutingTrigger: String, Codable {
    case userInitiated = "user_initiated"
    case background = "background"
    case regenerate = "regenerate"
}

struct AIRoutingPolicyDTO: Codable {
    let tenant_id: String?
    let phase: String
    let trigger: String
    let mode: String
}

struct AIAnalysisRunRequestDTO: Codable {
    let sinistro_ref: String?
    let phase: String
    let prompt_key: String
    let prompt_version_id: String
    let provider_used: String
    let model_name: String?
    let mode_applied: String
    let trigger: String
    let latency_ms: Int?
    let input_token_count: Int?
    let output_token_count: Int?
    let status: String
    let error_message: String?
    let client_id: String?
}

struct AIAnalysisRunResponseDTO: Codable {
    let id: String
}

// ============================================================================
// MARK: - AIPromptRegistry
// Cache offline-first della routing policy dal backend.
//
// Pattern offline-first coerente con [[project_task_system]]:
// - cache su disco in Application Support/AIPromptCache/
// - all'avvio carica cache, restituisce subito da cache se presente
// - in background lancia refresh "stale-while-revalidate"
// - se cache vuota e offline, errore
//
// Allineato con backend/app/api/v1/routes_ai_routing.py.
// ============================================================================

@MainActor
final class AIPromptRegistry {
    static let shared = AIPromptRegistry()

    private let client: HubAPIAdapterClient
    private let fileManager = FileManager.default

    // Cache in memoria — popolata da disco all'avvio, aggiornata da refresh.
    private var policyCache: [String: String] = [:]  // key "phase|trigger" -> mode

    // Refresh staleness: oltre questa età lanciamo un refresh in background
    // (ma serviamo comunque la cache subito). 1h è abbastanza per non
    // sovraccaricare il backend; gli admin che editano un prompt vedranno
    // la nuova versione al refresh successivo.
    private let maxStaleAge: TimeInterval = 60 * 60

    private var lastPolicyRefresh: Date?

    private init(client: HubAPIAdapterClient? = nil) {
        self.client = client ?? .shared
        loadFromDisk()
    }

    // MARK: - Public API

    /// Mode di routing per (phase, trigger). Usa policy cache; se assente
    /// (cache vuota o phase non trovata) cade su `prefer_local`, in linea
    /// col fallback del backend.
    func routingMode(phase: String, trigger: AIRoutingTrigger) -> AIRoutingMode {
        // regenerate forza sempre cloud, indipendentemente dalla policy
        // (regola di sistema: l'utente ha esplicitamente rifiutato il locale)
        if trigger == .regenerate {
            return .cloudOnly
        }
        let cacheKey = "\(phase)|\(trigger.rawValue)"
        if let mode = policyCache[cacheKey], let parsed = AIRoutingMode(rawValue: mode) {
            return parsed
        }
        return .preferLocal
    }

    /// Carica/refresha la matrice policy. Da chiamare al login e periodicamente.
    func refreshPolicyIfNeeded() async {
        if isStale(lastPolicyRefresh) {
            try? await refreshPolicy()
        }
    }

    /// Renderizza un prompt server-side e ritorna body pronto + version_id.
    ///
    /// I body sono asset proprietari: il backend renderizza `str.format_map`
    /// con le variabili passate e risponde con il testo finale. Il client
    /// non vede mai il template grezzo.
    ///
    /// `versionID` opzionale forza il render di una versione storica esatta
    /// (per riprocessing audit-friendly: stesso prompt di allora).
    func renderPrompt(
        phase: String,
        variables: [String: String],
        versionID: String? = nil
    ) async throws -> AIRenderPromptResponseDTO {
        let req = AIRenderPromptRequestDTO(
            phase: phase, variables: variables, version_id: versionID
        )
        let resp: AIRenderPromptResponseDTO = try await client.cloudPost(
            "/api/v1/ai-routing/render-prompt",
            body: req
        )
        return resp
    }

    /// Logga un'esecuzione AI al backend. Fire-and-forget: errori HTTP non
    /// bloccano l'analisi chiamante (solo log su console).
    func logAnalysisRun(_ run: AIAnalysisRunRequestDTO) {
        Task { [client] in
            do {
                let _: AIAnalysisRunResponseDTO = try await client.cloudPost(
                    "/api/v1/ai-routing/runs",
                    body: run
                )
            } catch {
                print("[AIPromptRegistry] log run failed: \(error)")
            }
        }
    }

    // MARK: - Refresh

    private func refreshPolicy() async throws {
        let rows: [AIRoutingPolicyDTO] = try await client.cloudGet("/api/v1/ai-routing/policy")
        // Compatta: tenant-specific vince sul globale (riga con tenant_id != nil)
        var resolved: [String: String] = [:]
        for row in rows {
            let key = "\(row.phase)|\(row.trigger)"
            if row.tenant_id != nil {
                resolved[key] = row.mode
            } else if resolved[key] == nil {
                resolved[key] = row.mode
            }
        }
        policyCache = resolved
        lastPolicyRefresh = Date()
        savePolicyToDisk(resolved)
    }

    // MARK: - Cache on disk

    private var cacheDirectory: URL? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = support.appendingPathComponent("AIPromptCache", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func loadFromDisk() {
        guard let dir = cacheDirectory else { return }
        let policyURL = dir.appendingPathComponent("policy.json")
        if let data = try? Data(contentsOf: policyURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            policyCache = decoded
        }
        // Rimuove prompt eventualmente salvati da versioni precedenti.
        if let entries = try? fileManager.contentsOfDirectory(atPath: dir.path) {
            for name in entries where name.hasPrefix("prompt_") && name.hasSuffix(".json") {
                try? fileManager.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    private func savePolicyToDisk(_ map: [String: String]) {
        guard let dir = cacheDirectory else { return }
        let url = dir.appendingPathComponent("policy.json")
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func isStale(_ at: Date?) -> Bool {
        guard let at else { return true }
        return Date().timeIntervalSince(at) > maxStaleAge
    }
}
