//
//  CATPlanningStore.swift
//  PerX per iPad
//
//  Store CAT collegato al backend per route, disponibilità e territorio.
//

import Foundation
import Combine

@MainActor
final class CATPlanningStore: ObservableObject {
    static let shared = CATPlanningStore()

    @Published private(set) var configuredEmail: String?
    @Published private(set) var routePlans: [CATRoutePlan] = []
    @Published private(set) var territory: CATTenantTerritorySnapshot = .empty
    @Published private(set) var schedulingRules: CATSchedulingRules = .default
    @Published private(set) var lastGeneratedAt: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var isSavingAvailability = false
    @Published private(set) var isSubmittingRouteDecision = false
    @Published private(set) var syncError: String?

    private let apiClient = HubAPIClient.shared
    private let calendar = Calendar(identifier: .gregorian)
    private var availabilityByMonth: [String: [CATAvailabilityDay]] = [:]
    private var currentTenantName: String?

    private init() {}

    func configure(for email: String?) {
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard configuredEmail != normalizedEmail else { return }

        configuredEmail = normalizedEmail
        routePlans = []
        territory = .empty
        schedulingRules = .default
        lastGeneratedAt = nil
        syncError = nil
        availabilityByMonth = [:]
    }

    func refresh(for month: Date = Date()) async {
        guard let configuredEmail, !configuredEmail.isEmpty else {
            applyMockState(reason: "Account CAT non configurato")
            return
        }

        guard apiClient.isCloudConfigured else {
            applyMockState(reason: "Backend cloud non configurato sull'iPad")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let monthString = Self.monthFormatter.string(from: month)
            async let tenantSettings = apiClient.getTenantSettingsFromCloud()
            async let routeResponse = apiClient.getInspectionRoutesFromCloud()
            async let availabilityResponse = apiClient.getInspectionAvailabilityFromCloud(month: monthString)

            let tenantDTO = try await tenantSettings
            let routesDTO = try await routeResponse
            let monthDTO = try await availabilityResponse

            currentTenantName = tenantDTO.tenant_name
            schedulingRules = Self.mapSchedulingRules(tenantDTO.cat_settings.planner)
            territory = Self.mapTerritory(
                tenantDTO: tenantDTO,
                configuredEmail: configuredEmail
            )
            routePlans = routesDTO.items.compactMap { route in
                Self.mapRoute(route, fallbackTenantName: tenantDTO.tenant_name)
            }
            lastGeneratedAt = routePlans.compactMap(\.generatedAt).max()
            availabilityByMonth[monthKey(for: month)] = monthDTO.items.compactMap(Self.mapAvailabilityDay)
            syncError = nil
            objectWillChange.send()
        } catch {
            if routePlans.isEmpty && territory.municipalities.isEmpty {
                applyMockState(reason: error.localizedDescription)
            } else {
                syncError = error.localizedDescription
            }
        }
    }

    func ensureAvailability(for month: Date) async {
        let key = monthKey(for: month)
        if availabilityByMonth[key] != nil {
            return
        }
        await refresh(for: month)
    }

    func dashboardSnapshot(for date: Date = Date()) -> CATDashboardSnapshot {
        let todayRoutes = routePlans.filter { calendar.isDate($0.routeDate, inSameDayAs: date) }
        let pendingRoutes = routePlans.filter { $0.status == .pendingApproval }
        let confirmedRoutes = routePlans.filter { $0.status == .confirmed }
        let outsideZoneStops = routePlans.flatMap(\.stops).filter(\.outsideZone).count

        return CATDashboardSnapshot(
            pendingApprovals: pendingRoutes.count,
            confirmedRoutes: confirmedRoutes.count,
            appointmentsToday: todayRoutes.flatMap(\.stops).count,
            assignedMunicipalities: territory.municipalities.count,
            outsideZoneStops: outsideZoneStops,
            nextPendingRoute: pendingRoutes.sorted { $0.routeDate < $1.routeDate }.first,
            nextConfirmedRoute: confirmedRoutes.sorted { $0.routeDate < $1.routeDate }.first
        )
    }

    func availability(for month: Date) -> [CATAvailabilityDay] {
        availabilityByMonth[monthKey(for: month)] ?? []
    }

