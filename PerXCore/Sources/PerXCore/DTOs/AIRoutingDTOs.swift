import Foundation

// MARK: - AI Prompt Registry / Routing DTOs
//
// Allineati con backend/app/api/v1/routes_ai_routing.py.
//
// Tenuti in PerXCore così possiamo riutilizzarli da PerXHub (Mac mini)
// quando estenderemo il flow lato Hub. PerXCore non ha dipendenze HTTP:
// è ciascun consumatore (client iOS / Hub Mac) a gestire il transport
// con il proprio client REST.

// MARK: Routing modes & triggers

public enum AIRoutingMode: String, Codable, Sendable {
    case localOnly = "local_only"
    case preferLocal = "prefer_local"
    case preferCloud = "prefer_cloud"
    case cloudOnly = "cloud_only"
}

public enum AIRoutingTrigger: String, Codable, Sendable {
    /// L'utente preme un bottone in UI (analizza, classifica, ...).
    case userInitiated = "user_initiated"
    /// Processo automatico (scansione foto da mail/WA, job notturni).
    case background = "background"
    /// L'utente ha rifiutato la risposta locale e ha chiesto di riprovare.
    /// Forza cloud per default (override sulla policy).
    case regenerate = "regenerate"
}

public enum AIRunStatus: String, Codable, Sendable {
    case success
    case error
    case fallback
}

// MARK: Render prompt
//
// I body grezzi dei prompt sono asset proprietari e non vengono mai serviti
// in chiaro ai client runtime. Il client invia (phase, variables) e riceve
// testo gia renderizzato pronto da inoltrare al modello AI scelto.

public struct AIRenderPromptRequestDTO: Codable, Sendable {
    public let phase: String
    public let variables: [String: String]
    public let version_id: String?

    public init(phase: String, variables: [String: String], version_id: String? = nil) {
        self.phase = phase
        self.variables = variables
        self.version_id = version_id
    }
}

public struct AIRenderPromptResponseDTO: Codable, Sendable {
    public let phase: String
    public let body_rendered: String
    public let version_id: String?
}

// MARK: Policy

public struct AIRoutingPolicyDTO: Codable, Sendable {
    public let tenant_id: String?
    public let phase: String
    public let trigger: String
    public let mode: String

    public init(tenant_id: String?, phase: String, trigger: String, mode: String) {
        self.tenant_id = tenant_id
        self.phase = phase
        self.trigger = trigger
        self.mode = mode
    }
}

public struct AIResolvedRoutingDTO: Codable, Sendable {
    public let phase: String
    public let trigger: String
    public let mode: String
}

// MARK: Analysis runs (client → server)

public struct AIAnalysisRunRequestDTO: Codable, Sendable {
    public let sinistro_ref: String?
    public let phase: String
    public let prompt_key: String
    public let prompt_version_id: String
    public let provider_used: String     // es. "local_mlx", "openai", "anthropic"
    public let model_name: String?
    public let mode_applied: String      // uno di AIRoutingMode.rawValue
    public let trigger: String           // uno di AIRoutingTrigger.rawValue
    public let latency_ms: Int?
    public let input_token_count: Int?
    public let output_token_count: Int?
    public let status: String            // uno di AIRunStatus.rawValue
    public let error_message: String?
    public let client_id: String?

    public init(
        sinistro_ref: String?,
        phase: String,
        prompt_key: String,
        prompt_version_id: String,
        provider_used: String,
        model_name: String?,
        mode_applied: String,
        trigger: String,
        latency_ms: Int?,
        input_token_count: Int?,
        output_token_count: Int?,
        status: String,
        error_message: String?,
        client_id: String?
    ) {
        self.sinistro_ref = sinistro_ref
        self.phase = phase
        self.prompt_key = prompt_key
        self.prompt_version_id = prompt_version_id
        self.provider_used = provider_used
        self.model_name = model_name
        self.mode_applied = mode_applied
        self.trigger = trigger
        self.latency_ms = latency_ms
        self.input_token_count = input_token_count
        self.output_token_count = output_token_count
        self.status = status
        self.error_message = error_message
        self.client_id = client_id
    }
}

public struct AIAnalysisRunResponseDTO: Codable, Sendable {
    public let id: String
}

// MARK: Known phase keys (constants)

/// Fasi note del flusso sinistri, allineate con le `key` dei prompt template
/// e le righe `ai_routing_policy` lato backend.
public enum AISinistroPhase {
    public static let tagging = "sinistri.tagging"
    public static let fase1Approfondita = "sinistri.fase1_approfondita"
    public static let parseDenuncia = "sinistri.parse_denuncia"
    public static let raggruppamento = "sinistri.raggruppamento"
    public static let relazione = "sinistri.relazione"
}
