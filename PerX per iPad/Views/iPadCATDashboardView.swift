//
//  iPadCATDashboardView.swift
//  PerX per iPad
//
//  Dashboard dedicata al CAT con route, copertura e disponibilità.
//

import SwiftUI
import MapKit

struct iPadCATDashboardView: View {
    @EnvironmentObject private var session: SessionCoordinator
    @StateObject private var store = CATPlanningStore.shared
    @State private var mapCameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 44.6471, longitude: 10.9252),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                statsGrid

                HStack(alignment: .top, spacing: 20) {
                    pendingRouteCard
                        .frame(maxWidth: .infinity, alignment: .top)

                    territoryCard
                        .frame(maxWidth: .infinity, alignment: .top)
                }

                HStack(alignment: .top, spacing: 20) {
                    weekAvailabilityCard
                        .frame(maxWidth: .infinity, alignment: .top)

                    policyCard
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dashboard CAT")
        .task {
            store.configure(for: session.currentUserEmail)
            await store.refresh()
            updateMapRegion()
        }
        .onChange(of: store.territory.municipalities.count) {
            updateMapRegion()
        }
    }

    private var dashboard: CATDashboardSnapshot {
        store.dashboardSnapshot()
    }

    private var nextAvailabilityDays: [CATAvailabilityDay] {
        let today = Calendar.current.startOfDay(for: Date())
        return store.availability(for: today).filter { $0.date >= today }.prefix(5).map { $0 }
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Operatività CAT")
                        .font(.title2.bold())
                    Text(session.currentUserName ?? session.currentCloudProfile?.displayName ?? "Tecnico CAT")
                        .font(.headline)
                        .foregroundColor(.secondary)
                Text("Le route vengono proposte alle 09:00, con revisione entro 1 ora e dati sensibili oscurati fino alla conferma.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let syncError = store.syncError {
                        Text(syncError)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    if let lastGeneratedAt = store.lastGeneratedAt {
                        Label {
                            Text(lastGeneratedAt, style: .time)
                        } icon: {
                            Image(systemName: "clock.badge.checkmark")
                        }
                    }

                    Text(Date(), style: .date)
                        .font(.headline)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                badge("Multi-tenant", color: .indigo)
                badge("No remoto", color: .orange)
                badge("Fuori zona max 50 km", color: .teal)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }

    @ViewBuilder
    private var statsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 16
        ) {
            StatCard(
                title: "Sopralluoghi Oggi",
                value: "\(dashboard.appointmentsToday)",
                icon: "binoculars.fill",
                color: .blue
            )

            StatCard(
                title: "Da Approvare",
                value: "\(dashboard.pendingApprovals)",
                icon: "checkmark.seal.trianglebadge.exclamationmark",
                color: .orange
            )

            StatCard(
                title: "Comuni Assegnati",
                value: "\(dashboard.assignedMunicipalities)",
                icon: "map.fill",
                color: .green
            )

            StatCard(
                title: "Fuori Zona",
                value: "\(dashboard.outsideZoneStops)",
                icon: "arrow.up.right.circle.fill",
                color: .purple
            )
        }
    }

    @ViewBuilder
    private var pendingRouteCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Proposta route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.headline)

                Spacer()

                if let route = dashboard.nextPendingRoute {
                    statusCapsule(route.status.title, color: .orange)
                } else {
                    statusCapsule("Nessuna in attesa", color: .green)
                }
            }

            if let route = dashboard.nextPendingRoute {
                VStack(alignment: .leading, spacing: 10) {
                    Text(route.title)
                        .font(.title3.bold())

                    Label(route.coverageSummary, systemImage: "map")
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        routeMetric("\(route.totalAppointments)", label: "stop")
                        routeMetric("\(Int(route.totalKilometers)) km", label: "km")
                        routeMetric("\(route.driveMinutes)m", label: "guida")
                        routeMetric("\(route.visitMinutes)m", label: "rilievo")
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vincoli applicati")
                            .font(.subheadline.bold())
                        Text("Finestre rispettate: \(route.constraints.respectedWindowsPercent)%")
                        Text("Fissati manualmente: \(route.constraints.fixedManualStops)")
                        Text("Impegni cross-tenant: \(route.constraints.crossTenantCommitments)")
                        Text("Fuori zona: \(route.constraints.outsideZoneStops)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await store.approveRoute(route.id, month: route.routeDate)
                            }
                        } label: {
                            Label("Approva proposta", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isSubmittingRouteDecision)

                        Button {
                            Task {
                                await store.rejectRoute(route.id, reason: .tooLong, month: route.routeDate)
                            }
                        } label: {
                            Label("Ricalcola", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isSubmittingRouteDecision)
                    }

                    Text("Fino all’approvazione vengono mostrati solo comune e area indicativa; nome assicurato e indirizzo restano nascosti.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let confirmed = dashboard.nextConfirmedRoute {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nessuna nuova proposta in coda.")
                        .font(.subheadline)
                    Text("La prossima route confermata è \(confirmed.title.lowercased()) per \(confirmed.routeDate.formatted(date: .abbreviated, time: .omitted)).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                ContentUnavailableView(
                    "Nessuna route",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                    description: Text("Quando il planner genera una proposta, apparirà qui.")
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }

    @ViewBuilder
    private var territoryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Copertura territoriale", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                Spacer()
                Text(store.territory.regions.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Map(position: $mapCameraPosition) {
                ForEach(territoryAnnotations) { item in
                    Marker("", coordinate: item.coordinate)
                        .tint(item.tint)
                }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Comuni di competenza")
                    .font(.subheadline.bold())
                ForEach(store.territory.municipalities.prefix(4)) { municipality in
                    HStack {
                        Text("\(municipality.comune) (\(municipality.provincia))")
                        Spacer()
                        Text(municipality.priority == 1 ? "Primario" : "Supporto")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }

    @ViewBuilder
    private var weekAvailabilityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Disponibilità prossimi giorni", systemImage: "calendar.badge.clock")
                .font(.headline)

            ForEach(nextAvailabilityDays) { day in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(day.date, format: .dateTime.weekday(.wide).day().month())
                            .font(.subheadline.bold())
                        Spacer()
                        if day.hasConfirmedRoute {
                            statusCapsule("Route confermata", color: .green)
                        } else if day.isAvailable {
                            statusCapsule("Disponibile", color: .blue)
                        } else {
                            statusCapsule("Non disponibile", color: .gray)
                        }
                    }

                    if day.isAvailable {
                        Text(day.windows.map(\.expandedLabel).joined(separator: " • "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !day.externalCommitments.isEmpty {
                        Text("Impegni altri tenant: \(day.externalCommitments.map { "\($0.tenantName) \($0.window.label)" }.joined(separator: " • "))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }

    @ViewBuilder
    private var policyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Regole planner", systemImage: "slider.horizontal.3")
                .font(.headline)

            policyRow("Generazione route", value: "ore \(String(format: "%02d:00", store.schedulingRules.routeGenerationHour))")
            policyRow("Review CAT", value: "\(store.schedulingRules.routeReviewWindowMinutes) minuti")
            policyRow("Slot disponibilità", value: "\(store.schedulingRules.availabilitySlotMinutes / 60) ore")
            policyRow("Margine sulle fasce", value: "\(Int(store.schedulingRules.availabilityTolerancePercent * 100))%")
            policyRow("Fuori zona", value: "max \(Int(store.schedulingRules.maxOutsideZoneKilometers)) km")

            Divider()

            Text("In questo step il sistema è mockato ma la struttura dati è pronta per integrare territori tenant, scelte assicurato, route approval e workflow in campo.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }

    private var territoryAnnotations: [CoverageAnnotation] {
        let municipalityAnnotations = store.territory.municipalities.map {
            CoverageAnnotation(id: $0.id, coordinate: $0.coordinate, tint: .green)
        }
        let poi = CoverageAnnotation(id: store.territory.poi.id, coordinate: store.territory.poi.coordinate, tint: .red)
        return [poi] + municipalityAnnotations
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func statusCapsule(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func routeMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label.uppercased())
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }

    private func policyRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
        .font(.subheadline)
    }

    private func updateMapRegion() {
        guard let municipality = store.territory.municipalities.first else { return }
        mapCameraPosition = .region(
            MKCoordinateRegion(
                center: municipality.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.45, longitudeDelta: 0.45)
            )
        )
    }
}

private struct CoverageAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let tint: Color
}
