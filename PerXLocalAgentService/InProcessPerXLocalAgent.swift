import Foundation
import OSLog

/// Physical implementation of the PerX Local Agent boundary.
///
/// Only the embedded XPC target compiles this actor. The app target talks to it
/// through `XPCPerXLocalAgentClient`.
actor InProcessPerXLocalAgent: PerXLocalAgentClient {
    static let shared = InProcessPerXLocalAgent()

    private let fileManager: FileManager
    private let session: URLSession
    private let ollamaBaseURL: URL
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "it.pernozzoli.PerX",
        category: "PerXLocalAgent"
    )

    private var monitoringTask: Task<Void, Never>?
    private var dependencyCache: [LocalDependency: LocalDependencyStatus] = [:]
    private var ollamaServerProcess: Process?
    private var ollamaStandardOutput: Pipe?
    private var ollamaStandardError: Pipe?

    init(
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        ollamaBaseURL: URL = URL(string: "http://localhost:11434")!
    ) {
        self.fileManager = fileManager
        self.session = session
        self.ollamaBaseURL = ollamaBaseURL
    }

    // MARK: - Dependency lifecycle

    func refreshDependencyStatuses(checkForUpdates: Bool = false) async -> [LocalDependencyStatus] {
        var statuses: [LocalDependencyStatus] = []
        for dependency in LocalDependency.allCases {
            statuses.append(await dependencyStatus(dependency, checkForUpdates: checkForUpdates))
        }
        logger.info("event=dependencies_refreshed count=\(statuses.count) updates_checked=\(checkForUpdates)")
        return statuses
    }

    func dependencyStatus(
        _ dependency: LocalDependency,
        checkForUpdates: Bool = false
    ) async -> LocalDependencyStatus {
        guard let executablePath = locateExecutable(for: dependency) else {
            let status = LocalDependencyStatus(
                dependency: dependency,
                state: .missing,
                executablePath: nil,
                version: nil,
                updateAvailable: nil,
                message: "\(dependency.displayName) non trovato"
            )
            dependencyCache[dependency] = status
            logger.notice("event=dependency_missing dependency=\(dependency.rawValue, privacy: .public)")
            return status
        }

        let version = await readVersion(of: dependency, executablePath: executablePath)
        let updateAvailable = checkForUpdates
            ? await hasHomebrewUpdate(for: dependency)
            : dependencyCache[dependency]?.updateAvailable
        let status = LocalDependencyStatus(
            dependency: dependency,
            state: .installed,
            executablePath: executablePath,
            version: version,
            updateAvailable: updateAvailable,
            message: nil
        )
        dependencyCache[dependency] = status
        logger.debug("event=dependency_available dependency=\(dependency.rawValue, privacy: .public) path=\(executablePath, privacy: .public)")
        return status
    }

    func installDependency(_ dependency: LocalDependency) async throws -> LocalDependencyStatus {
        if (await dependencyStatus(dependency)).isInstalled {
            return await dependencyStatus(dependency, checkForUpdates: true)
        }

        guard let package = dependency.homebrewPackage else {
            logger.notice("event=dependency_install_manual dependency=\(dependency.rawValue, privacy: .public)")
            throw PerXLocalAgentError.dependencyNotInstallable(dependency)
        }
        guard let brewPath = locateExecutable(for: .homebrew) else {
            throw PerXLocalAgentError.homebrewRequired(dependency)
        }

        dependencyCache[dependency] = LocalDependencyStatus(
            dependency: dependency,
            state: .installing,
            executablePath: nil,
            version: nil,
            updateAvailable: nil,
            message: "Installazione in corso"
        )
        logger.info("event=dependency_install_started dependency=\(dependency.rawValue, privacy: .public) package=\(package, privacy: .public)")
        let result = try await runProcess(
            executablePath: brewPath,
            arguments: ["install", package],
            timeout: 900
        )
        try validate(result)
        logger.info("event=dependency_install_completed dependency=\(dependency.rawValue, privacy: .public)")
        return await dependencyStatus(dependency, checkForUpdates: true)
    }

    func updateDependency(_ dependency: LocalDependency) async throws -> LocalDependencyStatus {
        guard let package = dependency.homebrewPackage else {
            throw PerXLocalAgentError.dependencyNotUpdatable(dependency)
        }
        guard let brewPath = locateExecutable(for: .homebrew) else {
            throw PerXLocalAgentError.homebrewRequired(dependency)
        }

        dependencyCache[dependency] = LocalDependencyStatus(
            dependency: dependency,
            state: .updating,
            executablePath: locateExecutable(for: dependency),
            version: dependencyCache[dependency]?.version,
            updateAvailable: dependencyCache[dependency]?.updateAvailable,
            message: "Aggiornamento in corso"
        )
        logger.info("event=dependency_update_started dependency=\(dependency.rawValue, privacy: .public) package=\(package, privacy: .public)")
        let result = try await runProcess(
            executablePath: brewPath,
            arguments: ["upgrade", package],
            timeout: 900
        )
        try validate(result)
        logger.info("event=dependency_update_completed dependency=\(dependency.rawValue, privacy: .public)")
        return await dependencyStatus(dependency, checkForUpdates: true)
    }

    func startDependencyMonitoring(interval: TimeInterval = 60) async {
        guard monitoringTask == nil else { return }
        let sleepNanoseconds = UInt64(max(interval, 5) * 1_000_000_000)
        logger.info("event=dependency_monitor_started interval=\(interval)")
        monitoringTask = Task { [weak self] in
            var refreshCount = 0
            while !Task.isCancelled {
                guard let self else { return }
                // Version discovery runs every heartbeat; slower Homebrew
                // update discovery runs every ten heartbeats.
                let checkForUpdates = refreshCount > 0 && refreshCount.isMultiple(of: 10)
                _ = await self.refreshDependencyStatuses(checkForUpdates: checkForUpdates)
                refreshCount += 1
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
            }
        }
    }

    func stopDependencyMonitoring() async {
        monitoringTask?.cancel()
        monitoringTask = nil
        logger.info("event=dependency_monitor_stopped")
    }

    // MARK: - Tool execution

    func runPythonScript(
        scriptPath: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        standardInput: Data? = nil,
        timeout: TimeInterval = 60
    ) async throws -> LocalAgentCommandResult {
        guard fileManager.fileExists(atPath: scriptPath),
              fileManager.isReadableFile(atPath: scriptPath) else {
            throw PerXLocalAgentError.invalidInputFile(scriptPath)
        }
        guard let pythonPath = locateExecutable(for: .python) else {
            throw PerXLocalAgentError.dependencyMissing(.python)
        }

        var processEnvironment = ProcessInfo.processInfo.environment
        processEnvironment.merge(environment) { _, requested in requested }
        processEnvironment["PYTHONIOENCODING"] = processEnvironment["PYTHONIOENCODING"] ?? "utf-8"
        processEnvironment["LANG"] = processEnvironment["LANG"] ?? "en_US.UTF-8"
        processEnvironment["HOME"] = processEnvironment["HOME"] ?? NSHomeDirectory()
        processEnvironment.removeValue(forKey: "DEVELOPER_DIR")
        processEnvironment.removeValue(forKey: "XCODE_DEVELOPER_DIR_PATH")

        logger.info("event=python_script_started script=\((scriptPath as NSString).lastPathComponent, privacy: .public)")
        let result = try await runProcess(
            executablePath: pythonPath,
            arguments: [scriptPath] + arguments,
            environment: processEnvironment,
            standardInput: standardInput,
            timeout: timeout
        )
        logger.info("event=python_script_completed script=\((scriptPath as NSString).lastPathComponent, privacy: .public) status=\(result.exitCode)")
        return result
    }

    func createZipArchive(
        from inputURL: URL,
        at outputURL: URL,
        recursive: Bool,
        flattenPaths: Bool
    ) async throws {
        guard fileManager.fileExists(atPath: inputURL.path) else {
            throw PerXLocalAgentError.invalidInputFile(inputURL.path)
        }
        guard let zipPath = locateExecutable(for: .zip) else {
            throw PerXLocalAgentError.dependencyMissing(.zip)
        }

        try? fileManager.removeItem(at: outputURL)
        var arguments: [String] = []
        if recursive { arguments.append("-r") }
        if flattenPaths { arguments.append("-j") }
        arguments += ["-q", "-9", outputURL.path, inputURL.lastPathComponent]

        logger.info("event=zip_started recursive=\(recursive) flatten=\(flattenPaths)")
        let result = try await runProcess(
            executablePath: zipPath,
            arguments: arguments,
            currentDirectoryURL: inputURL.deletingLastPathComponent(),
            timeout: 300
        )
        try validate(result)
        logger.info("event=zip_completed")
    }

    // MARK: - Ollama route

    func isOllamaAvailable() async -> Bool {
        var request = URLRequest(url: ollamaBaseURL.appendingPathComponent("api/tags"))
        request.httpMethod = "GET"
        request.timeoutInterval = 2

        do {
            let (_, response) = try await session.data(for: request)
            let healthy = (response as? HTTPURLResponse)?.statusCode == 200
            logger.debug("event=ollama_health_result available=\(healthy)")
            return healthy
        } catch {
            logger.debug("event=ollama_health_failed error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func startOllamaIfNeeded(timeout: TimeInterval = 10) async throws {
        if await isOllamaAvailable() {
            logger.debug("event=ollama_launch_skipped reason=already_healthy")
            return
        }
        if ollamaServerProcess?.isRunning != true {
            guard let executablePath = locateExecutable(for: .ollama) else {
                throw PerXLocalAgentError.dependencyMissing(.ollama)
            }
            try startOllamaServer(executablePath: executablePath)
        }

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            try Task.checkCancellation()
            if await isOllamaAvailable() {
                logger.info("event=ollama_launch_completed")
                return
            }
            if ollamaServerProcess?.isRunning != true {
                throw PerXLocalAgentError.ollamaProcessExited
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        } while Date() < deadline

        throw PerXLocalAgentError.ollamaStartupTimedOut(timeout)
    }

    func listOllamaModels() async throws -> [LocalAIModel] {
        try await startOllamaIfNeeded()
        let data = try await performOllamaRequest(
            method: "GET",
            path: "api/tags",
            body: nil,
            timeout: 2
        )
        do {
            let models = try JSONDecoder().decode(OllamaTagsResponse.self, from: data).models
            logger.info("event=ollama_models_listed count=\(models.count)")
            return models
        } catch {
            throw PerXLocalAgentError.invalidServerResponse
        }
    }

    func generateOllama(
        model: String,
        prompt: String,
        images: [String]? = nil,
        timeout: TimeInterval = 120
    ) async throws -> String {
        try await startOllamaIfNeeded()
        let body = try JSONEncoder().encode(
            OllamaGenerateRequest(model: model, prompt: prompt, images: images, stream: false)
        )
        let data = try await performOllamaRequest(
            method: "POST",
            path: "api/generate",
            body: body,
            timeout: timeout
        )
        return try decodeOllamaGenerateResponse(data)
    }

    func streamOllama(
        model: String,
        prompt: String,
        timeout: TimeInterval = 600,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await startOllamaIfNeeded()

        var request = URLRequest(url: ollamaBaseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaGenerateRequest(model: model, prompt: prompt, images: nil, stream: true)
        )

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PerXLocalAgentError.invalidServerResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PerXLocalAgentError.localServiceFailed("errore HTTP \(http.statusCode)")
        }

        var fullResponse = ""
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(OllamaGenerateResponse.self, from: data) else {
                continue
            }
            if let error = payload.error, !error.isEmpty {
                throw PerXLocalAgentError.localServiceFailed(error)
            }
            if let token = payload.response, !token.isEmpty {
                fullResponse += token
                onToken(token)
            }
            if payload.done == true { break }
        }
        return fullResponse
    }

    func importGGUFModel(modelName: String, ggufPath: String) async throws -> String {
        guard fileManager.fileExists(atPath: ggufPath),
              fileManager.isReadableFile(atPath: ggufPath) else {
            throw PerXLocalAgentError.invalidModelFile(ggufPath)
        }
        guard let ollamaPath = locateExecutable(for: .ollama) else {
            throw PerXLocalAgentError.dependencyMissing(.ollama)
        }

        let sanitizedName = sanitizeModelName(modelName, fallbackPath: ggufPath)
        let modelfileURL = fileManager.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-Modelfile")
        try "FROM \(ggufPath)\n".write(to: modelfileURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: modelfileURL) }

        logger.info("event=ollama_model_import_started model=\(sanitizedName, privacy: .public)")
        let result = try await runProcess(
            executablePath: ollamaPath,
            arguments: ["create", sanitizedName, "-f", modelfileURL.path],
            timeout: 900
        )
        try validate(result)
        logger.info("event=ollama_model_import_completed model=\(sanitizedName, privacy: .public)")
        return sanitizedName
    }

    // MARK: - Internal helpers

    private func startOllamaServer(executablePath: String) throws {
        guard fileManager.fileExists(atPath: executablePath),
              fileManager.isExecutableFile(atPath: executablePath) else {
            throw PerXLocalAgentError.invalidExecutable(executablePath)
        }

        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["serve"]
        process.standardOutput = standardOutput
        process.standardError = standardError
        attachLogging(to: standardOutput, stream: "stdout")
        attachLogging(to: standardError, stream: "stderr")
        process.terminationHandler = { [logger] terminatedProcess in
            logger.info("event=ollama_process_terminated status=\(terminatedProcess.terminationStatus)")
        }

        do {
            logger.info("event=ollama_launch_requested command=\(executablePath, privacy: .public) serve")
            try process.run()
            ollamaServerProcess = process
            ollamaStandardOutput = standardOutput
            ollamaStandardError = standardError
            logger.info("event=ollama_process_started pid=\(process.processIdentifier)")
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            throw PerXLocalAgentError.launchFailed(error.localizedDescription)
        }
    }

    private func attachLogging(to pipe: Pipe, stream: String) {
        pipe.fileHandleForReading.readabilityHandler = { [logger] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return
            }
            logger.debug("event=ollama_process_output stream=\(stream, privacy: .public) message=\(String(text.prefix(1_000)), privacy: .private)")
        }
    }

    private func performOllamaRequest(
        method: String,
        path: String,
        body: Data?,
        timeout: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(url: ollamaBaseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PerXLocalAgentError.invalidServerResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = Self.serverErrorMessage(from: data)
                throw PerXLocalAgentError.localServiceFailed("errore HTTP \(http.statusCode): \(message)")
            }
            return data
        } catch let error as PerXLocalAgentError {
            throw error
        } catch {
            throw PerXLocalAgentError.localServiceFailed(error.localizedDescription)
        }
    }

    private func decodeOllamaGenerateResponse(_ data: Data) throws -> String {
        do {
            let payload = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            if let error = payload.error, !error.isEmpty {
                throw PerXLocalAgentError.localServiceFailed(error)
            }
            guard let response = payload.response?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !response.isEmpty else {
                throw PerXLocalAgentError.invalidServerResponse
            }
            return response
        } catch let error as PerXLocalAgentError {
            throw error
        } catch {
            throw PerXLocalAgentError.invalidServerResponse
        }
    }

    private func locateExecutable(for dependency: LocalDependency) -> String? {
        for path in executableCandidates(for: dependency) {
            guard fileManager.fileExists(atPath: path),
                  fileManager.isExecutableFile(atPath: path) else {
                continue
            }
            return path
        }
        return nil
    }

    private func executableCandidates(for dependency: LocalDependency) -> [String] {
        switch dependency {
        case .homebrew:
            return ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        case .python:
            return [
                "/usr/local/bin/python3",
                "/opt/homebrew/bin/python3",
                "/usr/bin/python3",
                "\(NSHomeDirectory())/.local/bin/python3"
            ]
        case .node:
            return ["/usr/local/bin/node", "/opt/homebrew/bin/node", "/usr/bin/node"]
        case .ollama:
            return [
                "/usr/local/bin/ollama",
                "/opt/homebrew/bin/ollama",
                "/usr/bin/ollama",
                "\(NSHomeDirectory())/.local/bin/ollama"
            ]
        case .zip:
            return ["/usr/bin/zip"]
        case .unzip:
            return ["/usr/bin/unzip"]
        }
    }

    private func readVersion(of dependency: LocalDependency, executablePath: String) async -> String? {
        let arguments: [String]
        switch dependency {
        case .python, .node, .ollama, .homebrew, .zip:
            arguments = ["--version"]
        case .unzip:
            arguments = ["-v"]
        }
        guard let result = try? await runProcess(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 5
        ), result.exitCode == 0 else {
            return nil
        }
        let version = result.combinedOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : String(version.prefix(500))
    }

    private func hasHomebrewUpdate(for dependency: LocalDependency) async -> Bool? {
        guard let package = dependency.homebrewPackage,
              let brewPath = locateExecutable(for: .homebrew) else {
            return nil
        }
        guard let result = try? await runProcess(
            executablePath: brewPath,
            arguments: ["outdated", "--formula", package],
            timeout: 60
        ) else {
            return nil
        }
        return !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        standardInput: Data? = nil,
        timeout: TimeInterval
    ) async throws -> LocalAgentCommandResult {
        guard fileManager.fileExists(atPath: executablePath),
              fileManager.isExecutableFile(atPath: executablePath) else {
            throw PerXLocalAgentError.invalidExecutable(executablePath)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputURL = fileManager.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)-perx-agent-stdout.log")
            let errorURL = fileManager.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)-perx-agent-stderr.log")

            do {
                try Data().write(to: outputURL)
                try Data().write(to: errorURL)
                let outputHandle = try FileHandle(forWritingTo: outputURL)
                let errorHandle = try FileHandle(forWritingTo: errorURL)
                let inputPipe = standardInput == nil ? nil : Pipe()
                let timeoutState = ProcessTimeoutState()

                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                process.currentDirectoryURL = currentDirectoryURL
                if let environment {
                    process.environment = environment
                }
                process.standardOutput = outputHandle
                process.standardError = errorHandle
                process.standardInput = inputPipe

                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0.1) * 1_000_000_000))
                    if process.isRunning {
                        timeoutState.markTimedOut()
                        process.terminate()
                    }
                }

                process.terminationHandler = { terminatedProcess in
                    timeoutTask.cancel()
                    try? outputHandle.close()
                    try? errorHandle.close()
                    let outputData = (try? Data(contentsOf: outputURL)) ?? Data()
                    let errorData = (try? Data(contentsOf: errorURL)) ?? Data()
                    try? FileManager.default.removeItem(at: outputURL)
                    try? FileManager.default.removeItem(at: errorURL)
                    if timeoutState.didTimeOut {
                        continuation.resume(throwing: PerXLocalAgentError.commandTimedOut(timeout))
                        return
                    }
                    continuation.resume(
                        returning: LocalAgentCommandResult(
                            exitCode: terminatedProcess.terminationStatus,
                            output: String(data: outputData, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                            errorOutput: String(data: errorData, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        )
                    )
                }

                try process.run()
                if let standardInput, let inputPipe {
                    inputPipe.fileHandleForWriting.write(standardInput)
                    try? inputPipe.fileHandleForWriting.close()
                }
            } catch {
                try? fileManager.removeItem(at: outputURL)
                try? fileManager.removeItem(at: errorURL)
                continuation.resume(throwing: PerXLocalAgentError.launchFailed(error.localizedDescription))
            }
        }
    }

    private func validate(_ result: LocalAgentCommandResult) throws {
        guard result.exitCode == 0 else {
            throw PerXLocalAgentError.commandFailed(
                exitCode: result.exitCode,
                output: String(result.combinedOutput.prefix(4_000))
            )
        }
    }

    private func sanitizeModelName(_ modelName: String, fallbackPath: String) -> String {
        let fallbackName = ((fallbackPath as NSString).lastPathComponent as NSString)
            .deletingPathExtension
        let candidate = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? fallbackName : candidate
    }

    private static func serverErrorMessage(from data: Data) -> String {
        if let response = try? JSONDecoder().decode(OllamaGenerateResponse.self, from: data),
           let error = response.error,
           !error.isEmpty {
            return error
        }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(500)
            .description ?? "nessun dettaglio disponibile"
    }
}

private struct OllamaTagsResponse: Decodable {
    let models: [LocalAIModel]
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let images: [String]?
    let stream: Bool
}

private struct OllamaGenerateResponse: Decodable {
    let response: String?
    let done: Bool?
    let error: String?
}

private final class ProcessTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }

    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }
}
