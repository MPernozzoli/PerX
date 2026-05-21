import Foundation

struct TenantSummaryDTO: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String
}

struct TenantCATPlannerSettingsDTO: Codable {
    let route_generation_hour: Int
    let route_review_window_minutes: Int
    let availability_slot_minutes: Int
    let availability_tolerance_percent: Int
    let max_outside_zone_kilometers: Int
}

struct TenantCATPOIDTO: Codable, Identifiable, Hashable {
    let id: String
    let display_name: String
    let email: String
    let latitude: Double
    let longitude: Double
    let comune: String
    let provincia: String
    let regione: String
    let assigned_municipalities: [String]
    let note: String
}

struct TenantCATMunicipalityDTO: Codable, Identifiable, Hashable {
    let id: String
    let comune: String
    let provincia: String
    let regione: String
    let latitude: Double
    let longitude: Double
    let assigned_cat_emails: [String]
    let priority: Int
}

struct TenantCATSettingsDTO: Codable {
    let enabled: Bool
    let planner: TenantCATPlannerSettingsDTO
    let technicians: [TenantCATPOIDTO]
    let municipalities: [TenantCATMunicipalityDTO]
}

struct TenantInspectionProviderSettingsDTO: Codable {
    let map_provider: String
    let maps_api_key: String
    let routing_provider: String
    let routing_api_key: String
    let geocoding_provider: String
    let geocoding_api_key: String
    let messaging_provider: String
    let messaging_api_key: String
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
    let cat_settings: TenantCATSettingsDTO
    let provider_settings: TenantInspectionProviderSettingsDTO?
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
    let cat_settings: TenantCATSettingsDTO
    let provider_settings: TenantInspectionProviderSettingsDTO?
}

struct TenantInspectionRouteStopDTO: Decodable, Identifiable, Hashable {
    var id: String { "\(claim_id)-\(starts_at)" }
    let claim_id: String
    let claim_reference: String?
    let starts_at: String
    let ends_at: String
    let municipality: String?
    let province: String?
    let masked_location: String?
    let outside_zone: Bool
    let duration_minutes: Int
}

struct TenantInspectionRouteDTO: Decodable, Identifiable, Hashable {
    let event_id: String
    let owner_user_id: String
    let owner_email: String?
    let owner_name: String?
    let title: String
    let plan_date: String
    let generated_at: String?
    let review_deadline: String?
    let status: String
    let total_distance_km: Double
    let total_duration_minutes: Int
    let tenant_names: [String]
    let stops: [TenantInspectionRouteStopDTO]
    let rejection_reason_code: String?
    let rejection_reason: String?

    var id: String { event_id }
}

struct TenantInspectionRouteListDTO: Decodable {
    let items: [TenantInspectionRouteDTO]
    let total: Int
}

struct TenantInspectionRouteRunPayloadDTO: Encodable {
    let tenant_id: String?
    let plan_date: String?
    let force: Bool
}

struct TenantInspectionRouteRunDTO: Decodable {
    let tenant_id: String
    let plan_date: String
    let processed_at: String
    let generated_routes_count: Int
    let claims_planned: Int
    let claims_fallback_manual: Int
    let skipped_claims: Int
    let route_event_ids: [String]
    let fallback_claim_ids: [String]
}

struct TenantInspectionExpirationDTO: Decodable {
    let processed_at: String
    let expired_routes_count: Int
    let replanned_routes_count: Int
    let manual_fallback_claims: Int
}

struct TenantUserDTO: Codable, Identifiable, Hashable {
    let id: String
    let tenant_id: String
    let personal_email: String
    let professional_email: String?
    let email_aliases: [String]
    let first_name: String
    let last_name: String
    let full_name: String
    let job_title: String?
    let phone_number: String?
    let contract_type: String?
    let roles: [String]
    let is_active: Bool
    let invite_status: String?
    let invited_at: String?
    let last_login_at: String?
}

struct TenantUserCreateDTO: Encodable {
    let personal_email: String
    let first_name: String
    let last_name: String
    let job_title: String?
    let phone_number: String?
    let contract_type: String?
    let roles: [String]
    let send_invite: Bool
}

struct TenantUserUpdateDTO: Encodable {
    let first_name: String
    let last_name: String
    let job_title: String?
    let phone_number: String?
    let contract_type: String?
    let roles: [String]
    let is_active: Bool
    let professional_email: String?
}

