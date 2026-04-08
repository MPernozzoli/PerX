import Foundation

struct AssignmentPlannerSettingsDTO: Codable {
    let tenantSlug: String
    let planningHorizonDays: Int
    let defaultMonthlyTarget: Int
    let maxLoadRatioPerExpert: Double
    let rebalancePriorityMargin: Double
    let workingPenalty: Double
    let offlinePenalty: Double
    let enabled: Bool
}

struct AssignmentMemberSettingsDTO: Codable, Identifiable {
    var id: String { email }
    let tenantSlug: String
    let email: String
    let displayName: String
    let assignedCompanies: [String]
    let roleOverrides: [String]
    let monthlyClaimTarget: Int
    let maxAuthority: Double
    let preferredAgencyCodes: [String]
    let preferredPolicyNumbers: [String]
    let preferredInsureds: [String]
    let preferredGuarantees: [String]
    let isActive: Bool
}

struct AssignmentPlanEntryDTO: Codable, Identifiable {
    var id: String { claimReference }
    let tenantSlug: String
    let claimReference: String
    let company: String
    let assigneeEmail: String
    let assigneeName: String
    let plannedDayOffset: Int
    let priority: Double
    let complexityWeight: Double
    let previousAssigneeEmail: String?
}

struct AssignmentPlanDTO: Codable {
    let tenantSlug: String
    let generatedAt: Date
    let assignments: [AssignmentPlanEntryDTO]
    let unassignedClaimReferences: [String]
}

struct AssignmentPlanRecomputeRequest: Codable {
    let reason: String?
}
