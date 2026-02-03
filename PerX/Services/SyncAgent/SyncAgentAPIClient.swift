import Foundation
import CryptoKit

/// Client HTTP verso il PerX Sync Agent con fallback LAN/remoto.
final class SyncAgentAPIClient {
    static let shared = SyncAgentAPIClient()
    private let config = SyncAgentConfig.shared

    /// Session dedicata (timeout + bypass PAC/proxy) per evitare -1001/-1003 su domini Tailscale.
    /// Timeout aumentati per metadata (può richiedere tempo per calcolare MD5 di molti file).
    private lazy var defaultSession: URLSession = {
        URLSession(configuration: makeSessionConfiguration(timeoutRequest: 300, timeoutResource: 600))
    }()
    
    /// Session dedicata per metadata con timeout molto lunghi (può richiedere molto tempo per calcolare MD5 di molti file).
    private lazy var metadataSession: URLSession = {
        URLSession(configuration: makeSessionConfiguration(timeoutRequest: 900, timeoutResource: 1800))
    }()
    
    // Mantiene vivi i download in corso (anche se la view cambia)
    private struct ActiveDownload {
        let session: URLSession
        let delegate: DownloadDelegateWithCompletion
    }
    private var activeDownloads: [UUID: ActiveDownload] = [:]
    private let activeDownloadsLock = NSLock()

    private init() {}

    // MARK: - Health Check
    
    /// GET /health - Verifica raggiungibilità agent
    func checkHealth() async -> (reachable: Bool, response: HealthCheckResponse?) {
        guard let baseURL = await config.bestBaseURL() else {
            return (false, nil)
        }
        do {
            let url = try buildURL(baseURL: baseURL, path: "/health")
            var request = URLRequest(url: url)
            debugPrintRequest(request, label: "GET /health")
            // 5s è troppo aggressivo (DNS/PAC/Tailscale può impiegare di più)
            request.timeoutInterval = 12
            let (data, urlResponse) = try await defaultSession.data(for: request)
            
            // Consideriamo "raggiungibile" se l'host risponde (anche se /health non è JSON).
            if let http = urlResponse as? HTTPURLResponse, !(200..<500).contains(http.statusCode) {
                return (false, nil)
            }
            
            // Prova decode JSON (opzionale)
            if let decoded = try? JSONDecoder().decode(HealthCheckResponse.self, from: data) {
                return (true, decoded)
            }
            return (true, nil)
        } catch {
            return (false, nil)
        }
    }

    // MARK: - Metadata
    
    /// GET /api/claims/{claim_id}/metadata - Scarica manifest
    func fetchMetadata(claimId: String, userId: String) async throws -> ClaimMetadata {
        try await get(
            "/api/claims/\(claimId)/metadata",
            query: [URLQueryItem(name: "user_id", value: userId)]
        )
    }

    // MARK: - Download
    
    /// GET /api/claims/{claim_id}/download - Download pacchetto (fallback)
    /// Progress callback riceve: (progress 0-1, bytesDownloaded, bytesTotal, bytesPerSecond)
    /// - expectedTotalBytes: fallback se il server non invia Content-Length
    func downloadPackage(claimId: String, userId: String, expectedTotalBytes: Int64? = nil, progress: @escaping (Double, Int64, Int64, Double) -> Void) async throws -> URL {
        try await download(
            "/api/claims/\(claimId)/download",
            query: [URLQueryItem(name: "user_id", value: userId)],
            expectedTotalBytes: expectedTotalBytes,
            progress: progress
        )
    }
    
    /// GET /api/claims/{claim_id}/download?file={path} - Download singolo file
    func downloadFile(claimId: String, userId: String, relativePath: String) async throws -> Data {
        let startTime = Date()
        
        // URLQueryItem codifica automaticamente, ma se passiamo un valore già codificato
        // fa doppio encoding. Inoltre, FastAPI usa unquote_plus che decodifica '+' come spazio.
        // Soluzione: costruiamo manualmente la query string per il parametro 'file' per avere
        // controllo totale sull'encoding, mentre usiamo URLQueryItem per gli altri parametri.
        var allowedChars = CharacterSet.urlQueryAllowed
        allowedChars.remove("+") // '+' deve essere codificato come %2B, non lasciato come +
        let encodedFile = relativePath.addingPercentEncoding(withAllowedCharacters: allowedChars) ?? relativePath
        
        // Costruiamo manualmente la query string per evitare doppio encoding
        let userQuery = "user_id=\(userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId)"
        let fileQuery = "file=\(encodedFile)"
        let queryString = "\(userQuery)&\(fileQuery)"
        
        print("[SyncAgent] 📥 Download file: '\(relativePath)' -> encoded: '\(encodedFile)'")
        
        // Costruiamo l'URL manualmente con la query string
        guard let baseURL = await config.bestBaseURL() else {
            throw SyncAgentError.unreachable
        }
        let path = "/api/claims/\(claimId)/download"
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw SyncAgentError.invalidURL
        }
        let basePath = components.path
        let normalizedBasePath = (basePath == "/") ? "" : basePath
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        components.path = normalizedBasePath + normalizedPath
        components.percentEncodedQuery = queryString
        
