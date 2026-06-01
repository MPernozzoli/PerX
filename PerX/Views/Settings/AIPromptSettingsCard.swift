import SwiftUI

// ============================================================================
// MARK: - AIPromptSettingsCard
// Sezione "Prompt AI sinistri" dentro TenantSettingsView.
// - editor body del prompt `sinistri.tagging`
// - storico versioni read-only (per consultare cosa era in uso prima)
// - matrice routing policy (5 fasi sinistri × 3 trigger)
//
// MVP: solo il prompt tagging è editabile (è l'unico seedato finora).
// Quando porteremo le altre fasi (fase1_approfondita, relazione, ...) potremo
// estendere con un Picker di selezione del prompt.
// ============================================================================

struct AIPromptSettingsCard: View {
    @StateObject private var service = AIPromptAdminService.shared

    @State private var editedTitle: String = ""
    @State private var editedDescription: String = ""
    @State private var editedBody: String = ""
    @State private var changelog: String = ""
    @State private var selectedHistoryVersion: String?
    @State private var historyPreview: AIPromptAdminService.PromptVersionDTO?
    @State private var didPopulate = false

    private let phases: [(key: String, label: String)] = [
        (AISinistroPhase.tagging,           "Tagging foto"),
        (AISinistroPhase.fase1Approfondita, "Fase 1 — approfondita"),
        (AISinistroPhase.parseDenuncia,     "Parse denuncia / giustificativi"),
        (AISinistroPhase.raggruppamento,    "Raggruppamento beni"),
        (AISinistroPhase.relazione,         "Relazione finale"),
    ]
    private let triggers: [AIRoutingTrigger] = [.userInitiated, .background, .regenerate]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                header
                if service.isLoading && service.prompt == nil {
                    ProgressView("Caricamento…").padding(.vertical, 8)
                } else {
                    promptEditor
                    historySection
                    Divider()
                    policySection
                }
                if let err = service.lastError {
                    Text("⚠️ \(err)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .task { await initialLoad() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt AI sinistri")
                    .font(.headline)
                Text("Edita i prompt usati dal flusso di analisi sinistri (tagging foto, fasi Perxia, relazione). Ogni salvataggio crea una nuova versione immutabile.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                Task { await initialLoad(force: true) }
            } label: {
                Label("Ricarica", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(service.isLoading)
        }
    }

    // MARK: Prompt editor

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prompt: \(AISinistroPhase.tagging)")
                .font(.subheadline.weight(.semibold))
            if let p = service.prompt {
                HStack(spacing: 12) {
                    Text("Versione corrente:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(p.current_version_id ?? "—")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                    Spacer()
                }
            }
            TextField("Titolo", text: $editedTitle)
                .textFieldStyle(.roundedBorder)
            TextField("Descrizione", text: $editedDescription, axis: .vertical)
                .lineLimit(2, reservesSpace: true)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 4) {
                Text("Body").font(.caption).foregroundColor(.secondary)
                TextEditor(text: $editedBody)
                    .frame(minHeight: 240)
                    .font(.system(.body, design: .monospaced))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    )
            }
            TextField("Changelog (opzionale): cosa è cambiato?", text: $changelog)
                .textFieldStyle(.roundedBorder)
            HStack {
                if let vars = service.prompt?.variables, !vars.isEmpty {
                    Text("Variabili attese: \(vars.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    Task { await save() }
                } label: {
                    if service.isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Salva nuova versione", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(service.isSaving || editedBody.isEmpty)
            }
        }
    }

    // MARK: History

    private var historySection: some View {
        DisclosureGroup("Storico versioni (\(service.versions.count))") {
            VStack(alignment: .leading, spacing: 8) {
                if service.versions.isEmpty {
                    Text("Nessuna versione storica.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(service.versions) { v in
                        Button {
                            selectedHistoryVersion = v.version_id
                            historyPreview = v
                        } label: {
                            HStack {
                                Text(v.version_id)
                                    .font(.system(.caption, design: .monospaced))
                                Text(v.changelog ?? "—")
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(v.created_at.prefix(19))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .background(selectedHistoryVersion == v.version_id ? Color.accentColor.opacity(0.15) : .clear)
                    }
                    if let preview = historyPreview {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Body versione \(preview.version_id) (read-only)")
                                .font(.caption.weight(.semibold))
                            ScrollView {
                                Text(preview.body)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(maxHeight: 200)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    // MARK: Policy matrix

    private var policySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Routing locale ↔ cloud")
                .font(.subheadline.weight(.semibold))
            Text("Per ogni fase del flusso e tipo di trigger decidi se preferire esecuzione locale (MLX sul device), cloud, o forzare l'uno. `regenerate` è gestito dal sistema (sempre cloud) e non è esposto qui.")
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(phases, id: \.key) { phase in
                VStack(alignment: .leading, spacing: 6) {
                    Text(phase.label)
                        .font(.caption.weight(.semibold))
                    HStack(spacing: 12) {
                        ForEach(triggers.filter { $0 != .regenerate }, id: \.self) { trig in
                            policyPicker(phase: phase.key, trigger: trig)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func policyPicker(phase: String, trigger: AIRoutingTrigger) -> some View {
        let key = "\(phase)|\(trigger.rawValue)"
        let binding = Binding<String>(
            get: { service.policyMatrix[key] ?? AIRoutingMode.preferLocal.rawValue },
            set: { newValue in
                if let mode = AIRoutingMode(rawValue: newValue) {
                    Task { await service.savePolicy(phase: phase, trigger: trigger, mode: mode) }
                }
            }
        )
        return VStack(alignment: .leading, spacing: 2) {
            Text(triggerLabel(trigger))
                .font(.caption2)
                .foregroundColor(.secondary)
            Picker("", selection: binding) {
                Text("Locale only").tag(AIRoutingMode.localOnly.rawValue)
                Text("Preferisci locale").tag(AIRoutingMode.preferLocal.rawValue)
                Text("Preferisci cloud").tag(AIRoutingMode.preferCloud.rawValue)
                Text("Cloud only").tag(AIRoutingMode.cloudOnly.rawValue)
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .frame(minWidth: 160)
    }

    private func triggerLabel(_ t: AIRoutingTrigger) -> String {
        switch t {
        case .userInitiated: return "User-initiated"
        case .background:    return "Background"
        case .regenerate:    return "Regenerate"
        }
    }

    // MARK: Helpers

    private func initialLoad(force: Bool = false) async {
        if didPopulate && !force { return }
        await service.load()
        if let p = service.prompt {
            editedTitle = p.title
            editedDescription = p.description ?? ""
            editedBody = p.body
            changelog = ""
            didPopulate = true
        }
    }

    private func save() async {
        guard let p = service.prompt else { return }
        await service.savePrompt(
            key: p.key,
            title: editedTitle,
            description: editedDescription.isEmpty ? nil : editedDescription,
            body: editedBody,
            variables: p.variables,
            changelog: changelog.isEmpty ? nil : changelog
        )
        if let updated = service.prompt {
            editedBody = updated.body
            editedTitle = updated.title
            editedDescription = updated.description ?? ""
            changelog = ""
        }
    }
}
