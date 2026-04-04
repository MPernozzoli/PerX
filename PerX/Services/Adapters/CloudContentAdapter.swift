import Foundation

@MainActor
final class CloudContentAdapter: ObservableObject {
    static let shared = CloudContentAdapter()

    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let client = HubAPIAdapterClient.shared

    private init() {}

    var isConfigured: Bool { client.isCloudConfigured }

    func getDiaryEntries(sinistroRef: String) async throws -> [CloudDiaryEntryResponse] {
        isLoading = true
        defer { isLoading = false }
        let response: CloudDiaryEntryListResponse = try await client.cloudGet("/claims/\(sinistroRef)/diary")
        return response.items
    }

    func createDiaryNote(sinistroRef: String, title: String?, body: String, happenedAt: Date? = nil) async throws -> CloudDiaryEntryResponse {
        isLoading = true
        defer { isLoading = false }
        let request = CloudDiaryEntryCreateRequest(
            entry_type: "note",
            title: title,
            body_text: body,
            visibility: "internal",
            happened_at: happenedAt,
            metadata_json: nil
        )
        return try await client.cloudPost("/claims/\(sinistroRef)/diary", body: request)
    }

    func getEmails(sinistroRef: String) async throws -> [CloudEmailResponse] {
        isLoading = true
        defer { isLoading = false }
        let response: CloudEmailListResponse = try await client.cloudGet("/emails?claim_id=\(sinistroRef)")
        return response.items
    }

    func getFolders(sinistroRef: String) async throws -> [CloudFolderResponse] {
        isLoading = true
        defer { isLoading = false }
        let response: CloudFolderListResponse = try await client.cloudGet("/claims/\(sinistroRef)/folders")
        return response.items
    }

    func createFolder(sinistroRef: String, name: String, parentId: String? = nil, path: String? = nil) async throws -> CloudFolderResponse {
        isLoading = true
        defer { isLoading = false }
        let request = CloudFolderCreateRequest(
            name: name,
            parent_id: parentId,
            folder_type: "generic",
            path: path,
            source: "hub",
            external_ref: nil
        )
        return try await client.cloudPost("/claims/\(sinistroRef)/folders", body: request)
    }

    func getDocuments(sinistroRef: String) async throws -> [CloudDocumentResponse] {
        isLoading = true
        defer { isLoading = false }
        let response: CloudDocumentListResponse = try await client.cloudGet("/documents?claim_id=\(sinistroRef)")
        return response.items
    }

    func registerDocument(
        sinistroRef: String,
        folderId: String?,
        fileName: String,
        storagePath: String,
        sizeBytes: Int,
        mimeType: String? = nil
    ) async throws -> CloudDocumentResponse {
        isLoading = true
        defer { isLoading = false }
        let request = CloudDocumentCreateRequest(
            claim_id: sinistroRef,
            folder_id: folderId,
            attachment_id: nil,
            source_type: "hub",
            source_id: nil,
            file_name: fileName,
            original_file_name: nil,
            mime_type: mimeType,
            extension: nil,
            size_bytes: sizeBytes,
            storage_provider: "hub",
            storage_bucket: nil,
            storage_path: storagePath,
            logical_path: nil,
            checksum_sha256: nil,
            checksum_md5: nil,
            version_no: 1,
            status: "active",
            category: nil,
            tags_json: []
        )
        return try await client.cloudPost("/documents", body: request)
    }
}
