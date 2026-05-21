import SwiftUI

struct StudioTenantOverviewView: View {
    let tenantName: String
    let tenantSlug: String
    let internalDomainsText: String
    let targetTenantId: String?

    @StateObject private var apiService = TenantSettingsAPIService.shared
    @State private var selectedUser: TenantUserDTO?
    @State private var isCreatingUser = false
    @State private var isRefreshing = false
    @State private var actionMessage: String?

    private var users: [TenantUserDTO] {
        apiService.tenantUsers.sorted { lhs, rhs in
            lhs.full_name.localizedCaseInsensitiveCompare(rhs.full_name) == .orderedAscending
        }
    }

    private var activeUsers: Int {
        users.filter(\.is_active).count
    }

    private var adminUsers: Int {
        users.filter { $0.roles.contains("admin") }.count
    }

    private var pendingInvites: Int {
        users.filter { ($0.invite_status ?? "") != "sent" && $0.last_login_at == nil }.count
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                overviewHeader
                overviewMetrics
                Divider()
                userSection
            }
            .padding()
        } label: {
            Label("Overview Studio", systemImage: "building.columns")
        }
        .task {
            await refreshUsers()
        }
        .onChange(of: targetTenantId) { _, _ in
            Task { await refreshUsers() }
        }
        .sheet(isPresented: $isCreatingUser) {
            TenantUserEditorSheet(
                mode: .create,
                user: nil,
                targetTenantId: targetTenantId,
                onDone: { message in
                    actionMessage = message
                    Task { await refreshUsers() }
                }
            )
            .frame(minWidth: 620, minHeight: 620)
        }
        .sheet(item: $selectedUser) { user in
            TenantUserEditorSheet(
                mode: .edit,
                user: user,
                targetTenantId: targetTenantId,
                onDone: { message in
                    actionMessage = message
                    Task { await refreshUsers() }
                }
            )
            .frame(minWidth: 620, minHeight: 660)
        }
    }

    private var overviewHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tenantName.isEmpty ? "Studio" : tenantName)
                    .font(.title3.bold())
                Text("Tenant \(tenantSlug.isEmpty ? "non configurato" : tenantSlug)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await refreshUsers() }
            } label: {
                Label("Aggiorna", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)

            Button {
                isCreatingUser = true
            } label: {
                Label("Invita utente", systemImage: "person.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var overviewMetrics: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                metricTile(title: "Utenti attivi", value: "\(activeUsers)", icon: "person.2.fill", color: .blue)
                metricTile(title: "Admin tenant", value: "\(adminUsers)", icon: "shield.checkered", color: .purple)
                metricTile(title: "Inviti da verificare", value: "\(pendingInvites)", icon: "envelope.badge", color: .orange)
                metricTile(title: "Domini mail", value: "\(splitDomains.count)", icon: "at", color: .teal)
            }
        }
    }

    private var userSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Utenti")
                    .font(.headline)
                Spacer()
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if users.isEmpty {
                ContentUnavailableView(
                    "Nessun utente configurato",
                    systemImage: "person.2.slash",
                    description: Text("Crea il primo profilo e invia l'invito per impostare la password.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(users) { user in
                        userRow(user)
                    }
                }
            }

            if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let lastSyncError = apiService.lastSyncError, !lastSyncError.isEmpty {
                Text(lastSyncError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func userRow(_ user: TenantUserDTO) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(user.is_active ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(user.full_name)
                        .font(.subheadline.weight(.semibold))
                    ForEach(user.roles.prefix(3), id: \.self) { role in
                        Text(roleLabel(role))
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(Capsule())
                    }
                }

                Text(user.professional_email ?? "Mail professionale non generata")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(user.personal_email)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(user.invite_status ?? "profilo")
                    .font(.caption)
                    .foregroundStyle(inviteColor(user.invite_status))
                Button {
                    selectedUser = user
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .help("Gestisci profilo, ruoli e permessi")
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func metricTile(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .frame(minWidth: 140)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var splitDomains: [String] {
        internalDomainsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func refreshUsers() async {
        isRefreshing = true
        defer { isRefreshing = false }
        _ = await apiService.loadTenantUsers(targetTenantId: targetTenantId)
    }

    private func roleLabel(_ role: String) -> String {
        UserRole(rawValue: role)?.displayName ?? role
    }

    private func inviteColor(_ status: String?) -> Color {
        switch status {
        case "sent": return .green
        case "failed": return .red
        case "not_configured": return .orange
        default: return .secondary
        }
    }
}

private struct TenantUserEditorSheet: View {
    enum Mode {
        case create
        case edit
    }

    let mode: Mode
    let user: TenantUserDTO?
    let targetTenantId: String?
    let onDone: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var apiService = TenantSettingsAPIService.shared

    @State private var personalEmail = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var jobTitle = ""
    @State private var phoneNumber = ""
    @State private var contractType = ContractType.employee.rawValue
    @State private var selectedRoles: Set<String> = ["perito"]
    @State private var professionalEmail = ""
    @State private var isActive = true
    @State private var sendInvite = true
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Form {
                Section("Profilo anagrafico") {
                    TextField("Email personale", text: $personalEmail)
                        .disabled(mode == .edit)
                    TextField("Nome", text: $firstName)
                    TextField("Cognome", text: $lastName)
                    TextField("Qualifica", text: $jobTitle)
                    TextField("Telefono", text: $phoneNumber)
                    Picker("Contratto", selection: $contractType) {
                        ForEach(ContractType.allCases) { contract in
                            Text(contract.displayName).tag(contract.rawValue)
                        }
                    }
                }

                Section("Identità operativa") {
                    TextField("Mail professionale", text: $professionalEmail)
                    Text("Se lasciata vuota, PerX genera nome.cognome@dominio-tenant e risolve gli omonimi con il prefisso ruolo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let aliases = user?.email_aliases, !aliases.isEmpty {
                        Text("Alias: \(aliases.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Ruoli e accesso") {
                    roleGrid
                    Toggle("Utente attivo", isOn: $isActive)
                    if mode == .create {
                        Toggle("Invia invito per creare la password", isOn: $sendInvite)
                    }
                }
            }
            .formStyle(.grouped)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            Divider()
            footer
        }
        .onAppear(perform: populate)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .create ? "Nuovo utente" : "Gestione utente")
                    .font(.title3.bold())
                Text(mode == .create ? "Crea il profilo e invia l'invito password." : "Aggiorna profilo, ruoli e mail professionale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            if mode == .edit, let user {
                Button {
                    Task { await resendInvite(user.id) }
                } label: {
                    Label("Reinvia invito", systemImage: "envelope.arrow.triangle.branch")
                }
                .disabled(isSaving)
            }

            Spacer()

            Button("Annulla") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(mode == .create ? "Crea e invita" : "Salva") {
                Task { await save() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving || firstName.trimmingCharacters(in: .whitespaces).isEmpty || lastName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    private var roleGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(UserRole.allCases) { role in
                Toggle(isOn: Binding(
                    get: { selectedRoles.contains(role.rawValue) },
                    set: { enabled in
                        if enabled {
                            selectedRoles.insert(role.rawValue)
                        } else {
                            selectedRoles.remove(role.rawValue)
                        }
                    }
                )) {
                    Label(role.displayName, systemImage: role.icon)
                }
            }
        }
    }

    private func populate() {
        guard let user else { return }
        personalEmail = user.personal_email
        firstName = user.first_name
        lastName = user.last_name
        jobTitle = user.job_title ?? ""
        phoneNumber = user.phone_number ?? ""
        contractType = user.contract_type ?? ContractType.employee.rawValue
        selectedRoles = Set(user.roles)
        professionalEmail = user.professional_email ?? ""
        isActive = user.is_active
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        switch mode {
        case .create:
            let payload = TenantUserCreateDTO(
                personal_email: personalEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                first_name: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                last_name: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                job_title: emptyToNil(jobTitle),
                phone_number: emptyToNil(phoneNumber),
                contract_type: contractType,
                roles: Array(selectedRoles).sorted(),
                send_invite: sendInvite
            )
            guard let response = await apiService.createTenantUser(payload, targetTenantId: targetTenantId) else {
                message = apiService.lastSyncError ?? "Creazione non riuscita"
                return
            }
            onDone(response.invite_status == "sent" ? "Utente creato e invito inviato" : "Utente creato: \(response.invite_status)")
            dismiss()

        case .edit:
            guard let user else { return }
            let payload = TenantUserUpdateDTO(
                first_name: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                last_name: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                job_title: emptyToNil(jobTitle),
                phone_number: emptyToNil(phoneNumber),
                contract_type: contractType,
                roles: Array(selectedRoles).sorted(),
                is_active: isActive,
                professional_email: emptyToNil(professionalEmail)
            )
            guard await apiService.updateTenantUser(user.id, payload: payload, targetTenantId: targetTenantId) != nil else {
                message = apiService.lastSyncError ?? "Salvataggio non riuscito"
                return
            }
            onDone("Utente aggiornato")
            dismiss()
        }
    }

    private func resendInvite(_ userId: String) async {
        isSaving = true
        defer { isSaving = false }
        guard let response = await apiService.resendTenantUserInvite(userId, targetTenantId: targetTenantId) else {
            message = apiService.lastSyncError ?? "Invio non riuscito"
            return
        }
        message = response.invite_status == "sent" ? "Invito inviato" : "Invito: \(response.invite_status)"
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
