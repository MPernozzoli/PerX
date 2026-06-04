import Foundation
import Combine

@MainActor
final class CATLiteService: ObservableObject {
    @Published private(set) var routes: [CATRoutePlan] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var syncError: String?

    func dismissError() { syncError = nil }

    func fetch() async {
        isLoading = true
        defer { isLoading = false }
        syncError = nil
        do {
            let dto: RouteListDTO = try await APIClient.shared.get("/api/v1/inspections/routes")
            routes = dto.items.compactMap(Self.mapRoute)
        } catch {
            if routes.isEmpty { applyMock() }
            syncError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func approve(_ routeID: String) async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let _: RouteDTO = try await APIClient.shared.post(
                "/api/v1/inspections/routes/\(routeID)/accept",
                body: EmptyBody()
            )
            await fetch()
        } catch {
            syncError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func reject(_ routeID: String, reason: CATRouteRejectionReason) async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let _: RouteDTO = try await APIClient.shared.post(
                "/api/v1/inspections/routes/\(routeID)/reject",
                body: RouteDecisionBody(reason_code: reason.backendCode, reason: reason.title)
            )
            await fetch()
        } catch {
            syncError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Mock fallback

    private func applyMock() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let plusHour: (Date) -> Date = { cal.date(byAdding: .hour, value: 1, to: $0) ?? $0 }

        routes = [
            CATRoutePlan(
                id: "mock-today", title: "Percorso CAT – mattina",
                tenantNames: ["Tenant Alfa"],
                generatedAt: today, reviewDeadline: plusHour(today), routeDate: today,
                status: .pendingApproval, rejectionReason: nil,
                totalKilometers: 76, driveMinutes: 142, visitMinutes: 110,
                coverageSummary: "Modena, Carpi, Rubiera",
                constraints: CATRouteConstraintSummary(
                    fixedManualStops: 1, outsideZoneStops: 1,
                    respectedWindowsPercent: 83, crossTenantCommitments: 2),
                stops: Self.mockStops()
            ),
            CATRoutePlan(
                id: "mock-tomorrow", title: "Percorso CAT – Modena sud",
                tenantNames: ["Tenant Alfa"],
                generatedAt: tomorrow, reviewDeadline: plusHour(tomorrow), routeDate: tomorrow,
                status: .confirmed, rejectionReason: nil,
                totalKilometers: 39, driveMinutes: 68, visitMinutes: 75,
                coverageSummary: "Sassuolo, Modena",
                constraints: CATRouteConstraintSummary(
                    fixedManualStops: 0, outsideZoneStops: 0,
                    respectedWindowsPercent: 100, crossTenantCommitments: 1),
                stops: Self.mockStops()
            ),
        ]
    }

    static func mockStops() -> [CATRouteStop] {
        [
            CATRouteStop(
                id: "stop-1", claimReference: "SIN-2024-001",
                municipality: "Modena", province: "MO",
                latitude: 44.6471, longitude: 10.9252,
                plannedWindow: CATTimeWindow(startHour: 9, endHour: 11),
                durationMinutes: 45, assetCount: 3, complexity: .medium,
                outsideZone: false, manuallyFixed: false,
                redactedLocation: "Via Roma area", note: "",
                workflow: CATWorkflowStep.defaultInspectionFlow
            ),
            CATRouteStop(
                id: "stop-2", claimReference: "SIN-2024-002",
                municipality: "Carpi", province: "MO",
                latitude: 44.7824, longitude: 10.8777,
                plannedWindow: CATTimeWindow(startHour: 11, endHour: 13),
                durationMinutes: 30, assetCount: 2, complexity: .low,
                outsideZone: false, manuallyFixed: false,
                redactedLocation: "Centro Carpi", note: "",
                workflow: CATWorkflowStep.defaultInspectionFlow
            ),
            CATRouteStop(
                id: "stop-3", claimReference: "SIN-2024-003",
                municipality: "Rubiera", province: "RE",
                latitude: 44.6511, longitude: 10.7812,
                plannedWindow: CATTimeWindow(startHour: 14, endHour: 16),
                durationMinutes: 35, assetCount: 4, complexity: .high,
                outsideZone: true, manuallyFixed: false,
                redactedLocation: "Via Emilia est", note: "Accesso difficile",
                workflow: CATWorkflowStep.defaultInspectionFlow
            ),
        ]
    }
}

// MARK: - Cloud DTOs (private — used only for API parsing)

private extension CATLiteService {

