import Foundation
import SQLite
import PerXCore

public actor AssignmentPlannerService {
    public static let shared = AssignmentPlannerService()

    private init() {}

    private let readyStates: Set<String> = [
        "In attesa assegnazione",
        "Sopralluogo assegnato",
        "Videoperizia da eseguire",
        "Da gestire (video)",
        "Da gestire (tradizionale)",
        "Da gestire (documentale)",
        "Da gestire (no residui)"
    ]

    public func getSettings(tenantSlug: String) async throws -> AssignmentPlannerSettingsDTO {
        try await DatabaseManager.shared.getPlannerSettings(tenantSlug: tenantSlug)
            ?? AssignmentPlannerSettingsDTO(tenantSlug: tenantSlug)
    }

    public func updateSettings(_ settings: AssignmentPlannerSettingsDTO) async throws -> AssignmentPlannerSettingsDTO {
        try await DatabaseManager.shared.savePlannerSettings(settings)
        return settings
    }

    public func listMembers(tenantSlug: String) async throws -> [AssignmentMemberSettingsDTO] {
        try await DatabaseManager.shared.listPlannerMemberSettings(tenantSlug: tenantSlug)
    }

    public func upsertMember(_ member: AssignmentMemberSettingsDTO) async throws -> AssignmentMemberSettingsDTO {
        try await DatabaseManager.shared.savePlannerMemberSetting(member)
        return member
    }

    public func currentPlan(tenantSlug: String) async throws -> AssignmentPlanDTO? {
        try await DatabaseManager.shared.getPlannerPlan(tenantSlug: tenantSlug)
    }

    public func recomputePlan(tenantSlug: String, reason: String?) async throws -> AssignmentPlanDTO {
        let settings = try await getSettings(tenantSlug: tenantSlug)
        let members = try await listMembers(tenantSlug: tenantSlug).filter(\.isActive)
        let claims = try await fetchCandidateClaims(tenantSlug: tenantSlug)

        let assignments = buildAssignments(
            tenantSlug: tenantSlug,
            claims: claims,
            members: members,
            settings: settings
        )
        let assignedRefs = Set(assignments.map(\.claimReference))
        let unassigned = claims.map(\.reference).filter { !assignedRefs.contains($0) }.sorted()

        let plan = AssignmentPlanDTO(
            tenantSlug: tenantSlug,
            generatedAt: Date(),
            assignments: assignments,
            unassignedClaimReferences: unassigned
        )
        try await DatabaseManager.shared.replacePlannerAssignments(plan)
        return plan
    }

    private func fetchCandidateClaims(tenantSlug: String) async throws -> [CandidateClaim] {
        let db = try await DatabaseManager.shared.db()
        let query = DatabaseSchema.sinistri
            .filter(DatabaseSchema.SinistriColumns.tenantSlug == tenantSlug)
            .order(DatabaseSchema.SinistriColumns.dataIncarico.desc)

        return try db.prepare(query).compactMap { row in
            let state = row[DatabaseSchema.SinistriColumns.stato]
            guard readyStates.contains(state) else { return nil }
            let reference = row[DatabaseSchema.SinistriColumns.riferimento]
            guard !reference.isEmpty else { return nil }
            return CandidateClaim(
                reference: reference,
                company: normalizedCompany(group: row[DatabaseSchema.SinistriColumns.gruppo], company: row[DatabaseSchema.SinistriColumns.compagnia]),
                agencyCode: row[DatabaseSchema.SinistriColumns.codiceAgenzia],
                policyNumber: row[DatabaseSchema.SinistriColumns.numeroPolizza],
                insuredName: row[DatabaseSchema.SinistriColumns.nomeAssicurato] ?? row[DatabaseSchema.SinistriColumns.nomeContraente],
                guarantee: {
                    let raw = row[DatabaseSchema.SinistriColumns.fulminazione]
                    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return trimmed.isEmpty ? "Fenomeno Elettrico" : trimmed
                }(),
                estimatedAmount: [
                    row[DatabaseSchema.SinistriColumns.liquidato] ?? 0,
                    row[DatabaseSchema.SinistriColumns.richiesta] ?? 0,
                    row[DatabaseSchema.SinistriColumns.stimaDanno] ?? 0,
                    row[DatabaseSchema.SinistriColumns.dannoAccertato] ?? 0
                ].max() ?? 0,
                assignedTo: row[DatabaseSchema.SinistriColumns.assegnatario],
                priority: priorityScore(row: row),
                complexity: complexityScore(row: row)
            )
        }
    }

    private func buildAssignments(
        tenantSlug: String,
        claims: [CandidateClaim],
        members: [AssignmentMemberSettingsDTO],
        settings: AssignmentPlannerSettingsDTO
    ) -> [AssignmentPlanEntryDTO] {
        var projections = Dictionary(uniqueKeysWithValues: members.map { ($0.email.lowercased(), MemberProjection(member: $0, planningDays: settings.planningHorizonDays, defaultTarget: settings.defaultMonthlyTarget)) })
        let sortedClaims = claims.sorted {
            if $0.priority == $1.priority { return $0.complexity > $1.complexity }
            return $0.priority > $1.priority
        }

        var assignments: [AssignmentPlanEntryDTO] = []
        for claim in sortedClaims {
            let eligible = projections.values.compactMap { projection -> (MemberProjection, Int, Double)? in
                guard projection.accepts(company: claim.company) else { return nil }
                let day = projection.bestDay
                let nextRatio = (projection.totalWeight + claim.complexity) / max(projection.capacityWeight, 1)
                guard nextRatio <= settings.maxLoadRatioPerExpert else { return nil }

                var score = nextRatio + (projection.dayWeights[day] ?? 0)
                if projection.matchesAgency(claim.agencyCode) { score -= 0.35 }
                if projection.matchesPolicy(claim.policyNumber) { score -= 0.45 }
                if projection.matchesInsured(claim.insuredName) { score -= 0.35 }
                if projection.matchesGuarantee(claim.guarantee) { score -= 0.4 }
                if let current = claim.assignedTo?.lowercased(), current == projection.email { score -= 0.2 }
                if claim.estimatedAmount > 0, projection.maxAuthority > 0, projection.maxAuthority >= claim.estimatedAmount { score -= 0.1 }
                score -= min(claim.priority * 0.12, 0.2)
                return (projection, day, score)
            }
            .sorted { lhs, rhs in
                if lhs.2 == rhs.2 { return lhs.0.totalWeight < rhs.0.totalWeight }
                return lhs.2 < rhs.2
            }

            guard let best = eligible.first else { continue }
            var updated = best.0
            updated.totalWeight += claim.complexity
            updated.dayWeights[best.1, default: 0] += claim.complexity
            projections[updated.email] = updated

            assignments.append(
                AssignmentPlanEntryDTO(
                    tenantSlug: tenantSlug,
                    claimReference: claim.reference,
                    company: claim.company,
                    assigneeEmail: updated.email,
                    assigneeName: updated.displayName,
                    plannedDayOffset: best.1,
                    priority: claim.priority,
                    complexityWeight: claim.complexity,
                    previousAssigneeEmail: claim.assignedTo
                )
            )
        }

        return assignments.sorted {
            if $0.company == $1.company {
                if $0.plannedDayOffset == $1.plannedDayOffset { return $0.priority > $1.priority }
                return $0.plannedDayOffset < $1.plannedDayOffset
            }
            return $0.company < $1.company
        }
    }

    private func normalizedCompany(group: String?, company: String?) -> String {
        let groupValue = (group ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !groupValue.isEmpty { return groupValue }
        let companyValue = (company ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return companyValue.isEmpty ? "Senza compagnia" : companyValue
    }

    private func priorityScore(row: Row) -> Double {
        var score = 1.0
        if let amount = row[DatabaseSchema.SinistriColumns.richiesta], amount > 5000 { score += 0.35 }
        if let amount = row[DatabaseSchema.SinistriColumns.liquidato], amount > 5000 { score += 0.25 }
        if row[DatabaseSchema.SinistriColumns.sopralluogo] { score += 0.2 }
        let state = row[DatabaseSchema.SinistriColumns.stato]
        if state == "In attesa assegnazione" { score += 0.15 }
        if let incarico = row[DatabaseSchema.SinistriColumns.dataIncarico] {
            let ageDays = max((Date().timeIntervalSince1970 - incarico) / 86_400, 0)
            score += min(ageDays / 10.0, 0.5)
        }
        return score
    }

    private func complexityScore(row: Row) -> Double {
        var score = 1.0
        if row[DatabaseSchema.SinistriColumns.sopralluogo] { score += 0.35 }
        if row[DatabaseSchema.SinistriColumns.giustificativi] { score += 0.15 }
        if row[DatabaseSchema.SinistriColumns.oltreDieciBeni] { score += 0.25 }
        if let amount = row[DatabaseSchema.SinistriColumns.richiesta], amount > 10000 { score += 0.35 }
        return max(score, 0.5)
    }
}

private struct CandidateClaim {
    let reference: String
    let company: String
    let agencyCode: String?
    let policyNumber: String?
    let insuredName: String?
    let guarantee: String
    let estimatedAmount: Double
    let assignedTo: String?
    let priority: Double
    let complexity: Double
}

private struct MemberProjection {
    let email: String
    let displayName: String
    let assignedCompanies: Set<String>
    let preferredAgencyCodes: Set<String>
    let preferredPolicyNumbers: Set<String>
    let preferredInsureds: Set<String>
    let preferredGuarantees: Set<String>
    let maxAuthority: Double
    var totalWeight: Double
    var dayWeights: [Int: Double]
    let capacityWeight: Double

    init(member: AssignmentMemberSettingsDTO, planningDays: Int, defaultTarget: Int) {
        let normalizedTarget = max(member.monthlyClaimTarget, defaultTarget, 1)
        self.email = member.email.lowercased()
        self.displayName = member.displayName
        self.assignedCompanies = Set(member.assignedCompanies.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        self.preferredAgencyCodes = Set(member.preferredAgencyCodes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        self.preferredPolicyNumbers = Set(member.preferredPolicyNumbers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        self.preferredInsureds = Set(member.preferredInsureds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        self.preferredGuarantees = Set(member.preferredGuarantees.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        self.maxAuthority = member.maxAuthority
        self.totalWeight = 0
        self.dayWeights = Dictionary(uniqueKeysWithValues: (0..<max(planningDays, 1)).map { ($0, 0) })
        self.capacityWeight = max(Double(normalizedTarget) * Double(max(planningDays, 1)) / 22.0, 1.0)
    }

    var bestDay: Int {
        dayWeights.min(by: { $0.value < $1.value })?.key ?? 0
    }

    func accepts(company: String) -> Bool {
        assignedCompanies.isEmpty || assignedCompanies.contains(company)
    }

    func matchesAgency(_ code: String?) -> Bool {
        preferredAgencyCodes.contains(code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
    }

    func matchesPolicy(_ value: String?) -> Bool {
        preferredPolicyNumbers.contains(value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
    }

    func matchesInsured(_ value: String?) -> Bool {
        preferredInsureds.contains(value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
    }

    func matchesGuarantee(_ value: String?) -> Bool {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let effective = (normalized?.isEmpty == false ? normalized! : "fenomeno elettrico")
        return preferredGuarantees.contains(effective)
    }
}
