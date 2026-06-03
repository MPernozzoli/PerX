import Foundation

enum AvailabilityStatus: String, Codable, CaseIterable, Identifiable {
    case available
    case busy
    case away
    case offline
    case doNotDisturb = "do_not_disturb"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .available: return "Disponibile"
        case .busy: return "Occupato"
        case .away: return "Assente"
        case .offline: return "Offline"
        case .doNotDisturb: return "Non disturbare"
        }
    }
}

enum CommunicationStatus: String, Codable, CaseIterable, Identifiable {
    case idle
    case ringing
    case inCall = "in_call"
    case onHold = "on_hold"
    case unavailable

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .idle: return "Libero"
        case .ringing: return "Squilla"
        case .inCall: return "In chiamata"
        case .onHold: return "In attesa"
        case .unavailable: return "Non disponibile"
        }
    }
}

enum CommunicationDestinationType: String, Codable, CaseIterable {
    case externalPhone = "external_phone"
    case internalUser = "internal_user"
    case internalExtension = "internal_extension"
    case internalTeam = "internal_team"
    case queue
    case livekitRoom = "livekit_room"
    case externalGuestLink = "external_guest_link"
    case crossTenantPerX = "cross_tenant_perx"
}

enum CommunicationTransport: String, Codable, CaseIterable {
    case telecomProvider = "telecom_provider"
    case livekit
    case routingEngine = "routing_engine"
}

enum CommunicationCallDirection: String, Codable, CaseIterable {
    case inbound
    case outbound
    case missed
}

enum CommunicationCallState: String, Codable, CaseIterable {
    case pending
    case ringing
    case active
    case onHold = "on_hold"
    case transferred
    case completed
    case missed
    case failed
    case needsTriage = "needs_triage"
    case scheduled
    case expired
    case cancelled
}

struct CommunicationContext: Codable, Hashable {
    var tenantId: String
    var claimId: String?
    var claimReference: String?
    var source: String?
    var scheduledCommunicationId: String?

    enum CodingKeys: String, CodingKey {
        case tenantId = "tenant_id"
        case claimId = "claim_id"
        case claimReference = "claim_reference"
        case source
        case scheduledCommunicationId = "scheduled_communication_id"
    }
}

struct CommunicationDestination: Codable, Identifiable, Hashable {
    var id: String { targetId ?? displayName }
    var destinationType: CommunicationDestinationType
    var transport: CommunicationTransport
    var targetId: String?
    var displayName: String
    var tenantId: String
    var suggestedCallerId: String?
    var contextClaimId: String?
    var rawValue: String

    enum CodingKeys: String, CodingKey {
        case destinationType = "destination_type"
        case transport
        case targetId = "target_id"
        case displayName = "display_name"
        case tenantId = "tenant_id"
        case suggestedCallerId = "suggested_caller_id"
        case contextClaimId = "context_claim_id"
        case rawValue = "raw_value"
    }

    var transportLabel: String {
        switch transport {
        case .telecomProvider: return "Provider telefonico"
        case .livekit: return "PerX interno"
        case .routingEngine: return "Routing PerX"
        }
    }
}

struct CommunicationResolution: Codable, Hashable {
    var selected: CommunicationDestination?
    var candidates: [CommunicationDestination]
    var isAmbiguous: Bool
}

struct CommunicationCallLogItem: Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var subtitle: String
    var direction: CommunicationCallDirection
    var state: CommunicationCallState
    var startedAt: Date
    var durationSeconds: Int?
    var destination: CommunicationDestination
    var claimReference: String?
    var claimId: String?
    var claimContext: CommunicationClaimContext?
    var callerContext: CommunicationCallerContext?

    init(
        id: UUID = UUID(),
        displayName: String,
        subtitle: String,
        direction: CommunicationCallDirection,
        state: CommunicationCallState,
        startedAt: Date,
        durationSeconds: Int? = nil,
        destination: CommunicationDestination,
        claimReference: String? = nil,
        claimId: String? = nil,
        claimContext: CommunicationClaimContext? = nil,
        callerContext: CommunicationCallerContext? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
        self.direction = direction
        self.state = state
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.destination = destination
        self.claimReference = claimReference
        self.claimId = claimId
        self.claimContext = claimContext
        self.callerContext = callerContext
    }

    var effectiveClaimId: String? {
        claimContext?.claimId ?? callerContext?.claimContext?.claimId ?? claimId
    }

    var effectiveClaimContext: CommunicationClaimContext? {
        claimContext ?? callerContext?.claimContext
    }
}

