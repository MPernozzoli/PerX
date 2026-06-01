import Foundation
import PerXCore

// ============================================================================
// MARK: - AIRouter
// Smista l'esecuzione di una fase AI tra provider locale (MLX) e cloud in
// base a (phase, trigger), gestisce fallback automatico e logga l'esecuzione.
//
// Si appoggia ad `AIManager.shared` per l'esecuzione effettiva del singolo
// task: non riscrive la coda, ma decide quale `preferredProvider` mettere
// nella AITask e gestisce la catena di fallback in caso di errore o output
// malformato (regola di sistema concordata: parse JSON fallito o validate()
// false → riprova col provider successivo della chain).
//
// Catena per `mode`:
//   localOnly    -> [locale]
//   preferLocal  -> [locale, cloud]
//   preferCloud  -> [cloud, locale]
//   cloudOnly    -> [cloud]
//
// "locale" = `.localMultimodal` se ci sono immagini, altrimenti `.localText`.
//
// TODO (cluster LAN): quando introdurremo lo smistamento dinamico tra peer
// nella stessa rete, `providerChain` non cambia. Cambia *cosa significa
// "locale"*: oggi è il device corrente; in futuro sarà un protocollo
// `LocalAIProvider` con due implementazioni — `LocalDeviceMLXProvider`
// (corrente) e `LANPeerProvider` (peer scoperto via Bonjour / Mac mini Hub).
// La discovery va isolata in un nuovo `LocalAIClusterService` consumato qui.
// ============================================================================

@MainActor
final class AIRouter {
    static let shared = AIRouter()

    private let registry: AIPromptRegistry
    private init(registry: AIPromptRegistry = .shared) {
        self.registry = registry
    }

    // MARK: Outcome

    struct Outcome {
        let output: String?
        let providerUsed: AIModelProvider?
        let modeApplied: AIRoutingMode
        let trigger: AIRoutingTrigger
        let phase: String
        let promptVersionID: String
        let latencyMs: Int
        let status: AIRunStatus
        let errorMessage: String?
    }

    // MARK: Public API

    /// Esegue una fase AI con prompt già renderizzato dal backend.
    ///
    /// - Parameters:
    ///   - phase: chiave fase, es. `AISinistroPhase.tagging`
    ///   - trigger: `.userInitiated` / `.background` / `.regenerate`
    ///   - sinistroRef: ref del sinistro per audit (opzionale)
    ///   - renderedPrompt: testo già pronto (output di `AIPromptRegistry.renderPrompt`)
    ///   - promptVersionID: id versione usata, da `renderPrompt` response
    ///   - images: path delle immagini per task multimodali (vuoto = solo testo)
    ///   - systemPrompt: opzionale, per provider che lo supportano
    ///   - additionalParameters: extra params da passare alla AITask
    ///     (response_format, max_tokens, …)
    ///   - validate: closure che ritorna `true` se l'output è ben formato.
    ///     Quando ritorna `false` il router considera questo provider fallito
    ///     e passa al successivo della chain (regola: locale che sbaglia il
    ///     formato → fallback cloud).
    func run(
        phase: String,
        trigger: AIRoutingTrigger,
        sinistroRef: String?,
        renderedPrompt: String,
        promptVersionID: String,
        images: [URL] = [],
        systemPrompt: String? = nil,
        additionalParameters: [String: AnyCodable] = [:],
        taskType: AITaskType = .documentAnalysis,
        priority: AITaskPriority = .secondary,
        validate: @escaping (String) -> Bool = { _ in true }
    ) async -> Outcome {
        let mode = registry.routingMode(phase: phase, trigger: trigger)
        let chain = providerChain(mode: mode, isMultimodal: !images.isEmpty)
        let start = Date()
        var lastError: String?
        var providerForReport: AIModelProvider? = chain.first

        for (i, provider) in chain.enumerated() {
            providerForReport = provider
            let attempt = await runSingle(
                provider: provider,
                renderedPrompt: renderedPrompt,
                images: images,
                systemPrompt: systemPrompt,
                additionalParameters: additionalParameters,
                taskType: taskType,
                priority: priority
            )
            switch attempt {
            case .success(let text):
                if validate(text) {
                    let status: AIRunStatus = (i == 0) ? .success : .fallback
                    return finalize(
                        phase: phase, trigger: trigger,
                        sinistroRef: sinistroRef, versionID: promptVersionID,
                        provider: provider, mode: mode,
                        start: start, status: status,
                        output: text, error: nil
                    )
                }
                lastError = "output malformato (validate=false) su \(provider.rawValue)"
                print("[AIRouter] ⚠️ \(lastError ?? "")")
            case .failure(let err):
                lastError = err
                print("[AIRouter] ⚠️ provider \(provider.rawValue) ha fallito: \(err)")
            }
        }

        return finalize(
            phase: phase, trigger: trigger,
            sinistroRef: sinistroRef, versionID: promptVersionID,
            provider: providerForReport, mode: mode,
            start: start, status: .error,
            output: nil, error: lastError
        )
    }

