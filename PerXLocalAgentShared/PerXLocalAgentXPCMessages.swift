import Foundation

let perXLocalAgentServiceName = "it.pernozzoli.PerX.LocalAgent"

@objc protocol PerXLocalAgentXPCProtocol {
    func send(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
    func sendStreaming(
        _ requestData: Data,
        callbackEndpoint: NSXPCListenerEndpoint,
        withReply reply: @escaping (Data) -> Void
    )
}

@objc protocol PerXLocalAgentXPCStreamProtocol {
    func receiveToken(_ token: String)
}

struct LocalAgentXPCRequest: Codable, Sendable {
    enum Operation: String, Codable, Sendable {
        case refreshDependencyStatuses
        case dependencyStatus
        case installDependency
        case updateDependency
        case startDependencyMonitoring
        case stopDependencyMonitoring
        case runPythonScript
        case createZipArchive
        case isOllamaAvailable
        case startOllamaIfNeeded
        case listOllamaModels
        case generateOllama
        case streamOllama
        case importGGUFModel
    }

    let operation: Operation
    let dependency: LocalDependency?
    let checkForUpdates: Bool?
    let interval: TimeInterval?
    let scriptPath: String?
    let arguments: [String]?
    let environment: [String: String]?
    let standardInput: Data?
    let timeout: TimeInterval?
    let inputPath: String?
    let outputPath: String?
    let recursive: Bool?
    let flattenPaths: Bool?
    let model: String?
    let prompt: String?
    let images: [String]?
    let modelName: String?
    let ggufPath: String?

    init(
        operation: Operation,
        dependency: LocalDependency? = nil,
        checkForUpdates: Bool? = nil,
        interval: TimeInterval? = nil,
        scriptPath: String? = nil,
        arguments: [String]? = nil,
        environment: [String: String]? = nil,
        standardInput: Data? = nil,
        timeout: TimeInterval? = nil,
        inputPath: String? = nil,
        outputPath: String? = nil,
        recursive: Bool? = nil,
        flattenPaths: Bool? = nil,
        model: String? = nil,
        prompt: String? = nil,
        images: [String]? = nil,
        modelName: String? = nil,
        ggufPath: String? = nil
    ) {
        self.operation = operation
        self.dependency = dependency
        self.checkForUpdates = checkForUpdates
        self.interval = interval
        self.scriptPath = scriptPath
        self.arguments = arguments
        self.environment = environment
        self.standardInput = standardInput
        self.timeout = timeout
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.recursive = recursive
        self.flattenPaths = flattenPaths
        self.model = model
        self.prompt = prompt
        self.images = images
        self.modelName = modelName
        self.ggufPath = ggufPath
    }
}

struct LocalAgentXPCResponse: Codable, Sendable {
    let statuses: [LocalDependencyStatus]?
    let status: LocalDependencyStatus?
    let commandResult: LocalAgentCommandResult?
    let boolValue: Bool?
    let models: [LocalAIModel]?
    let stringValue: String?
    let error: LocalAgentXPCError?

    init(
        statuses: [LocalDependencyStatus]? = nil,
        status: LocalDependencyStatus? = nil,
        commandResult: LocalAgentCommandResult? = nil,
        boolValue: Bool? = nil,
        models: [LocalAIModel]? = nil,
        stringValue: String? = nil,
        error: LocalAgentXPCError? = nil
    ) {
        self.statuses = statuses
        self.status = status
        self.commandResult = commandResult
        self.boolValue = boolValue
        self.models = models
        self.stringValue = stringValue
        self.error = error
    }

    static func failure(_ error: Error) -> LocalAgentXPCResponse {
        LocalAgentXPCResponse(error: LocalAgentXPCError(error: error))
    }

