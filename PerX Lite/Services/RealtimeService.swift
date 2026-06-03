import Foundation
import Combine

struct RealtimeEvent {
    let type: String
    let payload: [String: Any]
}

@MainActor
final class RealtimeService: NSObject, ObservableObject, URLSessionDataDelegate {
    static let shared = RealtimeService()

    @Published private(set) var isConnected: Bool = false

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var reconnectAttempt = 0

    var onEvent: ((RealtimeEvent) -> Void)?

    func start() {
        stop()
        connect()
    }

    func stop() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
    }

    private func connect() {
        guard let token = APIClient.shared.accessToken else { return }
        let base = APIClient.shared.baseURL
        guard let url = URL(string: "\(base)/api/v1/realtime/stream?token=\(token)") else { return }

        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = .greatestFiniteMagnitude

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .greatestFiniteMagnitude
        config.timeoutIntervalForResource = .greatestFiniteMagnitude
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        let task = session.dataTask(with: req)
        self.task = task
        task.resume()
    }

    private func scheduleReconnect() {
        reconnectAttempt = min(reconnectAttempt + 1, 6)
        let delay = pow(2.0, Double(reconnectAttempt))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self.connect()
        }
    }

    // MARK: URLSessionDataDelegate

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor in
            self.isConnected = true
            self.reconnectAttempt = 0
            self.buffer.append(data)
            self.drainBuffer()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            if APIClient.shared.isLoggedIn {
                self.scheduleReconnect()
            }
        }
    }

    private func drainBuffer() {
        while let range = buffer.range(of: Data("\n\n".utf8)) {
            let chunk = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            guard let text = String(data: chunk, encoding: .utf8) else { continue }
            parseEvent(text)
        }
    }

    private func parseEvent(_ text: String) {
        var dataLine: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("data: ") {
                dataLine = String(line.dropFirst(6))
            }
        }
        guard let data = dataLine?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        let payload = (json["payload"] as? [String: Any]) ?? [:]
        onEvent?(RealtimeEvent(type: type, payload: payload))
    }
}