    // MARK: Internals

    private func providerChain(
        mode: AIRoutingMode, isMultimodal: Bool
    ) -> [AIModelProvider] {
        // TODO cluster LAN: il primo elemento "locale" dovrà essere risolto
        // da LocalAIClusterService.bestLocalProvider() invece che hardcoded
        // a un provider del device corrente.
        let local: AIModelProvider = isMultimodal ? .localMultimodal : .localText
        let cloud: AIModelProvider = .cloudOpenAI
        switch mode {
        case .localOnly:    return [local]
        case .preferLocal:  return [local, cloud]
        case .preferCloud:  return [cloud, local]
        case .cloudOnly:    return [cloud]
        }
    }

    private func runSingle(
        provider: AIModelProvider,
        renderedPrompt: String,
        images: [URL],
        systemPrompt: String?,
        additionalParameters: [String: AnyCodable],
        taskType: AITaskType,
        priority: AITaskPriority
    ) async -> Result<String, String> {
        var params: [String: AnyCodable] = additionalParameters
        params["prompt"] = AnyCodable(renderedPrompt)
        if let sp = systemPrompt { params["systemPrompt"] = AnyCodable(sp) }
        if !images.isEmpty {
            params["images"] = AnyCodable(images.map { $0.path })
        }

        let task = AITask(
            type: taskType,
            priority: priority,
            preferredProvider: provider,
            fallbackProviders: [],     // il router gestisce il fallback, non AIManager
            allowFallback: false,
            parameters: params,
            requiresKnowledge: false
        )

        return await withCheckedContinuation { cont in
            var resumed = false
            AIManager.shared.enqueue(task) { aiResult in
                if resumed { return }
                resumed = true
                if aiResult.success, let text = aiResult.result?.value as? String {
                    cont.resume(returning: .success(text))
                } else {
                    let msg = aiResult.error?.localizedDescription ?? "errore sconosciuto"
                    cont.resume(returning: .failure(msg))
                }
            }
        }
    }

    private func finalize(
        phase: String, trigger: AIRoutingTrigger,
        sinistroRef: String?, versionID: String,
        provider: AIModelProvider?, mode: AIRoutingMode,
        start: Date, status: AIRunStatus,
        output: String?, error: String?
    ) -> Outcome {
        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
        let outcome = Outcome(
            output: output,
            providerUsed: provider,
            modeApplied: mode,
            trigger: trigger,
            phase: phase,
            promptVersionID: versionID,
            latencyMs: latencyMs,
            status: status,
            errorMessage: error
        )
        let run = AIAnalysisRunRequestDTO(
            sinistro_ref: sinistroRef,
            phase: phase,
            prompt_key: phase,
            prompt_version_id: versionID,
            provider_used: provider?.rawValue ?? "unknown",
            model_name: nil,
            mode_applied: mode.rawValue,
            trigger: trigger.rawValue,
            latency_ms: latencyMs,
            input_token_count: nil,
            output_token_count: nil,
            status: status.rawValue,
            error_message: error,
            client_id: clientIdentifier()
        )
        registry.logAnalysisRun(run)
        return outcome
    }

    /// Identificatore stabile del device per il log lato backend.
    /// Combina nome host + tipo (iOS/macOS) per distinguere iPad utente da
    /// PerXHub Mac mini negli `ai_analysis_runs`.
    private func clientIdentifier() -> String {
        #if os(macOS)
        let prefix = "macos"
        #elseif os(iOS)
        let prefix = "ios"
        #else
        let prefix = "device"
        #endif
        let host = ProcessInfo.processInfo.hostName
        return "\(prefix):\(host)"
    }
}
