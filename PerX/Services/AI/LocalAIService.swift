import Foundation
import OSLog

enum LocalAIError: LocalizedError {
    case ollamaNotInstalled
    case ollamaStartupTimedOut(TimeInterval)
    case ollamaProcessExited
    case invalidServerResponse
    case modelNotConfigured
    case modelMissing(String)
    case visionModelNotConfigured
    case visionModelMissing(String)
    case invalidImagePath(String)
    case invalidPrompt
    case emptyResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .ollamaNotInstalled:
            return "Ollama non risulta installato. Installa Ollama e riprova."
        case .ollamaStartupTimedOut(let timeout):
            return "Ollama non ha risposto su localhost:11434 entro \(Int(timeout)) secondi."
        case .ollamaProcessExited:
            return "Ollama si e chiuso prima di rendere disponibile il server locale."
        case .invalidServerResponse:
            return "Ollama ha restituito una risposta locale non valida."
        case .modelNotConfigured:
            return "Nessun modello Ollama locale e configurato."
        case .modelMissing(let model):
            return "Il modello Ollama locale '\(model)' non e installato. Scaricalo con Ollama e riprova."
        case .visionModelNotConfigured:
            return "Nessun modello vision Ollama e configurato. Seleziona un modello vision locale nelle impostazioni AI."
        case .visionModelMissing(let model):
            return "Il modello vision Ollama '\(model)' non e installato. Scarica un modello compatibile con immagini e riprova."
        case .invalidImagePath(let path):
            return "L'immagine da analizzare non e leggibile: \(path)"
        case .invalidPrompt:
            return "Il prompt per l'AI locale non puo essere vuoto."
        case .emptyResponse:
            return "Ollama non ha restituito contenuto."
        case .requestFailed(let reason):
            return "La richiesta a Ollama non e riuscita: \(reason)"
        }
    }
}

/// App-facing route for local text and vision AI.
///
/// This service never connects to Ollama or launches tools directly. Every
/// local operation crosses `PerXLocalAgentClient` through the embedded XPC service.
actor LocalAIService {
    static let shared = LocalAIService()

    private let agent: any PerXLocalAgentClient
    private let startupTimeout: TimeInterval
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "it.pernozzoli.PerX",
        category: "LocalAIService"
    )

    private var requestTimeout: TimeInterval {
        let configured = UserDefaults.standard.double(forKey: "ai_local_timeout")
        return configured > 0 ? configured : 60
    }

    init(
        agent: any PerXLocalAgentClient = PerXLocalAgent.shared,
        startupTimeout: TimeInterval = 10
    ) {
        self.agent = agent
        self.startupTimeout = startupTimeout
    }

    func isOllamaAvailable() async -> Bool {
        await agent.isOllamaAvailable()
    }

    @discardableResult
    func startOllamaIfNeeded() async throws -> Bool {
        do {
            try await agent.startOllamaIfNeeded(timeout: startupTimeout)
            return true
        } catch {
            logger.error("event=ollama_start_failed error=\(error.localizedDescription, privacy: .public)")
            throw mapAgentError(error)
        }
    }

    func listLocalModels() async throws -> [LocalAIModel] {
        do {
            return try await agent.listOllamaModels()
        } catch {
            throw mapAgentError(error)
        }
    }

    func findLocalModelName(_ requestedName: String) async throws -> String? {
        Self.resolveModelName(requestedName, in: try await listLocalModels())
    }

    func generateLocalText(prompt: String, model: String) async throws -> String {
        let installedModel = try await validatedModel(prompt: prompt, model: model)
        do {
            return try await agent.generateOllama(
                model: installedModel,
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                images: nil,
                timeout: requestTimeout
            )
        } catch {
            throw mapAgentError(error)
        }
    }

    func streamLocalText(
        prompt: String,
        model: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let installedModel = try await validatedModel(prompt: prompt, model: model)
        do {
            return try await agent.streamOllama(
                model: installedModel,
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                timeout: max(requestTimeout, 300),
                onToken: onToken
            )
        } catch {
            throw mapAgentError(error)
        }
    }

    func analyzeImageWithLocalVision(imagePath: String, prompt: String) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw LocalAIError.invalidPrompt
        }

        let configuredModel = UserDefaults.standard
            .string(forKey: "ai_local_multimodal_model")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !configuredModel.isEmpty else {
            throw LocalAIError.visionModelNotConfigured
        }

        let imageURL = URL(fileURLWithPath: imagePath)
        guard FileManager.default.fileExists(atPath: imageURL.path),
              FileManager.default.isReadableFile(atPath: imageURL.path) else {
            throw LocalAIError.invalidImagePath(imagePath)
        }

        let models = try await listLocalModels()
        guard let installedModel = Self.resolveModelName(configuredModel, in: models) else {
            throw LocalAIError.visionModelMissing(configuredModel)
        }

        do {
            let image = try Data(contentsOf: imageURL, options: [.mappedIfSafe])
            logger.info("event=ollama_vision_requested model=\(installedModel, privacy: .public)")
            let response = try await agent.generateOllama(
                model: installedModel,
                prompt: trimmedPrompt,
                images: [image.base64EncodedString()],
                timeout: requestTimeout
            )
            logger.info("event=ollama_vision_completed model=\(installedModel, privacy: .public)")
            return response
        } catch let error as LocalAIError {
            throw error
        } catch {
            throw mapAgentError(error)
        }
    }

    func importGGUFModel(modelName: String, ggufPath: String) async throws -> String {
        do {
            try await startOllamaIfNeeded()
            let importedName = try await agent.importGGUFModel(
                modelName: modelName,
                ggufPath: ggufPath
            )
            return try await findLocalModelName(importedName) ?? importedName
        } catch {
            throw mapAgentError(error)
        }
    }

    private func validatedModel(prompt: String, model: String) async throws -> String {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalAIError.invalidPrompt
        }
        let configuredModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configuredModel.isEmpty else {
            throw LocalAIError.modelNotConfigured
        }
        let models = try await listLocalModels()
        guard let installedModel = Self.resolveModelName(configuredModel, in: models) else {
            throw LocalAIError.modelMissing(configuredModel)
        }
        return installedModel
    }

    private func mapAgentError(_ error: Error) -> Error {
        switch error {
        case let localError as LocalAIError:
            return localError
        case PerXLocalAgentError.dependencyMissing(.ollama):
            return LocalAIError.ollamaNotInstalled
        case PerXLocalAgentError.ollamaStartupTimedOut(let timeout):
            return LocalAIError.ollamaStartupTimedOut(timeout)
        case PerXLocalAgentError.ollamaProcessExited:
            return LocalAIError.ollamaProcessExited
        case PerXLocalAgentError.invalidServerResponse:
            return LocalAIError.invalidServerResponse
        default:
            return LocalAIError.requestFailed(error.localizedDescription)
        }
    }

    private static func resolveModelName(_ requestedName: String, in models: [LocalAIModel]) -> String? {
        let requested = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requested.isEmpty else { return nil }

        if let exactMatch = models.first(where: {
            $0.name.caseInsensitiveCompare(requested) == .orderedSame
                || $0.name.caseInsensitiveCompare("\(requested):latest") == .orderedSame
        }) {
            return exactMatch.name
        }

        let requestedBase = requested
            .split(separator: ":", maxSplits: 1)
            .first?
            .lowercased() ?? requested.lowercased()
        return models.first(where: {
            $0.name
                .split(separator: ":", maxSplits: 1)
                .first?
                .lowercased() == requestedBase
        })?.name
    }
}
