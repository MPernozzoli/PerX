import Foundation

struct TenantSummaryDTO: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String
}

struct TenantSettingsDTO: Codable {
    let tenant_id: String
    let tenant_name: String
    let tenant_slug: String
    let internal_domains: [String]
    let internal_emails: [String]
    let system_emails: [String]
    let secretariat_emails: [String]
    let claim_garanzie: [String]
    let default_claim_garanzia: String
}

struct TenantSettingsPayloadDTO: Encodable {
    let tenant_name: String
    let tenant_slug: String
    let internal_domains: [String]
    let internal_emails: [String]
    let system_emails: [String]
    let secretariat_emails: [String]
    let claim_garanzie: [String]
    let default_claim_garanzia: String
}

@MainActor
final class TenantSettingsAPIService: ObservableObject {
    static let shared = TenantSettingsAPIService()

    @Published private(set) var availableTenants: [TenantSummaryDTO] = []
    @Published private(set) var lastSyncError: String?
    @Published private(set) var backendReachable = false

    private let apiClient = BackendAPIClient.shared

    private init() {}

    func loadTenantSettings(targetTenantId: String? = nil) async -> TenantMailSettings {
        do {
            let dto: TenantSettingsDTO = try await apiClient.get(
                "tenants/me/settings",
                queryItems: queryItems(for: targetTenantId)
            )
            backendReachable = true
            lastSyncError = nil

            let mapped = map(dto)
            TenantMailSettingsService.shared.settings = mapped
            return mapped
        } catch {
            backendReachable = false
            lastSyncError = error.localizedDescription
            return TenantMailSettingsService.shared.settings
        }
    }

    func saveTenantSettings(_ settings: TenantMailSettings, targetTenantId: String? = nil) async -> TenantMailSettings {
        let payload = TenantSettingsPayloadDTO(
            tenant_name: settings.tenantName,
            tenant_slug: settings.tenantSlug,
            internal_domains: settings.internalDomains,
            internal_emails: settings.internalEmails,
            system_emails: settings.systemEmails,
            secretariat_emails: settings.secretariatEmails,
            claim_garanzie: settings.claimGaranzie,
            default_claim_garanzia: settings.defaultClaimGaranzia
        )

        TenantMailSettingsService.shared.settings = settings

        do {
            let dto: TenantSettingsDTO = try await apiClient.put(
                "tenants/me/settings",
                body: payload,
                queryItems: queryItems(for: targetTenantId)
            )
            backendReachable = true
            lastSyncError = nil
            let mapped = map(dto)
            TenantMailSettingsService.shared.settings = mapped
            return mapped
        } catch {
            backendReachable = false
            lastSyncError = error.localizedDescription
            return TenantMailSettingsService.shared.settings
        }
    }

    func refreshAvailableTenantsIfNeeded() async {
        guard CurrentUserService.shared.isPlatformAdmin else {
            availableTenants = []
            return
        }

        do {
            let tenants: [TenantSummaryDTO] = try await apiClient.get("admin/tenants")
            availableTenants = tenants
            backendReachable = true
            lastSyncError = nil
        } catch {
            backendReachable = false
            lastSyncError = error.localizedDescription
            availableTenants = []
        }
    }

    private func queryItems(for targetTenantId: String?) -> [URLQueryItem] {
        guard let targetTenantId, !targetTenantId.isEmpty else { return [] }
        return [URLQueryItem(name: "tenant_id", value: targetTenantId)]
    }

    private func map(_ dto: TenantSettingsDTO) -> TenantMailSettings {
        TenantMailSettings(
            tenantName: dto.tenant_name,
            tenantSlug: dto.tenant_slug,
            internalDomains: dto.internal_domains,
            internalEmails: dto.internal_emails,
            systemEmails: dto.system_emails,
            secretariatEmails: dto.secretariat_emails,
            claimGaranzie: dto.claim_garanzie,
            defaultClaimGaranzia: dto.default_claim_garanzia
        )
    }
}