    func availabilityDay(for date: Date) -> CATAvailabilityDay? {
        availability(for: date).first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func updateAvailability(_ day: CATAvailabilityDay, for month: Date) async {
        guard apiClient.isCloudConfigured else {
            cache(day, for: month)
            syncError = "Disponibilità salvata solo localmente: backend non configurato"
            return
        }

        isSavingAvailability = true
        defer { isSavingAvailability = false }

        do {
            let payload = CloudInspectionAvailabilityOverrideRequestDTO(
                is_available: day.isAvailable,
                note: day.note.isEmpty ? nil : day.note,
                windows: day.windows.map {
                    CloudInspectionAvailabilityWindowDTO(
                        start_time: Self.timeFormatter.string(from: $0.startDate),
                        end_time: Self.timeFormatter.string(from: $0.endDate)
                    )
                }
            )
            let response = try await apiClient.upsertInspectionAvailabilityOnCloud(
                date: Self.dayFormatter.string(from: day.date),
                payload: payload
            )
            if let mapped = Self.mapAvailabilityDay(response) {
                cache(mapped, for: month)
            }
            syncError = nil
        } catch {
            cache(day, for: month)
            syncError = "Disponibilità salvata solo localmente: \(error.localizedDescription)"
        }
    }

    func approveRoute(_ routeID: String, month: Date = Date()) async {
        guard apiClient.isCloudConfigured else {
            updateRoute(routeID) { route in
                route.status = .confirmed
                route.rejectionReason = nil
            }
            syncError = "Route aggiornata solo localmente: backend non configurato"
            return
        }

        isSubmittingRouteDecision = true
        defer { isSubmittingRouteDecision = false }

        do {
            _ = try await apiClient.acceptInspectionRouteOnCloud(eventID: routeID)
            await refresh(for: month)
        } catch {
            syncError = error.localizedDescription
        }
    }

    func rejectRoute(_ routeID: String, reason: CATRouteRejectionReason, month: Date = Date()) async {
        guard apiClient.isCloudConfigured else {
            updateRoute(routeID) { route in
                route.status = .needsRecalculation
                route.rejectionReason = reason
            }
            syncError = "Route aggiornata solo localmente: backend non configurato"
            return
        }

        isSubmittingRouteDecision = true
        defer { isSubmittingRouteDecision = false }

        do {
            _ = try await apiClient.rejectInspectionRouteOnCloud(
                eventID: routeID,
                reasonCode: reason.backendCode,
                reason: reason.title
            )
            await refresh(for: month)
        } catch {
            syncError = error.localizedDescription
        }
    }

    func route(withID routeID: String) -> CATRoutePlan? {
        routePlans.first { $0.id == routeID }
    }

    private func updateRoute(_ routeID: String, mutation: (inout CATRoutePlan) -> Void) {
        guard let index = routePlans.firstIndex(where: { $0.id == routeID }) else { return }
        var route = routePlans[index]
        mutation(&route)
        routePlans[index] = route
    }

    private func cache(_ day: CATAvailabilityDay, for month: Date) {
        let key = monthKey(for: month)
        var current = availabilityByMonth[key] ?? []
        if let index = current.firstIndex(where: { $0.id == day.id }) {
            current[index] = day
        } else {
            current.append(day)
        }
        current.sort { $0.date < $1.date }
        availabilityByMonth[key] = current
        objectWillChange.send()
    }

    private func monthKey(for date: Date) -> String {
        Self.monthFormatter.string(from: date)
    }

    private func applyMockState(reason: String) {
        syncError = reason
        territory = Self.mockTerritory(for: configuredEmail)
        routePlans = Self.mockRoutes()
        schedulingRules = .default
        lastGeneratedAt = routePlans.compactMap(\.generatedAt).max()
        availabilityByMonth[monthKey(for: Date())] = Self.defaultAvailability(for: Date(), routes: routePlans)
        objectWillChange.send()
    }
}

private extension CATPlanningStore {
    static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func mapSchedulingRules(_ dto: CloudTenantCATPlannerDTO) -> CATSchedulingRules {
        CATSchedulingRules(
            routeGenerationHour: dto.route_generation_hour,
            routeReviewWindowMinutes: dto.route_review_window_minutes,
            availabilitySlotMinutes: dto.availability_slot_minutes,
            availabilityTolerancePercent: Double(dto.availability_tolerance_percent) / 100.0,
            maxOutsideZoneKilometers: Double(dto.max_outside_zone_kilometers)
        )
    }

