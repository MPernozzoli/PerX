import Foundation

/// Client per l'API Anthropic Claude (fallback cloud dopo OpenAI)
class ClaudeAIService {
    static let shared = ClaudeAIService()

    private let baseURL = "about:blank"
    private let apiVersion = "2023-06-01"

    var isAvailable: Bool {
        false
    }

    private var apiKey: String {
        ""
    }

    private var model: String {
        ""
    }

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func executeTask(_ task: AITask) async -> Result<AIResult, AIError> {
        guard isAvailable else { return .failure(.modelUnavailable) }

        let startTime = Date()
        let prompt = buildPrompt(for: task)

        let result = await callClaude(prompt: prompt, task: task)
        let processingTime = Date().timeIntervalSince(startTime)

        switch result {
        case .success(let text):
            return .success(AIResult.success(
                taskID: task.id,
                provider: .cloudClaude,
                result: text,
                metadata: ["model": model, "processingTime": processingTime],
                processingTime: processingTime
            ))
        case .failure(let error):
            return .failure(error)
        }
    }

    func executeTaskStreaming(
        _ task: AITask,
        streamCallback: @escaping (String) -> Void
    ) async -> Result<AIResult, AIError> {
        guard isAvailable else { return .failure(.modelUnavailable) }

        let startTime = Date()
        let prompt = buildPrompt(for: task)

        let result = await callClaudeStreaming(prompt: prompt, task: task, streamCallback: streamCallback)
        let processingTime = Date().timeIntervalSince(startTime)

        switch result {
        case .success(let text):
            return .success(AIResult.success(
                taskID: task.id,
                provider: .cloudClaude,
                result: text,
                metadata: ["model": model, "processingTime": processingTime, "streamed": true],
                processingTime: processingTime
            ))
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Private

    private func buildPrompt(for task: AITask) -> String {
        if task.requiresKnowledge || !task.knowledgeChunks.isEmpty {
            return buildPerXPrompt(from: task)
        }
        switch task.type {
        case .emailSummary:
            let subject = task.parameters["subject"]?.value as? String ?? ""
            let body = task.parameters["body"]?.value as? String ?? ""
            return "Riassumi questa email:\nOggetto: \(subject)\nCorpo: \(body)"
        case .documentAnalysis, .imageAnalysis:
            return task.parameters["prompt"]?.value as? String ?? "Analizza questo documento in dettaglio"
        case .textGeneration, .chat:
            return task.parameters["prompt"]?.value as? String ?? ""
        default:
            return "Esegui il task richiesto"
        }
    }

    private func makeRequest(to path: String, payload: [String: Any]) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    private func systemMessage(for task: AITask) -> String {
        if let custom = task.parameters["systemPrompt"]?.value as? String, !custom.isEmpty {
            return custom
        }
        return "Sei un assistente AI per un'azienda di perizie assicurative in Italia. Rispondi sempre in italiano."
    }

    private func callClaude(prompt: String, task: AITask) async -> Result<String, AIError> {
        let maxTokens = (task.parameters["max_tokens"]?.value as? Int) ?? 2000
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemMessage(for: task),
            "messages": [["role": "user", "content": prompt]]
        ]
        do {
            let request = try makeRequest(to: "/messages", payload: payload)
            let (data, response) = try await session.data(for: request)
            return parseResponse(data: data, response: response)
        } catch let error as AIError {
            return .failure(error)
        } catch {
            return handleNetworkError(error)
        }
    }

    private func callClaudeStreaming(
        prompt: String,
        task: AITask,
        streamCallback: @escaping (String) -> Void
    ) async -> Result<String, AIError> {
        let maxTokens = (task.parameters["max_tokens"]?.value as? Int) ?? 2000
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemMessage(for: task),
            "messages": [["role": "user", "content": prompt]],
            "stream": true
        ]
        do {
            let request = try makeRequest(to: "/messages", payload: payload)
            let (asyncBytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.networkError("Risposta non valida"))
            }
            guard httpResponse.statusCode == 200 else {
                return .failure(.networkError("Status code: \(httpResponse.statusCode)"))
            }

            var fullResponse = ""
            var lineBuffer = Data()

            for try await byte in asyncBytes {
                if byte == 10 { // \n
                    if let line = String(data: lineBuffer, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !line.isEmpty {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" { break }
                            if let jsonData = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                               let type_ = json["type"] as? String,
                               type_ == "content_block_delta",
                               let delta = json["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                fullResponse += text
                                streamCallback(text)
                            }
                        }
                    }
                    lineBuffer = Data()
                } else if byte != 13 {
                    lineBuffer.append(byte)
                }
            }
            return .success(fullResponse)
        } catch {
            return handleNetworkError(error)
        }
    }

    private func parseResponse(data: Data, response: URLResponse) -> Result<String, AIError> {
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.networkError("Risposta non valida"))
        }
        if httpResponse.statusCode == 429 { return .failure(.rateLimitExceeded) }
        guard httpResponse.statusCode == 200 else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return .failure(.networkError(message))
            }
            return .failure(.networkError("Status code: \(httpResponse.statusCode)"))
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let content = json["content"] as? [[String: Any]],
           let firstBlock = content.first,
           let text = firstBlock["text"] as? String {
            return .success(text)
        }
        return .failure(.processingError("Risposta Claude non valida"))
    }

    private func handleNetworkError(_ error: Error) -> Result<String, AIError> {
        let nsError = error as NSError
        if nsError.code == NSURLErrorTimedOut { return .failure(.timeout) }
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return .failure(.timeout) }
        return .failure(.networkError(error.localizedDescription))
    }
}
