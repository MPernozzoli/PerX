import Foundation

protocol CommunicationDestinationResolving {
    func resolve(destination rawDestination: String, context: CommunicationContext) -> CommunicationResolution
}

struct CommunicationDirectoryUser: Hashable {
    var id: String
    var tenantId: String
    var displayName: String
    var extensionNumber: String?
    var extensionEnabled: Bool
    var availabilityStatus: AvailabilityStatus
    var communicationStatus: CommunicationStatus
}

struct CommunicationDestinationResolver: CommunicationDestinationResolving {
    var users: [CommunicationDirectoryUser]
    var teamDestinations: [CommunicationContactSuggestion]
    var queueDestinations: [CommunicationContactSuggestion]

    init(
        users: [CommunicationDirectoryUser] = CommunicationDestinationResolver.seedUsers,
        teamDestinations: [CommunicationContactSuggestion] = CommunicationDestinationResolver.seedTeams,
        queueDestinations: [CommunicationContactSuggestion] = CommunicationDestinationResolver.seedQueues
    ) {
        self.users = users
        self.teamDestinations = teamDestinations
        self.queueDestinations = queueDestinations
    }

    func resolve(destination rawDestination: String, context: CommunicationContext) -> CommunicationResolution {
        let trimmed = rawDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CommunicationResolution(selected: nil, candidates: [], isAmbiguous: false)
        }

        var candidates: [CommunicationDestination] = []

        if trimmed.isThreeDigitExtension,
           let user = users.first(where: { $0.tenantId == context.tenantId && $0.extensionEnabled && $0.extensionNumber == trimmed }) {
            candidates.append(destination(
                type: .internalExtension,
                transport: .livekit,
                targetId: user.id,
                displayName: "\(user.displayName) - interno \(trimmed)",
                rawValue: trimmed,
                context: context
            ))
        }

        let matchingUsers = users.filter {
            $0.tenantId == context.tenantId &&
            ($0.displayName.localizedCaseInsensitiveContains(trimmed) || $0.id.localizedCaseInsensitiveContains(trimmed))
        }
        candidates.append(contentsOf: matchingUsers.map { user in
            destination(
                type: .internalUser,
                transport: .livekit,
                targetId: user.id,
                displayName: user.displayName,
                rawValue: trimmed,
                context: context
            )
        })

        candidates.append(contentsOf: teamDestinations.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed) || $0.rawDestination.localizedCaseInsensitiveContains(trimmed)
        }.map {
            destination(type: .internalTeam, transport: .routingEngine, targetId: $0.id, displayName: $0.displayName, rawValue: trimmed, context: context)
        })

        candidates.append(contentsOf: queueDestinations.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed) || $0.rawDestination.localizedCaseInsensitiveContains(trimmed)
        }.map {
            destination(type: .queue, transport: .routingEngine, targetId: $0.id, displayName: $0.displayName, rawValue: trimmed, context: context)
        })

        if trimmed.looksLikeInviteLink {
            candidates.append(destination(
                type: .externalGuestLink,
                transport: .livekit,
                targetId: trimmed,
                displayName: "Ospite esterno via link",
                rawValue: trimmed,
                context: context
            ))
        }

        if trimmed.looksLikePhoneNumber {
            candidates.append(destination(
                type: .externalPhone,
                transport: .telecomProvider,
                targetId: trimmed,
                displayName: trimmed,
                rawValue: trimmed,
                context: context
            ))
        }

        var seen: Set<CommunicationDestination> = []
        var uniqueCandidates: [CommunicationDestination] = []
        for candidate in candidates where !seen.contains(candidate) {
            seen.insert(candidate)
            uniqueCandidates.append(candidate)
        }
        return CommunicationResolution(
            selected: uniqueCandidates.count == 1 ? uniqueCandidates.first : nil,
            candidates: uniqueCandidates,
            isAmbiguous: uniqueCandidates.count > 1
        )
    }

    private func destination(
        type: CommunicationDestinationType,
        transport: CommunicationTransport,
        targetId: String?,
        displayName: String,
        rawValue: String,
        context: CommunicationContext
    ) -> CommunicationDestination {
        CommunicationDestination(
            destinationType: type,
            transport: transport,
            targetId: targetId,
            displayName: displayName,
            tenantId: context.tenantId,
            suggestedCallerId: nil,
            contextClaimId: context.claimId,
            rawValue: rawValue
        )
    }
}

