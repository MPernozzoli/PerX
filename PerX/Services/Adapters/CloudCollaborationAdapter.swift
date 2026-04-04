import Foundation

@MainActor
final class CloudCollaborationAdapter: ObservableObject {
    static let shared = CloudCollaborationAdapter()

    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let client = HubAPIAdapterClient.shared

    private init() {}

    var isConfigured: Bool { client.isCloudConfigured }

    func getInternalThreads(sinistroRef: String? = nil) async throws -> [CloudInternalChatThreadResponse] {
        isLoading = true
        defer { isLoading = false }
        let path = sinistroRef.map { "/internal-chat/threads?claim_id=\($0)" } ?? "/internal-chat/threads"
        let response: CloudInternalChatThreadListResponse = try await client.cloudGet(path)
        return response.items
    }

    func createInternalThread(sinistroRef: String?, title: String, memberUserIds: [String] = []) async throws -> CloudInternalChatThreadResponse {
        isLoading = true
        defer { isLoading = false }
        let request = CloudInternalChatThreadCreateRequest(claim_id: sinistroRef, title: title, thread_type: "claim", member_user_ids: memberUserIds)
        return try await client.cloudPost("/internal-chat/threads", body: request)
    }

    func getInternalMessages(threadId: String) async throws -> [CloudInternalChatMessageResponse] {
        isLoading = true
        defer { isLoading = false }
        let response: CloudInternalChatMessageListResponse = try await client.cloudGet("/internal-chat/threads/\(threadId)/messages")
        return response.items
    }

    func sendInternalMessage(threadId: String, body: String) async throws -> CloudInternalChatMessageResponse {
        isLoading = true
        defer { isLoading = false }
        let request = CloudInternalChatMessageCreateRequest(body_text: body, message_type: "text", attachment_document_id: nil)
        return try await client.cloudPost("/internal-chat/threads/\(threadId)/messages", body: request)
    }

    func getAISessions(sinistroRef: String? = nil) async throws -> [CloudAIChatSessionResponse] {
        isLoading = true
        defer { isLoading = false }
        let path = sinistroRef.map { "/ai-chat/sessions?claim_id=\($0)" } ?? "/ai-chat/sessions"
        let response: CloudAIChatSessionListResponse = try await client.cloudGet(path)
        return response.items
    }

    func createAISession(sinistroRef: String?, title: String, model: String? = nil) async throws -> CloudAIChatSessionResponse {
        isLoading = true
        defer { isLoading = false }
        let request = CloudAIChatSessionCreateRequest(claim_id: sinistroRef, title: title, model: model)
        return try await client.cloudPost("/ai-chat/sessions", body: request)
    }

    func getAIMessages(sessionId: String) async throws -> [CloudAIChatMessageResponse] {
        isLoading = true
        defer { isLoading = false }
        let response: CloudAIChatMessageListResponse = try await client.cloudGet("/ai-chat/sessions/\(sessionId)/messages")
        return response.items
    }

    func sendAIMessage(sessionId: String, role: String, body: String) async throws -> CloudAIChatMessageResponse {
        isLoading = true
        defer { isLoading = false }
        let request = CloudAIChatMessageCreateRequest(role: role, body_text: body)
        return try await client.cloudPost("/ai-chat/sessions/\(sessionId)/messages", body: request)
    }

    func getCalendarEvents(sinistroRef: String? = nil) async throws -> [CloudCalendarEventResponse] {
        isLoading = true
        defer { isLoading = false }
        let path = sinistroRef.map { "/calendar-events?claim_id=\($0)" } ?? "/calendar-events"
        let response: CloudCalendarEventListResponse = try await client.cloudGet(path)
        return response.items
    }

    func createCalendarEvent(
        sinistroRef: String?,
        title: String,
        startsAt: Date,
        endsAt: Date,
        location: String? = nil
    ) async throws -> CloudCalendarEventResponse {
        isLoading = true
        defer { isLoading = false }
        let request = CloudCalendarEventCreateRequest(
            claim_id: sinistroRef,
            task_id: nil,
            owner_user_id: nil,
            title: title,
            description: nil,
            event_type: "appointment",
            starts_at: startsAt,
            ends_at: endsAt,
            all_day: false,
            location: location,
            status: "confirmed",
            visibility: "tenant",
            source: "manual"
        )
        return try await client.cloudPost("/calendar-events", body: request)
    }

    func getDashboardWidgets() async throws -> [CloudDashboardWidgetResponse] {
        isLoading = true
        defer { isLoading = false }
        let response: CloudDashboardWidgetListResponse = try await client.cloudGet("/dashboard/widgets")
        return response.items
    }

    func saveDashboardWidget(widgetKey: String, position: Int, enabled: Bool, settings: [String: String]? = nil) async throws -> CloudDashboardWidgetResponse {
        isLoading = true
        defer { isLoading = false }
        let request = CloudDashboardWidgetUpsertRequest(widget_key: widgetKey, position: position, enabled: enabled, settings_json: settings)
        return try await client.cloudPut("/dashboard/widgets/\(widgetKey)", body: request)
    }
}
