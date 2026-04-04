import SwiftUI

struct TenantSettingsView: View {
    @StateObject private var currentUserService = CurrentUserService.shared
    @StateObject private var apiService = TenantSettingsAPIService.shared
    @State private var tenantSettings = TenantMailSettingsService.shared.settings
    @State private var selectedTenantId: String = ""
    @State private var tenantName = ""
    @State private var tenantSlug = ""
    @State private var internalDomainsText = ""
    @State private var internalEmailsText = ""
    @State private var systemEmailsText = ""
    @State private var secretariatEmailsText = ""
    @State private var claimGaranzieText = ""
    @State private var defaultClaimGaranzia = "Fenomeno Elettrico"
    @State private var hasChanges = false
    @State private var saveMessage: String?
    @State private var isLoading = false
    @State private var isSaving = false

    var body: some View {
        Group {
            if currentUserService.canManageTenantSettings {
                ScrollView {
                    VStack(spacing: 20) {
                        headerCard
                        if currentUserService.isPlatformAdmin && !apiService.availableTenants.isEmpty {
                            tenantPickerCard
                        }
                        identityCard
                        mailCard
                        claimsCard
                    }
                    .padding()
                }
                .task {
                    await bootstrap()
                }
            } else {
                ContentUnavailableView(
                    "Accesso riservato",
                    systemImage: "lock.shield",
                    description: Text("Questa sezione è visibile solo all'admin generale dell'app e all'admin del tenant.")
                )
                .padding()
            }
        }
    }

    private var headerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(tenantName.isEmpty ? "Tenant" : tenantName)
                    .font(.title3.bold())

                HStack(spacing: 12) {
                    permissionBadge(
                        title: currentUserService.isPlatformAdmin ? "Admin Generale" : "Admin Tenant",
                        color: currentUserService.isPlatformAdmin ? Color(hex: "B45309") ?? .orange : .blue
                    )

                    permissionBadge(
                        title: "Slug: \(tenantSlug.isEmpty ? "non impostato" : tenantSlug)",
                        color: Color(hex: "0F766E") ?? .teal
                    )
                }