    static func mapTerritory(
        tenantDTO: CloudTenantSettingsDTO,
        configuredEmail: String
    ) -> CATTenantTerritorySnapshot {
        let matchedTechnician = tenantDTO.cat_settings.technicians.first {
            $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == configuredEmail
        } ?? tenantDTO.cat_settings.technicians.first

        let poi = CATTechnicianPOI(
            id: matchedTechnician?.id ?? "cat-base",
            displayName: matchedTechnician?.display_name ?? "CAT",
            latitude: matchedTechnician?.latitude ?? 44.6471,
            longitude: matchedTechnician?.longitude ?? 10.9252,
            tenantNames: [tenantDTO.tenant_name]
        )

        let municipalities = tenantDTO.cat_settings.municipalities.map {
            CATMunicipalityCoverage(
                id: $0.id,
                comune: $0.comune,
                provincia: $0.provincia,
                regione: $0.regione,
                latitude: $0.latitude,
                longitude: $0.longitude,
                priority: $0.priority
            )
        }

        return CATTenantTerritorySnapshot(
            poi: poi,
            municipalities: municipalities,
            provinces: Array(Set(municipalities.map(\.provincia))).sorted(),
            regions: Array(Set(municipalities.map(\.regione))).sorted()
        )
    }

    static func mapAvailabilityDay(_ dto: CloudInspectionAvailabilityDayDTO) -> CATAvailabilityDay? {
        guard let date = dayFormatter.date(from: dto.date) else { return nil }
        let windows = dto.windows.compactMap { window -> CATTimeWindow? in
            guard
                let start = timeComponents(from: window.start_time),
                let end = timeComponents(from: window.end_time)
            else { return nil }
            return CATTimeWindow(
                startHour: start.hour,
                startMinute: start.minute,
                endHour: end.hour,
                endMinute: end.minute
            )
        }

        let commitments = dto.external_commitments.compactMap { commitment -> CATExternalCommitment? in
            guard
                let start = timeComponents(from: commitment.start_time),
                let end = timeComponents(from: commitment.end_time)
            else { return nil }
            return CATExternalCommitment(
                id: commitment.id,
                tenantName: commitment.tenant_name ?? "Tenant corrente",
                label: commitment.label,
                window: CATTimeWindow(
                    startHour: start.hour,
                    startMinute: start.minute,
                    endHour: end.hour,
                    endMinute: end.minute
                )
            )
        }

        return CATAvailabilityDay(
            date: date,
            isAvailable: dto.is_available,
            windows: windows,
            note: dto.note ?? "",
            externalCommitments: commitments,
            hasConfirmedRoute: dto.has_confirmed_route
        )
    }

    static func mapRoute(
        _ dto: CloudInspectionRouteDTO,
        fallbackTenantName: String
    ) -> CATRoutePlan? {
        guard let routeDate = dayFormatter.date(from: dto.plan_date) else { return nil }
        let stops = dto.stops.compactMap(mapStop)
        let totalSpanMinutes = max(Int(dto.ends_at.timeIntervalSince(dto.starts_at) / 60), dto.total_duration_minutes)
        let driveMinutes = max(totalSpanMinutes - dto.total_duration_minutes, 0)
        let uniqueMunicipalities = Array(Set(stops.map { "\($0.municipality) (\($0.province))" })).sorted()
        let tenantNames = dto.tenant_names.isEmpty ? [fallbackTenantName] : dto.tenant_names

        return CATRoutePlan(
            id: dto.event_id,
            title: dto.title,
            tenantNames: tenantNames,
            generatedAt: dto.generated_at ?? dto.starts_at,
            reviewDeadline: dto.review_deadline ?? dto.starts_at,
            routeDate: routeDate,
            status: CATRoutePlanStatus(cloudStatus: dto.status),
            rejectionReason: CATRouteRejectionReason(backendCode: dto.rejection_reason_code),
            totalKilometers: dto.total_distance_km,
            driveMinutes: driveMinutes,
            visitMinutes: dto.total_duration_minutes,
            coverageSummary: uniqueMunicipalities.joined(separator: ", "),
            constraints: CATRouteConstraintSummary(
                fixedManualStops: stops.filter(\.manuallyFixed).count,
                outsideZoneStops: stops.filter(\.outsideZone).count,
                respectedWindowsPercent: stops.isEmpty ? 0 : 100,
                crossTenantCommitments: max(tenantNames.count - 1, 0)
            ),
            stops: stops
        )
    }