struct TenantUserInviteDTO: Decodable {
    let user: TenantUserDTO
    let invite_status: String
    let invite_error: String?
}

@MainActor
final class TenantSettingsAPIService: ObservableObject {
    static let shared = TenantSettingsAPIService()

    @Published private(set) var availableTenants: [TenantSummaryDTO] = []
    @Published private(set) var lastSyncError: String?
    @Published private(set) var backendReachable = false
    @Published private(set) var latestInspectionRoutes: [TenantInspectionRouteDTO] = []
    @Published private(set) var tenantUsers: [TenantUserDTO] = []

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
            default_claim_garanzia: settings.defaultClaimGaranzia,
            cat_settings: map(settings.catSettings),
            provider_settings: settings.providerSettings.map(map)
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

    func loadInspectionRoutes(targetTenantId: String? = nil) async -> [TenantInspectionRouteDTO] {
        do {
            let dto: TenantInspectionRouteListDTO = try await apiClient.get(
                "inspections/routes",
                queryItems: queryItems(for: targetTenantId)
            )
            backendReachable = true
            lastSyncError = nil
            latestInspectionRoutes = dto.items
            return dto.items
        } catch {
            backendReachable = false
            lastSyncError = error.localizedDescription
            return latestInspectionRoutes
        }
    }

    func loadTenantUsers(targetTenantId: String? = nil) async -> [TenantUserDTO] {
        do {
            let users: [TenantUserDTO] = try await apiClient.get(
                "tenants/me/users",
                queryItems: queryItems(for: targetTenantId)
            )
            backendReachable = true
            lastSyncError = nil
            tenantUsers = users
            return users
        } catch {
            backendReachable = false
            lastSyncError = error.localizedDescription
            return tenantUsers
        }
    }

    func createTenantUser(_ payload: TenantUserCreateDTO, targetTenantId: String? = nil) async -> TenantUserInviteDTO? {
        do {
            let response: TenantUserInviteDTO = try await apiClient.post(
                "tenants/me/users",
                body: payload,
                queryItems: queryItems(for: targetTenantId)
            )
            _ = await loadTenantUsers(targetTenantId: targetTenantId)
            backendReachable = true
            lastSyncError = response.invite_error
            return response
        } catch {
            backendReachable = false
            lastSyncError = error.localizedDescription
            return nil
        }
    }

    func updateTenantUser(_ userId: String, payload: TenantUserUpdateDTO, targetTenantId: String? = nil) async -> TenantUserDTO? {
        do {
            let user: TenantUserDTO = try await apiClient.put(
                "tenants/me/users/\(userId)",
                body: payload,
                queryItems: queryItems(for: targetTenantId)
            )
            _ = await loadTenantUsers(targetTenantId: targetTenantId)
            backendReachable = true
            lastSyncError = nil
            return user
        } catch {
            backendReachable = false
            lastSyncError = error.localizedDescription
            return nil
        }
    }

    func resendTenantUserInvite(_ userId: String, targetTenantId: String? = nil) async -> TenantUserInviteDTO? {
        do {
            let response: TenantUserInviteDTO = try await apiClient.post(
                "tenants/me/users/\(userId)/invite",
                body: EmptyTenantPayload(),
                queryItems: queryItems(for: targetTenantId)
            )
            _ = await loadTenantUsers(targetTenantId: targetTenantId)
            backendReachable = true
            lastSyncError = response.invite_error
            return response
        } catch {
            backendReachable = false
            lastSyncError = error.localizedDescription
            return nil
        }
    }

    func runInspectionPlanner(
        targetTenantId: String? = nil,
        planDate: String? = nil,
        force: Bool = false
    ) async -> TenantInspectionRouteRunDTO? {
        do {
            let dto: TenantInspectionRouteRunDTO = try await apiClient.post(
                "inspections/routes/run",
                body: TenantInspectionRouteRunPayloadDTO(
                    tenant_id: targetTenantId,
                    plan_date: planDate,
                    force: force
                )
            )
            backendReachable = true
            lastSyncError = nil
            _ = await loadInspectionRoutes(targetTenantId: targetTenantId)
            return dto
        } catch {
            backendReachable = false
            lastSyncError = error.localizedDescription
            return nil
        }
    }