        guard let url = components.url else {
            throw SyncAgentError.invalidURL
        }
        
        var request = URLRequest(url: url)
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw SyncAgentError.missingAPIKey
        }
        request.setValue(key, forHTTPHeaderField: "x_api_key")
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
        
        print("[SyncAgent] 🔗 URL completo: \(url.absoluteString)")
        
        guard let url = request.url else {
            throw SyncAgentError.invalidURL
        }
        
        print("[SyncAgent] 🔗 URL completo: \(url.absoluteString)")
        debugPrintRequest(request, label: "GET downloadFile")
        
        // Per file > 5MB usa downloadTask (evita caricare tutto in RAM)
        // Per file piccoli usa dataTask (più semplice)
        let useDownloadTask = false // TODO: abilita quando abbiamo size hint dal metadata
        
        if useDownloadTask {
            // DownloadTask path (per file grandi) - usa la stessa query string costruita manualmente
            let tempURL = try await download(
                "/api/claims/\(claimId)/download",
                query: [
                    URLQueryItem(name: "user_id", value: userId),
                    URLQueryItem(name: "file", value: encodedFile)
                ],
                expectedTotalBytes: nil,
                progress: { _, _, _, _ in }
            )
            
            // Leggi file scaricato
            guard let data = try? Data(contentsOf: tempURL) else {
                try? FileManager.default.removeItem(at: tempURL)
                throw SyncAgentError.httpError("Impossibile leggere file scaricato")
            }
            
            // Cleanup temp
            try? FileManager.default.removeItem(at: tempURL)
            
            let duration = Date().timeIntervalSince(startTime)
            let sha256 = sha256Hash(data: data)
            
            // Log diagnostica
            if let response = try? await URLSession.shared.data(for: request).1 as? HTTPURLResponse {
                logDownloadDiagnostics(
                    url: url,
                    method: "GET",
                    response: response,
                    bytesReceived: Int64(data.count),
                    duration: duration,
                    sha256: sha256
                )
            }
            
            return data
        } else {
            // DataTask path (file piccoli)
            let (data, response) = try await defaultSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SyncAgentError.httpError("Risposta non HTTP")
            }
            
            // Verifica status: NON salvare se non è 200
            guard (200..<300).contains(httpResponse.statusCode) else {
                let duration = Date().timeIntervalSince(startTime)
                logDownloadDiagnostics(
                    url: url,
                    method: "GET",
                    response: httpResponse,
                    bytesReceived: Int64(data.count),
                    duration: duration
                )
                throw SyncAgentError.httpError("HTTP \(httpResponse.statusCode)")
            }
            
            // Verifica Content-Type: deve essere application/octet-stream o image/* per file binari
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            if contentType.contains("application/zip") {
                print("[SyncAgent] ⚠️ ATTENZIONE: Server ha restituito ZIP invece di file singolo per \(relativePath)")
                throw SyncAgentError.httpError("Server ha restituito ZIP invece di file singolo")
            }
            
            // Verifica Content-Length se presente
            if let contentLengthStr = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let expectedLength = Int64(contentLengthStr),
               expectedLength > 0 {
                if Int64(data.count) != expectedLength {
                    print("[SyncAgent] ❌ Content-Length mismatch: atteso \(expectedLength), ricevuto \(data.count)")
                    throw SyncAgentError.httpError("Content-Length mismatch: atteso \(expectedLength), ricevuto \(data.count)")
                }
            }
            
            let duration = Date().timeIntervalSince(startTime)
            let sha256 = sha256Hash(data: data)
            
            // Log diagnostica
            logDownloadDiagnostics(
                url: url,
                method: "GET",
                response: httpResponse,
                bytesReceived: Int64(data.count),
                duration: duration,
                sha256: sha256
            )
            
            print("[SyncAgent] ✅ Download file \(relativePath): \(data.count) bytes, Content-Type: \(contentType)")
            
            return data
        }
    }

    // MARK: - Upload
    
    /// POST /api/claims/{claim_id}/upload - Upload file modificati
    func uploadFiles(claimId: String, userId: String, files: [URL], subpath: String? = nil, progress: @escaping (Double) -> Void) async throws -> GenericAPIResponse {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "user_id", value: userId),
        ]
        if let subpath, !subpath.isEmpty {
            query.append(URLQueryItem(name: "subpath", value: subpath))
        }
        return try await uploadFiles(
            "/api/claims/\(claimId)/upload",
            query: query,
            files: files.map { ($0, $0.lastPathComponent) },
            progress: progress
        )
    }
    
    /// POST /api/claims/{claim_id}/upload - Upload con path relativo (per mantenere struttura 1:1)
    func uploadFiles(claimId: String, userId: String, files: [(url: URL, relativePath: String)], subpath: String? = nil, progress: @escaping (Double) -> Void) async throws -> GenericAPIResponse {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "user_id", value: userId),
        ]
        if let subpath, !subpath.isEmpty {
            query.append(URLQueryItem(name: "subpath", value: subpath))
        }
        return try await uploadFiles(
            "/api/claims/\(claimId)/upload",
            query: query,
            files: files.map { ($0.url, $0.relativePath) },
            progress: progress
        )
    }

    /// Upload da Data (usa quando i file sono letti dentro security-scoped access)
    func uploadFiles(claimId: String, userId: String, filesData: [(data: Data, relativePath: String)], progress: @escaping (Double) -> Void) async throws -> GenericAPIResponse {
        return try await uploadFiles(
            "/api/claims/\(claimId)/upload",
            query: [URLQueryItem(name: "user_id", value: userId)],
            filesData: filesData.map { ($0.data, $0.relativePath) },
            progress: progress
        )
    }

    // MARK: - Generic HTTP Methods

    private func authorizedRequest(path: String, query: [URLQueryItem] = []) async throws -> URLRequest {
        guard let baseURL = await config.bestBaseURL() else {
            throw SyncAgentError.unreachable
        }
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw SyncAgentError.missingAPIKey
        }
        let url = try buildURL(baseURL: baseURL, path: path, query: query)
        var request = URLRequest(url: url)
        debugPrintRequest(request, label: "REQUEST")
        // L'agent FastAPI attuale legge l'header come `x_api_key` (convert_underscores=False).
        // Mettiamo entrambi per compatibilità.
        request.setValue(key, forHTTPHeaderField: "x_api_key")
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
        return request
    }

    func post<T: Encodable, R: Decodable>(_ path: String, body: T, query: [URLQueryItem] = []) async throws -> R {
        var request = try await authorizedRequest(path: path, query: query)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await defaultSession.data(for: request)
        try validate(response: response, data: data)
        do {
            return try makeJSONDecoder().decode(R.self, from: data)
        } catch let decodingError as DecodingError {
            let jsonString = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            print("[SyncAgent] ❌ JSON decode error in POST \(path): \(decodingError)")
            print("[SyncAgent] Response: \(jsonString.prefix(500))")
            throw SyncAgentError.httpError("Errore decodifica JSON: \(decodingError.localizedDescription)")
        }
    }

    func get<R: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> R {
        let isMetadata = path.contains("/metadata")
        let maxRetries = isMetadata ? 3 : 1
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                var request = try await authorizedRequest(path: path, query: query)
                // Timeout aumentato per metadata (può richiedere tempo per scansionare molti file)
                if isMetadata {
                    request.timeoutInterval = 900 // 15 minuti per metadata
                }
                
                // Usa sessione dedicata per metadata con timeout più lunghi
                let session = isMetadata ? metadataSession : defaultSession
                let (data, response) = try await session.data(for: request)
                try validate(response: response, data: data)
                do {
                    return try makeJSONDecoder().decode(R.self, from: data)
                } catch let decodingError as DecodingError {
                    let jsonString = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
                    print("[SyncAgent] ❌ JSON decode error in \(path): \(decodingError)")
                    print("[SyncAgent] Response: \(jsonString.prefix(500))")
                    throw SyncAgentError.httpError("Errore decodifica JSON: \(decodingError.localizedDescription)")
                }
            } catch let error as URLError where error.code == .timedOut {
                lastError = error
                if attempt < maxRetries {
                    let delay = Double(attempt) * 2.0 // Backoff esponenziale: 2s, 4s, 6s
                    print("[SyncAgent] ⚠️ Timeout su \(path) (tentativo \(attempt)/\(maxRetries)), retry tra \(delay)s...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    print("[SyncAgent] ❌ Timeout su \(path) dopo \(maxRetries) tentativi")
                }
            } catch {
                // Altri errori non vengono ritentati
                throw error
            }
        }
        
        throw lastError ?? SyncAgentError.httpError("Timeout dopo \(maxRetries) tentativi")
    }

    func delete<R: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> R {
        var request = try await authorizedRequest(path: path, query: query)
        request.httpMethod = "DELETE"
        let (data, response) = try await defaultSession.data(for: request)
        try validate(response: response, data: data)
        return try makeJSONDecoder().decode(R.self, from: data)
    }

    /// DELETE /api/claims/{claim_id}/files?user_id=&file= - Elimina file su server (sync eliminazioni locali)
    func deleteFile(claimId: String, userId: String, relativePath: String) async throws -> GenericAPIResponse {
        try await delete(
            "/api/claims/\(claimId)/files",
            query: [
                URLQueryItem(name: "user_id", value: userId),
                URLQueryItem(name: "file", value: relativePath)
            ]
        )
    }

    /// Progress callback: (progress 0-1, bytesDownloaded, bytesTotal, bytesPerSecond)
    func download(_ path: String, query: [URLQueryItem], expectedTotalBytes: Int64? = nil, progress: @escaping (Double, Int64, Int64, Double) -> Void) async throws -> URL {
        var request = try await authorizedRequest(path: path, query: query)
        debugPrintRequest(request, label: "GET download")
        
        // Timeout lunghi: zip da 1-2GB può richiedere minuti
        request.timeoutInterval = 60 * 15 // 15 min
        
        // Usa l'API tradizionale con continuation per ricevere i callback di progresso
        return try await withCheckedThrowingContinuation { continuation in
            let downloadId = UUID()
            
            let delegate = DownloadDelegateWithCompletion(
                expectedTotalBytesHint: expectedTotalBytes,
                onProgress: progress,
                onComplete: { [weak self] result in
                    // Cleanup e resume continuation
                    self?.removeActiveDownload(id: downloadId)
                    continuation.resume(with: result)
                }
            )
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 60 * 15      // 15 min
            cfg.timeoutIntervalForResource = 60 * 60     // 60 min
            cfg.waitsForConnectivity = true
            cfg.allowsConstrainedNetworkAccess = true
            cfg.allowsExpensiveNetworkAccess = true
            cfg.connectionProxyDictionary = [:]
            let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: .main)
            delegate.session = session
            
            self.addActiveDownload(id: downloadId, session: session, delegate: delegate)
            
            let task = session.downloadTask(with: request)
            delegate.task = task
            delegate.startProgressPolling()
            task.resume()
        }
    }
    
    private func addActiveDownload(id: UUID, session: URLSession, delegate: DownloadDelegateWithCompletion) {
        activeDownloadsLock.lock()
        activeDownloads[id] = ActiveDownload(session: session, delegate: delegate)
        activeDownloadsLock.unlock()
    }
    
    private func removeActiveDownload(id: UUID) {
        activeDownloadsLock.lock()
        activeDownloads.removeValue(forKey: id)
        activeDownloadsLock.unlock()
    }
    
    /// Cancella un download ZIP in corso per un claim (se presente).
    /// Serve quando l'utente sceglie "Interrompi sincronizzazione".
    func cancelDownload(claimId: String) {
        activeDownloadsLock.lock()
        let snapshot = activeDownloads
        activeDownloadsLock.unlock()
        
        for (id, active) in snapshot {
            guard let url = active.delegate.task?.originalRequest?.url else { continue }
            if url.path.contains("/api/claims/\(claimId)/download") {
                active.delegate.task?.cancel()
                active.session.invalidateAndCancel()
                removeActiveDownload(id: id)
            }
        }
    }

    func uploadFiles(_ path: String, query: [URLQueryItem], files: [(URL, String)], progress: @escaping (Double) -> Void) async throws -> GenericAPIResponse {
        let boundary = UUID().uuidString
        var request = try await authorizedRequest(path: path, query: query)
        debugPrintRequest(request, label: "POST upload")
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 * 15 // 15 min (upload grandi)

        let bodyFileURL = try writeMultipartBodyToTempFile(files: files, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: bodyFileURL) }
        let delegate = UploadDelegate(onProgress: progress)
        let cfg = makeSessionConfiguration(timeoutRequest: 60 * 15, timeoutResource: 60 * 60)
        let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        let (data, response) = try await session.upload(for: request, fromFile: bodyFileURL)
        try validate(response: response, data: data)
        return try makeJSONDecoder().decode(GenericAPIResponse.self, from: data)
    }

    func uploadFiles(_ path: String, query: [URLQueryItem], filesData: [(Data, String)], progress: @escaping (Double) -> Void) async throws -> GenericAPIResponse {
        let boundary = UUID().uuidString
        var request = try await authorizedRequest(path: path, query: query)
        debugPrintRequest(request, label: "POST upload (Data)")
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 * 15

        let bodyFileURL = try writeMultipartBodyToTempFileFromData(files: filesData, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: bodyFileURL) }
        let delegate = UploadDelegate(onProgress: progress)
        let cfg = makeSessionConfiguration(timeoutRequest: 60 * 15, timeoutResource: 60 * 60)
        let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        let (data, response) = try await session.upload(for: request, fromFile: bodyFileURL)
        try validate(response: response, data: data)
        return try makeJSONDecoder().decode(GenericAPIResponse.self, from: data)
    }

    // MARK: - Helpers
    private func makeSessionConfiguration(timeoutRequest: TimeInterval, timeoutResource: TimeInterval) -> URLSessionConfiguration {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = timeoutRequest
        cfg.timeoutIntervalForResource = timeoutResource
        cfg.waitsForConnectivity = true
        cfg.allowsConstrainedNetworkAccess = true
        cfg.allowsExpensiveNetworkAccess = true
        // Bypass PAC/proxy: su alcune reti genera -1003 e poi -1001
        cfg.connectionProxyDictionary = [:]
        return cfg
    }

    private func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let str = try container.decode(String.self)

            // 1) RFC3339 con frazioni di secondo e timezone
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f1.date(from: str) { return date }

            // 2) RFC3339 senza frazioni
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            if let date = f2.date(from: str) { return date }

            // 3) Datetime naive (senza timezone): trattiamo come UTC
            // Formato: "2026-01-21T17:03:15" (senza Z, +, o offset timezone)
            // Controlla se ha T ma non ha timezone (Z, +HH:MM, o -HH:MM dopo l'ora)
            let hasT = str.contains("T")
            let hasZ = str.contains("Z")
            let hasTimezoneOffset = str.range(of: #"[+-]\d{2}:\d{2}"#, options: .regularExpression) != nil
            
            if hasT && !hasZ && !hasTimezoneOffset {
                // Prova con Z (UTC) usando ISO8601DateFormatter
                if let date = f1.date(from: str + "Z") { return date }
                if let date = f2.date(from: str + "Z") { return date }
                
                // Fallback: DateFormatter per formato "YYYY-MM-DDTHH:MM:SS" (senza timezone)
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                dateFormatter.timeZone = TimeZone(identifier: "UTC")
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                if let date = dateFormatter.date(from: str) {
                    return date
                }
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(str)"
            )
        }
        return decoder
    }

    // MARK: - URL building

    /// Build a URL by safely combining baseURL + path (which may include slashes) + query.
    /// Avoids `appendingPathComponent` because it percent-encodes embedded slashes and can break routes.
    private func buildURL(baseURL: URL, path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw SyncAgentError.invalidURL
        }

        let basePath = components.path
        let normalizedBasePath = (basePath == "/") ? "" : basePath
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        components.path = normalizedBasePath + normalizedPath

        if !query.isEmpty {
            components.queryItems = query
        }

        guard let url = components.url else {
            throw SyncAgentError.invalidURL
        }
        return url
    }

    private func debugPrintRequest(_ request: URLRequest, label: String) {
        // Logging disabilitato: lasciamo solo errori (vedi `validate` / catch).
    }
    
    // MARK: - Download Diagnostics & Integrity Helpers
    
    /// Log dettagliato per diagnostica download
    func logDownloadDiagnostics(
        url: URL,
        method: String,
        response: HTTPURLResponse?,
        bytesReceived: Int64,
        duration: TimeInterval,
        sha256: String? = nil
    ) {
        var logLines: [String] = []
        logLines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        logLines.append("📥 DOWNLOAD DIAGNOSTICS")
        logLines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        logLines.append("URL: \(url.absoluteString.replacingOccurrences(of: url.query ?? "", with: "[QUERY]"))")
        logLines.append("Method: \(method)")
        
        if let http = response {
            logLines.append("Status: \(http.statusCode)")
            logLines.append("Content-Type: \(http.value(forHTTPHeaderField: "Content-Type") ?? "N/A")")
            logLines.append("Content-Length: \(http.value(forHTTPHeaderField: "Content-Length") ?? "N/A")")
            logLines.append("Content-Range: \(http.value(forHTTPHeaderField: "Content-Range") ?? "N/A")")
            logLines.append("Accept-Ranges: \(http.value(forHTTPHeaderField: "Accept-Ranges") ?? "N/A")")
            logLines.append("ETag: \(http.value(forHTTPHeaderField: "ETag") ?? "N/A")")
            logLines.append("Cache-Control: \(http.value(forHTTPHeaderField: "Cache-Control") ?? "N/A")")
        } else {
            logLines.append("Status: N/A (non HTTP response)")
        }
        
        logLines.append("Bytes Received: \(bytesReceived)")
        logLines.append("Duration: \(String(format: "%.2f", duration))s")
        if let sha = sha256 {
            logLines.append("SHA256: \(sha)")
        }
        logLines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        print(logLines.joined(separator: "\n"))
    }
    
    /// Calcola SHA256 di un file
    func sha256Hash(fileURL: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? fileHandle.close() }
        
        var hasher = SHA256()
        let chunkSize = 1024 * 1024 // 1MB chunks
        
        while true {
            autoreleasepool {
                let data = fileHandle.readData(ofLength: chunkSize)
                if data.isEmpty { return }
                hasher.update(data: data)
            }
            if let data = try? fileHandle.readData(ofLength: chunkSize), data.isEmpty {
                break
            }
        }
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Calcola SHA256 di Data
    private func sha256Hash(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Scrittura atomica: scrive su temp e poi rename
    private func atomicWrite(data: Data, to finalURL: URL) throws {
        let tempURL = finalURL.appendingPathExtension(".partial")
        
        // Rimuovi temp esistente se presente
        try? FileManager.default.removeItem(at: tempURL)
        
        // Scrivi su temp
        try data.write(to: tempURL, options: .atomic)
        
        // Verifica che il file sia stato scritto correttamente
        let writtenSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
        guard writtenSize == Int64(data.count) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw NSError(domain: "SyncAgent", code: -1, userInfo: [NSLocalizedDescriptionKey: "Scrittura atomica fallita: size mismatch"])
        }
        
        // Rimuovi file finale se esiste
        try? FileManager.default.removeItem(at: finalURL)
        
        // Rename temp -> finale
        try FileManager.default.moveItem(at: tempURL, to: finalURL)
    }
    
    /// Scrittura atomica per file scaricato (da URL temporaneo)
    private func atomicMove(from tempURL: URL, to finalURL: URL, expectedSize: Int64?) throws {
        // Verifica size se atteso
        if let expected = expectedSize {
            let actualSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
            guard actualSize == expected else {
                try? FileManager.default.removeItem(at: tempURL)
                throw NSError(domain: "SyncAgent", code: -1, userInfo: [NSLocalizedDescriptionKey: "Size mismatch: atteso \(expected), ottenuto \(actualSize)"])
            }
        }
        
        // Rimuovi file finale se esiste
        try? FileManager.default.removeItem(at: finalURL)
        
        // Move temp -> finale
        try FileManager.default.moveItem(at: tempURL, to: finalURL)
    }

    private func validate(response: URLResponse?, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard 200..<300 ~= http.statusCode else {
            let message = String(data: data ?? Data(), encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw SyncAgentError.httpError(message)
        }
    }

    private func buildMultipartBody(files: [(URL, String)], boundary: String) throws -> Data {
        var body = Data()
        for (fileURL, filename) in files {
            let data = try Data(contentsOf: fileURL)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func writeMultipartBodyToTempFileFromData(files: [(Data, String)], boundary: String) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
        let url = tmp.appendingPathComponent("perx_upload_\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        let out = try FileHandle(forWritingTo: url)
        defer { try? out.close() }
        func writeString(_ s: String) { if let d = s.data(using: .utf8) { out.write(d) } }
        for (data, filename) in files {
            let safeFilename = filename.replacingOccurrences(of: "\"", with: "_")
            writeString("--\(boundary)\r\n")
            writeString("Content-Disposition: form-data; name=\"files\"; filename=\"\(safeFilename)\"\r\n")
            writeString("Content-Type: application/octet-stream\r\n\r\n")
            out.write(data)
            writeString("\r\n")
        }
        writeString("--\(boundary)--\r\n")
        return url
    }

    private func writeMultipartBodyToTempFile(files: [(URL, String)], boundary: String) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
        let url = tmp.appendingPathComponent("perx_upload_\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)

        let out = try FileHandle(forWritingTo: url)
        defer { try? out.close() }

        func writeString(_ s: String) {
            if let d = s.data(using: .utf8) { out.write(d) }
        }

        for (fileURL, filename) in files {
            let safeFilename = filename.replacingOccurrences(of: "\"", with: "_")
            writeString("--\(boundary)\r\n")
            writeString("Content-Disposition: form-data; name=\"files\"; filename=\"\(safeFilename)\"\r\n")
            writeString("Content-Type: application/octet-stream\r\n\r\n")

            let input = try FileHandle(forReadingFrom: fileURL)
            defer { try? input.close() }
            while true {
                let chunk = input.readData(ofLength: 1024 * 1024)
                if chunk.isEmpty { break }
                out.write(chunk)
            }
            writeString("\r\n")
        }
        writeString("--\(boundary)--\r\n")
        return url
    }
}

enum SyncAgentError: Error {
    case unreachable
    case invalidURL
    case httpError(String)
    case missingAPIKey
    case downloadFailed
    case unzipFailed
}

extension SyncAgentError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreachable:
            return "Sync Agent non configurato: URL remoto non valido."
        case .invalidURL:
            return "URL Sync Agent non valido."
        case .missingAPIKey:
            return "API Key mancante: inseriscila nelle Impostazioni → Sync Agent."
        case .httpError(let message):
            // Il server ci ritorna spesso un body utile (401/403/404/500…)
            return "Errore Sync Agent: \(message)"
        case .downloadFailed:
            return "Download fallito."
        case .unzipFailed:
            return "Estrazione ZIP fallita."
        }
    }
}