    static func mapStop(_ dto: CloudInspectionRouteStopDTO) -> CATRouteStop? {
        let plannedWindow = CATTimeWindow(
            startHour: calendarHour(from: dto.starts_at),
            startMinute: calendarMinute(from: dto.starts_at),
            endHour: calendarHour(from: dto.ends_at),
            endMinute: calendarMinute(from: dto.ends_at)
        )
        let preferredWindows = dto.preferred_windows.compactMap { window -> CATTimeWindow? in
            guard
                let start = timeComponents(from: window.start_time),
                let end = timeComponents(from: window.end_time)
            else { return nil }
            return CATTimeWindow(
                startHour: start.hour,
                startMinute: start.minute,
                endHour: end.hour,
                endMinute: end.minute
            )
        }

        return CATRouteStop(
            id: dto.claim_id,
            claimReference: dto.claim_reference ?? dto.claim_id,
            municipality: dto.municipality ?? "",
            province: dto.province ?? "",
            region: dto.region ?? "",
            latitude: dto.latitude ?? 44.6471,
            longitude: dto.longitude ?? 10.9252,
            plannedWindow: plannedWindow,
            preferredWindows: preferredWindows,
            durationMinutes: dto.duration_minutes,
            assetCount: max(dto.asset_count, 1),
            complexity: CATClaimComplexity(rawValue: (dto.complexity ?? "").lowercased()) ?? .medium,
            outsideZone: dto.outside_zone,
            manuallyFixed: dto.manually_fixed,
            redactedLocation: dto.masked_location ?? [dto.municipality, dto.province].compactMap { $0 }.joined(separator: " • "),
            workflow: CATWorkflowStep.defaultInspectionFlow,
            note: dto.note ?? ""
        )
    }

    static func timeComponents(from rawValue: String) -> (hour: Int, minute: Int)? {
        let parts = rawValue.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return (hour, minute)
    }

    static func calendarHour(from date: Date) -> Int {
        Calendar.current.component(.hour, from: date)
    }

    static func calendarMinute(from date: Date) -> Int {
        Calendar.current.component(.minute, from: date)
    }

    static func defaultAvailability(for month: Date, routes: [CATRoutePlan]) -> [CATAvailabilityDay] {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }

        return range.compactMap { day -> CATAvailabilityDay? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { return nil }
            let weekday = calendar.component(.weekday, from: date)
            let isWeekend = weekday == 1 || weekday == 7
            let windows = isWeekend ? [] : [
                CATTimeWindow(startHour: 9, endHour: 11),
                CATTimeWindow(startHour: 11, endHour: 13),
                CATTimeWindow(startHour: 14, endHour: 16)
            ]
            let dayHasConfirmedRoute = routes.contains {
                $0.status == .confirmed && calendar.isDate($0.routeDate, inSameDayAs: date)
            }
            return CATAvailabilityDay(
                date: date,
                isAvailable: !isWeekend,
                windows: windows,
                note: isWeekend ? "Giorno non disponibile" : "",
                externalCommitments: [],
                hasConfirmedRoute: dayHasConfirmedRoute
            )
        }
    }

    static func mockTerritory(for email: String?) -> CATTenantTerritorySnapshot {
        let baseName: String
        if let email, let namePart = email.split(separator: "@").first {
            baseName = namePart.replacingOccurrences(of: ".", with: " ").capitalized
        } else {
            baseName = "CAT Nord"
        }

        let poi = CATTechnicianPOI(
            id: "cat-base",
            displayName: baseName,
            latitude: 44.6471,
            longitude: 10.9252,
            tenantNames: ["Tenant Alfa", "Tenant Beta"]
        )

        let municipalities = [
            CATMunicipalityCoverage(id: "modena", comune: "Modena", provincia: "MO", regione: "Emilia-Romagna", latitude: 44.6471, longitude: 10.9252, priority: 1),
            CATMunicipalityCoverage(id: "carpi", comune: "Carpi", provincia: "MO", regione: "Emilia-Romagna", latitude: 44.7824, longitude: 10.8777, priority: 1),
            CATMunicipalityCoverage(id: "sassuolo", comune: "Sassuolo", provincia: "MO", regione: "Emilia-Romagna", latitude: 44.5432, longitude: 10.7841, priority: 2),
            CATMunicipalityCoverage(id: "rubiera", comune: "Rubiera", provincia: "RE", regione: "Emilia-Romagna", latitude: 44.6511, longitude: 10.7812, priority: 2)
        ]

        return CATTenantTerritorySnapshot(
            poi: poi,
            municipalities: municipalities,
            provinces: Array(Set(municipalities.map(\.provincia))).sorted(),
            regions: Array(Set(municipalities.map(\.regione))).sorted()
        )
    }

