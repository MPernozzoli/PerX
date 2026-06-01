import SwiftUI

// ============================================================================
// MARK: - ActorPickerView
//
// Picker riusabile per selezionare un Actor backend (contraente/assicurato/
// danneggiato). Autocompleta su nome/CF/PIVA con debounce, e permette di
// creare al volo un nuovo attore se la ricerca non trova nulla.
//
// Uso:
//   ActorPickerView(
//       title: "Contraente",
//       selection: $contraente,
//       suggestedType: .person
//   )
//
// Il binding `selection` è di tipo CloudActorResponse? perché la UI può
// stare sia in stato "non scelto" sia "scelto". Quando l'utente seleziona
// un suggerimento o conferma un nuovo attore, il binding viene popolato.
// ============================================================================

struct ActorPickerView: View {
    let title: String
    @Binding var selection: CloudActorResponse?
    var suggestedType: CloudActorType = .person

    @StateObject private var repo = ActorRepository.shared

    @State private var queryText: String = ""
    @State private var showingCreateSheet = false
    @State private var isFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            if let selected = selection {
                selectedRow(selected)
            } else {
                searchRow
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            ActorCreateSheet(
                initialQuery: queryText,
                suggestedType: suggestedType,
                onCreated: { created in
                    selection = created
                    queryText = ""
                    repo.clearSearch()
                    showingCreateSheet = false
                },
                onCancel: { showingCreateSheet = false }
            )
        }
    }

    // MARK: - Selected state

    private func selectedRow(_ actor: CloudActorResponse) -> some View {
        HStack(spacing: 10) {
            actorIcon(actor.actor_type)
            VStack(alignment: .leading, spacing: 2) {
                Text(actor.displayName)
                    .font(.body)
                if let code = actor.identifyingCode {
                    Text(code)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospaced()
                }
            }
            Spacer()
            Button {
                selection = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Rimuovi selezione")
        }
        .padding(8)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(6)
    }

    // MARK: - Search state

    private var searchRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Cerca per nome, CF o P.IVA…", text: $queryText)
                    .textFieldStyle(.plain)
                    .onChange(of: queryText) { _, newValue in
                        repo.search(query: newValue, actorType: suggestedType)
                    }
                if repo.isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )

            if !queryText.isEmpty {
                resultsList
            }
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if repo.lastSearchResults.isEmpty && !repo.isSearching {
            HStack {
                Text("Nessun attore trovato.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Crea nuovo") {
                    showingCreateSheet = true
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(repo.lastSearchResults) { actor in
                    Button {
                        selection = actor
                        queryText = ""
                        repo.clearSearch()
                    } label: {
                        HStack(spacing: 10) {
                            actorIcon(actor.actor_type)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(actor.displayName)
                                    .font(.callout)
                                if let code = actor.identifyingCode {
                                    Text(code)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .monospaced()
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
                Button {
                    showingCreateSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Crea nuovo attore")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .background(Color(white: 0.98))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - Helpers

    private func actorIcon(_ type: CloudActorType) -> some View {
        let systemName: String
        switch type {
        case .person: systemName = "person.fill"
        case .company: systemName = "building.2.fill"
        case .condo: systemName = "building.fill"
        }
        return Image(systemName: systemName)
            .foregroundColor(.accentColor)
            .frame(width: 18)
    }
}

// ============================================================================
// MARK: - ActorCreateSheet
//
// Foglio minimo per creare un nuovo attore on-the-fly dal picker.
// Per gestione completa (indirizzi multipli, IBAN, relazioni) usa la
// schermata dedicata di gestione anagrafica.
// ============================================================================

struct ActorCreateSheet: View {
    let initialQuery: String
    let suggestedType: CloudActorType
    var onCreated: (CloudActorResponse) -> Void
    var onCancel: () -> Void

    @StateObject private var repo = ActorRepository.shared

    @State private var actorType: CloudActorType = .person
    @State private var nome: String = ""
    @State private var cognome: String = ""
    @State private var denominazione: String = ""
    @State private var codiceFiscale: String = ""
    @State private var partitaIva: String = ""
    @State private var email: String = ""
    @State private var telefono: String = ""

    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Nuovo attore")
                    .font(.title3.bold())
                Spacer()
                Button("Annulla", action: onCancel)
                    .buttonStyle(.plain)
            }

            Picker("Tipo", selection: $actorType) {
                ForEach(CloudActorType.allCases, id: \.self) { type in
                    Text(type.localized).tag(type)
                }
            }
            .pickerStyle(.segmented)

            if actorType == .person {
                HStack(spacing: 8) {
                    TextField("Nome", text: $nome).textFieldStyle(.roundedBorder)
                    TextField("Cognome", text: $cognome).textFieldStyle(.roundedBorder)
                }
                LabeledField(label: "Codice Fiscale") {
                    TextField("Codice Fiscale", text: $codiceFiscale)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: codiceFiscale) { _, v in codiceFiscale = v.uppercased() }
                }
            } else {
                LabeledField(label: actorType == .condo ? "Denominazione condominio" : "Ragione sociale") {
                    TextField("Denominazione", text: $denominazione)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField(label: "Partita IVA") {
                    TextField("Partita IVA", text: $partitaIva)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField(label: "Codice Fiscale (opzionale)") {
                    TextField("Codice Fiscale", text: $codiceFiscale)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: codiceFiscale) { _, v in codiceFiscale = v.uppercased() }
                }
            }

            HStack(spacing: 8) {
                LabeledField(label: "Email") {
                    TextField("Email", text: $email).textFieldStyle(.roundedBorder)
                }
                LabeledField(label: "Telefono") {
                    TextField("Telefono", text: $telefono).textFieldStyle(.roundedBorder)
                }
            }

            if let error {
                Text(error).font(.caption).foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Crea") { Task { await submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting || !canSubmit)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .onAppear {
            actorType = suggestedType
            seedInitialQuery()
        }
    }

    private var canSubmit: Bool {
        switch actorType {
        case .person:
            return !nome.trimmed.isEmpty && !cognome.trimmed.isEmpty
        case .company, .condo:
            return !denominazione.trimmed.isEmpty
        }
    }

    private func seedInitialQuery() {
        let q = initialQuery.trimmed
        guard !q.isEmpty else { return }
        if isLikelyCF(q) { codiceFiscale = q.uppercased() }
        else if isLikelyPIVA(q) { partitaIva = q }
        else if actorType == .person {
            let parts = q.split(separator: " ", maxSplits: 1).map(String.init)
            nome = parts.first ?? q
            if parts.count > 1 { cognome = parts[1] }
        } else {
            denominazione = q
        }
    }

    private func isLikelyCF(_ s: String) -> Bool {
        s.count == 16 && s.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private func isLikelyPIVA(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0.isNumber }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        error = nil
        let payload = CloudActorCreate(
            actor_type: actorType,
            nome: actorType == .person ? nome.trimmedOrNil : nil,
            cognome: actorType == .person ? cognome.trimmedOrNil : nil,
            data_nascita: nil,
            luogo_nascita: nil,
            sesso: nil,
            denominazione: actorType != .person ? denominazione.trimmedOrNil : nil,
            codice_fiscale: codiceFiscale.trimmedOrNil,
            partita_iva: partitaIva.trimmedOrNil,
            email: email.trimmedOrNil,
            telefono: telefono.trimmedOrNil,
            pec: nil,
            note: nil,
            addresses: nil,
            ibans: nil
        )
        do {
            let created = try await repo.create(payload)
            onCreated(created)
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}

// MARK: - Small helpers

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            content
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedOrNil: String? {
        let t = trimmed
        return t.isEmpty ? nil : t
    }
}
