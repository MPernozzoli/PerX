import Foundation

@MainActor
final class TeamConfigurationService: ObservableObject {
    static let shared = TeamConfigurationService()

    struct MemberSettings: Codable, Identifiable, Equatable {
        var id: String { email }
        var email: String
        var displayNameOverride: String?
        var assignedCompanies: [String]
        var roleOverrides: [String]
        var monthlyClaimTarget: Int
        var maxAuthority: Double
        var preferredAgencyCodes: [String]
        var preferredPolicyNumbers: [String]
        var preferredInsureds: [String]
        var preferredGuarantees: [String]
        var notes: String?

        init(
            email: String,
            displayNameOverride: String? = nil,
            assignedCompanies: [String] = [],
            roleOverrides: [String] = [],
            monthlyClaimTarget: Int = 0,
            maxAuthority: Double = 0,
            preferredAgencyCodes: [String] = [],
            preferredPolicyNumbers: [String] = [],
            preferredInsureds: [String] = [],
            preferredGuarantees: [String] = ["Fenomeno Elettrico"],
            notes: String? = nil
        ) {
            self.email = email.lowercased()
            self.displayNameOverride = displayNameOverride
            self.assignedCompanies = assignedCompanies
            self.roleOverrides = roleOverrides
            self.monthlyClaimTarget = monthlyClaimTarget
            self.maxAuthority = maxAuthority
            self.preferredAgencyCodes = preferredAgencyCodes
            self.preferredPolicyNumbers = preferredPolicyNumbers
            self.preferredInsureds = preferredInsureds
            self.preferredGuarantees = preferredGuarantees.isEmpty ? ["Fenomeno Elettrico"] : preferredGuarantees
            self.notes = notes
        }
    }

    @Published private(set) var memberSettingsByEmail: [String: MemberSettings] = [:]

    private let storageKeyPrefix = "teamConfiguration.memberSettings"
    private var loadedStorageKey: String?

    private init() {
        load()
        syncFromHubIfNeeded()
    }

    func settings(for email: String, fallbackName: String? = nil) -> MemberSettings {
        ensureTenantScopeLoaded()
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let existing = memberSettingsByEmail[normalized] {
            return existing
        }
        return MemberSettings(email: normalized, displayNameOverride: fallbackName)
    }

    func save(settings: MemberSettings) {
        ensureTenantScopeLoaded()
        memberSettingsByEmail[settings.email] = settings
        persist()
        pushMemberSettingToHub(settings)
    }

    func assignedCompanies(for email: String) -> [Compagnia] {
        settings(for: email).assignedCompanies.compactMap(Compagnia.fromStoredValue)
    }

    func effectiveRoles(for profile: UserProfile?) -> [UserRole] {
        guard let profile else { return [] }
        let overrideRoles = settings(for: profile.email).roleOverrides.compactMap(UserRole.init(rawValue:))
        return overrideRoles.isEmpty ? profile.roles : overrideRoles
    }

    func displayName(for profile: UserProfile?) -> String {
        guard let profile else { return "Utente" }
        let override = settings(for: profile.email).displayNameOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (override?.isEmpty == false ? override! : profile.displayName)
    }

    func canManageTeam(company: Compagnia, currentEmail: String?, profiles: [UserProfile]) -> Bool {
        ensureTenantScopeLoaded()
        guard let currentEmail else { return false }
        guard let profile = profiles.first(where: { $0.email.lowercased() == currentEmail.lowercased() }) else { return false }

        let roles = Set(effectiveRoles(for: profile))
        if roles.contains(.admin) { return true }
        guard roles.contains(.teamLeader) else { return false }

        let configuredCompanies = assignedCompanies(for: profile.email)
        return configuredCompanies.isEmpty || configuredCompanies.contains(company)
    }

    func reload() {
        load()
        syncFromHubIfNeeded()
    }

    private func ensureTenantScopeLoaded() {
        let key = storageKey
        guard loadedStorageKey != key else { return }
        load()
    }

    private var storageKey: String {
        "\(storageKeyPrefix).\(tenantSlug)"
    }

    private var tenantSlug: String {
        let slug = TenantMailSettingsService.shared.settings.tenantSlug
        return slug.isEmpty ? "default" : slug
    }

    private func load() {
        loadedStorageKey = storageKey
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: MemberSettings].self, from: data) else {
            memberSettingsByEmail = [:]
            return
        }
        memberSettingsByEmail = decoded
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(memberSettingsByEmail) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }

    private func syncFromHubIfNeeded() {
        guard HubConfigService.shared.isHubReady else { return }
        Task {
            do {
                let remote: [AssignmentMemberSettingsDTO] = try await HubAPIClient.shared.get(endpoint: "planner/members")
                let mapped = Dictionary(uniqueKeysWithValues: remote.map { dto in
                    (dto.email.lowercased(), MemberSettings(from: dto))
                })
                await MainActor.run {
                    self.memberSettingsByEmail = mapped
                    self.persist()
                }
            } catch {
                print("[TeamConfigurationService] Sync members fallita: \(error.localizedDescription)")
            }
        }
    }

    private func pushMemberSettingToHub(_ settings: MemberSettings) {
        guard HubConfigService.shared.isHubReady else { return }
        Task {
            do {
                let dto = AssignmentMemberSettingsDTO(
                    tenantSlug: tenantSlug,
                    email: settings.email,
                    displayName: settings.displayNameOverride ?? settings.email,
                    assignedCompanies: settings.assignedCompanies,
                    roleOverrides: settings.roleOverrides,
                    monthlyClaimTarget: settings.monthlyClaimTarget,
                    maxAuthority: settings.maxAuthority,
                    preferredAgencyCodes: settings.preferredAgencyCodes,
                    preferredPolicyNumbers: settings.preferredPolicyNumbers,
                    preferredInsureds: settings.preferredInsureds,
                    preferredGuarantees: settings.preferredGuarantees,
                    isActive: true
                )
                let _: AssignmentMemberSettingsDTO = try await HubAPIClient.shared.post(endpoint: "planner/members", body: dto)
            } catch {
                print("[TeamConfigurationService] Push member fallita: \(error.localizedDescription)")
            }
        }
    }
}

private extension Compagnia {
    static func fromStoredValue(_ value: String) -> Compagnia? {
        Compagnia.allCases.first(where: { $0.rawValue == value })
    }
}

private extension TeamConfigurationService.MemberSettings {
    init(from dto: AssignmentMemberSettingsDTO) {
        self.init(
            email: dto.email,
            displayNameOverride: dto.displayName,
            assignedCompanies: dto.assignedCompanies,
            roleOverrides: dto.roleOverrides,
            monthlyClaimTarget: dto.monthlyClaimTarget,
            maxAuthority: dto.maxAuthority,
            preferredAgencyCodes: dto.preferredAgencyCodes,
            preferredPolicyNumbers: dto.preferredPolicyNumbers,
            preferredInsureds: dto.preferredInsureds,
            preferredGuarantees: dto.preferredGuarantees
        )
    }
}
