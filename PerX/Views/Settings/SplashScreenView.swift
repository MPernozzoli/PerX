import SwiftUI

struct SplashScreenView: View {
    @ObservedObject private var authService = GoogleAuthService.shared
    @StateObject private var accountManager = AccountManager.shared
    @ObservedObject private var hubConfig = HubConfigService.shared

    @State private var isAnimating = false
    @State private var isCheckingAuth = true
    @State private var isLoggingIn = false
    @State private var selectedAccount: AccountManager.SavedAccount?
    @State private var showingManualLogin = false
    @State private var errorMessage: String?

    private let gridColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 20)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.10, blue: 0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                headerView

                if isCheckingAuth {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Verifico sessione backend...")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 40)
                } else {
                    contentView
                }
            }
            .padding(32)
        }
        .sheet(isPresented: $showingManualLogin) {
            MacManualLoginView { success in
                if success {
                    showingManualLogin = false
                }
            }
        }
        .alert("Errore login", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                isAnimating = true
            }
        }
        .task(id: "authCheck") {
            let result = await authService.checkAuthenticationState()
            authService.applyAuthResult(result)
            Task { @MainActor in
                isCheckingAuth = false
            }
        }
    }

    private var headerView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(isAnimating ? 0.95 : 0.3))
                .scaleEffect(isAnimating ? 1 : 0.85)

            Text("PerX")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Accedi con un account demo o con credenziali backend PerX")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 24) {
            if !hubConfig.cloudAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(hubConfig.cloudAPIBaseURL)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08), in: Capsule())
            }

            if accountManager.savedAccounts.isEmpty {
                Button("Aggiungi account backend") {
                    showingManualLogin = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 20) {
                    ForEach(accountManager.savedAccounts) { account in
                        MacAccountTileView(account: account) {
                            login(with: account)
                        }
                    }

                    Button {
                        showingManualLogin = true
                    } label: {
                        VStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                                .frame(height: 146)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: 30, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.7))
                                }

                            Text("Aggiungi account")
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 760)
            }

            if isLoggingIn, let selectedAccount {
                VStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Accesso in corso per \(selectedAccount.email)...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Button("Login manuale") {
                showingManualLogin = true
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.white)
        }
    }

    private func login(with account: AccountManager.SavedAccount) {
        guard !isLoggingIn else { return }
        guard let password = AccountManager.shared.getPassword(for: account.email), !password.isEmpty else {
            errorMessage = "Credenziali salvate mancanti per \(account.email)."
            return
        }

        selectedAccount = account
        isLoggingIn = true
        errorMessage = nil

        Task {
            do {
                try await authService.signIn(email: account.email, password: password)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                isLoggingIn = false
            }
        }
    }
}

private struct MacAccountTileView: View {
    let account: AccountManager.SavedAccount
    let onSelect: () -> Void

    private var avatarColor: Color {
        switch account.colorIndex % 6 {
        case 0: return .blue
        case 1: return .green
        case 2: return .orange
        case 3: return .purple
        case 4: return .red
        default: return .teal
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.white.opacity(0.08))
                        .frame(height: 146)

                    VStack(spacing: 12) {
                        Circle()
                            .fill(avatarColor.gradient)
                            .frame(width: 74, height: 74)
                            .overlay {
                                Text(account.avatarInitials)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                            }

                        Text(account.displayName)
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(account.email)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MacManualLoginView: View {
    let onComplete: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var backendURL = HubConfigService.shared.cloudAPIBaseURL
    @State private var email = HubConfigService.shared.cloudAPIEmail
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Login backend")
                .font(.title2.bold())

            Text("Usa le stesse credenziali backend disponibili su iPad. Gli account demo vengono salvati per i login successivi.")
                .foregroundStyle(.secondary)

            TextField("URL backend", text: $backendURL)
                .textFieldStyle(.roundedBorder)

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    performLogin()
                } label: {
                    if isLoggingIn {
                        ProgressView()
                    } else {
                        Text("Accedi")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    isLoggingIn ||
                    email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func performLogin() {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedURL = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)

        isLoggingIn = true
        errorMessage = nil

        Task {
            do {
                try await GoogleAuthService.shared.signIn(
                    email: normalizedEmail,
                    password: normalizedPassword,
                    baseURL: normalizedURL
                )
                await MainActor.run {
                    onComplete(true)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    onComplete(false)
                }
            }

            await MainActor.run {
                isLoggingIn = false
            }
        }
    }
}
