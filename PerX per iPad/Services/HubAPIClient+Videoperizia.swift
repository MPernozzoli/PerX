import Foundation

/// Conformità del client iPad al transport del Videoperizia service.
/// HubAPIClient lavora di default su `/api/v1/hub/...` (hub-compat); qui
/// usiamo path arbitrari `/api/v1/...` o `/portal/...`, quindi costruiamo
/// URL direttamente su `fixedCloudAPIBaseURL` senza il prefisso hub-compat.
extension HubAPIClient: VideoperiziaTransport {
    public func videoperiziaGet<T: Decodable>(_ path: String) async throws -> T {
        let url = try cloudURL(path)
        var request = authorizedCloudRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await cloudSession.data(for: request)
        try Self.validateCloudResponse(response)
        return try cloudDecoder.decode(T.self, from: data)
    }

    public func videoperiziaPostEmpty<T: Decodable>(_ path: String) async throws -> T {
        try await postJSON(path: path, body: Data("{}".utf8))
    }

    public func videoperiziaPost<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let encoded = try cloudEncoder.encode(body)
        return try await postJSON(path: path, body: encoded)
    }

    public func videoperiziaPostMultipart<T: Decodable>(
        _ path: String,
        fileData: Data,
        fileFieldName: String,
        fileName: String,
        mimeType: String,
        fields: [String: String]
    ) async throws -> T {
        let boundary = "perx-\(UUID().uuidString)"
        var body = Data()
        let crlf = "\r\n"
        for (key, value) in fields {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\(crlf)\(crlf)".data(using: .utf8)!)
            body.append("\(value)\(crlf)".data(using: .utf8)!)
        }
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(fileData)
        body.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)

        let url = try cloudURL(path)
        var request = authorizedCloudRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let (data, response) = try await cloudSession.upload(for: request, from: body)
        try Self.validateCloudResponse(response)
        return try cloudDecoder.decode(T.self, from: data)
    }

    // MARK: - Helpers privati al modulo

    private func postJSON<T: Decodable>(path: String, body: Data) async throws -> T {
        let url = try cloudURL(path)
        var request = authorizedCloudRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        let (data, response) = try await cloudSession.data(for: request)
        try Self.validateCloudResponse(response)
        return try cloudDecoder.decode(T.self, from: data)
    }

    private static func validateCloudResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw HubAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            switch http.statusCode {
            case 401: throw HubAPIError.unauthorized
            case 404: throw HubAPIError.notFound
            case 400: throw HubAPIError.badRequest
            case 500...599: throw HubAPIError.serverError(http.statusCode)
            default:  throw HubAPIError.httpError(http.statusCode)
            }
        }
    }
}
