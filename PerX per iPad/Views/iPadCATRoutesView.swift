//
//  iPadCATRoutesView.swift
//  PerX per iPad
//
//  Vista dedicata alla revisione delle route e al workflow sopralluogo CAT.
//

import SwiftUI
import MapKit

struct iPadCATRoutesView: View {
    @EnvironmentObject private var session: SessionCoordinator
    @StateObject private var store = CATPlanningStore.shared
    @State private var selectedRouteID: String?
    @State private var workflowStop: CATRouteStop?
    @State private var routeCameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 44.6471, longitude: 10.9252),
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
        )
    )
    @State private var rejectionRouteID: String?

    var body: some View {
        HStack(spacing: 0) {
            routeList
                .frame(width: 360)

            Divider()

            routeDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Route")
        .task {
            store.configure(for: session.currentUserEmail)
            if selectedRouteID == nil {
                selectedRouteID = store.routePlans.first?.id
            }
            updateRegion()
        }
        .onChange(of: selectedRouteID) {
            updateRegion()
        }
        .sheet(item: $workflowStop) { stop in
            CATInspectionWorkflowSheet(stop: stop)
        }
        .confirmationDialog(
            "Motivo del rifiuto",
            isPresented: Binding(
                get: { rejectionRouteID != nil },
                set: { if !$0 { rejectionRouteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(CATRouteRejectionReason.allCases) { reason in
                Button(reason.title) {
                    guard let routeID = rejectionRouteID else { return }
                    store.rejectRoute(routeID, reason: reason)
                    rejectionRouteID = nil
                }
            }
        } message: {
            Text("Il planner userà questa motivazione per proporre una nuova combinazione.")
        }
    }

    private var selectedRoute: CATRoutePlan? {
        guard let selectedRouteID else { return store.routePlans.first }
        return store.route(withID: selectedRouteID) ?? store.routePlans.first
    }

    @ViewBuilder
    private var routeList: some View {
        List(selection: $selectedRouteID) {
            Section {
                ForEach(store.routePlans) { route in
                    Button {
                        selectedRouteID = route.id
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(route.title)
                                    .font(.headline)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                statusBadge(for: route.status)
                            }

                            Text(route.routeDate, format: .dateTime.weekday(.wide).day().month())
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(spacing: 12) {
                                compactMetric("\(route.totalAppointments)", label: "stop")
                                compactMetric("\(Int(route.totalKilometers)) km", label: "km")
                                compactMetric("\(route.constraints.respectedWindowsPercent)%", label: "fasce")
                            }

                            if let reason = route.rejectionReason {
                                Text("Ultimo motivo: \(reason.title)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        (selectedRouteID == route.id ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                }
            } header: {
                Text("Proposte e percorsi")
            } footer: {
                Text("Prima della conferma i dettagli sono limitati a comune, area generica e vincoli operativi.")
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var routeDetail: some View {
        if let route = selectedRoute {
            ScrollView {
                VStack(spacing: 20) {
                    routeSummary(route)
                    routeMap(route)
                    routeConstraints(route)
                    routeStops(route)
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "Nessuna route",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                description: Text("Quando verranno generate le proposte del planner, appariranno qui.")
            )
        }
    }

    private func routeSummary(_ route: CATRoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(route.title)
                        .font(.title2.bold())
                    Text(route.coverageSummary)
                        .foregroundColor(.secondary)
                    Text("Tenant coinvolti: \(route.tenantNames.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    statusBadge(for: route.status)
                    Text("Generata \(route.generatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Scade \(route.reviewDeadline.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 14) {
                highlightedMetric("\(route.totalAppointments)", label: "sopralluoghi", color: .blue)
                highlightedMetric("\(Int(route.totalKilometers)) km", label: "stimati", color: .green)
                highlightedMetric("\(route.driveMinutes)m", label: "guida", color: .orange)
                highlightedMetric("\(route.visitMinutes)m", label: "sul posto", color: .purple)
            }

            HStack(spacing: 12) {
                if route.status == .pendingApproval {
                    Button {
                        store.approveRoute(route.id)
                    } label: {
                        Label("Approva", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        rejectionRouteID = route.id
                    } label: {
                        Label("Rifiuta", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                } else if route.status == .confirmed {
                    Label("Percorso confermato e pronto per l’esecuzione", systemImage: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                } else {
                    Label("In attesa di nuova proposta del planner", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }

                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }

    private func routeMap(_ route: CATRoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Sequenza route", systemImage: "map")
                .font(.headline)

            Map(position: $routeCameraPosition) {
                ForEach(route.stops) { stop in
                    Marker("", coordinate: stop.coordinate)
                        .tint(stop.outsideZone ? .orange : .blue)
                }
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Le coordinate mostrate sono approssimate al comune finché il CAT non accetta il percorso.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }

    private func routeConstraints(_ route: CATRoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Compatibilità e vincoli", systemImage: "shield.lefthalf.filled")
                .font(.headline)

            constraintRow("Finestre assicurato rispettate", value: "\(route.constraints.respectedWindowsPercent)%")
            constraintRow("Sopralluoghi fuori zona", value: "\(route.constraints.outsideZoneStops)")
            constraintRow("Sopralluoghi fissati manualmente", value: "\(route.constraints.fixedManualStops)")
            constraintRow("Impegni altri tenant considerati", value: "\(route.constraints.crossTenantCommitments)")

            Divider()

            Text("Il mock planner incorpora la logica base di disponibilità 2h, margine 50%, blocchi manuali inderogabili e carichi multi-tenant.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }

    private func routeStops(_ route: CATRoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Sopralluoghi in sequenza", systemImage: "list.number")
                .font(.headline)

            ForEach(Array(route.stops.enumerated()), id: \.element.id) { index, stop in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1). \(stop.claimReference)")
                                .font(.headline)
                            Text("\(stop.municipality) (\(stop.province)) • \(stop.redactedLocation)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if stop.manuallyFixed {
                            tag("Manuale", color: .red)
                        }
                        if stop.outsideZone {
                            tag("Fuori zona", color: .orange)
                        }
                    }

                    HStack(spacing: 12) {
                        tag(stop.plannedWindow.label, color: .blue)
                        tag("\(stop.durationMinutes) min", color: .purple)
                        tag("\(stop.assetCount) beni", color: .green)
                        tag("Complessità \(stop.complexity.title)", color: .gray)
                    }

                    Text("Fasce preferite: \(stop.preferredWindows.map(\.expandedLabel).joined(separator: " • "))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !stop.note.isEmpty {
                        Text(stop.note)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        workflowStop = stop
                    } label: {
                        Label("Apri workflow sopralluogo", systemImage: "checklist")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                .cornerRadius(16)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }

    private func statusBadge(for status: CATRoutePlanStatus) -> some View {
        let color: Color
        switch status {
        case .pendingApproval: color = .orange
        case .confirmed: color = .green
        case .needsRecalculation: color = .purple
        case .rejected: color = .red
        }

        return Text(status.title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func tag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func compactMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
            Text(label.uppercased())
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func highlightedMetric(_ value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.12))
        .cornerRadius(14)
    }

    private func constraintRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
        .font(.subheadline)
    }

    private func updateRegion() {
        guard let selectedRoute else { return }
        let latitudes = selectedRoute.stops.map(\.latitude)
        let longitudes = selectedRoute.stops.map(\.longitude)
        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max() else { return }

        routeCameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: (minLat + maxLat) / 2,
                    longitude: (minLon + maxLon) / 2
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: max((maxLat - minLat) * 1.8, 0.12),
                    longitudeDelta: max((maxLon - minLon) * 1.8, 0.12)
                )
            ),
        )
    }
}

private struct CATInspectionWorkflowSheet: View {
    let stop: CATRouteStop
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Scheda sopralluogo") {
                    LabeledContent("Sinistro", value: stop.claimReference)
                    LabeledContent("Area", value: "\(stop.municipality) (\(stop.province)) • \(stop.redactedLocation)")
                    LabeledContent("Durata", value: "\(stop.durationMinutes) min")
                    LabeledContent("Beni", value: "\(stop.assetCount)")
                    LabeledContent("Complessità", value: stop.complexity.title)
                }

                Section("Workflow operativo") {
                    ForEach(Array(stop.workflow.enumerated()), id: \.element.id) { index, step in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(index + 1). \(step.title)")
                                .font(.headline)
                            Text(step.detail)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Dati previsti in fase esecutiva") {
                    Label("Dati assicurato e indirizzo completo solo dopo conferma route", systemImage: "lock.fill")
                    Label("Checklist foto/video e note guidate", systemImage: "camera.fill")
                    Label("Esito visita, anomalie e passaggio al perito", systemImage: "arrowshape.turn.up.right.fill")
                }
                .font(.subheadline)
            }
            .navigationTitle("Workflow CAT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}