/// Delegate per download con callback di progresso E completamento
private final class DownloadDelegateWithCompletion: NSObject, URLSessionDownloadDelegate {
    /// Callback: (progress 0-1, bytesDownloaded, bytesTotal, bytesPerSecond)
    private let onProgress: (Double, Int64, Int64, Double) -> Void
    private let onComplete: (Result<URL, Error>) -> Void
    private let expectedTotalBytesHint: Int64?
    
    // Mantieni riferimento alla session per evitare deallocazione prematura
    var session: URLSession?
    var task: URLSessionDownloadTask?
    
    // Per calcolo velocità
    private var lastUpdateTime: Date?
    private var lastBytesWritten: Int64 = 0
    private var currentSpeed: Double = 0
    private var progressTimer: DispatchSourceTimer?
    private var lastPollTime: Date?
    private var lastPollBytes: Int64 = 0
    
    // Flag per evitare chiamate multiple a onComplete
    private var didComplete = false

    init(expectedTotalBytesHint: Int64?,
         onProgress: @escaping (Double, Int64, Int64, Double) -> Void,
         onComplete: @escaping (Result<URL, Error>) -> Void) {
        self.expectedTotalBytesHint = expectedTotalBytesHint
        self.onProgress = onProgress
        self.onComplete = onComplete
    }
    
