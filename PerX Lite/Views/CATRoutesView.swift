import SwiftUI

struct CATRoutesView: View {
    @StateObject private var service = CATLiteService()
    @State private var rejectTargetID: String?
    @State private var navigatorRoute: CATRoutePlan?

    private var pendingRoutes: [CATRoutePlan] {
        service.routes.filter { $0.status == .pendingApproval }
    }
    private var confirmedRoutes: [CATRoutePlan] {
        service.routes.filter { $0.status == .confirmed }
    }
    private var otherRoutes: [CATRoutePlan] {
        service.routes.filter { $0.status != .pendingApproval && $0.status != .confirmed }
    }

    var body: some View {
        NavigationStack {
            List {
                if service.routes.isEmpty && !service.isLoading {
                    ContentUnavailableView(
                        "Nessuna route",
                        systemImage: "map",
                        description: Text("Le proposte del planner appariranno qui.")
                    )
                    .listRowBackground(Color.clear)
                }

                if !pendingRoutes.isEmpty {
                    Section("Da approvare") {
                        ForEach(pendingRoutes) { route in
                            pendingRow(route)
                        }
                    }
                }

                if !confirmedRoutes.isEmpty {
                    Section("Confermati") {
                        ForEach(confirmedRoutes) { route in
                            confirmedRow(route)
                        }
                    }
                }

                if !otherRoutes.isEmpty {
                    Section("Storico") {
                        ForEach(otherRoutes) { route in
                            historicalRow(route)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Route CAT")
            .refreshable { await service.fetch() }
            .task { await service.fetch() }
            .overlay {
                if service.isLoading && service.routes.isEmpty {
                    ProgressView()
                }
            }
            .alert("Errore", isPresented: .constant(service.syncError != nil)) {
                Button("OK") { service.dismissError() }
            } message: {
                Text(service.syncError ?? "")
            }
            .confirmationDialog(
                "Motivo del rifiuto",
                isPresented: Binding(get: { rejectTargetID != nil }, set: { if !$0 { rejectTargetID = nil } }),
                titleVisibility: .visible
            ) {
                ForEach(CATRouteRejectionReason.allCases) { reason in
                    Button(reason.title) {
                        guard let id = rejectTargetID else { return }
                        rejectTargetID = nil
                        Task { await service.reject(id, reason: reason) }
                    }
                }
            } message: {
                Text("Il planner userà questa motivazione per proporre una nuova combinazione.")
            }
            .navigationDestination(item: $navigatorRoute) { route in
                CATNavigatorView(route: route)
            }
        }
    }

    // MARK: - Route rows

    private func pendingRow(_ route: CATRoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            routeHeader(route)
            routeMetrics(route)
            if let reason = route.rejectionReason {
                Text("Ultimo rifiuto: \(reason.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button {
                    Task { await service.approve(route.id) }
                } label: {
                    Label("Approva", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(service.isSubmitting)

                Button {
                    rejectTargetID = route.id
                } label: {
                    Label("Rifiuta", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(service.isSubmitting)
            }
        }
        .padding(.vertical, 6)
    }

    private func confirmedRow(_ route: CATRoutePlan) -> some View {
        Button { navigatorRoute = route } label: {
            VStack(alignment: .leading, spacing: 10) {
                routeHeader(route)
                routeMetrics(route)
                Label("Apri navigatore", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func historicalRow(_ route: CATRoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            routeHeader(route)
            routeMetrics(route)
        }
        .padding(.vertical, 4)
        .opacity(0.65)
    }

    // MARK: - Sub-views

    private func routeHeader(_ route: CATRoutePlan) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(route.title)
                    .font(.headline)
                Text(route.routeDate, format: .dateTime.weekday(.wide).day().month())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(route.coverageSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if route.tenantNames.count > 1 {
                    Text(route.tenantNames.joined(separator: " • "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            statusBadge(route.status)
        }
    }

    private func routeMetrics(_ route: CATRoutePlan) -> some View {
        HStack(spacing: 18) {
            metricChip("\(route.totalAppointments)", icon: "mappin.circle.fill", tint: .blue)
            metricChip("\(Int(route.totalKilometers)) km", icon: "road.lanes", tint: .green)
            metricChip("\(route.driveMinutes) min", icon: "car.fill", tint: .orange)
            if route.constraints.outsideZoneStops > 0 {
                metricChip("\(route.constraints.outsideZoneStops) extra", icon: "exclamationmark.triangle.fill", tint: .red)
            }
        }
    }

    private func metricChip(_ value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(value).fontWeight(.semibold)
        }
        .font(.caption)
    }

    private func statusBadge(_ status: CATRoutePlanStatus) -> some View {
        let color: Color = {
            switch status {
            case .pendingApproval:    return .orange
            case .confirmed:          return .green
            case .needsRecalculation: return .purple
            case .rejected:           return .red
            }
        }()
        return Text(status.title)
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

