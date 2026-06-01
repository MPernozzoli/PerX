import Foundation
import OSLog

final class PerXLocalAgentXPCService: NSObject, PerXLocalAgentXPCProtocol {
    static let shared = PerXLocalAgentXPCService()

    private let agent = InProcessPerXLocalAgent.shared
    private let logger = Logger(
        subsystem: perXLocalAgentServiceName,
        category: "XPCService"
    )

    private override init() {
        super.init()
        Task {
            await agent.startDependencyMonitoring(interval: 60)
        }
    }

    func send(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        Task {
            reply(Self.encode(await handle(requestData)))
        }
    }

    func sendStreaming(
        _ requestData: Data,
        callbackEndpoint: NSXPCListenerEndpoint,
        withReply reply: @escaping (Data) -> Void
    ) {
        let callbackConnection = NSXPCConnection(listenerEndpoint: callbackEndpoint)
        callbackConnection.remoteObjectInterface = NSXPCInterface(
            with: PerXLocalAgentXPCStreamProtocol.self
        )
        let callbackProxy = callbackConnection.remoteObjectProxyWithErrorHandler { [logger] error in
            logger.error("event=xpc_stream_callback_failed error=\(error.localizedDescription, privacy: .public)")
        } as? PerXLocalAgentXPCStreamProtocol
        callbackConnection.resume()

        Task {
            defer { callbackConnection.invalidate() }
            do {
                let request = try JSONDecoder().decode(LocalAgentXPCRequest.self, from: requestData)
                guard request.operation == .streamOllama else {
                    throw PerXLocalAgentError.invalidRequest(
                        "operazione \(request.operation.rawValue) non compatibile con streaming"
                    )
                }
                let output = try await agent.streamOllama(
                    model: try require(request.model, field: "model"),
                    prompt: try require(request.prompt, field: "prompt"),
                    timeout: request.timeout ?? 600
                ) { token in
                    callbackProxy?.receiveToken(token)
                }
                reply(Self.encode(LocalAgentXPCResponse(stringValue: output)))
            } catch {
                logger.error("event=xpc_stream_failed error=\(error.localizedDescription, privacy: .public)")
                reply(Self.encode(.failure(error)))
            }
        }
    }

    private func handle(_ requestData: Data) async -> LocalAgentXPCResponse {
        do {
            let request = try JSONDecoder().decode(LocalAgentXPCRequest.self, from: requestData)
            logger.debug("event=xpc_request operation=\(request.operation.rawValue, privacy: .public)")
            switch request.operation {
            case .refreshDependencyStatuses:
                return LocalAgentXPCResponse(
                    statuses: await agent.refreshDependencyStatuses(
                        checkForUpdates: request.checkForUpdates ?? false
                    )
                )
            case .dependencyStatus:
                return LocalAgentXPCResponse(
                    status: await agent.dependencyStatus(
                        try require(request.dependency, field: "dependency"),
                        checkForUpdates: request.checkForUpdates ?? false
                    )
                )
            case .installDependency:
                return LocalAgentXPCResponse(
                    status: try await agent.installDependency(
                        try require(request.dependency, field: "dependency")
                    )
                )
            case .updateDependency:
                return LocalAgentXPCResponse(
                    status: try await agent.updateDependency(
                        try require(request.dependency, field: "dependency")
                    )
                )
            case .startDependencyMonitoring:
                await agent.startDependencyMonitoring(interval: request.interval ?? 60)
                return LocalAgentXPCResponse()
            case .stopDependencyMonitoring:
                await agent.stopDependencyMonitoring()
                return LocalAgentXPCResponse()
            case .runPythonScript:
                return LocalAgentXPCResponse(
                    commandResult: try await agent.runPythonScript(
                        scriptPath: try require(request.scriptPath, field: "scriptPath"),
                        arguments: request.arguments ?? [],
                        environment: request.environment ?? [:],
                        standardInput: request.standardInput,
                        timeout: request.timeout ?? 60
                    )
                )
            case .createZipArchive:
                try await agent.createZipArchive(
                    from: URL(
                        fileURLWithPath: try require(request.inputPath, field: "inputPath")
                    ),
                    at: URL(
                        fileURLWithPath: try require(request.outputPath, field: "outputPath")
                    ),
                    recursive: request.recursive ?? true,
                    flattenPaths: request.flattenPaths ?? false
                )
                return LocalAgentXPCResponse()
            case .isOllamaAvailable:
                return LocalAgentXPCResponse(boolValue: await agent.isOllamaAvailable())
            case .startOllamaIfNeeded:
                try await agent.startOllamaIfNeeded(timeout: request.timeout ?? 10)
                return LocalAgentXPCResponse()
            case .listOllamaModels:
                return LocalAgentXPCResponse(models: try await agent.listOllamaModels())
            case .generateOllama:
                return LocalAgentXPCResponse(
                    stringValue: try await agent.generateOllama(
                        model: try require(request.model, field: "model"),
                        prompt: try require(request.prompt, field: "prompt"),
                        images: request.images,
                        timeout: request.timeout ?? 120
                    )
                )
            case .streamOllama:
                throw PerXLocalAgentError.invalidRequest(
                    "streamOllama richiede il canale callback XPC"
                )
            case .importGGUFModel:
                return LocalAgentXPCResponse(
                    stringValue: try await agent.importGGUFModel(
                        modelName: try require(request.modelName, field: "modelName"),
                        ggufPath: try require(request.ggufPath, field: "ggufPath")
                    )
                )
            }
        } catch {
            logger.error("event=xpc_request_failed error=\(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    private func require<Value>(_ value: Value?, field: String) throws -> Value {
        guard let value else {
            throw PerXLocalAgentError.invalidRequest("campo \(field) mancante")
        }
        return value
    }

    private static func encode(_ response: LocalAgentXPCResponse) -> Data {
        do {
            return try JSONEncoder().encode(response)
        } catch {
            let fallback = LocalAgentXPCResponse.failure(
                PerXLocalAgentError.localServiceFailed(
                    "serializzazione risposta XPC non riuscita: \(error.localizedDescription)"
                )
            )
            return (try? JSONEncoder().encode(fallback)) ?? Data()
        }
    }
}

final class PerXLocalAgentServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let service = PerXLocalAgentXPCService.shared
    private let logger = Logger(
        subsystem: perXLocalAgentServiceName,
        category: "XPCListener"
    )

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: PerXLocalAgentXPCProtocol.self)
        newConnection.exportedObject = service
        newConnection.invalidationHandler = { [logger] in
            logger.debug("event=xpc_client_disconnected")
        }
        newConnection.resume()
        logger.info("event=xpc_client_connected")
        return true
    }
}
