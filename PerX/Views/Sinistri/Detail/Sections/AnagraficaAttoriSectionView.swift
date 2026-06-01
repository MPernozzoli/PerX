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

    @State private var contraente: CloudActorResponse?
    @State private var assicurato: CloudActorResponse?
    @State private var danneggiato: CloudActorResponse?

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
                    ActorPickerView(title: "Contraente", selection: $contraente, suggestedType: .person)
                    ActorPickerView(title: "Assicurato", selection: $assicurato, suggestedType: .person)
                    ActorPickerView(title: "Danneggiato", selection: $danneggiato, suggestedType: .person)
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
        sinistro.danneggiatoCloudId != danneggiato?.id
    }

    private func reloadFromLocal() {
        Task {
            contraente = try? await loadActor(id: sinistro.contraenteCloudId)
            assicurato = try? await loadActor(id: sinistro.assicuratoCloudId)
            danneggiato = try? await loadActor(id: sinistro.danneggiatoCloudId)
        }
    }

    private func initialLoad() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        async let c = loadActor(id: sinistro.contraenteCloudId)
        async let a = loadActor(id: sinistro.assicuratoCloudId)
        async let d = loadActor(id: sinistro.danneggiatoCloudId)
        contraente = try? await c
        assicurato = try? await a
        danneggiato = try? await d
    }

    private func loadActor(id: String?) async throws -> CloudActorResponse? {
        guard let id, !id.isEmpty else { return nil }
        let detail = try await repo.detail(id: id)
        // Mappa il subset del CloudActorDetail in CloudActorResponse per il picker.
        return CloudActorResponse(
            id: detail.id,
            tenant_id: detail.tenant_id,
            actor_type: detail.actor_type,
            nome: detail.nome,
            cognome: detail.cognome,
            data_nascita: detail.data_nascita,
            luogo_nascita: detail.luogo_nascita,
            sesso: detail.sesso,
            denominazione: detail.denominazione,
            codice_fiscale: detail.codice_fiscale,
            partita_iva: detail.partita_iva,
            email: detail.email,
            telefono: detail.telefono,
            pec: detail.pec,
            note: detail.note,
            created_at: detail.created_at,
            updated_at: detail.updated_at
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
                danneggiatoId: danneggiato?.id
            )
            // applyActorCloudRefs è già stato chiamato dall'adapter; la
            // @ObservedObject sinistro pubblicherà le modifiche.
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}