    func startProgressPolling() {
        // Alcuni ambienti/proxy possono non invocare `didWriteData` in modo affidabile.
        // Questo polling usa i contatori del task e alimenta UI (bytes+speed) senza interrompere il download.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self, !self.didComplete, let task = self.task else { return }
            
            let received = task.countOfBytesReceived
            let expectedFromTask = task.countOfBytesExpectedToReceive
            let resolvedTotal: Int64 = {
                if expectedFromTask > 0 { return expectedFromTask }
                if let hint = self.expectedTotalBytesHint, hint > 0 { return hint }
                return 0
            }()
            
            // Velocità (media mobile)
            let now = Date()
            if let lastT = self.lastPollTime {
                let elapsed = now.timeIntervalSince(lastT)
                if elapsed > 0 {
                    let delta = received - self.lastPollBytes
                    let instantSpeed = Double(max(0, delta)) / elapsed
                    self.currentSpeed = self.currentSpeed * 0.7 + instantSpeed * 0.3
                }
            }
            self.lastPollTime = now
            self.lastPollBytes = received
            
            let progress: Double = {
                guard resolvedTotal > 0 else { return 0 }
                return min(1.0, Double(received) / Double(resolvedTotal))
            }()
            
            self.onProgress(progress, received, resolvedTotal, self.currentSpeed)
        }
        progressTimer = timer
        timer.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard !didComplete else { return }
        
