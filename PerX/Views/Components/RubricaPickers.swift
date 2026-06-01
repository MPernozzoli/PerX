import SwiftUI

// ============================================================================
// MARK: - Rubrica Pickers (Compagnia / Agenzia backend)
//
// Picker SwiftUI riusabili che pescano da /api/v1/rubrica/compagnie e
// /api/v1/rubrica/agenzie. Convivono con la rubrica CloudKit esistente:
// vanno usati quando serve collegare un sinistro al record backend
// (agency_id / compagnia_id) per popolare gli indici cross-sinistro.
// ============================================================================

// MARK: - Common search box style

private struct _SearchBox: View {
    @Binding var text: String
    var isLoading: Bool
    var placeholder: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.plain)
            if isLoading { ProgressView().controlSize(.small) }
        }
        .padding(8)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

private struct _SelectedChip: View {
    let icon: String
    let title: String
    let subtitle: String?
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(.accentColor).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption2).foregroundColor(.secondary).monospaced()
                }
            }
            Spacer()
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(6)
    }
}

// MARK: - CompagniaPickerView

struct CompagniaPickerView: View {
    let title: String
    @Binding var selection: CloudCompagniaResponse?

    @State private var query: String = ""
    @State private var results: [CloudCompagniaResponse] = []
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?
    @State private var error: String?
    @State private var creatingInline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)

            if let sel = selection {
                _SelectedChip(
                    icon: "building.columns.fill",
                    title: sel.nome,
                    subtitle: sel.gruppo,
                    onClear: { selection = nil }
                )
            } else {
                _SearchBox(text: $query, isLoading: isLoading, placeholder: "Cerca compagnia…")
                    .onChange(of: query) { _, v in scheduleSearch(v) }

                if !query.isEmpty {
                    resultsList
                }
            }

            if let error {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty && !isLoading {
            HStack {
                Text("Nessuna compagnia trovata.").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button(creatingInline ? "…" : "Crea \"\(query)\"") {
                    Task { await createInline() }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(creatingInline)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(results) { item in
                    Button {
                        selection = item
                        query = ""
                        results = []
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "building.columns")
                                .foregroundColor(.accentColor).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.nome).font(.callout)
                                if let g = item.gruppo, !g.isEmpty {
                                    Text(g).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 6).padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .background(Color(white: 0.98))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
    }

    private func scheduleSearch(_ q: String) {
        searchTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            isLoading = false
            return
        }
        isLoading = true
        searchTask = Task {
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            if Task.isCancelled { return }
            do {
                let response = try await HubAPIAdapterClient.shared.listCompagnie(query: trimmed)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.results = response.items
                    self.isLoading = false
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.error = (error as NSError).localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    @MainActor
    private func createInline() async {
        creatingInline = true
        defer { creatingInline = false }
        error = nil
        do {
            let created = try await HubAPIAdapterClient.shared.createCompagnia(
                CloudCompagniaCreate(nome: query.trimmingCharacters(in: .whitespaces))
            )
            selection = created
            query = ""
            results = []
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}

// MARK: - AgenziaPickerView

struct AgenziaPickerView: View {
    let title: String
    @Binding var selection: CloudAgenziaResponse?

    @State private var query: String = ""
    @State private var results: [CloudAgenziaResponse] = []
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?
    @State private var error: String?
    @State private var creatingInline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)

            if let sel = selection {
                _SelectedChip(
                    icon: "person.2.fill",
                    title: sel.nome,
                    subtitle: [sel.codice, sel.compagnia].compactMap { $0 }.joined(separator: " · "),
                    onClear: { selection = nil }
                )
            } else {
                _SearchBox(text: $query, isLoading: isLoading, placeholder: "Cerca agenzia…")
                    .onChange(of: query) { _, v in scheduleSearch(v) }

                if !query.isEmpty {
                    resultsList
                }
            }

            if let error {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty && !isLoading {
            HStack {
                Text("Nessuna agenzia trovata.").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button(creatingInline ? "…" : "Crea \"\(query)\"") {
                    Task { await createInline() }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(creatingInline)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(results) { item in
                    Button {
                        selection = item
                        query = ""
                        results = []
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.2").foregroundColor(.accentColor).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.nome).font(.callout)
                                let line = [item.codice, item.citta].compactMap { $0 }.joined(separator: " · ")
                                if !line.isEmpty {
                                    Text(line).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 6).padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .background(Color(white: 0.98))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
    }

    private func scheduleSearch(_ q: String) {
        searchTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            isLoading = false
            return
        }
        isLoading = true
        searchTask = Task {
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            if Task.isCancelled { return }
            do {
                let response = try await HubAPIAdapterClient.shared.listAgenzieFromBackend(query: trimmed)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.results = response.items
                    self.isLoading = false
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.error = (error as NSError).localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    @MainActor
    private func createInline() async {
        creatingInline = true
        defer { creatingInline = false }
        error = nil
        do {
            let created = try await HubAPIAdapterClient.shared.createAgenziaOnBackend(
                CloudAgenziaCreate(nome: query.trimmingCharacters(in: .whitespaces))
            )
            selection = created
            query = ""
            results = []
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}