    static func mockRoutes() -> [CATRoutePlan] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        let generatedToday = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today) ?? Date()
        let deadlineToday = calendar.date(byAdding: .minute, value: CATSchedulingRules.default.routeReviewWindowMinutes, to: generatedToday) ?? generatedToday
        let generatedTomorrow = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? Date()
        let deadlineTomorrow = calendar.date(byAdding: .minute, value: CATSchedulingRules.default.routeReviewWindowMinutes, to: generatedTomorrow) ?? generatedTomorrow

        return [
            CATRoutePlan(
                id: "route-today",
                title: "Percorso CAT mattina/sera",
                tenantNames: ["Tenant Alfa", "Tenant Beta"],
                generatedAt: generatedToday,
                reviewDeadline: deadlineToday,
                routeDate: today,
                status: .pendingApproval,
                rejectionReason: nil,
                totalKilometers: 76,
                driveMinutes: 142,
                visitMinutes: 110,
                coverageSummary: "Modena, Carpi, Rubiera",
                constraints: CATRouteConstraintSummary(fixedManualStops: 1, outsideZoneStops: 1, respectedWindowsPercent: 83, crossTenantCommitments: 2),
                stops: []
            ),
            CATRoutePlan(
                id: "route-tomorrow",
                title: "Percorso CAT area Modena sud",
                tenantNames: ["Tenant Alfa"],
                generatedAt: generatedTomorrow,
                reviewDeadline: deadlineTomorrow,
                routeDate: tomorrow,
                status: .confirmed,
                rejectionReason: nil,
                totalKilometers: 39,
                driveMinutes: 68,
                visitMinutes: 75,
                coverageSummary: "Sassuolo, Modena",
                constraints: CATRouteConstraintSummary(fixedManualStops: 0, outsideZoneStops: 0, respectedWindowsPercent: 100, crossTenantCommitments: 1),
                stops: []
            )
        ]
    }
}

private extension CATTimeWindow {
    var startDate: Date {
        Calendar.current.date(bySettingHour: startHour, minute: startMinute, second: 0, of: Date()) ?? Date()
    }

    var endDate: Date {
        Calendar.current.date(bySettingHour: endHour, minute: endMinute, second: 0, of: Date()) ?? Date()
    }
}

private extension CATRoutePlanStatus {
    init(cloudStatus: String) {
        switch cloudStatus.lowercased() {
        case "accepted":
            self = .confirmed
        case "rejected":
            self = .rejected
        case "expired", "superseded":
            self = .needsRecalculation
        default:
            self = .pendingApproval
        }
    }
}

private extension CATRouteRejectionReason {
    init?(backendCode: String?) {
        switch backendCode?.lowercased() {
        case "route_too_long":
            self = .tooLong
        case "outside_zone":
            self = .outsideZone
        case "unavailable", "review_window_expired":
            self = .unavailable
        case "impossible":
            self = .impossible
        default:
            return nil
        }
    }

    var backendCode: String {
        switch self {
        case .tooLong: return "route_too_long"
        case .outsideZone: return "outside_zone"
        case .unavailable: return "unavailable"
        case .impossible: return "impossible"
        }
    }
}

private extension CATTenantTerritorySnapshot {
    static let empty = CATTenantTerritorySnapshot(
        poi: CATTechnicianPOI(
            id: "empty",
            displayName: "CAT",
            latitude: 45,
            longitude: 9,
            tenantNames: []
        ),
        municipalities: [],
        provinces: [],
        regions: []
    )
}