        let startTime = Date()
        
        // Valida HTTP status: NON salvare se non è 200
        guard let http = downloadTask.response as? HTTPURLResponse else {
            didComplete = true
            onComplete(.failure(SyncAgentError.httpError("Risposta non HTTP")))
            session.finishTasksAndInvalidate()
            return
        }
        
        guard (200..<300).contains(http.statusCode) else {
            didComplete = true
            let statusCode = http.statusCode
            onComplete(.failure(SyncAgentError.httpError("HTTP \(statusCode)")))
            session.finishTasksAndInvalidate()
            return
        }
        
        didComplete = true
        
        // Verifica Content-Length se presente
        let actualSize = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int64) ?? 0
        if let contentLengthStr = http.value(forHTTPHeaderField: "Content-Length"),
           let expectedLength = Int64(contentLengthStr),
           expectedLength > 0 {
            if actualSize != expectedLength {
                print("[SyncAgent] ❌ Content-Length mismatch nel download: atteso \(expectedLength), scaricato \(actualSize)")
                onComplete(.failure(SyncAgentError.httpError("Content-Length mismatch: atteso \(expectedLength), scaricato \(actualSize)")))
                session.finishTasksAndInvalidate()
                return
            }
        }
        
        // Copia il file in una posizione temporanea persistente (scrittura atomica)
        // (il file in `location` viene eliminato dopo il return)
        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent(UUID().uuidString + ".zip")
        
        do {
            // Move atomico: location -> destURL
            try FileManager.default.moveItem(at: location, to: destURL)
            
            // Verifica che il file sia stato scritto correttamente
            let writtenSize = (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0
            guard writtenSize == actualSize else {
                try? FileManager.default.removeItem(at: destURL)
                onComplete(.failure(SyncAgentError.httpError("Scrittura fallita: size mismatch")))
                session.finishTasksAndInvalidate()
                return
            }
            
            // Log diagnostica
            let duration = Date().timeIntervalSince(startTime)
            let client = SyncAgentAPIClient.shared
            let sha256 = client.sha256Hash(fileURL: destURL)
            if let requestURL = downloadTask.originalRequest?.url {
                client.logDownloadDiagnostics(
                    url: requestURL,
                    method: "GET",
                    response: http,
                    bytesReceived: actualSize,
                    duration: duration,
                    sha256: sha256
                )
            }
            
            onComplete(.success(destURL))
        } catch {
            onComplete(.failure(error))
        }
        
        // Invalida la session
        progressTimer?.cancel()
        progressTimer = nil
        session.finishTasksAndInvalidate()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !didComplete, let error = error else { return }
        didComplete = true
        progressTimer?.cancel()
        progressTimer = nil
        onComplete(.failure(error))
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Alcuni server non inviano Content-Length (totalBytesExpectedToWrite = -1).
        // In quel caso usiamo l'hint (metadata.totalBytes) per calcolare il progresso.
        let resolvedTotal: Int64 = {
            if totalBytesExpectedToWrite > 0 { return totalBytesExpectedToWrite }
            if let hint = expectedTotalBytesHint, hint > 0 { return hint }
            return 0
        }()
        
        let progress: Double = {
            guard resolvedTotal > 0 else { return 0 }
            return min(1.0, Double(totalBytesWritten) / Double(resolvedTotal))
        }()
        
        // Calcola velocità di download
        let now = Date()
        if let lastTime = lastUpdateTime {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed > 0.25 { // Aggiorna velocità ogni 250ms (più stabile)
                let bytesInInterval = totalBytesWritten - lastBytesWritten
                let instantSpeed = Double(bytesInInterval) / elapsed
                // Smoothing della velocità (media mobile)
                currentSpeed = currentSpeed * 0.7 + instantSpeed * 0.3
                lastUpdateTime = now
                lastBytesWritten = totalBytesWritten
            }
        } else {
            lastUpdateTime = now
            lastBytesWritten = totalBytesWritten
        }
        
        // Già sul main thread (delegateQueue: .main)
        onProgress(progress, totalBytesWritten, resolvedTotal, currentSpeed)
    }
}

private final class UploadDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async { self.onProgress(progress) }
    }
}

