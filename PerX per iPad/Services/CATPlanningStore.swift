//
//  CATPlanningStore.swift
//  PerX per iPad
//
//  Store mock condiviso per dashboard, programmazione e route CAT.
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

    private var availabilityByMonth: [String: [CATAvailabilityDay]] = [:]

    private init() {}

    func configure(for email: String?) {
        let normalizedEmail = email?.lowercased()
        guard configuredEmail != normalizedEmail else { return }

        configuredEmail = normalizedEmail
        territory = Self.mockTerritory(for: normalizedEmail)
        routePlans = Self.mockRoutes()
        lastGeneratedAt = routePlans.map(\.generatedAt).max()

        _ = availability(for: Date())
    }

    func dashboardSnapshot(for date: Date = Date()) -> CATDashboardSnapshot {
        let calendar = Calendar.current
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
        let key = monthKey(for: month)
        if let cached = availabilityByMonth[key] {
            return cached
        }

        let loaded = loadAvailability(for: month)
        availabilityByMonth[key] = loaded
        return loaded
    }

    func availabilityDay(for date: Date) -> CATAvailabilityDay? {
        availability(for: date).first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func updateAvailability(_ day: CATAvailabilityDay, for month: Date) {
        let key = monthKey(for: month)
        var current = availability(for: month)

        if let index = current.firstIndex(where: { $0.id == day.id }) {
            current[index] = day
        } else {
            current.append(day)
        }

        current.sort { $0.date < $1.date }
        availabilityByMonth[key] = current
        persistAvailability(current, for: month)
        objectWillChange.send()
    }

    func approveRoute(_ routeID: String) {
        updateRoute(routeID) { route in
            route.status = .confirmed
            route.rejectionReason = nil
        }
    }

    func rejectRoute(_ routeID: String, reason: CATRouteRejectionReason) {
        updateRoute(routeID) { route in
            route.status = .needsRecalculation
            route.rejectionReason = reason
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

    private func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private func storageKey(for month: Date) -> String {
        let email = configuredEmail ?? "anonymous"
        return "cat_availability_\(email)_\(monthKey(for: month))"
    }

    private func loadAvailability(for month: Date) -> [CATAvailabilityDay] {
        let key = storageKey(for: month)
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([CATAvailabilityDay].self, from: data) {
            return decoded
        }

        let generated = Self.defaultAvailability(for: month, routes: routePlans)
        persistAvailability(generated, for: month)
        return generated
    }

    private func persistAvailability(_ days: [CATAvailabilityDay], for month: Date) {
        let key = storageKey(for: month)
        guard let data = try? JSONEncoder().encode(days) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private extension CATPlanningStore {
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

            let commitments: [CATExternalCommitment]
            switch day % 5 {
            case 0:
                commitments = [
                    CATExternalCommitment(
                        id: "studio-\(day)",
                        tenantName: "Tenant Alfa",
                        label: "Appuntamento manuale",
                        window: CATTimeWindow(startHour: 16, endHour: 18)
                    )
                ]
            case 2:
                commitments = [
                    CATExternalCommitment(
                        id: "studio-beta-\(day)",
                        tenantName: "Tenant Beta",
                        label: "Verifica già confermata",
                        window: CATTimeWindow(startHour: 11, endHour: 13)
                    )
                ]
            default:
                commitments = []
            }

            let windows: [CATTimeWindow]
            if isWeekend {
                windows = []
            } else {
                windows = [
                    CATTimeWindow(startHour: 9, endHour: 11),
                    CATTimeWindow(startHour: 11, endHour: 13),
                    CATTimeWindow(startHour: 14, endHour: 16)
                ]
            }

            let dayHasConfirmedRoute = routes.contains {
                $0.status == .confirmed && calendar.isDate($0.routeDate, inSameDayAs: date)
            }

            return CATAvailabilityDay(
                date: date,
                isAvailable: !isWeekend,
                windows: windows,
                note: isWeekend ? "Giorno non disponibile" : "",
                externalCommitments: commitments,
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
            CATMunicipalityCoverage(
                id: "modena",
                comune: "Modena",
                provincia: "MO",
                regione: "Emilia-Romagna",
                latitude: 44.6471,
                longitude: 10.9252,
                priority: 1
            ),
            CATMunicipalityCoverage(
                id: "carpi",
                comune: "Carpi",
                provincia: "MO",
                regione: "Emilia-Romagna",
                latitude: 44.7824,
                longitude: 10.8777,
                priority: 1
            ),
            CATMunicipalityCoverage(
                id: "sassuolo",
                comune: "Sassuolo",
                provincia: "MO",
                regione: "Emilia-Romagna",
                latitude: 44.5432,
                longitude: 10.7841,
                priority: 2
            ),
            CATMunicipalityCoverage(
                id: "rubiera",
                comune: "Rubiera",
                provincia: "RE",
                regione: "Emilia-Romagna",
                latitude: 44.6511,
                longitude: 10.7812,
                priority: 2
            )
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

        let todayStops = [
            CATRouteStop(
                id: "stop-1",
                claimReference: "SIN-26-0412",
                municipality: "Modena",
                province: "MO",
                region: "Emilia-Romagna",
                latitude: 44.6519,
                longitude: 10.9187,
                plannedWindow: CATTimeWindow(startHour: 9, startMinute: 30, endHour: 10, endMinute: 15),
                preferredWindows: [CATTimeWindow(startHour: 10, endHour: 12)],
                durationMinutes: 30,
                assetCount: 4,
                complexity: .medium,
                outsideZone: false,
                manuallyFixed: false,
                redactedLocation: "Area centro nord",
                workflow: CATWorkflowStep.defaultInspectionFlow,
                note: "Richiesta fascia mattutina."
            ),
            CATRouteStop(
                id: "stop-2",
                claimReference: "SIN-26-0418",
                municipality: "Carpi",
                province: "MO",
                region: "Emilia-Romagna",
                latitude: 44.7832,
                longitude: 10.8794,
                plannedWindow: CATTimeWindow(startHour: 11, startMinute: 10, endHour: 11, endMinute: 50),
                preferredWindows: [CATTimeWindow(startHour: 11, endHour: 13)],
                durationMinutes: 40,
                assetCount: 7,
                complexity: .high,
                outsideZone: false,
                manuallyFixed: true,
                redactedLocation: "Quadrante est",
                workflow: CATWorkflowStep.defaultInspectionFlow,
                note: "Fissato manualmente dal personale studio."
            ),
            CATRouteStop(
                id: "stop-3",
                claimReference: "SIN-26-0423",
                municipality: "Rubiera",
                province: "RE",
                region: "Emilia-Romagna",
                latitude: 44.6511,
                longitude: 10.7812,
                plannedWindow: CATTimeWindow(startHour: 14, startMinute: 20, endHour: 15, endMinute: 0),
                preferredWindows: [CATTimeWindow(startHour: 14, endHour: 16)],
                durationMinutes: 40,
                assetCount: 3,
                complexity: .low,
                outsideZone: true,
                manuallyFixed: false,
                redactedLocation: "Area produttiva sud",
                workflow: CATWorkflowStep.defaultInspectionFlow,
                note: "Fuori zona entro soglia +50 km."
            )
        ]

        let tomorrowStops = [
            CATRouteStop(
                id: "stop-4",
                claimReference: "SIN-26-0429",
                municipality: "Sassuolo",
                province: "MO",
                region: "Emilia-Romagna",
                latitude: 44.5432,
                longitude: 10.7841,
                plannedWindow: CATTimeWindow(startHour: 10, startMinute: 0, endHour: 10, endMinute: 45),
                preferredWindows: [CATTimeWindow(startHour: 10, endHour: 12), CATTimeWindow(startHour: 11, endHour: 13)],
                durationMinutes: 45,
                assetCount: 5,
                complexity: .medium,
                outsideZone: false,
                manuallyFixed: false,
                redactedLocation: "Periferia ovest",
                workflow: CATWorkflowStep.defaultInspectionFlow,
                note: "Due finestre indicate dall'assicurato."
            ),
            CATRouteStop(
                id: "stop-5",
                claimReference: "SIN-26-0431",
                municipality: "Modena",
                province: "MO",
                region: "Emilia-Romagna",
                latitude: 44.6405,
                longitude: 10.9410,
                plannedWindow: CATTimeWindow(startHour: 12, startMinute: 10, endHour: 12, endMinute: 40),
                preferredWindows: [CATTimeWindow(startHour: 12, endHour: 14)],
                durationMinutes: 30,
                assetCount: 2,
                complexity: .low,
                outsideZone: false,
                manuallyFixed: false,
                redactedLocation: "Asse tangenziale",
                workflow: CATWorkflowStep.defaultInspectionFlow,
                note: "Sopralluogo breve."
            )
        ]

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
                constraints: CATRouteConstraintSummary(
                    fixedManualStops: 1,
                    outsideZoneStops: 1,
                    respectedWindowsPercent: 83,
                    crossTenantCommitments: 2
                ),
                stops: todayStops
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
                constraints: CATRouteConstraintSummary(
                    fixedManualStops: 0,
                    outsideZoneStops: 0,
                    respectedWindowsPercent: 100,
                    crossTenantCommitments: 1
                ),
                stops: tomorrowStops
            )
        ]
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
