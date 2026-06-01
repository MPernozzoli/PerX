import Foundation

/// Conformità del client cloud macOS al transport del Videoperizia service.
/// Le 4 funzioni mappano 1:1 sui metodi esistenti `cloudGet/cloudPost/...`.
/// Body vuoto Codable per POST che non hanno payload.
private struct VideoperiziaEmptyBody: Encodable {}

extension HubAPIAdapterClient: VideoperiziaTransport {
    public func videoperiziaGet<T: Decodable>(_ path: String) async throws -> T {
        try await cloudGet(path)
    }

    public func videoperiziaPostEmpty<T: Decodable>(_ path: String) async throws -> T {
        return try await cloudPost(path, body: VideoperiziaEmptyBody())
    }

    public func videoperiziaPost<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await cloudPost(path, body: body)
    }

    public func videoperiziaPostMultipart<T: Decodable>(
        _ path: String,
        fileData: Data,
        fileFieldName: String,
        fileName: String,
        mimeType: String,
        fields: [String: String]
    ) async throws -> T {
        try await cloudPostMultipart(
            path,
            fileData: fileData,
            fileFieldName: fileFieldName,
            fileName: fileName,
            mimeType: mimeType,
            fields: fields
        )
    }
}