    func processInspectionRouteExpirations(targetTenantId: String? = nil) async -> TenantInspectionExpirationDTO? {
        do {
            let dto: TenantInspectionExpirationDTO = try await apiClient.post(
                "inspections/routes/process-expirations",
                body: EmptyTenantPayload(),
                queryItems: queryItems(for: targetTenantId)
            )
            backendReachable = true
            lastSyncError = nil
            _ = await loadInspectionRoutes(targetTenantId: targetTenantId)
            return dto
        } catch {
            backendReachable = false
            lastSyncError = error.localizedDescription
            return nil
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
            defaultClaimGaranzia: dto.default_claim_garanzia,
            catSettings: map(dto.cat_settings),
            providerSettings: dto.provider_settings.map(map)
        )
    }

    private func map(_ dto: TenantCATSettingsDTO) -> TenantCATSettings {
        TenantCATSettings(
            enabled: dto.enabled,
            planner: TenantCATPlannerSettings(
                routeGenerationHour: dto.planner.route_generation_hour,
                routeReviewWindowMinutes: dto.planner.route_review_window_minutes,
                availabilitySlotMinutes: dto.planner.availability_slot_minutes,
                availabilityTolerancePercent: dto.planner.availability_tolerance_percent,
                maxOutsideZoneKilometers: dto.planner.max_outside_zone_kilometers
            ),
            technicians: dto.technicians.map { item in
                TenantCATPOI(
                    id: item.id,
                    displayName: item.display_name,
                    email: item.email,
                    latitude: item.latitude,
                    longitude: item.longitude,
                    comune: item.comune,
                    provincia: item.provincia,
                    regione: item.regione,
                    assignedMunicipalities: item.assigned_municipalities,
                    note: item.note
                )
            },
            municipalities: dto.municipalities.map { item in
                TenantCATMunicipality(
                    id: item.id,
                    comune: item.comune,
                    provincia: item.provincia,
                    regione: item.regione,
                    latitude: item.latitude,
                    longitude: item.longitude,
                    assignedCATEmails: item.assigned_cat_emails,
                    priority: item.priority
                )
            }
        )
    }

    private func map(_ dto: TenantInspectionProviderSettingsDTO) -> TenantInspectionProviderSettings {
        TenantInspectionProviderSettings(
            mapProvider: dto.map_provider,
            mapsAPIKey: dto.maps_api_key,
            routingProvider: dto.routing_provider,
            routingAPIKey: dto.routing_api_key,
            geocodingProvider: dto.geocoding_provider,
            geocodingAPIKey: dto.geocoding_api_key,
            messagingProvider: dto.messaging_provider,
            messagingAPIKey: dto.messaging_api_key
        )
    }

    private func map(_ value: TenantCATSettings) -> TenantCATSettingsDTO {
        TenantCATSettingsDTO(
            enabled: value.enabled,
            planner: TenantCATPlannerSettingsDTO(
                route_generation_hour: value.planner.routeGenerationHour,
                route_review_window_minutes: value.planner.routeReviewWindowMinutes,
                availability_slot_minutes: value.planner.availabilitySlotMinutes,
                availability_tolerance_percent: value.planner.availabilityTolerancePercent,
                max_outside_zone_kilometers: value.planner.maxOutsideZoneKilometers
            ),
            technicians: value.technicians.map { item in
                TenantCATPOIDTO(
                    id: item.id,
                    display_name: item.displayName,
                    email: item.email,
                    latitude: item.latitude,
                    longitude: item.longitude,
                    comune: item.comune,
                    provincia: item.provincia,
                    regione: item.regione,
                    assigned_municipalities: item.assignedMunicipalities,
                    note: item.note
                )
            },
            municipalities: value.municipalities.map { item in
                TenantCATMunicipalityDTO(
                    id: item.id,
                    comune: item.comune,
                    provincia: item.provincia,
                    regione: item.regione,
                    latitude: item.latitude,
                    longitude: item.longitude,
                    assigned_cat_emails: item.assignedCATEmails,
                    priority: item.priority
                )
            }
        )
    }

    private func map(_ value: TenantInspectionProviderSettings) -> TenantInspectionProviderSettingsDTO {
        TenantInspectionProviderSettingsDTO(
            map_provider: value.mapProvider,
            maps_api_key: value.mapsAPIKey,
            routing_provider: value.routingProvider,
            routing_api_key: value.routingAPIKey,
            geocoding_provider: value.geocodingProvider,
            geocoding_api_key: value.geocodingAPIKey,
            messaging_provider: value.messagingProvider,
            messaging_api_key: value.messagingAPIKey
        )
    }
}

private struct EmptyTenantPayload: Encodable {}
