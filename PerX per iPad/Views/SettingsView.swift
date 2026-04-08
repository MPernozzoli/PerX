//
//  SettingsView.swift
//  PerX per iPad
//
//  Impostazioni app iPad: account, hub, sync, cache.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var session: SessionCoordinator
    @StateObject private var hubClient = HubAPIClient.shared
    @StateObject private var accountManager = AccountManager.shared
    @State private var showingLogoutConfirm = false
    @State private var hubURL = HubAPIClient.shared.hubBaseURL
    @State private var cloudAPIEmail = HubAPIClient.shared.cloudAPIEmail
    @State private var cloudAPIPassword = ""
    @State private var isCheckingHub = false
    @State private var hubCheckResult: String?
    @State private var isCheckingCloud = false
    @State private var cloudCheckResult: String?
    @State private var showingSetPasscode = false
    @State private var showingRemovePasscode = false
    
    private var currentAccount: AccountManager.SavedAccount? {
        guard let email = session.currentUserEmail else { return nil }
        return accountManager.savedAccounts.first { $0.email == email }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Account
                Section("Account") {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title)
                            .foregroundColor(.accentColor)
                        
                        VStack(alignment: .leading) {
                            Text(session.currentUserName ?? "Utente")
                                .font(.headline)
                            
                            Text(session.currentUserEmail ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if hubClient.isCloudConfigured {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Profilo utente sincronizzato tramite backend cloud", systemImage: "person.crop.circle.badge.checkmark")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let profile = session.currentCloudProfile {
                                Text("Ruoli: \(profile.roles.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("Firma email: \((profile.email_signature_html?.isEmpty == false || profile.email_signature_text?.isEmpty == false) ? "configurata" : "non configurata")")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Button(role: .destructive) {
                        showingLogoutConfirm = true
                    } label: {
                        Label("Disconnetti", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                
                // Hub Configuration
                Section("Hub Server") {
                    LabeledContent("Endpoint") {
                        Text(hubURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Non configurato" : hubURL)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    
                    HStack {
                        Circle()
                            .fill(hubClient.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        
                        Text(hubClient.isConnected ? "Connesso" : "Non connesso")
                        
                        Spacer()
                        
                        Button {
                            Task { await checkHubConnection() }
                        } label: {
                            if isCheckingHub {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("Testa")
                            }
                        }
                        .disabled(hubURL.isEmpty || isCheckingHub)
                    }
                    
                    if let result = hubCheckResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(hubClient.isConnected ? .green : .red)
                    }
                }

                Section("Cloud API") {
                    LabeledContent("Endpoint") {
                        Text(HubAPIClient.fixedCloudAPIBaseURL)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    TextField("Email backend", text: $cloudAPIEmail)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: cloudAPIEmail) { newValue in
                            hubClient.cloudAPIEmail = newValue.lowercased()
                        }

                    SecureField("Password backend", text: $cloudAPIPassword)

                    HStack {
                        Button("Salva credenziali") {
                            hubClient.saveCloudPassword(cloudAPIPassword)
                            let normalizedEmail = cloudAPIEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            if !normalizedEmail.isEmpty {
                                accountManager.savePassword(cloudAPIPassword, for: normalizedEmail)
                                if session.currentUserEmail == normalizedEmail {
                                    accountManager.saveAccount(
                                        email: normalizedEmail,
                                        displayName: session.currentUserName ?? normalizedEmail,
                                        password: cloudAPIPassword
                                    )
                                }
                            }
                            cloudCheckResult = "Credenziali backend salvate"
                        }
                        .disabled(cloudAPIPassword.isEmpty)

                        Spacer()

                        Button {
                            Task { await checkCloudConnection() }
                        } label: {
                            if isCheckingCloud {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("Testa login")
                            }
                        }
                        .disabled(cloudAPIEmail.isEmpty || cloudAPIPassword.isEmpty || isCheckingCloud)
                    }

                    if let result = cloudCheckResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.hasPrefix("✓") ? .green : .secondary)
                    }
                }
                
                // Sync Status
                Section("Sincronizzazione") {
                    HStack {
                        Circle()
                            .fill(session.cloudKitSyncService != nil ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        
                        Text("Dati")
                        
                        Spacer()
                        
                        Text(session.cloudKitSyncService?.dataSource.rawValue ?? "Non attivo")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let lastSync = session.cloudKitSyncService?.lastSyncAt {
                        HStack {
                            Text("Ultimo sync")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    syncStatusRow(
                        title: "Chat",
                        isActive: session.chatService != nil,
                        lastSync: nil
                    )
                    
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        
                        Text("Outbox")
                        
                        Spacer()
                        
                        Text("\(session.outboxService.pendingRequests.count) in coda")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        Task {
                            await session.cloudKitSyncService?.syncNow()
                            await session.chatService?.fetchRooms()
                        }
                    } label: {
                        Label("Sincronizza ora", systemImage: "arrow.clockwise")
                    }
                }
                
                // Sicurezza
                Section("Sicurezza") {
                    passcodeRow
                }
                
                // Cache
                Section("Cache") {
                    cacheStatusRow
                    
                    Button(role: .destructive) {
                        Task {
                            await session.folderCacheService?.purgeExpiredFolders()
                        }
                    } label: {
                        Label("Pulisci cache scadute", systemImage: "trash")
                    }
                }
                
                // Info
                Section("Informazioni") {
                    LabeledContent("Versione", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    LabeledContent("Piattaforma", value: "iPad")
                }
                
                // Note
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Architettura Hub-first", systemImage: "server.rack")
                            .font(.headline)
                        
                        Text("Questa versione iPad comunica con l'Hub centrale per email, WhatsApp e dati sinistri. L'Hub orchestra tutte le operazioni.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Impostazioni")
            .confirmationDialog("Vuoi disconnetterti?", isPresented: $showingLogoutConfirm, titleVisibility: .visible) {
                Button("Disconnetti", role: .destructive) {
                    Task {
                        await session.signOut()
                    }
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Tutti i dati locali verranno rimossi. Le cartelle scaricate non ancora scadute verranno eliminate.")
            }
        }
    }
    
    private func checkHubConnection() async {
        isCheckingHub = true
        hubCheckResult = nil
        
        do {
            let health = try await hubClient.checkHealth()
            hubCheckResult = "✓ \(health.status) - v\(health.version)"
        } catch {
            hubCheckResult = "✗ \(error.localizedDescription)"
        }
        
        isCheckingHub = false
    }

    private func checkCloudConnection() async {
        isCheckingCloud = true
        cloudCheckResult = nil
        hubClient.cloudAPIEmail = cloudAPIEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        hubClient.saveCloudPassword(cloudAPIPassword)

        do {
            _ = try await hubClient.cloudLogin(forceRefresh: true)
            cloudCheckResult = "✓ Login backend riuscito"
        } catch {
            cloudCheckResult = "Backend non raggiungibile: \(error.localizedDescription)"
        }

        isCheckingCloud = false
    }
    
    @ViewBuilder
    private func syncStatusRow(title: String, isActive: Bool, lastSync: Date?) -> some View {
        HStack {
            Circle()
                .fill(isActive ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(title)
            
            Spacer()
            
            if isActive {
                if let lastSync = lastSync {
                    Text(lastSync, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Attivo")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else {
                Text("Non attivo")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var cacheStatusRow: some View {
        let cachedCount = session.folderCacheService?.cachedFolders.count ?? 0
        let expiredCount = session.folderCacheService?.cachedFolders.values.filter { $0.isExpired }.count ?? 0
        
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Cartelle in cache")
                Spacer()
                Text("\(cachedCount)")
                    .foregroundColor(.secondary)
            }
            
            if expiredCount > 0 {
                HStack {
                    Text("Scadute")
                    Spacer()
                    Text("\(expiredCount)")
                        .foregroundColor(.orange)
                }
                .font(.caption)
            }
        }
    }
    
    @ViewBuilder
    private var passcodeRow: some View {
        let hasPasscode = currentAccount?.hasPasscode ?? false
        
        HStack {
            Label(
                hasPasscode ? "Codice di accesso attivo" : "Nessun codice",
                systemImage: hasPasscode ? "lock.fill" : "lock.open"
            )
            
            Spacer()
            
            if hasPasscode {
                Button("Rimuovi") {
                    showingRemovePasscode = true
                }
                .foregroundColor(.red)
            } else {
                Button("Imposta") {
                    showingSetPasscode = true
                }
            }
        }
        .sheet(isPresented: $showingSetPasscode) {
            SetPasscodeView(email: session.currentUserEmail ?? "")
        }
        .alert("Rimuovere codice?", isPresented: $showingRemovePasscode) {
            Button("Rimuovi", role: .destructive) {
                if let email = session.currentUserEmail {
                    accountManager.removePasscode(for: email)
                }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("L'account non sarà più protetto da codice")
        }
    }
}

// MARK: - Set Passcode View

struct SetPasscodeView: View {
    let email: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var step: PasscodeStep = .enter
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool
    
    enum PasscodeStep {
        case enter
        case confirm
    }
    
    private let passcodeLength = 4
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                VStack(spacing: 32) {
                    Spacer()
                    
                    Image(systemName: step == .enter ? "lock" : "lock.badge.clock")
                        .font(.system(size: 50))
                        .foregroundColor(.accentColor)
                    
                    Text(step == .enter ? "Inserisci un codice" : "Conferma il codice")
                        .font(.title2)
                    
                    // Passcode dots
                    HStack(spacing: 20) {
                        ForEach(0..<passcodeLength, id: \.self) { index in
                            let currentCode = step == .enter ? passcode : confirmPasscode
                            Circle()
                                .fill(index < currentCode.count ? Color.accentColor : Color.gray.opacity(0.3))
                                .frame(width: 20, height: 20)
                        }
                    }
                    
                    // Hidden text field
                    TextField("", text: step == .enter ? $passcode : $confirmPasscode)
                        .keyboardType(.numberPad)
                        .focused($isFocused)
                        .opacity(0)
                        .frame(width: 1, height: 1)
                        .onChange(of: passcode) { newValue in
                            handleInput(newValue, isConfirm: false)
                        }
                        .onChange(of: confirmPasscode) { newValue in
                            handleInput(newValue, isConfirm: true)
                        }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .onAppear {
                isFocused = true
            }
            .navigationTitle("Codice di accesso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func handleInput(_ value: String, isConfirm: Bool) {
        // Limita a 4 cifre
        if isConfirm {
            if value.count > passcodeLength {
                confirmPasscode = String(value.prefix(passcodeLength))
            }
        } else {
            if value.count > passcodeLength {
                passcode = String(value.prefix(passcodeLength))
            }
        }
        
        // Passa alla conferma
        if !isConfirm && passcode.count == passcodeLength {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                step = .confirm
                isFocused = true
            }
        }
        
        // Verifica conferma
        if isConfirm && confirmPasscode.count == passcodeLength {
            if confirmPasscode == passcode {
                AccountManager.shared.setPasscode(passcode, for: email)
                dismiss()
            } else {
                errorMessage = "I codici non corrispondono"
                confirmPasscode = ""
                
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(SessionCoordinator.shared)
}