    func unwrapped() throws -> LocalAgentXPCResponse {
        if let error {
            throw error.materialized()
        }
        return self
    }
}

struct LocalAgentXPCError: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case agentUnavailable
        case dependencyMissing
        case dependencyNotInstallable
        case dependencyNotUpdatable
        case homebrewRequired
        case invalidExecutable
        case invalidInputFile
        case invalidModelFile
        case invalidRequest
        case launchFailed
        case commandTimedOut
        case commandFailed
        case ollamaStartupTimedOut
        case ollamaProcessExited
        case invalidServerResponse
        case localServiceFailed
    }

    let kind: Kind
    let dependency: LocalDependency?
    let path: String?
    let timeout: TimeInterval?
    let exitCode: Int32?
    let message: String

    init(error: Error) {
        let message = error.localizedDescription
        switch error {
        case PerXLocalAgentError.agentUnavailable(let reason):
            self.init(kind: .agentUnavailable, message: reason)
        case PerXLocalAgentError.dependencyMissing(let dependency):
            self.init(kind: .dependencyMissing, dependency: dependency, message: message)
        case PerXLocalAgentError.dependencyNotInstallable(let dependency):
            self.init(kind: .dependencyNotInstallable, dependency: dependency, message: message)
        case PerXLocalAgentError.dependencyNotUpdatable(let dependency):
            self.init(kind: .dependencyNotUpdatable, dependency: dependency, message: message)
        case PerXLocalAgentError.homebrewRequired(let dependency):
            self.init(kind: .homebrewRequired, dependency: dependency, message: message)
        case PerXLocalAgentError.invalidExecutable(let path):
            self.init(kind: .invalidExecutable, path: path, message: message)
        case PerXLocalAgentError.invalidInputFile(let path):
            self.init(kind: .invalidInputFile, path: path, message: message)
        case PerXLocalAgentError.invalidModelFile(let path):
            self.init(kind: .invalidModelFile, path: path, message: message)
        case PerXLocalAgentError.invalidRequest(let reason):
            self.init(kind: .invalidRequest, message: reason)
        case PerXLocalAgentError.launchFailed(let reason):
            self.init(kind: .launchFailed, message: reason)
        case PerXLocalAgentError.commandTimedOut(let timeout):
            self.init(kind: .commandTimedOut, timeout: timeout, message: message)
        case PerXLocalAgentError.commandFailed(let exitCode, let output):
            self.init(kind: .commandFailed, exitCode: exitCode, message: output)
        case PerXLocalAgentError.ollamaStartupTimedOut(let timeout):
            self.init(kind: .ollamaStartupTimedOut, timeout: timeout, message: message)
        case PerXLocalAgentError.ollamaProcessExited:
            self.init(kind: .ollamaProcessExited, message: message)
        case PerXLocalAgentError.invalidServerResponse:
            self.init(kind: .invalidServerResponse, message: message)
        case PerXLocalAgentError.localServiceFailed(let reason):
            self.init(kind: .localServiceFailed, message: reason)
        default:
            self.init(kind: .localServiceFailed, message: message)
        }
    }

    private init(
        kind: Kind,
        dependency: LocalDependency? = nil,
        path: String? = nil,
        timeout: TimeInterval? = nil,
        exitCode: Int32? = nil,
        message: String
    ) {
        self.kind = kind
        self.dependency = dependency
        self.path = path
        self.timeout = timeout
        self.exitCode = exitCode
        self.message = message
    }

    func materialized() -> PerXLocalAgentError {
        switch kind {
        case .agentUnavailable:
            return .agentUnavailable(message)
        case .dependencyMissing:
            return .dependencyMissing(dependency ?? .ollama)
        case .dependencyNotInstallable:
            return .dependencyNotInstallable(dependency ?? .ollama)
        case .dependencyNotUpdatable:
            return .dependencyNotUpdatable(dependency ?? .ollama)
        case .homebrewRequired:
            return .homebrewRequired(dependency ?? .ollama)
        case .invalidExecutable:
            return .invalidExecutable(path ?? message)
        case .invalidInputFile:
            return .invalidInputFile(path ?? message)
        case .invalidModelFile:
            return .invalidModelFile(path ?? message)
        case .invalidRequest:
            return .invalidRequest(message)
        case .launchFailed:
            return .launchFailed(message)
        case .commandTimedOut:
            return .commandTimedOut(timeout ?? 0)
        case .commandFailed:
            return .commandFailed(exitCode: exitCode ?? -1, output: message)
        case .ollamaStartupTimedOut:
            return .ollamaStartupTimedOut(timeout ?? 0)
        case .ollamaProcessExited:
            return .ollamaProcessExited
        case .invalidServerResponse:
            return .invalidServerResponse
        case .localServiceFailed:
            return .localServiceFailed(message)
        }
    }
}
