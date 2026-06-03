import SwiftUI
import CoreLocation

/// Sub-tab "Videoperizia" del dettaglio sinistro. Condivisa fra macOS e iPadOS.
///
/// Layout:
///   - Sinistra: live call (riusa VideoperiziaCallView interna come embed)
///   - Destra:   mappa con doppio pin + alert distanza, galleria foto/clip,
///               controlli locali (mic/camera) e remoti (camera flip / flash)
///
/// **Pre-requisito Xcode**: i 3 file Videoperizia*.swift devono essere aggiunti
/// ad entrambi i target (PerX, PerX per iPad) e il package LiveKit collegato.
@MainActor
struct VideoperiziaTabContent: View {
    let claimId: String
    let claimReferenceLabel: String
    /// Indirizzo del sinistro in forma testuale (es. "Via Roma 10, Milano").
    /// La tab si occupa di geocodificarlo on-demand per piazzare il pin.
    let claimAddress: String?

    @StateObject private var model = VideoperiziaTabModel()
    @State private var claimAddressCoordinate: CLLocationCoordinate2D?

    var body: some View {
        HStack(spacing: 12) {
            VideoperiziaCallEmbed(
                claimId: claimId,
                claimReferenceLabel: claimReferenceLabel,
                model: model
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VideoperiziaSidePanel(
                claimAddressCoordinate: claimAddressCoordinate,
                model: model
            )
            .frame(width: 380)
        }
        .padding(12)
        .task {
            await model.bootstrap(claimId: claimId)
            await geocodeClaimAddressIfNeeded()
        }
        .onDisappear { model.stopPolling() }
    }

    private func geocodeClaimAddressIfNeeded() async {
        guard claimAddressCoordinate == nil,
              let address = claimAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty else { return }
        let geocoder = CLGeocoder()
        if let placemark = try? await geocoder.geocodeAddressString(address).first,
           let location = placemark.location {
            await MainActor.run {
                self.claimAddressCoordinate = location.coordinate
            }
        }
    }
}

// MARK: - Side panel layout

private struct VideoperiziaSidePanel: View {
    let claimAddressCoordinate: CLLocationCoordinate2D?
    @ObservedObject var model: VideoperiziaTabModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                VideoperiziaMapPane(
                    claimAddressCoordinate: claimAddressCoordinate,
                    insuredCoordinate: model.lastInsuredCoordinate,
                    distanceMeters: model.distanceFromAddress(claimAddressCoordinate)
                )
                VideoperiziaControlsPane(model: model)
                VideoperiziaGalleryPane(media: model.media)
            }
            .padding(.trailing, 4)
        }
    }
}

// MARK: - Call embed
//
// Wrapper che monta la nostra `VideoperiziaCallView` in modalità inline (non
// modale). Il binding di stato `model` permette al pannello laterale di
// leggere session, perito-control, media live.

private struct VideoperiziaCallEmbed: View {
    let claimId: String
    let claimReferenceLabel: String
    @ObservedObject var model: VideoperiziaTabModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.06))
            // La VideoperiziaCallView esistente sa già fare il flusso completo,
            // la usiamo embedded — il navigation/title è suo, glielo lasciamo.
            VideoperiziaCallView(
                claimId: claimId,
                claimReferenceLabel: claimReferenceLabel
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
