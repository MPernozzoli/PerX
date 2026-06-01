import Foundation
import OSLog

/// Compatibility facade for existing call sites.
///
/// New code should call `LocalAIService` directly. Process management lives in
/// the PerX Local Agent boundary and is intentionally absent from this type.
final class OllamaService {
    static let shared = OllamaService()

    /// PerX macOS is distributed directly with Developer ID, outside App Store sandboxing.
    static let isAvailable = true

    private let localAIService = LocalAIService.shared
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "it.pernozzoli.PerX",
        category: "OllamaCompatibility"
    )

    private init() {}

    func isRunning() async -> Bool {
        await localAIService.isOllamaAvailable()
    }

    func startOllama() async -> Bool {
        do {
            return try await localAIService.startOllamaIfNeeded()
        } catch {
            logger.error("event=ollama_start_failed error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func loadModel(modelName: String, ggufPath: String) async -> Result<String, Error> {
        do {
            let importedModel = try await localAIService.importGGUFModel(
                modelName: modelName,
                ggufPath: ggufPath
            )
            return .success(importedModel)
        } catch {
            logger.error("event=ollama_model_import_failed error=\(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func findModelName(_ modelName: String) async -> String? {
        do {
            return try await localAIService.findLocalModelName(modelName)
        } catch {
            logger.error("event=ollama_model_lookup_failed error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func isModelLoaded(_ modelName: String) async -> Bool {
        await findModelName(modelName) != nil
    }

    func getLoadedModels() async -> [String] {
        do {
            return try await localAIService.listLocalModels().map(\.name)
        } catch {
            logger.error("event=ollama_models_list_failed error=\(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
