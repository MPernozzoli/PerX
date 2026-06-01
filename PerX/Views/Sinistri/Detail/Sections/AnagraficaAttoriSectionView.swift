import SwiftUI

// ============================================================================
// MARK: - AnagraficaAttoriSectionView
//
// Sezione drop-in per il dettaglio sinistro che gestisce i tre ruoli attore
// (contraente / assicurato / danneggiato) usando l'anagrafica unificata
// backend (CloudActorResponse).
//
// Convive con `PolizzaAttoriSectionView` esistente: questa lavora sui campi
// `*CloudId` di Sinistro Core Data, quella sui campi piatti `nome*/email*`.
// Dopo che tutti i client saranno migrati, la vecchia sezione potrà essere
// rimossa.
// ============================================================================

struct AnagraficaAttoriSectionView: View {
    @ObservedObject var sinistro: Sinistro
    @Environment(\.managedObjectContext) private var viewContext

    @State private var contraente: CloudActorSummary?
    @State private var assicurato: CloudActorSummary?
    @State private var danneggiato: CloudActorSummary?
    @State private var agenzia: CloudAgenziaResponse?
    @State private var compagnia: CloudCompagniaResponse?

    @State private var isLoading = false
    @State private var isSaving = false
    @State private var error: String?

    @StateObject private var repo = ActorRepository.shared

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                header

                if isLoading {
                    ProgressView("Carico anagrafica…").controlSize(.small)
                }

                VStack(spacing: 12) {
                    ActorPickerView(title: "Contraente", selection: $contraente, suggestedType: .person, claimContextId: sinistro.riferimento)
                    ActorPickerView(title: "Assicurato", selection: $assicurato, suggestedType: .person, claimContextId: sinistro.riferimento)
                    ActorPickerView(title: "Danneggiato", selection: $danneggiato, suggestedType: .person, claimContextId: sinistro.riferimento)

                    Divider().padding(.vertical, 4)

                    HStack(alignment: .top, spacing: 12) {
                        CompagniaPickerView(title: "Compagnia", selection: $compagnia)
                        AgenziaPickerView(title: "Agenzia", selection: $agenzia)
                    }
                }

                if hasChanges {
                    HStack {
                        Spacer()
                        Button("Annulla") { reloadFromLocal() }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        Button {
                            Task { await save() }
                        } label: {
                            if isSaving {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Salva")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isSaving)
                    }
                }

                if let error {
                    Text(error).font(.caption).foregroundColor(.red)
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
        .task { await initialLoad() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Anagrafica attori")
                .font(.headline)
            Spacer()
            if let ref = sinistro.riferimento, !ref.isEmpty {
                Text(ref).font(.caption2).foregroundColor(.secondary).monospaced()
            }
        }
    }

    // MARK: - State management

    private var hasChanges: Bool {
        sinistro.contraenteCloudId != contraente?.id ||
        sinistro.assicuratoCloudId != assicurato?.id ||
        sinistro.danneggiatoCloudId != danneggiato?.id ||
        sinistro.agencyCloudId != agenzia?.id ||
        sinistro.compagniaCloudId != compagnia?.id
    }

    private func reloadFromLocal() {
        Task { await initialLoad() }
    }

    private func initialLoad() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        async let c = loadActor(id: sinistro.contraenteCloudId)
        async let a = loadActor(id: sinistro.assicuratoCloudId)
        async let d = loadActor(id: sinistro.danneggiatoCloudId)
        async let ag = loadAgenzia(id: sinistro.agencyCloudId)
        async let co = loadCompagnia(id: sinistro.compagniaCloudId)
        contraente = try? await c
        assicurato = try? await a
        danneggiato = try? await d
        agenzia = try? await ag
        compagnia = try? await co
    }

    private func loadAgenzia(id: String?) async throws -> CloudAgenziaResponse? {
        guard let id, !id.isEmpty else { return nil }
        // L'endpoint /rubrica/agenzie/{id} non esiste; cerchiamo per nome
        // tramite list e filtriamo l'id. Quantità ridotta in rubrica → ok.
        let resp = try await HubAPIAdapterClient.shared.listAgenzieFromBackend(limit: 500)
        return resp.items.first { $0.id == id }
    }

    private func loadCompagnia(id: String?) async throws -> CloudCompagniaResponse? {
        guard let id, !id.isEmpty else { return nil }
        let resp = try await HubAPIAdapterClient.shared.listCompagnie(limit: 500)
        return resp.items.first { $0.id == id }
    }

    private func loadActor(id: String?) async throws -> CloudActorSummary? {
        guard let id, !id.isEmpty else { return nil }
        let detail = try await repo.detail(id: id)
        // Mostriamo solo display + identifier mascherato (la section non ha
        // bisogno di email/telefono/indirizzi).
        let displayName: String
        switch detail.actor_type {
        case .person:
            let n = [detail.nome, detail.cognome].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            displayName = n.isEmpty ? (detail.denominazione ?? "—") : n
        case .company, .condo:
            displayName = detail.denominazione ?? "—"
        }
        return CloudActorSummary(
            id: detail.id,
            actor_type: detail.actor_type,
            display_name: displayName,
            codice_fiscale_masked: detail.codice_fiscale.map(_maskIdentifier),
            partita_iva_masked: detail.partita_iva.map(_maskIdentifier)
        )
    }

    @MainActor
    private func save() async {
        guard let riferimento = sinistro.riferimento, !riferimento.isEmpty else {
            error = "Sinistro senza riferimento, impossibile salvare."
            return
        }
        isSaving = true
        defer { isSaving = false }
        error = nil
        do {
            _ = try await ClaimAdapter.shared.updateActorRefs(
                riferimento: riferimento,
                contraenteId: contraente?.id,
                assicuratoId: assicurato?.id,
                danneggiatoId: danneggiato?.id,
                agencyId: agenzia?.id,
                compagniaId: compagnia?.id
            )
            // applyActorCloudRefs è già stato chiamato dall'adapter; la
            // @ObservedObject sinistro pubblicherà le modifiche.
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}

// MARK: - Helpers

private func _maskIdentifier(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    if trimmed.count <= 6 { return String(repeating: "*", count: trimmed.count) }
    let prefix = trimmed.prefix(3)
    let suffix = trimmed.suffix(3)
    let stars = String(repeating: "*", count: trimmed.count - 6)
    return "\(prefix)\(stars)\(suffix)"
}
