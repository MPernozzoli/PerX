import Foundation
import CoreData
import Combine

@MainActor
final class AutomaticClaimAssignmentService: ObservableObject {
    static let shared = AutomaticClaimAssignmentService()

    struct Settings: Codable, Equatable {
        var planningHorizonDays: Int = 3
        var defaultMonthlyTarget: Int = 80
        var maxLoadRatioPerExpert: Double = 1.15
        var rebalancePriorityMargin: Double = 0.12
        var workingPenalty: Double = 0.35
        var offlinePenalty: Double = 0.25
    }

    struct PlannedAssignment: Codable, Identifiable, Equatable {
        var id: String { claimReference }
        let tenantSlug: String
        let companyRawValue: String
        let claimReference: String
        let assigneeEmail: String
        let assigneeName: String
        let plannedDayOffset: Int
        let priority: Double
        let complexityWeight: Double
        let previousAssigneeEmail: String?
    }

    struct TeamPlan: Codable, Equatable {
        let tenantSlug: String
        let companyRawValue: String
        let generatedAt: Date
        let assignments: [PlannedAssignment]
        let unassignedClaimReferences: [String]
    }

    @Published private(set) var plansByCompany: [String: TeamPlan] = [:]
    @Published private(set) var lastRunAt: Date?
    @Published private(set) var lastReason: String?

    private let defaults = UserDefaults.standard
    private let profileService = UserProfileService.shared
    private let configService = TeamConfigurationService.shared
    private let directoryService = CloudKitUserDirectoryService.shared
    private let priorityCalculator = PriorityCalculator.shared
    private var cancellables = Set<AnyCancellable>()
    private var pendingRunTask: Task<Void, Never>?

    private let settingsKeyPrefix = "automaticClaimAssignment.settings"
    private let plansKeyPrefix = "automaticClaimAssignment.plans"

    private init() {
        loadPlans()
        setupObservers()
    }

    func runNow(reason: String, context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) async {
        pendingRunTask?.cancel()
        await rebuildPlans(reason: reason, context: context)
    }

    func currentPlan(for company: Compagnia) -> TeamPlan? {
        plansByCompany[company.rawValue]
    }

    func currentSettings() -> Settings {
        if HubConfigService.shared.isHubReady {
            Task { await fetchSettingsFromHub() }
        }
        guard let data = defaults.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return decoded.normalized
    }

