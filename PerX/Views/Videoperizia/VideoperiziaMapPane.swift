import SwiftUI
import MapKit
import CoreLocation

/// Mappa con doppio pin: indirizzo del sinistro (blu) e posizione live
/// dell'assicurato (rosso). Mostra un alert giallo se la distanza è > 50m.
@MainActor
struct VideoperiziaMapPane: View {
    let claimAddressCoordinate: CLLocationCoordinate2D?
    let insuredCoordinate: CLLocationCoordinate2D?
    let distanceMeters: Double?

    /// Soglia sopra la quale alertiamo il perito che l'assicurato non è
    /// presso l'indirizzo del sinistro.
    private let distanceThresholdMeters: Double = 50

    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Posizione")
                    .font(.headline)
                Spacer()
                if let distanceMeters {
                    Text("\(Int(distanceMeters)) m dall'indirizzo")
                        .font(.caption)
                        .foregroundStyle(distanceMeters > distanceThresholdMeters ? .red : .secondary)
                }
            }

            if let alert = alertText {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(alert).font(.caption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Map(position: $cameraPosition) {
                if let claimAddressCoordinate {
                    Marker("Indirizzo sinistro", systemImage: "house.fill", coordinate: claimAddressCoordinate)
                        .tint(.blue)
                }
                if let insuredCoordinate {
                    Marker("Assicurato", systemImage: "person.fill", coordinate: insuredCoordinate)
                        .tint(.red)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onChange(of: insuredCoordinate?.latitude) { _, _ in recenter() }
            .onAppear { recenter() }

            if insuredCoordinate == nil {
                Text("Posizione dell'assicurato non ancora disponibile.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.windowBackgroundColorCompat)))
    }

    private var alertText: String? {
        guard let distanceMeters else { return nil }
        if distanceMeters > distanceThresholdMeters {
            return "L'assicurato è a \(Int(distanceMeters)) m dall'indirizzo del sinistro (limite \(Int(distanceThresholdMeters)) m)."
        }
        return nil
    }

    private func recenter() {
        let coords = [claimAddressCoordinate, insuredCoordinate].compactMap { $0 }
        guard !coords.isEmpty else { return }
        if coords.count == 1 {
            cameraPosition = .region(MKCoordinateRegion(
                center: coords[0],
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
            return
        }
        let minLat = coords.map(\.latitude).min()!
        let maxLat = coords.map(\.latitude).max()!
        let minLon = coords.map(\.longitude).min()!
        let maxLon = coords.map(\.longitude).max()!
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.002, (maxLat - minLat) * 2),
            longitudeDelta: max(0.002, (maxLon - minLon) * 2)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private extension Color {
    /// `windowBackgroundColor` esiste solo su macOS; iOS usa systemBackground.
    /// Wrapper cross-platform per evitare `#if os(...)` sparso.
    static var windowBackgroundColorCompat: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}
