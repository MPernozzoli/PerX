import Foundation

/// Boundary used by the macOS app to communicate with the PerX Local Agent.
///
/// The app-facing layer must not launch tools or call local dependency services
/// directly. Its production implementation is the embedded XPC client.
protocol PerXLocalAgentClient: Sendable {
    func refreshDependencyStatuses(checkForUpdates: Bool) async -> [LocalDependencyStatus]
    func dependencyStatus(_ dependency: LocalDependency, checkForUpdates: Bool) async -> LocalDependencyStatus
    func installDependency(_ dependency: LocalDependency) async throws -> LocalDependencyStatus
    func updateDependency(_ dependency: LocalDependency) async throws -> LocalDependencyStatus
    func startDependencyMonitoring(interval: TimeInterval) async
    func stopDependencyMonitoring() async

    func runPythonScript(
        scriptPath: String,
        arguments: [String],
        environment: [String: String],
        standardInput: Data?,
        timeout: TimeInterval
    ) async throws -> LocalAgentCommandResult

    func createZipArchive(
        from inputURL: URL,
        at outputURL: URL,
        recursive: Bool,
        flattenPaths: Bool
    ) async throws

    func isOllamaAvailable() async -> Bool
    func startOllamaIfNeeded(timeout: TimeInterval) async throws
    func listOllamaModels() async throws -> [LocalAIModel]
    func generateOllama(
        model: String,
        prompt: String,
        images: [String]?,
        timeout: TimeInterval
    ) async throws -> String
    func streamOllama(
        model: String,
        prompt: String,
        timeout: TimeInterval,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String
    func importGGUFModel(modelName: String, ggufPath: String) async throws -> String
}
