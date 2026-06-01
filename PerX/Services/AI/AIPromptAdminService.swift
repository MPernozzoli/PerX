import Foundation
import PerXCore

// ============================================================================
// MARK: - AIPromptAdminService
// Service per la sezione settings "Prompt AI sinistri".
//
// Differente da `AIPromptRegistry` (runtime, server-rendered):
// - usa gli endpoint admin /api/v1/ai-prompts/* (richiedono platform_admin)
//   per leggere/scrivere il body grezzo dei template
// - usa /api/v1/ai-routing/policy per leggere/scrivere la matrice di routing
//
// La UI carica i dati al primo apparire e li ripopola dopo ogni save.
// ============================================================================

@MainActor
final class AIPromptAdminService: ObservableObject {
    static let shared = AIPromptAdminService()

    // MARK: DTOs

    struct PromptDTO: Codable, Identifiable {
        let id: String
        let tenant_id: String?
        let key: String
        let title: String
        let description: String?
        let body: String
        let variables: [String]?
        let version: Int
        let current_version_id: String?
        let updated_by_user_id: String?
    }

    struct PromptVersionDTO: Codable, Identifiable {
        let version_id: String
        let body: String
        let variables: [String]?
        let changelog: String?
        let created_at: String
        let created_by_user_id: String?

        var id: String { version_id }
    }

    struct PromptUpdateRequest: Codable {
        let title: String
        let description: String?
        let body: String
        let variables: [String]?
        let changelog: String?
    }

    struct PolicyUpdateRequest: Codable {
        let mode: String
    }

    // MARK: Published state

    @Published var prompt: PromptDTO?
    @Published var versions: [PromptVersionDTO] = []
    @Published var policyMatrix: [String: String] = [:]  // "phase|trigger" -> mode
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var lastError: String?

    private let client: HubAPIAdapterClient
    private init(client: HubAPIAdapterClient = .shared) {
        self.client = client
    }

    // MARK: Loading

    /// Carica prompt corrente + storico versioni + matrice policy.
    func load(promptKey: String = AISinistroPhase.tagging) async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil
        async let promptTask: PromptDTO = client.cloudGet("/api/v1/ai-prompts/\(promptKey)")
        async let versionsTask: [PromptVersionDTO] = client.cloudGet("/api/v1/ai-prompts/\(promptKey)/versions")
        async let policiesTask: [AIRoutingPolicyDTO] = client.cloudGet("/api/v1/ai-routing/policy")
        do {
            let p = try await promptTask
            let v = try await versionsTask
            let policies = try await policiesTask
            self.prompt = p
            self.versions = v
            self.policyMatrix = Self.flatten(policies)
        } catch {
            self.lastError = String(describing: error)
            print("[AIPromptAdmin] load failed: \(error)")
        }
    }

    /// Tenant-specific vince sul globale per la stessa (phase, trigger).
    private static func flatten(_ rows: [AIRoutingPolicyDTO]) -> [String: String] {
        var out: [String: String] = [:]
        for row in rows {
            let key = "\(row.phase)|\(row.trigger)"
            if row.tenant_id != nil {
                out[key] = row.mode
            } else if out[key] == nil {
                out[key] = row.mode
            }
        }
        return out
    }

    // MARK: Mutations

    /// Salva nuova versione del prompt (PUT /api/v1/ai-prompts/{key}).
    /// Il backend crea una riga immutabile in ai_prompt_template_versions.
    func savePrompt(
        key: String,
        title: String,
        description: String?,
        body: String,
        variables: [String]?,
        changelog: String?
    ) async {
        isSaving = true
        defer { isSaving = false }
        lastError = nil
        let req = PromptUpdateRequest(
            title: title, description: description, body: body,
            variables: variables, changelog: changelog
        )
        do {
            let updated: PromptDTO = try await client.cloudPut("/api/v1/ai-prompts/\(key)", body: req)
            self.prompt = updated
            // ricarica history per mostrare la nuova versione
            let v: [PromptVersionDTO] = try await client.cloudGet("/api/v1/ai-prompts/\(key)/versions")
            self.versions = v
        } catch {
            self.lastError = String(describing: error)
            print("[AIPromptAdmin] save failed: \(error)")
        }
    }

    /// Aggiorna la policy per (phase, trigger).
    /// PUT /api/v1/ai-routing/policy/{phase}/{trigger}
    func savePolicy(phase: String, trigger: AIRoutingTrigger, mode: AIRoutingMode) async {
        isSaving = true
        defer { isSaving = false }
        lastError = nil
        let req = PolicyUpdateRequest(mode: mode.rawValue)
        do {
            let _: AIRoutingPolicyDTO = try await client.cloudPut(
                "/api/v1/ai-routing/policy/\(phase)/\(trigger.rawValue)",
                body: req
            )
            policyMatrix["\(phase)|\(trigger.rawValue)"] = mode.rawValue
        } catch {
            self.lastError = String(describing: error)
            print("[AIPromptAdmin] save policy failed: \(error)")
        }
    }
}