private extension CommunicationDestinationResolver {
    static let seedUsers: [CommunicationDirectoryUser] = [
        CommunicationDirectoryUser(id: "user-massimo", tenantId: "default", displayName: "Massimo", extensionNumber: "101", extensionEnabled: true, availabilityStatus: .available, communicationStatus: .idle),
        CommunicationDirectoryUser(id: "user-sami", tenantId: "default", displayName: "Sami", extensionNumber: "102", extensionEnabled: true, availabilityStatus: .available, communicationStatus: .idle),
        CommunicationDirectoryUser(id: "user-segreteria", tenantId: "default", displayName: "Segreteria", extensionNumber: "103", extensionEnabled: true, availabilityStatus: .busy, communicationStatus: .inCall)
    ]

    static let seedTeams: [CommunicationContactSuggestion] = [
        CommunicationContactSuggestion(id: "team-periti", displayName: "Team periti", detail: "Routing interno PerX", rawDestination: "team:periti", destinationTypeHint: .internalTeam),
        CommunicationContactSuggestion(id: "team-segreteria", displayName: "Segreteria", detail: "Routing interno PerX", rawDestination: "team:segreteria", destinationTypeHint: .internalTeam)
    ]

    static let seedQueues: [CommunicationContactSuggestion] = [
        CommunicationContactSuggestion(id: "queue-triage", displayName: "Coda triage sinistri", detail: "Prima disponibilita'", rawDestination: "queue:triage", destinationTypeHint: .queue)
    ]
}

private extension String {
    var isThreeDigitExtension: Bool {
        range(of: #"^\d{3}$"#, options: .regularExpression) != nil
    }

    var looksLikePhoneNumber: Bool {
        let compact = replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        return compact.range(of: #"^\+?[0-9]{6,15}$"#, options: .regularExpression) != nil
    }

    var looksLikeInviteLink: Bool {
        localizedCaseInsensitiveContains("/guest/") ||
        localizedCaseInsensitiveContains("invite") ||
        localizedCaseInsensitiveContains("livekit")
    }
}

final class CommunicationStartService {
    static let shared = CommunicationStartService()

    private var transport: CommunicationHTTPTransport?

    private init() {}

    static func configure(transport: CommunicationHTTPTransport) {
        shared.transport = transport
    }

    func startCommunication(destination: CommunicationDestination, context: CommunicationContext) async throws -> (CommunicationCallLogItem, CommunicationStartResponse?) {
        let response: CommunicationStartResponse? = try await transport?.communicationPost(
            "/api/v1/communications/start",
            body: CommunicationStartRequest(destination: destination, context: context)
        )
        let call = CommunicationCallLogItem(
            displayName: destination.displayName,
            subtitle: destination.transportLabel,
            direction: .outbound,
            state: .active,
            startedAt: Date(),
            durationSeconds: nil,
            destination: destination,
            claimReference: context.claimReference,
            claimId: context.claimId
        )
        return (call, response)
    }

    func fetchIncomingCalls() async throws -> CommunicationIncomingCallListResponse {
        try await transport?.communicationGet("/api/v1/communications/incoming")
            ?? CommunicationIncomingCallListResponse(items: [])
    }

    func performNotificationAction(
        sessionId: String,
        actionType: CommunicationNotificationActionType
    ) async throws -> CommunicationSessionActionResponse? {
        try await transport?.communicationPost(
            "/api/v1/communications/sessions/\(sessionId)/actions",
            body: CommunicationSessionActionRequest(actionType: actionType)
        )
    }
}

@MainActor
protocol CommunicationHTTPTransport: Sendable {
    func communicationPost<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T
    func communicationGet<T: Decodable>(_ path: String) async throws -> T
}