    struct EmptyBody: Encodable {}

    struct RouteDecisionBody: Encodable {
        let reason_code: String
        let reason: String?
    }

    struct RouteListDTO: Decodable {
        let items: [RouteDTO]
        let total: Int
    }

    struct RouteDTO: Decodable {
        let event_id: String
        let title: String
        let plan_date: String
        let generated_at: Date?
        let starts_at: Date
        let ends_at: Date
        let review_deadline: Date?
        let status: String
        let total_distance_km: Double
        let total_duration_minutes: Int
        let tenant_names: [String]
        let stops: [StopDTO]
        let rejection_reason_code: String?
    }

    struct StopDTO: Decodable {
        let claim_id: String
        let claim_reference: String?
        let starts_at: Date
        let ends_at: Date
        let municipality: String?
        let province: String?
        let latitude: Double?
        let longitude: Double?
        let masked_location: String?
        let outside_zone: Bool
        let duration_minutes: Int
        let asset_count: Int
        let complexity: String?
        let manually_fixed: Bool
        let note: String?
        let preferred_windows: [PreferredWindowDTO]
    }

    struct PreferredWindowDTO: Decodable {
        let start_time: String
        let end_time: String
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func mapRoute(_ dto: RouteDTO) -> CATRoutePlan? {
        guard let routeDate = dayFormatter.date(from: dto.plan_date) else { return nil }
        let stops = dto.stops.compactMap(mapStop)
        let spanMinutes = max(Int(dto.ends_at.timeIntervalSince(dto.starts_at) / 60), dto.total_duration_minutes)
        let driveMinutes = max(spanMinutes - dto.total_duration_minutes, 0)
        let locations = Array(Set(stops.map { "\($0.municipality) (\($0.province))" })).sorted()

        return CATRoutePlan(
            id: dto.event_id,
            title: dto.title,
            tenantNames: dto.tenant_names,
            generatedAt: dto.generated_at ?? dto.starts_at,
            reviewDeadline: dto.review_deadline ?? dto.starts_at,
            routeDate: routeDate,
            status: CATRoutePlanStatus(cloudStatus: dto.status),
            rejectionReason: CATRouteRejectionReason(backendCode: dto.rejection_reason_code),
            totalKilometers: dto.total_distance_km,
            driveMinutes: driveMinutes,
            visitMinutes: dto.total_duration_minutes,
            coverageSummary: locations.joined(separator: ", "),
            constraints: CATRouteConstraintSummary(
                fixedManualStops: stops.filter(\.manuallyFixed).count,
                outsideZoneStops: stops.filter(\.outsideZone).count,
                respectedWindowsPercent: 100,
                crossTenantCommitments: max(dto.tenant_names.count - 1, 0)
            ),
            stops: stops
        )
    }

    static func mapStop(_ dto: StopDTO) -> CATRouteStop? {
        let cal = Calendar.current
        let window = CATTimeWindow(
            startHour: cal.component(.hour, from: dto.starts_at),
            startMinute: cal.component(.minute, from: dto.starts_at),
            endHour: cal.component(.hour, from: dto.ends_at),
            endMinute: cal.component(.minute, from: dto.ends_at)
        )
        let fallbackLocation = [dto.municipality, dto.province]
            .compactMap { $0 }
            .joined(separator: " • ")
        return CATRouteStop(
            id: dto.claim_id,
            claimReference: dto.claim_reference ?? dto.claim_id,
            municipality: dto.municipality ?? "",
            province: dto.province ?? "",
            latitude: dto.latitude ?? 44.6471,
            longitude: dto.longitude ?? 10.9252,
            plannedWindow: window,
            durationMinutes: dto.duration_minutes,
            assetCount: max(dto.asset_count, 1),
            complexity: CATClaimComplexity(rawValue: (dto.complexity ?? "").lowercased()) ?? .medium,
            outsideZone: dto.outside_zone,
            manuallyFixed: dto.manually_fixed,
            redactedLocation: dto.masked_location ?? fallbackLocation,
            note: dto.note ?? "",
            workflow: CATWorkflowStep.defaultInspectionFlow
        )
    }
}