struct CommunicationContactSuggestion: Identifiable, Hashable {
    let id: String
    var displayName: String
    var detail: String
    var rawDestination: String
    var destinationTypeHint: CommunicationDestinationType?
    var claimReference: String?
}

struct CommunicationLiveKitToken: Codable, Hashable {
    let token: String
    let livekitUrl: String
    let roomName: String
    let identity: String
    let expiresAt: Date
    let canPublish: Bool
    let canSubscribe: Bool
    let sessionId: String
    let callId: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case token
        case livekitUrl = "livekit_url"
        case roomName = "room_name"
        case identity
        case expiresAt = "expires_at"
        case canPublish = "can_publish"
        case canSubscribe = "can_subscribe"
        case sessionId = "session_id"
        case callId = "call_id"
        case displayName = "display_name"
    }
}

struct CommunicationClaimContext: Codable, Hashable {
    let claimId: String
    let claimReference: String?
    let claimNumber: String?
    let claimStatus: String?
    let insuredName: String?

    enum CodingKeys: String, CodingKey {
        case claimId = "claim_id"
        case claimReference = "claim_reference"
        case claimNumber = "claim_number"
        case claimStatus = "claim_status"
        case insuredName = "insured_name"
    }

    var displayReference: String {
        claimNumber ?? claimReference ?? claimId
    }
}

struct CommunicationCallerContext: Codable, Hashable {
    let displayName: String
    let source: String
    let contactType: String?
    let phoneNumber: String?
    let claimContext: CommunicationClaimContext?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case source
        case contactType = "contact_type"
        case phoneNumber = "phone_number"
        case claimContext = "claim_context"
    }
}

enum CommunicationNotificationActionType: String, Codable, CaseIterable {
    case answer
    case answerAndOpenClaim = "answer_and_open_claim"
    case openClaimOnly = "open_claim_only"
    case sendToVoicemailAITriage = "send_to_voicemail_ai_triage"
}

struct CommunicationNotificationAction: Codable, Hashable {
    let actionType: CommunicationNotificationActionType
    let title: String
    let emphasized: Bool
    let requiresClaim: Bool

    enum CodingKeys: String, CodingKey {
        case actionType = "action_type"
        case title
        case emphasized
        case requiresClaim = "requires_claim"
    }
}

extension CommunicationLiveKitToken: Identifiable {
    var id: String { "\(sessionId):\(identity)" }
}

struct CommunicationStartRequest: Codable {
    let destination: CommunicationDestination
    let context: CommunicationContext
}

struct CommunicationStartResponse: Codable {
    let sessionId: String
    let callId: String
    let state: String
    let destination: CommunicationDestination
    let createdAt: Date
    let livekitToken: CommunicationLiveKitToken?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case callId = "call_id"
        case state
        case destination
        case createdAt = "created_at"
        case livekitToken = "livekit_token"
    }
}

struct CommunicationSessionActionRequest: Codable {
    let actionType: CommunicationNotificationActionType

    enum CodingKeys: String, CodingKey {
        case actionType = "action_type"
    }
}

struct CommunicationSessionActionResponse: Codable {
    let sessionId: String
    let callId: String?
    let actionType: CommunicationNotificationActionType
    let state: String
    let claimId: String?
    let openClaim: Bool
    let livekitToken: CommunicationLiveKitToken?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case callId = "call_id"
        case actionType = "action_type"
        case state
        case claimId = "claim_id"
        case openClaim = "open_claim"
        case livekitToken = "livekit_token"
    }
}
