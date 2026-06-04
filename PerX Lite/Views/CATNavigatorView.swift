import SwiftUI
import MapKit

struct CATNavigatorView: View {
    let route: CATRoutePlan

    // "apple" or "google" — stored persistently so it survives app restart
    @AppStorage("liteNavigationApp") private var navAppRaw: String = NavigationApp.apple.rawValue
    @State private var activeStopID: String?
    @State private var workflowStop: CATRouteStop?
    @State private var mapPosition: MapCameraPosition = .automatic

    private var activeStop: CATRouteStop? {
        guard let id = activeStopID else { return route.stops.first }
        return route.stops.first { $0.id == id } ?? route.stops.first
    }

    private var navApp: NavigationApp {
        NavigationApp(rawValue: navAppRaw) ?? .apple
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                routeMap
                    .frame(height: 280)

                if let stop = activeStop {
                    nextStopCard(stop)
                        .padding()
                }

                stopsSequence
                    .padding(.horizontal)
                    .padding(.bottom, 32)
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            activeStopID = route.stops.first?.id
            fitAllStops()
        }
        .sheet(item: $workflowStop) { stop in
            CATWorkflowSheet(stop: stop)
        }
    }

    // MARK: - Map

    private var routeMap: some View {
        Map(position: $mapPosition) {
            // Sequential numbered pins
            ForEach(Array(route.stops.enumerated()), id: \.element.id) { index, stop in
                Annotation("\(index + 1)", coordinate: stop.coordinate, anchor: .center) {
                    ZStack {
                        Circle()
                            .fill(pinColor(for: stop))
                            .frame(width: 34, height: 34)
                            .shadow(radius: 3)
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                    .onTapGesture {
                        activeStopID = stop.id
                    }
                }
            }

            // Visual route line (straight-line sequence — road routing happens in the external app)
            if route.stops.count > 1 {
                MapPolyline(coordinates: route.stops.map(\.coordinate))
                    .stroke(.blue.opacity(0.55), lineWidth: 3)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
    }

    private func pinColor(for stop: CATRouteStop) -> Color {
        if stop.id == activeStopID { return .accentColor }
        if stop.outsideZone { return .orange }
        return .blue
    }

    // MARK: - Next-stop card

    private func nextStopCard(_ stop: CATRouteStop) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Prossimo sopralluogo", systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                complexityBadge(stop.complexity)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(stop.claimReference)
                    .font(.title3.bold())
                Text("\(stop.municipality) (\(stop.province))")
                    .foregroundStyle(.secondary)
                if !stop.redactedLocation.isEmpty {
                    Text(stop.redactedLocation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                infoChip(stop.plannedWindow.label, icon: "clock")
                infoChip("\(stop.durationMinutes) min", icon: "timer")
                infoChip("\(stop.assetCount) beni", icon: "archivebox")
            }

            if !stop.note.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(stop.note)
                        .font(.caption)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 10) {
                Button {
                    launchNavigation(to: stop)
                } label: {
                    Label("Avvia navigazione", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    workflowStop = stop
                } label: {
                    Label("Workflow", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Stops list

    private var stopsSequence: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sequenza")
                .font(.headline)
                .padding(.top, 8)
                .padding(.bottom, 2)

            ForEach(Array(route.stops.enumerated()), id: \.element.id) { index, stop in
                Button {
                    activeStopID = stop.id
                    focusMap(on: stop)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(stop.id == activeStopID ? Color.accentColor : Color(.tertiarySystemFill))
                                .frame(width: 32, height: 32)
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(stop.id == activeStopID ? .white : .primary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(stop.claimReference)
                                    .font(.subheadline.weight(.semibold))
                                if stop.outsideZone {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption2)
                                }
                                if stop.manuallyFixed {
                                    Image(systemName: "pin.fill")
                                        .foregroundStyle(.red)
                                        .font(.caption2)
                                }
                            }
                            Text("\(stop.municipality) • \(stop.plannedWindow.label) • \(stop.durationMinutes) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        stop.id == activeStopID
                            ? Color.accentColor.opacity(0.1)
                            : Color(.secondarySystemGroupedBackground)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Navigation launch

    private func launchNavigation(to stop: CATRouteStop) {
        let lat = stop.latitude
        let lon = stop.longitude

        let targetURL: URL?
        switch navApp {
        case .apple:
            targetURL = URL(string: "maps://?daddr=\(lat),\(lon)&dirflg=d")
        case .google:
            let googleURL = URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving")
            let googleAvailable = googleURL.map { UIApplication.shared.canOpenURL($0) } ?? false
            // Fallback to Apple Maps if Google Maps is not installed
            targetURL = googleAvailable
                ? googleURL
                : URL(string: "maps://?daddr=\(lat),\(lon)&dirflg=d")
        }

        if let url = targetURL {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Map helpers

    private func fitAllStops() {
        let coords = route.stops.map(\.coordinate)
        guard !coords.isEmpty else { return }
        if coords.count == 1 {
            mapPosition = .region(MKCoordinateRegion(
                center: coords[0],
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
            return
        }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        mapPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.8, 0.08),
                longitudeDelta: max((maxLon - minLon) * 1.8, 0.08)
            )
        ))
    }

    private func focusMap(on stop: CATRouteStop) {
        mapPosition = .region(MKCoordinateRegion(
            center: stop.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        ))
    }

    // MARK: - Helpers

    private func infoChip(_ label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func complexityBadge(_ complexity: CATClaimComplexity) -> some View {
        let color: Color = {
            switch complexity {
            case .low:    return .green
            case .medium: return .orange
            case .high:   return .red
            }
        }()
        return Text(complexity.title)
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Workflow sheet

private struct CATWorkflowSheet: View {
    let stop: CATRouteStop
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Scheda sopralluogo") {
                    LabeledContent("Sinistro", value: stop.claimReference)
                    LabeledContent("Comune", value: "\(stop.municipality) (\(stop.province))")
                    LabeledContent("Durata", value: "\(stop.durationMinutes) min")
                    LabeledContent("Beni", value: "\(stop.assetCount)")
                    LabeledContent("Complessità", value: stop.complexity.title)
                    LabeledContent("Fascia", value: stop.plannedWindow.label)
                }

                Section("Workflow operativo") {
                    ForEach(Array(stop.workflow.enumerated()), id: \.element.id) { index, step in
                        VStack(alignment: .leading, spacing: 4) {
                            Label {
                                Text("\(index + 1). \(step.title)")
                                    .font(.subheadline.weight(.semibold))
                            } icon: {
                                Image(systemName: step.isRequired ? "checkmark.circle" : "circle")
                                    .foregroundStyle(step.isRequired ? .blue : .secondary)
                            }
                            Text(step.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 28)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !stop.note.isEmpty {
                    Section("Note") {
                        Text(stop.note)
                    }
                }
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
