import Foundation
import OSLog

enum PerXLocalAgent {
    static let shared: any PerXLocalAgentClient = XPCPerXLocalAgentClient.shared
}

final class XPCPerXLocalAgentClient: @unchecked Sendable, PerXLocalAgentClient {
    static let shared = XPCPerXLocalAgentClient()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "it.pernozzoli.PerX",
        category: "PerXLocalAgentXPCClient"
    )
    private let connectionLock = NSLock()
    private var connection: NSXPCConnection?

    private init() {}

    func refreshDependencyStatuses(checkForUpdates: Bool) async -> [LocalDependencyStatus] {
        do {
            let response = try await perform(
                LocalAgentXPCRequest(
                    operation: .refreshDependencyStatuses,
                    checkForUpdates: checkForUpdates
                )
            )
            return try require(response.statuses, field: "statuses")
        } catch {
            logger.error("event=xpc_dependencies_refresh_failed error=\(error.localizedDescription, privacy: .public)")
            return LocalDependency.allCases.map { errorStatus(for: $0, error: error) }
        }
    }

    func dependencyStatus(
        _ dependency: LocalDependency,
        checkForUpdates: Bool
    ) async -> LocalDependencyStatus {
        do {
            let response = try await perform(
                LocalAgentXPCRequest(
                    operation: .dependencyStatus,
                    dependency: dependency,
                    checkForUpdates: checkForUpdates
                )
            )
            return try require(response.status, field: "status")
        } catch {
            logger.error("event=xpc_dependency_status_failed dependency=\(dependency.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return errorStatus(for: dependency, error: error)
        }
    }

    func installDependency(_ dependency: LocalDependency) async throws -> LocalDependencyStatus {
        let response = try await perform(
            LocalAgentXPCRequest(operation: .installDependency, dependency: dependency)
        )
        return try require(response.status, field: "status")
    }

    func updateDependency(_ dependency: LocalDependency) async throws -> LocalDependencyStatus {
        let response = try await perform(
            LocalAgentXPCRequest(operation: .updateDependency, dependency: dependency)
        )
        return try require(response.status, field: "status")
    }

    func startDependencyMonitoring(interval: TimeInterval) async {
        do {
            _ = try await perform(
                LocalAgentXPCRequest(
                    operation: .startDependencyMonitoring,
                    interval: interval
                )
            )
        } catch {
            logger.error("event=xpc_dependency_monitor_start_failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    func stopDependencyMonitoring() async {
        do {
            _ = try await perform(LocalAgentXPCRequest(operation: .stopDependencyMonitoring))
        } catch {
            logger.error("event=xpc_dependency_monitor_stop_failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    func runPythonScript(
        scriptPath: String,
        arguments: [String],
        environment: [String: String],
        standardInput: Data?,
        timeout: TimeInterval
    ) async throws -> LocalAgentCommandResult {
        let response = try await perform(
            LocalAgentXPCRequest(
                operation: .runPythonScript,
                scriptPath: scriptPath,
                arguments: arguments,
                environment: environment,
                standardInput: standardInput,
                timeout: timeout
            )
        )
        return try require(response.commandResult, field: "commandResult")
    }

    func createZipArchive(
        from inputURL: URL,
        at outputURL: URL,
        recursive: Bool,
        flattenPaths: Bool
    ) async throws {
        _ = try await perform(
            LocalAgentXPCRequest(
                operation: .createZipArchive,
                inputPath: inputURL.path,
                outputPath: outputURL.path,
                recursive: recursive,
                flattenPaths: flattenPaths
            )
        )
    }

    func isOllamaAvailable() async -> Bool {
        do {
            let response = try await perform(LocalAgentXPCRequest(operation: .isOllamaAvailable))
            return try require(response.boolValue, field: "boolValue")
        } catch {
            logger.error("event=xpc_ollama_health_failed error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func startOllamaIfNeeded(timeout: TimeInterval) async throws {
        _ = try await perform(
            LocalAgentXPCRequest(operation: .startOllamaIfNeeded, timeout: timeout)
        )
    }

    func listOllamaModels() async throws -> [LocalAIModel] {
        let response = try await perform(LocalAgentXPCRequest(operation: .listOllamaModels))
        return try require(response.models, field: "models")
    }

    func generateOllama(
        model: String,
        prompt: String,
        images: [String]?,
        timeout: TimeInterval
    ) async throws -> String {
        let response = try await perform(
            LocalAgentXPCRequest(
                operation: .generateOllama,
                timeout: timeout,
                model: model,
                prompt: prompt,
                images: images
            )
        )
        return try require(response.stringValue, field: "stringValue")
    }

    func streamOllama(
        model: String,
        prompt: String,
        timeout: TimeInterval,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let receiver = XPCStreamReceiver(onToken: onToken)
        defer { receiver.invalidate() }
        let response = try await performStreaming(
            LocalAgentXPCRequest(
                operation: .streamOllama,
                timeout: timeout,
                model: model,
                prompt: prompt
            ),
            callbackEndpoint: receiver.endpoint
        )
        return try require(response.stringValue, field: "stringValue")
    }

    func importGGUFModel(modelName: String, ggufPath: String) async throws -> String {
        let response = try await perform(
            LocalAgentXPCRequest(
                operation: .importGGUFModel,
                modelName: modelName,
                ggufPath: ggufPath
            )
        )
        return try require(response.stringValue, field: "stringValue")
    }

    private func perform(_ request: LocalAgentXPCRequest) async throws -> LocalAgentXPCResponse {
        let requestData = try JSONEncoder().encode(request)
        let responseData = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Data, Error>) in
            let gate = XPCReplyGate(continuation)
            do {
                let proxy = try remoteProxy { error in
                    gate.resume(.failure(error))
                }
                proxy.send(requestData) { data in
                    gate.resume(.success(data))
                }
            } catch {
                gate.resume(.failure(error))
            }
        }
        return try decode(responseData)
    }

    private func performStreaming(
        _ request: LocalAgentXPCRequest,
        callbackEndpoint: NSXPCListenerEndpoint
    ) async throws -> LocalAgentXPCResponse {
        let requestData = try JSONEncoder().encode(request)
        let responseData = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Data, Error>) in
            let gate = XPCReplyGate(continuation)
            do {
                let proxy = try remoteProxy { error in
                    gate.resume(.failure(error))
                }
                proxy.sendStreaming(requestData, callbackEndpoint: callbackEndpoint) { data in
                    gate.resume(.success(data))
                }
            } catch {
                gate.resume(.failure(error))
            }
        }
        return try decode(responseData)
    }

    private func decode(_ data: Data) throws -> LocalAgentXPCResponse {
        do {
            return try JSONDecoder().decode(LocalAgentXPCResponse.self, from: data).unwrapped()
        } catch let error as PerXLocalAgentError {
            throw error
        } catch {
            throw PerXLocalAgentError.agentUnavailable(
                "risposta XPC non valida: \(error.localizedDescription)"
            )
        }
    }

    private func remoteProxy(
        errorHandler: @escaping @Sendable (PerXLocalAgentError) -> Void
    ) throws -> PerXLocalAgentXPCProtocol {
        let connection = activeConnection()
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self, weak connection] error in
            let transportError = PerXLocalAgentError.agentUnavailable(error.localizedDescription)
            self?.logger.error("event=xpc_transport_failed error=\(error.localizedDescription, privacy: .public)")
            if let connection {
                self?.discard(connection)
            }
            errorHandler(transportError)
        }
        guard let typedProxy = proxy as? PerXLocalAgentXPCProtocol else {
            discard(connection)
            throw PerXLocalAgentError.agentUnavailable("proxy XPC non disponibile")
        }
        return typedProxy
    }

    private func activeConnection() -> NSXPCConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        if let connection {
            return connection
        }

        let newConnection = NSXPCConnection(serviceName: perXLocalAgentServiceName)
        newConnection.remoteObjectInterface = NSXPCInterface(with: PerXLocalAgentXPCProtocol.self)
        newConnection.interruptionHandler = { [weak self, weak newConnection] in
            self?.logger.notice("event=xpc_connection_interrupted")
            if let newConnection {
                self?.discard(newConnection)
            }
        }
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            self?.logger.notice("event=xpc_connection_invalidated")
            if let newConnection {
                self?.discard(newConnection)
            }
        }
        newConnection.resume()
        connection = newConnection
        logger.info("event=xpc_connection_opened service=\(perXLocalAgentServiceName, privacy: .public)")
        return newConnection
    }

    private func discard(_ discardedConnection: NSXPCConnection) {
        connectionLock.lock()
        if connection === discardedConnection {
            connection = nil
        }
        connectionLock.unlock()
    }

    private func require<Value>(_ value: Value?, field: String) throws -> Value {
        guard let value else {
            throw PerXLocalAgentError.agentUnavailable("payload XPC privo di \(field)")
        }
        return value
    }

    private func errorStatus(
        for dependency: LocalDependency,
        error: Error
    ) -> LocalDependencyStatus {
        LocalDependencyStatus(
            dependency: dependency,
            state: .error,
            executablePath: nil,
            version: nil,
            updateAvailable: nil,
            message: error.localizedDescription
        )
    }
}

private final class XPCReplyGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<Value, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

private final class XPCStreamReceiver: NSObject, NSXPCListenerDelegate, PerXLocalAgentXPCStreamProtocol {
    private let onToken: @Sendable (String) -> Void
    private let listener = NSXPCListener.anonymous()
    private let lock = NSLock()
    private var connections: [NSXPCConnection] = []

    var endpoint: NSXPCListenerEndpoint { listener.endpoint }

    init(onToken: @escaping @Sendable (String) -> Void) {
        self.onToken = onToken
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: PerXLocalAgentXPCStreamProtocol.self)
        newConnection.exportedObject = self
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let self, let newConnection else { return }
            self.lock.lock()
            self.connections.removeAll { $0 === newConnection }
            self.lock.unlock()
        }
        lock.lock()
        connections.append(newConnection)
        lock.unlock()
        newConnection.resume()
        return true
    }

    func receiveToken(_ token: String) {
        onToken(token)
    }

    func invalidate() {
        listener.invalidate()
        lock.lock()
        let activeConnections = connections
        connections.removeAll()
        lock.unlock()
        activeConnections.forEach { $0.invalidate() }
    }
}
