import Foundation

public struct AssignmentPlannerSettingsDTO: Codable, Sendable {
    public let tenantSlug: String
    public let planningHorizonDays: Int
    public let defaultMonthlyTarget: Int
    public let maxLoadRatioPerExpert: Double
    public let rebalancePriorityMargin: Double
    public let workingPenalty: Double
    public let offlinePenalty: Double
    public let enabled: Bool

    public init(
        tenantSlug: String,
        planningHorizonDays: Int = 3,
        defaultMonthlyTarget: Int = 80,
        maxLoadRatioPerExpert: Double = 1.15,
        rebalancePriorityMargin: Double = 0.12,
        workingPenalty: Double = 0.35,
        offlinePenalty: Double = 0.25,
        enabled: Bool = true
    ) {
        self.tenantSlug = tenantSlug
        self.planningHorizonDays = planningHorizonDays
        self.defaultMonthlyTarget = defaultMonthlyTarget
        self.maxLoadRatioPerExpert = maxLoadRatioPerExpert
        self.rebalancePriorityMargin = rebalancePriorityMargin
        self.workingPenalty = workingPenalty
        self.offlinePenalty = offlinePenalty
        self.enabled = enabled
    }
}

public struct AssignmentMemberSettingsDTO: Codable, Sendable, Identifiable {
    public var id: String { email }
    public let tenantSlug: String
    public let email: String
    public let displayName: String
    public let assignedCompanies: [String]
    public let roleOverrides: [String]
    public let monthlyClaimTarget: Int
    public let maxAuthority: Double
    public let preferredAgencyCodes: [String]
    public let preferredPolicyNumbers: [String]
    public let preferredInsureds: [String]
    public let preferredGuarantees: [String]
    public let isActive: Bool

    public init(
        tenantSlug: String,
        email: String,
        displayName: String,
        assignedCompanies: [String] = [],
        roleOverrides: [String] = [],
        monthlyClaimTarget: Int = 0,
        maxAuthority: Double = 0,
        preferredAgencyCodes: [String] = [],
        preferredPolicyNumbers: [String] = [],
        preferredInsureds: [String] = [],
        preferredGuarantees: [String] = ["Fenomeno Elettrico"],
        isActive: Bool = true
    ) {
        self.tenantSlug = tenantSlug
        self.email = email
        self.displayName = displayName
        self.assignedCompanies = assignedCompanies
        self.roleOverrides = roleOverrides
        self.monthlyClaimTarget = monthlyClaimTarget
        self.maxAuthority = maxAuthority
        self.preferredAgencyCodes = preferredAgencyCodes
        self.preferredPolicyNumbers = preferredPolicyNumbers
        self.preferredInsureds = preferredInsureds
        self.preferredGuarantees = preferredGuarantees
        self.isActive = isActive
    }
}

public struct AssignmentPlanEntryDTO: Codable, Sendable, Identifiable {
    public var id: String { claimReference }
    public let tenantSlug: String
    public let claimReference: String
    public let company: String
    public let assigneeEmail: String
    public let assigneeName: String
    public let plannedDayOffset: Int
    public let priority: Double
    public let complexityWeight: Double
    public let previousAssigneeEmail: String?

    public init(
        tenantSlug: String,
        claimReference: String,
        company: String,
        assigneeEmail: String,
        assigneeName: String,
        plannedDayOffset: Int,
        priority: Double,
        complexityWeight: Double,
        previousAssigneeEmail: String? = nil
    ) {
        self.tenantSlug = tenantSlug
        self.claimReference = claimReference
        self.company = company
        self.assigneeEmail = assigneeEmail
        self.assigneeName = assigneeName
        self.plannedDayOffset = plannedDayOffset
        self.priority = priority
        self.complexityWeight = complexityWeight
        self.previousAssigneeEmail = previousAssigneeEmail
    }
}

public struct AssignmentPlanDTO: Codable, Sendable {
    public let tenantSlug: String
    public let generatedAt: Date
    public let assignments: [AssignmentPlanEntryDTO]
    public let unassignedClaimReferences: [String]

    public init(
        tenantSlug: String,
        generatedAt: Date = Date(),
        assignments: [AssignmentPlanEntryDTO],
        unassignedClaimReferences: [String]
    ) {
        self.tenantSlug = tenantSlug
        self.generatedAt = generatedAt
        self.assignments = assignments
        self.unassignedClaimReferences = unassignedClaimReferences
    }
}

public struct AssignmentPlanRecomputeRequest: Codable, Sendable {
    public let reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }
}