    func updateSettings(_ mutate: (inout Settings) -> Void) {
        var settings = currentSettings()
        mutate(&settings)
        let normalized = settings.normalized
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: settingsKey)
        pushSettingsToHub(normalized)
        scheduleRun(reason: "settingsChanged", delay: 0.2)
    }

    private func setupObservers() {
        NotificationCenter.default.publisher(for: .sinistroCreated)
            .sink { [weak self] _ in self?.scheduleRun(reason: "sinistroCreated") }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sinistroUpdated)
            .sink { [weak self] _ in self?.scheduleRun(reason: "sinistroUpdated") }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sinistroStatoChanged)
            .sink { [weak self] _ in self?.scheduleRun(reason: "statoChanged") }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .workScheduleChanged)
            .sink { [weak self] _ in self?.scheduleRun(reason: "workScheduleChanged") }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .tenantSettingsChanged)
            .sink { [weak self] _ in
                self?.configService.reload()
                self?.loadPlans()
                self?.scheduleRun(reason: "tenantChanged", delay: 0.2)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: PersistenceController.shared.container.viewContext
        )
        .sink { [weak self] notification in
            guard let self else { return }
            if self.containsClaimChanges(notification.userInfo) {
                self.scheduleRun(reason: "coreDataClaimsChanged", delay: 0.4)
            }
        }
        .store(in: &cancellables)

        profileService.$allProfiles
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRun(reason: "profilesChanged") }
            .store(in: &cancellables)

        configService.$memberSettingsByEmail
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRun(reason: "teamConfigChanged", delay: 0.2) }
            .store(in: &cancellables)

        directoryService.$users
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRun(reason: "directoryChanged") }
            .store(in: &cancellables)
    }

    private func scheduleRun(reason: String, delay: TimeInterval = 0.8) {
        guard canCurrentUserManageAssignments else { return }
        pendingRunTask?.cancel()
        pendingRunTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.rebuildPlans(
                reason: reason,
                context: PersistenceController.shared.container.viewContext
            )
        }
    }

    private func rebuildPlans(reason: String, context: NSManagedObjectContext) async {
        guard canCurrentUserManageAssignments else { return }
        if HubConfigService.shared.isHubReady {
            await recomputeOnHub(reason: reason)
            return
        }

        let claims = fetchClaims(context: context)
        let settings = currentSettings()
        let today = Calendar.current.startOfDay(for: Date())

        var newPlans: [String: TeamPlan] = [:]
        var finalAssignments: [String: PlannedAssignment] = [:]
        var changedClaims: [Sinistro] = []

        let companies = Set(claims.map(detectCompany(for:)).filter { $0 != .unknown })
        for company in companies {
            let teamClaims = claims.filter { detectCompany(for: $0) == company }
            let plan = buildPlan(
                for: company,
                claims: teamClaims,
                settings: settings,
                today: today
            )
            newPlans[company.rawValue] = plan.teamPlan
            finalAssignments.merge(plan.assignmentsByClaim) { _, new in new }
        }

        let reassignableClaims = claims.filter(isReassignable)
        for claim in reassignableClaims {
            guard let reference = claim.riferimento, !reference.isEmpty else { continue }

            let currentAssignee = normalizeEmail(claim.assignedToUserEmail ?? claim.ownerEmail)
            if let planned = finalAssignments[reference] {
                let didChange = applyAssignment(planned, to: claim)
                if didChange {
                    changedClaims.append(claim)
                }
            } else {
                let didChange = revokeAssignmentIfNeeded(for: claim, currentAssignee: currentAssignee)
                if didChange {
                    changedClaims.append(claim)
                }
            }
        }

        persistPlans(newPlans)
        plansByCompany = newPlans
        lastRunAt = Date()
        lastReason = reason

        guard context.hasChanges else { return }

        do {
            try context.save()
            for claim in changedClaims {
                NotificationCenter.default.post(
                    name: .sinistroUpdated,
                    object: nil,
                    userInfo: ["sinistroID": claim.riferimento ?? ""]
                )
                await CloudKitSinistroSyncService.shared.pushSinistro(claim)
            }
        } catch {
            print("[AutomaticClaimAssignment] ❌ Errore salvataggio: \(error.localizedDescription)")
        }
    }

    private func buildPlan(
        for company: Compagnia,
        claims: [Sinistro],
        settings: Settings,
        today: Date
    ) -> (teamPlan: TeamPlan, assignmentsByClaim: [String: PlannedAssignment]) {
        let members = eligibleMembers(for: company, settings: settings)
        guard !members.isEmpty else {
            let unassigned = claims.filter(isReadyForAutomaticAssignment).compactMap(\.riferimento).sorted()
            return (
                TeamPlan(
                    tenantSlug: tenantSlug,
                    companyRawValue: company.rawValue,
                    generatedAt: Date(),
                    assignments: [],
                    unassignedClaimReferences: unassigned
                ),
                [:]
            )
        }

        var projections = Dictionary(uniqueKeysWithValues: members.map { ($0.email, $0) })
        let candidates = claims
            .filter(isReadyForAutomaticAssignment)
            .sorted { lhs, rhs in
                let left = claimPriority(for: lhs)
                let right = claimPriority(for: rhs)
                if left == right {
                    return complexityWeight(for: lhs) > complexityWeight(for: rhs)
                }
                return left > right
            }

        var assignments: [PlannedAssignment] = []
        var unassigned: [String] = []

        for claim in candidates {
            guard let reference = claim.riferimento, !reference.isEmpty else { continue }
            guard let choice = bestProjection(for: claim, members: projections, settings: settings) else {
                unassigned.append(reference)
                continue
            }

            let currentAssignee = normalizeEmail(claim.assignedToUserEmail ?? claim.ownerEmail)
            let assignment = PlannedAssignment(
                tenantSlug: tenantSlug,
                companyRawValue: company.rawValue,
                claimReference: reference,
                assigneeEmail: choice.member.email,
                assigneeName: choice.member.displayName,
                plannedDayOffset: choice.dayOffset,
                priority: claimPriority(for: claim),
                complexityWeight: complexityWeight(for: claim),
                previousAssigneeEmail: currentAssignee
            )
            assignments.append(assignment)

            var updated = choice.member
            updated.projectedTotalWeight += assignment.complexityWeight
            updated.projectedDayWeights[choice.dayOffset, default: 0] += assignment.complexityWeight
            projections[updated.email] = updated
        }

        let sortedAssignments = assignments.sorted {
            if $0.plannedDayOffset == $1.plannedDayOffset {
                return $0.priority > $1.priority
            }
            return $0.plannedDayOffset < $1.plannedDayOffset
        }

        return (
            TeamPlan(
                tenantSlug: tenantSlug,
                companyRawValue: company.rawValue,
                generatedAt: Date(),
                assignments: sortedAssignments,
                unassignedClaimReferences: unassigned.sorted()
            ),
            Dictionary(uniqueKeysWithValues: assignments.map { ($0.claimReference, $0) })
        )
    }

    private func bestProjection(
        for claim: Sinistro,
        members: [String: MemberProjection],
        settings: Settings
    ) -> (member: MemberProjection, dayOffset: Int)? {
        let priority = claimPriority(for: claim)
        let weight = complexityWeight(for: claim)
        let amount = claimEstimatedAmount(for: claim)
        let currentAssignee = normalizeEmail(claim.assignedToUserEmail ?? claim.ownerEmail)

        let scored = members.values.compactMap { member -> (MemberProjection, Int, Double)? in
            let bestDay = (0..<settings.normalized.planningHorizonDays).min { lhs, rhs in
                member.projectedDayWeights[lhs, default: 0] < member.projectedDayWeights[rhs, default: 0]
            } ?? 0

            let nextRatio = (member.projectedTotalWeight + weight) / max(member.capacityWeight, 1)
            if nextRatio > settings.maxLoadRatioPerExpert {
                return nil
            }

            var score = nextRatio
            score += member.workPenalty
            score += member.projectedDayWeights[bestDay, default: 0] / max(member.dailyCapacityWeight, 1)

            if currentAssignee == member.email {
                score -= 0.25
            }

            if member.matchesAgency(claim.codiceAgenzia) {
                score -= 0.35
            }
            if member.matchesPolicy(claim.numeroPolizza) {
                score -= 0.45
            }
            if member.matchesInsured(claim.nomeAssicurato ?? claim.nomeContraente) {
                score -= 0.35
            }
            if member.matchesGuarantee(claimGuarantee(for: claim)) {
                score -= 0.4
            }

            if amount > 0, member.maxAuthority > 0 {
                if member.maxAuthority >= amount {
                    score -= 0.08
                } else {
                    score += 0.12
                }
            }

            score -= min(priority * 0.15, 0.15)
            return (member, bestDay, score)
        }

        return scored.min { lhs, rhs in
            if lhs.2 == rhs.2 {
                return lhs.0.projectedTotalWeight < rhs.0.projectedTotalWeight
            }
            return lhs.2 < rhs.2
        }.map { ($0.0, $0.1) }
    }

    private func applyAssignment(_ assignment: PlannedAssignment, to claim: Sinistro) -> Bool {
        let currentAssignee = normalizeEmail(claim.assignedToUserEmail ?? claim.ownerEmail)
        let plannedAssignee = normalizeEmail(assignment.assigneeEmail)

        let alreadyAssigned = currentAssignee == plannedAssignee &&
            (claim.assignedToUserName ?? "") == assignment.assigneeName
        guard !alreadyAssigned else { return false }

        let actorEmail = normalizeEmail(CurrentUserService.shared.currentEmail)
        let previousDisplay = claim.assignedToUserName ?? claim.assignedToUserEmail ?? claim.ownerEmail ?? "non assegnato"

        claim.assignedToUserEmail = plannedAssignee
        claim.ownerEmail = plannedAssignee
        claim.assignedToUserName = assignment.assigneeName
        if claim.dataAssegnazione == nil {
            claim.dataAssegnazione = Date()
        }
        claim.cloudKitLastModified = Date()

        let note = currentAssignee.isEmpty
            ? "Assegnazione automatica a \(assignment.assigneeName)"
            : "Riassegnazione automatica da \(previousDisplay) a \(assignment.assigneeName)"

        claim.addDiarioEntry(
            DiarioEntry(
                testo: note,
                tipo: .assegnazione,
                createdByEmail: actorEmail.nilIfBlank
            )
        )
        return true
    }

    private func revokeAssignmentIfNeeded(for claim: Sinistro, currentAssignee: String) -> Bool {
        guard !currentAssignee.isEmpty else { return false }

        let actorEmail = normalizeEmail(CurrentUserService.shared.currentEmail)
        let previousDisplay = claim.assignedToUserName ?? claim.assignedToUserEmail ?? claim.ownerEmail ?? currentAssignee

        claim.assignedToUserEmail = nil
        claim.assignedToUserName = nil
        claim.ownerEmail = nil
        if state(for: claim) != .inAttesaAssegnazione {
            claim.stato = StatoManager.StatoSinistro.inAttesaAssegnazione.descrizione
        }
        claim.cloudKitLastModified = Date()
        claim.addDiarioEntry(
            DiarioEntry(
                testo: "Revoca automatica da \(previousDisplay) per riequilibrio carico",
                tipo: .assegnazione,
                createdByEmail: actorEmail.nilIfBlank
            )
        )
        return true
    }

    private func eligibleMembers(for company: Compagnia, settings: Settings) -> [MemberProjection] {
        let candidates = profileService.allProfiles.filter { profile in
            let roles = Set(configService.effectiveRoles(for: profile))
            guard roles.contains(.expert) || roles.contains(.teamLeader) else { return false }
            return configService.assignedCompanies(for: profile.email).contains(company)
        }

        return candidates.map { profile in
            let memberSettings = configService.settings(for: profile.email, fallbackName: profile.displayName)
            let cloudUser = directoryService.user(email: profile.email)
            let monthlyTarget = max(memberSettings.monthlyClaimTarget, settings.defaultMonthlyTarget)
            let capacityWeight = max(Double(monthlyTarget) * Double(settings.planningHorizonDays) / 22.0, 1.0)
            let dailyCapacityWeight = max(capacityWeight / Double(settings.planningHorizonDays), 1.0)

            return MemberProjection(
                email: profile.email.lowercased(),
                displayName: configService.displayName(for: profile),
                preferredAgencyCodes: Set(memberSettings.preferredAgencyCodes.map(normalizeText)),
                preferredPolicyNumbers: Set(memberSettings.preferredPolicyNumbers.map(normalizeText)),
                preferredInsureds: Set(memberSettings.preferredInsureds.map(normalizeText)),
                preferredGuarantees: Set(memberSettings.preferredGuarantees.map(normalizeText)),
                maxAuthority: memberSettings.maxAuthority,
                projectedTotalWeight: currentAssignedLoadWeight(for: profile.email, company: company),
                projectedDayWeights: [:],
                capacityWeight: capacityWeight,
                dailyCapacityWeight: dailyCapacityWeight,
                workPenalty: penalty(for: cloudUser, settings: settings)
            )
        }
    }

    private func currentAssignedLoadWeight(for email: String, company: Compagnia) -> Double {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "(assignedToUserEmail ==[c] %@ OR ownerEmail ==[c] %@)", email, email)
        let results = (try? context.fetch(request)) ?? []
        return results
            .filter { detectCompany(for: $0) == company }
            .filter { !isClosed($0) }
            .reduce(0) { $0 + complexityWeight(for: $1) }
    }

    private func penalty(for user: CloudKitUserDirectoryService.CloudUser?, settings: Settings) -> Double {
        guard let user else { return settings.workingPenalty }
        var penalty = 0.0
        switch user.workLocation {
        case .notWorking:
            penalty += settings.workingPenalty
        case .none:
            penalty += settings.workingPenalty / 2
        default:
            break
        }
        switch user.onlineStatus {
        case .offline:
            penalty += settings.offlinePenalty
        case .recent:
            penalty += settings.offlinePenalty / 2
        case .online:
            break
        }
        return penalty
    }

    private func fetchClaims(context: NSManagedObjectContext) -> [Sinistro] {
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Sinistro.dataIncarico, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    private func detectCompany(for claim: Sinistro) -> Compagnia {
        Compagnia.detect(gruppo: claim.gruppo, compagnia: claim.nomeCompagnia)
    }

    private func state(for claim: Sinistro) -> StatoManager.StatoSinistro? {
        guard let raw = claim.stato else { return nil }
        return StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == raw })
    }

    private func isClosed(_ claim: Sinistro) -> Bool {
        guard let state = state(for: claim) else { return false }
        return state.category == .chiusura || state == .revocata || state == .annullata
    }

    private func isReadyForAutomaticAssignment(_ claim: Sinistro) -> Bool {
        guard let state = state(for: claim) else { return false }
        guard !isClosed(claim) else { return false }
        return readyStates.contains(state)
    }

    private func isReassignable(_ claim: Sinistro) -> Bool {
        isReadyForAutomaticAssignment(claim)
    }

    private var readyStates: Set<StatoManager.StatoSinistro> {
        [
            .inAttesaAssegnazione,
            .sopralluogoAssegnato,
            .videoperiziaDaEseguire,
            .daGestireVideoperizia,
            .daGestireTradizionale,
            .daGestireDocumentale,
            .daGestireNoResidui
        ]
    }

    private func claimPriority(for claim: Sinistro) -> Double {
        let monthlyGoal = WorkScheduleManager.shared.getMonthlyTarget(for: Date())
        return priorityCalculator.calculateDynamicPriority(
            for: claim,
            monthlyGoal: monthlyGoal,
            currentClosures: 0,
            needsAcceleration: false
        )
    }

    private func complexityWeight(for claim: Sinistro) -> Double {
        var weight = 1.0
        let complexity = normalizeText(claim.complessita)
        if complexity.contains("alta") || complexity.contains("high") {
            weight += 0.6
        } else if complexity.contains("media") || complexity.contains("medium") {
            weight += 0.25
        } else if complexity.contains("bassa") || complexity.contains("low") {
            weight -= 0.15
        }
        if claim.oltreDieciBeni {
            weight += 0.25
        }
        if detectCompany(for: claim) == .unknown {
            weight += 0.15
        }
        return max(weight, 0.5)
    }

    private func claimEstimatedAmount(for claim: Sinistro) -> Double {
        [
            claim.liquidato?.doubleValue ?? 0,
            claim.stimaDanno?.doubleValue ?? 0,
            claim.richiesta?.doubleValue ?? 0,
            claim.dannoAccertato?.doubleValue ?? 0
        ].max() ?? 0
    }

    private func claimGuarantee(for claim: Sinistro) -> String {
        let guarantee = claim.fulminazione
        let normalized = normalizeText(guarantee)
        return normalized.isEmpty
            ? TenantMailSettingsService.shared.settings.defaultClaimGaranzia
            : (guarantee ?? TenantMailSettingsService.shared.settings.defaultClaimGaranzia)
    }

    private var canCurrentUserManageAssignments: Bool {
        let roles = Set(CurrentUserService.shared.currentRoles)
        return roles.contains(.admin) || roles.contains(.director) || roles.contains(.manager)
    }

    private var settingsKey: String {
        "\(settingsKeyPrefix).\(tenantSlug)"
    }

    private var plansKey: String {
        "\(plansKeyPrefix).\(tenantSlug)"
    }

    private var tenantSlug: String {
        let slug = TenantMailSettingsService.shared.settings.tenantSlug
        return slug.isEmpty ? "default" : slug
    }

    private func loadPlans() {
        if HubConfigService.shared.isHubReady {
            Task { await fetchPlansFromHub() }
        }
        guard let data = defaults.data(forKey: plansKey),
              let decoded = try? JSONDecoder().decode([String: TeamPlan].self, from: data) else {
            plansByCompany = [:]
            return
        }
        plansByCompany = decoded
    }

    private func persistPlans(_ plans: [String: TeamPlan]) {
        guard let data = try? JSONEncoder().encode(plans) else { return }
        defaults.set(data, forKey: plansKey)
    }

    private func fetchSettingsFromHub() async {
        do {
            let remote: AssignmentPlannerSettingsDTO = try await HubAPIClient.shared.get(endpoint: "planner/settings")
            let mapped = Settings(
                planningHorizonDays: remote.planningHorizonDays,
                defaultMonthlyTarget: remote.defaultMonthlyTarget,
                maxLoadRatioPerExpert: remote.maxLoadRatioPerExpert,
                rebalancePriorityMargin: remote.rebalancePriorityMargin,
                workingPenalty: remote.workingPenalty,
                offlinePenalty: remote.offlinePenalty
            ).normalized
            if let data = try? JSONEncoder().encode(mapped) {
                defaults.set(data, forKey: settingsKey)
            }
        } catch {
            print("[AutomaticClaimAssignment] Lettura settings HUB fallita: \(error.localizedDescription)")
        }
    }

    private func pushSettingsToHub(_ settings: Settings) {
        guard HubConfigService.shared.isHubReady else { return }
        Task {
            let dto = AssignmentPlannerSettingsDTO(
                tenantSlug: tenantSlug,
                planningHorizonDays: settings.planningHorizonDays,
                defaultMonthlyTarget: settings.defaultMonthlyTarget,
                maxLoadRatioPerExpert: settings.maxLoadRatioPerExpert,
                rebalancePriorityMargin: settings.rebalancePriorityMargin,
                workingPenalty: settings.workingPenalty,
                offlinePenalty: settings.offlinePenalty,
                enabled: true
            )
            do {
                let _: AssignmentPlannerSettingsDTO = try await HubAPIClient.shared.post(endpoint: "planner/settings", body: dto)
            } catch {
                print("[AutomaticClaimAssignment] Push settings HUB fallita: \(error.localizedDescription)")
            }
        }
    }

    private func fetchPlansFromHub() async {
        do {
            let remote: AssignmentPlanDTO = try await HubAPIClient.shared.get(endpoint: "planner/plan")
            let grouped = Dictionary(grouping: remote.assignments, by: \.company)
            let mapped = grouped.mapValues { entries -> TeamPlan in
                TeamPlan(
                    tenantSlug: tenantSlug,
                    companyRawValue: entries.first?.company ?? "",
                    generatedAt: remote.generatedAt,
                    assignments: entries.map {
                        PlannedAssignment(
                            tenantSlug: $0.tenantSlug,
                            companyRawValue: $0.company,
                            claimReference: $0.claimReference,
                            assigneeEmail: $0.assigneeEmail,
                            assigneeName: $0.assigneeName,
                            plannedDayOffset: $0.plannedDayOffset,
                            priority: $0.priority,
                            complexityWeight: $0.complexityWeight,
                            previousAssigneeEmail: $0.previousAssigneeEmail
                        )
                    },
                    unassignedClaimReferences: remote.unassignedClaimReferences
                )
            }
            plansByCompany = mapped
            persistPlans(mapped)
        } catch {
            print("[AutomaticClaimAssignment] Lettura piano HUB fallita: \(error.localizedDescription)")
        }
    }

    private func recomputeOnHub(reason: String) async {
        do {
            let plan: AssignmentPlanDTO = try await HubAPIClient.shared.post(
                endpoint: "planner/recompute",
                body: AssignmentPlanRecomputeRequest(reason: reason)
            )
            let grouped = Dictionary(grouping: plan.assignments, by: \.company)
            let mapped = grouped.mapValues { entries -> TeamPlan in
                TeamPlan(
                    tenantSlug: tenantSlug,
                    companyRawValue: entries.first?.company ?? "",
                    generatedAt: plan.generatedAt,
                    assignments: entries.map {
                        PlannedAssignment(
                            tenantSlug: $0.tenantSlug,
                            companyRawValue: $0.company,
                            claimReference: $0.claimReference,
                            assigneeEmail: $0.assigneeEmail,
                            assigneeName: $0.assigneeName,
                            plannedDayOffset: $0.plannedDayOffset,
                            priority: $0.priority,
                            complexityWeight: $0.complexityWeight,
                            previousAssigneeEmail: $0.previousAssigneeEmail
                        )
                    },
                    unassignedClaimReferences: plan.unassignedClaimReferences
                )
            }
            plansByCompany = mapped
            persistPlans(mapped)
            lastRunAt = Date()
            lastReason = reason
        } catch {
            print("[AutomaticClaimAssignment] Recompute HUB fallita: \(error.localizedDescription)")
        }
    }

    private func normalizeEmail(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func normalizeText(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func containsClaimChanges(_ userInfo: [AnyHashable: Any]?) -> Bool {
        let keys = [
            NSInsertedObjectsKey,
            NSUpdatedObjectsKey,
            NSDeletedObjectsKey,
            NSRefreshedObjectsKey
        ]

        for key in keys {
            if let objects = userInfo?[key] as? Set<NSManagedObject>,
               objects.contains(where: { $0 is Sinistro }) {
                return true
            }
        }
        return false
    }
}

private struct MemberProjection {
    let email: String
    let displayName: String
    let preferredAgencyCodes: Set<String>
    let preferredPolicyNumbers: Set<String>
    let preferredInsureds: Set<String>
    let preferredGuarantees: Set<String>
    let maxAuthority: Double
    var projectedTotalWeight: Double
    var projectedDayWeights: [Int: Double]
    let capacityWeight: Double
    let dailyCapacityWeight: Double
    let workPenalty: Double

    func matchesAgency(_ code: String?) -> Bool {
        preferredAgencyCodes.contains(code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
    }

    func matchesPolicy(_ policy: String?) -> Bool {
        preferredPolicyNumbers.contains(policy?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
    }

    func matchesInsured(_ name: String?) -> Bool {
        preferredInsureds.contains(name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
    }

    func matchesGuarantee(_ guarantee: String?) -> Bool {
        let normalized = guarantee?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let effective = (normalized?.isEmpty == false ? normalized! : "fenomeno elettrico")
        return preferredGuarantees.contains(effective)
    }
}

private extension AutomaticClaimAssignmentService.Settings {
    var normalized: AutomaticClaimAssignmentService.Settings {
        var value = self
        value.planningHorizonDays = min(max(value.planningHorizonDays, 1), 7)
        value.defaultMonthlyTarget = max(value.defaultMonthlyTarget, 1)
        value.maxLoadRatioPerExpert = max(value.maxLoadRatioPerExpert, 0.5)
        value.rebalancePriorityMargin = max(value.rebalancePriorityMargin, 0)
        value.workingPenalty = max(value.workingPenalty, 0)
        value.offlinePenalty = max(value.offlinePenalty, 0)
        return value
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