                Text("Gestisci identità studio, domini interni e caselle operative usate dai flussi dell'app.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let lastSyncError = apiService.lastSyncError, !lastSyncError.isEmpty {
                    Text(lastSyncError)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        } label: {
            Label("Gestione Tenant", systemImage: "building.2.crop.circle")
        }
    }

    private var tenantPickerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tenant target")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Tenant", selection: $selectedTenantId) {
                    ForEach(apiService.availableTenants) { tenant in
                        Text("\(tenant.name) (\(tenant.slug))")
                            .tag(tenant.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedTenantId) { _, _ in
                    Task { await loadSettingsFromBackend() }
                }
            }
            .padding()
        } label: {
            Label("Selezione Tenant", systemImage: "rectangle.stack.badge.person.crop")
        }
    }

    private var identityCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nome Tenant")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Studio Peritale Rossi", text: $tenantName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Slug Tenant")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("studio-peritale-rossi", text: $tenantSlug)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding()
        } label: {
            Label("Identità Tenant", systemImage: "person.text.rectangle")
        }
    }

    private var mailCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                mailField(
                    title: "Domini interni",
                    text: $internalDomainsText,
                    placeholder: "studio.it, perizie.it",
                    help: "Usati per riconoscere le comunicazioni interne del tenant."
                )

                mailField(
                    title: "Email interne",
                    text: $internalEmailsText,
                    placeholder: "mario@studio.it, laura@studio.it",
                    help: "Caselle personali o condivise interne allo studio."
                )

                mailField(
                    title: "Mail di sistema",
                    text: $systemEmailsText,
                    placeholder: "noreply@studio.it, pratiche@studio.it",
                    help: "Identità applicative o caselle tecniche configurate per il tenant."
                )

                mailField(
                    title: "Mail segreteria",
                    text: $secretariatEmailsText,
                    placeholder: "segreteria@studio.it",
                    help: "Usate per riconoscere i flussi di segreteria dello studio."
                )

                HStack {
                    if let saveMessage {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Ripristina") {
                        Task { await loadSettingsFromBackend() }
                    }
                    .buttonStyle(.bordered)

                    Button("Salva") {
                        Task { await saveSettings() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChanges || isSaving)
                }
            }
            .padding()
        } label: {
            Label("Configurazione Mail Tenant", systemImage: "envelope.badge")
        }
        .onChange(of: tenantName) { _, _ in hasChanges = true }
        .onChange(of: tenantSlug) { _, _ in hasChanges = true }
        .onChange(of: internalDomainsText) { _, _ in hasChanges = true }
        .onChange(of: internalEmailsText) { _, _ in hasChanges = true }
        .onChange(of: systemEmailsText) { _, _ in hasChanges = true }
        .onChange(of: secretariatEmailsText) { _, _ in hasChanges = true }
        .onChange(of: claimGaranzieText) { _, _ in hasChanges = true }
        .onChange(of: defaultClaimGaranzia) { _, _ in hasChanges = true }
    }

    private var claimsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                mailField(
                    title: "Garanzie sinistri",
                    text: $claimGaranzieText,
                    placeholder: "Fenomeno Elettrico",
                    help: "Enum tenant condiviso per i sinistri e per le preferenze di assegnazione automatica."
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Garanzia predefinita")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Garanzia predefinita", selection: $defaultClaimGaranzia) {
                        ForEach(availableClaimGaranzie, id: \.self) { garanzia in
                            Text(garanzia).tag(garanzia)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding()
        } label: {
            Label("Garanzie Tenant", systemImage: "shield.lefthalf.filled")
        }
    }

    private func permissionBadge(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func mailField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(placeholder, text: text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Text(help)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func loadSettings() {
        tenantSettings = TenantMailSettingsService.shared.settings
        tenantName = tenantSettings.tenantName
        tenantSlug = tenantSettings.tenantSlug
        internalDomainsText = tenantSettings.internalDomains.joined(separator: ", ")
        internalEmailsText = tenantSettings.internalEmails.joined(separator: ", ")
        systemEmailsText = tenantSettings.systemEmails.joined(separator: ", ")
        secretariatEmailsText = tenantSettings.secretariatEmails.joined(separator: ", ")
        claimGaranzieText = tenantSettings.claimGaranzie.joined(separator: ", ")
        defaultClaimGaranzia = tenantSettings.defaultClaimGaranzia
        hasChanges = false
        saveMessage = nil
    }

    private func saveSettings() async {
        isSaving = true
        defer { isSaving = false }

        tenantSettings.tenantName = tenantName.trimmingCharacters(in: .whitespacesAndNewlines)
        tenantSettings.tenantSlug = tenantSlug
        tenantSettings.internalDomains = splitValues(internalDomainsText)
        tenantSettings.internalEmails = splitValues(internalEmailsText)
        tenantSettings.systemEmails = splitValues(systemEmailsText)
        tenantSettings.secretariatEmails = splitValues(secretariatEmailsText)
        tenantSettings.claimGaranzie = splitValues(claimGaranzieText)
        if !tenantSettings.claimGaranzie.contains(defaultClaimGaranzia) {
            defaultClaimGaranzia = tenantSettings.claimGaranzie.first ?? "Fenomeno Elettrico"
        }
        tenantSettings.defaultClaimGaranzia = defaultClaimGaranzia

        let targetTenantId = selectedTenantId.isEmpty ? nil : selectedTenantId
        let saved = await apiService.saveTenantSettings(tenantSettings, targetTenantId: targetTenantId)
        tenantSettings = saved
        TenantMailSettingsService.shared.settings = saved
        loadSettings()
        saveMessage = apiService.lastSyncError == nil ? "Impostazioni tenant salvate su backend" : "Impostazioni salvate localmente, sync backend non riuscito"
    }

    private func splitValues(_ rawValue: String) -> [String] {
        rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var availableClaimGaranzie: [String] {
        let values = splitValues(claimGaranzieText)
        return values.isEmpty ? ["Fenomeno Elettrico"] : values
    }

    private func bootstrap() async {
        if currentUserService.isPlatformAdmin {
            await apiService.refreshAvailableTenantsIfNeeded()
            if selectedTenantId.isEmpty {
                selectedTenantId = apiService.availableTenants.first?.id ?? ""
            }
        }
        await loadSettingsFromBackend()
    }

    private func loadSettingsFromBackend() async {
        isLoading = true
        defer { isLoading = false }

        let targetTenantId = selectedTenantId.isEmpty ? nil : selectedTenantId
        let loaded = await apiService.loadTenantSettings(targetTenantId: targetTenantId)
        tenantSettings = loaded
        TenantMailSettingsService.shared.settings = loaded
        loadSettings()
        if apiService.lastSyncError == nil {
            saveMessage = "Configurazione tenant caricata dal backend"
        } else {
            saveMessage = "Uso configurazione locale: \(apiService.lastSyncError ?? "")"
        }
    }
}
